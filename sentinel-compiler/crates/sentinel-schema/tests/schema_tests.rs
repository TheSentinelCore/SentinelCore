//! Tests for sentinel-schema — comprehensive round-trip coverage

use sentinel_schema::prelude::*;
use sentinel_schema::{
    Action, ActionPayload, Analytics,
    Blueprint, BlueprintParameter, BlueprintReference, BlueprintCategory, ParameterType, ParameterValue,
    Condition, ExitConditions,
    FlightNode, HearthLocation,
    Operation, OperationDependency, OperationGoal,
    OptimizationPolicy, DependencyType, CompletionMetrics, OperationAnalytics,
    Path, Polygon,
};
use sentinel_schema::action::{
    BranchAction, DeathSkipAction, DungeonMarkerAction, EscortAction,
    FlightAction, GoToAction, GrindAreaAction, HearthAction,
    KillTargetAction, LootObjectAction, MailboxAction, BankAction,
    PickupQuestAction, PatrolAction, PurchaseRule, RecordPathAction,
    RepairAction, RetryPolicy as ActionRetryPolicy, SetVariableAction,
    StopCondition, PathSmoothing, TalkToNpcAction, TrainAction,
    TurnInQuestAction, UseItemAction, VendorAction, WaitAction,
};
use sentinel_schema::metadata::{Metadata, SourceType};
use uuid::Uuid;

// ── Helper ──────────────────────────────────────────────────────────────────

fn fixed_time() -> chrono::DateTime<chrono::Utc> {
    chrono::DateTime::parse_from_rfc3339("2025-06-01T12:00:00Z")
        .unwrap()
        .with_timezone(&chrono::Utc)
}

fn wp(zone: &str, x: f32, y: f32, z: f32) -> Waypoint {
    Waypoint::new(0, zone, x, y, z, 5.0)
}

fn npc(entry: u32, name: &str, zone: &str, pos: Waypoint) -> NpcReference {
    NpcReference::new(entry, name, zone, pos)
        .with_guid(format!("guid-{}", entry))
        .with_roles(vec![NpcRole::QuestGiver, NpcRole::Vendor])
}

// ── Geometry ────────────────────────────────────────────────────────────────

#[test]
fn test_waypoint_roundtrip() {
    let wp = Waypoint::new(0, "Elwynn Forest", -8912.5, -132.3, 83.2, 5.0);
    let json = serde_json::to_string(&wp).unwrap();
    let parsed: Waypoint = serde_json::from_str(&json).unwrap();
    assert_eq!(wp, parsed);
}

#[test]
fn test_path_roundtrip() {
    let path = Path::new(vec![
        Waypoint::new(0, "Elwynn Forest", -8900.0, -130.0, 80.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8910.0, -135.0, 81.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8920.0, -140.0, 82.0, 5.0),
    ]);
    let json = serde_json::to_string(&path).unwrap();
    let parsed: Path = serde_json::from_str(&json).unwrap();
    assert_eq!(path, parsed);
    assert_eq!(parsed.len(), 3);
}

#[test]
fn test_polygon_roundtrip() {
    let poly = Polygon::new(vec![
        Waypoint::new(0, "Elwynn Forest", -8900.0, -130.0, 80.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8910.0, -130.0, 80.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8910.0, -140.0, 80.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8900.0, -140.0, 80.0, 5.0),
    ]);
    let json = serde_json::to_string(&poly).unwrap();
    let parsed: Polygon = serde_json::from_str(&json).unwrap();
    assert_eq!(poly, parsed);
    assert!(parsed.is_valid());
    assert_eq!(parsed.vertex_count(), 4);
}

// ── Reference types ─────────────────────────────────────────────────────────

#[test]
fn test_npc_reference_roundtrip() {
    let pos = wp("Elwynn Forest", -8912.5, -132.3, 83.2);
    let npc = npc(197, "Marshal McBride", "Elwynn Forest", pos);
    let json = serde_json::to_string(&npc).unwrap();
    let parsed: NpcReference = serde_json::from_str(&json).unwrap();
    assert_eq!(npc, parsed);
    assert_eq!(parsed.roles.len(), 2);
    assert!(parsed.has_role(NpcRole::QuestGiver));
    assert!(parsed.has_role(NpcRole::Vendor));
}

#[test]
fn test_quest_reference_roundtrip() {
    let quest = QuestReference::new(33, "Wolves Across the Border", 197, 48);
    let json = serde_json::to_string(&quest).unwrap();
    let parsed: QuestReference = serde_json::from_str(&json).unwrap();
    assert_eq!(quest, parsed);
}

#[test]
fn test_item_reference_roundtrip() {
    let item = ItemReference::new(2589, "Linen Cloth", 10);
    let json = serde_json::to_string(&item).unwrap();
    let parsed: ItemReference = serde_json::from_str(&json).unwrap();
    assert_eq!(item, parsed);
}

#[test]
fn test_creature_reference_roundtrip() {
    let c = CreatureReference::new(6, "Kobold Worker");
    let json = serde_json::to_string(&c).unwrap();
    let parsed: CreatureReference = serde_json::from_str(&json).unwrap();
    assert_eq!(c, parsed);
}

#[test]
fn test_game_object_reference_roundtrip() {
    let go = GameObjectReference::new(10, "Worn Chest");
    let json = serde_json::to_string(&go).unwrap();
    let parsed: GameObjectReference = serde_json::from_str(&json).unwrap();
    assert_eq!(go, parsed);
}

#[test]
fn test_flight_node_roundtrip() {
    let fn_ = FlightNode::new(1, "Stormwind");
    let json = serde_json::to_string(&fn_).unwrap();
    let parsed: FlightNode = serde_json::from_str(&json).unwrap();
    assert_eq!(fn_, parsed);
}

#[test]
fn test_hearth_location_roundtrip() {
    let hl = HearthLocation::new("Elwynn Forest", 197);
    let json = serde_json::to_string(&hl).unwrap();
    let parsed: HearthLocation = serde_json::from_str(&json).unwrap();
    assert_eq!(hl, parsed);
}

#[test]
fn test_vendor_entry_roundtrip() {
    let pos = wp("Goldshire", -8800.0, -150.0, 80.0);
    let vendor_npc = npc(1234, "Brother Danil", "Goldshire", pos);
    let sells = vec![
        ItemReference::new(2589, "Linen Cloth", 5),
        ItemReference::new(2840, "Copper Bar", 2),
    ];
    let vendor = VendorEntry {
        npc: vendor_npc,
        sells,
        repairs: true,
    };
    let json = serde_json::to_string(&vendor).unwrap();
    let parsed: VendorEntry = serde_json::from_str(&json).unwrap();
    assert_eq!(vendor, parsed);
    assert!(parsed.repairs);
    assert_eq!(parsed.sells.len(), 2);
}

// ── Retry & Settings ────────────────────────────────────────────────────────

#[test]
fn test_retry_policy_roundtrip() {
    let rp = RetryPolicy { retries: 5, delay_ms: 2500 };
    let json = serde_json::to_string(&rp).unwrap();
    let parsed: RetryPolicy = serde_json::from_str(&json).unwrap();
    assert_eq!(rp, parsed);
}

#[test]
fn test_retry_policy_presets_roundtrip() {
    for policy in [
        RetryPolicy::default(),
        RetryPolicy::none(),
        RetryPolicy::aggressive(),
        RetryPolicy::conservative(),
    ] {
        let json = serde_json::to_string(&policy).unwrap();
        let parsed: RetryPolicy = serde_json::from_str(&json).unwrap();
        assert_eq!(policy, parsed);
    }
}

#[test]
fn test_level_range_roundtrip() {
    let lr = LevelRange::new(1, 60);
    let json = serde_json::to_string(&lr).unwrap();
    let parsed: LevelRange = serde_json::from_str(&json).unwrap();
    assert_eq!(lr, parsed);
    assert!(parsed.contains(30));
    assert!(!parsed.contains(0));
}

#[test]
fn test_profile_settings_roundtrip() {
    let settings = ProfileSettings {
        auto_vendor: true,
        auto_repair: false,
        auto_train: true,
        auto_loot: true,
        auto_accept: false,
        auto_turnin: true,
        use_flight_paths: true,
        allow_hearthstone: false,
        use_mailbox: true,
        death_skip: false,
        dry_run_enabled: true,
    };
    let json = serde_json::to_string(&settings).unwrap();
    let parsed: ProfileSettings = serde_json::from_str(&json).unwrap();
    assert_eq!(settings, parsed);
}

// ── Variables ───────────────────────────────────────────────────────────────

#[test]
fn test_variable_bool_roundtrip() {
    let v = Variable::bool("HasFood", true);
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_integer_roundtrip() {
    let v = Variable::integer("Gold", 12345);
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_float_roundtrip() {
    let v = Variable::float("XpRate", 1.75);
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_string_roundtrip() {
    let v = Variable::string("Zone", "Elwynn Forest");
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_position_roundtrip() {
    let v = Variable::position("HearthPos", wp("Goldshire", -8800.0, -150.0, 80.0));
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_quest_id_roundtrip() {
    let v = Variable::quest_id("ActiveQuest", 33);
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_npc_id_roundtrip() {
    let v = Variable::npc_id("TargetNpc", 197);
    let json = serde_json::to_string(&v).unwrap();
    let parsed: Variable = serde_json::from_str(&json).unwrap();
    assert_eq!(v, parsed);
}

#[test]
fn test_variable_all_variants_roundtrip() {
    let vars = vec![
        Variable::bool("B", true),
        Variable::integer("I", -42),
        Variable::float("F", 3.14),
        Variable::string("S", "hello"),
        Variable::position("P", wp("Zone", 1.0, 2.0, 3.0)),
        Variable::quest_id("Q", 99),
        Variable::npc_id("N", 777),
    ];
    let json = serde_json::to_string(&vars).unwrap();
    let parsed: Vec<Variable> = serde_json::from_str(&json).unwrap();
    assert_eq!(vars.len(), parsed.len());
    for (o, p) in vars.iter().zip(parsed.iter()) {
        assert_eq!(o, p);
    }
}

// ── Conditions ──────────────────────────────────────────────────────────────

#[test]
fn test_condition_all_variants_roundtrip() {
    let id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let wp_val = Waypoint::new(0, "Elwynn", 1.0, 2.0, 3.0, 5.0);
    let conditions = vec![
        Condition::QuestAccepted(33),
        Condition::QuestCompleted(34),
        Condition::QuestRewarded(35),
        Condition::LevelAtLeast(5),
        Condition::LevelBelow(10),
        Condition::HasItem(2589),
        Condition::BagSpace(10),
        Condition::DurabilityBelow(0.5),
        Condition::GoldAbove(100),
        Condition::VariableEquals("flag".to_string(), VariableValue::Bool(true)),
        Condition::VariableEquals("count".to_string(), VariableValue::Integer(42)),
        Condition::VariableTrue("ready".to_string()),
        Condition::VariableFalse("done".to_string()),
        Condition::OperationCompleted(id),
        Condition::OperationSkipped(id),
        Condition::OperationFailed(id),
        Condition::FactionIs(Faction::Alliance),
        Condition::RaceIs(Race::Human),
        Condition::ClassIs(Class::Warrior),
        Condition::ZoneEntered("Elwynn Forest".to_string()),
        Condition::QuestFailed(33),
        Condition::QuestTurnedIn(34),
        Condition::QuestAvailable(35),
        Condition::HasFlightPath(1),
        Condition::HasSpell(100),
        Condition::InCombat(true),
        Condition::Dead(false),
        Condition::Mounted(true),
        Condition::Custom("IsNight()".to_string()),
        Condition::VariableEquals("pos".to_string(), VariableValue::Position(wp_val)),
        Condition::VariableEquals("quest".to_string(), VariableValue::QuestId(33)),
        Condition::VariableEquals("npc".to_string(), VariableValue::NpcId(197)),
        Condition::VariableEquals("s".to_string(), VariableValue::String("test".to_string())),
        Condition::VariableEquals("e".to_string(), VariableValue::Enum("Alliance".to_string())),
    ];
    let json = serde_json::to_string_pretty(&conditions).unwrap();
    let parsed: Vec<Condition> = serde_json::from_str(&json).unwrap();
    assert_eq!(conditions.len(), parsed.len());
    for (o, p) in conditions.iter().zip(parsed.iter()) {
        assert_eq!(o, p);
    }
}

#[test]
fn test_exit_conditions_roundtrip() {
    let exit = ExitConditions::new()
        .with_success(vec![Condition::QuestRewarded(33), Condition::QuestRewarded(34)])
        .with_failure(vec![Condition::QuestFailed(33)])
        .with_abort(vec![Condition::Custom("DeathsExceed(3)".to_string())]);
    let json = serde_json::to_string(&exit).unwrap();
    let parsed: ExitConditions = serde_json::from_str(&json).unwrap();
    assert_eq!(exit, parsed);
    assert_eq!(parsed.success.len(), 2);
    assert_eq!(parsed.failure.len(), 1);
    assert_eq!(parsed.abort.len(), 1);
}

#[test]
fn test_exit_conditions_default_roundtrip() {
    let exit = ExitConditions::default();
    let json = serde_json::to_string(&exit).unwrap();
    let parsed: ExitConditions = serde_json::from_str(&json).unwrap();
    assert_eq!(exit, parsed);
    assert!(parsed.success.is_empty());
    assert!(parsed.failure.is_empty());
    assert!(parsed.abort.is_empty());
}

// ── Goals & Dependencies ────────────────────────────────────────────────────

#[test]
fn test_operation_goal_roundtrip() {
    let id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let mut goal = OperationGoal::required("Complete chain", GoalType::CompleteQuestChain(vec![33, 34, 35, 36]), 1.0);
    goal.id = id;
    let json = serde_json::to_string(&goal).unwrap();
    let parsed: OperationGoal = serde_json::from_str(&json).unwrap();
    assert_eq!(goal, parsed);
}

#[test]
fn test_operation_goal_optional_roundtrip() {
    let id = Uuid::parse_str("660e8400-e29b-41d4-a716-446655440000").unwrap();
    let mut goal = OperationGoal::optional("Reach level 5", GoalType::ReachLevel(5), 0.4);
    goal.id = id;
    let json = serde_json::to_string(&goal).unwrap();
    let parsed: OperationGoal = serde_json::from_str(&json).unwrap();
    assert_eq!(goal, parsed);
}

#[test]
fn test_goal_type_all_variants_roundtrip() {
    let wp_val = Waypoint::new(0, "Elwynn", 1.0, 2.0, 3.0, 5.0);
    let goals = vec![
        GoalType::CompleteQuest(33),
        GoalType::CompleteQuestChain(vec![33, 34]),
        GoalType::ReachLevel(5),
        GoalType::GainXp(10000),
        GoalType::ReachZone("Elwynn Forest".to_string()),
        GoalType::ReachWaypoint(wp_val),
        GoalType::AcquireItem(2589, 10),
        GoalType::KillCount(6, 20),
        GoalType::UnlockFlightPath(1),
        GoalType::LearnSpell(100),
        GoalType::Custom("MyCustomGoal".to_string()),
    ];
    let json = serde_json::to_string_pretty(&goals).unwrap();
    let parsed: Vec<GoalType> = serde_json::from_str(&json).unwrap();
    assert_eq!(goals.len(), parsed.len());
    for (o, p) in goals.iter().zip(parsed.iter()) {
        assert_eq!(o, p);
    }
}

#[test]
fn test_operation_dependency_requires_roundtrip() {
    let id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let dep = OperationDependency::requires(id);
    let json = serde_json::to_string(&dep).unwrap();
    let parsed: OperationDependency = serde_json::from_str(&json).unwrap();
    assert_eq!(dep, parsed);
}

#[test]
fn test_operation_dependency_all_types_roundtrip() {
    let id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let deps = vec![
        OperationDependency::requires(id),
        OperationDependency::soft_prefers(id),
        OperationDependency::excludes_with(id),
        OperationDependency::unlocks_after(id),
    ];
    let json = serde_json::to_string_pretty(&deps).unwrap();
    let parsed: Vec<OperationDependency> = serde_json::from_str(&json).unwrap();
    assert_eq!(deps.len(), parsed.len());
    for (o, p) in deps.iter().zip(parsed.iter()) {
        assert_eq!(o, p);
    }
}

// ── Enums ───────────────────────────────────────────────────────────────────

#[test]
fn test_game_version_roundtrip() {
    for v in [GameVersion::TbcClassic, GameVersion::WrathClassic, GameVersion::CataclysmClassic] {
        let json = serde_json::to_string(&v).unwrap();
        let parsed: GameVersion = serde_json::from_str(&json).unwrap();
        assert_eq!(v, parsed);
    }
}

#[test]
fn test_faction_roundtrip() {
    for f in [Faction::Alliance, Faction::Horde, Faction::Neutral] {
        let json = serde_json::to_string(&f).unwrap();
        let parsed: Faction = serde_json::from_str(&json).unwrap();
        assert_eq!(f, parsed);
    }
}

#[test]
fn test_race_roundtrip() {
    let races = vec![
        Race::Human, Race::Orc, Race::Dwarf, Race::NightElf, Race::Undead,
        Race::Tauren, Race::Gnome, Race::Troll, Race::BloodElf, Race::Draenei,
    ];
    for r in races {
        let json = serde_json::to_string(&r).unwrap();
        let parsed: Race = serde_json::from_str(&json).unwrap();
        assert_eq!(r, parsed);
    }
}

#[test]
fn test_class_roundtrip() {
    let classes = vec![
        Class::Warrior, Class::Paladin, Class::Hunter, Class::Rogue, Class::Priest,
        Class::DeathKnight, Class::Shaman, Class::Mage, Class::Warlock, Class::Druid,
    ];
    for c in classes {
        let json = serde_json::to_string(&c).unwrap();
        let parsed: Class = serde_json::from_str(&json).unwrap();
        assert_eq!(c, parsed);
    }
}

#[test]
fn test_npc_role_roundtrip() {
    let roles = vec![
        NpcRole::QuestGiver, NpcRole::Vendor, NpcRole::Trainer, NpcRole::Innkeeper,
        NpcRole::FlightMaster, NpcRole::Repair, NpcRole::Mailbox, NpcRole::Bank,
        NpcRole::Auctioneer, NpcRole::SpiritHealer, NpcRole::Generic,
    ];
    for r in roles {
        let json = serde_json::to_string(&r).unwrap();
        let parsed: NpcRole = serde_json::from_str(&json).unwrap();
        assert_eq!(r, parsed);
    }
}

#[test]
fn test_dependency_type_roundtrip() {
    for dt in [DependencyType::Requires, DependencyType::SoftPrefers, DependencyType::ExcludesWith, DependencyType::UnlocksAfter] {
        let json = serde_json::to_string(&dt).unwrap();
        let parsed: DependencyType = serde_json::from_str(&json).unwrap();
        assert_eq!(dt, parsed);
    }
}

#[test]
fn test_operation_status_roundtrip() {
    for s in [
        OperationStatus::Locked, OperationStatus::Ready, OperationStatus::Active,
        OperationStatus::Completed, OperationStatus::Failed, OperationStatus::Aborted, OperationStatus::Skipped,
    ] {
        let json = serde_json::to_string(&s).unwrap();
        let parsed: OperationStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(s, parsed);
    }
}

#[test]
fn test_path_smoothing_roundtrip() {
    for ps in [PathSmoothing::None, PathSmoothing::Chaikin, PathSmoothing::CatmullRom, PathSmoothing::Bezier] {
        let json = serde_json::to_string(&ps).unwrap();
        let parsed: PathSmoothing = serde_json::from_str(&json).unwrap();
        assert_eq!(ps, parsed);
    }
}

#[test]
fn test_stop_condition_roundtrip() {
    let conditions = vec![
        StopCondition::QuestComplete,
        StopCondition::ItemCount(2589, 10),
        StopCondition::KillCount(6, 20),
        StopCondition::TimeLimit(600000),
        StopCondition::LevelReached(5),
        StopCondition::Manual,
    ];
    let json = serde_json::to_string_pretty(&conditions).unwrap();
    let parsed: Vec<StopCondition> = serde_json::from_str(&json).unwrap();
    assert_eq!(conditions.len(), parsed.len());
    for (o, p) in conditions.iter().zip(parsed.iter()) {
        assert_eq!(o, p);
    }
}

#[test]
fn test_source_type_roundtrip() {
    for s in [SourceType::Manual, SourceType::Captured, SourceType::Imported, SourceType::Migrated] {
        let json = serde_json::to_string(&s).unwrap();
        let parsed: SourceType = serde_json::from_str(&json).unwrap();
        assert_eq!(s, parsed);
    }
}

// ── Metadata ────────────────────────────────────────────────────────────────

#[test]
fn test_metadata_roundtrip() {
    let meta = Metadata {
        created_at: fixed_time(),
        updated_at: fixed_time(),
        editor_version: "0.1.0".to_string(),
        compiler_version: "0.1.0".to_string(),
        notes: Some("Test notes".to_string()),
        source: SourceType::Captured,
    };
    let json = serde_json::to_string(&meta).unwrap();
    let parsed: Metadata = serde_json::from_str(&json).unwrap();
    assert_eq!(meta, parsed);
}

#[test]
fn test_metadata_default_roundtrip() {
    let meta = Metadata::default();
    let json = serde_json::to_string(&meta).unwrap();
    let parsed: Metadata = serde_json::from_str(&json).unwrap();
    assert_eq!(meta.created_at, parsed.created_at);
    assert_eq!(meta.editor_version, parsed.editor_version);
}

// ── Optimization & Analytics ────────────────────────────────────────────────

#[test]
fn test_optimization_policy_roundtrip() {
    let policy = OptimizationPolicy {
        travel_weight: 0.6,
        xp_weight: 0.4,
        time_weight: 0.1,
        risk_weight: 0.8,
        cluster_objectives: false,
        allow_reordering: false,
        grind_fallback: true,
        max_deaths: Some(1),
    };
    let json = serde_json::to_string(&policy).unwrap();
    let parsed: OptimizationPolicy = serde_json::from_str(&json).unwrap();
    assert_eq!(policy, parsed);
}

#[test]
fn test_optimization_policy_presets_roundtrip() {
    for policy in [OptimizationPolicy::default(), OptimizationPolicy::safe_low_level(), OptimizationPolicy::dangerous_high_level()] {
        let json = serde_json::to_string(&policy).unwrap();
        let parsed: OptimizationPolicy = serde_json::from_str(&json).unwrap();
        assert_eq!(policy, parsed);
    }
}

#[test]
fn test_completion_metrics_roundtrip() {
    let cm = CompletionMetrics {
        target_duration_ms: Some(300000),
        target_xp: Some(50000),
        min_success_rate: Some(0.9),
        max_acceptable_deaths: Some(3),
    };
    let json = serde_json::to_string(&cm).unwrap();
    let parsed: CompletionMetrics = serde_json::from_str(&json).unwrap();
    assert_eq!(cm, parsed);
}

#[test]
fn test_operation_analytics_roundtrip() {
    let id1 = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let id2 = Uuid::parse_str("660e8400-e29b-41d4-a716-446655440000").unwrap();
    let analytics = OperationAnalytics {
        runs: 42,
        average_duration_ms: 120000,
        average_xp: 5000.0,
        average_gold: 250.0,
        average_deaths: 0.5,
        success_rate: 0.95,
        skip_rate: 0.02,
        last_run: Some(fixed_time()),
        bottleneck_actions: vec![id1, id2],
    };
    let json = serde_json::to_string(&analytics).unwrap();
    let parsed: OperationAnalytics = serde_json::from_str(&json).unwrap();
    assert_eq!(analytics, parsed);
}

#[test]
fn test_analytics_roundtrip() {
    let a = Analytics {
        average_time: std::time::Duration::from_secs(120),
        average_xp: 5000.0,
        average_gold: 250.0,
        deaths: 2,
    };
    let json = serde_json::to_string(&a).unwrap();
    let parsed: Analytics = serde_json::from_str(&json).unwrap();
    assert_eq!(a, parsed);
}

// ── Blueprint types ─────────────────────────────────────────────────────────

#[test]
fn test_blueprint_reference_roundtrip() {
    let br = BlueprintReference::new("quest-hub-v1", "1.0.0")
        .with_param("vendor_id", serde_json::json!(1234))
        .with_param("repair", serde_json::json!(true));
    let json = serde_json::to_string(&br).unwrap();
    let parsed: BlueprintReference = serde_json::from_str(&json).unwrap();
    assert_eq!(br, parsed);
    assert_eq!(parsed.id, "quest-hub-v1");
    assert_eq!(parsed.version, "1.0.0");
}

#[test]
fn test_blueprint_parameter_required_roundtrip() {
    let param = BlueprintParameter::required("QuestGiver", ParameterType::Npc, "The quest giver NPC");
    let json = serde_json::to_string(&param).unwrap();
    let parsed: BlueprintParameter = serde_json::from_str(&json).unwrap();
    assert_eq!(param, parsed);
}

#[test]
fn test_blueprint_parameter_optional_roundtrip() {
    let param = BlueprintParameter::optional("Repair", ParameterType::Boolean, "Enable repair", ParameterValue::Boolean(true));
    let json = serde_json::to_string(&param).unwrap();
    let parsed: BlueprintParameter = serde_json::from_str(&json).unwrap();
    assert_eq!(param, parsed);
}

#[test]
fn test_parameter_type_all_variants_roundtrip() {
    for pt in [
        ParameterType::Npc, ParameterType::Quest, ParameterType::Waypoint, ParameterType::Polygon,
        ParameterType::Creature, ParameterType::Vendor, ParameterType::Trainer, ParameterType::Flight,
        ParameterType::Boolean, ParameterType::Integer, ParameterType::Float, ParameterType::String,
        ParameterType::Enum,
    ] {
        let json = serde_json::to_string(&pt).unwrap();
        let parsed: ParameterType = serde_json::from_str(&json).unwrap();
        assert_eq!(pt, parsed);
    }
}

#[test]
fn test_parameter_value_all_variants_roundtrip() {
    let pos = Waypoint::new(0, "Elwynn", 1.0, 2.0, 3.0, 5.0);
    let poly = Polygon::new(vec![
        Waypoint::new(0, "Elwynn", 0.0, 0.0, 0.0, 5.0),
        Waypoint::new(0, "Elwynn", 1.0, 0.0, 0.0, 5.0),
        Waypoint::new(0, "Elwynn", 0.0, 1.0, 0.0, 5.0),
    ]);
    let npc_ref = NpcReference::new(197, "McBride", "Elwynn", pos.clone());
    let values = vec![
        ParameterValue::Npc(npc_ref.clone()),
        ParameterValue::Quest(QuestReference::new(33, "Wolves", 197, 48)),
        ParameterValue::Waypoint(pos.clone()),
        ParameterValue::Polygon(poly),
        ParameterValue::Creature(CreatureReference::new(6, "Kobold")),
        ParameterValue::Vendor(VendorEntry { npc: npc_ref.clone(), sells: vec![], repairs: false }),
        ParameterValue::Trainer(npc_ref),
        ParameterValue::Flight(FlightNode::new(1, "Stormwind")),
        ParameterValue::Boolean(true),
        ParameterValue::Integer(42),
        ParameterValue::Float(3.14),
        ParameterValue::String("test".to_string()),
        ParameterValue::Enum("Alliance".to_string()),
    ];
    let json = serde_json::to_string_pretty(&values).unwrap();
    let parsed: Vec<ParameterValue> = serde_json::from_str(&json).unwrap();
    assert_eq!(values.len(), parsed.len());
    for (o, p) in values.iter().zip(parsed.iter()) {
        assert_eq!(o, p);
    }
}

#[test]
fn test_blueprint_roundtrip() {
    let bp_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let mut bp = Blueprint::new("Quest Hub", BlueprintCategory::Quest);
    bp.id = bp_id;
    bp.description = "Reusable quest hub template".to_string();
    bp.icon = "quest_hub.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Vendor", ParameterType::Vendor, "The vendor NPC"),
        BlueprintParameter::optional("Repair", ParameterType::Boolean, "Enable repair", ParameterValue::Boolean(true)),
    ];
    // Blueprint outputs Vec<Action> — put a simple Wait action in
    let action = Action::new("Wait for NPC", ActionPayload::Wait(WaitAction { duration_ms: 1000 }));
    bp.outputs = vec![action];
    let json = serde_json::to_string_pretty(&bp).unwrap();
    let parsed: Blueprint = serde_json::from_str(&json).unwrap();
    assert_eq!(bp.id, parsed.id);
    assert_eq!(bp.name, parsed.name);
    assert_eq!(bp.category, parsed.category);
    assert_eq!(bp.parameters.len(), parsed.parameters.len());
    assert_eq!(bp.outputs.len(), parsed.outputs.len());
}

// ── Actions ─────────────────────────────────────────────────────────────────

fn test_action_roundtrip(action: Action, label: &str) {
    let json = serde_json::to_string_pretty(&action).unwrap();
    let parsed: Action = serde_json::from_str(&json).unwrap_or_else(|e| {
        panic!("Failed to parse action '{}': {}\nJSON:\n{}", label, e, json)
    });
    assert_eq!(action.id, parsed.id, "{}: id mismatch", label);
    assert_eq!(action.enabled, parsed.enabled, "{}: enabled mismatch", label);
    assert_eq!(action.name, parsed.name, "{}: name mismatch", label);
    assert_eq!(action.notes, parsed.notes, "{}: notes mismatch", label);
    assert_eq!(action.retry_policy, parsed.retry_policy, "{}: retry_policy mismatch", label);
    assert_eq!(action.timeout_ms, parsed.timeout_ms, "{}: timeout_ms mismatch", label);
    assert_eq!(action.conditions.len(), parsed.conditions.len(), "{}: conditions len mismatch", label);
    assert_eq!(action.payload, parsed.payload, "{}: payload mismatch", label);
}

fn make_npc_ref() -> NpcReference {
    npc(197, "Marshal McBride", "Elwynn Forest", wp("Elwynn Forest", -8912.5, -132.3, 83.2))
}

fn make_quest_ref() -> QuestReference {
    QuestReference::new(33, "Wolves Across the Border", 197, 48)
}

fn make_item_ref() -> ItemReference {
    ItemReference::new(2589, "Linen Cloth", 10)
}

fn make_creature_ref() -> CreatureReference {
    CreatureReference::new(6, "Kobold Worker")
}

fn make_game_object_ref() -> GameObjectReference {
    GameObjectReference::new(10, "Worn Chest")
}

fn make_path() -> Path {
    Path::new(vec![
        wp("Elwynn Forest", -8900.0, -130.0, 80.0),
        wp("Elwynn Forest", -8910.0, -135.0, 81.0),
        wp("Elwynn Forest", -8920.0, -140.0, 82.0),
    ])
}

fn make_polygon() -> Polygon {
    Polygon::new(vec![
        wp("Elwynn Forest", -8900.0, -130.0, 80.0),
        wp("Elwynn Forest", -8910.0, -130.0, 80.0),
        wp("Elwynn Forest", -8910.0, -140.0, 80.0),
        wp("Elwynn Forest", -8900.0, -140.0, 80.0),
    ])
}

fn make_vendor_entry() -> VendorEntry {
    VendorEntry {
        npc: npc(1234, "Brother Danil", "Goldshire", wp("Goldshire", -8800.0, -150.0, 80.0)),
        sells: vec![make_item_ref()],
        repairs: true,
    }
}

#[test]
fn test_action_pickup_quest_roundtrip() {
    let id = Uuid::nil();
    let action = Action {
        id,
        enabled: true,
        name: "Pickup Wolves".to_string(),
        notes: Some("First quest".to_string()),
        tags: vec!["quest".to_string()],
        retry_policy: ActionRetryPolicy { retries: 3, delay_ms: 1000 },
        timeout_ms: 15000,
        conditions: vec![Condition::LevelAtLeast(1)],
        payload: ActionPayload::PickupQuest(PickupQuestAction {
            quest: make_quest_ref(),
            npc: make_npc_ref(),
            auto_complete_previous: false,
        }),
    };
    test_action_roundtrip(action, "PickupQuest");
}

#[test]
fn test_action_turn_in_quest_roundtrip() {
    let action = Action::new("Turn In Wolves", ActionPayload::TurnInQuest(TurnInQuestAction {
        quest: make_quest_ref(),
        npc: make_npc_ref(),
    }));
    test_action_roundtrip(action, "TurnInQuest");
}

#[test]
fn test_action_goto_roundtrip() {
    let action = Action::new("Go to Marshal", ActionPayload::GoTo(GoToAction {
        destination: wp("Elwynn Forest", -8912.5, -132.3, 83.2),
        arrival_radius: 10.0,
    }));
    test_action_roundtrip(action, "GoTo");
}

#[test]
fn test_action_record_path_roundtrip() {
    let action = Action::new("Record Path", ActionPayload::RecordPath(RecordPathAction {
        path: make_path(),
        smoothing: PathSmoothing::Chaikin,
    }));
    test_action_roundtrip(action, "RecordPath");
}

#[test]
fn test_action_patrol_roundtrip() {
    let action = Action::new("Patrol", ActionPayload::Patrol(PatrolAction {
        path: make_path(),
        wait_at_waypoints: true,
        wait_duration_ms: 5000,
    }));
    test_action_roundtrip(action, "Patrol");
}

#[test]
fn test_action_escort_roundtrip() {
    let action = Action::new("Escort NPC", ActionPayload::Escort(EscortAction {
        npc: make_npc_ref(),
        path: make_path(),
        protect: true,
    }));
    test_action_roundtrip(action, "Escort");
}

#[test]
fn test_action_grind_area_roundtrip() {
    let action = Action::new("Grind Kobolds", ActionPayload::GrindArea(GrindAreaAction {
        polygon: make_polygon(),
        targets: vec![make_creature_ref()],
        stop_condition: StopCondition::KillCount(6, 20),
        loot: vec![make_item_ref()],
    }));
    test_action_roundtrip(action, "GrindArea");
}

#[test]
fn test_action_kill_target_roundtrip() {
    let action = Action::new("Kill Kobolds", ActionPayload::KillTarget(KillTargetAction {
        targets: vec![make_creature_ref()],
        amount: Some(5),
    }));
    test_action_roundtrip(action, "KillTarget");
}

#[test]
fn test_action_kill_target_no_amount_roundtrip() {
    let action = Action::new("Kill Any", ActionPayload::KillTarget(KillTargetAction {
        targets: vec![make_creature_ref()],
        amount: None,
    }));
    test_action_roundtrip(action, "KillTarget(None)");
}

#[test]
fn test_action_loot_object_roundtrip() {
    let action = Action::new("Loot Chest", ActionPayload::LootObject(LootObjectAction {
        objects: vec![make_game_object_ref()],
    }));
    test_action_roundtrip(action, "LootObject");
}

#[test]
fn test_action_talk_to_npc_roundtrip() {
    let action = Action::new("Talk to McBride", ActionPayload::TalkToNpc(TalkToNpcAction {
        npc: make_npc_ref(),
        gossip_option: Some("I am ready to fight!".to_string()),
    }));
    test_action_roundtrip(action, "TalkToNpc");
}

#[test]
fn test_action_talk_to_npc_no_gossip_roundtrip() {
    let action = Action::new("Talk", ActionPayload::TalkToNpc(TalkToNpcAction {
        npc: make_npc_ref(),
        gossip_option: None,
    }));
    test_action_roundtrip(action, "TalkToNpc(None)");
}

#[test]
fn test_action_vendor_roundtrip() {
    let action = Action::new("Vendor Stop", ActionPayload::Vendor(VendorAction {
        vendor: make_vendor_entry(),
        repair: true,
        sell_gray: true,
        sell_white: false,
        buy: vec![PurchaseRule {
            item: make_item_ref(),
            max_count: 5,
            condition: Some(Condition::HasItem(2589)),
        }],
    }));
    test_action_roundtrip(action, "Vendor");
}

#[test]
fn test_action_repair_roundtrip() {
    let action = Action::new("Repair", ActionPayload::Repair(RepairAction {
        vendor: make_vendor_entry(),
    }));
    test_action_roundtrip(action, "Repair");
}

#[test]
fn test_action_train_roundtrip() {
    let action = Action::new("Train Abilities", ActionPayload::Train(TrainAction {
        trainer: make_npc_ref(),
        class: Class::Warrior,
    }));
    test_action_roundtrip(action, "Train");
}

#[test]
fn test_action_flight_roundtrip() {
    let action = Action::new("Fly to Stormwind", ActionPayload::FlightPath(FlightAction {
        from: FlightNode::new(1, "Goldshire"),
        to: FlightNode::new(2, "Stormwind"),
    }));
    test_action_roundtrip(action, "FlightPath");
}

#[test]
fn test_action_hearth_roundtrip() {
    let action = Action::new("Use Hearthstone", ActionPayload::Hearth(HearthAction {
        destination: HearthLocation::new("Elwynn Forest", 197),
    }));
    test_action_roundtrip(action, "Hearth");
}

#[test]
fn test_action_mailbox_roundtrip() {
    let action = Action::new("Check Mail", ActionPayload::Mailbox(MailboxAction {
        mailbox: make_npc_ref(),
    }));
    test_action_roundtrip(action, "Mailbox");
}

#[test]
fn test_action_bank_roundtrip() {
    let action = Action::new("Visit Bank", ActionPayload::Bank(BankAction {
        banker: make_npc_ref(),
    }));
    test_action_roundtrip(action, "Bank");
}

#[test]
fn test_action_use_item_roundtrip() {
    let action = Action::new("Use Potion", ActionPayload::UseItem(UseItemAction {
        item: make_item_ref(),
        target: Some(make_npc_ref()),
    }));
    test_action_roundtrip(action, "UseItem");
}

#[test]
fn test_action_use_item_no_target_roundtrip() {
    let action = Action::new("Use Item", ActionPayload::UseItem(UseItemAction {
        item: make_item_ref(),
        target: None,
    }));
    test_action_roundtrip(action, "UseItem(None)");
}

#[test]
fn test_action_wait_roundtrip() {
    let action = Action::new("Wait", ActionPayload::Wait(WaitAction { duration_ms: 5000 }));
    test_action_roundtrip(action, "Wait");
}

#[test]
fn test_action_set_variable_roundtrip() {
    let action = Action::new("Set Flag", ActionPayload::SetVariable(SetVariableAction {
        variable: "Ready".to_string(),
        value: VariableValue::Bool(true),
    }));
    test_action_roundtrip(action, "SetVariable");
}

#[test]
fn test_action_branch_roundtrip() {
    let id1 = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let id2 = Uuid::parse_str("660e8400-e29b-41d4-a716-446655440000").unwrap();
    let action = Action::new("Branch on Level", ActionPayload::Branch(BranchAction {
        expression: Condition::LevelAtLeast(5),
        true_actions: vec![id1],
        false_actions: vec![id2],
    }));
    test_action_roundtrip(action, "Branch");
}

#[test]
fn test_action_dungeon_marker_roundtrip() {
    let action = Action::new("Enter Deadmines", ActionPayload::DungeonMarker(DungeonMarkerAction {
        dungeon_name: "The Deadmines".to_string(),
        entrance: wp("Westfall", -11000.0, 1500.0, 40.0),
    }));
    test_action_roundtrip(action, "DungeonMarker");
}

#[test]
fn test_action_death_skip_roundtrip() {
    let action = Action::new("Death Skip", ActionPayload::DeathSkip(DeathSkipAction {
        graveyard: wp("Elwynn Forest", -8900.0, -130.0, 80.0),
        spirit_healer: make_npc_ref(),
    }));
    test_action_roundtrip(action, "DeathSkip");
}

#[test]
fn test_action_with_retry_and_timeout_roundtrip() {
    let action = Action::new("Retry Action", ActionPayload::Wait(WaitAction { duration_ms: 1000 }))
        .with_retry(5, 2000)
        .with_timeout(60000)
        .with_condition(Condition::InCombat(true));
    test_action_roundtrip(action, "Retry+Timeout");
}

#[test]
fn test_action_disabled_roundtrip() {
    let action = Action::new("Disabled Action", ActionPayload::Wait(WaitAction { duration_ms: 1000 }))
        .disabled();
    test_action_roundtrip(action, "Disabled");
}

// ── Full ActionPayload enum round-trip ──────────────────────────────────────

#[test]
fn test_all_action_payload_variants_roundtrip() {
    let payloads = vec![
        ("PickupQuest", ActionPayload::PickupQuest(PickupQuestAction {
            quest: make_quest_ref(), npc: make_npc_ref(), auto_complete_previous: true,
        })),
        ("TurnInQuest", ActionPayload::TurnInQuest(TurnInQuestAction {
            quest: make_quest_ref(), npc: make_npc_ref(),
        })),
        ("GoTo", ActionPayload::GoTo(GoToAction {
            destination: wp("Elwynn", 1.0, 2.0, 3.0), arrival_radius: 5.0,
        })),
        ("RecordPath", ActionPayload::RecordPath(RecordPathAction {
            path: make_path(), smoothing: PathSmoothing::CatmullRom,
        })),
        ("Patrol", ActionPayload::Patrol(PatrolAction {
            path: make_path(), wait_at_waypoints: false, wait_duration_ms: 3000,
        })),
        ("Escort", ActionPayload::Escort(EscortAction {
            npc: make_npc_ref(), path: make_path(), protect: false,
        })),
        ("GrindArea", ActionPayload::GrindArea(GrindAreaAction {
            polygon: make_polygon(), targets: vec![make_creature_ref()],
            stop_condition: StopCondition::QuestComplete, loot: vec![],
        })),
        ("KillTarget", ActionPayload::KillTarget(KillTargetAction {
            targets: vec![make_creature_ref()], amount: Some(10),
        })),
        ("LootObject", ActionPayload::LootObject(LootObjectAction {
            objects: vec![make_game_object_ref()],
        })),
        ("TalkToNpc", ActionPayload::TalkToNpc(TalkToNpcAction {
            npc: make_npc_ref(), gossip_option: None,
        })),
        ("Vendor", ActionPayload::Vendor(VendorAction {
            vendor: make_vendor_entry(), repair: false, sell_gray: true, sell_white: false, buy: vec![],
        })),
        ("Repair", ActionPayload::Repair(RepairAction { vendor: make_vendor_entry() })),
        ("Train", ActionPayload::Train(TrainAction { trainer: make_npc_ref(), class: Class::Mage })),
        ("FlightPath", ActionPayload::FlightPath(FlightAction {
            from: FlightNode::new(1, "A"), to: FlightNode::new(2, "B"),
        })),
        ("Hearth", ActionPayload::Hearth(HearthAction {
            destination: HearthLocation::new("Dun Morogh", 197),
        })),
        ("Mailbox", ActionPayload::Mailbox(MailboxAction { mailbox: make_npc_ref() })),
        ("Bank", ActionPayload::Bank(BankAction { banker: make_npc_ref() })),
        ("UseItem", ActionPayload::UseItem(UseItemAction { item: make_item_ref(), target: None })),
        ("Wait", ActionPayload::Wait(WaitAction { duration_ms: 5000 })),
        ("SetVariable", ActionPayload::SetVariable(SetVariableAction {
            variable: "x".to_string(), value: VariableValue::Integer(42),
        })),
        ("Branch", ActionPayload::Branch(BranchAction {
            expression: Condition::InCombat(true), true_actions: vec![], false_actions: vec![],
        })),
        ("DungeonMarker", ActionPayload::DungeonMarker(DungeonMarkerAction {
            dungeon_name: "Ragefire Chasm".to_string(),
            entrance: wp("Orgrimmar", 1500.0, -4400.0, -20.0),
        })),
        ("DeathSkip", ActionPayload::DeathSkip(DeathSkipAction {
            graveyard: wp("Elwynn", -8900.0, -130.0, 80.0),
            spirit_healer: make_npc_ref(),
        })),
    ];
    for (label, payload) in &payloads {
        let action = Action::new(*label, payload.clone());
        let json = serde_json::to_string(&action).unwrap();
        let parsed: Action = serde_json::from_str(&json).unwrap();
        assert_eq!(action.payload, parsed.payload, "Payload '{}' failed roundtrip", label);
    }
}

// ── Operation ───────────────────────────────────────────────────────────────

#[test]
fn test_operation_roundtrip() {
    let op_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let dep_id = Uuid::parse_str("660e8400-e29b-41d4-a716-446655440000").unwrap();
    let goal_id = Uuid::parse_str("770e8400-e29b-41d4-a716-446655440000").unwrap();
    let mut op = Operation::new("Northshire Valley")
        .with_description("Complete the Northshire starting zone")
        .with_level_range(1, 5)
        .with_priority(100)
        .with_goals(vec![{
            let mut g = OperationGoal::required(
                "Complete quest chain",
                GoalType::CompleteQuestChain(vec![33, 34, 35, 36]),
                1.0,
            );
            g.id = goal_id;
            g
        }])
        .with_entry_conditions(vec![Condition::RaceIs(Race::Human)])
        .with_exit_conditions(
            ExitConditions::new()
                .with_success(vec![Condition::QuestRewarded(36)])
                .with_failure(vec![Condition::QuestFailed(33)])
                .with_abort(vec![Condition::Custom("DeathsExceed(3)".to_string())]),
        )
        .with_dependency(OperationDependency::requires(dep_id));
    op.id = op_id;
    op.enabled = true;
    op.tags = vec!["starting-zone".to_string()];
    op.optimization_policy = OptimizationPolicy::safe_low_level();
    op.completion_metrics = CompletionMetrics {
        target_duration_ms: Some(600000),
        target_xp: Some(10000),
        min_success_rate: Some(0.95),
        max_acceptable_deaths: Some(3),
    };
    op.variables = vec![
        Variable::bool("StartedQuests", false),
        Variable::integer("KillCount", 0),
    ];
    op.actions = vec![
        Action::new("Pickup", ActionPayload::PickupQuest(PickupQuestAction {
            quest: make_quest_ref(),
            npc: make_npc_ref(),
            auto_complete_previous: false,
        })),
        Action::new("Turn In", ActionPayload::TurnInQuest(TurnInQuestAction {
            quest: make_quest_ref(),
            npc: make_npc_ref(),
        })),
    ];

    let json = serde_json::to_string_pretty(&op).unwrap();
    let parsed: Operation = serde_json::from_str(&json).unwrap();
    assert_eq!(op, parsed);
    assert_eq!(parsed.name, "Northshire Valley");
    assert_eq!(parsed.goals.len(), 1);
    assert_eq!(parsed.entry_conditions.len(), 1);
    assert_eq!(parsed.exit_conditions.success.len(), 1);
    assert_eq!(parsed.exit_conditions.failure.len(), 1);
    assert_eq!(parsed.exit_conditions.abort.len(), 1);
    assert_eq!(parsed.dependencies.len(), 1);
    assert_eq!(parsed.actions.len(), 2);
    assert_eq!(parsed.variables.len(), 2);
}

#[test]
fn test_operation_minimal_roundtrip() {
    let op = Operation::new("Empty Op");
    let json = serde_json::to_string(&op).unwrap();
    let parsed: Operation = serde_json::from_str(&json).unwrap();
    assert_eq!(op.id, parsed.id);
    assert_eq!(op.name, parsed.name);
    assert!(parsed.actions.is_empty());
    assert!(parsed.goals.is_empty());
}

// ── Full Profile ────────────────────────────────────────────────────────────

#[test]
fn test_profile_roundtrip() {
    let profile_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
    let mut profile = Profile::new("Northshire Leveling", "SentinelCore Team")
        .with_faction(Faction::Alliance)
        .with_race(Race::Human)
        .with_class(Class::Warrior)
        .with_level_range(1, 60)
        .with_description("Alliance leveling profile for Northshire through Redridge");
    profile.profile_id = profile_id;
    profile.tags = vec!["leveling".to_string(), "alliance".to_string()];
    profile.metadata = Metadata {
        created_at: fixed_time(),
        updated_at: fixed_time(),
        editor_version: "0.1.0".to_string(),
        compiler_version: "0.1.0".to_string(),
        notes: Some("Example profile".to_string()),
        source: SourceType::Manual,
    };
    profile.settings = ProfileSettings {
        auto_vendor: true,
        auto_repair: true,
        auto_train: true,
        auto_loot: true,
        auto_accept: true,
        auto_turnin: true,
        use_flight_paths: true,
        allow_hearthstone: false,
        use_mailbox: true,
        death_skip: false,
        dry_run_enabled: false,
    };
    profile.variables = vec![
        Variable::bool("QuestStarted", false),
        Variable::integer("Gold", 100),
        Variable::float("XpRate", 1.0),
        Variable::string("CurrentZone", "Elwynn Forest"),
        Variable::position("Hearth", wp("Goldshire", -8800.0, -150.0, 80.0)),
    ];
    profile.npc_library = vec![make_npc_ref()];
    profile.quest_library = vec![make_quest_ref()];
    profile.vendor_library = vec![make_vendor_entry()];
    profile.blueprints = vec![
        BlueprintReference::new("quest-hub", "1.0.0")
            .with_param("vendor_id", serde_json::json!(1234)),
    ];
    profile.operations = vec![{
        let mut op = Operation::new("Northshire");
        op.actions = vec![
            Action::new("Pickup", ActionPayload::PickupQuest(PickupQuestAction {
                quest: make_quest_ref(), npc: make_npc_ref(), auto_complete_previous: false,
            })),
            Action::new("Turn In", ActionPayload::TurnInQuest(TurnInQuestAction {
                quest: make_quest_ref(), npc: make_npc_ref(),
            })),
        ];
        op
    }];

    let json = serde_json::to_string_pretty(&profile).unwrap();
    let parsed: Profile = serde_json::from_str(&json).unwrap();
    assert_eq!(profile, parsed);
    assert_eq!(parsed.name, "Northshire Leveling");
    assert_eq!(parsed.operations.len(), 1);
}

#[test]
fn test_profile_minimal_roundtrip() {
    let profile = Profile::new("Minimal", "Test");
    let json = serde_json::to_string_pretty(&profile).unwrap();
    let parsed: Profile = serde_json::from_str(&json).unwrap();
    assert_eq!(profile.name, parsed.name);
    assert_eq!(profile.author, parsed.author);
    assert!(parsed.operations.is_empty());
}

#[test]
fn test_profile_none_options_roundtrip() {
    let mut profile = Profile::new("Options Test", "Test");
    profile.race = None;
    profile.class = None;
    let json = serde_json::to_string_pretty(&profile).unwrap();
    let parsed: Profile = serde_json::from_str(&json).unwrap();
    assert_eq!(profile.race, parsed.race);
    assert_eq!(profile.class, parsed.class);
}

// ── Sample profile file round-trip ──────────────────────────────────────────

#[test]
fn test_northshire_example_roundtrip() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("profiles")
        .join("northshire_example.json");
    let content = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("Failed to read {}: {}", path.display(), e));
    let profile: Profile = serde_json::from_str(&content)
        .unwrap_or_else(|e| panic!("Failed to deserialize {}: {}", path.display(), e));

    // Serialize back
    let json = serde_json::to_string_pretty(&profile).unwrap();
    // Deserialize again
    let roundtripped: Profile = serde_json::from_str(&json).unwrap();

    // Field-by-field
    assert_eq!(profile.schema_version, roundtripped.schema_version);
    assert_eq!(profile.profile_id, roundtripped.profile_id);
    assert_eq!(profile.name, roundtripped.name);
    assert_eq!(profile.author, roundtripped.author);
    assert_eq!(profile.description, roundtripped.description);
    assert_eq!(profile.game, roundtripped.game);
    assert_eq!(profile.faction, roundtripped.faction);
    assert_eq!(profile.race, roundtripped.race);
    assert_eq!(profile.class, roundtripped.class);
    assert_eq!(profile.level_range, roundtripped.level_range);
    assert_eq!(profile.tags, roundtripped.tags);
    assert_eq!(profile.settings, roundtripped.settings);
    assert_eq!(profile.variables.len(), roundtripped.variables.len());
    assert_eq!(profile.npc_library.len(), roundtripped.npc_library.len());
    assert_eq!(profile.quest_library.len(), roundtripped.quest_library.len());
    assert_eq!(profile.vendor_library.len(), roundtripped.vendor_library.len());
    assert_eq!(profile.blueprints.len(), roundtripped.blueprints.len());
    assert_eq!(profile.operations.len(), roundtripped.operations.len());

    for (orig, rt) in profile.operations.iter().zip(roundtripped.operations.iter()) {
        assert_eq!(orig.id, rt.id);
        assert_eq!(orig.name, rt.name);
        assert_eq!(orig.actions.len(), rt.actions.len());
        for (a, b) in orig.actions.iter().zip(rt.actions.iter()) {
            assert_eq!(a.id, b.id);
            assert_eq!(a.name, b.name);
            assert_eq!(a.payload, b.payload);
        }
    }
}
