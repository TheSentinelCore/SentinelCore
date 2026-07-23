//! Wire DTOs shared by the QueryServer client and server (ADR `01_ARCHITECTURE` §10).
//!
//! These mirror the *world-knowledge* shape the server returns. They are intentionally
//! independent of the authoring/runtime models in `sentinel-models`: the server owns facts about
//! the game world; clients only consume them. Both `sentinel-queryclient` and the standalone
//! `SentinelQueryServer` depend on this crate so the JSON contract has a single source of truth.

use serde::{Deserialize, Serialize};

/// A world coordinate as returned by the QueryServer (map + world xyz).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct WorldPos {
    pub map: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestSummary {
    pub id: u32,
    pub title: String,
    pub level: u8,
    pub min_level: u8,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestDetail {
    pub id: u32,
    pub title: String,
    pub level: u8,
    pub min_level: u8,
    #[serde(default)]
    pub required_quests: Vec<u32>,
    #[serde(default)]
    pub next_quests: Vec<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub giver_entry: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub finisher_entry: Option<u32>,
    #[serde(default)]
    pub objectives: Vec<String>,
    /// Structured objective requirements (ADR 06 Level-1 enrichment).
    ///
    /// `objectives` above is a lossy human string (`"Objective 6"`) that cannot drive execution.
    /// This carries what an objective actually *requires*, so the compiler can synthesise the
    /// action that satisfies it instead of emitting a gate the bot can never clear.
    #[serde(default)]
    pub structured_objectives: Vec<QuestObjective>,
}

/// What an objective needs, and what can produce it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestObjective {
    /// 1-based slot, matching the runtime's `ObjectiveComplete[quest, index]`.
    pub index: u8,
    pub kind: ObjectiveKind,
    /// Creature entry, item id, or gameobject entry depending on `kind`.
    pub target_entry: u32,
    pub required: u32,
    /// For `CollectItem`: creature entries whose loot table yields `target_entry`. Empty when the
    /// item has no loot row (script-driven — an ADR 06 Level 2/3 case, not derivable here).
    #[serde(default)]
    pub sources: Vec<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ObjectiveKind {
    KillCreature,
    CollectItem,
    InteractObject,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NpcSummary {
    pub entry: u32,
    pub name: String,
    pub faction: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NpcDetail {
    pub entry: u32,
    pub name: String,
    pub faction: String,
    #[serde(default)]
    pub positions: Vec<WorldPos>,
    #[serde(default)]
    pub roles: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VendorInfo {
    pub entry: u32,
    pub name: String,
    #[serde(default)]
    pub sells: Vec<u32>,
    #[serde(default)]
    pub repairs: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrainerInfo {
    pub entry: u32,
    pub name: String,
    #[serde(default)]
    pub trains: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FlightInfo {
    pub entry: u32,
    pub name: String,
    #[serde(default)]
    pub destinations: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ObjectInfo {
    pub entry: u32,
    pub name: String,
    pub kind: String,
    pub position: WorldPos,
}

/// Static item facts for runtime decisions the client cannot make on its own — the live
/// SDK exposes no item-quality API, so grey detection for vendor selling comes from here.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ItemInfo {
    pub entry: u32,
    pub name: String,
    /// 0 = poor (grey), 1 = common, 2 = uncommon, ...
    pub quality: i32,
    /// Vendor sell price in copper.
    pub sell_price: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CreaturePolygon {
    pub creature_entry: u32,
    #[serde(default)]
    pub polygon: Vec<WorldPos>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ValidateRequest {
    /// Opaque reference strings the server should resolve/check (e.g. `"npc:197"`, `"quest:54"`).
    #[serde(default)]
    pub references: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ValidationDiagnostic {
    pub severity: String,
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ValidateResponse {
    #[serde(default)]
    pub diagnostics: Vec<ValidationDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TravelEstimateRequest {
    pub from: WorldPos,
    pub to: WorldPos,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TravelEstimateResponse {
    /// Estimated travel time in seconds.
    pub seconds: u64,
}
