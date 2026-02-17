//! Shared pathfinding pipeline used by all path endpoints.
//!
//! Extracts the core find → straight → optimize → smooth → project → validate
//! pipeline so it can be reused by path, path-random, path-multi, path-tsp, etc.

use detour::filter::{
    NAV_AREA_AVOID, NAV_AREA_GROUND, NAV_AREA_GROUND_STEEP, NAV_AREA_MAGMA_SLIME, NAV_AREA_WATER,
    QueryFilter, QueryFilterBuilder,
};
use detour::mesh::NavMesh;
use detour::query::NavMeshQuery;
use detour::types::{PolyRef, Vec3};
use path_smoothing::{SmoothingAlgorithm, SmoothingConfig};

use crate::error::AppError;

/// Default area costs for WoW pathfinding.
pub const DEFAULT_GROUND_COST: f32 = 1.0;
pub const DEFAULT_WATER_COST: f32 = 1.5;
pub const DEFAULT_LAVA_COST: f32 = 100.0;

/// Search extents for general polygon searches (recovery, avoidance, etc.).
/// Reduced from 50/50/500 to match reference implementations.
pub const SEARCH_EXTENTS: Vec3 = Vec3 {
    x: 50.0,
    y: 50.0,
    z: 50.0,
};

/// Height extents for waypoint surface projection (smaller for accuracy).
/// Tight z keeps wall-clearance, surface projection, and validation on the correct floor
/// in multi-level structures (towers, ramps, bridges).
pub const HEIGHT_EXTENTS: Vec3 = Vec3 {
    x: 5.0,
    y: 5.0,
    z: 5.0,
};

/// Maximum polygons in the path corridor.
pub const MAX_PATH_POLYS: usize = 1024;

/// Maximum waypoints in the straight path.
pub const MAX_STRAIGHT_PATH: usize = 2048;

/// Tiered 3D search extents (x, y, z) for polygon search.
/// Tight first for correct floor selection, broader as fallback.
/// Reference: CMaNGOS uses 5/10, AmeisenNavigation uses 6, BloogBot uses 3.
/// Previous Sentinel Navigation Server XY=50 was 10x larger than all references, causing water/edge issues.
pub(crate) const SEARCH_TIERS: [(f32, f32, f32); 3] = [
    (6.0, 6.0, 6.0),    // Tight — matches AmeisenNavigation
    (10.0, 10.0, 10.0),  // Medium — matches CMaNGOS far search
    (50.0, 50.0, 50.0),  // Fallback — imprecise coordinates
];

/// XY offsets (yards) to try when the start poly appears to be on a disconnected island.
/// Cardinal + diagonal directions at ~3 yards — enough to step off most GO-induced islands.
const ISLAND_RETRY_OFFSETS: [(f32, f32); 8] = [
    (3.0, 0.0),
    (-3.0, 0.0),
    (0.0, 3.0),
    (0.0, -3.0),
    (2.0, 2.0),
    (-2.0, 2.0),
    (2.0, -2.0),
    (-2.0, -2.0),
];

/// NAV_GROUND flag (1 << (11-11) = 0x01).
const NAV_FLAG_GROUND: u16 = 0x01;
/// NAV_WATER flag (1 << (11-9) = 0x04).
const NAV_FLAG_WATER: u16 = 0x04;

/// Options controlling how a path is computed.
#[derive(Debug, Clone, Default)]
pub struct PathOptions {
    /// Smoothing algorithm name.
    pub smoothing: Option<String>,
    /// Enable string-pulling optimization.
    pub optimize: bool,
    /// Ground area cost multiplier.
    pub filter_ground: Option<f32>,
    /// Water area cost multiplier.
    pub filter_water: Option<f32>,
    /// Lava area cost multiplier.
    pub filter_lava: Option<f32>,
    /// Chaikin iterations.
    pub smooth_iterations: Option<u32>,
    /// Catmull-Rom/Bezier samples per segment.
    pub smooth_samples: Option<u32>,
    /// Chaikin corner-cut ratio.
    pub smooth_ratio: Option<f32>,
    /// Minimum corner angle to smooth.
    pub min_corner_angle: Option<f32>,
    /// Preserve original waypoints through smoothing.
    pub keep_originals: Option<bool>,
    /// Custom Z search extent override. When set, skips tiered fallback
    /// and uses this value directly. Useful for indoor/multi-floor scenarios.
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled).
    /// Pushes waypoints away from nearby walls using Detour's findDistanceToWall.
    pub wall_clearance: Option<f32>,
}

/// Result of a pathfinding computation.
pub struct PathResult {
    pub waypoints: Vec<Vec3>,
    pub distance: f32,
    pub partial: bool,
}

/// Check if any custom filter parameters are provided.
pub fn has_custom_filter(
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
) -> bool {
    filter_ground.is_some() || filter_water.is_some() || filter_lava.is_some()
}

/// Create a custom QueryFilter with specified area costs.
pub fn create_custom_filter(
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
) -> Result<QueryFilter, AppError> {
    let ground = filter_ground.unwrap_or(DEFAULT_GROUND_COST);
    let water = filter_water.unwrap_or(DEFAULT_WATER_COST);
    let lava = filter_lava.unwrap_or(DEFAULT_LAVA_COST);

    QueryFilterBuilder::new()
        .area_cost(NAV_AREA_GROUND, ground)        // area 11: ground
        .area_cost(NAV_AREA_GROUND_STEEP, ground)  // area 10: steep slopes (same cost as ground)
        .area_cost(NAV_AREA_WATER, water)           // area 9: water
        .area_cost(NAV_AREA_MAGMA_SLIME, lava)      // area 8: magma/slime
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to create filter: {}", e)))
}

/// Create a SmoothingConfig from optional parameters.
pub fn create_smoothing_config(
    smooth_iterations: Option<u32>,
    smooth_samples: Option<u32>,
    smooth_ratio: Option<f32>,
    min_corner_angle: Option<f32>,
    keep_originals: Option<bool>,
) -> SmoothingConfig {
    let mut config = SmoothingConfig::new();
    if let Some(iterations) = smooth_iterations {
        config = config.with_chaikin_iterations(iterations);
    }
    if let Some(samples) = smooth_samples {
        config = config.with_catmull_rom_samples(samples);
        config = config.with_bezier_samples(samples);
    }
    if let Some(ratio) = smooth_ratio {
        config = config.with_chaikin_ratio(ratio);
    }
    if let Some(angle) = min_corner_angle {
        config = config.with_min_corner_angle(angle);
    }
    if let Some(keep) = keep_originals {
        config = config.with_keep_originals(keep);
    }
    config
}

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

    // Tiered search: tight 3D extents first for correct floor/position selection
    for &(x_ext, y_ext, z_ext) in &SEARCH_TIERS {
        let extents = Vec3::new(x_ext, y_ext, z_ext);
        if let Ok(result) = query.find_nearest_poly(pos, extents, filter) {
            return maybe_prefer_water(query, mesh, pos, result);
        }
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

/// Execute the full pathfinding pipeline: find → straight → optimize → smooth → project → validate.
///
/// This is the core shared function used by all pathfinding endpoints.
pub fn execute_pathfind(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &PathOptions,
) -> Result<PathResult, AppError> {
    // Find nearest polygons to start and end positions (tiered 3D fallback for multi-floor safety)
    // Water-aware: prefers water polygon over ground when position is in a lake.
    let (start_ref, start_nearest) = find_poly_tiered(query, mesh, start_pos, filter, options.z_extent)?;
    let (end_ref, end_nearest) = find_poly_tiered(query, mesh, end_pos, filter, options.z_extent)?;

    // Find polygon corridor from start to end
    let (mut poly_path, mut is_partial) = query
        .find_path(
            start_ref,
            end_ref,
            start_nearest,
            end_nearest,
            filter,
            MAX_PATH_POLYS,
        )
        .map_err(|_| AppError::PathfindingFailed("No path found".into()))?;

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
            let Ok((alt_path, alt_partial)) = query.find_path(
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
            if !alt_partial || alt_path.len() > poly_path.len() {
                poly_path = alt_path;
                is_partial = alt_partial;
                effective_start = alt_nearest;
                effective_start_ref = alt_ref;
                if !alt_partial {
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
            let Ok((alt_path, alt_partial)) = query.find_path(
                effective_start_ref,
                alt_ref,
                effective_start,
                alt_nearest,
                filter,
                MAX_PATH_POLYS,
            ) else {
                continue;
            };
            if !alt_partial || alt_path.len() > poly_path.len() {
                poly_path = alt_path;
                is_partial = alt_partial;
                effective_end = alt_nearest;
                if !alt_partial {
                    break;
                }
            }
        }
    }

    if poly_path.is_empty() {
        return Err(AppError::PathfindingFailed("Empty polygon path".into()));
    }

    // Convert polygon corridor to straight path (waypoints)
    let mut waypoints = query
        .find_straight_path(effective_start, effective_end, &poly_path, MAX_STRAIGHT_PATH)
        .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

    // Apply string-pulling optimization if requested
    if options.optimize {
        waypoints = string_pull_path(&waypoints, query, filter);
    }

    // Densify long segments — insert midpoints projected to navmesh surface.
    // On spiral ramps, this snaps chord midpoints onto the actual ramp arc.
    waypoints = densify_segments(&waypoints, query, filter);

    // Store original waypoints before smoothing (for corner validation)
    let original_waypoints = waypoints.clone();

    // Apply smoothing if requested
    let smoothing =
        SmoothingAlgorithm::from_str(options.smoothing.as_deref().unwrap_or("none"));
    let smoothing_config = create_smoothing_config(
        options.smooth_iterations,
        options.smooth_samples,
        options.smooth_ratio,
        options.min_corner_angle,
        options.keep_originals,
    );
    let mut waypoints = smoothing.smooth_with_config(&waypoints, &smoothing_config);

    // Project smoothed waypoints to navmesh surface for correct Z heights
    project_waypoints_to_surface(&mut waypoints, query, filter);

    // Validate smoothed path doesn't cut through walls at corners
    let mut waypoints = validate_smoothed_path(&waypoints, &original_waypoints, query, filter);

    // Apply wall clearance LAST — after validation, so validation can't undo the push
    // by inserting pre-clearance original waypoints.
    if let Some(clearance) = options.wall_clearance {
        if clearance > 0.0 {
            waypoints = apply_wall_clearance(&waypoints, query, filter, clearance);
        }
    }

    // Calculate total path distance
    let distance = calculate_path_distance(&waypoints);

    Ok(PathResult {
        waypoints,
        distance,
        partial: is_partial,
    })
}

/// Max 3D deviation (yards) allowed when string-pulling skips intermediate waypoints.
/// Prevents collapsing ramp/staircase waypoints on vertical terrain.
const MAX_STRING_PULL_DEVIATION: f32 = 1.5;

/// Calculate the maximum perpendicular 3D distance from any intermediate waypoint
/// to the line segment between `waypoints[from]` and `waypoints[to]`.
///
/// Used to prevent string-pulling from collapsing curved or vertical paths
/// (ramps, spiral staircases, switchbacks) where intermediate waypoints
/// deviate significantly from the direct line.
fn max_deviation_from_segment(waypoints: &[Vec3], from: usize, to: usize) -> f32 {
    if to <= from + 1 {
        return 0.0;
    }

    let a = waypoints[from];
    let b = waypoints[to];
    let ab_x = b.x - a.x;
    let ab_y = b.y - a.y;
    let ab_z = b.z - a.z;
    let ab_len_sq = ab_x * ab_x + ab_y * ab_y + ab_z * ab_z;

    // If start and end overlap, return max distance to that point
    if ab_len_sq < 0.0001 {
        let mut max_dev = 0.0f32;
        for wp in &waypoints[(from + 1)..to] {
            max_dev = max_dev.max(wp.distance(&a));
        }
        return max_dev;
    }

    let mut max_dev = 0.0f32;
    for p in &waypoints[(from + 1)..to] {
        let ap_x = p.x - a.x;
        let ap_y = p.y - a.y;
        let ap_z = p.z - a.z;
        let t = ((ap_x * ab_x + ap_y * ab_y + ap_z * ab_z) / ab_len_sq).clamp(0.0, 1.0);
        let dx = p.x - (a.x + t * ab_x);
        let dy = p.y - (a.y + t * ab_y);
        let dz = p.z - (a.z + t * ab_z);
        let dev = (dx * dx + dy * dy + dz * dz).sqrt();
        max_dev = max_dev.max(dev);
    }
    max_dev
}

/// Max cumulative 2D heading change (radians) allowed when string-pulling.
/// Prevents collapsing spiral ramp/switchback waypoints where the walking
/// arc diverges significantly from the straight-line chord.
const MAX_HEADING_CHANGE: f32 = 0.524; // 30 degrees

/// Compute cumulative absolute heading change through waypoints[from..=to].
///
/// Sums the absolute turn angle at each intermediate waypoint. High values
/// indicate curved paths (spiral ramps, switchbacks) where skipping waypoints
/// would create chords that cut through walls.
fn cumulative_heading_change(waypoints: &[Vec3], from: usize, to: usize) -> f32 {
    if to <= from + 1 {
        return 0.0;
    }
    let mut total = 0.0f32;
    for i in (from + 1)..to {
        let prev = &waypoints[i - 1];
        let curr = &waypoints[i];
        let next = &waypoints[i + 1];
        let h1 = (curr.y - prev.y).atan2(curr.x - prev.x);
        let h2 = (next.y - curr.y).atan2(next.x - curr.x);
        let mut delta = (h2 - h1).abs();
        if delta > std::f32::consts::PI {
            delta = 2.0 * std::f32::consts::PI - delta;
        }
        total += delta;
    }
    total
}

/// String-pulling optimization to reduce waypoint count while maintaining a valid path.
///
/// Uses raycast to find the furthest visible waypoint from each position,
/// eliminating intermediate waypoints that have direct line-of-sight.
pub fn string_pull_path(
    waypoints: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
) -> Vec<Vec3> {
    if waypoints.len() <= 2 {
        return waypoints.to_vec();
    }

    let search_extents = Vec3::new(10.0, 10.0, 10.0);
    let mut result = Vec::with_capacity(waypoints.len());

    // Always include start point
    result.push(waypoints[0]);

    let mut current_idx = 0;

    while current_idx < waypoints.len() - 1 {
        let current_pos = waypoints[current_idx];
        let current_ref = match query.find_nearest_poly(current_pos, search_extents, filter) {
            Ok((poly_ref, _)) => poly_ref,
            Err(_) => {
                current_idx += 1;
                if current_idx < waypoints.len() {
                    result.push(waypoints[current_idx]);
                }
                continue;
            }
        };

        let mut furthest_visible = current_idx + 1;

        for target_idx in (current_idx + 2)..waypoints.len() {
            let target_pos = waypoints[target_idx];
            match query.raycast(current_ref, current_pos, target_pos, filter) {
                Ok((hit_t, _)) => {
                    if hit_t >= 1.0 {
                        let dev = max_deviation_from_segment(waypoints, current_idx, target_idx);
                        if dev > MAX_STRING_PULL_DEVIATION {
                            continue;
                        }
                        // Guard: don't skip if path curves too much in 2D (spiral ramps).
                        // The character walks a straight chord between waypoints, so a
                        // large heading change means the chord cuts through the arc interior.
                        let turn = cumulative_heading_change(waypoints, current_idx, target_idx);
                        if turn > MAX_HEADING_CHANGE {
                            break; // Path curves too much — stop looking further
                        }
                        furthest_visible = target_idx;
                    }
                }
                Err(_) => {
                    break;
                }
            }
        }

        result.push(waypoints[furthest_visible]);
        current_idx = furthest_visible;
    }

    result
}

/// Push waypoints away from nearby walls/obstacles to maintain minimum clearance.
///
/// Uses segment sampling to detect wall proximity along the path between waypoints,
/// not just at waypoint positions. This handles the common case where string-pulling
/// reduces a doorway path to just 2 waypoints with a straight line that clips corners.
///
/// For each segment A→B, samples points at `clearance`-yard intervals. Where a sample
/// is closer to a wall than `clearance`, an offset waypoint is inserted. Existing
/// intermediate waypoints are also offset if needed.
///
/// Start and end waypoints are preserved exactly (player position and destination).
pub fn apply_wall_clearance(
    waypoints: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
    clearance: f32,
) -> Vec<Vec3> {
    if waypoints.len() < 2 || clearance <= 0.0 {
        return waypoints.to_vec();
    }

    let max_radius = clearance * 2.0;
    let snap_extents = Vec3::new(clearance * 0.5, clearance * 0.5, 5.0);
    let mut result = Vec::with_capacity(waypoints.len() * 2);

    // Always keep start point as-is
    result.push(waypoints[0]);

    for seg_idx in 0..waypoints.len() - 1 {
        let a = waypoints[seg_idx];
        let b = waypoints[seg_idx + 1];

        // Sample points along this segment to detect wall proximity
        let seg_len = a.distance_2d(&b);
        if seg_len >= 0.01 {
            let base_spacing = clearance.max(1.0);

            // Collect sample positions (denser near endpoints for doorway corners)
            let mut sample_ts: Vec<f32> = Vec::new();

            // Dense sampling zone = clearance yards from each end, up to 30% of segment
            let dense_zone = (clearance / seg_len).min(0.3);
            let dense_spacing = 0.5 / seg_len; // 0.5 yard steps in dense zones
            let normal_spacing = base_spacing / seg_len;

            // Dense sampling in first clearance yards
            let mut t = dense_spacing;
            while t < dense_zone && t < 0.5 {
                sample_ts.push(t);
                t += dense_spacing;
            }

            // Normal sampling in middle
            t = dense_zone.max(normal_spacing);
            while t < 1.0 - dense_zone {
                sample_ts.push(t);
                t += normal_spacing;
            }

            // Dense sampling in last clearance yards
            t = (1.0 - dense_zone).max(0.5);
            while t < 1.0 - dense_spacing * 0.5 {
                sample_ts.push(t);
                t += dense_spacing;
            }

            for t in sample_ts {
                let sample = Vec3::new(
                    a.x + (b.x - a.x) * t,
                    a.y + (b.y - a.y) * t,
                    a.z + (b.z - a.z) * t,
                );

                // Snap sample to navmesh surface — on ramps, linear interpolation
                // between waypoints drifts off the polygon surface, making
                // find_distance_to_wall inaccurate.
                let (poly_ref, on_surface) =
                    match query.find_nearest_poly(sample, HEIGHT_EXTENTS, filter) {
                        Ok(result) => result,
                        Err(_) => continue,
                    };

                if let Ok((hit_dist, _hit_pos, hit_normal)) =
                    query.find_distance_to_wall(poly_ref, on_surface, max_radius, filter)
                {
                    if hit_dist < clearance {
                        // Segment passes too close to a wall — insert offset waypoint
                        let push_dist = clearance - hit_dist;
                        let candidate = Vec3::new(
                            on_surface.x + hit_normal.x * push_dist,
                            on_surface.y + hit_normal.y * push_dist,
                            on_surface.z,
                        );

                        if let Ok((snap_ref, snapped)) =
                            query.find_nearest_poly(candidate, snap_extents, filter)
                        {
                            if snapped.distance_2d(&candidate) < clearance {
                                // Verify pushed point is reachable (no wall in either direction)
                                let forward_ok = query
                                    .raycast(poly_ref, on_surface, snapped, filter)
                                    .map(|(t, _)| t >= 1.0)
                                    .unwrap_or(false);

                                // Also check reverse direction
                                let reverse_ok = if forward_ok {
                                    query
                                        .raycast(snap_ref, snapped, on_surface, filter)
                                        .map(|(t, _)| t >= 1.0)
                                        .unwrap_or(false)
                                } else {
                                    false
                                };

                                if forward_ok && reverse_ok {
                                    result.push(snapped);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Push the segment endpoint
        if seg_idx + 1 < waypoints.len() - 1 {
            // Intermediate waypoint — also offset if too close to a wall
            let pushed =
                try_push_from_wall(b, query, filter, clearance, max_radius, &snap_extents);
            result.push(pushed);
        }
    }

    // Always keep end point as-is
    result.push(*waypoints.last().unwrap());

    result
}

/// Try to push a single waypoint away from the nearest wall.
/// Returns the original waypoint if the push fails or is unnecessary.
fn try_push_from_wall(
    wp: Vec3,
    query: &NavMeshQuery,
    filter: &QueryFilter,
    clearance: f32,
    max_radius: f32,
    snap_extents: &Vec3,
) -> Vec3 {
    // Snap to surface first — waypoint may be slightly off-polygon on ramps
    let (poly_ref, on_surface) = match query.find_nearest_poly(wp, HEIGHT_EXTENTS, filter) {
        Ok(result) => result,
        Err(_) => return wp,
    };

    match query.find_distance_to_wall(poly_ref, on_surface, max_radius, filter) {
        Ok((hit_dist, _hit_pos, hit_normal)) if hit_dist < clearance => {
            let push_dist = clearance - hit_dist;
            let candidate = Vec3::new(
                on_surface.x + hit_normal.x * push_dist,
                on_surface.y + hit_normal.y * push_dist,
                on_surface.z,
            );

            if let Ok((snap_ref, snapped)) =
                query.find_nearest_poly(candidate, *snap_extents, filter)
            {
                if snapped.distance_2d(&candidate) < clearance {
                    // Verify pushed point is reachable (no wall in either direction)
                    let forward_ok = query
                        .raycast(poly_ref, on_surface, snapped, filter)
                        .map(|(t, _)| t >= 1.0)
                        .unwrap_or(false);

                    let reverse_ok = if forward_ok {
                        query
                            .raycast(snap_ref, snapped, on_surface, filter)
                            .map(|(t, _)| t >= 1.0)
                            .unwrap_or(false)
                    } else {
                        false
                    };

                    if forward_ok && reverse_ok {
                        // Also verify pushed point isn't closer to a different wall
                        let still_ok = query
                            .find_distance_to_wall(snap_ref, snapped, max_radius, filter)
                            .map(|(d, _, _)| d >= hit_dist)
                            .unwrap_or(false);
                        if still_ok {
                            return snapped;
                        }
                    }
                }
            }
            wp // push failed, keep original
        }
        _ => wp, // far enough from walls
    }
}

/// Calculate total path distance in yards.
pub fn calculate_path_distance(waypoints: &[Vec3]) -> f32 {
    waypoints
        .windows(2)
        .map(|w| w[0].distance(&w[1]))
        .sum()
}

/// Max segment length (yards) before inserting intermediate waypoints.
/// Short segments keep the walking chord close to the navmesh arc on curves
/// (spiral ramps, switchbacks). Midpoints are projected to the navmesh surface,
/// which snaps them from the chord onto the actual walkable surface.
const MAX_SEGMENT_LENGTH: f32 = 3.0;

/// Split long segments by inserting midpoints projected to the navmesh surface.
///
/// On curved paths (spiral ramps), linear interpolation between waypoints
/// creates chords that cut inside the curve. By inserting midpoints and
/// projecting them to the navmesh, the points snap onto the actual surface,
/// effectively following the arc.
pub fn densify_segments(
    waypoints: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
) -> Vec<Vec3> {
    if waypoints.len() < 2 {
        return waypoints.to_vec();
    }

    let mut result = Vec::with_capacity(waypoints.len() * 2);
    result.push(waypoints[0]);

    for i in 0..waypoints.len() - 1 {
        let a = waypoints[i];
        let b = waypoints[i + 1];
        let dist = a.distance(&b);

        if dist > MAX_SEGMENT_LENGTH {
            let splits = (dist / MAX_SEGMENT_LENGTH).ceil() as usize;
            for j in 1..splits {
                let t = j as f32 / splits as f32;
                let mid = Vec3::new(
                    a.x + (b.x - a.x) * t,
                    a.y + (b.y - a.y) * t,
                    a.z + (b.z - a.z) * t,
                );
                // Project to navmesh — on curved surfaces this snaps
                // from the chord onto the actual walkable surface.
                if let Ok((poly_ref, _)) = query.find_nearest_poly(mid, HEIGHT_EXTENTS, filter) {
                    if let Ok((snapped, _)) = query.closest_point_on_poly(poly_ref, mid) {
                        result.push(snapped);
                    }
                }
            }
        }

        result.push(b);
    }

    result
}

/// Project waypoints to navmesh surface for correct Z heights.
pub fn project_waypoints_to_surface(
    waypoints: &mut [Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
) {
    for waypoint in waypoints.iter_mut() {
        if let Ok((poly_ref, _)) = query.find_nearest_poly(*waypoint, HEIGHT_EXTENTS, filter) {
            if let Ok((snapped, _)) = query.closest_point_on_poly(poly_ref, *waypoint) {
                *waypoint = snapped;
            }
        }
    }
}

/// Validate smoothed path doesn't cut through walls.
///
/// After smoothing, paths may cut through walls at tight corners.
/// Uses raycast to check line-of-sight between consecutive waypoints
/// and inserts the closest original waypoint where blocked.
pub fn validate_smoothed_path(
    smoothed: &[Vec3],
    original: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
) -> Vec<Vec3> {
    if smoothed.len() <= 2 {
        return smoothed.to_vec();
    }

    let mut result = Vec::with_capacity(smoothed.len());
    result.push(smoothed[0]);

    for i in 0..smoothed.len() - 1 {
        let current = result.last().copied().unwrap_or(smoothed[i]);
        let next = smoothed[i + 1];

        if let Ok((current_ref, _)) = query.find_nearest_poly(current, HEIGHT_EXTENTS, filter) {
            if let Ok((hit_t, _)) = query.raycast(current_ref, current, next, filter) {
                if hit_t < 1.0 {
                    // Wall detected — find closest original waypoint to hit point
                    let hit_point = Vec3::new(
                        current.x + (next.x - current.x) * hit_t,
                        current.y + (next.y - current.y) * hit_t,
                        current.z + (next.z - current.z) * hit_t,
                    );
                    if let Some(closest) = find_closest_waypoint(&hit_point, original) {
                        result.push(closest);
                    }
                }
            }
        }
        result.push(next);
    }

    result
}

/// Find the closest waypoint from a list to a given point.
pub fn find_closest_waypoint(point: &Vec3, waypoints: &[Vec3]) -> Option<Vec3> {
    waypoints
        .iter()
        .min_by(|a, b| {
            let dist_a = (a.x - point.x).powi(2) + (a.y - point.y).powi(2);
            let dist_b = (b.x - point.x).powi(2) + (b.y - point.y).powi(2);
            dist_a.partial_cmp(&dist_b).unwrap_or(std::cmp::Ordering::Equal)
        })
        .copied()
}

/// Parse waypoints from semicolon-separated string format "x1,y1,z1;x2,y2,z2;...".
pub fn parse_waypoints(waypoints_str: &str) -> Result<Vec<Vec3>, AppError> {
    use crate::validation::validate_coordinate;

    if waypoints_str.is_empty() {
        return Err(AppError::InvalidParams("Empty waypoints string".into()));
    }

    let mut waypoints = Vec::new();
    for (i, point_str) in waypoints_str.split(';').enumerate() {
        let coords: Vec<&str> = point_str.split(',').collect();
        if coords.len() != 3 {
            return Err(AppError::InvalidParams(format!(
                "Invalid waypoint {} format: expected 'x,y,z'",
                i
            )));
        }

        let x: f32 = coords[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x coordinate in waypoint {}", i))
        })?;
        let y: f32 = coords[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y coordinate in waypoint {}", i))
        })?;
        let z: f32 = coords[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z coordinate in waypoint {}", i))
        })?;

        validate_coordinate(x, y, z)?;
        waypoints.push(Vec3::new(x, y, z));
    }

    Ok(waypoints)
}

/// Parse stops from semicolon-separated string format (minimum 2 stops).
pub fn parse_stops(stops_str: &str) -> Result<Vec<Vec3>, AppError> {
    let stops = parse_waypoints(stops_str)?;
    if stops.len() < 2 {
        return Err(AppError::InvalidParams(
            "At least 2 stops required".into(),
        ));
    }
    Ok(stops)
}

/// Parse avoidance zones from semicolon-separated "x,y,z,radius,cost" strings.
pub fn parse_avoidance_zones(zones_str: &str) -> Result<Vec<AvoidanceZone>, AppError> {
    use crate::validation::validate_coordinate;

    if zones_str.is_empty() {
        return Ok(Vec::new());
    }

    let zone_entries: Vec<&str> = zones_str.split(';').collect();
    let mut result = Vec::with_capacity(zone_entries.len());
    for (i, zone_str) in zone_entries.iter().enumerate() {
        let parts: Vec<&str> = zone_str.split(',').collect();
        if parts.len() != 5 {
            return Err(AppError::InvalidParams(format!(
                "Invalid avoidance zone {} format: expected 'x,y,z,radius,cost'",
                i
            )));
        }

        let x: f32 = parts[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x in avoidance zone {}", i))
        })?;
        let y: f32 = parts[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y in avoidance zone {}", i))
        })?;
        let z: f32 = parts[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z in avoidance zone {}", i))
        })?;
        let radius: f32 = parts[3].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid radius in avoidance zone {}", i))
        })?;
        let cost: f32 = parts[4].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid cost in avoidance zone {}", i))
        })?;

        validate_coordinate(x, y, z)?;

        if !radius.is_finite() || radius <= 0.0 || radius > 1000.0 {
            return Err(AppError::InvalidParams(format!(
                "Avoidance zone {} radius must be between 0 and 1000 (got {})",
                i, radius
            )));
        }
        if !cost.is_finite() || cost < 1.0 || cost > 1000.0 {
            return Err(AppError::InvalidParams(format!(
                "Avoidance zone {} cost must be between 1 and 1000 (got {})",
                i, cost
            )));
        }

        result.push(AvoidanceZone {
            center: Vec3::new(x, y, z),
            radius,
            cost_multiplier: cost,
        });
    }

    if result.len() > 20 {
        return Err(AppError::InvalidParams(
            "Maximum 20 avoidance zones allowed".into(),
        ));
    }

    Ok(result)
}

/// An avoidance zone that paths should route around.
#[derive(Debug, Clone)]
pub struct AvoidanceZone {
    pub center: Vec3,
    pub radius: f32,
    pub cost_multiplier: f32,
}

/// Parse threat positions from semicolon-separated "x,y,z" strings.
pub fn parse_threats(threats_str: &str) -> Result<Vec<Vec3>, AppError> {
    use crate::validation::validate_coordinate;

    if threats_str.is_empty() {
        return Err(AppError::InvalidParams("Empty threats string".into()));
    }

    let mut threats = Vec::new();
    for (i, point_str) in threats_str.split(';').enumerate() {
        let coords: Vec<&str> = point_str.split(',').collect();
        if coords.len() != 3 {
            return Err(AppError::InvalidParams(format!(
                "Invalid threat {} format: expected 'x,y,z'",
                i
            )));
        }

        let x: f32 = coords[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x in threat {}", i))
        })?;
        let y: f32 = coords[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y in threat {}", i))
        })?;
        let z: f32 = coords[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z in threat {}", i))
        })?;

        validate_coordinate(x, y, z)?;
        threats.push(Vec3::new(x, y, z));
    }

    Ok(threats)
}

/// Resolve the filter to use: custom if any filter params provided, otherwise pool default.
pub fn resolve_filter<'a>(
    pool_filter: &'a QueryFilter,
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
    custom_filter_storage: &'a mut Option<QueryFilter>,
) -> Result<&'a QueryFilter, AppError> {
    if has_custom_filter(filter_ground, filter_water, filter_lava) {
        let custom = create_custom_filter(filter_ground, filter_water, filter_lava)?;
        *custom_filter_storage = Some(custom);
        Ok(custom_filter_storage.as_ref().unwrap())
    } else {
        Ok(pool_filter)
    }
}

/// Maximum polygons returned by queryPolygons per avoidance zone.
const MAX_QUERY_POLYS_PER_ZONE: usize = 512;

/// RAII guard that restores polygon area types on drop.
///
/// Ensures the shared NavMesh is returned to its original state
/// even if pathfinding panics or returns early via `?`.
struct AreaRestoreGuard<'a> {
    mesh: &'a NavMesh,
    originals: Vec<(PolyRef, u8)>,
}

impl<'a> AreaRestoreGuard<'a> {
    fn new(mesh: &'a NavMesh) -> Self {
        Self {
            mesh,
            originals: Vec::new(),
        }
    }

    /// Record original area and set polygon to avoidance area type.
    fn stamp_polygon(&mut self, poly_ref: PolyRef, new_area: u8) -> Result<(), AppError> {
        let original = self
            .mesh
            .get_poly_area(poly_ref)
            .map_err(|e| AppError::Internal(format!("get_poly_area failed: {e}")))?;
        self.mesh
            .set_poly_area(poly_ref, new_area)
            .map_err(|e| AppError::Internal(format!("set_poly_area failed: {e}")))?;
        self.originals.push((poly_ref, original));
        Ok(())
    }
}

impl Drop for AreaRestoreGuard<'_> {
    fn drop(&mut self) {
        for &(poly_ref, original_area) in &self.originals {
            if let Err(e) = self.mesh.set_poly_area(poly_ref, original_area) {
                tracing::error!("Failed to restore poly area for ref {poly_ref}: {e}");
            }
        }
    }
}

/// Execute pathfinding with avoidance zones integrated into the A* cost model.
///
/// Instead of post-processing waypoints, this function temporarily stamps
/// navmesh polygons inside zones with `NAV_AREA_AVOID` (area 63) at high cost,
/// causing Detour's A* to naturally route around them.
///
/// # Thread Safety
///
/// Caller MUST hold the `QueryPool::avoidance_lock()` for the entire duration.
#[allow(clippy::too_many_arguments)]
pub fn execute_pathfind_with_avoidance(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    base_filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &PathOptions,
    zones: &[AvoidanceZone],
    _avoidance_proof: &parking_lot::RwLockWriteGuard<'_, ()>,
) -> Result<PathResult, AppError> {
    if zones.is_empty() {
        return execute_pathfind(query, mesh, base_filter, start_pos, end_pos, options);
    }

    // --- Step 1: Find and stamp polygons inside avoidance zones ---
    let mut guard = AreaRestoreGuard::new(mesh);

    let avoid_cost = zones
        .iter()
        .map(|z| z.cost_multiplier)
        .fold(1.0f32, f32::max);

    // Use default filter for polygon search (include all walkable areas)
    let search_filter = QueryFilter::default();

    for zone in zones {
        let half_extents = Vec3::new(zone.radius, zone.radius, 50.0);
        let before_count = guard.originals.len();

        let poly_refs = match query.query_polygons(
            zone.center,
            half_extents,
            &search_filter,
            MAX_QUERY_POLYS_PER_ZONE,
        ) {
            Ok(refs) => refs,
            Err(e) => {
                tracing::warn!("queryPolygons failed for zone at {:?}: {e}", zone.center);
                continue;
            }
        };

        // Refine AABB to circle: check polygon's closest point distance
        for poly_ref in &poly_refs {
            let (closest, _) = match query.closest_point_on_poly(*poly_ref, zone.center) {
                Ok(result) => result,
                Err(_) => continue,
            };

            if closest.distance_2d(&zone.center) <= zone.radius {
                // Only stamp if not already stamped (prevent double-stamp from overlapping zones)
                let current_area = match mesh.get_poly_area(*poly_ref) {
                    Ok(a) => a,
                    Err(_) => continue,
                };
                if current_area != NAV_AREA_AVOID {
                    guard.stamp_polygon(*poly_ref, NAV_AREA_AVOID)?;
                }
            }
        }

        let zone_stamped = guard.originals.len() - before_count;
        if zone_stamped == 0 {
            tracing::warn!(
                "Avoidance: zone at ({:.1}, {:.1}, {:.1}) r={:.1} stamped 0 polygons (query returned {}) — zone may be off-navmesh",
                zone.center.x, zone.center.y, zone.center.z, zone.radius, poly_refs.len(),
            );
        }
    }

    tracing::info!(
        "Avoidance: stamped {} polygons across {} zones (cost={avoid_cost})",
        guard.originals.len(),
        zones.len(),
    );

    // --- Step 2: Build filter with high cost for avoidance area ---
    let avoidance_filter = QueryFilterBuilder::new()
        .area_cost(NAV_AREA_GROUND, base_filter.area_cost(NAV_AREA_GROUND))
        .area_cost(
            NAV_AREA_GROUND_STEEP,
            base_filter.area_cost(NAV_AREA_GROUND_STEEP),
        )
        .area_cost(NAV_AREA_WATER, base_filter.area_cost(NAV_AREA_WATER))
        .area_cost(
            NAV_AREA_MAGMA_SLIME,
            base_filter.area_cost(NAV_AREA_MAGMA_SLIME),
        )
        .area_cost(NAV_AREA_AVOID, avoid_cost)
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to create avoidance filter: {e}")))?;

    // --- Step 3: Pathfind with modified navmesh + avoidance filter ---
    // guard drops after this, restoring all original polygon areas
    execute_pathfind(query, mesh, &avoidance_filter, start_pos, end_pos, options)
}

/// Pathfind with optional avoidance zones.
///
/// If `zones` is empty, delegates to `execute_pathfind`.
/// Otherwise, acquires the avoidance lock and calls `execute_pathfind_with_avoidance`.
pub fn pathfind_maybe_avoid(
    query: &NavMeshQuery,
    pool: &detour::pool::QueryPool,
    filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &PathOptions,
    zones: &[AvoidanceZone],
) -> Result<PathResult, AppError> {
    if zones.is_empty() {
        let _pathfind_guard = pool.pathfind_lock();
        execute_pathfind(query, pool.mesh(), filter, start_pos, end_pos, options)
    } else {
        let guard = pool.avoidance_lock();
        execute_pathfind_with_avoidance(
            query,
            pool.mesh(),
            filter,
            start_pos,
            end_pos,
            options,
            zones,
            &guard,
        )
    }
}

/// Compute safe corridor widths at each waypoint by raycasting perpendicular to the path.
pub fn compute_corridor_widths(
    waypoints: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
    probe_distance: f32,
) -> Vec<f32> {
    if waypoints.len() < 2 {
        return vec![0.0; waypoints.len()];
    }

    let mut widths = Vec::with_capacity(waypoints.len());

    for i in 0..waypoints.len() {
        let wp = waypoints[i];

        // Compute path direction at this waypoint
        let direction = if i < waypoints.len() - 1 {
            let next = waypoints[i + 1];
            Vec3::new(next.x - wp.x, next.y - wp.y, 0.0)
        } else {
            let prev = waypoints[i - 1];
            Vec3::new(wp.x - prev.x, wp.y - prev.y, 0.0)
        };

        let dir_len = (direction.x * direction.x + direction.y * direction.y).sqrt();
        if dir_len < 0.001 {
            widths.push(0.0);
            continue;
        }

        // Perpendicular direction (rotate 90 degrees in XY plane)
        let perp_x = -direction.y / dir_len;
        let perp_y = direction.x / dir_len;

        let mut min_dist = probe_distance;

        // Find polygon at this waypoint
        if let Ok((wp_ref, _)) = query.find_nearest_poly(wp, HEIGHT_EXTENTS, filter) {
            // Raycast left
            let left_target = Vec3::new(
                wp.x + perp_x * probe_distance,
                wp.y + perp_y * probe_distance,
                wp.z,
            );
            if let Ok((hit_t, _)) = query.raycast(wp_ref, wp, left_target, filter) {
                let left_dist = hit_t * probe_distance;
                if left_dist < min_dist {
                    min_dist = left_dist;
                }
            }

            // Raycast right
            let right_target = Vec3::new(
                wp.x - perp_x * probe_distance,
                wp.y - perp_y * probe_distance,
                wp.z,
            );
            if let Ok((hit_t, _)) = query.raycast(wp_ref, wp, right_target, filter) {
                let right_dist = hit_t * probe_distance;
                if right_dist < min_dist {
                    min_dist = right_dist;
                }
            }
        } else {
            min_dist = 0.0;
        }

        widths.push(min_dist);
    }

    widths
}
