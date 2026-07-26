//! Actions — the atomic unit of an [`super::Operation`] (ADR `02_DATA_MODEL` §12–§23).
//!
//! `ActionPayload` is an adjacently-tagged enum (`{"type": "...", "payload": {...}}`) so the
//! serialized form matches ADR `02_DATA_MODEL` §12 (`type` + `payload`). The compiler lowers
//! each `ActionPayload` variant to its resolved `RuntimeAction` counterpart (ADR `05` Part 3).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{enums::VariableValue, guide::GuideGate, position::Position};

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
    /// Trailing per-line class restriction (e.g. `Warrior`, `Warrior/Paladin`, `!Rogue`), parsed
    /// from a `<< ...` suffix on the source line (IF3). Authoring-side only: consumed by the
    /// compiler's class-filter pass (PR2b); the runtime never sees this field.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub class_restriction: Option<String>,
    /// The same `<< ...` suffix carried as a full gate expression rather than a class list.
    ///
    /// `class_restriction` is pinned by the live ADR-05 class-filter path and stays exactly as it
    /// is; this field sits beside it so race, faction and era tails — the majority of `<<` uses —
    /// reach later passes intact instead of degrading to an `UNKNOWN_CLASS_RESTRICTION` warning.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<GuideGate>,
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
    /// The arrival radius the source line authored, verbatim, in yards — `None` when it authored
    /// none.
    ///
    /// Distinct from [`tolerance`](Self::tolerance) and not a duplicate of it. `tolerance` is what
    /// the *runtime* should treat as "arrived": the importer drops a `0`, substitutes a 5-yard
    /// default and clamps into `[5, 60]` so a typo cannot make arrival meaninglessly wide. That
    /// policy is right for execution and destroys the authored value — `A-11-23.lua:215` authors
    /// `0` and reads back as `5`.
    ///
    /// ADR `07_RUNTIME_PROFILE_SCHEMA` §7.3.3 prints `radii: [0,0,0,60,…]` for that step, so the
    /// kernel artifact needs the authored number rather than the executable one. Carried here so
    /// neither reading has to be reconstructed from the other, which is impossible in both
    /// directions: `5` may mean "authored 5", "authored 0" or "authored nothing".
    ///
    /// `u16` because that is [`Route::radii`](sentinel_models::kernel::Route)'s own width.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authored_radius: Option<u16>,
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
    /// Spell IDs the guide asked to train (`.train <spell_id>[,rank]`). RestedXP's `.train` names
    /// the SPELL, not the trainer, so dropping this loses what to actually train. Serde-defaulted:
    /// projects authored before this field simply carry an empty list.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub spells: Vec<u32>,
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

/// What a gating `Condition` action means for step progression (PR5a). The runtime does not
/// gate on conditions today (`execute_condition` advances on success *or* skip alike); this
/// tags each condition with its intended semantics so a runtime fix (PR5b) can branch on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConditionRole {
    /// Wait-until-true: the step is not done until the condition holds (`.complete`,
    /// `.collect`, `.itemcount`).
    Completion,
    /// The step only applies if the condition holds (`.isOnQuest`, `.isQuestComplete`,
    /// `.isQuestTurnedIn`, `.isQuestAvailable`).
    Applicability,
}

impl Default for ConditionRole {
    fn default() -> Self {
        Self::Completion
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConditionAction {
    /// Raw `Condition` expression (ADR `02_DATA_MODEL` §23).
    pub expression: String,
    /// What this condition means for step progression (PR5a). Defaults to `Completion` for
    /// legacy/hand-authored actions predating this field.
    #[serde(default)]
    pub role: ConditionRole,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn condition_action_without_role_field_deserializes_as_completion() {
        // Pre-PR5a JSON (legacy hand-authored/serialized actions) never had a `role` field.
        let json = r#"{"expression":"QuestCompleted(1234)"}"#;
        let action: ConditionAction = serde_json::from_str(json).expect("deserialize ok");
        assert_eq!(action.role, ConditionRole::Completion);
    }
}
