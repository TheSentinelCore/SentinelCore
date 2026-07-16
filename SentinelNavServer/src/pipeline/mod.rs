//! Shared pathfinding pipeline used by all path endpoints.
//!
//! Extracts the core find → straight → optimize → smooth → project → validate
//! pipeline so it can be reused by path, path-random, path-multi, path-tsp, etc.

pub mod avoidance;
pub mod filter;
pub mod parsing;
pub mod pathfinding;
pub mod post_process;
pub mod string_pull;
pub mod tsp;
pub mod wall_clearance;

use detour::types::Vec3;

// Re-export types
pub use avoidance::AvoidanceZone;

// Re-export constants from filter
pub use filter::{
    DEFAULT_GROUND_COST, DEFAULT_LAVA_COST, DEFAULT_WATER_COST, HEIGHT_EXTENTS, MAX_PATH_POLYS,
    MAX_STRAIGHT_PATH, SEARCH_EXTENTS, SEARCH_TIERS,
};

// Re-export core pathfinding functions
pub use pathfinding::{
    execute_pathfind, execute_pathfind_raw, find_poly_tiered, post_process_path,
};

// Re-export avoidance functions
pub use avoidance::{
    execute_pathfind_with_avoidance, execute_pathfind_with_avoidance_raw, pathfind_maybe_avoid,
    pathfind_maybe_avoid_raw,
};

// Re-export filter functions
pub use filter::{create_custom_filter, has_custom_filter, resolve_filter};

// Re-export parsing functions
pub use parsing::{parse_avoidance_zones, parse_stops, parse_threats, parse_waypoints};

// Re-export post-processing functions
pub use post_process::{calculate_path_distance, compute_corridor_widths, densify_segments};

// Re-export string-pull and wall-clearance
pub use string_pull::string_pull_path;
pub use wall_clearance::apply_wall_clearance;

// Re-export TSP solver
pub use tsp::solve_tsp;

/// Options controlling how a path is computed.
#[derive(Debug, Clone, Default)]
pub struct PathOptions {
    /// Enable string-pulling optimization.
    pub optimize: bool,
    /// Ground area cost multiplier.
    pub filter_ground: Option<f32>,
    /// Water area cost multiplier.
    pub filter_water: Option<f32>,
    /// Lava area cost multiplier.
    pub filter_lava: Option<f32>,
    /// Custom Z search extent override. When set, skips tiered fallback
    /// and uses this value directly. Useful for indoor/multi-floor scenarios.
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled).
    /// Pushes waypoints away from nearby walls using Detour's findDistanceToWall.
    pub wall_clearance: Option<f32>,
    /// Max 3D deviation (yards) for string-pull optimization (default 1.5).
    /// Lower = tighter corners, higher = smoother but cuts corners more.
    pub string_pull_deviation: Option<f32>,
    /// Max heading change (degrees) for string-pull optimization (default 30).
    /// Lower = preserves more curves, higher = straighter paths.
    pub string_pull_heading: Option<f32>,
    /// Min wall distance (yards) for string-pull shortcuts (default 0.6).
    /// During optimization, if a proposed shortcut line passes closer to a wall
    /// than this threshold, the shortcut is rejected and intermediate waypoints
    /// are preserved. 0 = disabled.
    pub string_pull_wall_dist: Option<f32>,
    /// Max segment length (yards) for densification (default 3.0).
    /// Segments longer than this are split with midpoints projected to the navmesh.
    /// Lower = more waypoints on curves, higher = fewer waypoints.
    pub densify_segment_length: Option<f32>,
}

impl PathOptions {
    /// Compute a hash of all options that affect path output, for use as a cache key.
    pub fn cache_hash(&self) -> u64 {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        let mut h = DefaultHasher::new();
        self.optimize.hash(&mut h);
        self.wall_clearance.map(|v| v.to_bits()).hash(&mut h);
        self.string_pull_deviation
            .map(|v| v.to_bits())
            .hash(&mut h);
        self.string_pull_heading.map(|v| v.to_bits()).hash(&mut h);
        self.string_pull_wall_dist
            .map(|v| v.to_bits())
            .hash(&mut h);
        self.densify_segment_length
            .map(|v| v.to_bits())
            .hash(&mut h);
        self.filter_ground.map(|v| v.to_bits()).hash(&mut h);
        self.filter_water.map(|v| v.to_bits()).hash(&mut h);
        self.filter_lava.map(|v| v.to_bits()).hash(&mut h);
        self.z_extent.map(|v| v.to_bits()).hash(&mut h);
        h.finish()
    }
}

/// Result of a pathfinding computation.
#[derive(Debug, Clone)]
pub struct PathResult {
    pub waypoints: Vec<Vec3>,
    pub distance: f32,
    pub partial: bool,
    /// True if partial result was caused by A* node pool exhaustion.
    pub out_of_nodes: bool,
}
