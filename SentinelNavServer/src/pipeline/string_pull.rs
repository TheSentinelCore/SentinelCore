//! String-pulling optimization to reduce waypoint count while maintaining a valid path.
//!
//! Uses raycast to find the furthest visible waypoint from each position,
//! eliminating intermediate waypoints that have direct line-of-sight.

use detour::filter::QueryFilter;
use detour::query::NavMeshQuery;
use detour::types::Vec3;

use super::filter::HEIGHT_EXTENTS;

/// Max 3D deviation (yards) allowed when string-pulling skips intermediate waypoints.
/// Prevents collapsing ramp/staircase waypoints on vertical terrain.
pub(crate) const MAX_STRING_PULL_DEVIATION: f32 = 1.5;

/// Max cumulative 2D heading change (radians) allowed when string-pulling.
/// Prevents collapsing spiral ramp/switchback waypoints where the walking
/// arc diverges significantly from the straight-line chord.
pub(crate) const MAX_HEADING_CHANGE: f32 = 0.524; // 30 degrees

/// Compute Z extents for segment-based operations.
/// Uses the Z range of the segment endpoints with a buffer,
/// clamped to [2.0, 5.0] to stay on the correct floor in
/// multi-level structures (towers, ramps, bridges).
pub(crate) fn segment_z_extent(a: &Vec3, b: &Vec3) -> f32 {
    let z_range = (a.z - b.z).abs();
    (z_range + 1.0).max(2.0).min(5.0)
}

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

/// Check if any point along the line from `a` to `b` is closer to a wall than `threshold`.
/// Samples at ~1 yd intervals. Uses the same `find_distance_to_wall` API as `apply_wall_clearance`.
fn shortcut_near_wall(
    query: &NavMeshQuery,
    filter: &QueryFilter,
    a: Vec3,
    b: Vec3,
    threshold: f32,
) -> bool {
    let dist = a.distance(&b);
    if dist < 0.5 {
        return false;
    }
    let z_ext = segment_z_extent(&a, &b);
    let extents = Vec3::new(HEIGHT_EXTENTS.x, HEIGHT_EXTENTS.y, z_ext);
    let steps = (dist / 1.0).ceil().max(2.0) as usize;
    for i in 1..steps {
        let t = i as f32 / steps as f32;
        let sample = Vec3::new(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t,
        );
        if let Ok((poly_ref, on_surface)) = query.find_nearest_poly(sample, extents, filter) {
            if let Ok((wall_dist, _, _)) =
                query.find_distance_to_wall(poly_ref, on_surface, threshold * 2.0, filter)
            {
                if wall_dist < threshold {
                    return true;
                }
            }
        }
    }
    false
}

/// String-pulling optimization to reduce waypoint count while maintaining a valid path.
///
/// Uses raycast to find the furthest visible waypoint from each position,
/// eliminating intermediate waypoints that have direct line-of-sight.
///
/// `max_deviation`: Max 3D deviation (yards) before refusing to skip waypoints.
/// `max_heading`: Max cumulative heading change (radians) before refusing to skip.
/// `min_wall_dist`: Min wall distance (yards) for shortcuts. If any point along
///   the shortcut line is closer to a wall than this, the shortcut is rejected. 0 = disabled.
pub fn string_pull_path(
    waypoints: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
    max_deviation: f32,
    max_heading: f32,
    min_wall_dist: f32,
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
                        if dev > max_deviation {
                            continue;
                        }
                        // Guard: don't skip if path curves too much in 2D (spiral ramps).
                        // The character walks a straight chord between waypoints, so a
                        // large heading change means the chord cuts through the arc interior.
                        let turn =
                            cumulative_heading_change(waypoints, current_idx, target_idx);
                        if turn > max_heading {
                            break; // Path curves too much — stop looking further
                        }
                        // Guard: don't shortcut if the line passes too close to a wall.
                        // Raycast validates connectivity but not clearance — a line 0.1 yd
                        // from a wall still passes raycast. This check catches corner-clipping.
                        if min_wall_dist > 0.0
                            && shortcut_near_wall(
                                query,
                                filter,
                                current_pos,
                                target_pos,
                                min_wall_dist,
                            )
                        {
                            break; // Shortcut clips a corner — keep intermediate waypoints
                        }
                        furthest_visible = target_idx;
                    } else {
                        // Wall blocks LOS — stop looking past this point.
                        // Targets are sequential path waypoints; if the direct line to
                        // target+N hits a wall, targets past it would require going around
                        // the corner, producing exactly the corner-clipping we want to avoid.
                        break;
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
