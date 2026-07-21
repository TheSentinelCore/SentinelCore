//! HTTP API server for the Sentinel Questing Editor.
//!
//! Bridges the in-game Lua editor UI ↔ Rust editor backend.
//! Serves on `0.0.0.0:3031` by default (configurable via `SENTINEL_EDITOR_PORT`).

use std::path::PathBuf;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tower_http::cors::{Any, CorsLayer};
use tracing::info;

use crate::{CompileResult, EditorApi, EditorError, ProjectSummary};

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

#[derive(Clone)]
pub struct AppState {
    pub projects_dir: PathBuf,
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

// ---------------------------------------------------------------------------
// Handlers
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
    let project = EditorApi::load_project(&state.projects_dir, &name)
        .map_err(editor_error_to_response)?;
    let value = serde_json::to_value(&project).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_save_project(
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

    // Verify name matches path
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

    EditorApi::save_project(&state.projects_dir, &deser).map_err(editor_error_to_response)?;
    Ok(Json(SaveProjectResponse { success: true }))
}

async fn handle_delete_project(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<DeleteProjectResponse>, (StatusCode, Json<ErrorResponse>)> {
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

    Router::new()
        .route("/health", get(health))
        .route(
            "/editor/projects",
            get(handle_list_projects).post(handle_create_project),
        )
        .route("/editor/projects/{name}", get(handle_load_project).put(handle_save_project).delete(handle_delete_project))
        .route("/editor/projects/{name}/rename", post(handle_rename_project))
        .route("/editor/projects/{name}/duplicate", post(handle_duplicate_project))
        .route("/editor/projects/{name}/compile", post(handle_compile_project))
        .route("/editor/projects/{name}/validate", post(handle_validate_project))
        .layer(cors)
        .with_state(state)
}

// ---------------------------------------------------------------------------
// Convenience: start the server
// ---------------------------------------------------------------------------

/// Start the editor HTTP API server. Binds to `0.0.0.0:{port}` where the port
/// is read from `SENTINEL_EDITOR_PORT` env var (default 3031).
pub async fn start_server(projects_dir: Option<PathBuf>) {
    let port: u16 = std::env::var("SENTINEL_EDITOR_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3031);

    let dir = projects_dir.unwrap_or_else(crate::default_projects_dir);
    let state = AppState { projects_dir: dir.clone() };

    let app = build_router(state);

    let addr = format!("0.0.0.0:{}", port);
    info!("Starting Sentinel Editor API server on {} (projects: {:?})", addr, dir);

    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("Failed to bind editor server address");

    axum::serve(listener, app)
        .await
        .expect("Editor server exited with error");
}
