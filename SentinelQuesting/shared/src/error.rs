//! Typed error definitions shared across the Sentinel Questing model crates.

use thiserror::Error;

/// Errors produced while constructing, validating, or (de)serializing model entities.
///
/// These are *model-level* errors only. Subsystem-specific errors (importer, compiler,
/// validator, query) live in their own crates and wrap or reference these where useful.
#[derive(Debug, Error)]
pub enum ModelError {
    /// A UUID that is required to be present was missing or malformed.
    #[error("missing or invalid identifier for entity: {0}")]
    MissingId(String),

    /// Two entities claimed the same stable identifier within one collection.
    #[error("duplicate id `{id}` detected in `{collection}`")]
    DuplicateId {
        collection: &'static str,
        id: String,
    },

    /// A reference pointed at an entity that does not exist in the owning project.
    #[error("broken reference: {0} references missing {1}")]
    BrokenReference(String, String),

    /// JSON (de)serialization failed.
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    /// An invariant required by the ADRs was violated.
    #[error("invariant violated: {0}")]
    Invariant(String),
}

/// Convenience result alias used throughout the model layer.
pub type Result<T> = std::result::Result<T, ModelError>;
