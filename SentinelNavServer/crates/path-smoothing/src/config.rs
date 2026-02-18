//! Configuration for the combined smoothing pipeline.

/// Configuration for the 4-stage smoothing pipeline.
///
/// Controls Chaikin corner-cutting, centripetal Catmull-Rom interpolation,
/// height reprojection, and navmesh validation.
#[derive(Debug, Clone)]
pub struct SmootherConfig {
    // === Chaikin (Stage 1) ===
    /// Number of corner-cutting iterations (1-5). Default: 2.
    pub chaikin_iterations: u32,
    /// Corner-cut ratio (0.5-0.95). Higher = tighter to original. Default: 0.75.
    pub chaikin_ratio: f32,
    /// Minimum angle (degrees) to smooth. Below this, corner is preserved. Default: 30.0.
    pub chaikin_angle_threshold: f32,
    /// Angles sharper than this (degrees) are rejected entirely. Default: 90.0.
    pub chaikin_outlier_angle: f32,

    // === Catmull-Rom (Stage 2) ===
    /// Alpha for knot spacing. 0.5 = centripetal (guaranteed no cusps). Default: 0.5.
    pub catmull_rom_alpha: f32,
    /// Tension. 0.0 = natural curves, 1.0 = straight lines. Default: 0.0.
    pub catmull_rom_tension: f32,
    /// Base interpolated points per segment. Default: 4.
    pub catmull_rom_points_per_segment: usize,
    /// Scale density on steep terrain (stairs, ramps). Default: false.
    pub catmull_rom_adaptive_density: bool,

    // === Reprojection (Stage 3) ===
    /// Search extents [x, y, z] for find_nearest_poly. Default: [2.0, 4.0, 2.0].
    pub reprojection_extents: [f32; 3],
    /// Slope ratio above which terrain is classified as stairs. Default: 0.3.
    pub stair_detection_threshold: f32,

    // === Validation (Stage 4) ===
    /// Enable raycast validation. Default: true.
    pub validate_on_navmesh: bool,
    /// Fall back to pre-smoothed segment on wall hit. Default: true.
    pub fallback_on_invalid: bool,
    /// Max XY deviation (yards) from original path. Default: 5.0.
    pub max_deviation_from_original: f32,
}

impl Default for SmootherConfig {
    fn default() -> Self {
        Self {
            chaikin_iterations: 2,
            chaikin_ratio: 0.75,
            chaikin_angle_threshold: 30.0,
            chaikin_outlier_angle: 90.0,

            catmull_rom_alpha: 0.5,
            catmull_rom_tension: 0.0,
            catmull_rom_points_per_segment: 4,
            catmull_rom_adaptive_density: false,

            reprojection_extents: [2.0, 4.0, 2.0],
            stair_detection_threshold: 0.3,

            validate_on_navmesh: true,
            fallback_on_invalid: true,
            max_deviation_from_original: 5.0,
        }
    }
}

impl SmootherConfig {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_chaikin_iterations(mut self, n: u32) -> Self {
        self.chaikin_iterations = n;
        self
    }
    pub fn with_chaikin_ratio(mut self, r: f32) -> Self {
        self.chaikin_ratio = r;
        self
    }
    pub fn with_chaikin_angle_threshold(mut self, deg: f32) -> Self {
        self.chaikin_angle_threshold = deg;
        self
    }
    pub fn with_chaikin_outlier_angle(mut self, deg: f32) -> Self {
        self.chaikin_outlier_angle = deg;
        self
    }
    pub fn with_catmull_rom_alpha(mut self, a: f32) -> Self {
        self.catmull_rom_alpha = a;
        self
    }
    pub fn with_catmull_rom_tension(mut self, t: f32) -> Self {
        self.catmull_rom_tension = t;
        self
    }
    pub fn with_catmull_rom_points_per_segment(mut self, n: usize) -> Self {
        self.catmull_rom_points_per_segment = n;
        self
    }
    pub fn with_catmull_rom_adaptive_density(mut self, enabled: bool) -> Self {
        self.catmull_rom_adaptive_density = enabled;
        self
    }
    pub fn with_reprojection_extents(mut self, extents: [f32; 3]) -> Self {
        self.reprojection_extents = extents;
        self
    }
    pub fn with_stair_detection_threshold(mut self, t: f32) -> Self {
        self.stair_detection_threshold = t;
        self
    }
    pub fn with_validate_on_navmesh(mut self, enabled: bool) -> Self {
        self.validate_on_navmesh = enabled;
        self
    }
    pub fn with_max_deviation(mut self, d: f32) -> Self {
        self.max_deviation_from_original = d;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let cfg = SmootherConfig::default();
        assert_eq!(cfg.chaikin_iterations, 2);
        assert!((cfg.chaikin_ratio - 0.75).abs() < f32::EPSILON);
        assert!((cfg.catmull_rom_alpha - 0.5).abs() < f32::EPSILON);
        assert!(cfg.validate_on_navmesh);
    }

    #[test]
    fn test_builder_pattern() {
        let cfg = SmootherConfig::new()
            .with_chaikin_iterations(3)
            .with_catmull_rom_alpha(0.0)
            .with_validate_on_navmesh(false);
        assert_eq!(cfg.chaikin_iterations, 3);
        assert!((cfg.catmull_rom_alpha - 0.0).abs() < f32::EPSILON);
        assert!(!cfg.validate_on_navmesh);
    }
}
