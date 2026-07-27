//! Wire DTOs shared by the QueryServer client and server (ADR `01_ARCHITECTURE` §10).
//!
//! These mirror the *world-knowledge* shape the server returns. They are intentionally
//! independent of the authoring/runtime models in `sentinel-models`: the server owns facts about
//! the game world; clients only consume them. Both `sentinel-queryclient` and the standalone
//! `SentinelQueryServer` depend on this crate so the JSON contract has a single source of truth.

use serde::{Deserialize, Serialize};

/// A world coordinate as returned by the QueryServer (map + world xyz).
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
pub struct WorldPos {
    pub map: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct QuestSummary {
    pub id: u32,
    pub title: String,
    pub level: u8,
    pub min_level: u8,
    /// Display name of the quest's zone, resolved from `quest_template.ZoneOrSort`.
    ///
    /// Empty when `ZoneOrSort <= 0`: mangos overloads that column, and a non-positive value is a
    /// *sort* bucket (class/profession/seasonal), not an area id. The search panel renders the
    /// empty string as "—" rather than inventing a zone.
    #[serde(default)]
    pub zone: String,
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

/// A single link in a quest chain — a prerequisite, follow-up, or branch quest.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestChainLink {
    pub quest_id: u32,
    pub title: String,
    /// > 0: mutually exclusive with other quests sharing this group.
    /// 0: no exclusivity.
    /// -1: only member (no exclusivity in practice).
    pub exclusive_group: i32,
}

/// Chain information for a quest: what leads to it, what follows, and the computed chain depth.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestChain {
    pub quest_id: u32,
    pub title: String,
    #[serde(default)]
    pub prerequisites: Vec<QuestChainLink>,
    #[serde(default)]
    pub follow_ups: Vec<QuestChainLink>,
    /// Total number of quests linked via PrevQuestId from root to this quest.
    pub chain_depth: u32,
    /// Other quests sharing an ExclusiveGroup that are not direct prerequisites.
    #[serde(default)]
    pub branches: Vec<QuestChainLink>,
}

/// A single resolved objective in the `/quest/{id}/objectives` response.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ObjectiveResponseItem {
    pub index: u8,
    /// "kill", "collect", or "interact".
    pub kind: String,
    /// Creature entry, item id, or gameobject entry depending on kind.
    pub entry: u32,
    pub name: String,
    #[serde(default)]
    pub count: u32,
    /// For "collect": entries of creatures whose loot table yields this item.
    #[serde(default)]
    pub source_creatures: Vec<u32>,
}

/// The `/quest/{id}/objectives` response.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestObjectivesResponse {
    pub quest_id: u32,
    #[serde(default)]
    pub objectives: Vec<ObjectiveResponseItem>,
    /// Human-readable objective text assembled from objective data.
    pub objective_text: String,
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

/// One row of a creature's loot table.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct LootEntry {
    pub item: u32,
    pub name: String,
    /// Percentage chance. Mangos stores quest drops as a *negative* `ChanceOrQuestChance`; the
    /// server normalises to the magnitude, so this is always in `0..=100`.
    pub drop_chance: f32,
}

/// A quest an NPC takes part in, and which end of it they hold.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct NpcQuestRef {
    pub quest_id: u32,
    pub title: String,
    /// `"starter"` (`creature_questrelation`) or `"finisher"` (`creature_involvedrelation`).
    /// An NPC that does both appears once per role.
    pub role: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct NpcDetail {
    pub entry: u32,
    pub name: String,
    pub faction: String,
    #[serde(default)]
    pub positions: Vec<WorldPos>,
    #[serde(default)]
    pub roles: Vec<String>,
    /// `creature_template.MinLevel`. Spawns of a level range report their floor.
    #[serde(default)]
    pub level: u8,
    /// `"normal" | "elite" | "rare elite" | "boss" | "rare"`, from `creature_template.Rank`.
    #[serde(default)]
    pub classification: String,
    #[serde(default)]
    pub loot: Vec<LootEntry>,
    #[serde(default)]
    pub quests: Vec<NpcQuestRef>,
}

/// One row of a vendor's inventory.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct VendorItem {
    pub item_entry: u32,
    pub name: String,
    /// Copper. `0` when the item costs an `ExtendedCost` currency (honor, arena points, tokens)
    /// that has no copper equivalent — the panel renders that as "special cost", not "free".
    pub price: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct VendorInfo {
    pub entry: u32,
    pub name: String,
    /// Resolved inventory rows. This replaced a bare `Vec<u32>` of item ids: the Properties panel
    /// has no item lookup of its own, so ids alone rendered as numbers with no name or price.
    #[serde(default)]
    pub sells: Vec<VendorItem>,
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

/// One leg of a `POST /travel/route` request.
///
/// Deliberately permissive on the wire and strict in the handler: a walk carries `from`/`to` and
/// no `type`, a taxi carries `type: "taxi"` plus its node ids. An untagged enum would reject a
/// malformed body with serde's "data did not match any variant", which names neither the segment
/// nor the missing field — and the travel editor's whole job is telling the author what is wrong.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TravelRouteSegmentRequest {
    /// `"taxi"`, or absent/`"walk"` for a ground leg.
    #[serde(rename = "type", default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<WorldPos>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to: Option<WorldPos>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from_node: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to_node: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TravelRouteRequest {
    #[serde(default)]
    pub segments: Vec<TravelRouteSegmentRequest>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TravelRouteSegment {
    /// `"walk"` or `"taxi"`, echoed so the editor can label the row without re-deriving it.
    #[serde(rename = "type")]
    pub kind: String,
    /// Straight-line yards. Absent only if a future segment kind has no distance to report.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub distance_m: Option<f32>,
    pub estimated_s: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TravelRouteResponse {
    #[serde(default)]
    pub segments: Vec<TravelRouteSegment>,
    /// Always the sum of the segment estimates, so the editor never has to add them up itself and
    /// then disagree with the server about the total.
    pub total_s: u64,
}

/// One creature entry aggregated over the spawns of it that matched a query.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SpawnGroup {
    pub entry: u32,
    pub name: String,
    pub spawn_count: u32,
    /// Midpoint of `creature_template.MinLevel`/`MaxLevel` — a single creature entry is a level
    /// *range* in mangos, and the grind planner needs one number to sort on.
    pub avg_level: u8,
    pub classification: String,
    /// What a character of the creature's own level earns for the kill. See the QueryServer's
    /// `xp_reward` for the mangos formula it reproduces.
    pub xp_reward: u32,
    /// Yards from the query centre to the closest of this entry's matching spawns. Absent for
    /// zone-wide aggregation, which has no centre.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nearest_distance: Option<f32>,
    /// Matching spawn positions, nearest first. Bounded by the server; the grind generator turns
    /// these into waypoints, so it needs coordinates and not just a count.
    #[serde(default)]
    pub positions: Vec<WorldPos>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct NearbySpawnsResponse {
    pub map: u32,
    pub center: WorldPos,
    /// Yards, as requested.
    pub radius: f32,
    #[serde(default)]
    pub creatures: Vec<SpawnGroup>,
}

/// One gameobject entry aggregated over its spawns in a zone.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ZoneObject {
    pub entry: u32,
    pub name: String,
    pub spawn_count: u32,
    /// `gameobject_template.type` (chest, door, herb node, …), raw rather than named: the client
    /// already owns the enum, and inventing names here would be a second authority for them.
    #[serde(rename = "type")]
    pub kind: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ZoneSpawns {
    pub zone_id: u32,
    pub zone_name: String,
    #[serde(default)]
    pub creatures: Vec<SpawnGroup>,
    #[serde(default)]
    pub objects: Vec<ZoneObject>,
}

/// One level-banded density region inside a zone.
///
/// The `density_per_km2` figure is computed from the committed spawn→zone index and an area
/// estimate derived from the spread of matching creature spawns. It is a planning aid, not a
/// guarantee of in-game spawn density.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct DensityRegion {
    pub min_level: u8,
    pub max_level: u8,
    pub density_per_km2: f32,
    pub avg_xp_per_hour: u32,
}

/// A coordinate the density endpoint identifies as low-density relative to nearby spawns.
///
/// `distance_from_spawns` is the horizontal distance in yards from this point to the nearest
/// creature spawn considered by the density calculation.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SafeSpot {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub distance_from_spawns: f32,
}

/// `GET /spawns/density/{zone}` response.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SpawnDensityResponse {
    pub zone_id: u32,
    #[serde(default)]
    pub density_regions: Vec<DensityRegion>,
    #[serde(default)]
    pub safe_spots: Vec<SafeSpot>,
}
