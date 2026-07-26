//! The questing domain plugin (ADR 09 §4).
//!
//! Ten task types chosen to cover the 48 RestedXP directive verbs the old importer dropped — that
//! is the coverage target, not the count.
//!
//! Every lowering below emits **only** existing [`RuntimeAction`] variants. That constraint is the
//! interesting one: `Gate` wanted a branch primitive and got `Condition`; `Collect` wanted an
//! object pickup and got `Loot`. A task that genuinely cannot be expressed in the frozen
//! vocabulary is a runtime change with its own review, not something to paper over here.

use sentinel_models::authoring::ConditionRole;
use sentinel_models::platform::{EntityKind, EntityRef, Intent, IntentValue};
use sentinel_models::runtime::{
    GuardedAction, RuntimeAcceptQuest, RuntimeAction, RuntimeCondition, RuntimeConditionAction,
    RuntimeFlight, RuntimeHearth, RuntimeKill, RuntimeLoot, RuntimeTrain, RuntimeTravel,
    RuntimeTurnInQuest, RuntimeVendor, RuntimeWaypoint,
};

use crate::db::ResolverDb;
use crate::diagnostic::Diagnostic;
use crate::registry::{Field, FieldKind, TaskType, ValidationRule};

/// Matches `RuntimeTravel`'s own serde default, so an authored `tolerance` of 5 and an absent one
/// produce byte-identical plans — which is what keeps re-resolution diffs readable.
const DEFAULT_TOLERANCE: f32 = 5.0;

const QUEST_STATES: &[&str] = &["accepted", "completed", "rewarded"];

/// The questing task set, in ADR 09 §4 declaration order.
pub fn questing_task_types() -> Vec<TaskType> {
    vec![
        accept_quest(),
        turn_in(),
        kill(),
        collect(),
        vendor(),
        trainer(),
        flight(),
        hearth(),
        gate(),
        travel(),
    ]
}

// ---------------------------------------------------------------------------
// Intent readers
//
// Every one of these tolerates a missing or wrong-kinded field by returning `None`. The schema
// check has already reported those as diagnostics; a second report from lowering would show the
// author the same problem twice, and a panic here would take down a batch resolve over one typo.
// ---------------------------------------------------------------------------

fn entity_of<'a>(intent: &'a Intent, name: &str) -> Option<&'a EntityRef> {
    intent.entity(name)
}

fn int_of(intent: &Intent, name: &str) -> Option<i64> {
    match intent.get(name) {
        Some(IntentValue::Int(value)) => Some(*value),
        _ => None,
    }
}

fn f32_of(intent: &Intent, name: &str) -> Option<f32> {
    match intent.get(name) {
        Some(IntentValue::Float(value)) => Some(*value as f32),
        Some(IntentValue::Int(value)) => Some(*value as f32),
        _ => None,
    }
}

fn bool_of(intent: &Intent, name: &str) -> Option<bool> {
    match intent.get(name) {
        Some(IntentValue::Bool(value)) => Some(*value),
        _ => None,
    }
}

fn text_of<'a>(intent: &'a Intent, name: &str) -> Option<&'a str> {
    match intent.get(name) {
        Some(IntentValue::Text(value)) => Some(value.as_str()),
        _ => None,
    }
}

fn entity_ids(intent: &Intent, name: &str) -> Vec<u32> {
    match intent.get(name) {
        Some(IntentValue::List(items)) => items
            .iter()
            .filter_map(|item| match item {
                IntentValue::Entity(entity) => Some(entity.id),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

// ---------------------------------------------------------------------------
// Lowering helpers
// ---------------------------------------------------------------------------

/// The name to show for an entity. The database wins over `EntityRef::label`, which ADR 09a §1.2
/// defines as a cache that is refreshed on resolve and never authoritative — a campaign checked in
/// two expansions ago would otherwise ship its stale names into the plan.
fn display_name(db: &dyn ResolverDb, kind: EntityKind, id: u32, fallback: &str) -> String {
    if let Some(label) = db.label(kind, id) {
        return label;
    }
    if !fallback.is_empty() {
        return fallback.to_string();
    }
    format!("{kind}:{id}")
}

/// A `Travel` to an entry's spawn, or `None` plus a diagnostic when the database has no spawn for
/// it. Deliberately non-fatal: the interaction that follows still lowers, so a plan with a missing
/// waypoint degrades to "interact where you stand" instead of vanishing.
fn travel_to(
    db: &dyn ResolverDb,
    kind: EntityKind,
    id: u32,
    label: &str,
    field: &'static str,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<GuardedAction> {
    let Some(spawn) = db.spawn(kind, id) else {
        diagnostics.push(
            Diagnostic::warning(
                "resolver.spawn.unknown",
                format!("no spawn point for `{kind}:{id}`; the travel step was dropped"),
            )
            .with_field(field),
        );
        return None;
    };
    Some(
        RuntimeAction::Travel(RuntimeTravel {
            destination: display_name(db, kind, id, label),
            position: spawn.waypoint(),
            tolerance: DEFAULT_TOLERANCE,
            allow_flight: false,
            timeout: None,
        })
        .into(),
    )
}

fn no_validation(_: &Intent, _: &dyn ResolverDb) -> Vec<Diagnostic> {
    Vec::new()
}

// ---------------------------------------------------------------------------
// questing.AcceptQuest
// ---------------------------------------------------------------------------

fn accept_quest() -> TaskType {
    TaskType {
        type_name: "questing.AcceptQuest",
        schema: vec![
            Field::entity("quest", EntityKind::Quest).required(),
            Field::entity("from", EntityKind::Npc),
            Field::new("optional", FieldKind::Bool),
        ],
        lower: lower_accept_quest,
        validate: no_validation,
    }
}

fn lower_accept_quest(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let Some(quest) = entity_of(intent, "quest") else {
        return Vec::new();
    };
    let Some(npc_entry) = quest_npc(intent, db, "from", quest.id, diagnostics) else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(db, EntityKind::Npc, npc_entry, "", "from", diagnostics) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::AcceptQuest(RuntimeAcceptQuest {
            quest_id: quest.id,
            npc_entry,
            auto_complete_dialog: false,
            optional: bool_of(intent, "optional").unwrap_or(false),
        })
        .into(),
    );
    actions
}

/// The authored NPC, or the database relation when the author left it to the resolver. An entry of
/// `0` is not an acceptable fallback — the runtime would happily walk to nothing and report
/// success — so an unresolvable giver drops the whole lowering with an error instead.
fn quest_npc(
    intent: &Intent,
    db: &dyn ResolverDb,
    field: &'static str,
    quest_id: u32,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<u32> {
    if let Some(npc) = entity_of(intent, field) {
        return Some(npc.id);
    }
    let from_db = if field == "from" {
        db.quest_giver(quest_id)
    } else {
        db.quest_ender(quest_id)
    };
    if from_db.is_none() {
        let (code, role) = if field == "from" {
            ("resolver.quest.no_giver", "offers")
        } else {
            ("resolver.quest.no_ender", "takes")
        };
        diagnostics.push(
            Diagnostic::error(
                code,
                format!("no `{field}` was authored and the database knows no npc that {role} quest {quest_id}"),
            )
            .with_field(field),
        );
    }
    from_db
}

// ---------------------------------------------------------------------------
// questing.TurnIn
// ---------------------------------------------------------------------------

fn turn_in() -> TaskType {
    TaskType {
        type_name: "questing.TurnIn",
        schema: vec![
            Field::entity("quest", EntityKind::Quest).required(),
            Field::entity("to", EntityKind::Npc),
            Field::new("choose_reward", FieldKind::Int).with_rules(vec![ValidationRule::MinInt(0)]),
            Field::new("optional", FieldKind::Bool),
        ],
        lower: lower_turn_in,
        validate: no_validation,
    }
}

fn lower_turn_in(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let Some(quest) = entity_of(intent, "quest") else {
        return Vec::new();
    };
    let Some(npc_entry) = quest_npc(intent, db, "to", quest.id, diagnostics) else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(db, EntityKind::Npc, npc_entry, "", "to", diagnostics) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::TurnInQuest(RuntimeTurnInQuest {
            quest_id: quest.id,
            npc_entry,
            choose_reward: int_of(intent, "choose_reward").and_then(|n| u32::try_from(n).ok()),
            optional: bool_of(intent, "optional").unwrap_or(false),
        })
        .into(),
    );
    actions
}

// ---------------------------------------------------------------------------
// questing.Kill
// ---------------------------------------------------------------------------

fn kill() -> TaskType {
    TaskType {
        type_name: "questing.Kill",
        schema: vec![
            Field::entity("target", EntityKind::Npc).required(),
            Field::new("count", FieldKind::Int).with_rules(vec![ValidationRule::MinInt(1)]),
            Field::new("loot", FieldKind::Bool),
            Field::new("ignore_elites", FieldKind::Bool),
        ],
        lower: lower_kill,
        validate: no_validation,
    }
}

fn lower_kill(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let Some(target) = entity_of(intent, "target") else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(
        db,
        target.kind,
        target.id,
        &target.label,
        "target",
        diagnostics,
    ) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::Kill(RuntimeKill {
            creature_entries: vec![target.id],
            quantity: int_of(intent, "count").and_then(|n| u32::try_from(n).ok()),
            loot: bool_of(intent, "loot").unwrap_or(false),
            ignore_elites: bool_of(intent, "ignore_elites").unwrap_or(false),
        })
        .into(),
    );
    actions
}

// ---------------------------------------------------------------------------
// questing.Collect
// ---------------------------------------------------------------------------

fn collect() -> TaskType {
    TaskType {
        type_name: "questing.Collect",
        schema: vec![
            Field::entity("object", EntityKind::Object).required(),
            Field::new("count", FieldKind::Int).with_rules(vec![ValidationRule::MinInt(1)]),
        ],
        lower: lower_collect,
        validate: no_validation,
    }
}

fn lower_collect(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let Some(object) = entity_of(intent, "object") else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(
        db,
        object.kind,
        object.id,
        &object.label,
        "object",
        diagnostics,
    ) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::Loot(RuntimeLoot {
            object_entry: object.id,
            count: int_of(intent, "count").and_then(|n| u32::try_from(n).ok()),
        })
        .into(),
    );
    actions
}

// ---------------------------------------------------------------------------
// questing.Vendor
// ---------------------------------------------------------------------------

fn vendor() -> TaskType {
    TaskType {
        type_name: "questing.Vendor",
        schema: vec![
            Field::entity("npc", EntityKind::Npc).required(),
            Field::new("sell_grey", FieldKind::Bool),
            Field::new("repair", FieldKind::Bool),
            Field::entity_list("buy", EntityKind::Item),
            Field::new("minimum_free_slots", FieldKind::Int)
                .with_rules(vec![ValidationRule::MinInt(0)]),
        ],
        lower: lower_vendor,
        validate: no_validation,
    }
}

fn lower_vendor(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let Some(npc) = entity_of(intent, "npc") else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(db, npc.kind, npc.id, &npc.label, "npc", diagnostics) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::Vendor(RuntimeVendor {
            npc_entry: npc.id,
            sell_grey: bool_of(intent, "sell_grey").unwrap_or(false),
            repair: bool_of(intent, "repair").unwrap_or(false),
            buy_items: entity_ids(intent, "buy"),
            minimum_free_slots: int_of(intent, "minimum_free_slots")
                .and_then(|n| u32::try_from(n).ok()),
        })
        .into(),
    );
    actions
}

// ---------------------------------------------------------------------------
// questing.Trainer
// ---------------------------------------------------------------------------

fn trainer() -> TaskType {
    TaskType {
        type_name: "questing.Trainer",
        schema: vec![
            Field::entity("npc", EntityKind::Npc).required(),
            Field::entity_list("spells", EntityKind::Spell),
            Field::new("trainer_type", FieldKind::Text)
                .with_rules(vec![ValidationRule::NonEmptyText]),
            Field::new("minimum_level", FieldKind::Int)
                .with_rules(vec![ValidationRule::MinInt(1), ValidationRule::MaxInt(255)]),
        ],
        lower: lower_trainer,
        validate: no_validation,
    }
}

fn lower_trainer(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let Some(npc) = entity_of(intent, "npc") else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(db, npc.kind, npc.id, &npc.label, "npc", diagnostics) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::Train(RuntimeTrain {
            npc_entry: npc.id,
            spells: entity_ids(intent, "spells"),
            trainer_type: text_of(intent, "trainer_type").map(str::to_string),
            minimum_level: int_of(intent, "minimum_level").and_then(|n| u8::try_from(n).ok()),
        })
        .into(),
    );
    actions
}

// ---------------------------------------------------------------------------
// questing.Flight
// ---------------------------------------------------------------------------

fn flight() -> TaskType {
    TaskType {
        type_name: "questing.Flight",
        schema: vec![
            Field::entity("npc", EntityKind::Npc).required(),
            Field::new("destination", FieldKind::Text)
                .required()
                .with_rules(vec![ValidationRule::NonEmptyText]),
        ],
        lower: lower_flight,
        validate: no_validation,
    }
}

fn lower_flight(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let (Some(npc), Some(destination)) = (entity_of(intent, "npc"), text_of(intent, "destination"))
    else {
        return Vec::new();
    };

    let mut actions = Vec::new();
    if let Some(travel) = travel_to(db, npc.kind, npc.id, &npc.label, "npc", diagnostics) {
        actions.push(travel);
    }
    actions.push(
        RuntimeAction::Flight(RuntimeFlight {
            npc_entry: npc.id,
            destination: destination.to_string(),
        })
        .into(),
    );
    actions
}

// ---------------------------------------------------------------------------
// questing.Hearth
// ---------------------------------------------------------------------------

fn hearth() -> TaskType {
    TaskType {
        type_name: "questing.Hearth",
        schema: vec![
            Field::new("destination", FieldKind::Text).with_rules(vec![ValidationRule::NonEmptyText]),
            Field::entity("innkeeper", EntityKind::Npc),
        ],
        lower: lower_hearth,
        validate: no_validation,
    }
}

/// No `Travel` is emitted: a hearthstone is used where the player stands. `innkeeper` records
/// where the hearth is bound, not somewhere to walk to.
fn lower_hearth(
    intent: &Intent,
    _db: &dyn ResolverDb,
    _diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    vec![RuntimeAction::Hearth(RuntimeHearth {
        innkeeper_entry: entity_of(intent, "innkeeper").map(|npc| npc.id),
        destination: text_of(intent, "destination").map(str::to_string),
    })
    .into()]
}

// ---------------------------------------------------------------------------
// questing.Gate
// ---------------------------------------------------------------------------

fn gate() -> TaskType {
    TaskType {
        type_name: "questing.Gate",
        schema: vec![
            Field::entity("quest", EntityKind::Quest),
            Field::new("quest_state", FieldKind::Text)
                .with_rules(vec![ValidationRule::OneOf(QUEST_STATES)]),
            Field::new("level", FieldKind::Int)
                .with_rules(vec![ValidationRule::MinInt(1), ValidationRule::MaxInt(255)]),
            Field::entity("item", EntityKind::Item),
        ],
        lower: lower_gate,
        validate: validate_gate,
    }
}

/// A gate with no clause would lower to nothing and let execution straight through, which is the
/// opposite of what the author asked for. Fail loud instead.
fn validate_gate(intent: &Intent, _db: &dyn ResolverDb) -> Vec<Diagnostic> {
    if gate_clauses(intent).is_empty() {
        return vec![Diagnostic::error(
            "resolver.gate.no_clause",
            "a gate needs at least one of `quest`, `level`, or `item`",
        )];
    }
    Vec::new()
}

/// Clause order is fixed (quest, level, item) rather than following the intent's key order so the
/// emitted condition tree is stable across authoring edits.
fn gate_clauses(intent: &Intent) -> Vec<RuntimeCondition> {
    let mut clauses = Vec::new();

    if let Some(quest) = entity_of(intent, "quest") {
        clauses.push(
            match text_of(intent, "quest_state").unwrap_or("completed") {
                "accepted" => RuntimeCondition::QuestAccepted(quest.id),
                "rewarded" => RuntimeCondition::QuestRewarded(quest.id),
                // Anything else has already been rejected by the field's `OneOf` rule; defaulting
                // to the documented default here keeps lowering total.
                _ => RuntimeCondition::QuestCompleted(quest.id),
            },
        );
    }
    if let Some(level) = int_of(intent, "level").and_then(|n| u8::try_from(n).ok()) {
        clauses.push(RuntimeCondition::LevelAtLeast(level));
    }
    if let Some(item) = entity_of(intent, "item") {
        clauses.push(RuntimeCondition::HasItem(item.id));
    }

    clauses
}

fn lower_gate(
    intent: &Intent,
    _db: &dyn ResolverDb,
    _diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let mut clauses = gate_clauses(intent);
    let condition = match clauses.len() {
        0 => return Vec::new(),
        // A one-element `All` would be noise in every diff of a single-clause gate.
        1 => clauses.remove(0),
        _ => RuntimeCondition::All(clauses),
    };

    vec![RuntimeAction::Condition(RuntimeConditionAction {
        condition,
        // Wait-until-true. A gate blocks the route until it opens; `Applicability` would let the
        // route run straight past a closed gate.
        role: ConditionRole::Completion,
    })
    .into()]
}

// ---------------------------------------------------------------------------
// questing.Travel
// ---------------------------------------------------------------------------

fn travel() -> TaskType {
    TaskType {
        type_name: "questing.Travel",
        schema: vec![
            // No `entity_type`: a route may head for an npc, an object, or an area, and pinning
            // one kind would make the other two unauthorable.
            Field::new("to", FieldKind::Entity),
            Field::new("map", FieldKind::Int).with_rules(vec![ValidationRule::MinInt(0)]),
            Field::new("x", FieldKind::Float),
            Field::new("y", FieldKind::Float),
            Field::new("z", FieldKind::Float),
            Field::new("destination", FieldKind::Text),
            Field::new("tolerance", FieldKind::Float),
            Field::new("allow_flight", FieldKind::Bool),
        ],
        lower: lower_travel,
        validate: no_validation,
    }
}

fn lower_travel(
    intent: &Intent,
    db: &dyn ResolverDb,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<GuardedAction> {
    let explicit = match (
        int_of(intent, "map"),
        f32_of(intent, "x"),
        f32_of(intent, "y"),
        f32_of(intent, "z"),
    ) {
        (Some(map), Some(x), Some(y), Some(z)) => u32::try_from(map)
            .ok()
            .map(|map| RuntimeWaypoint::new(map, x, y, z)),
        _ => None,
    };

    let target = entity_of(intent, "to");
    let position = match (explicit, target) {
        // Authored coordinates win: they are what a recorder observed, and the database's
        // canonical spawn for an entry may be a different one of its many spawns.
        (Some(waypoint), _) => waypoint,
        (None, Some(entity)) => match db.spawn(entity.kind, entity.id) {
            Some(spawn) => spawn.waypoint(),
            None => {
                diagnostics.push(
                    Diagnostic::error(
                        "resolver.spawn.unknown",
                        format!("no spawn point for `{}`", entity.as_ref_string()),
                    )
                    .with_field("to"),
                );
                return Vec::new();
            }
        },
        (None, None) => {
            diagnostics.push(Diagnostic::error(
                "resolver.travel.no_destination",
                "a travel needs either `to` or all of `map`, `x`, `y`, `z`",
            ));
            return Vec::new();
        }
    };

    let destination = match (text_of(intent, "destination"), target) {
        (Some(text), _) => text.to_string(),
        (None, Some(entity)) => display_name(db, entity.kind, entity.id, &entity.label),
        (None, None) => String::new(),
    };

    vec![RuntimeAction::Travel(RuntimeTravel {
        destination,
        position,
        tolerance: f32_of(intent, "tolerance").unwrap_or(DEFAULT_TOLERANCE),
        allow_flight: bool_of(intent, "allow_flight").unwrap_or(false),
        timeout: None,
    })
    .into()]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{InMemoryDb, Spawn};

    fn db() -> InMemoryDb {
        InMemoryDb::new("test@0")
            .with_spawn(EntityKind::Npc, 823, Spawn::new(0, 1.0, 2.0, 3.0))
            .with_label(EntityKind::Npc, 823, "Deputy Willem")
    }

    #[test]
    fn every_task_type_has_a_questing_namespace() {
        for task in questing_task_types() {
            assert!(
                task.type_name.starts_with("questing."),
                "{} is not namespaced",
                task.type_name
            );
        }
    }

    #[test]
    fn a_single_clause_gate_emits_a_bare_condition_not_a_one_element_all() {
        let mut intent = Intent::new();
        intent.insert("level", 10i64);
        let mut diagnostics = Vec::new();
        let actions = lower_gate(&intent, &db() as &dyn ResolverDb, &mut diagnostics);
        let RuntimeAction::Condition(action) = &actions[0].action else {
            panic!("gate lowers to Condition");
        };
        assert_eq!(action.condition, RuntimeCondition::LevelAtLeast(10));
    }

    #[test]
    fn authored_coordinates_beat_the_databases_canonical_spawn() {
        // An entry has many spawns; a recorder observed a specific one. Preferring the database
        // here would quietly relocate every recorded step.
        let mut intent = Intent::new();
        intent.insert("to", EntityRef::new(EntityKind::Npc, 823, "Deputy Willem"));
        intent.insert("map", 0i64);
        intent.insert("x", 99.0f64);
        intent.insert("y", 98.0f64);
        intent.insert("z", 97.0f64);
        let mut diagnostics = Vec::new();
        let actions = lower_travel(&intent, &db() as &dyn ResolverDb, &mut diagnostics);
        let RuntimeAction::Travel(travel) = &actions[0].action else {
            panic!("travel lowers to Travel");
        };
        assert_eq!(travel.position.world_x, 99.0);
        assert!(diagnostics.is_empty());
    }

    #[test]
    fn a_travel_with_neither_target_nor_coordinates_errors_instead_of_going_to_the_origin() {
        let mut diagnostics = Vec::new();
        let actions = lower_travel(&Intent::new(), &db() as &dyn ResolverDb, &mut diagnostics);
        assert!(actions.is_empty());
        assert_eq!(diagnostics[0].code, "resolver.travel.no_destination");
    }

    #[test]
    fn a_hearth_never_emits_a_travel() {
        let mut intent = Intent::new();
        intent.insert("destination", "Goldshire");
        let mut diagnostics = Vec::new();
        let actions = lower_hearth(&intent, &db() as &dyn ResolverDb, &mut diagnostics);
        assert_eq!(actions.len(), 1);
        assert!(matches!(actions[0].action, RuntimeAction::Hearth(_)));
    }

    #[test]
    fn a_turn_in_without_an_authored_npc_uses_the_database_relation() {
        let db = db().with_quest_ender(783, 823);
        let mut intent = Intent::new();
        intent.insert("quest", EntityRef::new(EntityKind::Quest, 783, "q"));
        let mut diagnostics = Vec::new();
        let actions = lower_turn_in(&intent, &db as &dyn ResolverDb, &mut diagnostics);
        let RuntimeAction::TurnInQuest(turn_in) = &actions[1].action else {
            panic!("second action is the turn-in");
        };
        assert_eq!(turn_in.npc_entry, 823);
        assert!(diagnostics.is_empty());
    }
}
