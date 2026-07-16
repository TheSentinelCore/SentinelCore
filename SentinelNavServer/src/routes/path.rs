//! Pathfinding endpoints.

use axum::{
    extract::{Query, State},
    Json,
};
use detour::types::Vec3;
use rand::Rng;
use serde::{Deserialize, Serialize};
use mmap_loader::error::MmapError;

use crate::cache::CachedPath;
use crate::error::AppError;
use crate::pipeline::{
    self, execute_pathfind, resolve_filter,
    PathOptions, SEARCH_EXTENTS,
};
use std::sync::Arc;
use crate::blackboard::ServerBlackboard;
use crate::validation::{
    validate_area_cost, validate_coordinate, validate_deviation, validate_map_id,
    validate_wall_clearance, validate_z_extent,
};

/// Path request query parameters.
#[derive(Debug, Deserialize)]
pub struct PathRequest {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
    /// Enable string-pulling optimization to reduce waypoint count.
    #[serde(default)]
    pub optimize: Option<bool>,
    /// Ground area cost multiplier (default 1.0, higher = more expensive)
    #[serde(default)]
    pub filter_ground: Option<f32>,
    /// Water area cost multiplier (default 10.0, higher = more expensive)
    #[serde(default)]
    pub filter_water: Option<f32>,
    /// Lava area cost multiplier (default 100.0, higher = more expensive)
    #[serde(default)]
    pub filter_lava: Option<f32>,
    /// If true, return partial paths with recovery suggestions instead of failing.
    #[serde(default)]
    pub allow_partial: Option<bool>,
    /// Custom Z search extent for polygon lookup (overrides tiered fallback).
    /// Smaller values (e.g. 10) pick correct floor in multi-story buildings.
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
    /// Max 3D deviation (yards) for string-pull optimization (default 1.5).
    #[serde(default)]
    pub string_pull_deviation: Option<f32>,
    /// Max heading change (degrees) for string-pull optimization (default 30).
    #[serde(default)]
    pub string_pull_heading: Option<f32>,
    /// Min wall distance (yards) for string-pull shortcuts (default 0.6, 0 = disabled).
    #[serde(default)]
    pub string_pull_wall_dist: Option<f32>,
    /// Max segment length (yards) for densification (default 3.0).
    #[serde(default)]
    pub densify_segment_length: Option<f32>,
    /// Game identifier (e.g. "tbc", "retail"). Uses server default if omitted.
    #[serde(default)]
    pub game: Option<String>,
}

/// Random path request (extends PathRequest).
#[derive(Debug, Deserialize)]
pub struct RandomPathRequest {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
    /// Enable string-pulling optimization to reduce waypoint count.
    #[serde(default)]
    pub optimize: Option<bool>,
    #[serde(default = "default_max_deviation")]
    pub max_deviation: f32,
    /// Ground area cost multiplier (default 1.0, higher = more expensive)
    #[serde(default)]
    pub filter_ground: Option<f32>,
    /// Water area cost multiplier (default 10.0, higher = more expensive)
    #[serde(default)]
    pub filter_water: Option<f32>,
    /// Lava area cost multiplier (default 100.0, higher = more expensive)
    #[serde(default)]
    pub filter_lava: Option<f32>,
    /// Custom Z search extent for polygon lookup (overrides tiered fallback).
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
    /// Max 3D deviation (yards) for string-pull optimization (default 1.5).
    #[serde(default)]
    pub string_pull_deviation: Option<f32>,
    /// Max heading change (degrees) for string-pull optimization (default 30).
    #[serde(default)]
    pub string_pull_heading: Option<f32>,
    /// Min wall distance (yards) for string-pull shortcuts (default 0.6, 0 = disabled).
    #[serde(default)]
    pub string_pull_wall_dist: Option<f32>,
    /// Max segment length (yards) for densification (default 3.0).
    #[serde(default)]
    pub densify_segment_length: Option<f32>,
    /// Game identifier (e.g. "tbc", "retail"). Uses server default if omitted.
    #[serde(default)]
    pub game: Option<String>,
}

fn default_max_deviation() -> f32 {
    5.0
}

/// Waypoint in the path response.
#[derive(Debug, Serialize)]
pub struct Waypoint {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// Convert Vec3 slice to Waypoint vec.
pub fn vec3_to_waypoints(points: &[Vec3]) -> Vec<Waypoint> {
    points.iter().map(|v| Waypoint { x: v.x, y: v.y, z: v.z }).collect()
}

/// Path response.
#[derive(Debug, Serialize)]
pub struct PathResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub distance: f32,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub partial: bool,
    pub computation_time_ms: f64,
    /// Present when partial=true and allow_partial was requested.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub partial_endpoint: Option<Waypoint>,
    /// Recovery suggestions when partial path detected.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery_suggestions: Option<Vec<Waypoint>>,
    /// Reason for partial path: "out_of_nodes" or "disconnected". Absent when path is complete.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub partial_reason: Option<String>,
}

/// Validate custom filter parameters if provided.
pub fn validate_filter_params(
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
) -> Result<(), AppError> {
    if let Some(cost) = filter_ground {
        validate_area_cost(cost, "ground")?;
    }
    if let Some(cost) = filter_water {
        validate_area_cost(cost, "water")?;
    }
    if let Some(cost) = filter_lava {
        validate_area_cost(cost, "lava")?;
    }
    Ok(())
}

/// Helper: acquire map, pool, and query from a game bundle.
/// Declares `_nb_mesh`, `$pool`, and `$query` in the calling scope.
/// Use `$pool.filter()` for the default filter, and `&*$query` for the query ref.
macro_rules! acquire_query {
    ($bundle:expr, $map_id:expr, $pool:ident, $query:ident) => {
        let _nb_mesh = $bundle
            .mmap_manager
            .get_or_load_mesh($map_id)
            .map_err(|e| match &e {
                MmapError::MapNotFound(_) => AppError::MapNotFound($map_id),
                _ => AppError::Internal(e.to_string()),
            })?;

        let $pool = $bundle
            .mmap_manager
            .get_query_pool($map_id)
            .ok_or_else(|| AppError::MapNotFound($map_id))?;

        let $query = $pool
            .acquire()
            .map_err(|e| AppError::Internal(e.to_string()))?;
    };
}

pub(crate) use acquire_query;

/// GET /api/v1/path - Find path between two points.
pub async fn find_path(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<PathRequest>,
) -> Result<Json<PathResponse>, AppError> {
    state.metrics.total_requests.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    // Validate inputs
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_coordinate(params.end_x, params.end_y, params.end_z)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;
    if let Some(z) = params.z_extent {
        validate_z_extent(z)?;
    }
    if let Some(wc) = params.wall_clearance {
        validate_wall_clearance(wc)?;
    }

    let start_time = std::time::Instant::now();
    let start_pos = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end_pos = Vec3::new(params.end_x, params.end_y, params.end_z);

    // Build options early so cache key includes options hash
    let options = PathOptions {
        optimize: params.optimize.unwrap_or(false),
        filter_ground: params.filter_ground,
        filter_water: params.filter_water,
        filter_lava: params.filter_lava,
        z_extent: params.z_extent,
        wall_clearance: params.wall_clearance,
        string_pull_deviation: params.string_pull_deviation,
        string_pull_heading: params.string_pull_heading.map(f32::to_radians),
        string_pull_wall_dist: params.string_pull_wall_dist,
        densify_segment_length: params.densify_segment_length,
    };
    let opts_hash = options.cache_hash();

    // Check path cache (keyed on position + options)
    if let Some(cached) = state.path_cache.get(params.map_id, &start_pos, &end_pos, opts_hash) {
        return Ok(Json(PathResponse {
            success: true,
            path: vec3_to_waypoints(&cached.waypoints),
            distance: cached.distance,
            partial: cached.partial,
            computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
            partial_endpoint: None,
            recovery_suggestions: None,
            partial_reason: None,
        }));
    }

    // Acquire concurrency permit (503 if overloaded)
    let _permit = state.try_acquire_permit()?;

    let bundle = state.get_game(params.game.as_deref())?;
    acquire_query!(bundle, params.map_id, pool, query);

    // Resolve filter
    let mut custom_filter_storage = None;
    let filter = resolve_filter(pool.filter(), params.filter_ground, params.filter_water, params.filter_lava, &mut custom_filter_storage)?;

    let result = execute_pathfind(&query, pool.mesh(), filter, start_pos, end_pos, &options)?;

    // Handle partial paths with recovery suggestions
    let (partial_endpoint, recovery_suggestions) = if result.partial
        && params.allow_partial.unwrap_or(false)
    {
        let endpoint = result.waypoints.last().copied();
        let suggestions = if let Some(ep) = endpoint {
            compute_recovery_suggestions(&query, filter, ep, end_pos)
        } else {
            vec![]
        };
        (
            endpoint.map(|v| Waypoint { x: v.x, y: v.y, z: v.z }),
            if suggestions.is_empty() {
                None
            } else {
                Some(vec3_to_waypoints(&suggestions))
            },
        )
    } else {
        (None, None)
    };

    // Cache the result
    state.path_cache.insert(
        params.map_id,
        &start_pos,
        &end_pos,
        opts_hash,
        CachedPath {
            waypoints: result.waypoints.clone(),
            distance: result.distance,
            partial: result.partial,
        },
    );

    let partial_reason = if result.partial {
        Some(if result.out_of_nodes { "out_of_nodes" } else { "disconnected" }.to_string())
    } else {
        None
    };

    Ok(Json(PathResponse {
        success: true,
        path: vec3_to_waypoints(&result.waypoints),
        distance: result.distance,
        partial: result.partial,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
        partial_endpoint,
        recovery_suggestions,
        partial_reason,
    }))
}

/// GET /api/v1/path-random - Find path with random deviation for anti-detection.
pub async fn find_path_random(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<RandomPathRequest>,
) -> Result<Json<PathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_coordinate(params.end_x, params.end_y, params.end_z)?;
    validate_deviation(params.max_deviation)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;
    if let Some(z) = params.z_extent {
        validate_z_extent(z)?;
    }
    if let Some(wc) = params.wall_clearance {
        validate_wall_clearance(wc)?;
    }

    let start_time = std::time::Instant::now();

    let _permit = state.try_acquire_permit()?;

    let bundle = state.get_game(params.game.as_deref())?;
    acquire_query!(bundle, params.map_id, pool, query);

    let mut custom_filter_storage = None;
    let filter = resolve_filter(pool.filter(), params.filter_ground, params.filter_water, params.filter_lava, &mut custom_filter_storage)?;

    let start_pos = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end_pos = Vec3::new(params.end_x, params.end_y, params.end_z);

    let options = PathOptions {
        optimize: params.optimize.unwrap_or(false),
        filter_ground: params.filter_ground,
        filter_water: params.filter_water,
        filter_lava: params.filter_lava,
        z_extent: params.z_extent,
        wall_clearance: params.wall_clearance,
        string_pull_deviation: params.string_pull_deviation,
        string_pull_heading: params.string_pull_heading.map(f32::to_radians),
        string_pull_wall_dist: params.string_pull_wall_dist,
        densify_segment_length: params.densify_segment_length,
    };

    let raw_result = execute_pathfind(&query, pool.mesh(), filter, start_pos, end_pos, &options)?;
    let mut waypoints = raw_result.waypoints;

    // Apply random deviation to intermediate waypoints
    apply_random_deviation(&mut waypoints, &query, filter, params.max_deviation);

    let distance = pipeline::calculate_path_distance(&waypoints);

    let partial_reason = if raw_result.partial {
        Some(if raw_result.out_of_nodes { "out_of_nodes" } else { "disconnected" }.to_string())
    } else {
        None
    };

    Ok(Json(PathResponse {
        success: true,
        path: vec3_to_waypoints(&waypoints),
        distance,
        partial: raw_result.partial,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
        partial_endpoint: None,
        recovery_suggestions: None,
        partial_reason,
    }))
}

/// Generate a Gaussian random number using Box-Muller transform.
fn gaussian_random<R: Rng>(rng: &mut R, max: f32) -> f32 {
    let u1: f32 = rng.gen_range(0.0001_f32..1.0);
    let u2: f32 = rng.gen_range(0.0_f32..1.0);
    let z = (-2.0 * u1.ln()).sqrt() * (2.0 * std::f32::consts::PI * u2).cos();
    (z * (max / 3.0)).abs().min(max)
}

/// Apply random deviation to intermediate waypoints using Gaussian distribution.
fn apply_random_deviation(
    waypoints: &mut [Vec3],
    query: &detour::query::NavMeshQuery,
    filter: &detour::filter::QueryFilter,
    max_deviation: f32,
) {
    if waypoints.len() <= 2 {
        return;
    }

    let mut rng = rand::thread_rng();

    for i in 1..waypoints.len().saturating_sub(1) {
        let angle = rng.gen_range(0.0..std::f32::consts::TAU);
        let distance = gaussian_random(&mut rng, max_deviation);

        let offset_x = angle.cos() * distance;
        let offset_y = angle.sin() * distance;

        let candidate = Vec3::new(
            waypoints[i].x + offset_x,
            waypoints[i].y + offset_y,
            waypoints[i].z,
        );

        let search_extents = Vec3::new(max_deviation * 2.0, max_deviation * 2.0, 50.0);

        if let Ok((_, snapped)) = query.find_nearest_poly(candidate, search_extents, filter) {
            waypoints[i] = snapped;
        }
    }
}

/// Compute recovery suggestions for partial paths by sampling along the line
/// from the partial endpoint to the destination.
fn compute_recovery_suggestions(
    query: &detour::query::NavMeshQuery,
    filter: &detour::filter::QueryFilter,
    partial_end: Vec3,
    destination: Vec3,
) -> Vec<Vec3> {
    let mut suggestions = Vec::new();

    // Sample 5 points along the line from partial_end to destination
    for i in 1..=5 {
        let t = i as f32 / 6.0;
        let sample = Vec3::new(
            partial_end.x + (destination.x - partial_end.x) * t,
            partial_end.y + (destination.y - partial_end.y) * t,
            partial_end.z + (destination.z - partial_end.z) * t,
        );

        // Check if this sample point is on the navmesh
        if let Ok((_, snapped)) = query.find_nearest_poly(sample, SEARCH_EXTENTS, filter) {
            // Only include if it's reasonably close to the sampled point
            if snapped.distance_2d(&sample) < 20.0 {
                suggestions.push(snapped);
            }
        }
    }

    suggestions
}

// =============================================================================
// PATH VALIDATION ENDPOINTS
// =============================================================================

/// Request for path validation endpoints.
#[derive(Debug, Deserialize)]
pub struct ValidatePathRequest {
    pub map_id: u32,
    /// Waypoints as semicolon-separated "x,y,z" values
    pub waypoints: String,
    /// Game identifier (e.g. "tbc", "retail"). Uses server default if omitted.
    #[serde(default)]
    pub game: Option<String>,
}

/// Response for path validation endpoints.
#[derive(Debug, Serialize)]
pub struct ValidatePathResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub original_count: usize,
    pub validated_count: usize,
    pub computation_time_ms: f64,
}

/// GET /api/v1/path/validate-snap - Validate path by snapping to nearest navmesh polygons.
pub async fn validate_path_snap(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<ValidatePathRequest>,
) -> Result<Json<ValidatePathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    let waypoints = pipeline::parse_waypoints(&params.waypoints)?;
    let original_count = waypoints.len();

    let start_time = std::time::Instant::now();

    let _permit = state.try_acquire_permit()?;

    let bundle = state.get_game(params.game.as_deref())?;
    acquire_query!(bundle, params.map_id, pool, query);
    let filter = pool.filter();

    let search_extents = Vec3::new(10.0, 10.0, 50.0);
    let mut snapped = Vec::with_capacity(waypoints.len());
    for wp in &waypoints {
        match query.find_nearest_poly(*wp, search_extents, filter) {
            Ok((poly_ref, _)) => match query.closest_point_on_poly(poly_ref, *wp) {
                Ok((closest, _)) => snapped.push(closest),
                Err(_) => snapped.push(*wp),
            },
            Err(_) => snapped.push(*wp),
        }
    }

    Ok(Json(ValidatePathResponse {
        success: true,
        path: vec3_to_waypoints(&snapped),
        original_count,
        validated_count: snapped.len(),
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}

/// GET /api/v1/path/validate-surface - Validate path by moving along navmesh surface.
pub async fn validate_path_surface(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<ValidatePathRequest>,
) -> Result<Json<ValidatePathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    let waypoints = pipeline::parse_waypoints(&params.waypoints)?;
    let original_count = waypoints.len();

    let start_time = std::time::Instant::now();

    let _permit = state.try_acquire_permit()?;

    let bundle = state.get_game(params.game.as_deref())?;
    acquire_query!(bundle, params.map_id, pool, query);
    let filter = pool.filter();

    let search_extents = Vec3::new(10.0, 10.0, 50.0);
    let mut validated = Vec::with_capacity(waypoints.len());

    let (start_ref, start_pos) = query
        .find_nearest_poly(waypoints[0], search_extents, filter)
        .map_err(|_| AppError::PathfindingFailed("First waypoint not on navmesh".into()))?;
    validated.push(start_pos);

    let mut current_ref = start_ref;
    let mut current_pos = start_pos;

    for i in 1..waypoints.len() {
        let target = waypoints[i];
        match query.move_along_surface(current_ref, current_pos, target, filter) {
            Ok(result_pos) => {
                validated.push(result_pos);
                if let Ok((new_ref, _)) =
                    query.find_nearest_poly(result_pos, search_extents, filter)
                {
                    current_ref = new_ref;
                    current_pos = result_pos;
                } else {
                    current_pos = result_pos;
                }
            }
            Err(_) => {
                if let Ok((new_ref, snapped)) =
                    query.find_nearest_poly(target, search_extents, filter)
                {
                    validated.push(snapped);
                    current_ref = new_ref;
                    current_pos = snapped;
                } else {
                    validated.push(target);
                }
            }
        }
    }

    Ok(Json(ValidatePathResponse {
        success: true,
        path: vec3_to_waypoints(&validated),
        original_count,
        validated_count: validated.len(),
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}
