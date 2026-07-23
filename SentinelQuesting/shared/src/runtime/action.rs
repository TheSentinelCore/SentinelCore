//! RuntimeAction — fully-resolved, executable actions (ADR `05` Part 4).
//!
//! Every `ActionPayload` from the authoring model lowers to exactly one `RuntimeAction`; the
//! compiler has already resolved all NPC/quest/object names to numeric entries and inlined
//! coordinates. The Lua runtime dispatches on the variant. Each carries enough semantics for the
//! executor to act without further lookups.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{condition::RuntimeCondition, waypoint::RuntimeWaypoint};
use crate::authoring::{ConditionRole, VariableValue};

/// All 22 runtime action variants (see ADR `05` Part 4).
///
/// DeathSkip and DungeonMarker were removed from the enum because no authoring
/// ActionPayload path existed to produce them — they were always lowered to
/// Comment by the compiler's catch-all. Re-add when the importer supports
/// the underlying RestedXP directives.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum RuntimeAction {
    Travel(RuntimeTravel),
    AcceptQuest(RuntimeAcceptQuest),
    TurnInQuest(RuntimeTurnInQuest),
    Vendor(RuntimeVendor),
    Repair(RuntimeRepair),
    Train(RuntimeTrain),
    InteractNpc(RuntimeInteractNpc),
    UseItem(RuntimeUseItem),
    Mailbox(RuntimeMailbox),
    Bank(RuntimeBank),
    Wait(RuntimeWait),
    Escort(RuntimeEscort),
    Patrol(RuntimePatrol),
    Condition(RuntimeConditionAction),
    SetVariable(RuntimeSetVariable),
    Comment(RuntimeComment),
    Grind(RuntimeGrind),
    Kill(RuntimeKill),
    Loot(RuntimeLoot),
    Flight(RuntimeFlight),
    Hearth(RuntimeHearth),
    LearnFlightPath(RuntimeLearnFlightPath),
}

fn default_tolerance() -> f32 {
    5.0
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeTravel {
    pub destination: String,
    pub position: RuntimeWaypoint,
    #[serde(default = "default_tolerance")]
    pub tolerance: f32,
    #[serde(default)]
    pub allow_flight: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeAcceptQuest {
    pub quest_id: u32,
    pub npc_entry: u32,
    #[serde(default)]
    pub auto_complete_dialog: bool,
    #[serde(default)]
    pub optional: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeTurnInQuest {
    pub quest_id: u32,
    pub npc_entry: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub choose_reward: Option<u32>,
    #[serde(default)]
    pub optional: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeVendor {
    pub npc_entry: u32,
    #[serde(default)]
    pub sell_grey: bool,
    #[serde(default)]
    pub repair: bool,
    #[serde(default)]
    pub buy_items: Vec<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_free_slots: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeRepair {
    pub npc_entry: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeTrain {
    pub npc_entry: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trainer_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_level: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeInteractNpc {
    pub npc_entry: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gossip: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeUseItem {
    pub item: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_entry: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeMailbox {
    pub npc_entry: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeBank {
    pub npc_entry: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeWait {
    /// Seconds to wait.
    pub duration: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeEscort {
    pub npc_entry: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub area: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimePatrol {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub area: Option<Uuid>,
    #[serde(default)]
    pub waypoints: Vec<RuntimeWaypoint>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeConditionAction {
    /// Typed condition tree evaluated by the runtime before the next action.
    pub condition: RuntimeCondition,
    /// What this condition means for step progression (PR5a) — carried through unchanged from
    /// the authoring `ConditionAction.role` so the Lua runtime (PR5b) can branch on it.
    #[serde(default)]
    pub role: ConditionRole,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeSetVariable {
    pub name: String,
    pub value: VariableValue,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeComment {
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeGrind {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub polygon: Option<Uuid>,
    #[serde(default)]
    pub targets: Vec<u32>,
    #[serde(default)]
    pub loot: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_kills: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maximum_kills: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stop_condition: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeKill {
    #[serde(default)]
    pub creature_entries: Vec<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quantity: Option<u32>,
    #[serde(default)]
    pub loot: bool,
    #[serde(default)]
    pub ignore_elites: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeLoot {
    pub object_entry: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub count: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeFlight {
    pub npc_entry: u32,
    pub destination: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeHearth {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub innkeeper_entry: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeLearnFlightPath {
    pub npc_entry: u32,
}


