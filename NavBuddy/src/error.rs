//! Application error types.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;

/// Application error type.
#[derive(Debug)]
pub enum AppError {
    /// Map not loaded or not found.
    MapNotFound(u32),
    /// Pathfinding failed.
    PathfindingFailed(String),
    /// Invalid parameters.
    InvalidParams(String),
    /// Internal server error.
    Internal(String),
}

/// Error response body.
#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: String,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            AppError::MapNotFound(map_id) => (
                StatusCode::NOT_FOUND,
                "MAP_NOT_FOUND",
                format!("Map {} not loaded", map_id),
            ),
            AppError::PathfindingFailed(msg) => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "PATHFINDING_FAILED",
                msg,
            ),
            AppError::InvalidParams(msg) => (
                StatusCode::BAD_REQUEST,
                "INVALID_PARAMS",
                msg,
            ),
            AppError::Internal(msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                msg,
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
