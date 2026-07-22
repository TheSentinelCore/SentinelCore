//! Integration tests for the Compiler.

use sentinel_compiler::Compiler;
use sentinel_models::authoring::{Action, ActionPayload, NPCReference, Operation, VendorAction};
use sentinel_models::authoring::new_project;
use uuid::Uuid;

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
    
    let profile = Compiler::compile(&project).expect("compile ok");
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