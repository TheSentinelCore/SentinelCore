//! Path smoothing algorithms for human-like movement.
//!
//! This crate provides several smoothing algorithms that can be applied
//! to navigation paths to make them look more natural.

pub mod chaikin;
pub mod catmull_rom;
pub mod bezier;

pub use chaikin::smooth_chaikin;
pub use catmull_rom::smooth_catmull_rom;
pub use bezier::smooth_bezier;

use detour::Vec3;

/// Default iterations for Chaikin algorithm.
pub const DEFAULT_CHAIKIN_ITERATIONS: u32 = 2;

/// Default corner-cut ratio for Chaikin algorithm.
pub const DEFAULT_CHAIKIN_RATIO: f32 = 0.75;

/// Default samples per segment for Catmull-Rom spline.
pub const DEFAULT_CATMULL_ROM_SAMPLES: u32 = 10;

/// Default samples per segment for Bezier curves.
pub const DEFAULT_BEZIER_SAMPLES: u32 = 10;

/// Configuration for smoothing algorithms.
#[derive(Debug, Clone, Copy, Default)]
pub struct SmoothingConfig {
    /// Number of iterations for Chaikin algorithm (1-5, default 2).
    /// More iterations = smoother curve but more waypoints.
    pub chaikin_iterations: Option<u32>,

    /// Corner-cut ratio for Chaikin algorithm (0.5-0.95, default 0.75).
    /// Higher = stays closer to original path (tighter corners).
    /// Lower = more aggressive smoothing.
    pub chaikin_ratio: Option<f32>,

    /// Minimum corner angle to smooth (degrees, 0-180, default 0 = smooth all).
    /// Corners sharper than this angle won't be smoothed, preserving navmesh accuracy.
    /// This prevents path smoothing from cutting through walls at tight corners.
    pub min_corner_angle: Option<f32>,

    /// If true, preserve original waypoints and only insert interpolation points.
    /// Guarantees path passes through navmesh-validated positions.
    pub keep_originals: Option<bool>,

    /// Number of interpolated points per segment for Catmull-Rom (5-50, default 10).
    /// More samples = smoother curve but more waypoints.
    pub catmull_rom_samples: Option<u32>,

    /// Number of interpolated points per segment for Bezier (5-50, default 10).
    /// More samples = smoother curve but more waypoints.
    pub bezier_samples: Option<u32>,
}

impl SmoothingConfig {
    /// Create a new config with default values.
    pub fn new() -> Self {
        Self::default()
    }

    /// Set Chaikin iterations.
    pub fn with_chaikin_iterations(mut self, iterations: u32) -> Self {
        self.chaikin_iterations = Some(iterations);
        self
    }

    /// Set Chaikin corner-cut ratio.
    pub fn with_chaikin_ratio(mut self, ratio: f32) -> Self {
        self.chaikin_ratio = Some(ratio);
        self
    }

    /// Set minimum corner angle for Chaikin smoothing.
    pub fn with_min_corner_angle(mut self, angle: f32) -> Self {
        self.min_corner_angle = Some(angle);
        self
    }

    /// Set keep_originals mode for Chaikin smoothing.
    pub fn with_keep_originals(mut self, keep: bool) -> Self {
        self.keep_originals = Some(keep);
        self
    }

    /// Set Catmull-Rom samples per segment.
    pub fn with_catmull_rom_samples(mut self, samples: u32) -> Self {
        self.catmull_rom_samples = Some(samples);
        self
    }

    /// Set Bezier samples per segment.
    pub fn with_bezier_samples(mut self, samples: u32) -> Self {
        self.bezier_samples = Some(samples);
        self
    }

    /// Get Chaikin iterations with default fallback.
    pub fn get_chaikin_iterations(&self) -> usize {
        self.chaikin_iterations.unwrap_or(DEFAULT_CHAIKIN_ITERATIONS) as usize
    }

    /// Get Chaikin ratio with default fallback.
    pub fn get_chaikin_ratio(&self) -> f32 {
        self.chaikin_ratio.unwrap_or(DEFAULT_CHAIKIN_RATIO)
    }

    /// Get minimum corner angle with default fallback (0 = smooth all corners).
    pub fn get_min_corner_angle(&self) -> f32 {
        self.min_corner_angle.unwrap_or(0.0)
    }

    /// Get keep_originals mode with default fallback (false).
    pub fn get_keep_originals(&self) -> bool {
        self.keep_originals.unwrap_or(false)
    }

    /// Get Catmull-Rom samples with default fallback.
    pub fn get_catmull_rom_samples(&self) -> usize {
        self.catmull_rom_samples.unwrap_or(DEFAULT_CATMULL_ROM_SAMPLES) as usize
    }

    /// Get Bezier samples with default fallback.
    pub fn get_bezier_samples(&self) -> usize {
        self.bezier_samples.unwrap_or(DEFAULT_BEZIER_SAMPLES) as usize
    }
}

/// Available smoothing algorithms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SmoothingAlgorithm {
    #[default]
    None,
    Chaikin,
    CatmullRom,
    Bezier,
}

impl SmoothingAlgorithm {
    /// Parse from string.
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "chaikin" => Self::Chaikin,
            "catmull_rom" | "catmullrom" | "catmull-rom" => Self::CatmullRom,
            "bezier" => Self::Bezier,
            _ => Self::None,
        }
    }

    /// Apply smoothing to a path with default configuration.
    pub fn smooth(&self, path: &[Vec3]) -> Vec<Vec3> {
        self.smooth_with_config(path, &SmoothingConfig::default())
    }

    /// Apply smoothing to a path with custom configuration.
    pub fn smooth_with_config(&self, path: &[Vec3], config: &SmoothingConfig) -> Vec<Vec3> {
        match self {
            Self::None => path.to_vec(),
            Self::Chaikin => smooth_chaikin(
                path,
                config.get_chaikin_iterations(),
                config.get_chaikin_ratio(),
                config.get_min_corner_angle(),
                config.get_keep_originals(),
            ),
            Self::CatmullRom => smooth_catmull_rom(path, config.get_catmull_rom_samples()),
            Self::Bezier => smooth_bezier(path, config.get_bezier_samples()),
        }
    }
}
