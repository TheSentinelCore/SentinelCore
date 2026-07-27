//! HTTP API server for the Sentinel Questing Editor.
//!
//! Bridges the in-game Lua editor UI ↔ Rust editor backend.
//! Serves on `0.0.0.0:3031` by default (configurable via `SENTINEL_EDITOR_PORT`).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use tower_http::cors::{Any, CorsLayer};
use tracing::info;

use crate::campaign_handlers::CampaignSession;
use crate::history::{self, CommandHistory};
use crate::{CompileResult, EditorApi, EditorError, ProjectSummary};

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

/// Per-project in-memory session.
#[derive(Clone)]
pub struct ProjectSession {
    pub project: sentinel_models::authoring::Project,
    pub history: CommandHistory,
}

#[derive(Clone)]
pub struct AppState {
    pub projects_dir: PathBuf,
    pub project_store: Arc<RwLock<HashMap<String, ProjectSession>>>,
    pub campaigns_dir: PathBuf,
    pub campaign_store: Arc<RwLock<HashMap<String, CampaignSession>>>,
}

impl AppState {
    pub fn new(projects_dir: PathBuf, campaigns_dir: PathBuf) -> Self {
        Self {
            projects_dir,
            project_store: Arc::new(RwLock::new(HashMap::new())),
            campaigns_dir,
            campaign_store: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateProjectRequest {
    pub name: String,
}

#[derive(Deserialize)]
pub struct RenameProjectRequest {
    pub new_name: String,
}

#[derive(Deserialize)]
pub struct DuplicateProjectRequest {
    pub new_name: String,
}

#[derive(Serialize)]
pub struct SaveProjectResponse {
    pub success: bool,
}

#[derive(Serialize)]
pub struct DeleteProjectResponse {
    pub success: bool,
}

#[derive(Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

#[derive(Serialize)]
pub struct HistoryResponse {
    pub can_undo: bool,
    pub can_redo: bool,
    pub undo_description: Option<String>,
    pub redo_description: Option<String>,
}

#[derive(Serialize)]
pub struct UndoRedoResponse {
    pub description: String,
}

// Operation mutation payloads
#[derive(Deserialize)]
pub struct AddOperationRequest {
    pub operation: serde_json::Value,
}

#[derive(Deserialize)]
pub struct RemoveOperationRequest {
    pub index: usize,
}

#[derive(Deserialize)]
pub struct ModifyOperationRequest {
    pub index: usize,
    pub operation: serde_json::Value,
}

// Action mutation payloads
#[derive(Deserialize)]
pub struct AddActionRequest {
    pub op_index: usize,
    pub action: serde_json::Value,
}

#[derive(Deserialize)]
pub struct RemoveActionRequest {
    pub op_index: usize,
    pub index: usize,
}

#[derive(Deserialize)]
pub struct ModifyActionRequest {
    pub op_index: usize,
    pub action_index: usize,
    pub action: serde_json::Value,
}

// ---------------------------------------------------------------------------
// State helpers
// ---------------------------------------------------------------------------

fn editor_error_to_response(e: EditorError) -> (StatusCode, Json<ErrorResponse>) {
    let (code, msg) = match &e {
        EditorError::NotFound(_) => (StatusCode::NOT_FOUND, e.to_string()),
        EditorError::AlreadyExists(_) => (StatusCode::CONFLICT, e.to_string()),
        EditorError::InvalidName(_) => (StatusCode::BAD_REQUEST, e.to_string()),
        EditorError::Io(_) | EditorError::Serde(_) | EditorError::Compile(_) => {
            (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
        }
    };
    (code, Json(ErrorResponse { error: msg }))
}

fn bad_request(msg: impl Into<String>) -> (StatusCode, Json<ErrorResponse>) {
    (
        StatusCode::BAD_REQUEST,
        Json(ErrorResponse {
            error: msg.into(),
        }),
    )
}

fn internal_error(msg: impl Into<String>) -> (StatusCode, Json<ErrorResponse>) {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(ErrorResponse {
            error: msg.into(),
        }),
    )
}

// ---------------------------------------------------------------------------
// Handlers — Project CRUD
// ---------------------------------------------------------------------------

async fn handle_list_projects(
    State(state): State<AppState>,
) -> Result<Json<Vec<ProjectSummary>>, (StatusCode, Json<ErrorResponse>)> {
    EditorApi::list_projects(&state.projects_dir)
        .map(Json)
        .map_err(editor_error_to_response)
}

async fn handle_create_project(
    State(state): State<AppState>,
    Json(payload): Json<CreateProjectRequest>,
) -> Result<(StatusCode, Json<ProjectSummary>), (StatusCode, Json<ErrorResponse>)> {
    let project = EditorApi::create_project(&state.projects_dir, &payload.name)
        .map_err(editor_error_to_response)?;

    let summary = ProjectSummary {
        name: project.metadata.name.clone(),
        path: state
            .projects_dir
            .join(format!("{}.json", &project.metadata.name))
            .to_string_lossy()
            .to_string(),
        created_at: project.metadata.created_at,
        updated_at: project.metadata.updated_at,
        operation_count: project.operations.len(),
    };

    Ok((StatusCode::CREATED, Json(summary)))
}

async fn handle_load_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    // Load into store so subsequent mutations have a session
    {
        let mut store = state.project_store.write().await;
        if !store.contains_key(&name) {
            let project = EditorApi::load_project(&state.projects_dir, &name)
                .map_err(editor_error_to_response)?;
            store.insert(
                name.clone(),
                ProjectSession {
                    project,
                    history: CommandHistory::new(),
                },
            );
        }
    }

    let store = state.project_store.read().await;
    let session = store.get(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not found", name),
            }),
        )
    })?;
    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_save_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(project): Json<serde_json::Value>,
) -> Result<Json<SaveProjectResponse>, (StatusCode, Json<ErrorResponse>)> {
    let deser: sentinel_models::authoring::Project =
        serde_json::from_value(project).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: format!("Invalid project JSON: {}", e),
                }),
            )
        })?;

    if deser.metadata.name != name {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: format!(
                    "Name mismatch: path has '{}' but project has '{}'",
                    name, deser.metadata.name
                ),
            }),
        ));
    }

    // Update in-memory session
    {
        let mut store = state.project_store.write().await;
        store.insert(
            name.clone(),
            ProjectSession {
                project: deser.clone(),
                history: CommandHistory::new(),
            },
        );
    }

    EditorApi::save_project(&state.projects_dir, &deser).map_err(editor_error_to_response)?;
    Ok(Json(SaveProjectResponse { success: true }))
}

async fn handle_delete_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<DeleteProjectResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Remove from store
    {
        let mut store = state.project_store.write().await;
        store.remove(&name);
    }
    EditorApi::delete_project(&state.projects_dir, &name).map_err(editor_error_to_response)?;
    Ok(Json(DeleteProjectResponse { success: true }))
}

async fn handle_rename_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<RenameProjectRequest>,
) -> Result<Json<ProjectSummary>, (StatusCode, Json<ErrorResponse>)> {
    let project =
        EditorApi::rename_project(&state.projects_dir, &name, &payload.new_name)
            .map_err(editor_error_to_response)?;

    // Update store key
    {
        let mut store = state.project_store.write().await;
        if let Some(session) = store.remove(&name) {
            store.insert(payload.new_name.clone(), session);
        }
    }

    let summary = ProjectSummary {
        name: project.metadata.name,
        path: state
            .projects_dir
            .join(format!("{}.json", &payload.new_name))
            .to_string_lossy()
            .to_string(),
        created_at: project.metadata.created_at,
        updated_at: project.metadata.updated_at,
        operation_count: project.operations.len(),
    };

    Ok(Json(summary))
}

async fn handle_duplicate_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<DuplicateProjectRequest>,
) -> Result<Json<ProjectSummary>, (StatusCode, Json<ErrorResponse>)> {
    let project =
        EditorApi::duplicate_project(&state.projects_dir, &name, &payload.new_name)
            .map_err(editor_error_to_response)?;

    let summary = ProjectSummary {
        name: project.metadata.name,
        path: state
            .projects_dir
            .join(format!("{}.json", &payload.new_name))
            .to_string_lossy()
            .to_string(),
        created_at: project.metadata.created_at,
        updated_at: project.metadata.updated_at,
        operation_count: project.operations.len(),
    };

    Ok(Json(summary))
}

async fn handle_compile_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<CompileResult>, (StatusCode, Json<ErrorResponse>)> {
    EditorApi::compile_project(&state.projects_dir, &name)
        .map(Json)
        .map_err(editor_error_to_response)
}

async fn handle_validate_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<Vec<crate::sentinel_models::authoring::Diagnostic>>, (StatusCode, Json<ErrorResponse>)> {
    EditorApi::validate_project_file(&state.projects_dir, &name)
        .map(Json)
        .map_err(editor_error_to_response)
}

// ---------------------------------------------------------------------------
// Handlers — Command-based mutations
// ---------------------------------------------------------------------------

async fn handle_add_operation(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<AddOperationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let operation: sentinel_models::authoring::Operation =
        serde_json::from_value(payload.operation).map_err(|e| bad_request(format!("Invalid operation JSON: {}", e)))?;

    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let index = session.project.operations.len();
    session
        .history
        .execute(
            Box::new(history::AddOperation {
                index,
                operation,
            }),
            &mut session.project,
        )
        .map_err(internal_error)?;

    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_remove_operation(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<RemoveOperationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let index = payload.index;
    if index >= session.project.operations.len() {
        return Err(bad_request(format!(
            "Operation index {} out of range (len = {})",
            index,
            session.project.operations.len()
        )));
    }

    let operation = session.project.operations[index].clone();
    session
        .history
        .execute(
            Box::new(history::RemoveOperation { index, operation }),
            &mut session.project,
        )
        .map_err(internal_error)?;

    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_modify_operation(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<ModifyOperationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let new_op: sentinel_models::authoring::Operation =
        serde_json::from_value(payload.operation).map_err(|e| bad_request(format!("Invalid operation JSON: {}", e)))?;

    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let index = payload.index;
    if index >= session.project.operations.len() {
        return Err(bad_request(format!(
            "Operation index {} out of range (len = {})",
            index,
            session.project.operations.len()
        )));
    }

    let old_op = session.project.operations[index].clone();
    session
        .history
        .execute(
            Box::new(history::ModifyOperation {
                index,
                old_op,
                new_op,
            }),
            &mut session.project,
        )
        .map_err(internal_error)?;

    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_add_action(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<AddActionRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let action: sentinel_models::authoring::Action =
        serde_json::from_value(payload.action).map_err(|e| bad_request(format!("Invalid action JSON: {}", e)))?;

    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    session
        .history
        .execute(
            Box::new(history::AddAction {
                op_index: payload.op_index,
                action,
            }),
            &mut session.project,
        )
        .map_err(internal_error)?;

    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_remove_action(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<RemoveActionRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let op_index = payload.op_index;
    let index = payload.index;

    if op_index >= session.project.operations.len() {
        return Err(bad_request(format!(
            "Operation index {} out of range",
            op_index
        )));
    }

    let actions = &session.project.operations[op_index].actions;
    let actual_index = if index == usize::MAX {
        actions.len().saturating_sub(1)
    } else {
        index
    };

    if actual_index >= actions.len() {
        return Err(bad_request(format!(
            "Action index {} out of range (len = {})",
            actual_index,
            actions.len()
        )));
    }

    let action = actions[actual_index].clone();
    session
        .history
        .execute(
            Box::new(history::RemoveAction {
                op_index,
                index: actual_index,
                action,
            }),
            &mut session.project,
        )
        .map_err(internal_error)?;

    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_modify_action(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(payload): Json<ModifyActionRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let new_action: sentinel_models::authoring::Action =
        serde_json::from_value(payload.action).map_err(|e| bad_request(format!("Invalid action JSON: {}", e)))?;

    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let op_index = payload.op_index;
    let action_index = payload.action_index;

    if op_index >= session.project.operations.len() {
        return Err(bad_request(format!("Operation index {} out of range", op_index)));
    }
    if action_index >= session.project.operations[op_index].actions.len() {
        return Err(bad_request(format!(
            "Action index {} out of range (len = {})",
            action_index,
            session.project.operations[op_index].actions.len()
        )));
    }

    let old_action = session.project.operations[op_index].actions[action_index].clone();
    session
        .history
        .execute(
            Box::new(history::ModifyAction {
                op_index,
                action_index,
                old_action,
                new_action,
            }),
            &mut session.project,
        )
        .map_err(internal_error)?;

    let value = serde_json::to_value(&session.project).unwrap_or_default();
    Ok(Json(value))
}

// ---------------------------------------------------------------------------
// Handlers — Undo / Redo / History
// ---------------------------------------------------------------------------

async fn handle_undo(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<UndoRedoResponse>, (StatusCode, Json<ErrorResponse>)> {
    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let desc = session.history.undo(&mut session.project).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse { error: e }),
        )
    })?;

    Ok(Json(UndoRedoResponse { description: desc }))
}

async fn handle_redo(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<UndoRedoResponse>, (StatusCode, Json<ErrorResponse>)> {
    let mut store = state.project_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let desc = session.history.redo(&mut session.project).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse { error: e }),
        )
    })?;

    Ok(Json(UndoRedoResponse { description: desc }))
}

async fn handle_get_history(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<HistoryResponse>, (StatusCode, Json<ErrorResponse>)> {
    let store = state.project_store.read().await;
    let session = store.get(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: format!("Project '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    Ok(Json(HistoryResponse {
        can_undo: session.history.can_undo(),
        can_redo: session.history.can_redo(),
        undo_description: session.history.undo_description(),
        redo_description: session.history.redo_description(),
    }))
}

// ---------------------------------------------------------------------------
// Directory-format handlers
// ---------------------------------------------------------------------------

async fn handle_save_project_dir(
    State(state): State<AppState>,
    Path(name): Path<String>,
    Json(project): Json<serde_json::Value>,
) -> Result<Json<SaveProjectResponse>, (StatusCode, Json<ErrorResponse>)> {
    let deser: crate::sentinel_models::authoring::Project =
        serde_json::from_value(project).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: format!("Invalid project JSON: {}", e),
                }),
            )
        })?;

    if deser.metadata.name != name {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: format!(
                    "Name mismatch: path has '{}' but project has '{}'",
                    name, deser.metadata.name
                ),
            }),
        ));
    }

    let dir_path = state.projects_dir.join(format!("{}.sproject", name));
    EditorApi::save_project_dir(&dir_path, &deser).map_err(editor_error_to_response)?;
    Ok(Json(SaveProjectResponse { success: true }))
}

async fn handle_load_project_dir(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let dir_path = state.projects_dir.join(format!("{}.sproject", name));
    let project = EditorApi::load_project_dir(&dir_path)
        .map_err(editor_error_to_response)?;
    let value = serde_json::to_value(&project).unwrap_or_default();
    Ok(Json(value))
}

async fn health() -> &'static str {
    "ok"
}

// ---------------------------------------------------------------------------
// Router builder
// ---------------------------------------------------------------------------

/// Build the editor API router with shared state.
pub fn build_router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let router = Router::new()
        .route("/health", get(health))
        // Project CRUD
        .route(
            "/editor/projects",
            get(handle_list_projects).post(handle_create_project),
        )
        .route("/editor/projects/{name}", get(handle_load_project).put(handle_save_project).delete(handle_delete_project))
        .route("/editor/projects/{name}/rename", post(handle_rename_project))
        .route("/editor/projects/{name}/duplicate", post(handle_duplicate_project))
        .route("/editor/projects/{name}/compile", post(handle_compile_project))
        .route("/editor/projects/{name}/validate", post(handle_validate_project))
        // Command-based mutations
        .route("/editor/projects/{name}/add-operation", post(handle_add_operation))
        .route("/editor/projects/{name}/remove-operation", post(handle_remove_operation))
        .route("/editor/projects/{name}/modify-operation", post(handle_modify_operation))
        .route("/editor/projects/{name}/add-action", post(handle_add_action))
        .route("/editor/projects/{name}/remove-action", post(handle_remove_action))
        .route("/editor/projects/{name}/modify-action", post(handle_modify_action))
        // Undo / Redo / History
        .route("/editor/projects/{name}/undo", post(handle_undo))
        .route("/editor/projects/{name}/redo", post(handle_redo))
        .route("/editor/projects/{name}/history", get(handle_get_history))
        // Directory-format
        .route("/editor/projects/{name}/save-dir", put(handle_save_project_dir))
        .route("/editor/projects/{name}/load-dir", get(handle_load_project_dir));

    // Mount campaign routes.
    let router = crate::campaign_handlers::mount(router);

    router
        .layer(cors)
        .with_state(state)
}

// ---------------------------------------------------------------------------
// Convenience: start the server
// ---------------------------------------------------------------------------

/// Start the editor HTTP API server. Binds to `0.0.0.0:{port}` where the port
/// is read from `SENTINEL_EDITOR_PORT` env var (default 3031).
///
/// `projects_dir` controls where questing projects are stored; `campaigns_dir`
/// controls where campaign files are stored. Both default when `None`.
pub async fn start_server(
    projects_dir: Option<PathBuf>,
    campaigns_dir: Option<PathBuf>,
) {
    let port: u16 = std::env::var("SENTINEL_EDITOR_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3031);

    let proj_dir = projects_dir.unwrap_or_else(crate::default_projects_dir);
    let camp_dir = campaigns_dir.unwrap_or_else(crate::default_campaigns_dir);
    let state = AppState::new(proj_dir.clone(), camp_dir.clone());

    let app = build_router(state);

    let addr = format!("0.0.0.0:{}", port);
    info!(
        "Starting Sentinel Editor API server on {} (projects: {:?}, campaigns: {:?})",
        addr, proj_dir, camp_dir
    );

    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("Failed to bind editor server address");

    axum::serve(listener, app)
        .await
        .expect("Editor server exited with error");
}
