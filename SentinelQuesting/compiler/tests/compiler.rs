//! Integration tests for the Compiler.

use sentinel_compiler::Compiler;
use sentinel_models::authoring::{
    Action, ActionPayload, ConditionAction, NPCReference, Operation, VendorAction,
};
use sentinel_models::authoring::new_project;
use sentinel_models::runtime::{RuntimeAction, RuntimeCondition};
use uuid::Uuid;

fn condition_action(expression: &str) -> Action {
    Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        note: None,
        payload: ActionPayload::Condition(ConditionAction { expression: expression.to_string() }),
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
fn fails_on_unresolved_npc_reference() {
    let mut project = new_project("test");
    
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        note: None,
        payload: ActionPayload::Vendor(VendorAction {
            npc: Uuid::new_v4(), // Non-existent NPC
            sell_grey: false,
            repair: false,
            buy_items: vec![],
            minimum_free_slots: None,
        }),
    });
    project.operations.push(op);
    
    let result = Compiler::compile(&project);
    assert!(result.is_err(), "unresolved NPC should cause compile error");
}

#[test]
fn recognized_condition_expression_lowers_to_typed_runtime_condition() {
    let mut project = new_project("test");
    let mut op = Operation::new("test-op".to_string());
    op.actions.push(condition_action("QuestCompleted(1234)"));
    project.operations.push(op);

    let (profile, _report) = Compiler::compile(&project).expect("compile ok");
    let RuntimeAction::Condition(c) = &profile.operations[0].actions[0] else { panic!("expected Condition") };
    assert_eq!(c.condition, RuntimeCondition::QuestCompleted(1234));
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
    let RuntimeAction::Condition(c) = &profile.operations[0].actions[0] else { panic!("expected Condition") };
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