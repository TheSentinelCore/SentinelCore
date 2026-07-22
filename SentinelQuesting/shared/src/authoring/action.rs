//! Actions — the atomic unit of an [`super::Operation`] (ADR `02_DATA_MODEL` §12–§23).
//!
//! `ActionPayload` is an adjacently-tagged enum (`{"type": "...", "payload": {...}}`) so the
//! serialized form matches ADR `02_DATA_MODEL` §12 (`type` + `payload`). The compiler lowers
//! each `ActionPayload` variant to its resolved `RuntimeAction` counterpart (ADR `05` Part 3).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{enums::VariableValue, position::Position};

/// An editable action. Carries its own enable flag and an optional gate expression
/// (ADR `02_DATA_MODEL` §23 grammar) evaluated by the runtime before execution.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Action {
    pub id: Uuid,
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Optional gate; serialized as a `Condition` expression string.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub condition: Option<String>,
    /// Author note / provenance (e.g. RestedXP import source line).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// Flattened so the serialized form is `{ "id", "enabled", "type", "payload", ... }`
    /// (ADR `02_DATA_MODEL` §12: type + payload as siblings).
    #[serde(flatten)]
    pub payload: ActionPayload,
}

fn default_true() -> bool {
    true
}

/// All supported authoring actions (ADR `02_DATA_MODEL` §13), with resolved payloads.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ActionPayload {
    AcceptQuest(AcceptQuestAction),
    TurnInQuest(TurnInQuestAction),
    Travel(TravelAction),
    Kill(KillTargetAction),
    GrindArea(GrindAreaAction),
    LootObject(LootObjectAction),
    InteractNPC(InteractNpcAction),
    Vendor(VendorAction),
    Repair(RepairAction),
    Train(TrainerAction),
    LearnFlightPath(LearnFlightPathAction),
    UseItem(UseItemAction),
    Flight(FlightAction),
    SetHearth(SetHearthAction),
    Hearth(HearthAction),
    Wait(WaitAction),
    Escort(EscortAction),
    Patrol(PatrolAction),
    Mailbox(MailboxAction),
    Bank(BankAction),
    Condition(ConditionAction),
    SetVariable(SetVariableAction),
    Comment(CommentAction),
}

fn default_tolerance() -> f32 {
    5.0
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TravelAction {
    pub destination: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position: Option<Position>,
    #[serde(default = "default_tolerance")]
    pub tolerance: f32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mount: Option<String>,
    #[serde(default)]
    pub allow_flight: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AcceptQuestAction {
    pub quest: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub npc: Option<Uuid>,
    #[serde(default)]
    pub auto_complete_dialog: bool,
    #[serde(default)]
    pub optional: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TurnInQuestAction {
    pub quest: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub npc: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub choose_reward: Option<u32>,
    #[serde(default)]
    pub optional: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KillTargetAction {
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
pub struct GrindAreaAction {
    /// [`Uuid`] of an `Area` in the project's areas collection.
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
pub struct LootObjectAction {
    pub object: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub count: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InteractNpcAction {
    pub npc: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gossip: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VendorAction {
    pub npc: Uuid,
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
pub struct RepairAction {
    pub npc: Uuid,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrainerAction {
    pub npc: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trainer_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_level: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnFlightPathAction {
    pub npc: Uuid,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UseItemAction {
    pub item: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<Uuid>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FlightAction {
    pub npc: Uuid,
    pub destination: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SetHearthAction {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub npc: Option<Uuid>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HearthAction {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub innkeeper: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WaitAction {
    /// Seconds to wait.
    pub duration: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EscortAction {
    pub npc: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub area: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PatrolAction {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub area: Option<Uuid>,
    #[serde(default)]
    pub waypoints: Vec<Position>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MailboxAction {
    pub npc: Uuid,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BankAction {
    pub npc: Uuid,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConditionAction {
    /// Raw `Condition` expression (ADR `02_DATA_MODEL` §23).
    pub expression: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SetVariableAction {
    pub name: String,
    pub value: VariableValue,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CommentAction {
    pub text: String,
}
