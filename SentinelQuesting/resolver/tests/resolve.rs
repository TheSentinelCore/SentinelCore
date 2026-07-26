//! The W2 acceptance surface (ADR 09a §2 W2): purity, linear lowering, import overrides,
//! unresolvable references, and task-set coverage.
//!
//! These are integration tests on purpose — they exercise only the crate's public API, which is
//! what QueryServer (W6), the CLI, and CI will call.

use sentinel_models::platform::{
    Campaign, CampaignImport, Edge, EntityKind, EntityRef, ExecutionPlan, Graph, Intent,
    IntentValue, Node, NodeOverride,
};
use sentinel_models::runtime::RuntimeAction;
use sentinel_resolver::{
    resolve, questing_task_types, Diagnostic, InMemoryDb, Resolver, ResolverDb, Severity, Spawn,
    TaskRegistry,
};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn id(n: u128) -> Uuid {
    Uuid::from_u128(n)
}

/// A database that knows every entity the fixtures below point at.
fn db() -> InMemoryDb {
    InMemoryDb::new("tbcmangos@a1b2c3")
        .with_spawn(EntityKind::Npc, 823, Spawn::new(0, -8933.5, -136.5, 83.25))
        .with_label(EntityKind::Npc, 823, "Deputy Willem")
        .with_spawn(EntityKind::Npc, 299, Spawn::new(0, -9000.0, -200.0, 70.5))
        .with_label(EntityKind::Npc, 299, "Kobold Vermin")
        .with_spawn(EntityKind::Npc, 1247, Spawn::new(0, -8900.0, -100.0, 80.0))
        .with_label(EntityKind::Npc, 1247, "Innkeeper Farley")
        .with_spawn(EntityKind::Object, 1617, Spawn::new(0, -8950.0, -150.0, 82.0))
        .with_label(EntityKind::Object, 1617, "Chest")
        .with_label(EntityKind::Quest, 783, "Kobold Camp Cleanup")
        .with_quest_giver(783, 823)
        .with_quest_ender(783, 823)
}

fn entity(kind: EntityKind, entity_id: u32, label: &str) -> IntentValue {
    IntentValue::Entity(EntityRef::new(kind, entity_id, label))
}

fn accept_quest_node(node_id: u128) -> Node {
    let mut intent = Intent::new();
    intent.insert("quest", entity(EntityKind::Quest, 783, "Kobold Camp Cleanup"));
    intent.insert("from", entity(EntityKind::Npc, 823, "Deputy Willem"));
    Node {
        id: id(node_id),
        node_type: "questing.AcceptQuest".to_string(),
        intent,
        resolved: None,
        context: None,
    }
}

fn kill_node(node_id: u128, count: i64) -> Node {
    let mut intent = Intent::new();
    intent.insert("target", entity(EntityKind::Npc, 299, "Kobold Vermin"));
    intent.insert("count", count);
    Node {
        id: id(node_id),
        node_type: "questing.Kill".to_string(),
        intent,
        resolved: None,
        context: None,
    }
}

fn turn_in_node(node_id: u128) -> Node {
    let mut intent = Intent::new();
    intent.insert("quest", entity(EntityKind::Quest, 783, "Kobold Camp Cleanup"));
    intent.insert("to", entity(EntityKind::Npc, 823, "Deputy Willem"));
    Node {
        id: id(node_id),
        node_type: "questing.TurnIn".to_string(),
        intent,
        resolved: None,
        context: None,
    }
}

/// Accept → Kill → TurnIn, wired as the linear route ADR 09a §1.3 calls the degenerate graph.
fn linear_campaign() -> Campaign {
    let nodes = vec![accept_quest_node(1), kill_node(2, 8), turn_in_node(3)];
    let edges = vec![
        Edge {
            id: id(101),
            from: id(1),
            to: id(2),
            guard: None,
        },
        Edge {
            id: id(102),
            from: id(2),
            to: id(3),
            guard: None,
        },
    ];
    let mut campaign = Campaign::new("Human 1-60");
    campaign.id = id(1000);
    campaign.graphs.push(Graph {
        id: id(500),
        name: "Elwynn Forest".to_string(),
        entry_node: id(1),
        nodes,
        edges,
    });
    campaign
}

fn action_types(plan: &ExecutionPlan, operation: usize) -> Vec<String> {
    plan.operations[operation]
        .actions
        .iter()
        .map(|guarded| match &guarded.action {
            RuntimeAction::Travel(_) => "Travel",
            RuntimeAction::AcceptQuest(_) => "AcceptQuest",
            RuntimeAction::TurnInQuest(_) => "TurnInQuest",
            RuntimeAction::Vendor(_) => "Vendor",
            RuntimeAction::Train(_) => "Train",
            RuntimeAction::Kill(_) => "Kill",
            RuntimeAction::Loot(_) => "Loot",
            RuntimeAction::Flight(_) => "Flight",
            RuntimeAction::Hearth(_) => "Hearth",
            RuntimeAction::Condition(_) => "Condition",
            _ => "other",
        })
        .map(str::to_string)
        .collect()
}

fn errors(diagnostics: &[Diagnostic]) -> Vec<&Diagnostic> {
    diagnostics
        .iter()
        .filter(|d| d.severity == Severity::Error)
        .collect()
}

// ---------------------------------------------------------------------------
// Purity
// ---------------------------------------------------------------------------

/// The defining property of the crate (ADR 09 §5): same intent + same `db_fingerprint` ⇒
/// byte-identical output. Anything non-deterministic — a clock read, a random hash seed, a
/// `HashMap` iteration order — breaks re-resolution diffing, and breaks it silently.
#[test]
fn resolving_the_same_campaign_twice_is_byte_identical() {
    let campaign = linear_campaign();
    let db = db();

    let (first, first_diagnostics) = resolve(&campaign, &db);
    let (second, second_diagnostics) = resolve(&campaign, &db);

    assert_eq!(
        serde_json::to_string(&first).unwrap(),
        serde_json::to_string(&second).unwrap(),
        "two resolves of one campaign must serialize identically"
    );
    assert_eq!(first.content_hash, second.content_hash);
    assert!(!first.content_hash.is_empty());
    assert_eq!(
        serde_json::to_string(&first_diagnostics).unwrap(),
        serde_json::to_string(&second_diagnostics).unwrap(),
    );
}

/// A campaign large enough that an unordered container would show up. Insertion order here is
/// deliberately scrambled relative to graph order.
#[test]
fn a_branching_campaign_orders_operations_deterministically() {
    let mut campaign = linear_campaign();
    let graph = &mut campaign.graphs[0];
    graph.nodes.push(kill_node(4, 3));
    graph.nodes.push(kill_node(5, 4));
    graph.edges.push(Edge {
        id: id(103),
        from: id(1),
        to: id(4),
        guard: None,
    });
    graph.edges.push(Edge {
        id: id(104),
        from: id(4),
        to: id(5),
        guard: None,
    });
    graph.edges.push(Edge {
        id: id(105),
        from: id(5),
        to: id(3),
        guard: None,
    });

    let db = db();
    let first = serde_json::to_string(&resolve(&campaign, &db).0).unwrap();
    for _ in 0..8 {
        assert_eq!(
            first,
            serde_json::to_string(&resolve(&campaign, &db).0).unwrap()
        );
    }
}

// ---------------------------------------------------------------------------
// Linear lowering
// ---------------------------------------------------------------------------

#[test]
fn a_linear_three_node_campaign_lowers_to_three_sequential_operations() {
    let campaign = linear_campaign();
    let (plan, diagnostics) = resolve(&campaign, &db());

    assert!(errors(&diagnostics).is_empty(), "{diagnostics:#?}");
    assert_eq!(plan.schema_version, 3);
    assert_eq!(plan.campaign_id, id(1000));
    assert_eq!(plan.graph_id, id(500));
    assert_eq!(plan.db_fingerprint, "tbcmangos@a1b2c3");
    assert_eq!(plan.operations.len(), 3);

    assert_eq!(plan.operations[0].node_id, id(1));
    assert_eq!(plan.operations[1].node_id, id(2));
    assert_eq!(plan.operations[2].node_id, id(3));

    assert_eq!(plan.operations[0].next.len(), 1);
    assert_eq!(plan.operations[0].next[0].to_index, 1);
    assert!(plan.operations[0].next[0].guard.is_none());
    assert_eq!(plan.operations[1].next[0].to_index, 2);
    assert!(
        plan.operations[2].next.is_empty(),
        "the terminal operation has no successor"
    );
    assert!(plan.operations[0].is_sequential_advance());

    assert_eq!(action_types(&plan, 0), vec!["Travel", "AcceptQuest"]);
    assert_eq!(action_types(&plan, 1), vec!["Travel", "Kill"]);
    assert_eq!(action_types(&plan, 2), vec!["Travel", "TurnInQuest"]);
}

/// The waypoint is the whole reason W3 exists: guide text never carried `world_z`, so every
/// imported Travel landed at `world_z = 0`. A resolved Travel must carry the spawn's real height.
#[test]
fn a_lowered_travel_carries_the_spawn_position_including_z() {
    let (plan, _) = resolve(&linear_campaign(), &db());
    let RuntimeAction::Travel(travel) = &plan.operations[0].actions[0].action else {
        panic!("first action must be Travel: {:?}", plan.operations[0]);
    };
    assert_eq!(travel.position.map, 0);
    assert_eq!(travel.position.world_x, -8933.5);
    assert_eq!(travel.position.world_y, -136.5);
    assert_eq!(travel.position.world_z, 83.25);
    assert_eq!(travel.destination, "Deputy Willem");
}

/// `label` is a cache, never authoritative (ADR 09a §1.2) — a stale one must not survive a
/// resolve that had the real name available.
#[test]
fn a_stale_intent_label_is_refreshed_from_the_database() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].nodes[0]
        .intent
        .insert("from", entity(EntityKind::Npc, 823, "Deputy Willem (old)"));

    let (plan, _) = resolve(&campaign, &db());
    let RuntimeAction::Travel(travel) = &plan.operations[0].actions[0].action else {
        panic!("first action must be Travel");
    };
    assert_eq!(travel.destination, "Deputy Willem");
}

// ---------------------------------------------------------------------------
// Imports and overrides
// ---------------------------------------------------------------------------

#[test]
fn an_import_override_applies_without_mutating_the_source() {
    let base = linear_campaign();
    let pristine = base.clone();

    let mut patch = Intent::new();
    patch.insert("count", 3i64);
    let mut importer = Campaign::new("Human 1-60 (my edits)");
    importer.id = id(2000);
    importer.imports.push(CampaignImport {
        campaign: base.id,
        overrides: vec![NodeOverride {
            node: id(2),
            intent: patch,
        }],
        disabled_nodes: vec![],
    });

    let library = vec![base];
    let resolver = Resolver::new(TaskRegistry::with_questing(), &library);
    let (plan, diagnostics) = resolver.resolve(&importer, &db());

    assert!(errors(&diagnostics).is_empty(), "{diagnostics:#?}");
    assert_eq!(plan.operations.len(), 3);
    let RuntimeAction::Kill(kill) = &plan.operations[1].actions[1].action else {
        panic!("second operation must lower to Kill: {:?}", plan.operations[1]);
    };
    assert_eq!(kill.quantity, Some(3), "the override must win");
    assert_eq!(kill.creature_entries, vec![299], "unpatched fields survive");

    assert_eq!(
        library[0], pristine,
        "an override must never rewrite the imported campaign"
    );
    let (base_plan, _) = resolve(&library[0], &db());
    let RuntimeAction::Kill(base_kill) = &base_plan.operations[1].actions[1].action else {
        panic!("base second operation must lower to Kill");
    };
    assert_eq!(base_kill.quantity, Some(8), "the source still resolves to 8");
}

/// Disabling a node in an imported guide is how an author skips a quest they already did. The
/// route must stay connected — a hole in the middle of a linear route would strand the runtime on
/// the operation before it.
#[test]
fn a_disabled_imported_node_is_spliced_out_not_left_as_a_hole() {
    let base = linear_campaign();
    let mut importer = Campaign::new("skip the kill");
    importer.id = id(2001);
    importer.imports.push(CampaignImport {
        campaign: base.id,
        overrides: vec![],
        disabled_nodes: vec![id(2)],
    });

    let library = vec![base];
    let resolver = Resolver::new(TaskRegistry::with_questing(), &library);
    let (plan, diagnostics) = resolver.resolve(&importer, &db());

    assert!(errors(&diagnostics).is_empty(), "{diagnostics:#?}");
    assert_eq!(plan.operations.len(), 2);
    assert_eq!(plan.operations[0].node_id, id(1));
    assert_eq!(plan.operations[1].node_id, id(3));
    assert_eq!(
        plan.operations[0].next[0].to_index, 1,
        "the predecessor must advance to the disabled node's successor"
    );
}

#[test]
fn an_import_of_an_unknown_campaign_is_a_diagnostic_not_a_panic() {
    let mut importer = Campaign::new("dangling import");
    importer.id = id(2002);
    importer.imports.push(CampaignImport {
        campaign: id(9999),
        overrides: vec![],
        disabled_nodes: vec![],
    });

    let (_, diagnostics) = resolve(&importer, &db());
    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.import.unknown_campaign"),
        "{diagnostics:#?}"
    );
}

// ---------------------------------------------------------------------------
// Unresolvable references
// ---------------------------------------------------------------------------

#[test]
fn an_unresolvable_entity_ref_produces_a_diagnostic_rather_than_a_panic() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].nodes[0]
        .intent
        .insert("from", entity(EntityKind::Npc, 99999, "Nobody"));

    let (plan, diagnostics) = resolve(&campaign, &db());

    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.spawn.unknown" && d.node_id == Some(id(1))),
        "{diagnostics:#?}"
    );
    assert_eq!(
        plan.operations.len(),
        3,
        "an unresolvable reference must never drop the node"
    );
    assert_eq!(
        action_types(&plan, 0),
        vec!["AcceptQuest"],
        "the Travel is dropped, the interaction is not"
    );
}

/// A quest with neither an authored giver nor a database relation cannot lower at all. The
/// operation must still exist, empty, with an Error — emitting `npc_entry: 0` would be a plan the
/// runtime happily executes against nothing.
#[test]
fn a_quest_with_no_resolvable_giver_yields_an_empty_operation_and_an_error() {
    let mut campaign = linear_campaign();
    let mut intent = Intent::new();
    intent.insert("quest", entity(EntityKind::Quest, 4242, "Unknown Quest"));
    campaign.graphs[0].nodes[0].intent = intent;

    let (plan, diagnostics) = resolve(&campaign, &db());

    assert_eq!(plan.operations.len(), 3);
    assert!(plan.operations[0].actions.is_empty());
    assert!(
        errors(&diagnostics)
            .iter()
            .any(|d| d.code == "resolver.quest.no_giver"),
        "{diagnostics:#?}"
    );
}

#[test]
fn an_unknown_task_type_is_a_diagnostic_and_still_emits_its_operation() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].nodes[1].node_type = "crafting.SmeltOre".to_string();

    let (plan, diagnostics) = resolve(&campaign, &db());

    assert_eq!(plan.operations.len(), 3, "the node must not disappear");
    assert!(plan.operations[1].actions.is_empty());
    assert!(
        errors(&diagnostics)
            .iter()
            .any(|d| d.code == "resolver.task.unknown"),
        "{diagnostics:#?}"
    );
}

#[test]
fn a_missing_required_field_is_a_diagnostic_from_the_schema_not_from_lowering() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].nodes[1].intent = Intent::new();

    let (_, diagnostics) = resolve(&campaign, &db());
    let missing = diagnostics
        .iter()
        .find(|d| d.code == "resolver.field.missing")
        .unwrap_or_else(|| panic!("{diagnostics:#?}"));
    assert_eq!(missing.severity, Severity::Error);
    assert_eq!(missing.field.as_deref(), Some("target"));
    assert_eq!(missing.node_id, Some(id(2)));
}

#[test]
fn a_field_of_the_wrong_kind_is_a_diagnostic() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].nodes[1]
        .intent
        .insert("target", "Kobold Vermin");

    let (_, diagnostics) = resolve(&campaign, &db());
    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.field.kind" && d.field.as_deref() == Some("target")),
        "{diagnostics:#?}"
    );
}

#[test]
fn an_entity_field_pointing_at_the_wrong_kind_is_a_diagnostic() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].nodes[1]
        .intent
        .insert("target", entity(EntityKind::Item, 2589, "Linen Cloth"));

    let (_, diagnostics) = resolve(&campaign, &db());
    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.field.entity_kind"),
        "{diagnostics:#?}"
    );
}

#[test]
fn a_dangling_edge_guard_is_a_diagnostic() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].edges[0].guard = Some(id(7777));

    let (plan, diagnostics) = resolve(&campaign, &db());
    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.guard.unknown_condition"),
        "{diagnostics:#?}"
    );
    assert_eq!(
        plan.operations[0].next[0].guard,
        Some(id(7777)),
        "the transition stays visible in the plan so the break is inspectable"
    );
}

/// A cycle is legal (a repeatable loop) but has no topological order. Every node must still make
/// it into the plan.
#[test]
fn a_cyclic_graph_keeps_every_node_and_warns() {
    let mut campaign = linear_campaign();
    campaign.graphs[0].edges.push(Edge {
        id: id(199),
        from: id(3),
        to: id(1),
        guard: None,
    });

    let (plan, diagnostics) = resolve(&campaign, &db());
    assert_eq!(plan.operations.len(), 3);
    assert!(
        diagnostics.iter().any(|d| d.code == "resolver.graph.cycle"),
        "{diagnostics:#?}"
    );
}

#[test]
fn a_campaign_with_no_graph_yields_an_empty_plan_and_an_error() {
    let mut campaign = Campaign::new("empty");
    campaign.id = id(2003);
    let (plan, diagnostics) = resolve(&campaign, &db());
    assert!(plan.operations.is_empty());
    assert!(
        errors(&diagnostics)
            .iter()
            .any(|d| d.code == "resolver.campaign.no_graph"),
        "{diagnostics:#?}"
    );
}

// ---------------------------------------------------------------------------
// Task set coverage
// ---------------------------------------------------------------------------

/// The questing set registered as a plugin (ADR 09 §4). Pinned so a task cannot be added without
/// a lowering test below.
#[test]
fn the_questing_plugin_registers_exactly_the_documented_task_set() {
    let registry = TaskRegistry::with_questing();
    let names: Vec<&str> = registry.type_names().collect();
    assert_eq!(
        names,
        vec![
            "questing.AcceptQuest",
            "questing.Collect",
            "questing.Flight",
            "questing.Gate",
            "questing.Hearth",
            "questing.Kill",
            "questing.Trainer",
            "questing.Travel",
            "questing.TurnIn",
            "questing.Vendor",
        ]
    );
}

/// Nothing is baked into the core: an empty registry knows no task types, and the questing set
/// arrives through the same `register` any other domain would use.
#[test]
fn the_core_registry_is_empty_until_a_domain_plugin_registers() {
    let empty = TaskRegistry::new();
    assert_eq!(empty.type_names().count(), 0);

    let mut registry = TaskRegistry::new();
    for task in questing_task_types() {
        registry.register(task).expect("first registration wins");
    }
    assert_eq!(registry.type_names().count(), 10);
}

#[test]
fn registering_a_duplicate_task_type_is_rejected_rather_than_shadowing() {
    let mut registry = TaskRegistry::with_questing();
    let duplicate = questing_task_types()
        .into_iter()
        .next()
        .expect("the questing set is non-empty");
    let name = duplicate.type_name;
    let err = registry
        .register(duplicate)
        .expect_err("a second registration of the same type must fail");
    assert!(err.to_string().contains(name), "{err}");
}

/// A fully-populated intent per registered type. This is also the coverage ledger: a new task type
/// fails `the_questing_plugin_registers_exactly_the_documented_task_set` until it is added here.
fn well_formed_intent(type_name: &str) -> Intent {
    let mut intent = Intent::new();
    match type_name {
        "questing.AcceptQuest" => {
            intent.insert("quest", entity(EntityKind::Quest, 783, "Kobold Camp Cleanup"));
            intent.insert("from", entity(EntityKind::Npc, 823, "Deputy Willem"));
        }
        "questing.TurnIn" => {
            intent.insert("quest", entity(EntityKind::Quest, 783, "Kobold Camp Cleanup"));
            intent.insert("to", entity(EntityKind::Npc, 823, "Deputy Willem"));
        }
        "questing.Kill" => {
            intent.insert("target", entity(EntityKind::Npc, 299, "Kobold Vermin"));
            intent.insert("count", 8i64);
            intent.insert("loot", true);
        }
        "questing.Collect" => {
            intent.insert("object", entity(EntityKind::Object, 1617, "Chest"));
            intent.insert("count", 4i64);
        }
        "questing.Vendor" => {
            intent.insert("npc", entity(EntityKind::Npc, 1247, "Innkeeper Farley"));
            intent.insert("sell_grey", true);
            intent.insert("repair", true);
            intent.insert(
                "buy",
                IntentValue::List(vec![entity(EntityKind::Item, 2589, "Linen Cloth")]),
            );
        }
        "questing.Trainer" => {
            intent.insert("npc", entity(EntityKind::Npc, 1247, "Innkeeper Farley"));
            intent.insert(
                "spells",
                IntentValue::List(vec![entity(EntityKind::Spell, 8690, "Hearthstone")]),
            );
        }
        "questing.Flight" => {
            intent.insert("npc", entity(EntityKind::Npc, 1247, "Innkeeper Farley"));
            intent.insert("destination", "Stormwind");
        }
        "questing.Hearth" => {
            intent.insert("destination", "Goldshire");
        }
        "questing.Gate" => {
            intent.insert("quest", entity(EntityKind::Quest, 783, "Kobold Camp Cleanup"));
            intent.insert("quest_state", "completed");
            intent.insert("level", 10i64);
        }
        "questing.Travel" => {
            intent.insert("to", entity(EntityKind::Npc, 823, "Deputy Willem"));
        }
        other => panic!("no fixture intent for task type `{other}`"),
    }
    intent
}

#[test]
fn every_registered_task_type_lowers_to_at_least_one_action() {
    let registry = TaskRegistry::with_questing();
    let db = db();
    for name in registry.type_names().collect::<Vec<_>>() {
        let task = registry.get(name).expect("listed types resolve");
        let intent = well_formed_intent(name);
        let mut diagnostics = Vec::new();
        let actions = (task.lower)(&intent, &db as &dyn ResolverDb, &mut diagnostics);
        assert!(
            !actions.is_empty(),
            "`{name}` lowered to no action: {diagnostics:#?}"
        );
        assert!(
            errors(&diagnostics).is_empty(),
            "`{name}` produced errors on a well-formed intent: {diagnostics:#?}"
        );
    }
}

#[test]
fn every_registered_task_type_validates_a_well_formed_intent_cleanly() {
    let registry = TaskRegistry::with_questing();
    let db = db();
    for name in registry.type_names().collect::<Vec<_>>() {
        let task = registry.get(name).expect("listed types resolve");
        let diagnostics = task.check(&well_formed_intent(name), &db as &dyn ResolverDb);
        assert!(
            diagnostics.is_empty(),
            "`{name}` rejected its own well-formed intent: {diagnostics:#?}"
        );
    }
}

/// The enforcement point of ADR 09 §4 rule 1: the IDE Properties panel renders from `schema`, so
/// the schema has to be complete and serializable. A hand-coded per-task panel is what this test
/// exists to make unnecessary.
#[test]
fn every_task_type_exposes_a_serializable_schema_for_the_properties_panel() {
    let registry = TaskRegistry::with_questing();
    for name in registry.type_names().collect::<Vec<_>>() {
        let task = registry.get(name).expect("listed types resolve");
        assert!(!task.schema.is_empty(), "`{name}` has no schema");
        let wire = serde_json::to_value(&task.schema).expect("schema serializes");
        for field in wire.as_array().expect("schema is an array") {
            assert!(field["name"].is_string(), "{field}");
            assert!(field["kind"].is_string(), "{field}");
            assert!(field["required"].is_boolean(), "{field}");
        }
    }
}

#[test]
fn entity_fields_declare_the_kind_the_ide_should_autocomplete() {
    let registry = TaskRegistry::with_questing();
    let accept = registry.get("questing.AcceptQuest").expect("registered");
    let wire = serde_json::to_value(&accept.schema).unwrap();
    let quest = wire
        .as_array()
        .unwrap()
        .iter()
        .find(|field| field["name"] == "quest")
        .expect("AcceptQuest has a quest field");
    assert_eq!(quest["kind"], "entity");
    assert_eq!(quest["entity_type"], "quest");
    assert_eq!(quest["required"], true);
}

/// `RuntimeTravel.position` is `f32`, and JSON `83` deserializes as an integer while `83.0`
/// deserializes as a float. A coordinate authored without a decimal point must not be rejected as
/// the wrong kind.
#[test]
fn an_integer_authored_into_a_float_field_is_accepted() {
    let mut intent = Intent::new();
    intent.insert("map", 0i64);
    intent.insert("x", -8933i64);
    intent.insert("y", -136i64);
    intent.insert("z", 83i64);
    intent.insert("destination", "Northshire");

    let registry = TaskRegistry::with_questing();
    let travel = registry.get("questing.Travel").expect("registered");
    let db = db();
    assert!(
        travel.check(&intent, &db as &dyn ResolverDb).is_empty(),
        "integer coordinates must satisfy a float field"
    );

    let mut diagnostics = Vec::new();
    let actions = (travel.lower)(&intent, &db as &dyn ResolverDb, &mut diagnostics);
    let RuntimeAction::Travel(action) = &actions[0].action else {
        panic!("Travel must lower to Travel");
    };
    assert_eq!(action.position.world_z, 83.0);
}

#[test]
fn a_validation_rule_violation_is_reported_against_its_field() {
    let mut intent = well_formed_intent("questing.Kill");
    intent.insert("count", 0i64);

    let registry = TaskRegistry::with_questing();
    let kill = registry.get("questing.Kill").expect("registered");
    let db = db();
    let diagnostics = kill.check(&intent, &db as &dyn ResolverDb);
    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.field.rule" && d.field.as_deref() == Some("count")),
        "{diagnostics:#?}"
    );
}

#[test]
fn an_unknown_intent_field_warns_rather_than_failing() {
    let mut intent = well_formed_intent("questing.Kill");
    intent.insert("colour", "blue");

    let registry = TaskRegistry::with_questing();
    let kill = registry.get("questing.Kill").expect("registered");
    let db = db();
    let diagnostics = kill.check(&intent, &db as &dyn ResolverDb);
    assert_eq!(diagnostics.len(), 1);
    assert_eq!(diagnostics[0].code, "resolver.field.unknown");
    assert_eq!(diagnostics[0].severity, Severity::Warning);
}

/// `Gate` is the branch primitive. It lowers to the existing `Condition` action — no new runtime
/// action type was invented for it (ADR 09 §4 rule 2).
#[test]
fn gate_lowers_to_the_existing_condition_action() {
    let registry = TaskRegistry::with_questing();
    let gate = registry.get("questing.Gate").expect("registered");
    let db = db();
    let mut diagnostics = Vec::new();
    let actions = (gate.lower)(
        &well_formed_intent("questing.Gate"),
        &db as &dyn ResolverDb,
        &mut diagnostics,
    );
    let RuntimeAction::Condition(condition) = &actions[0].action else {
        panic!("Gate must lower to Condition: {actions:?}");
    };
    let wire = serde_json::to_value(&condition.condition).unwrap();
    assert_eq!(wire["type"], "All");
    assert_eq!(wire["payload"][0]["type"], "QuestCompleted");
    assert_eq!(wire["payload"][1]["type"], "LevelAtLeast");
}

#[test]
fn a_gate_with_no_clause_is_an_error_not_a_pass_through() {
    let registry = TaskRegistry::with_questing();
    let gate = registry.get("questing.Gate").expect("registered");
    let db = db();
    let diagnostics = gate.check(&Intent::new(), &db as &dyn ResolverDb);
    assert!(
        diagnostics
            .iter()
            .any(|d| d.code == "resolver.gate.no_clause" && d.severity == Severity::Error),
        "{diagnostics:#?}"
    );
}

/// The plan is the runtime's input and the Lua side dispatches on `action.type`. Externally
/// tagged enums silently fail open there (see `CLAUDE.md` known state), so pin the bytes.
#[test]
fn the_plan_serializes_with_the_adjacent_tagging_the_lua_runtime_dispatches_on() {
    let (plan, _) = resolve(&linear_campaign(), &db());
    let wire = serde_json::to_value(&plan).unwrap();
    assert_eq!(wire["operations"][0]["actions"][1]["type"], "AcceptQuest");
    assert_eq!(
        wire["operations"][0]["actions"][1]["payload"]["quest_id"],
        783
    );
    assert_eq!(
        wire["operations"][0]["actions"][1]["payload"]["npc_entry"],
        823
    );
    assert_eq!(wire["operations"][0]["next"][0]["to_index"], 1);
    assert_eq!(
        wire["operations"][0]["next"][0]["guard"],
        serde_json::Value::Null
    );
}
