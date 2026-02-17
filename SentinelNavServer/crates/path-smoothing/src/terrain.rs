//! Terrain analysis for adaptive smoothing density.
//!
//! Detects stairs, ramps, and spiral structures to scale interpolation
//! density — steep segments get more points for accurate height tracking.

use detour::Vec3;

/// Result of analyzing terrain between two waypoints.
#[derive(Debug, Clone)]
pub struct TerrainAnalysis {
    /// Horizontal (XY) distance between points.
    pub horizontal_dist: f32,
    /// Absolute vertical (Z) delta between points.
    pub z_delta: f32,
    /// Slope ratio: |z_delta| / horizontal_dist. High = stairs/ramp.
    pub slope_ratio: f32,
}

impl TerrainAnalysis {
    /// Analyze the terrain between two waypoints.
    pub fn analyze_segment(a: &Vec3, b: &Vec3) -> Self {
        let horizontal_dist = a.distance_2d(b);
        let z_delta = (b.z - a.z).abs();
        let slope_ratio = if horizontal_dist > 0.01 {
            z_delta / horizontal_dist
        } else {
            0.0
        };
        Self {
            horizontal_dist,
            z_delta,
            slope_ratio,
        }
    }

    /// Scale interpolation density based on terrain steepness.
    ///
    /// Steep terrain (stairs, ramps) gets 2x density, capped at 32.
    pub fn scale_density(&self, base_density: usize, stair_threshold: f32) -> usize {
        if self.slope_ratio > stair_threshold {
            (base_density * 2).min(32)
        } else {
            base_density
        }
    }
}

/// Compute cumulative absolute heading change through waypoints[from..=to].
///
/// High values indicate spiral ramps or switchbacks where the path curves
/// significantly while climbing. Used to detect terrain that needs higher
/// interpolation density.
///
/// Returns cumulative heading change in radians.
pub fn cumulative_heading_change(waypoints: &[Vec3], from: usize, to: usize) -> f32 {
    if to <= from + 1 || to >= waypoints.len() {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_flat_terrain_no_scaling() {
        let a = Vec3::new(0.0, 0.0, 100.0);
        let b = Vec3::new(10.0, 0.0, 100.0);
        let analysis = TerrainAnalysis::analyze_segment(&a, &b);
        assert!(analysis.slope_ratio < 0.01);
        assert_eq!(analysis.scale_density(8, 0.3), 8);
    }

    #[test]
    fn test_stairs_detected() {
        let a = Vec3::new(0.0, 0.0, 100.0);
        let b = Vec3::new(5.0, 0.0, 104.0);
        let analysis = TerrainAnalysis::analyze_segment(&a, &b);
        assert!(analysis.slope_ratio > 0.3);
        assert_eq!(analysis.scale_density(8, 0.3), 16);
    }

    #[test]
    fn test_density_cap_at_32() {
        let a = Vec3::new(0.0, 0.0, 100.0);
        let b = Vec3::new(1.0, 0.0, 110.0);
        let analysis = TerrainAnalysis::analyze_segment(&a, &b);
        assert_eq!(analysis.scale_density(20, 0.3), 32);
    }

    #[test]
    fn test_coincident_points() {
        let a = Vec3::new(5.0, 5.0, 100.0);
        let b = Vec3::new(5.0, 5.0, 100.0);
        let analysis = TerrainAnalysis::analyze_segment(&a, &b);
        assert!(analysis.slope_ratio < 0.01);
    }

    #[test]
    fn test_heading_change_straight_line() {
        let waypoints = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
            Vec3::new(2.0, 0.0, 0.0),
            Vec3::new(3.0, 0.0, 0.0),
        ];
        let change = cumulative_heading_change(&waypoints, 0, 3);
        assert!(change < 0.01);
    }

    #[test]
    fn test_heading_change_right_angle() {
        let waypoints = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 10.0, 0.0),
            Vec3::new(10.0, 20.0, 0.0),
        ];
        let change = cumulative_heading_change(&waypoints, 0, 3);
        assert!((change - std::f32::consts::FRAC_PI_2).abs() < 0.1);
    }
}
