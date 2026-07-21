//! Error type for the QueryClient (typed, never stringly-typed — ADR `04` §6).

use thiserror::Error;

#[derive(Debug, Error)]
pub enum QueryClientError {
    /// The requested entity does not exist in world data.
    #[error("not found: {0}")]
    NotFound(String),
    /// Lower-level transport failure (DNS, connection, TLS, timeout…).
    #[error("transport error: {0}")]
    Transport(String),
    /// The server answered with a non-success status.
    #[error("server error {status}: {body}")]
    Server { status: u16, body: String },
    /// Response (de)serialization failed.
    #[error("decode error: {0}")]
    Decode(#[from] serde_json::Error),
}
