//! Path post-processing: densification and distance calculation.

use detour::filter::QueryFilter;
use detour::query::NavMeshQuery;
use detour::types::Vec3;

use super::filter::HEIGHT_EXTENTS;
use super::string_pull::segment_z_extent;

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
pub(crate) const MAX_SEGMENT_LENGTH: f32 = 3.0;

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
    max_segment: f32,
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

        if dist > max_segment {
            let z_ext = segment_z_extent(&a, &b);
            let extents = Vec3::new(HEIGHT_EXTENTS.x, HEIGHT_EXTENTS.y, z_ext);
            let splits = (dist / max_segment).ceil() as usize;
            for j in 1..splits {
                let t = j as f32 / splits as f32;
                let mid = Vec3::new(
                    a.x + (b.x - a.x) * t,
                    a.y + (b.y - a.y) * t,
                    a.z + (b.z - a.z) * t,
                );
                // Project to navmesh — on curved surfaces this snaps
                // from the chord onto the actual walkable surface.
                if let Ok((poly_ref, _)) = query.find_nearest_poly(mid, extents, filter) {
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
