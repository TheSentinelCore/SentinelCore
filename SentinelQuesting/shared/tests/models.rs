//! Phase 1 acceptance tests (ADR `04_IMPLEMENTATION_PLAN` Phase 1):
//! JSON serialization round-trips, UUID generation, and schema defaults.

use sentinel_models::authoring::{
    new_project, AcceptQuestAction, Action, ActionPayload, CoordinateMode, Operation, Position,
    TravelAction, Variable, VariableType, VariableValue,
};
use sentinel_models::runtime::{
    RuntimeAcceptQuest, RuntimeAction, RuntimeNpc, RuntimeOperation, RuntimeProfile, RuntimeTravel,
    RuntimeVariable, RuntimeWaypoint,
};
use uuid::Uuid;

#[test]
fn project_json_roundtrip_is_stable() {
    let mut p = new_project("Test Human 1-5");
    p.metadata.faction = Some(sentinel_models::authoring::Faction::Alliance);

    let mut op = Operation::new("Northshire");
    op.actions.push(Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        note: Some("imported from Human.lua:421".to_string()),
        payload: ActionPayload::Travel(TravelAction {
            destination: "Goldshire".into(),
            position: Some(Position::new(0, 1.0, 2.0, 3.0)),
            tolerance: 5.0,
            mount: None,
            allow_flight: false,
            timeout: Some(300),
        }),
    });
    op.actions.push(Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        note: None,
        payload: ActionPayload::AcceptQuest(AcceptQuestAction {
            quest: 54,
            npc: None,
            auto_complete_dialog: false,
            optional: false,
        }),
    });
    p.operations.push(op);
    p.variables.push(Variable::new(
        "did_goldshire",
        VariableType::Bool,
        VariableValue::Bool(false),
    ));

    let json = serde_json::to_string_pretty(&p).expect("serialize project");
    let back: sentinel_models::authoring::Project =
        serde_json::from_str(&json).expect("deserialize project");
    assert_eq!(p, back, "project must round-trip unchanged");
}

#[test]
fn runtime_json_roundtrip_is_stable() {
    let op = RuntimeOperation::new(
        Uuid::new_v4(),
        "Northshire",
        vec![
            RuntimeAction::Travel(RuntimeTravel {
                destination: "Goldshire".into(),
                position: RuntimeWaypoint::new(0, 1.0, 2.0, 3.0),
                tolerance: 5.0,
                allow_flight: false,
                timeout: Some(300),
            }),
            RuntimeAction::AcceptQuest(RuntimeAcceptQuest {
                quest_id: 54,
                npc_entry: 197,
                auto_complete_dialog: false,
                optional: false,
            }),
        ],
    );

    let mut prof = RuntimeProfile::new("Test", vec![op]);
    prof.npcs.push(RuntimeNpc::new(
        197,
        "Marshal Dughan",
        Position::new(0, 1.0, 2.0, 3.0),
    ));
    prof.variables.push(RuntimeVariable::new(
        "did_goldshire",
        VariableType::Bool,
        VariableValue::Bool(false),
    ));

    let json = serde_json::to_string(&prof).expect("serialize runtime");
    let back: RuntimeProfile = serde_json::from_str(&json).expect("deserialize runtime");
    assert_eq!(prof, back, "runtime profile must round-trip unchanged");
    assert_eq!(prof.total_actions(), 2);
}

#[test]
fn new_project_has_unique_id_and_sane_defaults() {
    let a = new_project("A");
    let b = new_project("B");
    assert_ne!(
        a.metadata.id, b.metadata.id,
        "each project gets a unique id"
    );
    assert!(!a.metadata.id.is_nil());
    assert_eq!(a.metadata.game_version, "2.4.3");
    assert_eq!(a.settings.coordinate_mode, CoordinateMode::World);
    assert_eq!(a.metadata.schema_version, "1.0.0");
}

#[test]
fn action_payload_is_adjacently_tagged() {
    let action = Action {
        id: Uuid::new_v4(),
        enabled: true,
        condition: None,
        class_restriction: None,
        note: None,
        payload: ActionPayload::Comment(sentinel_models::authoring::CommentAction {
            text: "hi".into(),
        }),
    };
    let json = serde_json::to_value(&action).unwrap();
    // ADR 02 §12: { "type": "Comment", "payload": { "text": "hi" } }
    assert_eq!(json["payload"]["text"], "hi");
    assert_eq!(json["type"], "Comment");
}
