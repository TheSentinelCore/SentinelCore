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

/// One campaign diagnostic, in the shape the Lua validation bar renders.
///
/// `node_id` is what makes a diagnostic navigable: clicking it selects the offending node in the
/// Graph panel. A diagnostic that cannot name a node is still emitted, with `node_id: null`.
///
/// Deliberately local rather than `query_types::ValidationDiagnostic`, which has no `node_id` and
/// belongs to a different (project-level) validation surface.
#[derive(Debug, Clone, Serialize)]
pub struct CampaignDiagnostic {
    pub severity: String,
    pub code: String,
    pub message: String,
    pub node_id: Option<Uuid>,
}

/// The intent field a node names a quest with, as an integer, or `None`.
fn quest_id_of(node: &sentinel_models::platform::Node) -> Option<i64> {
    match node.intent.get("quest_id") {
        Some(sentinel_models::platform::IntentValue::Int(v)) => Some(*v),
        Some(sentinel_models::platform::IntentValue::Float(v)) => Some(*v as i64),
        Some(sentinel_models::platform::IntentValue::Text(v)) => v.parse().ok(),
        _ => None,
    }
}

/// Campaign rules. Only MISSING_ACCEPT is implemented; the remaining archived rules (V2–V11) still
/// need the campaign-aware validator and are NOT silently reported as clean by something else here.
///
/// A turn-in with no accept is the one the spec names, and it is the one that actually strands a
/// run: the bot walks to the finisher for a quest it never took and stands there.
fn validate_campaign(campaign: &sentinel_models::platform::Campaign) -> Vec<CampaignDiagnostic> {
    let mut diagnostics = Vec::new();

    for graph in &campaign.graphs {
        let accepted: std::collections::HashSet<i64> = graph
            .nodes
            .iter()
            .filter(|n| n.node_type == "questing.AcceptQuest")
            .filter_map(quest_id_of)
            .collect();

        for node in &graph.nodes {
            if node.node_type != "questing.TurnInQuest" {
                continue;
            }
            let Some(quest_id) = quest_id_of(node) else {
                continue;
            };
            if accepted.contains(&quest_id) {
                continue;
            }
            diagnostics.push(CampaignDiagnostic {
                severity: "error".to_string(),
                code: "MISSING_ACCEPT".to_string(),
                message: format!(
                    "TurnInQuest({}) has no AcceptQuest({}) in graph '{}'",
                    quest_id, quest_id, graph.name
                ),
                node_id: Some(node.id),
            });
        }
    }

    diagnostics
}

async fn handle_validate_campaign(
    State(state): State<crate::server::AppState>,
    Path(name): Path<String>,
) -> Result<Json<Vec<CampaignDiagnostic>>, (StatusCode, Json<crate::server::ErrorResponse>)> {
    // Read through the session when there is one: a campaign mutated this session and not yet
    // re-read from disk must validate as it now IS, not as it was last saved.
    let store = state.campaign_store.read().await;
    if let Some(session) = store.get(&name) {
        return Ok(Json(validate_campaign(&session.campaign)));
    }
    drop(store);

    let campaign = CampaignApi::load(&state.campaigns_dir, &name)
        .map_err(editor_error_to_response)?;
    Ok(Json(validate_campaign(&campaign)))
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
        //
        // Update is reachable by POST as well as PUT. The Sylvannas SDK the in-game IDE runs on
        // exposes `core.http_get` and `core.http_post` and no other verb
        // (docs/SylvannasAPI/dev/api/core.md), so a PUT-only route is unreachable from the one
        // client this endpoint exists for. PUT stays for every other caller.
        .route("/editor/campaigns/{name}/nodes", post(handle_add_node))
        .route(
            "/editor/campaigns/{name}/nodes/{node_id}",
            put(handle_update_node)
                .post(handle_update_node)
                .delete(handle_remove_node),
        )
        // Delete is also exposed as POST because the Sylvannas SDK has no DELETE verb.
        .route(
            "/editor/campaigns/{name}/nodes/{node_id}/remove",
            post(handle_remove_node),
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_models::platform::{Campaign, Graph, Intent, IntentValue, Node};

    fn quest_node(node_type: &str, quest_id: i64) -> Node {
        let mut intent = Intent::new();
        intent.insert("quest_id", IntentValue::Int(quest_id));
        Node::new(node_type, intent)
    }

    fn campaign_with(nodes: Vec<Node>) -> Campaign {
        let mut campaign = Campaign::new("stw");
        let entry = nodes.first().map(|n| n.id).unwrap_or_else(Uuid::nil);
        let mut graph = Graph::new("main", entry);
        graph.nodes = nodes;
        campaign.graphs.push(graph);
        campaign
    }

    #[test]
    fn turn_in_without_accept_is_reported_and_names_its_node() {
        let turn_in = quest_node("questing.TurnInQuest", 9);
        let turn_in_id = turn_in.id;
        let campaign = campaign_with(vec![turn_in]);

        let diagnostics = validate_campaign(&campaign);
        assert_eq!(diagnostics.len(), 1, "the spec's scenario, exactly");
        assert_eq!(diagnostics[0].code, "MISSING_ACCEPT");
        assert_eq!(
            diagnostics[0].node_id,
            Some(turn_in_id),
            "the node id is what makes the diagnostic navigable; without it the Graph panel has \
             nothing to select when the operator clicks it"
        );
        assert!(
            diagnostics[0].message.contains("TurnInQuest(9)"),
            "and the message names the quest: {}",
            diagnostics[0].message
        );
    }

    #[test]
    fn a_matching_accept_clears_it() {
        let campaign = campaign_with(vec![
            quest_node("questing.AcceptQuest", 9),
            quest_node("questing.TurnInQuest", 9),
        ]);
        assert!(validate_campaign(&campaign).is_empty());
    }

    #[test]
    fn an_accept_for_a_different_quest_does_not_cover_the_turn_in() {
        let campaign = campaign_with(vec![
            quest_node("questing.AcceptQuest", 8),
            quest_node("questing.TurnInQuest", 9),
        ]);
        let diagnostics = validate_campaign(&campaign);
        assert_eq!(diagnostics.len(), 1, "quest 9 is still never accepted");
    }

    #[test]
    fn accepts_do_not_leak_across_graphs() {
        // Each graph is an independently runnable route. An accept in one is not an accept in
        // another, and treating it as one would hide the stranding this rule exists to catch.
        let mut campaign = campaign_with(vec![quest_node("questing.AcceptQuest", 9)]);
        let turn_in = quest_node("questing.TurnInQuest", 9);
        let mut second = Graph::new("side", turn_in.id);
        second.nodes = vec![turn_in];
        campaign.graphs.push(second);

        assert_eq!(validate_campaign(&campaign).len(), 1);
    }

    #[test]
    fn a_turn_in_with_no_quest_id_is_not_blamed_for_a_missing_accept() {
        // An unfilled template node is incomplete, not wrong, and reporting it as a broken chain
        // would bury the real diagnostics under every node an author has not finished yet.
        let campaign = campaign_with(vec![Node::new("questing.TurnInQuest", Intent::new())]);
        assert!(validate_campaign(&campaign).is_empty());
    }

    #[tokio::test]
    async fn post_remove_node_alias_deletes_node_and_persists() {
        // The Sylvannas SDK only exposes GET and POST, so the editor exposes a POST alias at
        // /editor/campaigns/{name}/nodes/{node_id}/remove. This test proves that alias actually
        // removes the node, updates the in-memory session, and writes the campaign back to disk.
        let tmp = tempfile::tempdir().unwrap();
        let state = crate::server::AppState::new(tmp.path().to_path_buf(), tmp.path().to_path_buf());

        let node = quest_node("questing.AcceptQuest", 42);
        let node_id = node.id;
        let campaign = campaign_with(vec![node]);
        let graph_id = campaign.graphs[0].id;

        // Seed both the filesystem and the in-memory store so the handler can load a session.
        crate::campaign_store::CampaignApi::save(&state.campaigns_dir, &campaign).unwrap();
        {
            let mut store = state.campaign_store.write().await;
            store.insert(
                "stw".to_string(),
                CampaignSession {
                    campaign,
                    history: CampaignHistory::new(),
                },
            );
        }

        let response = handle_remove_node(
            State(state.clone()),
            Path(("stw".to_string(), node_id.to_string())),
            Json(GraphIdParam { graph_id }),
        )
        .await;

        assert!(response.is_ok(), "remove should succeed");

        // In-memory session must reflect the removal immediately.
        {
            let store = state.campaign_store.read().await;
            let session = store.get("stw").unwrap();
            assert!(session.campaign.graphs[0].nodes.is_empty());
        }

        // And the on-disk copy must be updated (the Graph panel reloads from disk on refresh).
        let saved = crate::campaign_store::CampaignApi::load(&state.campaigns_dir, "stw").unwrap();
        assert!(saved.graphs[0].nodes.is_empty());
    }
}
