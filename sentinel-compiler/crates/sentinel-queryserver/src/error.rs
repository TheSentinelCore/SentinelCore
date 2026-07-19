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
        let (status, error_message) = match &self {
            QueryError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            QueryError::InvalidRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            QueryError::Validation(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            QueryError::Database(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)),
            QueryError::Cache(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Cache error: {}", e)),
            QueryError::Graph(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Graph error: {}", e)),
            QueryError::Serialization(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Serialization error: {}", e)),
            QueryError::Internal(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("Internal error: {}", e)),
        };
        
        tracing::error!("Query error: {}", error_message);
        
        let body = Json(json!({
            "error": error_message,
        }));
        
        (status, body).into_response()
    }
}

/// Result type for QueryServer operations
pub type QueryResult<T> = Result<T, QueryError>;