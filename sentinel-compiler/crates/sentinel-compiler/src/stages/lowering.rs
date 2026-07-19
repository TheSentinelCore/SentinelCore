//! Stage 7: Lowering — Convert optimized authoring structures into an
//! immutable Runtime Execution Profile.
//!
//! See: docs/adr/008-compilation-pipeline.md §10

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use sentinel_schema::Profile;
use uuid::Uuid;

use crate::runtime_profile::{ResolvedActionPayload, RuntimeAction, RuntimeOperation, RuntimeProfile};
use crate::stages::optimization::OptimizedProfile;

/// Stage 7: Lower the optimized profile into a RuntimeProfile.
pub fn lower(
    optimized: &OptimizedProfile,
    source_profile_id: Uuid,
) -> (RuntimeProfile, String) {
    let source_profile_hash = compute_profile_hash(&optimized.profile);

    let operations: Vec<RuntimeOperation> = optimized
        .profile
        .operations
        .iter()
        .map(|op| RuntimeOperation {
            id: op.id,
            name: op.name.clone(),
            entry_conditions: op.entry_conditions.clone(),
            exit_conditions: op.exit_conditions.clone(),
            goals: op.goals.clone(),
            actions: op
                .actions
                .iter()
                .map(|action| RuntimeAction {
                    id: action.id,
                    payload: ResolvedActionPayload(action.payload.clone()),
                    retry_policy: action.retry_policy.clone(),
                    timeout_ms: action.timeout_ms,
                    generated_from: None, // Blueprint expansion would populate this
                })
                .collect(),
        })
        .collect();

    let profile = RuntimeProfile {
        schema_version: optimized.profile.schema_version.clone(),
        compiled_at: chrono::Utc::now(),
        compiler_version: env!("CARGO_PKG_VERSION").to_string(),
        source_profile_id,
        source_profile_hash: source_profile_hash.clone(),
        operations,
    };

    (profile, source_profile_hash)
}

/// Compute a deterministic hash of a Profile for cache invalidation.
fn compute_profile_hash(profile: &Profile) -> String {
    let mut hasher = DefaultHasher::new();
    profile.name.hash(&mut hasher);
    profile.author.hash(&mut hasher);
    profile.schema_version.hash(&mut hasher);
    profile.faction.hash(&mut hasher);
    profile.operations.len().hash(&mut hasher);
    for op in &profile.operations {
        op.id.hash(&mut hasher);
        op.name.hash(&mut hasher);
        op.actions.len().hash(&mut hasher);
        for action in &op.actions {
            action.id.hash(&mut hasher);
        }
    }
    format!("{:016x}", hasher.finish())
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::action::*;
    use sentinel_schema::{Action, Operation, Profile, Waypoint};

    fn test_waypoint(x: f32, y: f32) -> Waypoint {
        Waypoint::new(0, "Test", x, y, 0.0, 5.0)
    }

    #[test]
    fn test_lower_empty_profile() {
        let profile = Profile::new("Empty", "Test");
        let optimized = crate::stages::optimization::OptimizedProfile {
            profile: profile.clone(),
            optimizations_applied: vec![],
        };

        let (result, _hash) = lower(&optimized, profile.profile_id);
        assert_eq!(result.operations.len(), 0);
        assert_eq!(result.source_profile_id, profile.profile_id);
        assert_eq!(result.schema_version, "1.0.0");
    }

    #[test]
    fn test_lower_preserves_operations() {
        let mut profile = Profile::new("Test", "Agent");
        let mut op1 = Operation::new("Op1");
        op1.actions = vec![Action::new(
            "Wait",
            ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
        )];
        let mut op2 = Operation::new("Op2");
        op2.actions = vec![Action::new(
            "WaitLonger",
            ActionPayload::Wait(WaitAction { duration_ms: 5000 }),
        )];
        profile.operations.push(op1);
        profile.operations.push(op2);

        let optimized = crate::stages::optimization::OptimizedProfile {
            profile,
            optimizations_applied: vec![],
        };

        let (result, _hash) = lower(&optimized, optimized.profile.profile_id);
        assert_eq!(result.operations.len(), 2);
        assert_eq!(result.operations[0].name, "Op1");
        assert_eq!(result.operations[1].name, "Op2");
    }

    #[test]
    fn test_lower_actions_converted() {
        let mut profile = Profile::new("Test", "Agent");
        let mut op = Operation::new("Op");
        op.actions = vec![
            Action::new(
                "Wait",
                ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
            ),
            Action::new(
                "GoTo",
                ActionPayload::GoTo(GoToAction {
                    destination: test_waypoint(100.0, 200.0),
                    arrival_radius: 5.0,
                }),
            ),
        ];
        profile.operations.push(op);

        let optimized = crate::stages::optimization::OptimizedProfile {
            profile,
            optimizations_applied: vec![],
        };

        let (result, _hash) = lower(&optimized, optimized.profile.profile_id);
        let action = &result.operations[0].actions[0];
        assert_eq!(action.timeout_ms, 30000); // default timeout
        assert_eq!(action.retry_policy.retries, 3); // default retry
    }

    #[test]
    fn test_lower_metadata_set() {
        let profile = Profile::new("Test", "Agent");
        let optimized = crate::stages::optimization::OptimizedProfile {
            profile,
            optimizations_applied: vec![],
        };

        let (result, _hash) = lower(&optimized, optimized.profile.profile_id);
        assert!(!result.compiler_version.is_empty());
        assert!(!result.source_profile_hash.is_empty());
        // compiled_at should be within the last few seconds
        let age = chrono::Utc::now() - result.compiled_at;
        assert!(
            age.num_seconds() < 10,
            "compiled_at should be very recent"
        );
    }

    #[test]
    fn test_lower_goals_preserved() {
        let mut profile = Profile::new("Test", "Agent");
        let mut op = Operation::new("Op");
        op.goals.push(sentinel_schema::condition::OperationGoal::required(
            "Kill 10 wolves",
            sentinel_schema::enums::GoalType::CompleteQuest(1),
            1.0,
        ));
        profile.operations.push(op);

        let optimized = crate::stages::optimization::OptimizedProfile {
            profile,
            optimizations_applied: vec![],
        };

        let (result, _hash) = lower(&optimized, optimized.profile.profile_id);
        assert_eq!(result.operations[0].goals.len(), 1);
        assert_eq!(result.operations[0].goals[0].description, "Kill 10 wolves");
        assert!(result.operations[0].goals[0].required);
    }

    #[test]
    fn test_lower_entry_conditions_preserved() {
        use sentinel_schema::Condition;
        let mut profile = Profile::new("Test", "Agent");
        let mut op = Operation::new("Op");
        op.entry_conditions
            .push(Condition::LevelAtLeast(10));
        profile.operations.push(op);

        let optimized = crate::stages::optimization::OptimizedProfile {
            profile,
            optimizations_applied: vec![],
        };

        let (result, _hash) = lower(&optimized, optimized.profile.profile_id);
        assert!(result.operations[0]
            .entry_conditions
            .contains(&Condition::LevelAtLeast(10)));
    }

    #[test]
    fn test_hash_is_deterministic() {
        let profile = Profile::new("Test", "Agent");
        let hash1 = compute_profile_hash(&profile);
        let hash2 = compute_profile_hash(&profile);
        assert_eq!(hash1, hash2, "Hash should be deterministic");
    }

    #[test]
    fn test_hash_differs_for_different_profiles() {
        let p1 = Profile::new("ProfileA", "Author");
        let p2 = Profile::new("ProfileB", "Author");
        let h1 = compute_profile_hash(&p1);
        let h2 = compute_profile_hash(&p2);
        assert_ne!(h1, h2, "Different profiles should have different hashes");
    }
}
