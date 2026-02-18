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
    self, execute_pathfind, has_custom_filter, create_custom_filter,
    PathOptions, SEARCH_EXTENTS,
};
use crate::state::AppState;
use crate::validation::{
    validate_area_cost, validate_coordinate, validate_deviation, validate_map_id,
    validate_min_corner_angle, validate_smooth_iterations, validate_smooth_ratio,
    validate_smooth_samples, validate_wall_clearance, validate_z_extent,
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
    #[serde(default)]
    pub smoothing: Option<String>,
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
    /// Number of iterations for Chaikin smoothing (1-5, default 2).
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    /// Number of samples per segment for Catmull-Rom/Bezier (5-50, default 10).
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    /// Chaikin corner-cut ratio (0.5-0.95, default 0.75).
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    /// Minimum corner angle to smooth (degrees, 0-180, default 0).
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    /// If true, preserve original waypoints and only insert interpolation points.
    #[serde(default)]
    pub keep_originals: Option<bool>,
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
    #[serde(default)]
    pub smoothing: Option<String>,
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
    /// Number of iterations for Chaikin smoothing (1-5, default 2).
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    /// Number of samples per segment for Catmull-Rom/Bezier (5-50, default 10).
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    /// Chaikin corner-cut ratio (0.5-0.95, default 0.75).
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    /// Minimum corner angle to smooth (degrees, 0-180, default 0).
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    /// If true, preserve original waypoints and only insert interpolation points.
    #[serde(default)]
    pub keep_originals: Option<bool>,
    /// Custom Z search extent for polygon lookup (overrides tiered fallback).
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
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

/// Validate smoothing parameters if provided.
pub fn validate_smoothing_params(
    smooth_iterations: Option<u32>,
    smooth_samples: Option<u32>,
    smooth_ratio: Option<f32>,
    min_corner_angle: Option<f32>,
) -> Result<(), AppError> {
    if let Some(iterations) = smooth_iterations {
        validate_smooth_iterations(iterations)?;
    }
    if let Some(samples) = smooth_samples {
        validate_smooth_samples(samples)?;
    }
    if let Some(ratio) = smooth_ratio {
        validate_smooth_ratio(ratio)?;
    }
    if let Some(angle) = min_corner_angle {
        validate_min_corner_angle(angle)?;
    }
    Ok(())
}

/// Helper: acquire map, pool, and query from state.
/// Declares `_nb_mesh`, `_nb_pool`, and `_nb_query` in the calling scope.
/// Use `_nb_pool.filter()` for the default filter, and `&*_nb_query` for the query ref.
macro_rules! acquire_query {
    ($state:expr, $map_id:expr, $pool:ident, $query:ident) => {
        let _nb_mesh = $state
            .mmap_manager
            .get_or_load_mesh($map_id)
            .map_err(|e| match &e {
                MmapError::MapNotFound(_) => AppError::MapNotFound($map_id),
                _ => AppError::Internal(e.to_string()),
            })?;

        let $pool = $state
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
    State(state): State<AppState>,
    Query(params): Query<PathRequest>,
) -> Result<Json<PathResponse>, AppError> {
    state.metrics.total_requests.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    // Validate inputs
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_coordinate(params.end_x, params.end_y, params.end_z)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;
    validate_smoothing_params(
        params.smooth_iterations,
        params.smooth_samples,
        params.smooth_ratio,
        params.min_corner_angle,
    )?;
    if let Some(z) = params.z_extent {
        validate_z_extent(z)?;
    }
    if let Some(wc) = params.wall_clearance {
        validate_wall_clearance(wc)?;
    }

    let start_time = std::time::Instant::now();
    let start_pos = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end_pos = Vec3::new(params.end_x, params.end_y, params.end_z);

    // Check path cache
    if let Some(cached) = state.path_cache.get(params.map_id, &start_pos, &end_pos) {
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

    acquire_query!(state, params.map_id, pool, query);

    // Resolve filter
    let custom_filter;
    let filter = if has_custom_filter(params.filter_ground, params.filter_water, params.filter_lava)
    {
        custom_filter = create_custom_filter(
            params.filter_ground,
            params.filter_water,
            params.filter_lava,
        )?;
        &custom_filter
    } else {
        pool.filter()
    };

    let options = PathOptions {
        smoothing: params.smoothing,
        optimize: params.optimize.unwrap_or(false),
        filter_ground: params.filter_ground,
        filter_water: params.filter_water,
        filter_lava: params.filter_lava,
        smooth_iterations: params.smooth_iterations,
        smooth_samples: params.smooth_samples,
        smooth_ratio: params.smooth_ratio,
        min_corner_angle: params.min_corner_angle,
        keep_originals: params.keep_originals,
        z_extent: params.z_extent,
        wall_clearance: params.wall_clearance,
    };

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
    State(state): State<AppState>,
    Query(params): Query<RandomPathRequest>,
) -> Result<Json<PathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    validate_coordinate(params.start_x, params.start_y, params.start_z)?;
    validate_coordinate(params.end_x, params.end_y, params.end_z)?;
    validate_deviation(params.max_deviation)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;
    validate_smoothing_params(
        params.smooth_iterations,
        params.smooth_samples,
        params.smooth_ratio,
        params.min_corner_angle,
    )?;
    if let Some(z) = params.z_extent {
        validate_z_extent(z)?;
    }
    if let Some(wc) = params.wall_clearance {
        validate_wall_clearance(wc)?;
    }

    let start_time = std::time::Instant::now();

    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    acquire_query!(state, params.map_id, pool, query);

    let custom_filter;
    let filter = if has_custom_filter(params.filter_ground, params.filter_water, params.filter_lava)
    {
        custom_filter = create_custom_filter(
            params.filter_ground,
            params.filter_water,
            params.filter_lava,
        )?;
        &custom_filter
    } else {
        pool.filter()
    };

    let start_pos = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end_pos = Vec3::new(params.end_x, params.end_y, params.end_z);

    // Use pipeline but with deviation inserted before smoothing
    let options = PathOptions {
        smoothing: params.smoothing,
        optimize: params.optimize.unwrap_or(false),
        filter_ground: params.filter_ground,
        filter_water: params.filter_water,
        filter_lava: params.filter_lava,
        smooth_iterations: params.smooth_iterations,
        smooth_samples: params.smooth_samples,
        smooth_ratio: params.smooth_ratio,
        min_corner_angle: params.min_corner_angle,
        keep_originals: params.keep_originals,
        z_extent: params.z_extent,
        wall_clearance: params.wall_clearance,
    };

    // For random paths, we need the raw waypoints before smoothing so we can
    // apply deviation. Use a no-smoothing pipeline first, then apply deviation + smooth.
    let mut raw_options = options.clone();
    raw_options.smoothing = Some("none".to_string());

    let raw_result = execute_pathfind(&query, pool.mesh(), filter, start_pos, end_pos, &raw_options)?;
    let mut waypoints = raw_result.waypoints;

    // Apply random deviation
    apply_random_deviation(&mut waypoints, &query, filter, params.max_deviation);

    // Now apply smoothing manually
    let waypoints = if options.smoothing.as_deref().unwrap_or("none") != "none" {
        let smoother = path_smoothing::SmootherPipeline::with_default_config();
        smoother.smooth(&waypoints, &query, filter)
    } else {
        waypoints
    };
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
    State(state): State<AppState>,
    Query(params): Query<ValidatePathRequest>,
) -> Result<Json<ValidatePathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    let waypoints = pipeline::parse_waypoints(&params.waypoints)?;
    let original_count = waypoints.len();

    let start_time = std::time::Instant::now();

    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    acquire_query!(state, params.map_id, pool, query);
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
    State(state): State<AppState>,
    Query(params): Query<ValidatePathRequest>,
) -> Result<Json<ValidatePathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    let waypoints = pipeline::parse_waypoints(&params.waypoints)?;
    let original_count = waypoints.len();

    let start_time = std::time::Instant::now();

    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    acquire_query!(state, params.map_id, pool, query);
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
