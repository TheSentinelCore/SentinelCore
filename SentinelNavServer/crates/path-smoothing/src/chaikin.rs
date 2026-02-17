//! Chaikin's corner-cutting algorithm for path smoothing.

use detour::Vec3;

/// Calculate the angle at a corner point (in degrees).
///
/// Returns the angle between vectors (prev -> current) and (current -> next).
/// A smaller angle means a sharper turn (90° = right angle, 180° = straight line).
pub(crate) fn corner_angle(prev: Vec3, current: Vec3, next: Vec3) -> f32 {
    // Vector from current to prev
    let v1_x = prev.x - current.x;
    let v1_y = prev.y - current.y;
    let v1_z = prev.z - current.z;

    // Vector from current to next
    let v2_x = next.x - current.x;
    let v2_y = next.y - current.y;
    let v2_z = next.z - current.z;

    // Dot product
    let dot = v1_x * v2_x + v1_y * v2_y + v1_z * v2_z;

    // Magnitudes
    let len1 = (v1_x * v1_x + v1_y * v1_y + v1_z * v1_z).sqrt();
    let len2 = (v2_x * v2_x + v2_y * v2_y + v2_z * v2_z).sqrt();

    // Handle degenerate cases
    if len1 < 0.0001 || len2 < 0.0001 {
        return 180.0; // Treat as straight line
    }

    // Clamp to avoid NaN from acos
    let cos_angle = (dot / (len1 * len2)).clamp(-1.0, 1.0);
    cos_angle.acos().to_degrees()
}

/// Remove waypoints whose turn angle is sharper than the outlier threshold.
///
/// Angles < outlier_angle indicate extreme corners (data glitches or
/// hairpin turns) that should be removed entirely, not smoothed.
/// Start and end points are always preserved.
fn reject_outliers(path: &[Vec3], outlier_angle: f32) -> Vec<Vec3> {
    if path.len() < 3 || outlier_angle <= 0.0 || outlier_angle >= 180.0 {
        return path.to_vec();
    }

    let mut result = Vec::with_capacity(path.len());
    result.push(path[0]);

    for i in 1..path.len() - 1 {
        let angle = corner_angle(path[i - 1], path[i], path[i + 1]);
        if angle >= outlier_angle {
            result.push(path[i]);
        }
        // else: angle too sharp, remove this waypoint
    }

    result.push(*path.last().unwrap());
    result
}

/// Chaikin smoothing with outlier rejection pre-pass.
///
/// First removes extreme-angle waypoints, then applies standard Chaikin.
pub fn smooth_chaikin_with_outlier_rejection(
    path: &[Vec3],
    iterations: usize,
    ratio: f32,
    min_angle: f32,
    outlier_angle: f32,
) -> Vec<Vec3> {
    let filtered = reject_outliers(path, outlier_angle);
    smooth_chaikin(&filtered, iterations, ratio, min_angle, false)
}

/// Smooth a path using Chaikin's algorithm with angle-aware corner handling.
///
/// Iteratively cuts corners to create smoother curves.
/// More iterations = smoother curve but more waypoints.
///
/// # Arguments
/// * `path` - The input path
/// * `iterations` - Number of smoothing iterations (2-3 recommended)
/// * `ratio` - Corner-cut ratio (0.5-0.95, default 0.75). Higher = tighter corners.
/// * `min_angle` - Minimum corner angle to smooth (degrees, 0-180). Corners sharper than
///   this angle won't be smoothed. 0 = smooth all, 90 = skip tight turns.
/// * `keep_originals` - If true, preserve original waypoints and only insert interpolation points.
pub fn smooth_chaikin(
    path: &[Vec3],
    iterations: usize,
    ratio: f32,
    min_angle: f32,
    keep_originals: bool,
) -> Vec<Vec3> {
    if path.len() < 3 {
        return path.to_vec();
    }

    // Use the appropriate smoothing mode
    if keep_originals {
        smooth_chaikin_preserving(path, iterations, ratio, min_angle)
    } else {
        smooth_chaikin_standard(path, iterations, ratio, min_angle)
    }
}

/// Standard Chaikin smoothing that replaces corners with Q/R points.
fn smooth_chaikin_standard(
    path: &[Vec3],
    iterations: usize,
    ratio: f32,
    min_angle: f32,
) -> Vec<Vec3> {
    let mut current = path.to_vec();
    let inv_ratio = 1.0 - ratio;

    for _ in 0..iterations {
        let mut next = Vec::with_capacity(current.len() * 2);
        next.push(current[0]); // Keep start point

        for i in 0..current.len() - 1 {
            let p0 = current[i];
            let p1 = current[i + 1];

            // Check if this corner should be smoothed based on angle
            let should_smooth = if min_angle > 0.0 && i > 0 && i < current.len() - 1 {
                // Calculate angle at p0 (between previous point, p0, and p1)
                let prev = current[i - 1];
                let angle = corner_angle(prev, p0, p1);
                // Smooth only if angle is >= min_angle (wider/gentler turns)
                // Sharp corners (small angles) are preserved
                angle >= min_angle
            } else {
                true // First/last segments always get Q/R points
            };

            if should_smooth {
                // Q = ratio * P0 + (1-ratio) * P1 (closer to P0)
                let q = Vec3::new(
                    ratio * p0.x + inv_ratio * p1.x,
                    ratio * p0.y + inv_ratio * p1.y,
                    ratio * p0.z + inv_ratio * p1.z,
                );

                // R = (1-ratio) * P0 + ratio * P1 (closer to P1)
                let r = Vec3::new(
                    inv_ratio * p0.x + ratio * p1.x,
                    inv_ratio * p0.y + ratio * p1.y,
                    inv_ratio * p0.z + ratio * p1.z,
                );

                next.push(q);
                next.push(r);
            } else {
                // Sharp corner - keep original point to preserve navmesh accuracy
                next.push(p0);
            }
        }

        next.push(*current.last().unwrap()); // Keep end point
        current = next;
    }

    current
}

/// Chaikin smoothing that preserves all original waypoints.
///
/// Instead of replacing corners with Q/R points, this inserts interpolation
/// points between original waypoints while keeping all originals.
fn smooth_chaikin_preserving(
    path: &[Vec3],
    iterations: usize,
    ratio: f32,
    min_angle: f32,
) -> Vec<Vec3> {
    let mut current = path.to_vec();
    let inv_ratio = 1.0 - ratio;

    for _ in 0..iterations {
        let mut next = Vec::with_capacity(current.len() * 3);
        next.push(current[0]); // Keep start point

        for i in 0..current.len() - 1 {
            let p0 = current[i];
            let p1 = current[i + 1];

            // Check if this corner should be smoothed based on angle
            let should_smooth = if min_angle > 0.0 && i > 0 && i < current.len() - 1 {
                let prev = current[i - 1];
                let angle = corner_angle(prev, p0, p1);
                angle >= min_angle
            } else {
                true
            };

            if should_smooth && i > 0 {
                // Insert Q point between prev original and current (closer to current)
                let q = Vec3::new(
                    ratio * p0.x + inv_ratio * p1.x,
                    ratio * p0.y + inv_ratio * p1.y,
                    ratio * p0.z + inv_ratio * p1.z,
                );
                next.push(q);
            }

            // Keep original point (this is the key difference from standard)
            if i < current.len() - 1 {
                next.push(p1);
            }
        }

        current = next;
    }

    // Ensure we end with the final point
    if current.last() != path.last() {
        current.push(*path.last().unwrap());
    }

    current
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chaikin_preserves_endpoints() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
            Vec3::new(1.0, 1.0, 0.0),
        ];

        let smoothed = smooth_chaikin(&path, 2, 0.75, 0.0, false);

        assert_eq!(smoothed[0], path[0]);
        assert_eq!(*smoothed.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_chaikin_increases_points() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
            Vec3::new(1.0, 1.0, 0.0),
        ];

        let smoothed = smooth_chaikin(&path, 1, 0.75, 0.0, false);

        assert!(smoothed.len() > path.len());
    }

    #[test]
    fn test_chaikin_short_path() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
        ];

        let smoothed = smooth_chaikin(&path, 2, 0.75, 0.0, false);

        assert_eq!(smoothed.len(), path.len());
    }

    #[test]
    fn test_corner_angle_calculation() {
        // 90 degree turn
        let prev = Vec3::new(0.0, 0.0, 0.0);
        let current = Vec3::new(1.0, 0.0, 0.0);
        let next = Vec3::new(1.0, 1.0, 0.0);

        let angle = corner_angle(prev, current, next);
        assert!((angle - 90.0).abs() < 0.1);
    }

    #[test]
    fn test_corner_angle_straight_line() {
        // Straight line = 180 degrees
        let prev = Vec3::new(0.0, 0.0, 0.0);
        let current = Vec3::new(1.0, 0.0, 0.0);
        let next = Vec3::new(2.0, 0.0, 0.0);

        let angle = corner_angle(prev, current, next);
        assert!((angle - 180.0).abs() < 0.1);
    }

    #[test]
    fn test_angle_threshold_skips_sharp_corners() {
        // Path with a sharp 90-degree turn
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 10.0, 0.0),
            Vec3::new(20.0, 10.0, 0.0),
        ];

        // With min_angle=120, the 90-degree corner should NOT be smoothed
        let smoothed_skip = smooth_chaikin(&path, 1, 0.75, 120.0, false);

        // With min_angle=0, all corners are smoothed
        let smoothed_all = smooth_chaikin(&path, 1, 0.75, 0.0, false);

        // Skipping sharp corners should result in fewer points
        // (or the sharp corner point is preserved)
        assert!(smoothed_skip.len() <= smoothed_all.len());
    }

    #[test]
    fn test_keep_originals_preserves_waypoints() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 10.0, 0.0),
        ];

        let smoothed = smooth_chaikin(&path, 1, 0.75, 0.0, true);

        // Original endpoint should be preserved
        assert_eq!(*smoothed.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_outlier_rejection_removes_sharp_turn() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 0.1, 0.0), // Nearly 180° reversal (~0° angle)
            Vec3::new(20.0, 0.0, 0.0),
        ];
        let filtered = reject_outliers(&path, 90.0);
        // The sharp turn point should be removed
        assert!(filtered.len() < path.len());
        assert_eq!(filtered[0], path[0]);
        assert_eq!(*filtered.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_outlier_rejection_preserves_endpoints() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(5.0, 0.0, 0.0),
            Vec3::new(5.0, 5.0, 0.0),
        ];
        let filtered = reject_outliers(&path, 90.0);
        assert_eq!(filtered[0], path[0]);
        assert_eq!(*filtered.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_outlier_rejection_keeps_gentle_turns() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 2.0, 0.0), // gentle turn (~170° angle)
            Vec3::new(30.0, 2.0, 0.0),
        ];
        let filtered = reject_outliers(&path, 90.0);
        assert_eq!(filtered.len(), path.len()); // nothing removed
    }

    #[test]
    fn test_smooth_with_outlier_rejection() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 0.1, 0.0), // outlier
            Vec3::new(20.0, 0.0, 0.0),
            Vec3::new(20.0, 10.0, 0.0),
        ];
        let smoothed = smooth_chaikin_with_outlier_rejection(&path, 2, 0.75, 30.0, 90.0);
        assert_eq!(smoothed[0], path[0]);
        assert_eq!(*smoothed.last().unwrap(), *path.last().unwrap());
    }
}
