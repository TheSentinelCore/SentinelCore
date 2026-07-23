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

pub mod history;
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
    /// Validator-time project diagnostics + the compiler's `CompileReport` diagnostics (e.g.
    /// `UNMAPPED_CONDITION`) — both channels merged, never one dropped in favor of the other.
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
// Internal helpers
// ---------------------------------------------------------------------------

/// Whether the project is stored as a flat JSON file or a directory tree.
enum Resolution {
    File(PathBuf),
    Dir(PathBuf),
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

            // Detect both .json files and .sproject directories
            let (is_project, name) = if path.extension().is_some_and(|e| e == "json") {
                let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("unknown");
                (true, stem.to_string())
            } else if path.extension().is_some_and(|e| e == "sproject") && path.is_dir() {
                let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("unknown");
                (true, stem.to_string())
            } else {
                (false, String::new())
            };

            if is_project {
                // Load the project to get metadata and operation count
                let result = if path.is_dir() {
                    Self::load_project_dir(&path)
                } else {
                    Self::load_project_from_path(&path)
                };

                match result {
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
                        // Skip corrupt projects — still list with basic metadata
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
        let json_path = Self::project_path(projects_dir, name);
        let dir_path = projects_dir.join(format!("{}.sproject", name));

        if json_path.exists() || dir_path.exists() {
            return Err(EditorError::AlreadyExists(name.to_string()));
        }

        // Ensure parent directory exists
        if let Some(parent) = json_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let project = sentinel_models::authoring::new_project(name);
        let json = serde_json::to_string_pretty(&project)?;
        fs::write(&json_path, json)?;
        Ok(project)
    }

    // ---- Save project -------------------------------------------------

    /// Save a project to its JSON file (by name).
    /// Auto-detects directory vs flat-file format based on what exists on disk.
    pub fn save_project(projects_dir: &Path, project: &Project) -> Result<(), EditorError> {
        Self::validate_name(&project.metadata.name)?;
        let dir_path = projects_dir.join(format!("{}.sproject", project.metadata.name));
        if dir_path.is_dir() {
            return Self::save_project_dir(&dir_path, project);
        }
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

    // ---- Directory-format save/load (ADR §29) -------------------------

    /// Save a project as a modular directory structure.
    ///
    /// Layout:
    ///   `<path>.sproject/
    ///     project.json        — metadata, settings, indices
    ///     operations/<id>.json — one file per operation
    ///     areas/<id>.json      — one file per area`
    pub fn save_project_dir(path: &Path, project: &Project) -> Result<(), EditorError> {
        fs::create_dir_all(path)?;

        // Recreate clean subdirectories (no stale files from previous saves).
        let ops_dir = path.join("operations");
        let areas_dir = path.join("areas");
        if ops_dir.exists() {
            fs::remove_dir_all(&ops_dir)?;
        }
        if areas_dir.exists() {
            fs::remove_dir_all(&areas_dir)?;
        }
        fs::create_dir_all(&ops_dir)?;
        fs::create_dir_all(&areas_dir)?;

        // Write the index manifest.
        let index = sentinel_models::authoring::ProjectDirIndex::from(project);
        let json = serde_json::to_string_pretty(&index)?;
        fs::write(path.join("project.json"), json)?;

        // Write each operation to its own file.
        for op in &project.operations {
            let op_path = ops_dir.join(format!("{}.json", op.id));
            let json = serde_json::to_string_pretty(op)?;
            fs::write(op_path, json)?;
        }

        // Write each area to its own file.
        for area in &project.areas {
            let area_path = areas_dir.join(format!("{}.json", area.id));
            let json = serde_json::to_string_pretty(area)?;
            fs::write(area_path, json)?;
        }

        Ok(())
    }

    /// Load a project from a modular directory structure.
    pub fn load_project_dir(path: &Path) -> Result<Project, EditorError> {
        // Read the index manifest.
        let index_path = path.join("project.json");
        if !index_path.exists() {
            return Err(EditorError::NotFound(
                path.file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("?")
                    .to_string(),
            ));
        }
        let json = fs::read_to_string(&index_path)?;
        let index: sentinel_models::authoring::ProjectDirIndex =
            serde_json::from_str(&json)?;

        // Read individual operations.
        let mut operations = Vec::new();
        let ops_dir = path.join("operations");
        if ops_dir.is_dir() {
            for entry in fs::read_dir(&ops_dir)? {
                let entry = entry?;
                let op_path = entry.path();
                if op_path.extension().is_some_and(|e| e == "json") {
                    let op_json = fs::read_to_string(&op_path)?;
                    let op: sentinel_models::authoring::Operation =
                        serde_json::from_str(&op_json)?;
                    operations.push(op);
                }
            }
        }

        // Read individual areas.
        let mut areas = Vec::new();
        let areas_dir = path.join("areas");
        if areas_dir.is_dir() {
            for entry in fs::read_dir(&areas_dir)? {
                let entry = entry?;
                let area_path = entry.path();
                if area_path.extension().is_some_and(|e| e == "json") {
                    let area_json = fs::read_to_string(&area_path)?;
                    let area: sentinel_models::authoring::Area =
                        serde_json::from_str(&area_json)?;
                    areas.push(area);
                }
            }
        }

        // Reorder operations and areas to match the index order.
        let op_index: std::collections::HashMap<uuid::Uuid, _> = operations
            .into_iter()
            .map(|op| (op.id, op))
            .collect();
        operations = index
            .operations
            .iter()
            .filter_map(|idx| op_index.get(&idx.id).cloned())
            .collect();

        let area_index: std::collections::HashMap<uuid::Uuid, _> = areas
            .into_iter()
            .map(|a| (a.id, a))
            .collect();
        areas = index
            .areas
            .iter()
            .filter_map(|idx| area_index.get(&idx.id).cloned())
            .collect();

        Ok(index.into_project(operations, areas))
    }

    /// Resolve a name to either a `.json` file or a `.sproject` directory,
    /// returning the canonical path for use by load/save.
    fn resolve_project_path(projects_dir: &Path, name: &str) -> Resolution {
        let json_path = projects_dir.join(format!("{name}.json"));
        if json_path.exists() {
            return Resolution::File(json_path);
        }
        let dir_path = projects_dir.join(format!("{name}.sproject"));
        if dir_path.is_dir() {
            return Resolution::Dir(dir_path);
        }
        Resolution::File(json_path)
    }

    // ---- Load project -------------------------------------------------

    /// Load a project by name from the projects directory.
    /// Auto-detects flat-file (`.json`) vs directory (`.sproject/`) format.
    pub fn load_project(projects_dir: &Path, name: &str) -> Result<Project, EditorError> {
        Self::validate_name(name)?;
        match Self::resolve_project_path(projects_dir, name) {
            Resolution::File(path) => Self::load_project_from_path(&path),
            Resolution::Dir(path) => Self::load_project_dir(&path),
        }
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

    // ---- Rename project -----------------------------------------------

    /// Rename a project (rename file/directory + update ProjectMetadata).
    pub fn rename_project(
        projects_dir: &Path,
        old_name: &str,
        new_name: &str,
    ) -> Result<Project, EditorError> {
        Self::validate_name(old_name)?;
        Self::validate_name(new_name)?;

        let new_json = Self::project_path(projects_dir, new_name);
        let new_dir = projects_dir.join(format!("{}.sproject", new_name));

        if new_json.exists() || new_dir.exists() {
            return Err(EditorError::AlreadyExists(new_name.to_string()));
        }

        // Detect source format and load.
        let (mut project, was_dir) = match Self::resolve_project_path(projects_dir, old_name) {
            Resolution::File(path) => (Self::load_project_from_path(&path)?, false),
            Resolution::Dir(path) => (Self::load_project_dir(&path)?, true),
        };

        project.metadata.name = new_name.to_string();
        let now = Utc::now().to_rfc3339();
        project.metadata.updated_at = now;

        // Save in the same format, then remove the old location.
        if was_dir {
            Self::save_project_dir(&new_dir, &project)?;
            let old_dir = projects_dir.join(format!("{}.sproject", old_name));
            if old_dir.exists() {
                fs::remove_dir_all(old_dir)?;
            }
        } else {
            Self::save_project_to_path(&new_json, &project)?;
            let old_file = Self::project_path(projects_dir, old_name);
            if old_file.exists() {
                fs::remove_file(old_file)?;
            }
        }

        Ok(project)
    }

    // ---- Delete project -----------------------------------------------

    /// Delete a project (file or directory).
    pub fn delete_project(projects_dir: &Path, name: &str) -> Result<(), EditorError> {
        Self::validate_name(name)?;
        match Self::resolve_project_path(projects_dir, name) {
            Resolution::File(path) => {
                fs::remove_file(path)?;
                Ok(())
            }
            Resolution::Dir(path) => {
                fs::remove_dir_all(path)?;
                Ok(())
            }
        }
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
        let (profile, report) = sentinel_compiler::Compiler::compile(project)
            .map_err(|e| EditorError::Compile(e.to_string()))?;

        let profile_json = serde_json::to_string(&profile)?;
        let operation_count = profile.operations.len();

        // Never drop the compiler's own diagnostics (e.g. UNMAPPED_CONDITION fail-open).
        let mut diagnostics = project.diagnostics.clone();
        diagnostics.extend(report.unmapped_conditions);

        Ok(CompileResult { profile_json, operation_count, diagnostics })
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
            sticky: false,
            looping: false,
            actions: vec![
                sentinel_models::authoring::Action {
                    id: uuid::Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    class_restriction: None,
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
    fn compile_surfaces_unmapped_condition_diagnostic() {
        use sentinel_models::authoring::{Action, ActionPayload, ConditionAction, Operation};
        let mut project = sentinel_models::authoring::new_project("cond-test");
        let mut op = Operation::new("op".to_string());
        op.actions.push(Action {
            id: uuid::Uuid::new_v4(), enabled: true, condition: None, class_restriction: None, note: None,
            payload: ActionPayload::Condition(ConditionAction {
                expression: "NotARealPredicate(1)".to_string(),
                role: sentinel_models::authoring::ConditionRole::Completion,
            }),
        });
        project.operations.push(op);
        let result = EditorApi::compile_project_inner(&project).unwrap();
        assert!(result.diagnostics.iter().any(|d| d.code == "UNMAPPED_CONDITION"), "got: {:?}", result.diagnostics);
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

    // ---- Directory-format tests (ADR §29) -----------------------------

    #[test]
    fn save_and_load_dir_round_trip() {
        let (_tmp, dir) = tmp_projects_dir();
        let dir = dir.path().join("my-project.sproject");

        let mut project = sentinel_models::authoring::new_project("my-project");

        // Add two operations with distinct data.
        let op1 = sentinel_models::authoring::Operation {
            id: uuid::Uuid::new_v4(),
            name: "Northshire".to_string(),
            description: Some("Starting area".to_string()),
            minimum_level: Some(1),
            maximum_level: Some(5),
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            actions: vec![
                sentinel_models::authoring::Action {
                    id: uuid::Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    class_restriction: None,
                    note: None,
                    payload: sentinel_models::authoring::ActionPayload::Comment(
                        sentinel_models::authoring::CommentAction {
                            text: "Begin".to_string(),
                        },
                    ),
                },
            ],
            notes: None,
        };
        let op2 = sentinel_models::authoring::Operation {
            id: uuid::Uuid::new_v4(),
            name: "Goldshire".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: false,
            conditions: vec!["done_northshire".to_string()],
            sticky: false,
            looping: false,
            actions: vec![],
            notes: Some("Need to finish".to_string()),
        };
        project.operations.push(op1);
        project.operations.push(op2);

        // Add one area.
        let area = sentinel_models::authoring::Area {
            id: uuid::Uuid::new_v4(),
            zone: Some("Elwynn Forest".to_string()),
            name: "Northshire Valley".to_string(),
            points: vec![
                sentinel_models::authoring::Position {
                    map: 0,
                    world_x: 0.0,
                    world_y: 0.0,
                    world_z: 0.0,
                    orientation: None,
                },
                sentinel_models::authoring::Position {
                    map: 0,
                    world_x: 100.0,
                    world_y: 0.0,
                    world_z: 0.0,
                    orientation: None,
                },
            ],
            tags: vec!["start".to_string()],
        };
        project.areas.push(area);

        // Save as directory.
        EditorApi::save_project_dir(&dir, &project).unwrap();

        // Verify structure.
        assert!(dir.join("project.json").exists());
        assert!(dir.join("operations").is_dir());
        assert!(dir.join("areas").is_dir());

        // Verify operations directory has the right files.
        let mut op_files: Vec<_> = std::fs::read_dir(dir.join("operations"))
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .collect();
        op_files.sort();
        assert_eq!(op_files.len(), 2);

        // Verify areas directory has the right files.
        let area_files: Vec<_> = std::fs::read_dir(dir.join("areas"))
            .unwrap()
            .filter_map(|e| e.ok())
            .collect();
        assert_eq!(area_files.len(), 1);

        // Load back.
        let loaded = EditorApi::load_project_dir(&dir).unwrap();
        assert_eq!(loaded, project);
    }

    #[test]
    fn dir_save_then_auto_load() {
        let (projects_dir, _tmp) = tmp_projects_dir();

        // Create a project via normal API, then save as dir.
        let mut project = EditorApi::create_project(&projects_dir, "dir-test").unwrap();
        project.metadata.description = "Directory test".to_string();
        project.operations.push(sentinel_models::authoring::Operation {
            id: uuid::Uuid::new_v4(),
            name: "TestOp".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            actions: vec![],
            notes: None,
        });

        // Remove the .json file that create_project wrote.
        let json_path = projects_dir.join("dir-test.json");
        if json_path.exists() {
            std::fs::remove_file(&json_path).unwrap();
        }

        // Save to .sproject directory.
        let dir_path = projects_dir.join("dir-test.sproject");
        EditorApi::save_project_dir(&dir_path, &project).unwrap();

        // The file-based .json should NOT exist for dir-test now.
        assert!(!json_path.exists());

        // Auto-detect load should find the .sproject directory.
        let mut loaded = EditorApi::load_project(&projects_dir, "dir-test").unwrap();
        assert_eq!(loaded.metadata.description, "Directory test");
        assert_eq!(loaded.operations.len(), 1);

        // Auto-detect save should update the directory.
        loaded.metadata.description = "Updated via auto-save".to_string();
        EditorApi::save_project(&projects_dir, &loaded).unwrap();
        let reloaded = EditorApi::load_project(&projects_dir, "dir-test").unwrap();
        assert_eq!(reloaded.metadata.description, "Updated via auto-save");
        assert!(dir_path.exists());
        assert!(!json_path.exists());

        // Auto-detect list should pick it up.
        let summaries = EditorApi::list_projects(&projects_dir).unwrap();
        let names: Vec<_> = summaries.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&"dir-test"));
    }

    #[test]
    fn delete_dir_project() {
        let (projects_dir, _tmp) = tmp_projects_dir();

        // Create a project as directory format.
        let project = EditorApi::create_project(&projects_dir, "to-delete-dir").unwrap();
        let dir_path = projects_dir.join("to-delete-dir.sproject");
        EditorApi::save_project_dir(&dir_path, &project).unwrap();

        // Remove the original .json file so only the dir remains.
        let json_path = projects_dir.join("to-delete-dir.json");
        if json_path.exists() {
            std::fs::remove_file(&json_path).unwrap();
        }

        // Delete via auto-detect should remove the directory.
        EditorApi::delete_project(&projects_dir, "to-delete-dir").unwrap();
        assert!(!dir_path.exists());

        // Load should now fail.
        assert!(matches!(
            EditorApi::load_project(&projects_dir, "to-delete-dir"),
            Err(EditorError::NotFound(_))
        ));
    }

    #[test]
    fn backward_compat_file_format() {
        let (projects_dir, _tmp) = tmp_projects_dir();

        // Traditional monolithic JSON should still work.
        let mut project = EditorApi::create_project(&projects_dir, "legacy").unwrap();
        project.metadata.description = "Legacy format".to_string();
        EditorApi::save_project(&projects_dir, &project).unwrap();

        let json_path = projects_dir.join("legacy.json");
        assert!(json_path.exists());
        let dir_path = projects_dir.join("legacy.sproject");
        assert!(!dir_path.exists());

        let loaded = EditorApi::load_project(&projects_dir, "legacy").unwrap();
        assert_eq!(loaded.metadata.description, "Legacy format");
        assert_eq!(loaded, project);
    }
}

