//! Error types for QueryServer

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

/// QueryServer error types
#[derive(Debug, Error)]
pub enum QueryError {
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),
    
    #[error("Not found: {0}")]
    NotFound(String),
    
    #[error("Invalid request: {0}")]
    InvalidRequest(String),
    
    #[error("Cache error: {0}")]
    Cache(String),
    
    #[error("Graph error: {0}")]
    Graph(String),
    
    #[error("Validation error: {0}")]
    Validation(String),
    
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
    
    #[error("Internal error: {0}")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for QueryError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            QueryError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            QueryError::InvalidRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            QueryError::Validation(msg) => (StatusCode::BAD_REQUEST, msg),
            QueryError::Database(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Database error".to_string()),
            QueryError::Cache(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Cache error".to_string()),
            QueryError::Graph(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Graph error".to_string()),
            QueryError::Serialization(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Serialization error".to_string()),
            QueryError::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Internal error".to_string()),
        };
        
        let body = Json(json!({
            "error": error_message,
        }));
        
        (status, body).into_response()
    }
}

/// Result type for QueryServer operations
pub type QueryResult<T> = Result<T, QueryError>;