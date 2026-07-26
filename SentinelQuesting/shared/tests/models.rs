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
        gate: None,
        note: Some("imported from Human.lua:421".to_string()),
        payload: ActionPayload::Travel(TravelAction {
            destination: "Goldshire".into(),
            position: Some(Position::new(0, 1.0, 2.0, 3.0)),
            tolerance: 5.0,
            authored_radius: None,
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
        gate: None,
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
        gate: None,
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

// ===========================================================================
// RestedXP task graph — authoring carriers (RED).
// ===========================================================================

/// Model-level coverage for the task-graph carriers `authoring::Operation` must grow so the
/// importer can stop discarding `#requires` / `#completewith` / `#optional` / `#`-archetype
/// selectors and the full `<<` gate expression.
///
/// This module does not compile until `GuideGate`, `Gated<T>`, `CompleteWithTarget`,
/// `GuideDirective` and the seven new `Operation` fields exist. That compile failure is the
/// intended RED for Rust — the assertions below are shape claims, not guesses.
///
/// ## WHAT THESE TESTS CANNOT SEE
///
/// * **No importer, no corpus, no guide text.** Everything here is hand-constructed. A perfectly
///   shaped `Operation` proves nothing about whether the importer ever *populates* it — that is
///   `importer/tests/task_graph_directives.rs`'s job, and these two files can pass and fail
///   independently.
/// * **`GuideGate` is an opaque string here.** No test parses `AndGroup (WS AndGroup)*` /
///   `Term ('/' Term)*` / `'!'? Ident`, and no test evaluates a gate against an archetype. If the
///   grammar is implemented wrong, this file stays green.
/// * **Nothing is asserted about the compiler or the kernel.** `CompleteWithTarget` is checked
///   for adjacent tagging because the Lua kernel dispatches on `.type` (the `RuntimeCondition`
///   regression that made every non-unit condition fail open), but no Lua-side test is touched,
///   so a drift on the Lua side is still invisible from here. The lowering of `#optional` to
///   kernel `Task.blocking = false`, and of `#requires` to `Task.deps`, is not covered.
/// * **Round-trip equality is only as strong as `PartialEq`.** A field added to `Operation`
///   without being added to these fixtures round-trips silently and is never noticed.
/// * **Backward compatibility is tested one direction only** — old JSON (no task-graph fields)
///   into the new type. Nothing here proves an old *reader* survives new JSON.
mod task_graph {
    use sentinel_models::authoring::{
        new_project, CompleteWithTarget, Gated, GuideDirective, GuideGate, Operation,
    };

    /// `The Burning Crusade.lua:91092  #requires FlyMoongladeH << Horde`
    ///
    /// The unit that makes stacked directives work: value, its OWN gate, and the source line it
    /// came from. Sharing one gate across a step's entries destroys the distinction between
    /// TBC:24728-24729 (an AND of two ungated requirements) and TBC:91092-91093 (a
    /// faction-exclusive OR that resolves away at C2).
    #[test]
    fn gated_entry_carries_value_gate_and_source_line() {
        let g = Gated {
            value: "FlyMoongladeH".to_string(),
            gate: Some(GuideGate("Horde".to_string())),
            line: 91092,
        };
        assert_eq!(g.value, "FlyMoongladeH");
        assert_eq!(g.gate.as_ref().map(|x| x.0.as_str()), Some("Horde"));
        assert_eq!(g.line, 91092, "the source line is needed to place diagnostics on the guide");

        let json = serde_json::to_value(&g).unwrap();
        assert_eq!(json["value"], "FlyMoongladeH");
        assert_eq!(json["line"], 91092);
        let back: Gated<String> = serde_json::from_value(json).unwrap();
        assert_eq!(g, back, "a gated entry must round-trip unchanged");
    }

    /// `The Burning Crusade.lua:24728  #requires cloth1`
    ///
    /// An ungated entry must omit `gate` entirely on the wire — 3,038 of 3,067 `#optional` and
    /// the large majority of `#requires`/`#label` are ungated, so emitting `"gate": null` on all
    /// of them bloats every project file for nothing.
    #[test]
    fn ungated_entry_omits_the_gate_field_on_the_wire() {
        let g = Gated { value: "cloth1".to_string(), gate: None, line: 24728 };
        let json = serde_json::to_value(&g).unwrap();
        assert!(
            json.get("gate").is_none(),
            "an ungated entry must not serialize a `gate` key at all; got {json}"
        );
        let back: Gated<String> = serde_json::from_value(json).unwrap();
        assert_eq!(g, back);
    }

    /// `A-1-11-Dwarf-Gnome.lua:407  #requires TroggEnd << !Paladin !Warlock !Hunter`
    /// `A-23-30.lua:380             step << Dwarf Paladin`
    /// `The Burning Crusade.lua:4875 step << !tbc !wotlk`
    /// `A-1-11-Human.lua:938        #optional << Warrior/Rogue/Paladin`
    ///
    /// `GuideGate` is a verbatim carrier, not a parsed class list. Measured vocabulary: 10
    /// classes plus `DK`(178)/`Pala`(2), ten races, `Alliance`(809)/`Horde`(953),
    /// `tbc`(241)/`wotlk`(121)/`classic`(4)/`era`(14)/`sod`, a level bound `!70`, and the `skip`
    /// sentinel(139). The compiler's 10-entry `KNOWN_CLASSES` covers a minority of that, which is
    /// why the raw expression has to survive intact this far.
    #[test]
    fn guide_gate_holds_the_whole_tail_verbatim_without_parsing_it() {
        for tail in [
            "!Paladin !Warlock !Hunter", // DG:407 — whitespace AND over negated classes
            "Dwarf Paladin",             // A-23-30:380 — race AND class
            "!tbc !wotlk",               // TBC:4875 — era
            "Warrior/Rogue/Paladin",     // A-1-11-Human:938 — `/` OR-group
            "Horde",                     // TBC:85496 — faction
            "!Human",                    // A-1-11-Human:14 — negated race
            "tbc/wotlk",                 // TBC:35668 — era OR-group
            "skip Horde",                // TBC:86156 — disable sentinel plus its absorbed tail
        ] {
            let g = GuideGate(tail.to_string());
            assert_eq!(g.0, tail, "GuideGate stores the tail byte-for-byte");
            let json = serde_json::to_value(&g).unwrap();
            let back: GuideGate = serde_json::from_value(json).unwrap();
            assert_eq!(g, back, "gate `{tail}` must round-trip unchanged");
        }
    }

    /// `The Burning Crusade.lua:4066   #completewith next << !Druid`   (reserved literal)
    /// `The Burning Crusade.lua:4065   #completewith BetterIngredientTI << Druid` (label)
    /// `The Burning Crusade.lua:11260  #completewith end`              (label — `end` is real)
    ///
    /// Adjacent tagging is a hard repo rule, not a style choice: `RuntimeCondition` was once
    /// externally tagged and every non-unit condition fell through to fail-open `true` in the Lua
    /// runtime. Anything that may cross into the profile dispatches on `.type`.
    #[test]
    fn complete_with_target_is_adjacently_tagged() {
        let next = serde_json::to_value(CompleteWithTarget::Next).unwrap();
        assert_eq!(next["type"], "Next", "TBC:4066 — the reserved literal, 2,681 uses");
        assert!(
            next.get("payload").is_none(),
            "a unit variant carries no payload; got {next}"
        );

        let label = serde_json::to_value(CompleteWithTarget::Label("Un'Goro End".to_string())).unwrap();
        assert_eq!(label["type"], "Label");
        assert_eq!(
            label["payload"], "Un'Goro End",
            "TBC:103798 — internal whitespace and apostrophe survive the wire"
        );

        let back: CompleteWithTarget = serde_json::from_value(label).unwrap();
        assert_eq!(back, CompleteWithTarget::Label("Un'Goro End".to_string()));

        assert_ne!(
            CompleteWithTarget::Next,
            CompleteWithTarget::Label("next".to_string()),
            "`next` is a distinct variant, never a label named \"next\" — it is never used as a \
             `#label` anywhere in the corpus, so the namespaces do not collide"
        );
    }

    /// A fresh `Operation` carries no task graph. Every new field must be inert by default so the
    /// editor's hand-authored operations are unaffected.
    #[test]
    fn new_operation_defaults_to_an_empty_task_graph() {
        let op = Operation::new("Northshire");
        assert!(op.labels.is_empty());
        assert!(op.requires.is_empty());
        assert!(op.complete_with.is_empty());
        assert_eq!(op.optional, None);
        assert_eq!(op.gate, None);
        assert!(op.directives.is_empty());
        assert!(!op.placeholder);
        assert!(op.enabled, "unchanged existing default");
    }

    /// Every project JSON already on disk predates these fields. Loading one must not fail.
    #[test]
    fn operation_json_without_task_graph_fields_still_deserializes() {
        let legacy = serde_json::json!({
            "id": "6f1e2a3c-0000-4000-8000-000000000001",
            "name": "Northshire",
            "enabled": true,
            "conditions": [],
            "sticky": false,
            "looping": false,
            "actions": []
        });
        let op: Operation =
            serde_json::from_value(legacy).expect("pre-task-graph operation JSON must still load");
        assert!(op.labels.is_empty());
        assert!(op.requires.is_empty());
        assert!(op.complete_with.is_empty());
        assert_eq!(op.optional, None);
        assert_eq!(op.gate, None);
        assert!(op.directives.is_empty());
        assert!(!op.placeholder);
    }

    /// A fully populated task graph must survive the project round-trip the editor performs on
    /// every save. Fixture assembled from `The Burning Crusade.lua:91090-91096` plus
    /// `:24728-24729`, `:4065-4066`, `:2729`, `A-23-30.lua:433` and `A-1-11-Human.lua:3103`.
    #[test]
    fn project_with_a_populated_task_graph_roundtrips_unchanged() {
        let mut p = new_project("Timbermaw");
        let mut op = Operation::new("label:TimbermawTurnin");

        op.gate = Some(GuideGate("Mage/Priest/Warlock".to_string()));
        op.labels.push(Gated {
            value: "TimbermawTurnin".to_string(),
            gate: None,
            line: 91098,
        });
        // TBC:91092-91093 — the faction-exclusive OR: two entries, two gates.
        op.requires.push(Gated {
            value: "FlyMoongladeH".to_string(),
            gate: Some(GuideGate("Horde".to_string())),
            line: 91100,
        });
        op.requires.push(Gated {
            value: "FlyMoongladeA".to_string(),
            gate: Some(GuideGate("Alliance".to_string())),
            line: 91101,
        });
        // TBC:4065-4066 — a label target and the reserved literal on one step.
        op.complete_with.push(Gated {
            value: CompleteWithTarget::Label("TimbermawEndOne".to_string()),
            gate: Some(GuideGate("Druid".to_string())),
            line: 91099,
        });
        op.complete_with.push(Gated {
            value: CompleteWithTarget::Next,
            gate: Some(GuideGate("!Druid".to_string())),
            line: 4066,
        });
        // A-23-30:433 — a gated `#optional`.
        op.optional = Some(Gated {
            value: (),
            gate: Some(GuideGate("Dwarf Paladin".to_string())),
            line: 433,
        });
        // TBC:2729 — an archetype selector with a value.
        op.directives.push(GuideDirective {
            name: "phase".to_string(),
            value: Some("4-6".to_string()),
            gate: None,
            line: 2729,
        });
        op.placeholder = false;
        p.operations.push(op);

        let json = serde_json::to_string_pretty(&p).expect("serialize project");
        let back: sentinel_models::authoring::Project =
            serde_json::from_str(&json).expect("deserialize project");
        assert_eq!(p, back, "the task graph must round-trip unchanged");
    }
}
