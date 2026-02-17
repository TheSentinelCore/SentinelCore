//! Path quality metrics for smoothing pipeline diagnostics.

use detour::Vec3;

/// Quality metrics for a smoothed path.
#[derive(Debug, Clone, Default)]
pub struct PathMetrics {
    /// Average angle change between consecutive segments (degrees). Lower = smoother.
    pub smoothness: f32,
    /// Maximum distance from any smoothed point to the original path (yards).
    pub max_deviation: f32,
    /// Number of output waypoints.
    pub point_count: usize,
    /// Total path length (yards).
    pub total_length: f32,
    /// Number of segments that required validation fallback.
    pub fallback_count: usize,
}

impl PathMetrics {
    /// Compute metrics for a smoothed path relative to the original.
    pub fn compute(smoothed: &[Vec3], original: &[Vec3]) -> Self {
        Self {
            smoothness: compute_smoothness(smoothed),
            max_deviation: compute_max_deviation(smoothed, original),
            point_count: smoothed.len(),
            total_length: path_length(smoothed),
            fallback_count: 0, // set externally by pipeline
        }
    }
}

fn path_length(path: &[Vec3]) -> f32 {
    path.windows(2).map(|w| w[0].distance(&w[1])).sum()
}

/// Average absolute heading change between consecutive segments (degrees).
fn compute_smoothness(path: &[Vec3]) -> f32 {
    if path.len() < 3 {
        return 0.0;
    }
    let mut total = 0.0f32;
    let mut count = 0u32;
    for i in 1..path.len() - 1 {
        let v1_x = path[i].x - path[i - 1].x;
        let v1_y = path[i].y - path[i - 1].y;
        let v2_x = path[i + 1].x - path[i].x;
        let v2_y = path[i + 1].y - path[i].y;
        let len1 = (v1_x * v1_x + v1_y * v1_y).sqrt();
        let len2 = (v2_x * v2_x + v2_y * v2_y).sqrt();
        if len1 > 0.001 && len2 > 0.001 {
            let dot = v1_x * v2_x + v1_y * v2_y;
            let cos_a = (dot / (len1 * len2)).clamp(-1.0, 1.0);
            total += cos_a.acos().to_degrees();
            count += 1;
        }
    }
    if count > 0 {
        total / count as f32
    } else {
        0.0
    }
}

/// Maximum 2D distance from any smoothed point to the nearest original path segment.
fn compute_max_deviation(smoothed: &[Vec3], original: &[Vec3]) -> f32 {
    if original.len() < 2 {
        return 0.0;
    }
    let mut max_dev = 0.0f32;
    for sp in smoothed {
        let mut min_dist = f32::MAX;
        for w in original.windows(2) {
            let dist = point_to_segment_2d(*sp, w[0], w[1]);
            if dist < min_dist {
                min_dist = dist;
            }
        }
        if min_dist > max_dev {
            max_dev = min_dist;
        }
    }
    max_dev
}

fn point_to_segment_2d(p: Vec3, a: Vec3, b: Vec3) -> f32 {
    let ab_x = b.x - a.x;
    let ab_y = b.y - a.y;
    let len_sq = ab_x * ab_x + ab_y * ab_y;
    if len_sq < 0.0001 {
        return p.distance_2d(&a);
    }
    let t = ((p.x - a.x) * ab_x + (p.y - a.y) * ab_y) / len_sq;
    let t = t.clamp(0.0, 1.0);
    let dx = p.x - (a.x + t * ab_x);
    let dy = p.y - (a.y + t * ab_y);
    (dx * dx + dy * dy).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_straight_path_smoothness_zero() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 0.0, 0.0),
        ];
        let m = PathMetrics::compute(&path, &path);
        assert!(m.smoothness < 0.1);
    }

    #[test]
    fn test_self_deviation_zero() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 5.0, 0.0),
        ];
        let m = PathMetrics::compute(&path, &path);
        assert!(m.max_deviation < 0.01);
    }

    #[test]
    fn test_path_length() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(3.0, 4.0, 0.0),
        ];
        let len = path_length(&path);
        assert!((len - 5.0).abs() < 0.01);
    }
}
