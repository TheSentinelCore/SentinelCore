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

/// The travel medium the authored movement command demanded.
///
/// RestedXP spells movement four ways and two of them are instructions about *how* to travel, not
/// only about where. ADR `07_RUNTIME_PROFILE_SCHEMA` §4.2 rules all four KEEP and §7.1 maps them one
/// way and one way only: `.goto` (38,087) and `.waypoint` (593) to [`Any`](Self::Any),
/// `.groundgoto` (114) to [`Ground`](Self::Ground), `.flygoto` (1) to [`Air`](Self::Air).
///
/// Distinct from [`TravelAction::allow_flight`], which is an execution preference the editor may set
/// on any travel action. Reading that flag as this fact would mark every ordinary `.goto` route
/// ground-forced; reading this fact as that flag would lose the override `.groundgoto` exists to
/// express — §5.7: it threads mountain paths, caves and stairs where a direct or flying line fails.
///
/// This is the *authoring* vocabulary. `sentinel_models::kernel::TravelMode` is the artifact's, and
/// the compiler maps between them in one place; the two are deliberately not the same type, because
/// the kernel model is a second, additive lowering that the editor's model must not be pinned to.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TravelMedium {
    /// The author named no medium — the engine picks. `.goto`, `.waypoint`.
    #[default]
    Any,
    /// Ground travel is forced. `.groundgoto`.
    Ground,
    /// Air travel is forced. `.flygoto`.
    Air,
}

impl TravelMedium {
    /// The medium a movement command demands, or `None` when the command is not one.
    ///
    /// The single table. Both the importer (deciding which commands become a [`TravelAction`]) and
    /// the compiler's own source-line lowering read it here, so the mapping cannot drift into two
    /// disagreeing copies — which is precisely how `.groundgoto` came to be recognised by the
    /// compiler and dropped by the importer.
    ///
    /// A leading `.` is optional: the importer's lexer has already stripped it, the compiler's
    /// source-line parser has not.
    ///
    /// `.line` also carries coordinates but is variadic (arity 5..259) and is not a single movement,
    /// so it is deliberately absent.
    pub fn for_command(command: &str) -> Option<Self> {
        match command.strip_prefix('.').unwrap_or(command) {
            "goto" | "waypoint" => Some(Self::Any),
            "groundgoto" => Some(Self::Ground),
            "flygoto" => Some(Self::Air),
            _ => None,
        }
    }
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
    /// The medium the source command demanded. See [`TravelMedium`].
    ///
    /// Defaulted rather than required so a `Project` written before the field existed still loads;
    /// [`TravelMedium::Any`] is the right reading for such a file, because the only commands the
    /// importer lowered back then were `.goto` and `.waypoint`.
    #[serde(default)]
    pub medium: TravelMedium,
    /// 1-based line in the source guide this movement was authored on, when it came from one.
    ///
    /// Carried so a refusal can point at the line rather than at the step. The route builder's one
    /// refusal — a run that demanded two media — has to name the movement that broke it, and a
    /// step-wide span does not: `The Burning Crusade.lua:8158-8159` is a two-line step whose two
    /// lines disagree. `None` is an editor-authored action, or a `Project` written before the field
    /// existed; it stays `None` rather than becoming `1`, because a line number that exists is
    /// worse than an admitted gap.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_line: Option<u32>,
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

/// One creature a combat command named, as the world database resolved it.
///
/// Entry **and** name, because they are never separable: a `.mob` names a creature by name and one
/// `search_npcs` row supplies both at once. ADR 07 §5.4.1 needs the pair — `NpcRef::expect_name` is
/// what makes the kernel's first-touch probe possible, and an entry carried without its name is an
/// id nothing can verify.
///
/// The name is the **world database's** spelling, not the author's. `.mob pygmy tide crawler`
/// resolves case-insensitively; carrying the authored casing forward would fail the probe on the
/// first unit it ever saw.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreatureRef {
    /// MaNGOS `creature_template.entry`.
    pub entry: u32,
    /// The name that entry carries in the world database.
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KillTargetAction {
    /// Entry ids only — the ADR-05 runtime's projection of [`creatures`](Self::creatures), which is
    /// what `runtime::KillAction` has carried since before names were resolved at all.
    ///
    /// Written from `creatures` at every site that fills both, so the two cannot disagree about
    /// which creatures a step names.
    #[serde(default)]
    pub creature_entries: Vec<u32>,
    /// The same creatures with the name each entry carries (ADR 07 §5.4.1, §5.8).
    ///
    /// Additive and `serde(default)`: a project written before names were carried loads with an
    /// empty list, and an empty list means "no name was resolved", never "no creature".
    #[serde(default)]
    pub creatures: Vec<CreatureRef>,
    /// `.unitscan` (735) rather than `.mob` (7,456).
    ///
    /// One payload for both because they name the same thing — a creature this step's combat cares
    /// about — and differ only in what the kernel does with it: ADR 07 §5.6 puts a `.unitscan`
    /// creature in `CombatPolicy::watch_units` *as well as* in the kill whitelist, because a roamer
    /// worth noticing is a unit the task fights (§7.3.3 task 2 has no `.mob` at all and still gets
    /// `2164` in `targets`).
    ///
    /// The ADR-05 path treats a watch as **inert**, exactly as it treated `.unitscan` when the
    /// command produced a bare `Comment`: the live runtime gains no kill behaviour from this field.
    #[serde(default)]
    pub watch: bool,
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
