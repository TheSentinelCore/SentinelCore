use std::{env, net::SocketAddr, sync::Arc};

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Clone)]
struct AppState {
    database_path: Arc<String>,
}

#[derive(Debug, Error)]
enum AppError {
    #[error("database error: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("not found")]
    NotFound,
    #[error("invalid request: {0}")]
    Invalid(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = match self {
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::Invalid(_) => StatusCode::BAD_REQUEST,
            Self::Database(_) => StatusCode::INTERNAL_SERVER_ERROR,
        };
        (status, self.to_string()).into_response()
    }
}

#[derive(Debug, Serialize)]
struct Health {
    status: &'static str,
    database: String,
}

#[derive(Debug, Serialize)]
struct Quest {
    quest_id: i64,
    title: String,
    min_level: i64,
    max_level: i64,
    quest_level: i64,
    zone_or_sort: i64,
    suggested_players: i64,
    prev_quest_id: i64,
    next_quest_id: i64,
    next_quest_in_chain: i64,
    breadcrumb_for_quest_id: i64,
    required_classes: i64,
    required_races: i64,
    objectives: Vec<QuestObjective>,
    rewards: Vec<QuestReward>,
}

#[derive(Debug, Serialize)]
struct QuestObjective {
    slot: i64,
    item_id: i64,
    item_count: i64,
    creature_or_go_id: i64,
    creature_or_go_count: i64,
    spell_id: i64,
    text: Option<String>,
}

#[derive(Debug, Serialize)]
struct QuestReward {
    slot: i64,
    item_id: i64,
    item_count: i64,
    choice: bool,
}

#[derive(Debug, Serialize)]
struct QuestNpc {
    npc_id: i64,
    name: String,
    map_id: i64,
    x: f64,
    y: f64,
    z: f64,
    quest_ids: Vec<i64>,
}

#[derive(Debug, Deserialize)]
struct NpcQuery {
    relation: Option<String>,
    map_id: Option<i64>,
}

#[allow(dead_code)]
fn open_database(state: &AppState) -> Result<Connection, AppError> {
    Ok(Connection::open(state.database_path.as_str())?)
}

async fn health(State(state): State<Arc<AppState>>) -> Result<Json<Health>, AppError> {
    let path = state.database_path.clone();
    tokio::task::spawn_blocking(move || {
        let connection = Connection::open(path.as_str())?;
        connection.query_row("SELECT 1", [], |_| Ok(()))?;
        Ok::<_, AppError>(Json(Health { status: "ok", database: path.to_string() }))
    })
    .await
    .map_err(|error| AppError::Invalid(error.to_string()))?
}

async fn quest(
    State(state): State<Arc<AppState>>,
    Path(quest_id): Path<i64>,
) -> Result<Json<Quest>, AppError> {
    let path = state.database_path.clone();
    tokio::task::spawn_blocking(move || query_quest(path.as_str(), quest_id))
        .await
        .map_err(|error| AppError::Invalid(error.to_string()))?
}

fn query_quest(path: &str, quest_id: i64) -> Result<Json<Quest>, AppError> {
    let connection = Connection::open(path)?;
    let row = connection
        .query_row(
            "SELECT entry, COALESCE(Title, ''), MinLevel, MaxLevel, QuestLevel,
                    ZoneOrSort, SuggestedPlayers, PrevQuestId, NextQuestId,
                    NextQuestInChain, BreadcrumbForQuestId, RequiredClasses,
                    RequiredRaces,
                    ObjectiveText1, ObjectiveText2, ObjectiveText3, ObjectiveText4,
                    ReqItemId1, ReqItemId2, ReqItemId3, ReqItemId4,
                    ReqItemCount1, ReqItemCount2, ReqItemCount3, ReqItemCount4,
                    ReqCreatureOrGOId1, ReqCreatureOrGOId2, ReqCreatureOrGOId3, ReqCreatureOrGOId4,
                    ReqCreatureOrGOCount1, ReqCreatureOrGOCount2, ReqCreatureOrGOCount3, ReqCreatureOrGOCount4,
                    ReqSpellCast1, ReqSpellCast2, ReqSpellCast3, ReqSpellCast4,
                    RewItemId1, RewItemId2, RewItemId3, RewItemId4,
                    RewItemCount1, RewItemCount2, RewItemCount3, RewItemCount4,
                    RewChoiceItemId1, RewChoiceItemId2, RewChoiceItemId3, RewChoiceItemId4,
                    RewChoiceItemId5, RewChoiceItemId6,
                    RewChoiceItemCount1, RewChoiceItemCount2, RewChoiceItemCount3,
                    RewChoiceItemCount4, RewChoiceItemCount5, RewChoiceItemCount6
             FROM quest_template WHERE entry = ?1",
            params![quest_id],
            |row| {
                let objective_texts = [
                    row.get::<_, Option<String>>(13)?,
                    row.get::<_, Option<String>>(14)?,
                    row.get::<_, Option<String>>(15)?,
                    row.get::<_, Option<String>>(16)?,
                ];
                let item_ids = [row.get::<_, i64>(17)?, row.get(18)?, row.get(19)?, row.get(20)?];
                let item_counts = [row.get::<_, i64>(21)?, row.get(22)?, row.get(23)?, row.get(24)?];
                let creature_ids = [row.get::<_, i64>(25)?, row.get(26)?, row.get(27)?, row.get(28)?];
                let creature_counts = [row.get::<_, i64>(29)?, row.get(30)?, row.get(31)?, row.get(32)?];
                let spell_ids = [row.get::<_, i64>(33)?, row.get(34)?, row.get(35)?, row.get(36)?];
                let mut objectives = Vec::new();
                for slot in 0..4 {
                    if item_ids[slot] != 0 || creature_ids[slot] != 0 || spell_ids[slot] != 0 {
                        objectives.push(QuestObjective {
                            slot: (slot + 1) as i64,
                            item_id: item_ids[slot],
                            item_count: item_counts[slot],
                            creature_or_go_id: creature_ids[slot],
                            creature_or_go_count: creature_counts[slot],
                            spell_id: spell_ids[slot],
                            text: objective_texts[slot].clone(),
                        });
                    }
                }
                let reward_ids = [row.get::<_, i64>(37)?, row.get(38)?, row.get(39)?, row.get(40)?];
                let reward_counts = [row.get::<_, i64>(41)?, row.get(42)?, row.get(43)?, row.get(44)?];
                let choice_ids = [row.get::<_, i64>(45)?, row.get(46)?, row.get(47)?, row.get(48)?, row.get(49)?, row.get(50)?];
                let choice_counts = [row.get::<_, i64>(51)?, row.get(52)?, row.get(53)?, row.get(54)?, row.get(55)?, row.get(56)?];
                let mut rewards = Vec::new();
                for slot in 0..4 {
                    if reward_ids[slot] != 0 {
                        rewards.push(QuestReward { slot: (slot + 1) as i64, item_id: reward_ids[slot], item_count: reward_counts[slot], choice: false });
                    }
                }
                for slot in 0..6 {
                    if choice_ids[slot] != 0 {
                        rewards.push(QuestReward { slot: (slot + 1) as i64, item_id: choice_ids[slot], item_count: choice_counts[slot], choice: true });
                    }
                }
                Ok(Quest {
                    quest_id: row.get(0)?, title: row.get(1)?, min_level: row.get(2)?, max_level: row.get(3)?,
                    quest_level: row.get(4)?, zone_or_sort: row.get(5)?, suggested_players: row.get(6)?,
                    prev_quest_id: row.get(7)?, next_quest_id: row.get(8)?, next_quest_in_chain: row.get(9)?,
                    breadcrumb_for_quest_id: row.get(10)?, required_classes: row.get(11)?, required_races: row.get(12)?,
                    objectives, rewards,
                })
            },
        )
        .optional()?;
    row.map(Json).ok_or(AppError::NotFound)
}

async fn quest_npcs(
    State(state): State<Arc<AppState>>,
    Path(quest_id): Path<i64>,
    Query(query): Query<NpcQuery>,
) -> Result<Json<Vec<QuestNpc>>, AppError> {
    let path = state.database_path.clone();
    tokio::task::spawn_blocking(move || query_quest_npcs(path.as_str(), quest_id, query))
        .await
        .map_err(|error| AppError::Invalid(error.to_string()))?
}

fn query_quest_npcs(path: &str, quest_id: i64, query: NpcQuery) -> Result<Json<Vec<QuestNpc>>, AppError> {
    let connection = Connection::open(path)?;
    let relation = query.relation.as_deref().unwrap_or("giver");
    let table = match relation {
        "giver" => "creature_questrelation",
        "turnin" => "creature_involvedrelation",
        _ => return Err(AppError::Invalid("relation must be giver or turnin".into())),
    };
    let sql = format!(
        "SELECT c.id, COALESCE(t.Name, ''), c.map, c.position_x, c.position_y, c.position_z
         FROM {table} r JOIN creature_template t ON t.Entry = r.id
         LEFT JOIN creature c ON c.id = r.id
         WHERE r.quest = ?1 AND (?2 IS NULL OR c.map = ?2)"
    );
    let mut statement = connection.prepare(&sql)?;
    let mut rows = statement.query(params![quest_id, query.map_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(QuestNpc {
            npc_id: row.get(0)?, name: row.get(1)?, map_id: row.get(2)?,
            x: row.get(3)?, y: row.get(4)?, z: row.get(5)?, quest_ids: vec![quest_id],
        });
    }
    Ok(Json(result))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt().with_env_filter("info").init();
    let database_path = env::var("SENTINEL_QUERY_DB").unwrap_or_else(|_| "../Database/tbcmangos.sqlite".into());
    let host = env::var("SENTINEL_QUERY_HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let port = env::var("SENTINEL_QUERY_PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(8081);
    let state = Arc::new(AppState { database_path: Arc::new(database_path) });
    let app = Router::new()
        .route("/health", get(health))
        .route("/api/v1/quests/:quest_id", get(quest))
        .route("/api/v1/quests/:quest_id/npcs", get(quest_npcs))
        .with_state(state);
    let address: SocketAddr = format!("{host}:{port}").parse()?;
    tracing::info!(%address, "Sentinel Query Server listening");
    let listener = tokio::net::TcpListener::bind(address).await?;
    axum::serve(listener, app).with_graceful_shutdown(async { let _ = tokio::signal::ctrl_c().await; }).await?;
    Ok(())
}
