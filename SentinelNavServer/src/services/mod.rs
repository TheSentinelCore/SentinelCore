//! Service trait definitions and request/result types.
//!
//! Decomposes the monolithic `pipeline.rs` into trait-based services with
//! dependency injection. Each service handles one domain:
//!
//! - **PathfindingService**: Core A*-to-waypoint pipeline (find, avoid, corridor, check)
//! - **RoutingService**: Multi-stop and TSP optimization
//! - **SpatialService**: Low-level navmesh queries (raycast, height, random, move)
//! - **TacticalService**: Combat-oriented path generation (flee, cover, kite)
//! - **CacheService**: Path result caching with spatial quantization

use detour::types::Vec3;

use crate::error::AppError;
use crate::pipeline::{AvoidanceZone, PathOptions, PathResult};

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

/// Core pathfinding request.
#[derive(Debug, Clone)]
pub struct PathRequest {
    pub map_id: u32,
    pub start: Vec3,
    pub end: Vec3,
    pub options: PathOptions,
}

/// Pathfinding with avoidance zones.
#[derive(Debug, Clone)]
pub struct AvoidanceRequest {
    pub map_id: u32,
    pub start: Vec3,
    pub end: Vec3,
    pub zones: Vec<AvoidanceZone>,
    pub options: PathOptions,
}

/// Path with corridor width computation.
#[derive(Debug, Clone)]
pub struct CorridorRequest {
    pub map_id: u32,
    pub start: Vec3,
    pub end: Vec3,
    pub probe_distance: f32,
    pub options: PathOptions,
}

/// Check connectivity between two points.
#[derive(Debug, Clone)]
pub struct ConnectivityRequest {
    pub map_id: u32,
    pub waypoints: Vec<Vec3>,
}

/// Ordered multi-stop path request.
#[derive(Debug, Clone)]
pub struct MultiStopRequest {
    pub map_id: u32,
    pub stops: Vec<Vec3>,
    pub options: PathOptions,
}

/// TSP-optimized multi-stop path request.
#[derive(Debug, Clone)]
pub struct TspRequest {
    pub map_id: u32,
    pub stops: Vec<Vec3>,
    pub options: PathOptions,
}

/// Raycast (line-of-sight) request.
#[derive(Debug, Clone)]
pub struct RaycastRequest {
    pub map_id: u32,
    pub start: Vec3,
    pub end: Vec3,
}

/// Single height query.
#[derive(Debug, Clone)]
pub struct HeightRequest {
    pub map_id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// Batch height query.
#[derive(Debug, Clone)]
pub struct BatchHeightRequest {
    pub map_id: u32,
    pub positions: Vec<Vec3>,
}

/// Random point on navmesh.
#[derive(Debug, Clone)]
pub struct RandomPointRequest {
    pub map_id: u32,
    pub center: Vec3,
    pub radius: f32,
}

/// Move along navmesh surface.
#[derive(Debug, Clone)]
pub struct MoveRequest {
    pub map_id: u32,
    pub start: Vec3,
    pub end: Vec3,
}

/// Flee from threats.
#[derive(Debug, Clone)]
pub struct FleeRequest {
    pub map_id: u32,
    pub player_pos: Vec3,
    pub threats: Vec<Vec3>,
    pub flee_distance: f32,
    pub options: PathOptions,
}

/// Find cover from a threat (line-of-sight based).
#[derive(Debug, Clone)]
pub struct CoverRequest {
    pub map_id: u32,
    pub player_pos: Vec3,
    pub threat_pos: Vec3,
    pub search_radius: f32,
    pub num_samples: usize,
    pub options: PathOptions,
}

/// Kite (arc movement) around a threat.
#[derive(Debug, Clone)]
pub struct KiteRequest {
    pub map_id: u32,
    pub player_pos: Vec3,
    pub threat_pos: Vec3,
    pub desired_distance: f32,
    pub arc_angle: f32,
    pub num_arc_points: usize,
    pub options: PathOptions,
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Path with corridor widths at each waypoint.
#[derive(Debug, Clone)]
pub struct CorridorResult {
    pub path: PathResult,
    pub corridor_widths: Vec<f32>,
}

/// Multi-stop path result with per-leg breakdown.
#[derive(Debug, Clone)]
pub struct MultiStopResult {
    pub waypoints: Vec<Vec3>,
    pub total_distance: f32,
    pub leg_distances: Vec<f32>,
    pub leg_boundaries: Vec<usize>,
    pub partial: bool,
}

/// Raycast result.
#[derive(Debug, Clone)]
pub struct RaycastResult {
    pub hit: bool,
    /// Parametric hit distance [0..1] along the segment.
    pub t: f32,
    /// World-space distance from start to hit (or full segment length if no hit).
    pub hit_distance: f32,
    /// Hit position (if hit) or end position (if no hit).
    pub hit_position: Vec3,
}

/// Single height result.
#[derive(Debug, Clone)]
pub struct HeightResult {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub found: bool,
}

/// Move-along-surface result.
#[derive(Debug, Clone)]
pub struct MoveResult {
    pub position: Vec3,
    pub visited_count: usize,
}

/// Cover position candidate.
#[derive(Debug, Clone)]
pub struct CoverPosition {
    pub position: Vec3,
    pub distance_to_threat: f32,
    pub has_los: bool,
}

/// Cover search result.
#[derive(Debug, Clone)]
pub struct CoverResult {
    pub positions: Vec<CoverPosition>,
    pub path: Option<PathResult>,
}

/// Kite result.
#[derive(Debug, Clone)]
pub struct KiteResult {
    pub path: PathResult,
    pub arc_points: Vec<Vec3>,
}

/// Flee result.
#[derive(Debug, Clone)]
pub struct FleeResult {
    pub path: PathResult,
    pub flee_point: Vec3,
    pub distance_from_threat: f32,
}

/// Cache statistics.
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub hits: u64,
    pub misses: u64,
    pub size: usize,
}

// ---------------------------------------------------------------------------
// Service traits
// ---------------------------------------------------------------------------

/// Core pathfinding: A* search → straight path → optimize → smooth → project.
///
/// Implementations own an `Arc<MmapManager>` and handle mesh loading, query pool
/// acquisition, and filter resolution internally.
pub trait PathfindingService: Send + Sync {
    /// Find a path between two points.
    fn find_path(&self, req: PathRequest) -> Result<PathResult, AppError>;

    /// Find a path while routing around avoidance zones.
    fn find_path_with_avoidance(&self, req: AvoidanceRequest) -> Result<PathResult, AppError>;

    /// Find a path and compute corridor widths at each waypoint.
    fn find_corridor(&self, req: CorridorRequest) -> Result<CorridorResult, AppError>;

    /// Check whether a sequence of waypoints remains on the navmesh.
    fn check_connectivity(&self, req: ConnectivityRequest) -> Result<Vec<bool>, AppError>;
}

/// Multi-stop and TSP route optimization.
pub trait RoutingService: Send + Sync {
    /// Compute a path visiting stops in the given order.
    fn multi_stop(&self, req: MultiStopRequest) -> Result<MultiStopResult, AppError>;

    /// Compute a TSP-optimized route visiting all stops.
    fn tsp_optimize(&self, req: TspRequest) -> Result<MultiStopResult, AppError>;
}

/// Low-level navmesh spatial queries.
pub trait SpatialService: Send + Sync {
    /// Raycast between two points. Returns hit info.
    fn raycast(&self, req: RaycastRequest) -> Result<RaycastResult, AppError>;

    /// Get navmesh height at a position.
    fn get_height(&self, req: HeightRequest) -> Result<HeightResult, AppError>;

    /// Get heights at multiple positions.
    fn get_heights(&self, req: BatchHeightRequest) -> Result<Vec<HeightResult>, AppError>;

    /// Find a random point on the navmesh within a radius.
    fn random_point(&self, req: RandomPointRequest) -> Result<Vec3, AppError>;

    /// Move along the navmesh surface from start toward end.
    fn move_along_surface(&self, req: MoveRequest) -> Result<MoveResult, AppError>;
}

/// Combat-oriented tactical pathfinding.
pub trait TacticalService: Send + Sync {
    /// Find a flee path away from threats.
    fn flee(&self, req: FleeRequest) -> Result<FleeResult, AppError>;

    /// Find cover positions that break line-of-sight to a threat.
    fn find_cover(&self, req: CoverRequest) -> Result<CoverResult, AppError>;

    /// Generate kite arc waypoints around a threat.
    fn kite(&self, req: KiteRequest) -> Result<KiteResult, AppError>;
}

/// Path result caching with spatial quantization.
pub trait CacheService: Send + Sync {
    /// Look up a cached path. Returns None on miss.
    fn get(&self, map_id: u32, start: &Vec3, end: &Vec3, options_hash: u64) -> Option<crate::cache::CachedPath>;

    /// Insert a path into the cache.
    fn put(&self, map_id: u32, start: &Vec3, end: &Vec3, options_hash: u64, path: crate::cache::CachedPath);

    /// Get cache statistics.
    fn stats(&self) -> CacheStats;
}

// ---------------------------------------------------------------------------
// Implementations (each in its own file)
// ---------------------------------------------------------------------------

pub mod pathfinding;
pub mod routing;
pub mod spatial;
pub mod tactical;
pub mod cache_impl;
