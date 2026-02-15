//! Spatial query endpoints.
//!
//! These endpoints provide lower-level navmesh operations beyond pathfinding:
//! - Move along surface (sliding movement)
//! - Raycast (line of sight checks)
//! - Random point generation
//! - Height queries
//! - Polygon exploration

use axum::{
    extract::{Query, State},
    Json,
};
use detour::types::Vec3;
use polygon_sampling::SamplingConfig;
use serde::{Deserialize, Deserializer, Serialize};
use tc_mmap::error::MmapError;

use crate::error::AppError;
use crate::state::AppState;
use crate::validation::{
    validate_coordinate, validate_map_id, validate_min_distance, validate_polygon, validate_radius,
};

/// Search extents for finding polygons.
const SEARCH_EXTENTS: Vec3 = Vec3 {
    x: 50.0,
    y: 50.0,
    z: 50.0,
};

// ============================================================================
// Move Along Surface
// ============================================================================

/// Request for move along surface endpoint.
#[derive(Debug, Deserialize)]
pub struct MoveRequest {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
}

/// Response for move along surface endpoint.
#[derive(Debug, Serialize)]
pub struct MoveResponse {
    pub success: bool,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// GET /api/v1/move - Move along the navmesh surface.
///
/// This performs a "sliding" movement that stays constrained to the navmesh.
/// Useful for simulating player movement that can't pass through walls.
pub async fn move_along_surface(
    State(state): State<AppState>,
    Query(params): Query<MoveRequest>,
) -> Result<Json<MoveResponse>, AppError> {
    // Validate inputs
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_coordinate(params.end_x, params.end_y, params.end_z)?;

    // Acquire concurrency permit
    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // Load map
    let _mesh = state
        .mmap_manager
        .get_or_load_mesh(params.map_id)
        .map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(params.map_id),
            _ => AppError::Internal(e.to_string()),
        })?;

    // Get query pool
    let pool = state
        .mmap_manager
        .get_query_pool(params.map_id)
        .ok_or_else(|| AppError::MapNotFound(params.map_id))?;

    let query = pool
        .acquire()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let filter = pool.filter();

    let start = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end = Vec3::new(params.end_x, params.end_y, params.end_z);

    // Find starting polygon
    let (start_ref, _) = query
        .find_nearest_poly(start, SEARCH_EXTENTS, filter)
        .map_err(|_| AppError::PathfindingFailed("Start position not on navmesh".into()))?;

    // Move along surface
    let result_pos = query
        .move_along_surface(start_ref, start, end, filter)
        .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

    Ok(Json(MoveResponse {
        success: true,
        x: result_pos.x,
        y: result_pos.y,
        z: result_pos.z,
    }))
}

// ============================================================================
// Raycast
// ============================================================================

/// Request for raycast endpoint.
#[derive(Debug, Deserialize)]
pub struct RaycastRequest {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
}

/// Response for raycast endpoint.
#[derive(Debug, Serialize)]
pub struct RaycastResponse {
    /// Whether the ray hit something before reaching the end point.
    pub hit: bool,
    /// Hit position (or end position if no hit).
    pub hit_x: f32,
    pub hit_y: f32,
    pub hit_z: f32,
    /// Hit parameter (0.0-1.0 for hit, >= 1.0 for no hit).
    pub t: f32,
    /// Hit normal (only meaningful if hit is true).
    pub normal_x: f32,
    pub normal_y: f32,
    pub normal_z: f32,
}

/// GET /api/v1/raycast - Cast a ray along the navmesh.
///
/// Returns where the ray hits a navmesh boundary or reaches the end point.
/// Useful for line-of-sight checks and obstacle detection.
pub async fn raycast(
    State(state): State<AppState>,
    Query(params): Query<RaycastRequest>,
) -> Result<Json<RaycastResponse>, AppError> {
    // Validate inputs
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_coordinate(params.end_x, params.end_y, params.end_z)?;

    // Acquire concurrency permit
    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // Load map
    let _mesh = state
        .mmap_manager
        .get_or_load_mesh(params.map_id)
        .map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(params.map_id),
            _ => AppError::Internal(e.to_string()),
        })?;

    // Get query pool
    let pool = state
        .mmap_manager
        .get_query_pool(params.map_id)
        .ok_or_else(|| AppError::MapNotFound(params.map_id))?;

    let query = pool
        .acquire()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let filter = pool.filter();

    let start = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end = Vec3::new(params.end_x, params.end_y, params.end_z);

    // Find starting polygon
    let (start_ref, _) = query
        .find_nearest_poly(start, SEARCH_EXTENTS, filter)
        .map_err(|_| AppError::PathfindingFailed("Start position not on navmesh".into()))?;

    // Perform raycast
    let (t, hit_normal) = query
        .raycast(start_ref, start, end, filter)
        .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

    // Calculate hit position
    let hit = t < 1.0;
    let hit_pos = if hit {
        // Interpolate along ray
        Vec3::new(
            start.x + (end.x - start.x) * t,
            start.y + (end.y - start.y) * t,
            start.z + (end.z - start.z) * t,
        )
    } else {
        end
    };

    Ok(Json(RaycastResponse {
        hit,
        hit_x: hit_pos.x,
        hit_y: hit_pos.y,
        hit_z: hit_pos.z,
        t,
        normal_x: hit_normal.x,
        normal_y: hit_normal.y,
        normal_z: hit_normal.z,
    }))
}

// ============================================================================
// Random Point
// ============================================================================

/// Request for random point endpoint.
#[derive(Debug, Deserialize)]
pub struct RandomPointRequest {
    pub map_id: u32,
    /// Center X coordinate (optional, for circle search).
    pub center_x: Option<f32>,
    /// Center Y coordinate (optional, for circle search).
    pub center_y: Option<f32>,
    /// Center Z coordinate (optional, for circle search).
    pub center_z: Option<f32>,
    /// Search radius (optional, for circle search).
    pub radius: Option<f32>,
}

/// Response for random point endpoint.
#[derive(Debug, Serialize)]
pub struct RandomPointResponse {
    pub success: bool,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// GET /api/v1/random - Find a random point on the navmesh.
///
/// If center_x, center_y, center_z, and radius are all provided, finds a
/// random point within that circle. Otherwise, finds a random point anywhere
/// on the navmesh.
pub async fn random_point(
    State(state): State<AppState>,
    Query(params): Query<RandomPointRequest>,
) -> Result<Json<RandomPointResponse>, AppError> {
    // Validate inputs
    validate_map_id(params.map_id)?;
    // Validate circle parameters if provided
    if let (Some(cx), Some(cy), Some(cz), Some(r)) = (
        params.center_x,
        params.center_y,
        params.center_z,
        params.radius,
    ) {
        validate_coordinate(cx, cy, cz)?;
        validate_radius(r)?;
    }

    // Acquire concurrency permit
    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // Load map
    let _mesh = state
        .mmap_manager
        .get_or_load_mesh(params.map_id)
        .map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(params.map_id),
            _ => AppError::Internal(e.to_string()),
        })?;

    // Get query pool
    let pool = state
        .mmap_manager
        .get_query_pool(params.map_id)
        .ok_or_else(|| AppError::MapNotFound(params.map_id))?;

    let query = pool
        .acquire()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let filter = pool.filter();

    // Check if we're doing a circle search or global random
    let point = match (
        params.center_x,
        params.center_y,
        params.center_z,
        params.radius,
    ) {
        (Some(cx), Some(cy), Some(cz), Some(radius)) => {
            // Circle search
            let center = Vec3::new(cx, cy, cz);

            // Find center polygon
            let (start_ref, _) = query
                .find_nearest_poly(center, SEARCH_EXTENTS, filter)
                .map_err(|_| AppError::PathfindingFailed("Center position not on navmesh".into()))?;

            // Find random point around circle
            let (_, point) = query
                .find_random_point_around_circle(start_ref, center, radius, filter)
                .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;
            point
        }
        _ => {
            // Global random point
            let (_, point) = query
                .find_random_point(filter)
                .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;
            point
        }
    };

    Ok(Json(RandomPointResponse {
        success: true,
        x: point.x,
        y: point.y,
        z: point.z,
    }))
}

// ============================================================================
// Height Query
// ============================================================================

/// Request for height query endpoint.
#[derive(Debug, Deserialize)]
pub struct HeightRequest {
    pub map_id: u32,
    pub x: f32,
    pub y: f32,
    /// Approximate Z for polygon search.
    pub z: f32,
}

/// Response for height query endpoint.
#[derive(Debug, Serialize)]
pub struct HeightResponse {
    pub success: bool,
    pub height: f32,
}

/// GET /api/v1/height - Get the navmesh height at a position.
///
/// Returns the height of the navmesh surface at the given X/Y position.
/// The provided Z is used to find the nearest polygon.
pub async fn get_height(
    State(state): State<AppState>,
    Query(params): Query<HeightRequest>,
) -> Result<Json<HeightResponse>, AppError> {
    // Validate inputs
    validate_map_id(params.map_id)?;
    validate_coordinate(params.x, params.y, params.z)?;

    // Acquire concurrency permit
    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // Load map
    let _mesh = state
        .mmap_manager
        .get_or_load_mesh(params.map_id)
        .map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(params.map_id),
            _ => AppError::Internal(e.to_string()),
        })?;

    // Get query pool
    let pool = state
        .mmap_manager
        .get_query_pool(params.map_id)
        .ok_or_else(|| AppError::MapNotFound(params.map_id))?;

    let query = pool
        .acquire()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let filter = pool.filter();

    let pos = Vec3::new(params.x, params.y, params.z);

    // Find nearest polygon
    let (poly_ref, _) = query
        .find_nearest_poly(pos, SEARCH_EXTENTS, filter)
        .map_err(|_| AppError::PathfindingFailed("Position not on navmesh".into()))?;

    // Get height at position
    let height = query
        .get_poly_height(poly_ref, pos)
        .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

    Ok(Json(HeightResponse {
        success: true,
        height,
    }))
}

// ============================================================================
// Multi-Height Query
// ============================================================================

/// Request for multi-height query endpoint.
#[derive(Debug, Deserialize)]
pub struct HeightsRequest {
    pub map_id: u32,
    pub x: f32,
    pub y: f32,
    /// Approximate Z for polygon search center (defaults to 0).
    pub z: Option<f32>,
    /// Horizontal search radius in yards (defaults to 2.0).
    pub xy_extent: Option<f32>,
    /// Vertical search radius in yards (defaults to 1000.0).
    pub z_extent: Option<f32>,
    /// Maximum polygons to query (defaults to 50).
    pub max_polys: Option<usize>,
    /// Deduplication tolerance in yards (defaults to 1.5).
    pub cluster_tolerance: Option<f32>,
    /// When true, filter out heights unreachable from (from_x, from_y, from_z).
    /// Requires from_x, from_y, from_z to be set.
    #[serde(default)]
    pub filter_unreachable: Option<bool>,
    /// Origin X for reachability check (typically player position).
    pub from_x: Option<f32>,
    /// Origin Y for reachability check.
    pub from_y: Option<f32>,
    /// Origin Z for reachability check.
    pub from_z: Option<f32>,
}

/// Single height entry with polygon metadata.
#[derive(Debug, Serialize)]
pub struct HeightEntry {
    pub height: f32,
    /// Polygon flags: 0x01=ground, 0x02=steep, 0x04=water, 0x08=magma/slime.
    pub flags: u16,
    /// Present only when filter_unreachable is used. True if pathfinding succeeds.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reachable: Option<bool>,
}

/// Response for multi-height query endpoint.
#[derive(Debug, Serialize)]
pub struct HeightsResponse {
    pub success: bool,
    /// All heights at the XY position, sorted ascending and deduplicated.
    pub heights: Vec<HeightEntry>,
    /// Number of heights found.
    pub count: usize,
}

/// GET /api/v1/heights - Get all navmesh heights at an XY position.
///
/// Returns every navigable height at the given X/Y coordinate, enabling
/// detection of multi-level structures (bridges, towers, caves, etc.).
/// Heights are sorted ascending and deduplicated within `cluster_tolerance`.
pub async fn get_heights(
    State(state): State<AppState>,
    Query(params): Query<HeightsRequest>,
) -> Result<Json<HeightsResponse>, AppError> {
    // Validate inputs
    validate_map_id(params.map_id)?;
    let z = params.z.unwrap_or(0.0);
    validate_coordinate(params.x, params.y, z)?;

    let xy_extent = params.xy_extent.unwrap_or(2.0);
    let z_extent = params.z_extent.unwrap_or(1000.0);
    let max_polys = params.max_polys.unwrap_or(50);
    let cluster_tolerance = params.cluster_tolerance.unwrap_or(1.5);

    if xy_extent <= 0.0 || xy_extent > 50.0 {
        return Err(AppError::InvalidParams(
            "xy_extent must be between 0 and 50".into(),
        ));
    }
    if z_extent <= 0.0 || z_extent > 2000.0 {
        return Err(AppError::InvalidParams(
            "z_extent must be between 0 and 2000".into(),
        ));
    }
    if max_polys == 0 || max_polys > 200 {
        return Err(AppError::InvalidParams(
            "max_polys must be between 1 and 200".into(),
        ));
    }
    if cluster_tolerance < 0.0 || cluster_tolerance > 10.0 {
        return Err(AppError::InvalidParams(
            "cluster_tolerance must be between 0 and 10".into(),
        ));
    }

    // Acquire concurrency permit
    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // Load map
    let _mesh = state
        .mmap_manager
        .get_or_load_mesh(params.map_id)
        .map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(params.map_id),
            _ => AppError::Internal(e.to_string()),
        })?;

    // Get query pool
    let pool = state
        .mmap_manager
        .get_query_pool(params.map_id)
        .ok_or_else(|| AppError::MapNotFound(params.map_id))?;

    let query = pool
        .acquire()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let filter = pool.filter();

    let pos = Vec3::new(params.x, params.y, z);
    let half_extents = Vec3::new(xy_extent, xy_extent, z_extent);

    // Query all polygons in the vertical column
    let poly_refs = query
        .query_polygons(pos, half_extents, filter, max_polys)
        .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

    // For each polygon, get height and flags
    let mut entries: Vec<HeightEntry> = Vec::with_capacity(poly_refs.len());
    for poly_ref in poly_refs {
        if let Ok(height) = query.get_poly_height(poly_ref, pos) {
            let flags = pool.mesh().get_poly_flags(poly_ref).unwrap_or(0);
            entries.push(HeightEntry { height, flags, reachable: None });
        }
    }

    // Sort by height ascending
    entries.sort_by(|a, b| a.height.partial_cmp(&b.height).unwrap_or(std::cmp::Ordering::Equal));

    // Deduplicate heights within cluster_tolerance
    let mut deduplicated: Vec<HeightEntry> = Vec::new();
    for entry in entries {
        let is_duplicate = deduplicated
            .iter()
            .any(|prev| (entry.height - prev.height).abs() < cluster_tolerance);
        if !is_duplicate {
            deduplicated.push(entry);
        }
    }

    // Reachability filtering: use lightweight pathfinding to remove disconnected floors
    if params.filter_unreachable.unwrap_or(false) {
        let (from_x, from_y, from_z) = match (params.from_x, params.from_y, params.from_z) {
            (Some(x), Some(y), Some(z)) => (x, y, z),
            _ => {
                return Err(AppError::InvalidParams(
                    "filter_unreachable requires from_x, from_y, from_z".into(),
                ));
            }
        };

        validate_coordinate(from_x, from_y, from_z)?;

        let from_pos = Vec3::new(from_x, from_y, from_z);

        // Find origin polygon (player position) once
        let (from_ref, _) = query
            .find_nearest_poly(from_pos, SEARCH_EXTENTS, filter)
            .map_err(|_| {
                AppError::PathfindingFailed(
                    "Origin position for reachability not on navmesh".into(),
                )
            })?;

        const MAX_REACHABILITY_POLYS: usize = 2048;
        // Disconnected islands have very few polys; if the partial path
        // used fewer than this, the search exhausted a small island.
        const MIN_PARTIAL_POLYS: usize = 5;

        for entry in &mut deduplicated {
            let target_pos = Vec3::new(params.x, params.y, entry.height);
            let target_extents = Vec3::new(xy_extent.max(5.0), xy_extent.max(5.0), 2.0);

            let reachable =
                match query.find_nearest_poly(target_pos, target_extents, filter) {
                    Ok((target_ref, _)) => {
                        match query.find_path(
                            from_ref,
                            target_ref,
                            from_pos,
                            target_pos,
                            filter,
                            MAX_REACHABILITY_POLYS,
                        ) {
                            Ok((_path, false)) => true, // full path found
                            Ok((path, true)) => {
                                // Partial path: if the search explored many polys,
                                // the areas are connected (search just ran out of
                                // budget). Very short partial = tiny disconnected island.
                                path.len() >= MIN_PARTIAL_POLYS
                            }
                            Err(_) => false, // no path at all
                        }
                    }
                    Err(_) => false, // target height not on a navmesh polygon
                };

            entry.reachable = Some(reachable);
        }

        // Remove unreachable entries
        deduplicated.retain(|e| e.reachable.unwrap_or(true));
    }

    let count = deduplicated.len();
    Ok(Json(HeightsResponse {
        success: true,
        heights: deduplicated,
        count,
    }))
}

// ============================================================================
// Polygon Exploration
// ============================================================================

/// Default minimum distance between exploration points (yards).
fn default_min_distance() -> f32 {
    30.0
}

/// Waypoint in exploration responses.
#[derive(Debug, Clone, Serialize)]
pub struct ExploreWaypoint {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// Custom deserializer for polygon vertices from query params.
///
/// Expects format: `polygon=x,y,z&polygon=x,y,z&polygon=x,y,z&polygon=x,y,z`
fn deserialize_polygon<'de, D>(deserializer: D) -> Result<Vec<(f32, f32, f32)>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;

    // Deserialize as Vec<String> since serde_urlencoded handles repeated params
    let values: Vec<String> = Vec::deserialize(deserializer)?;

    let mut polygon = Vec::with_capacity(values.len());
    for (i, value) in values.iter().enumerate() {
        let parts: Vec<&str> = value.split(',').collect();
        if parts.len() != 3 {
            return Err(D::Error::custom(format!(
                "Polygon vertex {} must have format 'x,y,z' (got '{}')",
                i, value
            )));
        }

        let x = parts[0]
            .trim()
            .parse::<f32>()
            .map_err(|_| D::Error::custom(format!("Invalid x coordinate in vertex {}", i)))?;
        let y = parts[1]
            .trim()
            .parse::<f32>()
            .map_err(|_| D::Error::custom(format!("Invalid y coordinate in vertex {}", i)))?;
        let z = parts[2]
            .trim()
            .parse::<f32>()
            .map_err(|_| D::Error::custom(format!("Invalid z coordinate in vertex {}", i)))?;

        polygon.push((x, y, z));
    }

    Ok(polygon)
}

/// Request for polygon exploration endpoint.
#[derive(Debug, Deserialize)]
pub struct ExploreRequest {
    pub map_id: u32,
    /// Polygon vertices as repeated params: `polygon=x,y,z&polygon=x,y,z&...`
    #[serde(deserialize_with = "deserialize_polygon")]
    pub polygon: Vec<(f32, f32, f32)>,
    /// Minimum distance between exploration points (default 30.0 yards).
    #[serde(default = "default_min_distance")]
    pub min_distance: f32,
    /// Enable TSP (Traveling Salesman Problem) ordering to optimize traversal order.
    /// When enabled, points are ordered using nearest-neighbor heuristic starting from
    /// the `start_x`, `start_y`, `start_z` position.
    #[serde(default)]
    pub tsp_order: Option<bool>,
    /// Starting X position for TSP ordering (defaults to first polygon vertex).
    pub start_x: Option<f32>,
    /// Starting Y position for TSP ordering (defaults to first polygon vertex).
    pub start_y: Option<f32>,
    /// Starting Z position for TSP ordering (defaults to first polygon vertex).
    pub start_z: Option<f32>,
}

/// Response for polygon exploration endpoint.
#[derive(Debug, Serialize)]
pub struct ExploreResponse {
    pub success: bool,
    /// Exploration waypoints within the polygon.
    pub points: Vec<ExploreWaypoint>,
    /// Number of points generated.
    pub point_count: usize,
    /// Computation time in milliseconds.
    pub computation_time_ms: f64,
}

/// GET /api/v1/explore - Generate exploration points within a polygon.
///
/// Uses Bridson's Poisson Disk Sampling algorithm to generate uniformly
/// distributed points. Points are snapped to the navmesh for validity.
///
/// When `tsp_order=true` is specified, points are reordered using the
/// nearest-neighbor TSP heuristic for efficient traversal.
///
/// Example: `GET /api/v1/explore?map_id=0&polygon=-8960,-120,83&polygon=-8900,-120,83&polygon=-8900,-170,83&polygon=-8960,-170,83&min_distance=20`
///
/// Example with TSP: `GET /api/v1/explore?map_id=0&polygon=...&tsp_order=true&start_x=-8960&start_y=-120&start_z=83`
pub async fn explore_polygon(
    State(state): State<AppState>,
    Query(params): Query<ExploreRequest>,
) -> Result<Json<ExploreResponse>, AppError> {
    let start_time = std::time::Instant::now();

    // Validate inputs
    validate_map_id(params.map_id)?;
    validate_polygon(&params.polygon)?;
    validate_min_distance(params.min_distance)?;

    // Validate start coordinates if provided
    if let (Some(x), Some(y), Some(z)) = (params.start_x, params.start_y, params.start_z) {
        validate_coordinate(x, y, z)?;
    }

    // Acquire concurrency permit
    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    // Load map
    let _mesh = state
        .mmap_manager
        .get_or_load_mesh(params.map_id)
        .map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(params.map_id),
            _ => AppError::Internal(e.to_string()),
        })?;

    // Get query pool
    let pool = state
        .mmap_manager
        .get_query_pool(params.map_id)
        .ok_or_else(|| AppError::MapNotFound(params.map_id))?;

    let query = pool
        .acquire()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let filter = pool.filter();

    // Convert polygon to format expected by polygon_sampling
    let polygon: Vec<[f32; 3]> = params
        .polygon
        .iter()
        .map(|(x, y, z)| [*x, *y, *z])
        .collect();

    // Determine start position for TSP (defaults to first polygon vertex)
    let tsp_start = match (params.start_x, params.start_y, params.start_z) {
        (Some(x), Some(y), Some(z)) => [x, y, z],
        _ => polygon.first().copied().unwrap_or([0.0, 0.0, 0.0]),
    };

    // Generate exploration points using Bridson's algorithm
    let config = SamplingConfig::with_min_distance(params.min_distance);
    let sample_points = if params.tsp_order.unwrap_or(false) {
        // Generate with TSP ordering
        polygon_sampling::bridson_sampling_with_tsp(&polygon, &config, tsp_start)
    } else {
        // Generate without ordering
        polygon_sampling::bridson_sampling(&polygon, &config)
    };

    // Snap points to navmesh and filter out invalid ones
    let mut points = Vec::with_capacity(sample_points.len());
    for p in sample_points {
        let pos = Vec3::new(p[0], p[1], p[2]);

        // Try to snap to navmesh
        if let Ok((_, snapped)) = query.find_nearest_poly(pos, SEARCH_EXTENTS, filter) {
            points.push(ExploreWaypoint {
                x: snapped.x,
                y: snapped.y,
                z: snapped.z,
            });
        }
        // Skip points that can't be snapped to navmesh
    }

    let point_count = points.len();

    Ok(Json(ExploreResponse {
        success: true,
        points,
        point_count,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}
