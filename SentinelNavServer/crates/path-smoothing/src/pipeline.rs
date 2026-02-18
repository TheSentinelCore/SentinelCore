//! Combined 4-stage smoothing pipeline.
//!
//! Stages:
//! 1. Chaikin corner-cutting (angle filtering + outlier rejection)
//! 2. Centripetal Catmull-Rom interpolation (adaptive density)
//! 3. Height reprojection (detail mesh sampling)
//! 4. Raycast validation (original-path fallback)

use detour::query::NavMeshQuery;
use detour::filter::QueryFilter;
use detour::types::Vec3;

use crate::chaikin;
use crate::catmull_rom;
use crate::config::SmootherConfig;
use crate::metrics::PathMetrics;
use crate::reprojection;
use crate::validation;

/// Combined smoothing pipeline.
///
/// Replaces individual algorithm selection with a fixed 4-stage pipeline
/// that produces smooth, height-accurate, navmesh-validated paths.
pub struct SmootherPipeline {
    config: SmootherConfig,
}

impl SmootherPipeline {
    /// Create a pipeline with the given configuration.
    pub fn new(config: SmootherConfig) -> Self {
        Self { config }
    }

    /// Create a pipeline with default configuration.
    pub fn with_default_config() -> Self {
        Self {
            config: SmootherConfig::default(),
        }
    }

    /// Run the full 4-stage smoothing pipeline.
    ///
    /// Infallible — individual stages degrade gracefully on errors.
    /// Short paths (< 3 points) are returned unchanged.
    pub fn smooth(
        &self,
        waypoints: &[Vec3],
        query: &NavMeshQuery,
        filter: &QueryFilter,
    ) -> Vec<Vec3> {
        if waypoints.len() < 3 {
            return waypoints.to_vec();
        }

        let original = waypoints.to_vec();

        // Stage 1: Outlier rejection (remove glitch/hairpin waypoints)
        let after_rejection = chaikin::reject_outliers(waypoints, self.config.chaikin_outlier_angle);

        // Stage 2: Centripetal Catmull-Rom interpolation
        let after_catmull = catmull_rom::smooth_catmull_rom_centripetal(
            &after_rejection,
            self.config.catmull_rom_alpha,
            self.config.catmull_rom_tension,
            self.config.catmull_rom_points_per_segment,
            self.config.catmull_rom_adaptive_density,
            self.config.stair_detection_threshold,
        );

        // Stage 3: Height reprojection
        let mut reprojected = after_catmull;
        reprojection::reproject_heights(
            &mut reprojected,
            query,
            filter,
            self.config.reprojection_extents,
        );

        // Stage 4: Validation
        if self.config.validate_on_navmesh {
            validation::validate_path(
                &reprojected,
                &original,
                query,
                filter,
                self.config.reprojection_extents,
                self.config.max_deviation_from_original,
                self.config.fallback_on_invalid,
            )
        } else {
            reprojected
        }
    }

    /// Run the pipeline and compute quality metrics.
    pub fn smooth_with_metrics(
        &self,
        waypoints: &[Vec3],
        query: &NavMeshQuery,
        filter: &QueryFilter,
    ) -> (Vec<Vec3>, PathMetrics) {
        let original = waypoints.to_vec();
        let smoothed = self.smooth(waypoints, query, filter);
        let metrics = PathMetrics::compute(&smoothed, &original);
        (smoothed, metrics)
    }
}
