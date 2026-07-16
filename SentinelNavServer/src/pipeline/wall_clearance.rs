//! Wall clearance: push waypoints away from nearby walls/obstacles.

use detour::filter::QueryFilter;
use detour::query::NavMeshQuery;
use detour::types::{PolyRef, Vec3};

use super::filter::HEIGHT_EXTENTS;
use super::string_pull::segment_z_extent;

/// Verify a point is reachable from both directions (no wall blocking either way).
fn check_reachable(
    query: &NavMeshQuery,
    filter: &QueryFilter,
    from_ref: PolyRef,
    from_pos: Vec3,
    to_ref: PolyRef,
    to_pos: Vec3,
) -> bool {
    let forward_ok = query
        .raycast(from_ref, from_pos, to_pos, filter)
        .map(|(t, _)| t >= 1.0)
        .unwrap_or(false);

    if !forward_ok {
        return false;
    }

    query
        .raycast(to_ref, to_pos, from_pos, filter)
        .map(|(t, _)| t >= 1.0)
        .unwrap_or(false)
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
    let mut result = Vec::with_capacity(waypoints.len() * 2);

    // Always keep start point as-is
    result.push(waypoints[0]);

    for seg_idx in 0..waypoints.len() - 1 {
        let a = waypoints[seg_idx];
        let b = waypoints[seg_idx + 1];

        // Per-segment Z extents to stay on correct floor in multi-level structures
        let seg_z_ext = segment_z_extent(&a, &b);
        let seg_extents = Vec3::new(HEIGHT_EXTENTS.x, HEIGHT_EXTENTS.y, seg_z_ext);
        let snap_extents = Vec3::new(clearance * 0.5, clearance * 0.5, seg_z_ext);

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
                    match query.find_nearest_poly(sample, seg_extents, filter) {
                        Ok(result) => result,
                        Err(_) => continue,
                    };

                match query.find_distance_to_wall(poly_ref, on_surface, max_radius, filter) {
                    Ok((hit_dist, _hit_pos, hit_normal)) => {
                        if hit_dist < clearance {
                            // Segment passes too close to a wall — insert offset waypoint
                            let push_dist = clearance - hit_dist;
                            let candidate = Vec3::new(
                                on_surface.x + hit_normal.x * push_dist,
                                on_surface.y + hit_normal.y * push_dist,
                                on_surface.z,
                            );

                            match query.find_nearest_poly(candidate, snap_extents, filter) {
                                Ok((snap_ref, snapped)) => {
                                    if snapped.distance_2d(&candidate) < clearance
                                        && check_reachable(
                                            query,
                                            filter,
                                            poly_ref,
                                            on_surface,
                                            snap_ref,
                                            snapped,
                                        )
                                    {
                                        result.push(snapped);
                                    }
                                }
                                Err(_) => {}
                            }
                        }
                    }
                    Err(_) => {}
                }
            }
        }

        // Push the segment endpoint
        if seg_idx + 1 < waypoints.len() - 1 {
            // Intermediate waypoint — also offset if too close to a wall
            let pushed = try_push_from_wall(
                b,
                query,
                filter,
                clearance,
                max_radius,
                &snap_extents,
                seg_z_ext,
            );
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
    z_ext: f32,
) -> Vec3 {
    // Snap to surface first — waypoint may be slightly off-polygon on ramps.
    // Use segment-relative Z to stay on the correct floor in multi-level structures.
    let extents = Vec3::new(HEIGHT_EXTENTS.x, HEIGHT_EXTENTS.y, z_ext);
    let (poly_ref, on_surface) = match query.find_nearest_poly(wp, extents, filter) {
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
                if snapped.distance_2d(&candidate) < clearance
                    && check_reachable(query, filter, poly_ref, on_surface, snap_ref, snapped)
                {
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
            wp // push failed, keep original
        }
        Ok(_) => wp,
        Err(_) => wp,
    }
}
