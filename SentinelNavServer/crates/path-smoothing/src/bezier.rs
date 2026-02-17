//! Cubic Bezier curve smoothing for paths.

use detour::Vec3;

/// Smooth a path using cubic Bezier curves.
///
/// Creates smooth curves that approximate the original path.
///
/// # Arguments
/// * `path` - The input path
/// * `samples_per_segment` - Number of interpolated points per curve segment
pub fn smooth_bezier(path: &[Vec3], samples_per_segment: usize) -> Vec<Vec3> {
    if path.len() < 3 {
        return path.to_vec();
    }

    let mut result = Vec::new();
    result.push(path[0]);

    // Process path in segments of 3 points (creating quadratic Bezier curves)
    // For a smoother result with cubic Bezier, we generate control points
    let mut i = 0;
    while i < path.len() - 1 {
        let p0 = path[i];
        let p2 = path[(i + 1).min(path.len() - 1)];

        // Generate control point as midpoint offset
        let p1 = if i + 2 < path.len() {
            // Use next point to influence control point
            let next = path[i + 2];
            Vec3::new(
                (p0.x + p2.x * 2.0 + next.x) / 4.0,
                (p0.y + p2.y * 2.0 + next.y) / 4.0,
                (p0.z + p2.z * 2.0 + next.z) / 4.0,
            )
        } else {
            // Simple midpoint for last segment
            Vec3::new(
                (p0.x + p2.x) / 2.0,
                (p0.y + p2.y) / 2.0,
                (p0.z + p2.z) / 2.0,
            )
        };

        // Sample the quadratic Bezier curve
        for j in 1..=samples_per_segment {
            let t = j as f32 / samples_per_segment as f32;
            let point = quadratic_bezier(p0, p1, p2, t);
            result.push(point);
        }

        i += 1;
    }

    // Ensure we end at the last point
    if let Some(last) = result.last() {
        let target = path.last().unwrap();
        if (last.x - target.x).abs() > 0.001
            || (last.y - target.y).abs() > 0.001
            || (last.z - target.z).abs() > 0.001
        {
            result.push(*target);
        }
    }

    result
}

/// Calculate a point on a quadratic Bezier curve.
fn quadratic_bezier(p0: Vec3, p1: Vec3, p2: Vec3, t: f32) -> Vec3 {
    let u = 1.0 - t;
    let tt = t * t;
    let uu = u * u;

    Vec3::new(
        uu * p0.x + 2.0 * u * t * p1.x + tt * p2.x,
        uu * p0.y + 2.0 * u * t * p1.y + tt * p2.y,
        uu * p0.z + 2.0 * u * t * p1.z + tt * p2.z,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bezier_preserves_start() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 1.0, 0.0),
            Vec3::new(2.0, 0.0, 0.0),
        ];

        let smoothed = smooth_bezier(&path, 5);

        assert_eq!(smoothed[0], path[0]);
    }

    #[test]
    fn test_bezier_short_path() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
        ];

        let smoothed = smooth_bezier(&path, 5);

        assert_eq!(smoothed.len(), path.len());
    }
}
