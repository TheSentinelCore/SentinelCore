use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatasetManifest {
    pub dataset_version: String,
    pub source: String,
    pub game_version: String,
    pub db_version_string: String,
    pub importer_schema_version: u32,
    pub built_at_utc: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub uptime_secs: u64,
    pub dataset_version: String,
    pub game_version: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ContextResolveRequest {
    pub map_id: Option<i64>,
    pub ui_map_id: Option<i64>,
    pub x: Option<f64>,
    pub y: Option<f64>,
    pub z: Option<f64>,
    pub instance_id: Option<i64>,
    pub instance_type: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ContextResolveResponse {
    pub canonical_map_id: Option<i64>,
    pub map_id: Option<i64>,
    pub zone_id: Option<i64>,
    pub area_id: Option<i64>,
    pub resolved: bool,
    pub ambiguous: bool,
    pub diagnostic_confidence: f64,
    pub resolution: String,
    pub source: String,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PagedResponse<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
    pub count: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct VendorEntity {
    pub guid: i64,
    pub entry: i64,
    pub name: String,
    pub map_id: i64,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub distance: Option<f64>,
    pub npc_flags: i64,
    pub can_sell: bool,
    pub can_repair: bool,
    pub vendor_item_count: i64,
    pub faction_id: i64,
    pub faction_team: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TrainerEntity {
    pub guid: i64,
    pub entry: i64,
    pub name: String,
    pub map_id: i64,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub distance: Option<f64>,
    pub trainer_type: String,
    pub trainer_class: i64,
    pub trainer_race: i64,
    pub trainer_spell_count: i64,
    pub faction_id: i64,
    pub faction_team: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TrainerDetail {
    pub entry: i64,
    pub name: String,
    pub npc_flags: i64,
    pub trainer_type: String,
    pub trainer_class: i64,
    pub trainer_race: i64,
    pub trainer_spell_count: i64,
    pub faction_id: i64,
    pub faction_team: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TrainerSpell {
    pub spell: i64,
    pub spell_cost: i64,
    pub req_skill: i64,
    pub req_skill_value: i64,
    pub req_level: i64,
    pub req_ability_1: Option<i64>,
    pub req_ability_2: Option<i64>,
    pub req_ability_3: Option<i64>,
    pub source: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct UtilityEntity {
    pub guid: i64,
    pub entry: i64,
    pub name: String,
    pub map_id: i64,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub distance: Option<f64>,
    pub faction_id: i64,
    pub faction_team: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct UnifiedEntity {
    pub entity_type: String,
    pub guid: i64,
    pub entry: i64,
    pub name: String,
    pub map_id: i64,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub distance: f64,
    pub faction_id: i64,
    pub faction_team: Option<String>,
    pub can_sell: Option<bool>,
    pub can_repair: Option<bool>,
    pub trainer_type: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ItemInfo {
    pub entry: i64,
    pub name: String,
    pub quality: i64,
    pub sell_price: i64,
    pub item_class: i64,
    pub item_subclass: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct ItemListResponse {
    pub items: Vec<ItemInfo>,
    pub count: usize,
}
