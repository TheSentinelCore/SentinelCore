//! Intelligence endpoints: multi-stop, TSP, avoidance, corridor, path-check, explore-route.

use axum::{
    extract::{Query, State},
    Json,
};
use detour::types::Vec3;
use serde::{Deserialize, Serialize};
use tc_mmap::error::MmapError;

use crate::error::AppError;
use crate::pipeline::{
    self, apply_avoidance, compute_corridor_widths, execute_pathfind, has_custom_filter,
    create_custom_filter, parse_avoidance_zones, parse_stops, parse_waypoints, PathOptions,
    SEARCH_EXTENTS, HEIGHT_EXTENTS,
};
use crate::routes::path::{
    acquire_query, validate_filter_params, validate_smoothing_params,
    vec3_to_waypoints, Waypoint,
};
use crate::state::AppState;
use crate::validation::{validate_coordinate, validate_map_id, validate_wall_clearance, validate_z_extent};

// =============================================================================
// PATH-MULTI
// =============================================================================

/// Multi-stop path request.
#[derive(Debug, Deserialize)]
pub struct MultiPathRequest {
    pub map_id: u32,
    /// Semicolon-separated "x,y,z" stops (minimum 2).
    pub stops: String,
    #[serde(default)]
    pub smoothing: Option<String>,
    #[serde(default)]
    pub optimize: Option<bool>,
    #[serde(default)]
    pub filter_ground: Option<f32>,
    #[serde(default)]
    pub filter_water: Option<f32>,
    #[serde(default)]
    pub filter_lava: Option<f32>,
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    #[serde(default)]
    pub keep_originals: Option<bool>,
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
}

/// Multi-stop path response.
#[derive(Debug, Serialize)]
pub struct MultiPathResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub total_distance: f32,
    pub leg_distances: Vec<f32>,
    pub leg_boundaries: Vec<usize>,
    pub partial_legs: Vec<usize>,
    pub computation_time_ms: f64,
}

/// GET /api/v1/path-multi - Multi-stop ordered route.
pub async fn path_multi(
    State(state): State<AppState>,
    Query(params): Query<MultiPathRequest>,
) -> Result<Json<MultiPathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    let stops = parse_stops(&params.stops)?;
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

    let mut all_waypoints: Vec<Vec3> = Vec::new();
    let mut leg_distances = Vec::new();
    let mut leg_boundaries = vec![0usize];
    let mut partial_legs = Vec::new();
    let mut total_distance = 0.0f32;

    for i in 0..stops.len() - 1 {
        let result = execute_pathfind(&query, pool.mesh(), filter, stops[i], stops[i + 1], &options)?;

        if result.partial {
            partial_legs.push(i);
        }

        leg_distances.push(result.distance);
        total_distance += result.distance;

        // Append waypoints, deduplicating shared endpoint
        if all_waypoints.is_empty() {
            all_waypoints.extend_from_slice(&result.waypoints);
        } else if !result.waypoints.is_empty() {
            // Skip first waypoint of this leg (same as last of previous leg)
            all_waypoints.extend_from_slice(&result.waypoints[1..]);
        }

        leg_boundaries.push(all_waypoints.len());
    }

    Ok(Json(MultiPathResponse {
        success: true,
        path: vec3_to_waypoints(&all_waypoints),
        total_distance,
        leg_distances,
        leg_boundaries,
        partial_legs,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}

// =============================================================================
// PATH-TSP
// =============================================================================

/// TSP-optimized path request.
#[derive(Debug, Deserialize)]
pub struct TspPathRequest {
    pub map_id: u32,
    /// Semicolon-separated "x,y,z" points to visit (minimum 2).
    pub points: String,
    /// Optional start position.
    #[serde(default)]
    pub start_x: Option<f32>,
    #[serde(default)]
    pub start_y: Option<f32>,
    #[serde(default)]
    pub start_z: Option<f32>,
    /// Return to start position after visiting all points.
    #[serde(default)]
    pub return_to_start: Option<bool>,
    /// Semicolon-separated priority weights per point.
    #[serde(default)]
    pub weights: Option<String>,
    #[serde(default)]
    pub smoothing: Option<String>,
    #[serde(default)]
    pub optimize: Option<bool>,
    #[serde(default)]
    pub filter_ground: Option<f32>,
    #[serde(default)]
    pub filter_water: Option<f32>,
    #[serde(default)]
    pub filter_lava: Option<f32>,
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    #[serde(default)]
    pub keep_originals: Option<bool>,
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
}

/// TSP path response.
#[derive(Debug, Serialize)]
pub struct TspPathResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub total_distance: f32,
    pub leg_distances: Vec<f32>,
    pub leg_boundaries: Vec<usize>,
    pub visit_order: Vec<usize>,
    pub partial_legs: Vec<usize>,
    pub computation_time_ms: f64,
}

/// Parse optional weights from semicolon-separated string.
fn parse_weights(weights_str: &str, expected_count: usize) -> Result<Vec<f32>, AppError> {
    let weights: Vec<f32> = weights_str
        .split(';')
        .map(|s| {
            s.trim().parse::<f32>().map_err(|_| {
                AppError::InvalidParams("Invalid weight value".into())
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    if weights.len() != expected_count {
        return Err(AppError::InvalidParams(format!(
            "Expected {} weights, got {}",
            expected_count,
            weights.len()
        )));
    }

    for (i, &w) in weights.iter().enumerate() {
        if !w.is_finite() || w <= 0.0 {
            return Err(AppError::InvalidParams(format!(
                "Weight {} must be positive finite (got {})",
                i, w
            )));
        }
    }

    Ok(weights)
}

/// Nearest-neighbor TSP with optional 2-opt improvement.
fn solve_tsp(distances: &[Vec<f32>], start_idx: usize, weights: &[f32]) -> Vec<usize> {
    let n = distances.len();
    if n <= 2 {
        return (0..n).collect();
    }

    // Nearest-neighbor heuristic with weighted cost
    let mut visited = vec![false; n];
    let mut order = Vec::with_capacity(n);
    let mut current = start_idx;
    visited[current] = true;
    order.push(current);

    for _ in 1..n {
        let mut best_idx = None;
        let mut best_cost = f32::MAX;

        for j in 0..n {
            if !visited[j] {
                // Cost = distance / weight (higher weight = prefer visiting sooner)
                let cost = distances[current][j] / weights[j];
                if cost < best_cost {
                    best_cost = cost;
                    best_idx = Some(j);
                }
            }
        }

        if let Some(next) = best_idx {
            visited[next] = true;
            order.push(next);
            current = next;
        }
    }

    // 2-opt improvement
    let mut improved = true;
    while improved {
        improved = false;
        for i in 1..order.len() - 1 {
            for j in (i + 1)..order.len() {
                let old_cost = distances[order[i - 1]][order[i]]
                    + distances[order[j - 1]][order[j % order.len()]];
                let new_cost = distances[order[i - 1]][order[j - 1]]
                    + distances[order[i]][order[j % order.len()]];

                if new_cost < old_cost - 0.01 {
                    // Reverse the segment between i and j-1
                    order[i..j].reverse();
                    improved = true;
                }
            }
        }
    }

    order
}

/// GET /api/v1/path-tsp - TSP-optimized multi-stop route.
pub async fn path_tsp(
    State(state): State<AppState>,
    Query(params): Query<TspPathRequest>,
) -> Result<Json<TspPathResponse>, AppError> {
    validate_map_id(params.map_id)?;
    let points = parse_stops(&params.points)?;
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

    if points.len() > 30 {
        return Err(AppError::InvalidParams(
            "Maximum 30 points for TSP (got more)".into(),
        ));
    }

    let weights = if let Some(ref w) = params.weights {
        parse_weights(w, points.len())?
    } else {
        vec![1.0; points.len()]
    };

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

    // Determine start index
    let start_idx = if let (Some(sx), Some(sy), Some(sz)) =
        (params.start_x, params.start_y, params.start_z)
    {
        validate_coordinate(sx, sy, sz)?;
        let start_pos = Vec3::new(sx, sy, sz);
        // Find closest point to start position
        points
            .iter()
            .enumerate()
            .min_by(|(_, a): &(usize, &Vec3), (_, b): &(usize, &Vec3)| {
                a.distance_2d(&start_pos)
                    .partial_cmp(&b.distance_2d(&start_pos))
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .map(|(i, _)| i)
            .unwrap_or(0)
    } else {
        0
    };

    // Compute pairwise distances
    let n = points.len();
    let mut distances = vec![vec![0.0f32; n]; n];

    if n <= 15 {
        // Use navmesh distances for small N
        let no_smooth_options = PathOptions {
            smoothing: Some("none".to_string()),
            optimize: true,
            ..Default::default()
        };

        for i in 0..n {
            for j in (i + 1)..n {
                let dist = match execute_pathfind(
                    &query,
                    pool.mesh(),
                    filter,
                    points[i],
                    points[j],
                    &no_smooth_options,
                ) {
                    Ok(result) => result.distance,
                    Err(_) => points[i].distance(&points[j]) * 1.5, // Fallback with penalty
                };
                distances[i][j] = dist;
                distances[j][i] = dist;
            }
        }
    } else {
        // Use Euclidean distances for large N
        for i in 0..n {
            for j in (i + 1)..n {
                let dist = points[i].distance(&points[j]);
                distances[i][j] = dist;
                distances[j][i] = dist;
            }
        }
    }

    // Solve TSP
    let visit_order = solve_tsp(&distances, start_idx, &weights);

    // Build ordered stops
    let mut ordered_stops: Vec<Vec3> = visit_order.iter().map(|&i| points[i]).collect();

    if params.return_to_start.unwrap_or(false) && !ordered_stops.is_empty() {
        ordered_stops.push(ordered_stops[0]);
    }

    // Compute full paths between ordered stops
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

    let mut all_waypoints: Vec<Vec3> = Vec::new();
    let mut leg_distances = Vec::new();
    let mut leg_boundaries = vec![0usize];
    let mut partial_legs = Vec::new();
    let mut total_distance = 0.0f32;

    for i in 0..ordered_stops.len() - 1 {
        let result = execute_pathfind(
            &query,
            pool.mesh(),
            filter,
            ordered_stops[i],
            ordered_stops[i + 1],
            &options,
        )?;

        if result.partial {
            partial_legs.push(i);
        }

        leg_distances.push(result.distance);
        total_distance += result.distance;

        if all_waypoints.is_empty() {
            all_waypoints.extend_from_slice(&result.waypoints);
        } else if !result.waypoints.is_empty() {
            all_waypoints.extend_from_slice(&result.waypoints[1..]);
        }

        leg_boundaries.push(all_waypoints.len());
    }

    Ok(Json(TspPathResponse {
        success: true,
        path: vec3_to_waypoints(&all_waypoints),
        total_distance,
        leg_distances,
        leg_boundaries,
        visit_order,
        partial_legs,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}

// =============================================================================
// PATH-AVOID
// =============================================================================

/// Path with avoidance zones request.
#[derive(Debug, Deserialize)]
pub struct AvoidPathRequest {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
    /// Repeated param: "x,y,z,radius,cost" per zone.
    #[serde(default)]
    pub avoid: Vec<String>,
    #[serde(default)]
    pub smoothing: Option<String>,
    #[serde(default)]
    pub optimize: Option<bool>,
    #[serde(default)]
    pub filter_ground: Option<f32>,
    #[serde(default)]
    pub filter_water: Option<f32>,
    #[serde(default)]
    pub filter_lava: Option<f32>,
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    #[serde(default)]
    pub keep_originals: Option<bool>,
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
}

/// GET /api/v1/path-avoid - Path with avoidance zones.
pub async fn path_avoid(
    State(state): State<AppState>,
    Query(params): Query<AvoidPathRequest>,
) -> Result<Json<crate::routes::path::PathResponse>, AppError> {
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

    let zones = parse_avoidance_zones(&params.avoid)?;

    let start_time = std::time::Instant::now();
    let start_pos = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end_pos = Vec3::new(params.end_x, params.end_y, params.end_z);

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

    // Apply avoidance post-processing
    let waypoints = apply_avoidance(&result.waypoints, &zones, &query, filter);
    let distance = pipeline::calculate_path_distance(&waypoints);

    Ok(Json(crate::routes::path::PathResponse {
        success: true,
        path: vec3_to_waypoints(&waypoints),
        distance,
        partial: result.partial,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
        partial_endpoint: None,
        recovery_suggestions: None,
    }))
}

// =============================================================================
// PATH/CHECK
// =============================================================================

/// Path validity check request.
#[derive(Debug, Deserialize)]
pub struct PathCheckRequest {
    pub map_id: u32,
    pub current_x: f32,
    pub current_y: f32,
    pub current_z: f32,
    /// Remaining path as semicolon-separated "x,y,z" waypoints.
    pub waypoints: String,
    /// Max waypoints to check ahead (default 10).
    #[serde(default = "default_max_check")]
    pub max_check: u32,
}

fn default_max_check() -> u32 {
    10
}

/// Path validity check response.
#[derive(Debug, Serialize)]
pub struct PathCheckResponse {
    pub success: bool,
    pub valid: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_invalid_segment: Option<usize>,
    pub player_on_navmesh: bool,
    pub computation_time_ms: f64,
}

/// GET /api/v1/path/check - Check if remaining path is still valid.
pub async fn path_check(
    State(state): State<AppState>,
    Query(params): Query<PathCheckRequest>,
) -> Result<Json<PathCheckResponse>, AppError> {
    validate_map_id(params.map_id)?;
    validate_coordinate(params.current_x, params.current_y, params.current_z)?;

    let waypoints = parse_waypoints(&params.waypoints)?;
    let max_check = params.max_check.min(waypoints.len() as u32) as usize;

    let start_time = std::time::Instant::now();

    let _permit = state
        .request_semaphore
        .acquire()
        .await
        .map_err(|_| AppError::Internal("Semaphore closed".into()))?;

    acquire_query!(state, params.map_id, pool, query);
    let filter = pool.filter();

    let current_pos = Vec3::new(params.current_x, params.current_y, params.current_z);

    // Check if player is on navmesh
    let player_on_navmesh = query
        .find_nearest_poly(current_pos, SEARCH_EXTENTS, filter)
        .is_ok();

    if !player_on_navmesh {
        return Ok(Json(PathCheckResponse {
            success: true,
            valid: false,
            first_invalid_segment: None,
            player_on_navmesh: false,
            computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
        }));
    }

    // Raycast from current position to first waypoint
    let mut valid = true;
    let mut first_invalid = None;

    let check_points = std::iter::once(&current_pos)
        .chain(waypoints.iter().take(max_check))
        .collect::<Vec<_>>();

    for i in 0..check_points.len() - 1 {
        let from = *check_points[i];
        let to = *check_points[i + 1];

        let reachable = if let Ok((from_ref, _)) =
            query.find_nearest_poly(from, HEIGHT_EXTENTS, filter)
        {
            query
                .raycast(from_ref, from, to, filter)
                .map(|(t, _)| t >= 1.0)
                .unwrap_or(false)
        } else {
            false
        };

        if !reachable {
            valid = false;
            first_invalid = Some(i);
            break;
        }
    }

    Ok(Json(PathCheckResponse {
        success: true,
        valid,
        first_invalid_segment: first_invalid,
        player_on_navmesh: true,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}

// =============================================================================
// PATH/CORRIDOR
// =============================================================================

/// Path with corridor widths request.
#[derive(Debug, Deserialize)]
pub struct CorridorPathRequest {
    pub map_id: u32,
    pub start_x: f32,
    pub start_y: f32,
    pub start_z: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub end_z: f32,
    #[serde(default)]
    pub smoothing: Option<String>,
    #[serde(default)]
    pub optimize: Option<bool>,
    #[serde(default)]
    pub filter_ground: Option<f32>,
    #[serde(default)]
    pub filter_water: Option<f32>,
    #[serde(default)]
    pub filter_lava: Option<f32>,
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    #[serde(default)]
    pub keep_originals: Option<bool>,
    /// How far to probe sideways for corridor width (default 20.0).
    #[serde(default = "default_probe_distance")]
    pub probe_distance: f32,
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
}

fn default_probe_distance() -> f32 {
    20.0
}

/// Path with corridor widths response.
#[derive(Debug, Serialize)]
pub struct CorridorPathResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub corridor_widths: Vec<f32>,
    pub distance: f32,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub partial: bool,
    pub computation_time_ms: f64,
}

/// GET /api/v1/path/corridor - Path with safe corridor widths.
pub async fn path_corridor(
    State(state): State<AppState>,
    Query(params): Query<CorridorPathRequest>,
) -> Result<Json<CorridorPathResponse>, AppError> {
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

    if !params.probe_distance.is_finite() || params.probe_distance <= 0.0 || params.probe_distance > 100.0 {
        return Err(AppError::InvalidParams(
            "probe_distance must be between 0 and 100".into(),
        ));
    }

    let start_time = std::time::Instant::now();
    let start_pos = Vec3::new(params.start_x, params.start_y, params.start_z);
    let end_pos = Vec3::new(params.end_x, params.end_y, params.end_z);

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
    let corridor_widths = compute_corridor_widths(&result.waypoints, &query, filter, params.probe_distance);

    Ok(Json(CorridorPathResponse {
        success: true,
        path: vec3_to_waypoints(&result.waypoints),
        corridor_widths,
        distance: result.distance,
        partial: result.partial,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}

// =============================================================================
// EXPLORE-ROUTE
// =============================================================================

/// Explore with full paths request.
#[derive(Debug, Deserialize)]
pub struct ExploreRouteRequest {
    pub map_id: u32,
    /// Repeated polygon vertex params "x,y,z".
    #[serde(default)]
    pub polygon: Vec<String>,
    /// Minimum distance between exploration points.
    #[serde(default = "default_min_distance")]
    pub min_distance: f32,
    /// Order points using TSP.
    #[serde(default)]
    pub tsp_order: Option<bool>,
    /// TSP start position.
    #[serde(default)]
    pub start_x: Option<f32>,
    #[serde(default)]
    pub start_y: Option<f32>,
    #[serde(default)]
    pub start_z: Option<f32>,
    #[serde(default)]
    pub smoothing: Option<String>,
    #[serde(default)]
    pub optimize: Option<bool>,
    #[serde(default)]
    pub filter_ground: Option<f32>,
    #[serde(default)]
    pub filter_water: Option<f32>,
    #[serde(default)]
    pub filter_lava: Option<f32>,
    #[serde(default)]
    pub smooth_iterations: Option<u32>,
    #[serde(default)]
    pub smooth_samples: Option<u32>,
    #[serde(default)]
    pub smooth_ratio: Option<f32>,
    #[serde(default)]
    pub min_corner_angle: Option<f32>,
    #[serde(default)]
    pub keep_originals: Option<bool>,
    #[serde(default)]
    pub z_extent: Option<f32>,
    /// Minimum distance to maintain from walls/obstacles (0 = disabled, max 5.0 yards).
    #[serde(default)]
    pub wall_clearance: Option<f32>,
}

fn default_min_distance() -> f32 {
    30.0
}

/// Explore route response.
#[derive(Debug, Serialize)]
pub struct ExploreRouteResponse {
    pub success: bool,
    pub points: Vec<Waypoint>,
    pub path: Vec<Waypoint>,
    pub leg_boundaries: Vec<usize>,
    pub total_distance: f32,
    pub point_count: usize,
    pub computation_time_ms: f64,
}

/// GET /api/v1/explore-route - Polygon exploration with full paths between points.
pub async fn explore_route(
    State(state): State<AppState>,
    Query(params): Query<ExploreRouteRequest>,
) -> Result<Json<ExploreRouteResponse>, AppError> {
    validate_map_id(params.map_id)?;
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

    // Parse polygon vertices
    let mut vertices = Vec::new();
    for (i, v) in params.polygon.iter().enumerate() {
        let parts: Vec<&str> = v.split(',').collect();
        if parts.len() != 3 {
            return Err(AppError::InvalidParams(format!(
                "Invalid polygon vertex {}: expected 'x,y,z'",
                i
            )));
        }
        let x: f32 = parts[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x in polygon vertex {}", i))
        })?;
        let y: f32 = parts[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y in polygon vertex {}", i))
        })?;
        let z: f32 = parts[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z in polygon vertex {}", i))
        })?;
        validate_coordinate(x, y, z)?;
        vertices.push([x, y, z]);
    }

    if vertices.len() < 3 {
        return Err(AppError::InvalidParams(
            "At least 3 polygon vertices required".into(),
        ));
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

    // Generate exploration points using Poisson disk sampling
    let sampler_config = polygon_sampling::SamplingConfig {
        min_distance: params.min_distance,
        max_candidates: 30,
        max_points: 2048,
    };

    let explore_points = polygon_sampling::bridson_sampling(&vertices, &sampler_config);

    // Snap points to navmesh
    let search_extents = Vec3::new(params.min_distance, params.min_distance, 500.0);
    let mut valid_points = Vec::new();
    for p in &explore_points {
        let v = Vec3::new(p[0], p[1], p[2]);
        if let Ok((_, snapped)) = query.find_nearest_poly(v, search_extents, filter) {
            valid_points.push(snapped);
        }
    }

    // Apply TSP ordering if requested
    if params.tsp_order.unwrap_or(false) && valid_points.len() > 1 {
        let start_pos = if let (Some(sx), Some(sy), Some(sz)) =
            (params.start_x, params.start_y, params.start_z)
        {
            [sx, sy, sz]
        } else {
            // Default to first vertex
            vertices[0]
        };

        let points_as_arrays: Vec<[f32; 3]> =
            valid_points.iter().map(|v| [v.x, v.y, v.z]).collect();
        let ordered = polygon_sampling::nearest_neighbor_tsp(&points_as_arrays, start_pos);
        valid_points = ordered.iter().map(|p| Vec3::new(p[0], p[1], p[2])).collect();
    }

    // Compute full paths between exploration points
    let options = PathOptions {
        smoothing: params.smoothing,
        optimize: params.optimize.unwrap_or(true), // Default optimize for exploration
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

    let mut all_waypoints: Vec<Vec3> = Vec::new();
    let mut leg_boundaries = vec![0usize];
    let mut total_distance = 0.0f32;
    let point_count = valid_points.len();

    for i in 0..valid_points.len().saturating_sub(1) {
        match execute_pathfind(&query, pool.mesh(), filter, valid_points[i], valid_points[i + 1], &options) {
            Ok(result) => {
                total_distance += result.distance;
                if all_waypoints.is_empty() {
                    all_waypoints.extend_from_slice(&result.waypoints);
                } else if !result.waypoints.is_empty() {
                    all_waypoints.extend_from_slice(&result.waypoints[1..]);
                }
            }
            Err(_) => {
                // Skip legs that fail to pathfind
            }
        }
        leg_boundaries.push(all_waypoints.len());
    }

    Ok(Json(ExploreRouteResponse {
        success: true,
        points: vec3_to_waypoints(&valid_points),
        path: vec3_to_waypoints(&all_waypoints),
        leg_boundaries,
        total_distance,
        point_count,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}
