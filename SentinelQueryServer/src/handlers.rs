use axum::{
    extract::{Extension, Json, Path, Query},
    http::StatusCode,
    Json as AxumJson,
};
use serde_json::json;
use sentinel_query_types::*;
use std::collections::HashMap;

use crate::db::Db;

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