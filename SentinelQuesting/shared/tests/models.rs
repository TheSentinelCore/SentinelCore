//! Phase 1 acceptance tests (ADR `04_IMPLEMENTATION_PLAN` Phase 1):
//! JSON serialization round-trips, UUID generation, and schema defaults.

use sentinel_models::authoring::{
    new_project, AcceptQuestAction, Action, ActionPayload, CoordinateMode, Operation, Position,
    TravelAction, Variable, VariableType, VariableValue,
};
use sentinel_models::runtime::{
    GuardedAction, RuntimeAcceptQuest, RuntimeAction, RuntimeCondition, RuntimeNpc, RuntimeOperation,
    RuntimeProfile, RuntimeTravel, RuntimeVariable, RuntimeWaypoint,
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

// ---------------------------------------------------------------------------
// CL4 — GuardedAction: {type,payload,guard} additive, backward-compatible shape.
// ---------------------------------------------------------------------------

#[test]
fn guardless_action_serializes_without_guard_field_and_deserializes() {
    let ga: GuardedAction = RuntimeAction::Comment(sentinel_models::runtime::RuntimeComment {
        text: "hi".into(),
    })
    .into();
    let json = serde_json::to_value(&ga).unwrap();
    assert_eq!(json["type"], "Comment");
    assert_eq!(json["payload"]["text"], "hi");
    assert!(json.get("guard").is_none(), "guard-less action must omit the guard field entirely");

    let back: GuardedAction = serde_json::from_value(json).expect("guard-less action must deserialize");
    assert_eq!(ga, back);
}

#[test]
fn guarded_action_roundtrips_type_payload_guard_as_siblings() {
    let ga = GuardedAction {
        action: RuntimeAction::Comment(sentinel_models::runtime::RuntimeComment {
            text: "hi".into(),
        }),
        guard: Some(RuntimeCondition::ClassIs("Mage".to_string())),
    };
    let json = serde_json::to_value(&ga).unwrap();
    assert_eq!(json["type"], "Comment");
    assert_eq!(json["payload"]["text"], "hi");
    // RuntimeCondition is adjacently tagged (matches the Lua evaluate_condition contract):
    // { "type": "ClassIs", "payload": "Mage" } — NOT externally tagged { "ClassIs": "Mage" }.
    assert_eq!(json["guard"]["type"], "ClassIs");
    assert_eq!(json["guard"]["payload"], "Mage");

    let back: GuardedAction = serde_json::from_value(json).expect("guarded action must deserialize losslessly");
    assert_eq!(ga, back);
}

// Pin the exact wire shape the Lua runtime_action.lua condition handlers consume: newtype ->
// scalar payload, tuple -> array payload, Not/Any -> nested condition object(s). If this shape
// drifts, class filtering and §23 condition gating silently fail open in-game.
#[test]
fn runtime_condition_wire_shape_matches_lua_type_payload_contract() {
    let simple = serde_json::to_value(RuntimeCondition::ClassIs("Mage".into())).unwrap();
    assert_eq!(simple["type"], "ClassIs");
    assert_eq!(simple["payload"], "Mage");

    let tuple = serde_json::to_value(RuntimeCondition::ObjectiveComplete(1234, 2)).unwrap();
    assert_eq!(tuple["type"], "ObjectiveComplete");
    assert_eq!(tuple["payload"][0], 1234);
    assert_eq!(tuple["payload"][1], 2);

    let nested = serde_json::to_value(RuntimeCondition::Not(Box::new(RuntimeCondition::Any(vec![
        RuntimeCondition::ClassIs("Warrior".into()),
        RuntimeCondition::ClassIs("Paladin".into()),
    ]))))
    .unwrap();
    assert_eq!(nested["type"], "Not");
    assert_eq!(nested["payload"]["type"], "Any");
    assert_eq!(nested["payload"]["payload"][0]["type"], "ClassIs");
    assert_eq!(nested["payload"]["payload"][0]["payload"], "Warrior");

    // Round-trip fidelity through the tagged form.
    let back: RuntimeCondition = serde_json::from_value(nested).unwrap();
    assert_eq!(
        back,
        RuntimeCondition::Not(Box::new(RuntimeCondition::Any(vec![
            RuntimeCondition::ClassIs("Warrior".into()),
            RuntimeCondition::ClassIs("Paladin".into()),
        ])))
    );
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
