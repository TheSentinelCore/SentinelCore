//! Application error types.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use thiserror::Error;

/// Application error type.
#[derive(Debug, Error)]
pub enum AppError {
    /// Map not loaded or not found.
    #[error("Map {0} not loaded")]
    MapNotFound(u32),

    /// Pathfinding failed.
    #[error("Pathfinding failed: {0}")]
    PathfindingFailed(String),

    /// Invalid parameters.
    #[error("Invalid parameters: {0}")]
    InvalidParams(String),

    /// Internal server error.
    #[error("Internal error: {0}")]
    Internal(String),

    /// Bad request (e.g. unknown game identifier).
    #[error("Bad request: {0}")]
    BadRequest(String),

    /// Server overloaded — too many concurrent requests.
    #[error("Server overloaded, try again later")]
    Overloaded,
}

/// Error response body.
#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: String,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, message) = match &self {
            AppError::MapNotFound(map_id) => (
                StatusCode::NOT_FOUND,
                "MAP_NOT_FOUND",
                format!("Map {} not loaded", map_id),
            ),
            AppError::PathfindingFailed(msg) => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "PATHFINDING_FAILED",
                msg.clone(),
            ),
            AppError::InvalidParams(msg) => (
                StatusCode::BAD_REQUEST,
                "INVALID_PARAMS",
                msg.clone(),
            ),
            AppError::Internal(msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                msg.clone(),
            ),
            AppError::BadRequest(msg) => (
                StatusCode::BAD_REQUEST,
                "BAD_REQUEST",
                msg.clone(),
            ),
            AppError::Overloaded => (
                StatusCode::SERVICE_UNAVAILABLE,
                "OVERLOADED",
                "Server overloaded, try again later".to_string(),
            ),
        };

        let body = Json(ErrorResponse {
            error: message,
            code: code.to_string(),
        });

        (status, body).into_response()
    }
}

impl From<anyhow::Error> for AppError {
    fn from(err: anyhow::Error) -> Self {
        AppError::Internal(err.to_string())
    }
}
