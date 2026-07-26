//! Integration tests for the Compiler.

use sentinel_compiler::Compiler;
use sentinel_models::authoring::{
    Action, ActionPayload, ConditionAction, ConditionRole, GameObjectReference, LootObjectAction,
    NPCReference, Operation, Position, VendorAction,
};
use sentinel_models::authoring::new_project;
use sentinel_models::runtime::{RuntimeAction, RuntimeCondition};
use uuid::Uuid;

fn condition_action(expression: &str) -> Action {
    condition_action_with_role(expression, ConditionRole::Completion)
}

fn vendor_action_with_class(npc: Uuid, class_restriction: Option<&str>) -> Action {
    Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: class_restriction.map(|s| s.to_string()),
        gate: None,
        note: None,
        payload: ActionPayload::Vendor(VendorAction {
            npc,
            sell_grey: false,
            repair: false,
            buy_items: vec![],
            minimum_free_slots: None,
        }),
    }
}

fn condition_action_with_role(expression: &str, role: ConditionRole) -> Action {
    Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        gate: None,
        note: None,
        payload: ActionPayload::Condition(ConditionAction { expression: expression.to_string(), role }),
    }
}

fn loot_action(object: Uuid) -> Action {
    Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        gate: None,
        note: None,
        payload: ActionPayload::LootObject(LootObjectAction { object, count: None }),
    }
}

#[test]
fn compiles_project_to_runtime_profile() {
    let npc_id = Uuid::new_v4();
    let npc = NPCReference {
        id: npc_id,
        entry: Some(123),
        guid: None,
        name: "Test NPC".to_string(),
        faction: None,
        roles: vec![],
        position: None,
        source: None,
        notes: None,
    };
    let mut project = new_project("test");
    project.npc_library.push(npc);
    
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        gate: None,
        note: None,
        payload: ActionPayload::Vendor(VendorAction {
            npc: npc_id,
            sell_grey: false,
            repair: false,
            buy_items: vec![],
            minimum_free_slots: None,
        }),
    });
    project.operations.push(op);
    
    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    assert_eq!(profile.operations.len(), 1);
    assert_eq!(profile.operations[0].actions.len(), 1);
}

#[test]
fn unresolved_npc_reference_degrades_to_comment_and_is_reported() {
    let mut project = new_project("test");

    let mut op = Operation::new("test-op".to_string());
    let action = Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        gate: None,
        note: None,
        payload: ActionPayload::Vendor(VendorAction {
            npc: Uuid::new_v4(), // Non-existent NPC
            sell_grey: false,
            repair: false,
            buy_items: vec![],
            minimum_free_slots: None,
        }),
    };
    let action_id = action.id;
    op.actions.push(action);
    project.operations.push(op);

    let (profile, report) = Compiler::compile(&project)
        .expect("unresolved NPC must not abort the whole guide compile");
    let RuntimeAction::Comment(c) = &profile.operations[0].actions[0].action else {
        panic!("expected unresolved NPC to lower to a Comment, got: {:?}", profile.operations[0].actions[0].action)
    };
    assert!(c.text.contains("unresolved NPC"), "got: {}", c.text);
    assert_eq!(report.unresolved, 1);
    assert!(
        report.unmapped_conditions.iter().any(|d| {
            d.code == "UNRESOLVED_NPC" && d.action.as_deref() == Some(&action_id.to_string())
        }),
        "got: {:?}", report.unmapped_conditions
    );
}

#[test]
fn missing_npc_reference_option_degrades_to_comment_and_is_reported() {
    // AcceptQuest.npc is Option<Uuid> — the importer leaves it `None` when it cannot resolve a
    // quest giver at all (the exact shape seen on the real corpus). This must degrade the same
    // way as an unresolvable-but-present Uuid, not abort the whole guide compile.
    let mut project = new_project("test");

    let mut op = Operation::new("test-op".to_string());
    let action = Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        gate: None,
        note: None,
        payload: ActionPayload::AcceptQuest(sentinel_models::authoring::AcceptQuestAction {
            quest: 1234,
            npc: None,
            auto_complete_dialog: false,
            optional: false,
        }),
    };
    let action_id = action.id;
    op.actions.push(action);
    project.operations.push(op);

    let (profile, report) = Compiler::compile(&project)
        .expect("missing NPC reference must not abort the whole guide compile");
    let RuntimeAction::Comment(c) = &profile.operations[0].actions[0].action else {
        panic!("expected missing NPC reference to lower to a Comment, got: {:?}", profile.operations[0].actions[0].action)
    };
    assert!(c.text.contains("unresolved NPC"), "got: {}", c.text);
    assert_eq!(report.unresolved, 1);
    assert!(
        report.unmapped_conditions.iter().any(|d| {
            d.code == "UNRESOLVED_NPC" && d.action.as_deref() == Some(&action_id.to_string())
        }),
        "got: {:?}", report.unmapped_conditions
    );
}

#[test]
fn recognized_condition_expression_lowers_to_typed_runtime_condition() {
    let mut project = new_project("test");
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(condition_action("QuestCompleted(1234)"));
    project.operations.push(op);

    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    let RuntimeAction::Condition(c) = &profile.operations[0].actions[0].action else { panic!("expected Condition") };
    assert_eq!(c.condition, RuntimeCondition::QuestCompleted(1234));
}

#[test]
fn condition_role_is_carried_through_to_the_runtime_action() {
    let mut project = new_project("test");
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(condition_action_with_role("QuestCompleted(1234)", ConditionRole::Completion));
    op.actions.push(condition_action_with_role("QuestAccepted(5624)", ConditionRole::Applicability));
    project.operations.push(op);

    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    let RuntimeAction::Condition(c0) = &profile.operations[0].actions[0].action else { panic!("expected Condition") };
    let RuntimeAction::Condition(c1) = &profile.operations[0].actions[1].action else { panic!("expected Condition") };
    assert_eq!(c0.role, ConditionRole::Completion);
    assert_eq!(c1.role, ConditionRole::Applicability);
}

#[test]
fn unmappable_condition_expression_records_diagnostic_and_fails_open() {
    let mut project = new_project("test");
    let mut op = Operation::new("test-op".to_string());
    let action = condition_action("NotARealPredicate(1)");
    let action_id = action.id;
    op.actions.push(action);
    project.operations.push(op);

    let (profile, report) = Compiler::compile(&project).expect("compile ok");
    // Fail-open (never a blanket compile failure), but only alongside a diagnostic — never silent.
    let RuntimeAction::Condition(c) = &profile.operations[0].actions[0].action else { panic!("expected Condition") };
    assert_eq!(c.condition, RuntimeCondition::AlwaysTrue);
    assert!(
        report.unmapped_conditions.iter().any(|d| {
            d.code == "UNMAPPED_CONDITION"
                && d.entity.as_deref() == Some("NotARealPredicate(1)")
                && d.action.as_deref() == Some(&action_id.to_string())
        }),
        "got: {:?}", report.unmapped_conditions
    );
}

// ---------------------------------------------------------------------------
// CL2 — LootObject entry resolution.
// ---------------------------------------------------------------------------

#[test]
fn resolvable_loot_object_gets_real_entry() {
    let mut project = new_project("test");
    let obj_id = Uuid::new_v4();
    project.object_library.push(GameObjectReference::new(
        4444,
        "Test Chest",
        Position { map: 0, world_x: 1.0, world_y: 2.0, world_z: 3.0, orientation: None },
        "Chest",
    ));
    project.object_library[0].id = obj_id;

    let mut op = Operation::new("test-op".to_string());
    op.actions.push(loot_action(obj_id));
    project.operations.push(op);

    let (profile, report) = Compiler::compile(&project).expect("compile ok");
    let RuntimeAction::Loot(l) = &profile.operations[0].actions[0].action else { panic!("expected Loot") };
    assert_eq!(l.object_entry, 4444);
    assert_eq!(report.unresolved, 0);
}

#[test]
fn unresolvable_loot_object_records_diagnostic_and_unresolved_count() {
    let mut project = new_project("test");
    let missing_id = Uuid::new_v4();

    let mut op = Operation::new("test-op".to_string());
    let action = loot_action(missing_id);
    let action_id = action.id;
    op.actions.push(action);
    project.operations.push(op);

    let (profile, report) = Compiler::compile(&project).expect("compile ok");
    let RuntimeAction::Loot(l) = &profile.operations[0].actions[0].action else { panic!("expected Loot") };
    assert_eq!(l.object_entry, 0, "unresolved object falls back to 0, never a guessed entry");
    assert_eq!(report.unresolved, 1);
    assert!(
        report.unmapped_conditions.iter().any(|d| {
            d.code == "UNRESOLVED_OBJECT" && d.action.as_deref() == Some(&action_id.to_string())
        }),
        "got: {:?}", report.unmapped_conditions
    );
}

// ---------------------------------------------------------------------------
// CL4 — class-restriction lowered to a per-action guard (RuntimeCondition).
// ---------------------------------------------------------------------------

fn project_with_class_restricted_vendor(class_restriction: Option<&str>) -> sentinel_models::authoring::Project {
    let npc_id = Uuid::new_v4();
    let npc = NPCReference {
        id: npc_id,
        entry: Some(555),
        guid: None,
        name: "Test Vendor".to_string(),
        faction: None,
        roles: vec![],
        position: None,
        source: None,
        notes: None,
    };
    let mut project = new_project("test");
    project.npc_library.push(npc);
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(vendor_action_with_class(npc_id, class_restriction));
    project.operations.push(op);
    project
}

#[test]
fn no_class_restriction_yields_no_guard() {
    let project = project_with_class_restricted_vendor(None);
    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    assert_eq!(profile.operations[0].actions[0].guard, None);
}

#[test]
fn single_class_restriction_lowers_to_class_is_guard() {
    let project = project_with_class_restricted_vendor(Some("Mage"));
    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    assert_eq!(
        profile.operations[0].actions[0].guard,
        Some(RuntimeCondition::ClassIs("Mage".to_string()))
    );
}

#[test]
fn multi_class_restriction_lowers_to_any_of_class_is_guards() {
    let project = project_with_class_restricted_vendor(Some("Warrior/Paladin"));
    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    assert_eq!(
        profile.operations[0].actions[0].guard,
        Some(RuntimeCondition::Any(vec![
            RuntimeCondition::ClassIs("Warrior".to_string()),
            RuntimeCondition::ClassIs("Paladin".to_string()),
        ]))
    );
}

#[test]
fn negated_single_class_restriction_lowers_to_not_class_is_guard() {
    let project = project_with_class_restricted_vendor(Some("!Rogue"));
    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    assert_eq!(
        profile.operations[0].actions[0].guard,
        Some(RuntimeCondition::Not(Box::new(RuntimeCondition::ClassIs("Rogue".to_string()))))
    );
}

#[test]
fn unknown_class_token_records_diagnostic_and_skips_guard() {
    let project = project_with_class_restricted_vendor(Some("NotAClass"));
    let (profile, report) = Compiler::compile(&project).expect("compile ok");
    assert_eq!(profile.operations[0].actions[0].guard, None);
    assert!(
        report.unmapped_conditions.iter().any(|d| d.code == "UNKNOWN_CLASS_RESTRICTION"),
        "got: {:?}", report.unmapped_conditions
    );
}
#[test]
fn level_at_least_condition_lowers_and_serializes_adjacently_tagged() {
    // `.xp N` importer emission: `LevelAtLeast(N)` must lower to the typed variant — not the
    // fail-open AlwaysTrue path — and hit the exact adjacently-tagged wire shape the Lua
    // runtime dispatches on ({type, payload}); externally-tagged shapes fell through silently.
    let mut project = new_project("test");
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(condition_action_with_role("LevelAtLeast(14)", ConditionRole::Completion));
    project.operations.push(op);

    let (profile, report) = Compiler::compile(&project).expect("compile ok");
    let guarded = &profile.operations[0].actions[0];
    let RuntimeAction::Condition(c) = &guarded.action else { panic!("expected Condition") };
    assert_eq!(c.condition, RuntimeCondition::LevelAtLeast(14));
    assert_eq!(c.role, ConditionRole::Completion);
    assert!(
        !report.unmapped_conditions.iter().any(|d| d.code == "UNMAPPED_CONDITION"),
        "LevelAtLeast must be a mapped predicate, got: {:?}", report.unmapped_conditions
    );

    // Pin the wire shape end-to-end (what the Lua runtime actually reads).
    let wire = serde_json::to_value(guarded).expect("serialize");
    assert_eq!(
        wire,
        serde_json::json!({
            "type": "Condition",
            "payload": {
                "condition": { "type": "LevelAtLeast", "payload": 14 },
                "role": "Completion"
            }
        })
    );
}
