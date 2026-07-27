//! Campaign HTTP handlers — Axum routes for Campaign CRUD and graph mutations.
//!
//! Each mutable endpoint follows the same pattern:
//! 1. Lock the in-memory `campaign_store`
//! 2. Get the `CampaignSession` for the named campaign
//! 3. Build the appropriate `CampaignCommand`
//! 4. `history.execute(command, &mut session.campaign)`
//! 5. Auto-save to disk
//! 6. Return the updated campaign or a status response

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{delete, get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::campaign_history::{
    AddCondition, AddEdge, AddGraph, AddNode, CampaignHistory,
    ModifyNode, RemoveEdge, RemoveNode,
};
use crate::campaign_store::{CampaignApi, CampaignSummary};
use crate::EditorError;

// ---------------------------------------------------------------------------
// Campaign session
// ---------------------------------------------------------------------------

/// Per-campaign in-memory session with undo/redo history.
pub struct CampaignSession {
    pub campaign: sentinel_models::platform::Campaign,
    pub history: CampaignHistory,
}

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateCampaignRequest {
    pub name: String,
}

/// Generic body for operations that reference a graph by id.
#[derive(Deserialize)]
pub struct GraphIdParam {
    pub graph_id: Uuid,
}

/// Body for add-node and update-node.
#[derive(Deserialize)]
pub struct NodeMutationRequest {
    pub graph_id: Uuid,
    pub node: serde_json::Value,
}

/// Body for add-edge.
#[derive(Deserialize)]
pub struct EdgeMutationRequest {
    pub graph_id: Uuid,
    pub edge: serde_json::Value,
}

/// Body for add-graph.
#[derive(Deserialize)]
pub struct AddGraphRequest {
    pub graph: serde_json::Value,
}

/// Body for add-condition.
#[derive(Deserialize)]
pub struct AddConditionRequest {
    pub condition: serde_json::Value,
}

#[derive(Serialize)]
pub struct DeleteResponse {
    pub success: bool,
}

#[derive(Serialize)]
pub struct UndoRedoResponse {
    pub description: String,
}

// ---------------------------------------------------------------------------
// Error helpers
// ---------------------------------------------------------------------------

fn editor_error_to_response(e: EditorError) -> (StatusCode, Json<crate::server::ErrorResponse>) {
    let msg = e.to_string();
    let code = match &e {
        EditorError::NotFound(_) => StatusCode::NOT_FOUND,
        EditorError::AlreadyExists(_) => StatusCode::CONFLICT,
        EditorError::InvalidName(_) => StatusCode::BAD_REQUEST,
        EditorError::Io(_) | EditorError::Serde(_) | EditorError::Compile(_) => {
            StatusCode::INTERNAL_SERVER_ERROR
        }
    };
    (code, Json(crate::server::ErrorResponse { error: msg }))
}

fn bad_request(msg: impl Into<String>) -> (StatusCode, Json<crate::server::ErrorResponse>) {
    (
        StatusCode::BAD_REQUEST,
        Json(crate::server::ErrorResponse {
            error: msg.into(),
        }),
    )
}

fn internal_error(msg: impl Into<String>) -> (StatusCode, Json<crate::server::ErrorResponse>) {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(crate::server::ErrorResponse {
            error: msg.into(),
        }),
    )
}

// ---------------------------------------------------------------------------
// Handlers — Campaign CRUD
// ---------------------------------------------------------------------------

async fn handle_list_campaigns(
    State(state): State<crate::server::AppState>,
) -> Result<Json<Vec<CampaignSummary>>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    CampaignApi::list(&state.campaigns_dir)
        .map(Json)
        .map_err(editor_error_to_response)
}

async fn handle_create_campaign(
    State(state): State<crate::server::AppState>,
    Json(payload): Json<CreateCampaignRequest>,
) -> Result<(StatusCode, Json<CampaignSummary>), (StatusCode, Json<crate::server::ErrorResponse>)> {
    let campaign = CampaignApi::create(&state.campaigns_dir, &payload.name)
        .map_err(editor_error_to_response)?;

    // Insert into in-memory store.
    {
        let mut store = state.campaign_store.write().await;
        store.insert(
            campaign.name.clone(),
            CampaignSession {
                campaign: campaign.clone(),
                history: CampaignHistory::new(),
            },
        );
    }

    let node_count: usize = campaign.graphs.iter().map(|g| g.nodes.len()).sum();
    let edge_count: usize = campaign.graphs.iter().map(|g| g.edges.len()).sum();

    Ok((
        StatusCode::CREATED,
        Json(CampaignSummary {
            name: campaign.name,
            id: campaign.id,
            updated_at: chrono::Utc::now().to_rfc3339(),
            node_count,
            edge_count,
        }),
    ))
}

async fn handle_load_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    // Load into store so subsequent mutations have a session.
    {
        let mut store = state.campaign_store.write().await;
        if !store.contains_key(&name) {
            let campaign = CampaignApi::load(&state.campaigns_dir, &name)
                .map_err(editor_error_to_response)?;
            store.insert(
                name.clone(),
                CampaignSession {
                    campaign,
                    history: CampaignHistory::new(),
                },
            );
        }
    }

    let store = state.campaign_store.read().await;
    let session = store.get(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not found", name),
            }),
        )
    })?;
    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_delete_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<DeleteResponse>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    // Remove from store.
    {
        let mut store = state.campaign_store.write().await;
        store.remove(&name);
    }
    CampaignApi::delete(&state.campaigns_dir, &name).map_err(editor_error_to_response)?;
    Ok(Json(DeleteResponse { success: true }))
}

// ---------------------------------------------------------------------------
// Node mutation handlers
// ---------------------------------------------------------------------------

async fn handle_add_node(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
    Json(payload): Json<NodeMutationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let node: sentinel_models::platform::Node = serde_json::from_value(payload.node)
        .map_err(|e| bad_request(format!("Invalid Node JSON: {}", e)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    session
        .history
        .execute(
            Box::new(AddNode {
                campaign_name: name.clone(),
                graph_id: payload.graph_id,
                node,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_update_node(
    State(state): State<crate::server::AppState>,
    Path((name, node_id_str)): Path<(String, String)>,
    Json(payload): Json<NodeMutationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let node_id = Uuid::parse_str(&node_id_str)
        .map_err(|_| bad_request(format!("Invalid node_id UUID: {}", node_id_str)))?;

    let new_node: sentinel_models::platform::Node = serde_json::from_value(payload.node)
        .map_err(|e| bad_request(format!("Invalid Node JSON: {}", e)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    // Find the old node.
    let old_node = {
        let graph = session
            .campaign
            .graphs
            .iter()
            .find(|g| g.id == payload.graph_id)
            .ok_or_else(|| bad_request(format!("Graph {} not found", payload.graph_id)))?;

        graph
            .nodes
            .iter()
            .find(|n| n.id == node_id)
            .ok_or_else(|| bad_request(format!("Node {} not found", node_id)))?
            .clone()
    };

    session
        .history
        .execute(
            Box::new(ModifyNode {
                campaign_name: name.clone(),
                graph_id: payload.graph_id,
                old_node,
                new_node,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_remove_node(
    State(state): State<crate::server::AppState>,
    Path((name, node_id_str)): Path<(String, String)>,
    Json(payload): Json<GraphIdParam>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let node_id = Uuid::parse_str(&node_id_str)
        .map_err(|_| bad_request(format!("Invalid node_id UUID: {}", node_id_str)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    // Find the node to remove.
    let node = {
        let graph = session
            .campaign
            .graphs
            .iter()
            .find(|g| g.id == payload.graph_id)
            .ok_or_else(|| bad_request(format!("Graph {} not found", payload.graph_id)))?;

        graph
            .nodes
            .iter()
            .find(|n| n.id == node_id)
            .ok_or_else(|| bad_request(format!("Node {} not found", node_id)))?
            .clone()
    };

    session
        .history
        .execute(
            Box::new(RemoveNode {
                campaign_name: name.clone(),
                graph_id: payload.graph_id,
                node,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

// ---------------------------------------------------------------------------
// Edge mutation handlers
// ---------------------------------------------------------------------------

async fn handle_add_edge(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
    Json(payload): Json<EdgeMutationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let edge: sentinel_models::platform::Edge = serde_json::from_value(payload.edge)
        .map_err(|e| bad_request(format!("Invalid Edge JSON: {}", e)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    session
        .history
        .execute(
            Box::new(AddEdge {
                campaign_name: name.clone(),
                graph_id: payload.graph_id,
                edge,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

async fn handle_remove_edge(
    State(state): State<crate::server::AppState>,
    Path((name, edge_id_str)): Path<(String, String)>,
    Json(payload): Json<GraphIdParam>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let edge_id = Uuid::parse_str(&edge_id_str)
        .map_err(|_| bad_request(format!("Invalid edge_id UUID: {}", edge_id_str)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    // Find the edge to remove.
    let edge = {
        let graph = session
            .campaign
            .graphs
            .iter()
            .find(|g| g.id == payload.graph_id)
            .ok_or_else(|| bad_request(format!("Graph {} not found", payload.graph_id)))?;

        graph
            .edges
            .iter()
            .find(|e| e.id == edge_id)
            .ok_or_else(|| bad_request(format!("Edge {} not found", edge_id)))?
            .clone()
    };

    session
        .history
        .execute(
            Box::new(RemoveEdge {
                campaign_name: name.clone(),
                graph_id: payload.graph_id,
                edge,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

// ---------------------------------------------------------------------------
// Graph mutation handlers
// ---------------------------------------------------------------------------

async fn handle_add_graph(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
    Json(payload): Json<AddGraphRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let graph: sentinel_models::platform::Graph = serde_json::from_value(payload.graph)
        .map_err(|e| bad_request(format!("Invalid Graph JSON: {}", e)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    session
        .history
        .execute(
            Box::new(AddGraph {
                campaign_name: name.clone(),
                graph,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

// ---------------------------------------------------------------------------
// Condition mutation handlers
// ---------------------------------------------------------------------------

async fn handle_add_condition(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
    Json(payload): Json<AddConditionRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let condition: sentinel_models::platform::ConditionDef =
        serde_json::from_value(payload.condition)
            .map_err(|e| bad_request(format!("Invalid ConditionDef JSON: {}", e)))?;

    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    session
        .history
        .execute(
            Box::new(AddCondition {
                campaign_name: name.clone(),
                condition,
            }),
            &mut session.campaign,
        )
        .map_err(internal_error)?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    let value = serde_json::to_value(&session.campaign).unwrap_or_default();
    Ok(Json(value))
}

// ---------------------------------------------------------------------------
// Compile / Validate (stubs — full pipeline in later phase)
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct CompileCampaignResult {
    pub campaign_id: Uuid,
    pub campaign_name: String,
    pub graph_count: usize,
    pub node_count: usize,
    pub edge_count: usize,
    pub message: String,
}

async fn handle_compile_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<CompileCampaignResult>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let campaign = CampaignApi::load(&state.campaigns_dir, &name)
        .map_err(editor_error_to_response)?;

    let node_count: usize = campaign.graphs.iter().map(|g| g.nodes.len()).sum();
    let edge_count: usize = campaign.graphs.iter().map(|g| g.edges.len()).sum();

    Ok(Json(CompileCampaignResult {
        campaign_id: campaign.id,
        campaign_name: campaign.name,
        graph_count: campaign.graphs.len(),
        node_count,
        edge_count,
        message: "Campaign compile — full pipeline available in a later phase".to_string(),
    }))
}

async fn handle_validate_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<Vec<serde_json::Value>>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    // Load the campaign to ensure it exists; validation against the Campaign
    // schema will be implemented when the campaign-aware validator is ready.
    let _campaign = CampaignApi::load(&state.campaigns_dir, &name)
        .map_err(editor_error_to_response)?;

    // For now, return empty diagnostics — no campaign-specific rules yet.
    Ok(Json(Vec::new()))
}

// ---------------------------------------------------------------------------
// Undo / Redo handlers
// ---------------------------------------------------------------------------

async fn handle_undo_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<UndoRedoResponse>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let desc = session
        .history
        .undo(&mut session.campaign)
        .map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(crate::server::ErrorResponse { error: e }),
            )
        })?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    Ok(Json(UndoRedoResponse { description: desc }))
}

async fn handle_redo_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<UndoRedoResponse>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    let mut store = state.campaign_store.write().await;
    let session = store.get_mut(&name).ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(crate::server::ErrorResponse {
                error: format!("Campaign '{}' not loaded. Load it first.", name),
            }),
        )
    })?;

    let desc = session
        .history
        .redo(&mut session.campaign)
        .map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(crate::server::ErrorResponse { error: e }),
            )
        })?;

    CampaignApi::save(&state.campaigns_dir, &session.campaign)
        .map_err(editor_error_to_response)?;

    Ok(Json(UndoRedoResponse { description: desc }))
}

// ---------------------------------------------------------------------------
// Router attachment
// ---------------------------------------------------------------------------

/// Mount all campaign routes onto the given router.
///
/// Call this from `build_router()` in `server.rs`:
/// ```ignore
/// campaign_handlers::mount(router)
/// ```
pub fn mount(router: Router<crate::server::AppState>) -> Router<crate::server::AppState> {
    router
        // Campaign CRUD
        .route(
            "/editor/campaigns",
            get(handle_list_campaigns).post(handle_create_campaign),
        )
        .route(
            "/editor/campaigns/{name}",
            get(handle_load_campaign).delete(handle_delete_campaign),
        )
        // Node mutations
        .route("/editor/campaigns/{name}/nodes", post(handle_add_node))
        .route(
            "/editor/campaigns/{name}/nodes/{node_id}",
            put(handle_update_node).delete(handle_remove_node),
        )
        // Edge mutations
        .route("/editor/campaigns/{name}/edges", post(handle_add_edge))
        .route(
            "/editor/campaigns/{name}/edges/{edge_id}",
            delete(handle_remove_edge),
        )
        // Graph mutations
        .route("/editor/campaigns/{name}/graphs", post(handle_add_graph))
        // Condition mutations
        .route("/editor/campaigns/{name}/conditions", post(handle_add_condition))
        // Compile / Validate
        .route("/editor/campaigns/{name}/compile", post(handle_compile_campaign))
        .route("/editor/campaigns/{name}/validate", post(handle_validate_campaign))
        // Undo / Redo
        .route("/editor/campaigns/{name}/undo", post(handle_undo_campaign))
        .route("/editor/campaigns/{name}/redo", post(handle_redo_campaign))
}
