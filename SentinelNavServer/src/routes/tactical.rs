//! Tactical endpoints: flee, LoS cover, kite paths.

use axum::{
    extract::{Query, State},
    Json,
};
use detour::types::Vec3;
use serde::{Deserialize, Serialize};
use mmap_loader::error::MmapError;

use crate::error::AppError;
use path_smoothing::SmootherPipeline;

use crate::pipeline::{
    has_custom_filter, create_custom_filter, parse_threats,
    parse_avoidance_zones, pathfind_maybe_avoid,
    apply_wall_clearance,
    PathOptions, SEARCH_EXTENTS, HEIGHT_EXTENTS,
};
use crate::routes::path::{
    acquire_query, validate_filter_params,
    vec3_to_waypoints, Waypoint,
};
use std::sync::Arc;
use crate::blackboard::ServerBlackboard;
use crate::validation::{validate_coordinate, validate_map_id, validate_radius, validate_z_extent, validate_wall_clearance};

// =============================================================================
// FLEE
// =============================================================================

/// Flee path request.
#[derive(Debug, Deserialize)]
pub struct FleeRequest {
    pub map_id: u32,
    pub player_x: f32,
    pub player_y: f32,
    pub player_z: f32,
    /// Semicolon-separated "x,y,z" threat positions.
    pub threats: String,
    /// Desired distance from threats (default 60).
    #[serde(default = "default_flee_distance")]
    pub flee_distance: f32,
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
    pub z_extent: Option<f32>,
    #[serde(default)]
    pub wall_clearance: Option<f32>,
    /// Semicolon-separated "x,y,z,radius,cost" avoidance zones.
    #[serde(default)]
    pub avoid: Option<String>,
}

fn default_flee_distance() -> f32 {
    60.0
}

/// Flee path response.
#[derive(Debug, Serialize)]
pub struct FleeResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub distance: f32,
    /// Minimum distance to any threat along the flee path.
    pub min_threat_distance: f32,
    pub computation_time_ms: f64,
}

/// GET /api/v1/tactical/flee - Find path away from threats.
pub async fn flee(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<FleeRequest>,
) -> Result<Json<FleeResponse>, AppError> {
    validate_map_id(params.map_id)?;
    validate_coordinate(params.player_x, params.player_y, params.player_z)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;
    if let Some(z) = params.z_extent {
        validate_z_extent(z)?;
    }
    if let Some(wc) = params.wall_clearance {
        validate_wall_clearance(wc)?;
    }

    if !params.flee_distance.is_finite() || params.flee_distance <= 0.0 || params.flee_distance > 500.0 {
        return Err(AppError::InvalidParams(
            "flee_distance must be between 0 and 500".into(),
        ));
    }

    let threats = parse_threats(&params.threats)?;
    if threats.is_empty() {
        return Err(AppError::InvalidParams("At least one threat required".into()));
    }

    let start_time = std::time::Instant::now();
    let player_pos = Vec3::new(params.player_x, params.player_y, params.player_z);

    // Acquire concurrency permit (503 if overloaded)
    let _permit = state.try_acquire_permit()?;

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

    let zones = if let Some(ref avoid_str) = params.avoid {
        parse_avoidance_zones(avoid_str)?
    } else {
        Vec::new()
    };

    let options = PathOptions {
        smoothing: params.smoothing,
        optimize: params.optimize.unwrap_or(true),
        filter_ground: params.filter_ground,
        filter_water: params.filter_water,
        filter_lava: params.filter_lava,
        z_extent: params.z_extent,
        wall_clearance: params.wall_clearance,
    };

    // Compute threat centroid
    let centroid = {
        let mut cx = 0.0f32;
        let mut cy = 0.0f32;
        let mut cz = 0.0f32;
        for t in &threats {
            cx += t.x;
            cy += t.y;
            cz += t.z;
        }
        let n = threats.len() as f32;
        Vec3::new(cx / n, cy / n, cz / n)
    };

    // Flee vector: direction away from threat centroid
    let flee_dir = {
        let dx = player_pos.x - centroid.x;
        let dy = player_pos.y - centroid.y;
        let len = (dx * dx + dy * dy).sqrt();
        if len > 0.001 {
            (dx / len, dy / len)
        } else {
            (1.0, 0.0) // Arbitrary direction if player is at centroid
        }
    };

    // Try flee path at several rotated angles
    let angles = [0.0_f32, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0];
    let mut best_result = None;
    let mut best_min_threat_dist = 0.0f32;

    for &angle_deg in &angles {
        let angle_rad = angle_deg.to_radians();
        let rotated_x = flee_dir.0 * angle_rad.cos() - flee_dir.1 * angle_rad.sin();
        let rotated_y = flee_dir.0 * angle_rad.sin() + flee_dir.1 * angle_rad.cos();

        let target = Vec3::new(
            player_pos.x + rotated_x * params.flee_distance,
            player_pos.y + rotated_y * params.flee_distance,
            player_pos.z,
        );

        // Snap target to navmesh
        if let Ok((_, snapped)) = query.find_nearest_poly(target, SEARCH_EXTENTS, filter) {
            if let Ok(result) = pathfind_maybe_avoid(&query, &pool, filter, player_pos, snapped, &options, &zones) {
                // Score: minimum distance from any waypoint to any threat
                let min_dist = result
                    .waypoints
                    .iter()
                    .flat_map(|wp: &Vec3| threats.iter().map(move |t| wp.distance_2d(t)))
                    .fold(f32::MAX, f32::min);

                if best_result.is_none() || min_dist > best_min_threat_dist {
                    best_min_threat_dist = min_dist;
                    best_result = Some(result);
                }
            }
        }
    }

    match best_result {
        Some(result) => Ok(Json(FleeResponse {
            success: true,
            path: vec3_to_waypoints(&result.waypoints),
            distance: result.distance,
            min_threat_distance: best_min_threat_dist,
            computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
        })),
        None => Err(AppError::PathfindingFailed(
            "Could not find any flee path".into(),
        )),
    }
}

// =============================================================================
// LOS COVER
// =============================================================================

/// LoS cover positions request.
#[derive(Debug, Deserialize)]
pub struct LosCoverRequest {
    pub map_id: u32,
    pub player_x: f32,
    pub player_y: f32,
    pub player_z: f32,
    /// Semicolon-separated "x,y,z" threat positions.
    pub threats: String,
    /// Search radius (default 30).
    #[serde(default = "default_search_radius")]
    pub search_radius: f32,
    /// Max results to return (default 5).
    #[serde(default = "default_max_results")]
    pub max_results: u32,
}

fn default_search_radius() -> f32 {
    30.0
}

fn default_max_results() -> u32 {
    5
}

/// A cover position.
#[derive(Debug, Serialize)]
pub struct CoverPosition {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    /// Number of threats blocked by LoS at this position.
    pub blocked_threats: usize,
    /// Distance from player to this position.
    pub distance: f32,
}

/// LoS cover response.
#[derive(Debug, Serialize)]
pub struct LosCoverResponse {
    pub success: bool,
    pub positions: Vec<CoverPosition>,
    pub computation_time_ms: f64,
}

/// GET /api/v1/tactical/los - Find positions that break line-of-sight to threats.
pub async fn los_cover(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<LosCoverRequest>,
) -> Result<Json<LosCoverResponse>, AppError> {
    validate_map_id(params.map_id)?;
    validate_coordinate(params.player_x, params.player_y, params.player_z)?;
    validate_radius(params.search_radius)?;

    let threats = parse_threats(&params.threats)?;
    if threats.is_empty() {
        return Err(AppError::InvalidParams("At least one threat required".into()));
    }

    let max_results = params.max_results.min(20) as usize;

    let start_time = std::time::Instant::now();
    let player_pos = Vec3::new(params.player_x, params.player_y, params.player_z);

    // Acquire concurrency permit (503 if overloaded)
    let _permit = state.try_acquire_permit()?;

    acquire_query!(state, params.map_id, pool, query);
    let filter = pool.filter();

    // Find the player's polygon for random point sampling
    let (player_ref, _) = query
        .find_nearest_poly(player_pos, SEARCH_EXTENTS, filter)
        .map_err(|_| AppError::PathfindingFailed("Player not on navmesh".into()))?;

    // Sample candidate positions around the player
    let num_samples = 25usize;
    let mut candidates: Vec<(Vec3, usize, f32)> = Vec::new();

    for _ in 0..num_samples {
        if let Ok((_, candidate)) =
            query.find_random_point_around_circle(player_ref, player_pos, params.search_radius, filter)
        {
            // For each candidate, raycast to each threat
            let mut blocked = 0usize;
            if let Ok((cand_ref, _)) = query.find_nearest_poly(candidate, HEIGHT_EXTENTS, filter) {
                for threat in &threats {
                    match query.raycast(cand_ref, candidate, *threat, filter) {
                        Ok((hit_t, _)) => {
                            if hit_t < 1.0 {
                                blocked += 1; // Wall blocks LoS to this threat
                            }
                        }
                        Err(_) => {
                            blocked += 1; // Assume blocked if raycast fails
                        }
                    }
                }
            }

            let dist = player_pos.distance_2d(&candidate);
            candidates.push((candidate, blocked, dist));
        }
    }

    // Sort: most threats blocked first, then by distance (closer = better)
    candidates.sort_by(|a, b| {
        b.1.cmp(&a.1)
            .then_with(|| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal))
    });

    // Return top results
    let positions: Vec<CoverPosition> = candidates
        .into_iter()
        .take(max_results)
        .filter(|(_, blocked, _)| *blocked > 0) // Only include positions that block at least 1 threat
        .map(|(pos, blocked, dist)| CoverPosition {
            x: pos.x,
            y: pos.y,
            z: pos.z,
            blocked_threats: blocked,
            distance: dist,
        })
        .collect();

    Ok(Json(LosCoverResponse {
        success: true,
        positions,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}

// =============================================================================
// KITE
// =============================================================================

/// Kite path request.
#[derive(Debug, Deserialize)]
pub struct KiteRequest {
    pub map_id: u32,
    pub player_x: f32,
    pub player_y: f32,
    pub player_z: f32,
    pub target_x: f32,
    pub target_y: f32,
    pub target_z: f32,
    /// Desired distance from target while kiting.
    pub kite_radius: f32,
    /// Arc degrees to generate (default 120).
    #[serde(default = "default_arc_degrees")]
    pub arc_degrees: f32,
    /// "cw" or "ccw" (default "ccw").
    #[serde(default = "default_direction")]
    pub direction: String,
    #[serde(default)]
    pub smoothing: Option<String>,
    #[serde(default)]
    pub filter_ground: Option<f32>,
    #[serde(default)]
    pub filter_water: Option<f32>,
    #[serde(default)]
    pub filter_lava: Option<f32>,
    #[serde(default)]
    pub wall_clearance: Option<f32>,
}

fn default_arc_degrees() -> f32 {
    120.0
}

fn default_direction() -> String {
    "ccw".to_string()
}

/// Kite path response.
#[derive(Debug, Serialize)]
pub struct KiteResponse {
    pub success: bool,
    pub path: Vec<Waypoint>,
    pub waypoint_count: usize,
    pub computation_time_ms: f64,
}

/// GET /api/v1/tactical/kite - Generate kiting arc path around a target.
pub async fn kite(
    State(state): State<Arc<ServerBlackboard>>,
    Query(params): Query<KiteRequest>,
) -> Result<Json<KiteResponse>, AppError> {
    validate_map_id(params.map_id)?;
    validate_coordinate(params.player_x, params.player_y, params.player_z)?;
    validate_coordinate(params.target_x, params.target_y, params.target_z)?;
    validate_radius(params.kite_radius)?;
    validate_filter_params(params.filter_ground, params.filter_water, params.filter_lava)?;
    if let Some(wc) = params.wall_clearance {
        validate_wall_clearance(wc)?;
    }

    if !params.arc_degrees.is_finite() || params.arc_degrees <= 0.0 || params.arc_degrees > 360.0 {
        return Err(AppError::InvalidParams(
            "arc_degrees must be between 0 and 360".into(),
        ));
    }

    let clockwise = params.direction.to_lowercase() == "cw";

    let start_time = std::time::Instant::now();
    let player_pos = Vec3::new(params.player_x, params.player_y, params.player_z);
    let target_pos = Vec3::new(params.target_x, params.target_y, params.target_z);

    // Acquire concurrency permit (503 if overloaded)
    let _permit = state.try_acquire_permit()?;

    acquire_query!(state, params.map_id, pool, query);

    let custom_filter;
    let filter = if has_custom_filter(params.filter_ground, params.filter_water, params.filter_lava) {
        custom_filter = create_custom_filter(
            params.filter_ground,
            params.filter_water,
            params.filter_lava,
        )?;
        &custom_filter
    } else {
        pool.filter()
    };

    // Compute current angle from target to player
    let dx = player_pos.x - target_pos.x;
    let dy = player_pos.y - target_pos.y;
    let start_angle = dy.atan2(dx);

    // Generate arc waypoints
    let arc_rad = params.arc_degrees.to_radians();
    let num_points = (params.arc_degrees / 10.0).ceil() as usize; // One point every ~10 degrees
    let num_points = num_points.max(3).min(36);

    let mut waypoints = Vec::with_capacity(num_points);

    for i in 0..num_points {
        let t = i as f32 / (num_points - 1) as f32;
        let angle = if clockwise {
            start_angle - arc_rad * t
        } else {
            start_angle + arc_rad * t
        };

        let point = Vec3::new(
            target_pos.x + angle.cos() * params.kite_radius,
            target_pos.y + angle.sin() * params.kite_radius,
            player_pos.z, // Use player's height as initial guess
        );

        // Snap to navmesh
        let search = Vec3::new(params.kite_radius * 0.3, params.kite_radius * 0.3, 50.0);
        if let Ok((_, snapped)) = query.find_nearest_poly(point, search, filter) {
            waypoints.push(snapped);
        }
    }

    // Apply smoothing pipeline to arc waypoints
    let mut waypoints = if params.smoothing.as_deref().unwrap_or("none") != "none" {
        let smoother = SmootherPipeline::with_default_config();
        smoother.smooth(&waypoints, &query, filter)
    } else {
        waypoints
    };

    if let Some(clearance) = params.wall_clearance {
        if clearance > 0.0 {
            waypoints = apply_wall_clearance(&waypoints, &query, filter, clearance);
        }
    }

    let count = waypoints.len();

    Ok(Json(KiteResponse {
        success: true,
        path: vec3_to_waypoints(&waypoints),
        waypoint_count: count,
        computation_time_ms: start_time.elapsed().as_secs_f64() * 1000.0,
    }))
}
