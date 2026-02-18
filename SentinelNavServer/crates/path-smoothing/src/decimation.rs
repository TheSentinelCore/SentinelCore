//! Post-interpolation waypoint decimation.
//!
//! Removes consecutive waypoints closer than a minimum spacing threshold.
//! Prevents dense clustering on stairs where navmesh segments are very short.

use detour::Vec3;

/// Remove waypoints closer than `min_spacing` yards (3D distance).
///
/// Always preserves the first and last waypoint.
pub fn decimate_by_distance(waypoints: &[Vec3], min_spacing: f32) -> Vec<Vec3> {
    if waypoints.len() <= 2 {
        return waypoints.to_vec();
    }

    let min_sq = min_spacing * min_spacing;
    let mut result = Vec::with_capacity(waypoints.len());
    result.push(waypoints[0]);

    for i in 1..waypoints.len() - 1 {
        let last = *result.last().unwrap();
        let wp = waypoints[i];
        let dx = wp.x - last.x;
        let dy = wp.y - last.y;
        let dz = wp.z - last.z;
        if dx * dx + dy * dy + dz * dz >= min_sq {
            result.push(wp);
        }
    }

    result.push(*waypoints.last().unwrap());
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preserves_endpoints() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(0.3, 0.0, 0.0),
            Vec3::new(0.6, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
        ];
        let result = decimate_by_distance(&path, 1.0);
        assert_eq!(result[0], path[0]);
        assert_eq!(*result.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_removes_dense_points() {
        let path: Vec<Vec3> = (0..20)
            .map(|i| Vec3::new(i as f32 * 0.3, 0.0, i as f32 * 0.15))
            .collect();
        let result = decimate_by_distance(&path, 1.0);
        assert!(result.len() < path.len());
        assert!(result.len() >= 2);
    }

    #[test]
    fn test_keeps_well_spaced_points() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(3.0, 0.0, 0.0),
            Vec3::new(6.0, 0.0, 0.0),
            Vec3::new(9.0, 0.0, 0.0),
        ];
        let result = decimate_by_distance(&path, 1.0);
        assert_eq!(result.len(), path.len());
    }

    #[test]
    fn test_short_path_passthrough() {
        let path = vec![Vec3::new(0.0, 0.0, 0.0), Vec3::new(1.0, 0.0, 0.0)];
        let result = decimate_by_distance(&path, 5.0);
        assert_eq!(result.len(), 2);
    }
}
