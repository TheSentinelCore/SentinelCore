//! Integration tests for the Project Validator.

use sentinel_models::authoring::{Action, ActionPayload, NPCReference, Operation, Position, VendorAction};
use sentinel_models::authoring::new_project;
use sentinel_validator::Validator;
use uuid::Uuid;

fn make_op_with_action(action: Action) -> Operation {
    let mut op = sentinel_models::authoring::Operation::new("test".to_string());
    op.actions.push(action);
    op
}

#[test]
fn detects_duplicate_npc_entries() {
    let npc = NPCReference {
        id: Uuid::new_v4(),
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
    project.npc_library.push(npc.clone());
    project.npc_library.push(npc); // duplicate
    
    let diagnostics = Validator::validate(&project);
    assert!(diagnostics.iter().any(|d| d.code == "DUPLICATE_NPC"));
}

#[test]
fn detects_broken_npc_reference_in_vendor() {
    let action = Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        gate: None,
        note: None,
        payload: ActionPayload::Vendor(VendorAction {
            npc: Uuid::new_v4(), // non-existent NPC
            sell_grey: false,
            repair: false,
            buy_items: vec![],
            minimum_free_slots: None,
        }),
    };
    let mut project = new_project("test");
    // No NPCs in library
    project.operations.push(make_op_with_action(action));
    
    let diagnostics = Validator::validate(&project);
    assert!(diagnostics.iter().any(|d| d.code == "BROKEN_NPC_REFERENCE"));
}

#[test]
fn passes_valid_project() {
    let npc = NPCReference {
        id: Uuid::new_v4(),
        entry: Some(123),
        guid: None,
        name: "Test NPC".to_string(),
        faction: None,
        roles: vec![],
        position: Some(Position::new(1, -8345.0, 610.0, 94.0)),
        source: None,
        notes: None,
    };
    let npc_id = npc.id;
    let vendor_action = Action {
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
    };
    let mut project = new_project("test");
    project.npc_library.push(npc);
    project.operations.push(make_op_with_action(vendor_action));
    
    let diagnostics = Validator::validate(&project);
    assert!(
        diagnostics.is_empty(),
        "valid project should have no diagnostics, got: {:?}",
        diagnostics
    );
}