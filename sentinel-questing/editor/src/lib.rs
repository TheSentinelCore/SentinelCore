//! Sentinel Questing — In-Game Editor (Phase 8).
//!
//! This module provides the editor backend for the in-game editor UI.
//! The Lua frontend handles rendering; Rust provides serialization and validation.

use sentinel_models::authoring::Project;

/// Editor operations that the Lua UI can call.
pub struct EditorApi;

impl EditorApi {
    /// Create a new empty project.
    pub fn create_project(name: &str) -> Project {
        sentinel_models::authoring::new_project(name)
    }

    /// Save a project to JSON.
    pub fn save_project(project: &Project) -> Result<String, String> {
        serde_json::to_string_pretty(project)
            .map_err(|e| format!("Serialization error: {}", e))
    }

    /// Load a project from JSON.
    pub fn load_project(json: &str) -> Result<Project, String> {
        serde_json::from_str(json)
            .map_err(|e| format!("Deserialization error: {}", e))
    }

    /// Validate a project (delegates to Validator).
    pub fn validate_project(project: &Project) -> Vec<sentinel_models::authoring::Diagnostic> {
        sentinel_validator::Validator::validate(project)
    }
}

pub struct SentinelEditor;