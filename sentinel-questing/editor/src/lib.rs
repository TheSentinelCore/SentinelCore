//! Sentinel Questing — Editor Backend (Phase 8).
//!
//! This crate provides both a library of editor operations (`EditorApi`) and an
//! optional Axum HTTP server (`server` module) that bridges the Lua editor UI ↔
//! Rust backend.
//!
//! The library API handles all filesystem operations:
//! - Project CRUD (list, create, load, save, rename, delete, duplicate)
//! - Compilation (load project → compiler → return RuntimeProfile JSON)
//! - Validation (load project → validator → return diagnostics)

pub mod server;

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sentinel_models::authoring::{Project, Diagnostic};
use thiserror::Error;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Summary of a project, returned by `list_projects()`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectSummary {
    pub name: String,
    pub path: String,
    pub created_at: String,
    pub updated_at: String,
    pub operation_count: usize,
}

/// Result of a compilation request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompileResult {
    /// The compiled RuntimeProfile as a JSON string (ready to be loaded by Lua runtime).
    pub profile_json: String,
    /// Number of runtime operations in the compiled profile.
    pub operation_count: usize,
    /// Any diagnostics emitted during compilation.
    pub diagnostics: Vec<Diagnostic>,
}

/// Errors that can occur during editor operations.
#[derive(Debug, Error)]
pub enum EditorError {
    #[error("Project '{0}' not found")]
    NotFound(String),

    #[error("Project '{0}' already exists")]
    AlreadyExists(String),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("Compilation error: {0}")]
    Compile(String),

    #[error("Invalid name '{0}': names must not be empty, contain '..', or path separators")]
    InvalidName(String),
}

// ---------------------------------------------------------------------------
// Default projects directory
// ---------------------------------------------------------------------------

/// Default directory name for questing projects, relative to wherever the
/// editor binary is launched (or configurable via env var `SENTINEL_PROJECTS_DIR`).
pub fn default_projects_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("SENTINEL_PROJECTS_DIR") {
        return PathBuf::from(dir);
    }
    PathBuf::from(".questing/projects")
}

// ---------------------------------------------------------------------------
// EditorApi — all filesystem operations
// ---------------------------------------------------------------------------

pub struct EditorApi;

impl EditorApi {
    // ---- Sanity helpers ------------------------------------------------

    /// Validate a project name (no path separators, no `..`, not empty).
    fn validate_name(name: &str) -> Result<(), EditorError> {
        if name.is_empty() || name.contains('/') || name.contains('\\') || name.contains("..") {
            return Err(EditorError::InvalidName(name.to_string()));
        }
        Ok(())
    }

    fn project_path(projects_dir: &Path, name: &str) -> PathBuf {
        projects_dir.join(format!("{}.json", name))
    }

    // ---- List projects ------------------------------------------------

    /// Scan the projects directory and return a sorted listing of all projects.
    pub fn list_projects(projects_dir: &Path) -> Result<Vec<ProjectSummary>, EditorError> {
        if !projects_dir.exists() {
            return Ok(Vec::new());
        }

        let mut summaries = Vec::new();
        for entry in fs::read_dir(projects_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.extension().map_or(false, |e| e == "json") {
                let name = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("unknown")
                    .to_string();

                // Load the project to get metadata and operation count
                match Self::load_project_from_path(&path) {
                    Ok(project) => {
                        summaries.push(ProjectSummary {
                            name,
                            path: path.to_string_lossy().to_string(),
                            created_at: project.metadata.created_at,
                            updated_at: project.metadata.updated_at,
                            operation_count: project.operations.len(),
                        });
                    }
                    Err(_) => {
                        // Skip corrupt files — still list with basic metadata
                        if let Ok(meta) = fs::metadata(&path) {
                            summaries.push(ProjectSummary {
                                name,
                                path: path.to_string_lossy().to_string(),
                                created_at: "unknown".to_string(),
                                updated_at: format_timestamp(meta.modified().ok()),
                                operation_count: 0,
                            });
                        }
                    }
                }
            }
        }

        summaries.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(summaries)
    }

    // ---- Create project -----------------------------------------------

    /// Create a new empty project with the given name.
    pub fn create_project(projects_dir: &Path, name: &str) -> Result<Project, EditorError> {
        Self::validate_name(name)?;
        let path = Self::project_path(projects_dir, name);

        if path.exists() {
            return Err(EditorError::AlreadyExists(name.to_string()));
        }

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        let project = sentinel_models::authoring::new_project(name);
        let json = serde_json::to_string_pretty(&project)?;
        fs::write(&path, json)?;
        Ok(project)
    }

    // ---- Load project -------------------------------------------------

    /// Load a project by name from the projects directory.
    pub fn load_project(projects_dir: &Path, name: &str) -> Result<Project, EditorError> {
        Self::validate_name(name)?;
        let path = Self::project_path(projects_dir, name);
        Self::load_project_from_path(&path)
    }

    fn load_project_from_path(path: &Path) -> Result<Project, EditorError> {
        if !path.exists() {
            let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("?");
            return Err(EditorError::NotFound(name.to_string()));
        }
        let json = fs::read_to_string(path)?;
        let project: Project = serde_json::from_str(&json)?;
        Ok(project)
    }

    // ---- Save project -------------------------------------------------

    /// Save a project to its JSON file (by name).
    pub fn save_project(projects_dir: &Path, project: &Project) -> Result<(), EditorError> {
        Self::validate_name(&project.metadata.name)?;
        let path = Self::project_path(projects_dir, &project.metadata.name);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(project)?;
        fs::write(&path, json)?;
        Ok(())
    }

    /// Save a project to its JSON file (by explicit path).
    pub fn save_project_to_path(path: &Path, project: &Project) -> Result<(), EditorError> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(project)?;
        fs::write(path, json)?;
        Ok(())
    }

    // ---- Rename project -----------------------------------------------

    /// Rename a project (rename the JSON file + update ProjectMetadata).
    pub fn rename_project(
        projects_dir: &Path,
        old_name: &str,
        new_name: &str,
    ) -> Result<Project, EditorError> {
        Self::validate_name(old_name)?;
        Self::validate_name(new_name)?;

        let old_path = Self::project_path(projects_dir, old_name);
        let new_path = Self::project_path(projects_dir, new_name);

        if !old_path.exists() {
            return Err(EditorError::NotFound(old_name.to_string()));
        }
        if new_path.exists() {
            return Err(EditorError::AlreadyExists(new_name.to_string()));
        }

        // Load, update metadata, write new file, remove old
        let mut project = Self::load_project_from_path(&old_path)?;
        project.metadata.name = new_name.to_string();
        let now = Utc::now().to_rfc3339();
        project.metadata.updated_at = now;

        Self::save_project_to_path(&new_path, &project)?;
        fs::remove_file(&old_path)?;

        Ok(project)
    }

    // ---- Delete project -----------------------------------------------

    /// Delete a project file.
    pub fn delete_project(projects_dir: &Path, name: &str) -> Result<(), EditorError> {
        Self::validate_name(name)?;
        let path = Self::project_path(projects_dir, name);
        if !path.exists() {
            return Err(EditorError::NotFound(name.to_string()));
        }
        fs::remove_file(path)?;
        Ok(())
    }

    // ---- Duplicate project --------------------------------------------

    /// Deep-copy a project under a new name.
    pub fn duplicate_project(
        projects_dir: &Path,
        name: &str,
        new_name: &str,
    ) -> Result<Project, EditorError> {
        let project = Self::load_project(projects_dir, name)?;
        Self::create_project(projects_dir, new_name)?;

        let mut duplicate = Self::load_project(projects_dir, new_name)?;
        // Copy all fields except metadata identity
        duplicate.variables = project.variables;
        duplicate.npc_library = project.npc_library;
        duplicate.quest_library = project.quest_library;
        duplicate.object_library = project.object_library;
        duplicate.areas = project.areas;
        duplicate.operations = project.operations;
        duplicate.settings = project.settings;
        duplicate.metadata.description = project.metadata.description;
        duplicate.metadata.author = project.metadata.author;
        duplicate.metadata.version = project.metadata.version;
        duplicate.metadata.faction = project.metadata.faction;
        duplicate.metadata.race = project.metadata.race;
        duplicate.metadata.class = project.metadata.class;
        duplicate.metadata.minimum_level = project.metadata.minimum_level;
        duplicate.metadata.maximum_level = project.metadata.maximum_level;
        let now = Utc::now().to_rfc3339();
        duplicate.metadata.updated_at = now.clone();
        duplicate.metadata.created_at = now;
        duplicate.diagnostics.clear();

        Self::save_project(projects_dir, &duplicate)?;
        Ok(duplicate)
    }

    // ---- Compile ------------------------------------------------------

    /// Load a project and compile it to a RuntimeProfile. Returns the JSON
    /// string that the Lua runtime can consume directly.
    pub fn compile_project(
        projects_dir: &Path,
        name: &str,
    ) -> Result<CompileResult, EditorError> {
        let project = Self::load_project(projects_dir, name)?;
        Self::compile_project_inner(&project)
    }

    /// Compile an already-loaded project (useful when the editor has it in memory).
    pub fn compile_project_inner(project: &Project) -> Result<CompileResult, EditorError> {
        let profile = sentinel_compiler::Compiler::compile(project)
            .map_err(|e| EditorError::Compile(e.to_string()))?;

        let profile_json = serde_json::to_string(&profile)?;
        let operation_count = profile.operations.len();

        Ok(CompileResult {
            profile_json,
            operation_count,
            diagnostics: project.diagnostics.clone(),
        })
    }

    // ---- Validate -----------------------------------------------------

    /// Load a project and run validation. Returns diagnostics.
    pub fn validate_project_file(
        projects_dir: &Path,
        name: &str,
    ) -> Result<Vec<Diagnostic>, EditorError> {
        let project = Self::load_project(projects_dir, name)?;
        Ok(sentinel_validator::Validator::validate(&project))
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn format_timestamp(modified: Option<std::time::SystemTime>) -> String {
    match modified {
        Some(time) => {
            let dt: DateTime<Utc> = time.into();
            dt.to_rfc3339()
        }
        None => "unknown".to_string(),
    }
}

// ---------------------------------------------------------------------------
// Re-exports
// ---------------------------------------------------------------------------

pub use sentinel_models;
pub use sentinel_compiler;
pub use sentinel_validator;

// ======================================================================
// Tests (W8.2 — Editor Rust backend tests)
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// Helper: create a temporary directory for the project files.
    fn tmp_projects_dir() -> (PathBuf, tempfile::TempDir) {
        let dir = tempfile::tempdir().expect("failed to create temp dir");
        let projects_dir = dir.path().join("projects");
        std::fs::create_dir_all(&projects_dir).unwrap();
        (projects_dir, dir)
    }

    #[test]
    fn list_projects_returns_empty_for_new_dir() {
        let (dir, _tmp) = tmp_projects_dir();
        let projects = EditorApi::list_projects(&dir).unwrap();
        assert!(projects.is_empty());
    }

    #[test]
    fn create_and_list_project() {
        let (dir, _tmp) = tmp_projects_dir();
        let project = EditorApi::create_project(&dir, "test-profile").unwrap();
        assert_eq!(project.metadata.name, "test-profile");
        assert!(project.metadata.id != uuid::Uuid::nil());

        let projects = EditorApi::list_projects(&dir).unwrap();
        assert_eq!(projects.len(), 1);
        assert_eq!(projects[0].name, "test-profile");
        assert_eq!(projects[0].operation_count, 0);
    }

    #[test]
    fn create_duplicate_fails() {
        let (dir, _tmp) = tmp_projects_dir();
        EditorApi::create_project(&dir, "dup").unwrap();
        let result = EditorApi::create_project(&dir, "dup");
        assert!(matches!(result, Err(EditorError::AlreadyExists(_))));
    }

    #[test]
    fn load_nonexistent_fails() {
        let (dir, _tmp) = tmp_projects_dir();
        let result = EditorApi::load_project(&dir, "nope");
        assert!(matches!(result, Err(EditorError::NotFound(_))));
    }

    #[test]
    fn save_and_reload_project() {
        let (dir, _tmp) = tmp_projects_dir();
        let mut project = EditorApi::create_project(&dir, "save-test").unwrap();
        project.metadata.description = "Updated description".to_string();
        EditorApi::save_project(&dir, &project).unwrap();

        let loaded = EditorApi::load_project(&dir, "save-test").unwrap();
        assert_eq!(loaded.metadata.description, "Updated description");
    }

    #[test]
    fn rename_project() {
        let (dir, _tmp) = tmp_projects_dir();
        EditorApi::create_project(&dir, "old-name").unwrap();
        EditorApi::rename_project(&dir, "old-name", "new-name").unwrap();

        // Old file should be gone
        assert!(matches!(
            EditorApi::load_project(&dir, "old-name"),
            Err(EditorError::NotFound(_))
        ));
        // New file should exist
        let loaded = EditorApi::load_project(&dir, "new-name").unwrap();
        assert_eq!(loaded.metadata.name, "new-name");
    }

    #[test]
    fn delete_project() {
        let (dir, _tmp) = tmp_projects_dir();
        EditorApi::create_project(&dir, "to-delete").unwrap();
        EditorApi::delete_project(&dir, "to-delete").unwrap();
        let projects = EditorApi::list_projects(&dir).unwrap();
        assert!(projects.is_empty());
    }

    #[test]
    fn duplicate_project() {
        let (dir, _tmp) = tmp_projects_dir();
        let mut project = EditorApi::create_project(&dir, "original").unwrap();
        // Add a variable to verify deep copy
        project.variables.push(sentinel_models::authoring::Variable::new(
            "counter",
            sentinel_models::authoring::VariableType::Int,
            sentinel_models::authoring::VariableValue::Int(0),
        ));
        EditorApi::save_project(&dir, &project).unwrap();

        EditorApi::duplicate_project(&dir, "original", "copy").unwrap();
        let copy = EditorApi::load_project(&dir, "copy").unwrap();
        assert_eq!(copy.variables.len(), 1);
        assert_eq!(copy.variables[0].name, "counter");
    }

    #[test]
    fn validate_project_runs_validator() {
        let (dir, _tmp) = tmp_projects_dir();
        EditorApi::create_project(&dir, "valid").unwrap();
        let diags = EditorApi::validate_project_file(&dir, "valid").unwrap();
        // Empty project should pass validation (no variables, no operations)
        assert!(diags.is_empty());
    }

    #[test]
    fn compile_minimal_project() {
        let (dir, _tmp) = tmp_projects_dir();
        let mut project = EditorApi::create_project(&dir, "compile-me").unwrap();
        // Add an NPC + operation for compilation
        let npc_id = uuid::Uuid::new_v4();
        project.npc_library.push(sentinel_models::authoring::NPCReference {
            id: npc_id,
            entry: Some(12345),
            guid: None,
            name: "Test NPC".to_string(),
            faction: None,
            roles: vec![],
            position: None,
            source: None,
            notes: None,
        });
        project.operations.push(sentinel_models::authoring::Operation {
            id: uuid::Uuid::new_v4(),
            name: "TestOp".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            actions: vec![
                sentinel_models::authoring::Action {
                    id: uuid::Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: None,
                    payload: sentinel_models::authoring::ActionPayload::Comment(
                        sentinel_models::authoring::CommentAction {
                            text: "Hello".to_string(),
                        },
                    ),
                },
            ],
            notes: None,
        });
        EditorApi::save_project(&dir, &project).unwrap();

        let result = EditorApi::compile_project(&dir, "compile-me").unwrap();
        assert_eq!(result.operation_count, 1);
        assert!(!result.profile_json.is_empty());
        // Verify it parses as a valid RuntimeProfile
        let profile: sentinel_models::runtime::RuntimeProfile =
            serde_json::from_str(&result.profile_json).unwrap();
        assert_eq!(profile.operations.len(), 1);
        assert!(!profile.content_hash.is_empty());
    }

    #[test]
    fn invalid_name_rejected() {
        let (dir, _tmp) = tmp_projects_dir();
        assert!(matches!(
            EditorApi::create_project(&dir, "has/slash"),
            Err(EditorError::InvalidName(_))
        ));
        assert!(matches!(
            EditorApi::create_project(&dir, ""),
            Err(EditorError::InvalidName(_))
        ));
        assert!(matches!(
            EditorApi::create_project(&dir, "has..dots"),
            Err(EditorError::InvalidName(_))
        ));
    }
}

