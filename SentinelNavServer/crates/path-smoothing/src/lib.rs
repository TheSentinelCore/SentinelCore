//! Path smoothing pipeline for human-like navigation movement.
//!
//! Provides a combined 4-stage pipeline:
//! 1. Chaikin corner-cutting with angle filtering and outlier rejection
//! 2. Centripetal Catmull-Rom interpolation with adaptive density
//! 3. Height reprojection onto navmesh detail mesh
//! 4. Raycast validation with original-path fallback
//!
//! ## Usage
//!
//! ```ignore
//! let pipeline = SmootherPipeline::with_default_config();
//! let smoothed = pipeline.smooth(&waypoints, &query, &filter);
//! ```

pub mod config;
pub mod pipeline;
pub mod chaikin;
pub mod catmull_rom;
pub mod bezier;
pub mod decimation;
pub mod reprojection;
pub mod validation;
pub mod metrics;
pub mod terrain;

// Primary API
pub use config::SmootherConfig;
pub use pipeline::SmootherPipeline;
pub use metrics::PathMetrics;

// Standalone algorithm (not part of pipeline)
pub use bezier::smooth_bezier;

// === Deprecated compat — remove in next major version ===

pub use chaikin::smooth_chaikin;

#[allow(deprecated)]
pub use catmull_rom::smooth_catmull_rom;

/// Default iterations for Chaikin algorithm.
pub const DEFAULT_CHAIKIN_ITERATIONS: u32 = 2;
/// Default corner-cut ratio for Chaikin algorithm.
pub const DEFAULT_CHAIKIN_RATIO: f32 = 0.75;
/// Default samples per segment for Catmull-Rom spline.
pub const DEFAULT_CATMULL_ROM_SAMPLES: u32 = 10;
/// Default samples per segment for Bezier curves.
pub const DEFAULT_BEZIER_SAMPLES: u32 = 10;

use detour::Vec3;

/// Deprecated. Use [`SmootherConfig`] instead.
#[derive(Debug, Clone, Copy, Default)]
pub struct SmoothingConfig {
    pub chaikin_iterations: Option<u32>,
    pub chaikin_ratio: Option<f32>,
    pub min_corner_angle: Option<f32>,
    pub keep_originals: Option<bool>,
    pub catmull_rom_samples: Option<u32>,
    pub bezier_samples: Option<u32>,
}

impl SmoothingConfig {
    pub fn new() -> Self { Self::default() }
    pub fn with_chaikin_iterations(mut self, i: u32) -> Self { self.chaikin_iterations = Some(i); self }
    pub fn with_chaikin_ratio(mut self, r: f32) -> Self { self.chaikin_ratio = Some(r); self }
    pub fn with_min_corner_angle(mut self, a: f32) -> Self { self.min_corner_angle = Some(a); self }
    pub fn with_keep_originals(mut self, k: bool) -> Self { self.keep_originals = Some(k); self }
    pub fn with_catmull_rom_samples(mut self, s: u32) -> Self { self.catmull_rom_samples = Some(s); self }
    pub fn with_bezier_samples(mut self, s: u32) -> Self { self.bezier_samples = Some(s); self }
    pub fn get_chaikin_iterations(&self) -> usize { self.chaikin_iterations.unwrap_or(DEFAULT_CHAIKIN_ITERATIONS) as usize }
    pub fn get_chaikin_ratio(&self) -> f32 { self.chaikin_ratio.unwrap_or(DEFAULT_CHAIKIN_RATIO) }
    pub fn get_min_corner_angle(&self) -> f32 { self.min_corner_angle.unwrap_or(0.0) }
    pub fn get_keep_originals(&self) -> bool { self.keep_originals.unwrap_or(false) }
    pub fn get_catmull_rom_samples(&self) -> usize { self.catmull_rom_samples.unwrap_or(DEFAULT_CATMULL_ROM_SAMPLES) as usize }
    pub fn get_bezier_samples(&self) -> usize { self.bezier_samples.unwrap_or(DEFAULT_BEZIER_SAMPLES) as usize }
}

/// Deprecated. Use [`SmootherPipeline`] instead.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SmoothingAlgorithm {
    #[default]
    None,
    Chaikin,
    CatmullRom,
    Bezier,
}

impl SmoothingAlgorithm {
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "chaikin" => Self::Chaikin,
            "catmull_rom" | "catmullrom" | "catmull-rom" => Self::CatmullRom,
            "bezier" => Self::Bezier,
            _ => Self::None,
        }
    }

    pub fn smooth(&self, path: &[Vec3]) -> Vec<Vec3> {
        self.smooth_with_config(path, &SmoothingConfig::default())
    }

    #[allow(deprecated)]
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
            Self::CatmullRom => catmull_rom::smooth_catmull_rom_centripetal(
                path, 0.5, 0.0,
                config.get_catmull_rom_samples(),
                false, 0.3,
            ),
            Self::Bezier => smooth_bezier(path, config.get_bezier_samples()),
        }
    }
}
