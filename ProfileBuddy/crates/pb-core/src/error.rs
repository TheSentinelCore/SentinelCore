//! Error types for ProfileBuddy
//!
//! Provides a unified error type for all operations.

use thiserror::Error;

/// Result type alias for ProfileBuddy operations
pub type Result<T> = std::result::Result<T, Error>;

/// ProfileBuddy error types
#[derive(Error, Debug)]
pub enum Error {
    /// Failed to parse GatherMate2 Lua data
    #[error("Failed to parse GatherMate2 data: {0}")]
    ParseError(String),

    /// File I/O error
    #[error("File I/O error: {0}")]
    IoError(#[from] std::io::Error),

    /// Zone not found in database
    #[error("Zone not found: {zone_id} ({zone_name})")]
    ZoneNotFound { zone_id: u32, zone_name: String },

    /// No nodes found for the given selection
    #[error("No nodes found for selection: {0}")]
    NoNodesFound(String),

    /// Invalid coordinate data
    #[error("Invalid coordinate: {0}")]
    InvalidCoordinate(String),

    /// Profile generation failed
    #[error("Profile generation failed: {0}")]
    ProfileGenerationError(String),

    /// JSON serialization error
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    /// Regex compilation error
    #[error("Regex error: {0}")]
    RegexError(#[from] regex::Error),

    /// Invalid algorithm configuration
    #[error("Invalid optimizer configuration: {0}")]
    InvalidConfig(String),

    /// NavBuddy service unavailable
    #[error("NavBuddy unavailable at {url}: {reason}")]
    NavBuddyUnavailable { url: String, reason: String },

    /// HTTP request error
    #[error("HTTP error: {0}")]
    HttpError(#[from] reqwest::Error),
}
