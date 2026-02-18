//! Post-smoothing navmesh validation.
//!
//! Verifies smoothed paths don't cut through walls by raycasting between
//! consecutive points. On failure, falls back to the closest original
//! (pre-smoothed) waypoint.

use detour::query::NavMeshQuery;
use detour::filter::QueryFilter;
use detour::types::Vec3;

/// Validate a smoothed path against navmesh constraints.
///
/// Checks each segment for:
/// 1. Wall intersection via raycast
/// 2. Excessive deviation from original path
///
/// On failure, inserts the closest original waypoint as a recovery point.
pub fn validate_path(
    smoothed: &[Vec3],
    original: &[Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
    extents: [f32; 3],
    max_deviation: f32,
    fallback_on_invalid: bool,
) -> Vec<Vec3> {
    if smoothed.len() <= 2 {
        return smoothed.to_vec();
    }

    let search_extents = Vec3::new(extents[0], extents[1], extents[2]);
    let mut result = Vec::with_capacity(smoothed.len());
    result.push(smoothed[0]);

    for i in 0..smoothed.len() - 1 {
        let current = *result.last().unwrap();
        let next = smoothed[i + 1];

        let mut is_valid = true;

        // Check 1: Raycast — wall intersection
        if let Ok((poly_ref, _)) = query.find_nearest_poly(current, search_extents, filter) {
            if let Ok((hit_t, _)) = query.raycast(poly_ref, current, next, filter) {
                if hit_t < 1.0 {
                    is_valid = false;
                }
            }
        }

        // Check 2: Deviation from original path
        if is_valid && max_deviation > 0.0 {
            let dev = min_distance_to_path(next, original);
            if dev > max_deviation {
                is_valid = false;
            }
        }

        if !is_valid && fallback_on_invalid {
            if let Some(closest) = find_closest_original(next, original) {
                if result.last().is_none_or(|last| last.distance(&closest) > 0.1) {
                    result.push(closest);
                }
            }
        } else {
            result.push(next);
        }
    }

    result
}

/// Minimum perpendicular distance from a point to any segment of a path.
fn min_distance_to_path(point: Vec3, path: &[Vec3]) -> f32 {
    if path.is_empty() {
        return f32::MAX;
    }
    if path.len() == 1 {
        return point.distance_2d(&path[0]);
    }

    let mut min_dist = f32::MAX;
    for window in path.windows(2) {
        let dist = point_to_segment_distance_2d(point, window[0], window[1]);
        if dist < min_dist {
            min_dist = dist;
        }
    }
    min_dist
}

/// 2D perpendicular distance from a point to a line segment.
fn point_to_segment_distance_2d(p: Vec3, a: Vec3, b: Vec3) -> f32 {
    let ab_x = b.x - a.x;
    let ab_y = b.y - a.y;
    let len_sq = ab_x * ab_x + ab_y * ab_y;

    if len_sq < 0.0001 {
        return p.distance_2d(&a);
    }

    let t = ((p.x - a.x) * ab_x + (p.y - a.y) * ab_y) / len_sq;
    let t = t.clamp(0.0, 1.0);

    let proj_x = a.x + t * ab_x;
    let proj_y = a.y + t * ab_y;
    let dx = p.x - proj_x;
    let dy = p.y - proj_y;
    (dx * dx + dy * dy).sqrt()
}

/// Find closest original waypoint to a point (2D distance).
fn find_closest_original(point: Vec3, original: &[Vec3]) -> Option<Vec3> {
    original
        .iter()
        .min_by(|a, b| {
            let da = a.distance_2d(&point);
            let db = b.distance_2d(&point);
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        })
        .copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_point_to_segment_on_segment() {
        let p = Vec3::new(5.0, 0.0, 0.0);
        let a = Vec3::new(0.0, 0.0, 0.0);
        let b = Vec3::new(10.0, 0.0, 0.0);
        let d = point_to_segment_distance_2d(p, a, b);
        assert!(d < 0.01);
    }

    #[test]
    fn test_point_to_segment_perpendicular() {
        let p = Vec3::new(5.0, 3.0, 0.0);
        let a = Vec3::new(0.0, 0.0, 0.0);
        let b = Vec3::new(10.0, 0.0, 0.0);
        let d = point_to_segment_distance_2d(p, a, b);
        assert!((d - 3.0).abs() < 0.01);
    }

    #[test]
    fn test_min_distance_to_path() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 10.0, 0.0),
        ];
        let point = Vec3::new(5.0, 2.0, 0.0);
        let d = min_distance_to_path(point, &path);
        assert!((d - 2.0).abs() < 0.01);
    }

    #[test]
    fn test_find_closest_original() {
        let original = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 0.0, 0.0),
        ];
        let point = Vec3::new(11.0, 1.0, 0.0);
        let closest = find_closest_original(point, &original).unwrap();
        assert_eq!(closest, original[1]);
    }
}
