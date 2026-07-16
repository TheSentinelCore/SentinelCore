//! Core pathfinding pipeline: polygon finding, A*, island recovery, post-processing.

use detour::filter::QueryFilter;
use detour::mesh::NavMesh;
use detour::query::NavMeshQuery;
use detour::types::{PolyRef, Vec3};

use crate::error::AppError;

use super::filter::{
    HEIGHT_EXTENTS, ISLAND_RETRY_OFFSETS, MAX_PATH_POLYS, MAX_STRAIGHT_PATH, MAX_Z_SNAP_DELTA,
    NAV_FLAG_GROUND, NAV_FLAG_WATER, SEARCH_EXTENTS, SEARCH_TIERS,
};
use super::post_process::calculate_path_distance;
use super::string_pull::{
    string_pull_path, MAX_HEADING_CHANGE, MAX_STRING_PULL_DEVIATION,
};
use super::wall_clearance::apply_wall_clearance;
use super::{PathOptions, PathResult};

/// Find the nearest polygon using tiered 3D-extent search with water-aware selection.
///
/// Tries tight extents first to pick the correct floor in multi-level
/// structures (towers, bridges, stacked rooms). Falls back to broader extents
/// for positions on cliffs, steep terrain, or far from navmesh.
///
/// Water-aware: if a ground polygon is found but a water polygon exists above it
/// (lake/ocean scenario), prefers the water polygon so paths route along the
/// water surface instead of the lake bottom.
pub fn find_poly_tiered(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    pos: Vec3,
    filter: &QueryFilter,
    z_override: Option<f32>,
) -> Result<(PolyRef, Vec3), AppError> {
    // If caller provides explicit z_extent, use it directly
    if let Some(z) = z_override {
        let extents = Vec3::new(SEARCH_EXTENTS.x, SEARCH_EXTENTS.y, z);
        let result = query
            .find_nearest_poly(pos, extents, filter)
            .map_err(|_| AppError::PathfindingFailed("Position not on navmesh".into()))?;
        return maybe_prefer_water(query, mesh, pos, result);
    }

    // Tiered search: tight Z extents first for correct floor selection.
    // Reject results where snapped Z is too far from requested Z (wrong floor).
    let mut best_fallback: Option<(PolyRef, Vec3)> = None;

    for (i, &(x_ext, y_ext, z_ext)) in SEARCH_TIERS.iter().enumerate() {
        let extents = Vec3::new(x_ext, y_ext, z_ext);
        if let Ok(result) = query.find_nearest_poly(pos, extents, filter) {
            let z_delta = (result.1.z - pos.z).abs();
            let is_last_tier = i == SEARCH_TIERS.len() - 1;

            if is_last_tier || z_delta <= MAX_Z_SNAP_DELTA {
                return maybe_prefer_water(query, mesh, pos, result);
            }
            // Z too far from requested — save as fallback and try next tier
            if best_fallback.is_none() {
                best_fallback = Some(result);
            }
        }
    }

    // No tier passed Z check — use best available
    if let Some(result) = best_fallback {
        return maybe_prefer_water(query, mesh, pos, result);
    }

    Err(AppError::PathfindingFailed("Position not on navmesh".into()))
}

/// If the found polygon is ground and a water polygon exists above it,
/// prefer the water polygon (lake/ocean surface routing).
fn maybe_prefer_water(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    pos: Vec3,
    (poly_ref, snapped): (PolyRef, Vec3),
) -> Result<(PolyRef, Vec3), AppError> {
    let flags = mesh.get_poly_flags(poly_ref).unwrap_or(0);
    if flags & NAV_FLAG_GROUND == 0 {
        // Not ground — keep as-is (already water, steep, etc.)
        return Ok((poly_ref, snapped));
    }

    // Found ground — check if water polygon exists above (lake scenario)
    let water_filter = match QueryFilter::water_only() {
        Ok(f) => f,
        Err(_) => return Ok((poly_ref, snapped)),
    };

    // Search with generous Z to find water surface above ground
    let water_extents = Vec3::new(6.0, 6.0, 50.0);
    if let Ok((w_ref, w_snapped)) = query.find_nearest_poly(pos, water_extents, &water_filter) {
        let w_flags = mesh.get_poly_flags(w_ref).unwrap_or(0);
        // Water polygon must be above the ground polygon (lake surface > lake bottom)
        if w_flags & NAV_FLAG_WATER != 0 && w_snapped.z > snapped.z + 2.0 {
            return Ok((w_ref, w_snapped));
        }
    }

    Ok((poly_ref, snapped))
}

/// Execute pathfinding returning raw waypoints (find + straight path only).
///
/// No string-pulling, no densification, no wall_clearance. Used by multi-leg
/// endpoints that need to concatenate legs before applying post-processing
/// to the full path.
pub fn execute_pathfind_raw(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &PathOptions,
) -> Result<PathResult, AppError> {
    // Find nearest polygons to start and end positions (tiered 3D fallback for multi-floor safety)
    // Water-aware: prefers water polygon over ground when position is in a lake.
    let (start_ref, start_nearest) =
        find_poly_tiered(query, mesh, start_pos, filter, options.z_extent)?;
    let (end_ref, end_nearest) =
        find_poly_tiered(query, mesh, end_pos, filter, options.z_extent)?;

    // Find polygon corridor from start to end
    let find_result = query
        .find_path(
            start_ref,
            end_ref,
            start_nearest,
            end_nearest,
            filter,
            MAX_PATH_POLYS,
        )
        .map_err(|_| AppError::PathfindingFailed("No path found".into()))?;

    let mut poly_path = find_result.path;
    let mut is_partial = find_result.is_partial;
    let mut was_out_of_nodes = find_result.out_of_nodes;

    // If partial, start may be on a disconnected navmesh island (caused by GO injection
    // fragmenting the mesh). Try nearby positions to find a polygon on the main connected mesh.
    let mut effective_start = start_nearest;
    let mut effective_start_ref = start_ref;
    if is_partial {
        for &(dx, dy) in &ISLAND_RETRY_OFFSETS {
            let alt_pos = Vec3::new(start_pos.x + dx, start_pos.y + dy, start_pos.z);
            let Ok((alt_ref, alt_nearest)) =
                find_poly_tiered(query, mesh, alt_pos, filter, options.z_extent)
            else {
                continue;
            };
            if alt_ref == start_ref {
                continue; // Same polygon, skip
            }
            let Ok(alt_result) = query.find_path(
                alt_ref,
                end_ref,
                alt_nearest,
                end_nearest,
                filter,
                MAX_PATH_POLYS,
            ) else {
                continue;
            };
            // Use this result if it's better (full path, or longer partial)
            if !alt_result.is_partial || alt_result.path.len() > poly_path.len() {
                poly_path = alt_result.path;
                is_partial = alt_result.is_partial;
                was_out_of_nodes = alt_result.out_of_nodes;
                effective_start = alt_nearest;
                effective_start_ref = alt_ref;
                if !is_partial {
                    break; // Found full path, stop searching
                }
            }
        }
    }

    // If still partial, the destination may be on a disconnected island or slope-severed region.
    // Try offset end positions.
    let mut effective_end = end_nearest;
    if is_partial {
        for &(dx, dy) in &ISLAND_RETRY_OFFSETS {
            let alt_pos = Vec3::new(end_pos.x + dx, end_pos.y + dy, end_pos.z);
            let Ok((alt_ref, alt_nearest)) =
                find_poly_tiered(query, mesh, alt_pos, filter, options.z_extent)
            else {
                continue;
            };
            if alt_ref == end_ref {
                continue; // Same polygon, skip
            }
            let Ok(alt_result) = query.find_path(
                effective_start_ref,
                alt_ref,
                effective_start,
                alt_nearest,
                filter,
                MAX_PATH_POLYS,
            ) else {
                continue;
            };
            if !alt_result.is_partial || alt_result.path.len() > poly_path.len() {
                poly_path = alt_result.path;
                is_partial = alt_result.is_partial;
                was_out_of_nodes = alt_result.out_of_nodes;
                effective_end = alt_nearest;
                if !is_partial {
                    break;
                }
            }
        }
    }

    // Diagnostic logging for partial paths
    if is_partial {
        if was_out_of_nodes {
            tracing::warn!(
                "Partial path (OUT_OF_NODES): ({:.1},{:.1},{:.1}) -> ({:.1},{:.1},{:.1}), \
                 poly_count={} — consider increasing max_query_nodes",
                start_pos.x, start_pos.y, start_pos.z,
                end_pos.x, end_pos.y, end_pos.z,
                poly_path.len(),
            );
        } else {
            tracing::warn!(
                "Partial path (disconnected): ({:.1},{:.1},{:.1}) -> ({:.1},{:.1},{:.1}), \
                 poly_count={}",
                start_pos.x, start_pos.y, start_pos.z,
                end_pos.x, end_pos.y, end_pos.z,
                poly_path.len(),
            );
        }
    }

    if poly_path.is_empty() {
        return Err(AppError::PathfindingFailed("Empty polygon path".into()));
    }

    // Convert polygon corridor to straight path (raw waypoints only)
    let waypoints = query
        .find_straight_path(effective_start, effective_end, &poly_path, MAX_STRAIGHT_PATH)
        .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

    let distance = calculate_path_distance(&waypoints);

    Ok(PathResult {
        waypoints,
        distance,
        partial: is_partial,
        out_of_nodes: was_out_of_nodes,
    })
}

/// Apply string-pulling + densification + wall_clearance to an existing path.
///
/// Used by multi-leg endpoints after concatenating raw legs, and by
/// `execute_pathfind` for single-leg paths. Ensures consistent post-processing
/// regardless of how the raw waypoints were produced.
pub fn post_process_path(
    waypoints: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
    options: &PathOptions,
) -> Vec<Vec3> {
    let mut result = if options.optimize {
        string_pull_path(
            waypoints,
            query,
            filter,
            options
                .string_pull_deviation
                .unwrap_or(MAX_STRING_PULL_DEVIATION),
            options.string_pull_heading.unwrap_or(MAX_HEADING_CHANGE),
            options.string_pull_wall_dist.unwrap_or(0.6),
        )
    } else {
        waypoints.to_vec()
    };

    use super::post_process::{densify_segments, MAX_SEGMENT_LENGTH};
    result = densify_segments(
        &result,
        query,
        filter,
        options.densify_segment_length.unwrap_or(MAX_SEGMENT_LENGTH),
    );

    if let Some(clearance) = options.wall_clearance {
        if clearance > 0.0 {
            result = apply_wall_clearance(&result, query, filter, clearance);
        }
    }

    result
}

/// Execute the full pathfinding pipeline: find → straight → optimize → densify → wall_clearance.
///
/// This is the core shared function used by single-path endpoints.
pub fn execute_pathfind(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &PathOptions,
) -> Result<PathResult, AppError> {
    let mut result = execute_pathfind_raw(query, mesh, filter, start_pos, end_pos, options)?;
    result.waypoints = post_process_path(&result.waypoints, query, filter, options);
    result.distance = calculate_path_distance(&result.waypoints);
    Ok(result)
}
