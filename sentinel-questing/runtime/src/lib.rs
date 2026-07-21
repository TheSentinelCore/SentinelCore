//! Sentinel Questing — Runtime Loader (Phase 7).
//!
//! Loads compiled profiles and provides execution state management for Lua runtime.

use sentinel_models::runtime::RuntimeProfile;

/// Execution state for a runtime profile.
#[derive(Debug, Clone)]
pub struct RuntimeState {
    /// Current operation index.
    pub current_operation: usize,
    /// Completed operation indices.
    pub completed_operations: Vec<usize>,
    /// Variable values.
    pub variables: std::collections::HashMap<String, serde_json::Value>,
}

impl RuntimeState {
    pub fn new() -> Self {
        Self {
            current_operation: 0,
            completed_operations: Vec::new(),
            variables: std::collections::HashMap::new(),
        }
    }
}

pub struct RuntimeLoader;

impl RuntimeLoader {
    /// Load a compiled runtime profile from JSON.
    pub fn load(json: &str) -> Result<RuntimeProfile, String> {
        let profile: RuntimeProfile = serde_json::from_str(json)
            .map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(profile)
    }

    /// Create initial state for profile execution.
    pub fn create_state() -> RuntimeState {
        RuntimeState::new()
    }
}