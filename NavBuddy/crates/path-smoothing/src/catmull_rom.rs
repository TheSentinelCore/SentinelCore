//! Catmull-Rom spline interpolation for path smoothing.

use detour::Vec3;

/// Smooth a path using Catmull-Rom spline interpolation.
///
/// Creates smooth curves that pass through all original control points.
///
/// # Arguments
/// * `path` - The input path
/// * `samples_per_segment` - Number of interpolated points between each pair
pub fn smooth_catmull_rom(path: &[Vec3], samples_per_segment: usize) -> Vec<Vec3> {
    if path.len() < 4 {
        return path.to_vec();
    }

    let mut result = Vec::new();

    for i in 0..path.len() - 1 {
        let p0 = if i == 0 { path[0] } else { path[i - 1] };
        let p1 = path[i];
        let p2 = path[i + 1];
        let p3 = if i + 2 >= path.len() {
            path[path.len() - 1]
        } else {
            path[i + 2]
        };

        for j in 0..samples_per_segment {
            let t = j as f32 / samples_per_segment as f32;
            let point = catmull_rom_point(p0, p1, p2, p3, t);
            result.push(point);
        }
    }

    result.push(*path.last().unwrap());
    result
}

/// Calculate a point on a Catmull-Rom spline.
fn catmull_rom_point(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, t: f32) -> Vec3 {
    let t2 = t * t;
    let t3 = t2 * t;

    Vec3::new(
        0.5 * ((2.0 * p1.x)
            + (-p0.x + p2.x) * t
            + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2
            + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3),
        0.5 * ((2.0 * p1.y)
            + (-p0.y + p2.y) * t
            + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2
            + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3),
        0.5 * ((2.0 * p1.z)
            + (-p0.z + p2.z) * t
            + (2.0 * p0.z - 5.0 * p1.z + 4.0 * p2.z - p3.z) * t2
            + (-p0.z + 3.0 * p1.z - 3.0 * p2.z + p3.z) * t3),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_catmull_rom_preserves_endpoint() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
            Vec3::new(2.0, 1.0, 0.0),
            Vec3::new(3.0, 1.0, 0.0),
        ];

        let smoothed = smooth_catmull_rom(&path, 5);

        assert_eq!(*smoothed.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_catmull_rom_short_path() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
        ];

        let smoothed = smooth_catmull_rom(&path, 5);

        assert_eq!(smoothed.len(), path.len());
    }
}
