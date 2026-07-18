//! Tests for sentinel-schema

use sentinel_schema::prelude::*;
use sentinel_schema::{
    OptimizationPolicy, DependencyType, OperationGoal, ExitConditions, 
    OperationDependency, BlueprintParameter, ParameterType, ParameterValue,
};
use uuid::Uuid;

#[test]
fn test_profile_roundtrip() {
    let profile = Profile::new("Test Profile", "Tester")
        .with_faction(Faction::Alliance)
        .with_race(Race::Human)
        .with_class(Class::Warrior)
        .with_level_range(1, 60)
        .with_description("A test profile");
    
    let json = serde_json::to_string_pretty(&profile).unwrap();
    let parsed: Profile = serde_json::from_str(&json).unwrap();
    
    assert_eq!(profile.name, parsed.name);
    assert_eq!(profile.author, parsed.author);
    assert_eq!(profile.faction, parsed.faction);
    assert_eq!(profile.race, parsed.race);
    assert_eq!(profile.class, parsed.class);
    assert_eq!(profile.level_range, parsed.level_range);
}

#[test]
fn test_operation_roundtrip() {
    let op = Operation::new("Northshire")
        .with_description("Starting zone operations")
        .with_level_range(1, 5)
        .with_priority(100)
        .with_goals(vec![
            OperationGoal::required("Complete quest chain", GoalType::CompleteQuestChain(vec![33, 34, 35, 36]), 1.0),
        ])
        .with_entry_conditions(vec![
            Condition::RaceIs(Race::Human),
            Condition::LevelBelow(6),
        ])
        .with_exit_conditions(ExitConditions::new()
            .with_success(vec![
                Condition::QuestRewarded(33),
                Condition::QuestRewarded(34),
                Condition::QuestRewarded(35),
                Condition::QuestRewarded(36),
            ])
        );
    
    let json = serde_json::to_string_pretty(&op).unwrap();
    let parsed: Operation = serde_json::from_str(&json).unwrap();
    
    assert_eq!(op.name, parsed.name);
    assert_eq!(op.description, parsed.description);
    assert_eq!(op.level_range, parsed.level_range);
    assert_eq!(op.priority, parsed.priority);
    assert_eq!(op.goals.len(), parsed.goals.len());
    assert_eq!(op.entry_conditions.len(), parsed.entry_conditions.len());
    assert_eq!(op.exit_conditions.success.len(), parsed.exit_conditions.success.len());
}

#[test]
fn test_retry_policy() {
    let default = RetryPolicy::default();
    assert_eq!(default.retries, 3);
    assert_eq!(default.delay_ms, 1000);
    
    let none = RetryPolicy::none();
    assert_eq!(none.retries, 0);
    assert_eq!(none.delay_ms, 0);
    
    let aggressive = RetryPolicy::aggressive();
    assert_eq!(aggressive.retries, 5);
    assert_eq!(aggressive.delay_ms, 500);
    
    let conservative = RetryPolicy::conservative();
    assert_eq!(conservative.retries, 2);
    assert_eq!(conservative.delay_ms, 5000);
}

#[test]
fn test_optimization_policy_presets() {
    let safe = OptimizationPolicy::safe_low_level();
    assert_eq!(safe.risk_weight, 0.1);
    assert!(safe.allow_reordering);
    assert_eq!(safe.max_deaths, Some(3));
    
    let dangerous = OptimizationPolicy::dangerous_high_level();
    assert_eq!(dangerous.risk_weight, 0.8);
    assert!(!dangerous.allow_reordering);
    assert_eq!(dangerous.max_deaths, Some(1));
}

#[test]
fn test_condition_serialization() {
    let conditions = vec![
        Condition::QuestAccepted(33),
        Condition::QuestCompleted(34),
        Condition::LevelAtLeast(5),
        Condition::VariableEquals("HasItem".to_string(), VariableValue::Bool(true)),
        Condition::OperationCompleted(Uuid::new_v4()),
        Condition::RaceIs(Race::Human),
        Condition::ZoneEntered("Elwynn Forest".to_string()),
    ];
    
    let json = serde_json::to_string_pretty(&conditions).unwrap();
    let parsed: Vec<Condition> = serde_json::from_str(&json).unwrap();
    
    assert_eq!(conditions.len(), parsed.len());
    for (orig, parsed) in conditions.iter().zip(parsed.iter()) {
        assert_eq!(orig, parsed);
    }
}

#[test]
fn test_exit_conditions() {
    let exit = ExitConditions::new()
        .with_success(vec![Condition::QuestRewarded(33), Condition::QuestRewarded(34)])
        .with_failure(vec![Condition::QuestFailed(33)])
        .with_abort(vec![Condition::Custom("DeathsExceed(3)".to_string())]);
    
    let json = serde_json::to_string_pretty(&exit).unwrap();
    let parsed: ExitConditions = serde_json::from_str(&json).unwrap();
    
    assert_eq!(exit.success.len(), parsed.success.len());
    assert_eq!(exit.failure.len(), parsed.failure.len());
    assert_eq!(exit.abort.len(), parsed.abort.len());
}

#[test]
fn test_operation_goal() {
    let required = OperationGoal::required("Complete chain", GoalType::CompleteQuestChain(vec![33, 34, 35, 36]), 1.0);
    assert!(required.required);
    assert_eq!(required.weight, 1.0);
    
    let optional = OperationGoal::optional("Reach level 5", GoalType::ReachLevel(5), 0.4);
    assert!(!optional.required);
    assert_eq!(optional.weight, 0.4);
}

#[test]
fn test_operation_dependency() {
    let id = Uuid::new_v4();
    let req = OperationDependency::requires(id);
    assert_eq!(req.operation_id, id);
    assert_eq!(req.relationship, DependencyType::Requires);
    
    let soft = OperationDependency::soft_prefers(id);
    assert_eq!(soft.relationship, DependencyType::SoftPrefers);
    
    let excludes = OperationDependency::excludes_with(id);
    assert_eq!(excludes.relationship, DependencyType::ExcludesWith);
    
    let unlocks = OperationDependency::unlocks_after(id);
    assert_eq!(unlocks.relationship, DependencyType::UnlocksAfter);
}

#[test]
fn test_geometry() {
    let wp1 = Waypoint::new(0, "Elwynn Forest", -8912.5, -132.3, 83.2, 5.0);
    let wp2 = Waypoint::new(0, "Elwynn Forest", -8920.0, -140.0, 82.5, 5.0);
    
    let dist = wp1.distance_3d(&wp2);
    assert!(dist > 0.0);
    
    let path = Path::new(vec![wp1, wp2]);
    assert_eq!(path.len(), 2);
    assert!(!path.is_empty());
    assert!((path.len() - 2) == 0); // len() returns vertex count
    
    let poly = Polygon::new(vec![
        Waypoint::new(0, "Elwynn Forest", -8912.0, -132.0, 83.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8920.0, -132.0, 83.0, 5.0),
        Waypoint::new(0, "Elwynn Forest", -8920.0, -140.0, 83.0, 5.0),
    ]);
    assert!(poly.is_valid());
    assert_eq!(poly.vertex_count(), 3);
    
    let centroid = poly.centroid().unwrap();
    assert!(centroid.x > -8920.0 && centroid.x < -8912.0);
    assert!(centroid.y > -140.0 && centroid.y < -132.0);
    assert!(centroid.z > 82.0 && centroid.z < 84.0);
}

#[test]
fn test_variable_values() {
    let vars = vec![
        Variable::bool("HasFood", true),
        Variable::integer("Gold", 1000),
        Variable::float("XpRate", 1.5),
        Variable::string("CurrentZone", "Elwynn Forest"),
        Variable::position("HearthPos", Waypoint::new(0, "Goldshire", -8800.0, -150.0, 80.0, 10.0)),
        Variable::quest_id("ActiveQuest", 33),
        Variable::npc_id("TargetNpc", 197),
    ];
    
    let json = serde_json::to_string_pretty(&vars).unwrap();
    let parsed: Vec<Variable> = serde_json::from_str(&json).unwrap();
    
    assert_eq!(vars.len(), parsed.len());
    for (orig, parsed) in vars.iter().zip(parsed.iter()) {
        assert_eq!(orig.name, parsed.name);
        assert_eq!(orig.value, parsed.value);
    }
}

#[test]
fn test_blueprint_parameter() {
    let param = BlueprintParameter::required("QuestGiver", ParameterType::Npc, "The NPC giving the quest");
    assert!(param.required);
    assert_eq!(param.param_type, ParameterType::Npc);
    
    let optional = BlueprintParameter::optional("Trainer", ParameterType::Trainer, "Class trainer", ParameterValue::Boolean(false));
    assert!(!optional.required);
    assert_eq!(optional.param_type, ParameterType::Trainer);
}