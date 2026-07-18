//! Response models — Volume 4 §"API Design Principles"
//! 
//! Semantic objects returned by the API, not SQL rows.
//! The editor consumes semantic objects. Not SQL rows.

use serde::{Deserialize, Serialize};
use sentinel_schema::{Waypoint, NpcRole, Class};

/// Quest search result — Volume 4 §7
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestSearchResult {
    pub id: u32,
    pub title: String,
    pub level: u32,
    pub min_level: u32,
    pub zone: String,
    pub giver: u32,
}

/// Quest details — Volume 4 §8
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestDetails {
    pub id: u32,
    pub title: String,
    pub level: u32,
    pub min_level: u32,
    pub max_level: u32,
    pub zone: String,
    pub giver: u32,
    pub turn_in: u32,
    pub objectives: Vec<QuestObjective>,
    pub rewards: Vec<QuestReward>,
    pub chain: QuestChain,
    pub prerequisites: Vec<u32>,
    pub followups: Vec<u32>,
    pub exclusive_quests: Vec<u32>,
    pub required_items: Vec<u32>,
    pub required_kills: Vec<QuestKillRequirement>,
}

/// Quest objective — Volume 4 §8
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestObjective {
    pub slot: u32,
    pub item_id: u32,
    pub item_count: u32,
    pub creature_or_go_id: u32,
    pub creature_or_go_count: u32,
    pub spell_id: u32,
    pub text: Option<String>,
}

/// Quest reward — Volume 4 §8
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestReward {
    pub slot: u32,
    pub item_id: u32,
    pub item_count: u32,
    pub choice: bool,
}

/// Quest chain — Volume 4 §9
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestChain {
    pub accept: Vec<u32>,
    pub quests: Vec<u32>,
    pub followups: Vec<u32>,
    pub branches: Vec<QuestChainBranch>,
    pub end: Vec<u32>,
}

/// Quest chain branch — Volume 4 §9
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestChainBranch {
    pub quest_id: u32,
    pub branches: Vec<u32>,
}

/// Quest kill requirement
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestKillRequirement {
    pub creature_id: u32,
    pub count: u32,
}

/// NPC details — Volume 4 §8
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NpcDetails {
    pub entry: u32,
    pub name: String,
    pub roles: Vec<NpcRole>,
    pub zone: String,
    pub position: Waypoint,
    pub faction: String,
    pub quest_ids: Vec<u32>,
}

/// NPC search result — Volume 4 §8
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NpcSearchResult {
    pub entry: u32,
    pub name: String,
    pub roles: Vec<NpcRole>,
    pub zone: String,
}

/// Creature details — Volume 4 §9
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreatureDetails {
    pub entry: u32,
    pub name: String,
    pub family: String,
    pub faction: String,
    pub level_min: u32,
    pub level_max: u32,
    pub elite: bool,
    pub spawns: Vec<CreatureSpawn>,
}

/// Creature spawn location — Volume 4 §9
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreatureSpawn {
    pub map: u32,
    pub zone: String,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub respawn_time_sec: u32,
    pub density: f32,
}

/// Vendor details — Volume 4 §10
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VendorDetails {
    pub entry: u32,
    pub name: String,
    pub items: Vec<VendorItem>,
    pub repairs: bool,
    pub ammo: bool,
    pub food: bool,
    pub drink: bool,
}

/// Vendor item — Volume 4 §10
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VendorItem {
    pub item_id: u32,
    pub name: String,
    pub price: u32,
    pub limited_supply: bool,
    pub max_count: u32,
    pub incr_time: u32,
}

/// Trainer details — Volume 4 §11
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrainerDetails {
    pub entry: u32,
    pub name: String,
    pub class: Class,
    pub spells: Vec<TrainerSpell>,
}

/// Trainer spell — Volume 4 §11
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrainerSpell {
    pub spell_id: u32,
    pub name: String,
    pub level_required: u32,
    pub cost: u32,
}

/// Flight master — Volume 4 §12
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlightMaster {
    pub node: u32,
    pub name: String,
    pub faction: String,
    pub connected_routes: Vec<FlightRoute>,
}

/// Flight route — Volume 4 §12
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlightRoute {
    pub from: u32,
    pub to: u32,
    pub cost: u32,
}

/// Mailbox — Volume 4 §13
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mailbox {
    pub entry: u32,
    pub name: String,
    pub position: Waypoint,
}

/// Innkeeper — Volume 4 §14
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Innkeeper {
    pub entry: u32,
    pub name: String,
    pub rest_area: String,
    pub hearth: bool,
    pub position: Waypoint,
}

/// Area query result — Volume 4 §15
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AreaQueryResult {
    pub npcs: Vec<NpcSearchResult>,
    pub objects: Vec<GameObjectReference>,
    pub creatures: Vec<CreatureDetails>,
    pub spawn_density: f32,
    pub loot_sources: Vec<LootSource>,
    pub quest_objectives: Vec<QuestObjectiveReference>,
}

/// Game object reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameObjectReference {
    pub entry: u32,
    pub name: String,
    pub position: Waypoint,
}

/// Loot source — Volume 4 §23
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LootSource {
    pub creature_id: u32,
    pub creature_name: String,
    pub drop_chance: f32,
    pub avg_count: f32,
    pub spawn_area: String,
}

/// Quest objective reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestObjectiveReference {
    pub quest_id: u32,
    pub quest_title: String,
    pub objective_type: String,
    pub target_id: u32,
}

/// Polygon analysis — Volume 4 §16
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolygonAnalysis {
    pub avg_mob_density: f32,
    pub respawn_rate: f32,
    pub unique_creatures: u32,
    pub quest_overlap: u32,
    pub elite_mobs: u32,
    pub aggro_risk: f32,
    pub avg_travel_distance: f32,
}

/// Route analysis — Volume 4 §17
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteAnalysis {
    pub distance: f32,
    pub travel_time_sec: f32,
    pub elevation_change: f32,
    pub zone_crossings: u32,
    pub suggested_split: Option<Vec<Waypoint>>,
}

/// Quest hub analysis — Volume 4 §18
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestHubAnalysis {
    pub available_quests: Vec<QuestSearchResult>,
    pub nearby_vendor: Option<NpcSearchResult>,
    pub nearby_trainer: Option<NpcSearchResult>,
    pub nearby_mailbox: Option<Mailbox>,
    pub nearby_flight: Option<FlightMaster>,
    pub nearby_repair: Option<NpcSearchResult>,
    pub nearby_inn: Option<Innkeeper>,
    pub nearby_bank: Option<NpcSearchResult>,
}

/// Validation result — Volume 4 §19
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub warnings: Vec<ValidationMessage>,
    pub errors: Vec<ValidationMessage>,
    pub suggestions: Vec<ValidationMessage>,
    pub database_issues: Vec<ValidationMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationMessage {
    pub code: String,
    pub message: String,
    pub entity: String,
    pub suggested_fix: Option<String>,
}

/// Search everywhere — Volume 4 §20
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub npcs: Vec<NpcSearchResult>,
    pub quests: Vec<QuestSearchResult>,
    pub items: Vec<ItemSearchResult>,
    pub objects: Vec<GameObjectReference>,
    pub zones: Vec<ZoneSearchResult>,
    pub creatures: Vec<CreatureDetails>,
    pub vendors: Vec<NpcSearchResult>,
    pub trainers: Vec<NpcSearchResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemSearchResult {
    pub id: u32,
    pub name: String,
    pub quality: u32,
    pub level: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZoneSearchResult {
    pub id: u32,
    pub name: String,
}

/// Blueprint suggestion — Volume 4 §21
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlueprintSuggestion {
    pub blueprint_type: String,
    pub confidence: f32,
    pub suggested_params: serde_json::Value,
}

/// Grind suggestion — Volume 4 §22
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrindSuggestion {
    pub best_creatures: Vec<CreatureDetails>,
    pub drop_rates: Vec<LootSource>,
    pub xp_per_hour: f32,
    pub suggested_loot: Vec<ItemSearchResult>,
    pub quest_overlap: Vec<QuestSearchResult>,
}

/// Item drops — Volume 4 §23
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemDrops {
    pub item_id: u32,
    pub drops: Vec<LootSource>,
}

/// World graph node — Volume 4 §24
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldGraphNode {
    pub id: String,
    pub node_type: GraphNodeType,
    pub data: serde_json::Value,
    pub connections: Vec<GraphConnection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum GraphNodeType {
    Quest,
    Npc,
    Vendor,
    Trainer,
    Flight,
    Zone,
    Object,
    Loot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphConnection {
    pub target_id: String,
    pub relationship: String,
    pub weight: f32,
}

/// Health check — Volume 4 §4
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Health {
    pub status: &'static str,
    pub database: String,
    pub uptime_sec: u64,
    pub cache_stats: crate::cache::CacheStats,
}