use axum::{
    extract::{Extension, Json, Path, Query},
    http::StatusCode,
    Json as AxumJson,
};
use serde_json::json;
use sentinel_query_types::*;
use std::collections::HashMap;

use crate::db::Db;
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