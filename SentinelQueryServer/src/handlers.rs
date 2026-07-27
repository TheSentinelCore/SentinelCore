use axum::{
    body::Bytes,
    extract::{Extension, Json, Path, Query},
    http::StatusCode,
    Json as AxumJson,
};
use sentinel_models::platform::Campaign;
use sentinel_query_types::*;
use serde_json::json;
use std::collections::HashMap;

use crate::db::Db;
use crate::resolve::{ResolveResponse, SqliteResolverDb};
use crate::search::{parse_limit, SearchHit, SpawnPoint, SpawnType};

pub async fn search_quests(
    Extension(db): Extension<Db>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<AxumJson<Vec<QuestSummary>>, (StatusCode, Json<serde_json::Value>)> {
    let query = params.get("q").cloned().unwrap_or_default();
    match db.search_quests(&query) {
        Ok(quests) => Ok(AxumJson(quests)),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn get_quest(
    Extension(db): Extension<Db>,
    Path(id): Path<u32>,
) -> Result<AxumJson<QuestDetail>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_quest(id) {
        Ok(Some(quest)) => Ok(AxumJson(quest)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Quest not found: {}", id) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn search_npcs(
    Extension(db): Extension<Db>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<AxumJson<Vec<NpcSummary>>, (StatusCode, Json<serde_json::Value>)> {
    let query = params.get("q").cloned().unwrap_or_default();
    match db.search_npcs(&query) {
        Ok(npcs) => Ok(AxumJson(npcs)),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn get_npc(
    Extension(db): Extension<Db>,
    Path(entry): Path<u32>,
) -> Result<AxumJson<NpcDetail>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_npc(entry) {
        Ok(Some(npc)) => Ok(AxumJson(npc)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("NPC not found: {}", entry) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn get_vendor(
    Extension(db): Extension<Db>,
    Path(entry): Path<u32>,
) -> Result<AxumJson<VendorInfo>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_vendor(entry) {
        Ok(Some(vendor)) => Ok(AxumJson(vendor)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Vendor not found: {}", entry) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn get_trainer(
    Extension(db): Extension<Db>,
    Path(entry): Path<u32>,
) -> Result<AxumJson<TrainerInfo>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_trainer(entry) {
        Ok(Some(trainer)) => Ok(AxumJson(trainer)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Trainer not found: {}", entry) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn get_flight(
    Extension(db): Extension<Db>,
    Path(entry): Path<u32>,
) -> Result<AxumJson<FlightInfo>, (StatusCode, Json<serde_json::Value>)> {
    let db = db.0.lock().unwrap();
    let name_opt: Result<Option<String>, (StatusCode, Json<serde_json::Value>)> = db
        .prepare("SELECT Name FROM creature_template WHERE Entry = ?1 AND (NpcFlags & 8192) != 0")
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "error": e.to_string() })),
            )
        })
        .and_then(|mut stmt| {
            stmt.query_row([entry], |row| row.get::<_, Option<String>>(0))
                .map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(json!({ "error": e.to_string() })),
                    )
                })
        });

    let name = match name_opt {
        Ok(Some(name)) => name,
        Ok(None) => {
            return Err((
                StatusCode::NOT_FOUND,
                Json(json!({ "error": format!("Flight master not found: {}", entry) })),
            ))
        }
        Err(e) => return Err(e),
    };

    Ok(AxumJson(FlightInfo {
        entry,
        name,
        destinations: Vec::new(), // No taxi tables in this DB snapshot
    }))
}

pub async fn get_item_sources(
    Extension(db): Extension<Db>,
    Path(item): Path<u32>,
) -> Result<AxumJson<Vec<u32>>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_item_sources(item) {
        Ok(sources) => Ok(AxumJson(sources)),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": e })))),
    }
}

pub async fn get_item(
    Extension(db): Extension<Db>,
    Path(entry): Path<u32>,
) -> Result<AxumJson<ItemInfo>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_item(entry) {
        Ok(Some(item)) => Ok(AxumJson(item)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Item not found: {}", entry) })),
        )),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": e })))),
    }
}

pub async fn get_object(
    Extension(db): Extension<Db>,
    Path(entry): Path<u32>,
) -> Result<AxumJson<ObjectInfo>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_object(entry) {
        Ok(Some(obj)) => Ok(AxumJson(obj)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Object not found: {}", entry) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn creatures_polygon(
    Extension(db): Extension<Db>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<AxumJson<CreaturePolygon>, (StatusCode, Json<serde_json::Value>)> {
    let entry_str = params.get("entry").ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Missing 'entry' parameter" })),
        )
    })?;
    let entry: u32 = entry_str
        .parse()
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({ "error": "Invalid 'entry' parameter" })),
            )
        })?;
    
    match db.creatures_polygon(entry) {
        Ok(Some(polygon)) => Ok(AxumJson(polygon)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Creature not found: {}", entry) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn validate(
    Extension(db): Extension<Db>,
    AxumJson(req): AxumJson<ValidateRequest>,
) -> Result<AxumJson<ValidateResponse>, (StatusCode, Json<serde_json::Value>)> {
    match db.validate(req) {
        Ok(response) => Ok(AxumJson(response)),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

pub async fn travel_estimate(
    Extension(db): Extension<Db>,
    AxumJson(req): AxumJson<TravelEstimateRequest>,
) -> Result<AxumJson<TravelEstimateResponse>, (StatusCode, Json<serde_json::Value>)> {
    match db.travel_estimate(req) {
        Ok(response) => Ok(AxumJson(response)),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

/// `GET /quest/{id}/chain` — quest chain information: prerequisites, follow-ups, branches.
pub async fn get_quest_chain(
    Extension(db): Extension<Db>,
    Path(id): Path<u32>,
) -> Result<AxumJson<QuestChain>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_quest_chain(id) {
        Ok(Some(chain)) => Ok(AxumJson(chain)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Quest not found: {}", id) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

/// `GET /quest/{id}/objectives` — parsed objectives with creature/item cross-references.
pub async fn get_quest_objectives(
    Extension(db): Extension<Db>,
    Path(id): Path<u32>,
) -> Result<AxumJson<QuestObjectivesResponse>, (StatusCode, Json<serde_json::Value>)> {
    match db.get_quest_objectives(id) {
        Ok(Some(objectives)) => Ok(AxumJson(objectives)),
        Ok(None) => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("Quest not found: {}", id) })),
        )),
        Err(e) => {
            let err = json!({ "error": e });
            Err((StatusCode::INTERNAL_SERVER_ERROR, Json(err)))
        }
    }
}

/// `GET /search?q=<text>&limit=<n>` — one federated, ranked, typed result list across
/// npc / quest / item / object / area. The IDE's Smart Search calls this once per keystroke,
/// so an empty or missing term is refused rather than answered with a full table sweep.
pub async fn search(
    Extension(db): Extension<Db>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<AxumJson<Vec<SearchHit>>, (StatusCode, Json<serde_json::Value>)> {
    let term = params.get("q").map(|s| s.trim()).unwrap_or_default();
    if term.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "Missing 'q' parameter" })),
        ));
    }

    let limit = parse_limit(params.get("limit").map(String::as_str))
        .map_err(|e| (StatusCode::BAD_REQUEST, Json(json!({ "error": e }))))?;

    match db.federated_search(term, limit) {
        Ok(hits) => Ok(AxumJson(hits)),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": e })))),
    }
}

/// `GET /spawns/:type/:entry` — every spawn point of an entry, `:type` being `npc` or `object`.
///
/// This is where `world_z` comes from. Guide text never carried ground height, which left every
/// imported Travel position at `world_z = 0` — underground, and unusable for navmesh queries.
pub async fn get_spawns(
    Extension(db): Extension<Db>,
    Path((kind, entry)): Path<(String, u32)>,
) -> Result<AxumJson<Vec<SpawnPoint>>, (StatusCode, Json<serde_json::Value>)> {
    let kind: SpawnType = kind
        .parse()
        .map_err(|e: String| (StatusCode::BAD_REQUEST, Json(json!({ "error": e }))))?;

    match db.spawns(kind, entry) {
        Ok(spawns) if spawns.is_empty() => Err((
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("No spawns found for {}: {}", kind_label(kind), entry) })),
        )),
        Ok(spawns) => Ok(AxumJson(spawns)),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": e })))),
    }
}

/// `POST /resolve` — a Campaign (ADR 09a §1.3) in, `{ plan, diagnostics }` out.
///
/// A transport over `sentinel-resolver`, with no lowering rule of its own (ADR 09 §5). Two things
/// this handler must not do: add anything clock- or iteration-derived to the response, which would
/// break the crate's guarantee that the same intent plus the same `db_fingerprint` yields
/// byte-identical output; and treat diagnostics as failure — a campaign with unresolvable
/// references *resolved*, and reported problems, which is a 200.
///
/// The body is read as [`Bytes`] rather than through the `Json` extractor because that extractor's
/// rejection is a plain-text body: malformed input would be the one response from this server not
/// shaped like `{"error": …}`.
pub async fn resolve(
    Extension(db): Extension<Db>,
    body: Bytes,
) -> Result<AxumJson<ResolveResponse>, (StatusCode, Json<serde_json::Value>)> {
    let campaign: Campaign = serde_json::from_slice(&body).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": e.to_string() })),
        )
    })?;

    let resolver_db = SqliteResolverDb::new(db)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": e }))))?;

    // A lookup the database could not perform is this server's fault, not the campaign's, so it is
    // a 500 rather than a 200 carrying a diagnostic. The resolver returns no plan at all in that
    // case: a plan lowered against a half-readable snapshot is structurally complete and would be
    // indistinguishable from a good one downstream.
    let (plan, diagnostics) = sentinel_resolver::resolve(&campaign, &resolver_db).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "error": e.to_string() })),
        )
    })?;
    Ok(AxumJson(ResolveResponse { plan, diagnostics }))
}

fn kind_label(kind: SpawnType) -> &'static str {
    match kind {
        SpawnType::Npc => "npc",
        SpawnType::Object => "object",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_db::open;
    use crate::search::MAX_SEARCH_LIMIT;
    use sentinel_models::runtime::RuntimeAction;

    /// A three-node linear route over entries that really exist in this snapshot: Deputy Willem
    /// (npc 823) offers quest 783 "A Threat Within", Marshal McBride (npc 197) takes it back. The
    /// `TurnIn` deliberately omits `to` so the resolver has to ask the database who ends the quest.
    const LINEAR_CAMPAIGN: &str = r#"{
      "schema_version": 3,
      "id": "018f0000-0000-7000-8000-000000000001",
      "name": "Elwynn opener",
      "graphs": [{
        "id": "018f0000-0000-7000-8000-000000000002",
        "name": "Northshire",
        "entry_node": "018f0000-0000-7000-8000-000000000010",
        "nodes": [
          { "id": "018f0000-0000-7000-8000-000000000010",
            "type": "questing.AcceptQuest",
            "intent": { "quest": { "ref": "quest:783", "label": "A Threat Within" },
                        "from":  { "ref": "npc:823",   "label": "Deputy Willem" } } },
          { "id": "018f0000-0000-7000-8000-000000000011",
            "type": "questing.Travel",
            "intent": { "to": { "ref": "npc:823", "label": "Deputy Willem" } } },
          { "id": "018f0000-0000-7000-8000-000000000012",
            "type": "questing.TurnIn",
            "intent": { "quest": { "ref": "quest:783", "label": "A Threat Within" } } }
        ],
        "edges": [
          { "id": "018f0000-0000-7000-8000-000000000020",
            "from": "018f0000-0000-7000-8000-000000000010",
            "to":   "018f0000-0000-7000-8000-000000000011" },
          { "id": "018f0000-0000-7000-8000-000000000021",
            "from": "018f0000-0000-7000-8000-000000000011",
            "to":   "018f0000-0000-7000-8000-000000000012" }
        ]
      }]
    }"#;

    /// One `Travel` at an entry no snapshot has ever carried.
    const UNRESOLVABLE_CAMPAIGN: &str = r#"{
      "id": "018f0000-0000-7000-8000-000000000001",
      "name": "Dangling",
      "graphs": [{
        "id": "018f0000-0000-7000-8000-000000000002",
        "name": "Nowhere",
        "entry_node": "018f0000-0000-7000-8000-000000000030",
        "nodes": [
          { "id": "018f0000-0000-7000-8000-000000000030",
            "type": "questing.Travel",
            "intent": { "to": { "ref": "npc:99999999", "label": "Ghost" } } }
        ],
        "edges": []
      }]
    }"#;

    async fn resolved(campaign: &str) -> ResolveResponse {
        resolve(Extension(open()), Bytes::from(campaign.to_string()))
            .await
            .expect("a resolvable campaign is a 200")
            .0
    }

    #[tokio::test]
    async fn resolve_lowers_one_operation_per_node_in_route_order() {
        let response = resolved(LINEAR_CAMPAIGN).await;
        let plan = &response.plan;
        assert_eq!(plan.operations.len(), 3, "one operation per node");
        assert_eq!(
            plan.operations[0].node_id.to_string(),
            "018f0000-0000-7000-8000-000000000010"
        );
        // Travel to the giver, then accept: the resolver, not the author, supplied the walk.
        assert_eq!(plan.operations[0].actions.len(), 2);
        assert_eq!(plan.operations[0].next[0].to_index, 1);
        assert_eq!(plan.operations[1].next[0].to_index, 2);
        assert!(plan.operations[2].next.is_empty(), "the route ends here");
        assert!(
            response.diagnostics.is_empty(),
            "nothing in this route is unresolvable: {:?}",
            response.diagnostics
        );
    }

    #[tokio::test]
    async fn the_turn_in_npc_comes_from_the_database_when_the_author_omitted_it() {
        let response = resolved(LINEAR_CAMPAIGN).await;
        let RuntimeAction::TurnInQuest(turn_in) = &response.plan.operations[2].actions[1].action
        else {
            panic!("the turn-in node lowers to Travel + TurnInQuest");
        };
        assert_eq!(turn_in.npc_entry, 197, "Marshal McBride ends quest 783");
    }

    #[tokio::test]
    async fn resolving_the_same_campaign_twice_produces_byte_identical_plans() {
        // The crate's purity guarantee has to survive the transport: a timestamp, a request id, or
        // a HashMap iteration anywhere in this handler would make bulk re-resolution a rewrite
        // instead of a diff.
        let first = serde_json::to_string(&resolved(LINEAR_CAMPAIGN).await.plan).unwrap();
        let second = serde_json::to_string(&resolved(LINEAR_CAMPAIGN).await.plan).unwrap();
        assert_eq!(first, second);
    }

    #[tokio::test]
    async fn a_travel_carries_the_real_ground_height() {
        let response = resolved(LINEAR_CAMPAIGN).await;
        let RuntimeAction::Travel(travel) = &response.plan.operations[1].actions[0].action else {
            panic!("the travel node lowers to Travel");
        };
        assert_eq!(travel.position.map, 0);
        // Deputy Willem stands at z = 83.4466 in `creature`. `world_z = 0` is the bug this whole
        // phase exists to fix, so pin the actual height rather than merely "not zero".
        assert!(
            (travel.position.world_z - 83.4466).abs() < 0.01,
            "world_z was {}",
            travel.position.world_z
        );
    }

    #[tokio::test]
    async fn an_unresolvable_reference_is_a_diagnostic_not_a_failure() {
        // Resolution succeeded and reported a problem; that is a 200. Reserving non-2xx for
        // malformed input is what lets the IDE show squiggles instead of an error toast.
        let response = resolved(UNRESOLVABLE_CAMPAIGN).await;
        let diagnostic = response
            .diagnostics
            .iter()
            .find(|d| d.code == "resolver.spawn.unknown")
            .expect("an entry with no spawn must be reported");
        assert_eq!(
            diagnostic.node_id.map(|id| id.to_string()).as_deref(),
            Some("018f0000-0000-7000-8000-000000000030"),
            "a diagnostic the IDE cannot attribute to a node is unactionable"
        );
        assert_eq!(response.plan.operations.len(), 1, "the node is still there");
    }

    #[tokio::test]
    async fn malformed_json_is_a_client_error_in_the_usual_error_shape() {
        let err = resolve(Extension(open()), Bytes::from_static(b"{\"id\": "))
            .await
            .expect_err("truncated JSON is a client error, not a panic");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
        assert!(err.1 .0.get("error").is_some(), "{:?}", err.1 .0);
    }

    #[tokio::test]
    async fn an_unknown_entity_kind_is_refused_rather_than_defaulted() {
        let body = LINEAR_CAMPAIGN.replace("npc:823", "mount:823");
        let err = resolve(Extension(open()), Bytes::from(body))
            .await
            .expect_err("an unparseable ref must not deserialize into a default");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn the_plan_names_the_database_it_was_resolved_against() {
        let response = resolved(LINEAR_CAMPAIGN).await;
        assert!(
            response.plan.db_fingerprint.starts_with("tbcmangos@"),
            "fingerprint was {}",
            response.plan.db_fingerprint
        );
    }

    fn params(pairs: &[(&str, &str)]) -> Query<HashMap<String, String>> {
        Query(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        )
    }

    #[tokio::test]
    async fn search_rejects_a_missing_term() {
        let err = search(Extension(open()), params(&[]))
            .await
            .expect_err("no term must not sweep every table");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
        assert!(err.1 .0.get("error").is_some());
    }

    #[tokio::test]
    async fn search_rejects_a_blank_term() {
        let err = search(Extension(open()), params(&[("q", "   ")]))
            .await
            .expect_err("blank term must not sweep every table");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn search_rejects_an_unparseable_limit() {
        let err = search(Extension(open()), params(&[("q", "Fang"), ("limit", "abc")]))
            .await
            .expect_err("a bad limit is a client error");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
        assert!(err.1 .0.get("error").is_some());
    }

    #[tokio::test]
    async fn search_caps_an_oversized_limit() {
        let hits = search(
            Extension(open()),
            params(&[("q", "a"), ("limit", "100000")]),
        )
        .await
        .expect("oversized limits clamp rather than fail");
        assert!(hits.0.len() <= MAX_SEARCH_LIMIT, "returned {}", hits.0.len());
    }

    #[tokio::test]
    async fn spawns_returns_ground_height_for_deputy_willem() {
        let spawns = get_spawns(Extension(open()), Path(("npc".to_string(), 823)))
            .await
            .expect("Deputy Willem is spawned");
        let first = &spawns.0[0];
        assert_eq!(first.map, 0);
        assert_ne!(first.position_z, 0.0);
    }

    #[tokio::test]
    async fn spawns_rejects_an_unknown_type() {
        let err = get_spawns(Extension(open()), Path(("dragon".to_string(), 823)))
            .await
            .expect_err("only npc and object are spawn tables");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
        assert!(err.1 .0.get("error").is_some());
    }

    #[tokio::test]
    async fn spawns_of_an_unknown_entry_are_a_not_found() {
        let err = get_spawns(Extension(open()), Path(("npc".to_string(), 99_999_999)))
            .await
            .expect_err("an unspawned entry is a 404, not a panic");
        assert_eq!(err.0, StatusCode::NOT_FOUND);
        assert!(err.1 .0.get("error").is_some());
    }
}