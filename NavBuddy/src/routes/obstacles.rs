//! Obstacle registry endpoints.

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::error::AppError;
use crate::registry::RegisteredObstacle;
use crate::state::AppState;
use crate::validation::validate_coordinate;

// =============================================================================
// UPDATE (register obstacles)
// =============================================================================

#[derive(Debug, Deserialize)]
pub struct UpdateObstaclesRequest {
    pub map_id: u32,
    /// Semicolon-separated "x,y,z,radius,cost" obstacles.
    pub obstacles: String,
}

#[derive(Debug, Serialize)]
pub struct UpdateObstaclesResponse {
    pub success: bool,
    pub count: usize,
}

/// GET /api/v1/obstacles/update - Register obstacles for a map.
pub async fn update_obstacles(
    State(state): State<AppState>,
    Query(params): Query<UpdateObstaclesRequest>,
) -> Result<Json<UpdateObstaclesResponse>, AppError> {
    let obstacles = parse_obstacles(&params.obstacles)?;
    let count = obstacles.len();
    state.obstacle_registry.update(params.map_id, obstacles);

    tracing::debug!(
        "Registered {} obstacles for map {}",
        count,
        params.map_id
    );

    Ok(Json(UpdateObstaclesResponse {
        success: true,
        count,
    }))
}

// =============================================================================
// CLEAR
// =============================================================================

#[derive(Debug, Deserialize)]
pub struct ClearObstaclesRequest {
    pub map_id: u32,
}

#[derive(Debug, Serialize)]
pub struct ClearObstaclesResponse {
    pub success: bool,
}

/// GET /api/v1/obstacles/clear - Clear registered obstacles for a map.
pub async fn clear_obstacles(
    State(state): State<AppState>,
    Query(params): Query<ClearObstaclesRequest>,
) -> Result<Json<ClearObstaclesResponse>, AppError> {
    state.obstacle_registry.clear(params.map_id);
    Ok(Json(ClearObstaclesResponse { success: true }))
}

// =============================================================================
// LIST
// =============================================================================

#[derive(Debug, Deserialize)]
pub struct ListObstaclesRequest {
    pub map_id: u32,
}

#[derive(Debug, Serialize)]
pub struct ListObstaclesResponse {
    pub success: bool,
    pub count: usize,
    pub obstacles: Vec<RegisteredObstacle>,
}

/// GET /api/v1/obstacles/list - List registered obstacles for a map.
pub async fn list_obstacles(
    State(state): State<AppState>,
    Query(params): Query<ListObstaclesRequest>,
) -> Result<Json<ListObstaclesResponse>, AppError> {
    let obstacles = state.obstacle_registry.get_raw(params.map_id);
    Ok(Json(ListObstaclesResponse {
        success: true,
        count: obstacles.len(),
        obstacles,
    }))
}

// =============================================================================
// PARSING
// =============================================================================

/// Parse obstacles from "x,y,z,radius,cost;x,y,z,radius,cost;..." format.
fn parse_obstacles(obstacles_str: &str) -> Result<Vec<RegisteredObstacle>, AppError> {
    if obstacles_str.is_empty() {
        return Ok(Vec::new());
    }

    let entries: Vec<&str> = obstacles_str.split(';').collect();
    let mut result = Vec::with_capacity(entries.len());

    for (i, entry) in entries.iter().enumerate() {
        let parts: Vec<&str> = entry.split(',').collect();
        if parts.len() != 5 {
            return Err(AppError::InvalidParams(format!(
                "Invalid obstacle {} format: expected 'x,y,z,radius,cost'",
                i
            )));
        }

        let x: f32 = parts[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x in obstacle {}", i))
        })?;
        let y: f32 = parts[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y in obstacle {}", i))
        })?;
        let z: f32 = parts[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z in obstacle {}", i))
        })?;
        let radius: f32 = parts[3].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid radius in obstacle {}", i))
        })?;
        let cost: f32 = parts[4].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid cost in obstacle {}", i))
        })?;

        validate_coordinate(x, y, z)?;

        if radius <= 0.0 || radius > 100.0 {
            return Err(AppError::InvalidParams(format!(
                "Obstacle {} radius must be 0-100, got {}",
                i, radius
            )));
        }

        result.push(RegisteredObstacle {
            x,
            y,
            z,
            radius,
            cost,
        });
    }

    if result.len() > 200 {
        return Err(AppError::InvalidParams(
            "Maximum 200 registered obstacles allowed".into(),
        ));
    }

    Ok(result)
}
