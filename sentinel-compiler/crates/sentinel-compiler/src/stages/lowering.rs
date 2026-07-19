//! Stage 7: Lowering — Convert optimized authoring structures into an
//! immutable Runtime Execution Profile.
//!
//! See: docs/adr/008-compilation-pipeline.md §10

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use sentinel_schema::Profile;
use uuid::Uuid;

use crate::diagnostics::{Diagnostic, Stage};
use crate::runtime_profile::{ResolvedActionPayload, RuntimeAction, RuntimeDiagnostics, RuntimeOperation, RuntimeProfile};
use crate::stages::optimization::OptimizedProfile;

/// C-7xxx error codes for Stage 7
pub mod error_codes {
    pub const MISSING_PROFILE_ID: &str = "C-7001";
    pub const MISSING_OPERATIONS: &str = "C-7002";
    pub const INVALID_OPERATION: &str = "C-7003";
    pub const INVALID_ACTION: &str = "C-7004";
    pub const MISSING_ACTION_ID: &str = "C-7005";
}

/// Stage 7 result
#[derive(Debug, Clone)]
pub struct LoweringResult {
    pub runtime_profile: RuntimeProfile,
    pub source_profile_hash: String,
    pub diagnostics: Vec<Diagnostic>,
}

/// Stage 7: Lower the optimized profile into a RuntimeProfile.
pub fn lower(optimized: &OptimizedProfile, source_profile_id: Uuid) -> LoweringResult {
    let mut diagnostics = Vec::new();
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
                    generated_from: None, // Actions don't have generated_from, reserved for blueprint-generated actions
                })
                .collect(),
        })
        .collect();

    let runtime_profile = RuntimeProfile {
        schema_version: optimized.profile.schema_version.clone(),
        compiled_at: chrono::Utc::now(),
        compiler_version: env!("CARGO_PKG_VERSION").to_string(),
        source_profile_id,
        source_profile_hash: source_profile_hash.clone(),
        operations,
        diagnostics: RuntimeDiagnostics {
            errors: vec![],
            warnings: vec![],
        },
    };

    // Emit info for successful lowering
    diagnostics.push(Diagnostic::info(
        "C-7001",
        Stage::Lowering,
        format!(
            "Lowered {} operations to RuntimeProfile",
            runtime_profile.operations.len()
        ),
    ));

    LoweringResult {
        runtime_profile,
        source_profile_hash,
        diagnostics,
    }
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

        let result = lower(&optimized, profile.profile_id);
        assert_eq!(result.runtime_profile.operations.len(), 0);
        assert_eq!(result.runtime_profile.source_profile_id, profile.profile_id);
        assert_eq!(result.runtime_profile.schema_version, "1.0.0");
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

        let result = lower(&optimized, optimized.profile.profile_id);
        assert_eq!(result.runtime_profile.operations.len(), 2);
        assert_eq!(result.runtime_profile.operations[0].name, "Op1");
        assert_eq!(result.runtime_profile.operations[1].name, "Op2");
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

        let result = lower(&optimized, optimized.profile.profile_id);
        let action = &result.runtime_profile.operations[0].actions[0];
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

        let result = lower(&optimized, optimized.profile.profile_id);
        assert!(!result.runtime_profile.compiler_version.is_empty());
        assert!(!result.source_profile_hash.is_empty());
        // compiled_at should be within the last few seconds
        let age = chrono::Utc::now() - result.runtime_profile.compiled_at;
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

        let result = lower(&optimized, optimized.profile.profile_id);
        assert_eq!(result.runtime_profile.operations[0].goals.len(), 1);
        assert_eq!(result.runtime_profile.operations[0].goals[0].description, "Kill 10 wolves");
        assert!(result.runtime_profile.operations[0].goals[0].required);
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

        let result = lower(&optimized, optimized.profile.profile_id);
        assert!(result.runtime_profile.operations[0]
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

    #[test]
    fn test_c7xxx_error_codes() {
        assert_eq!(error_codes::MISSING_PROFILE_ID, "C-7001");
        assert_eq!(error_codes::MISSING_OPERATIONS, "C-7002");
        assert_eq!(error_codes::INVALID_OPERATION, "C-7003");
        assert_eq!(error_codes::INVALID_ACTION, "C-7004");
        assert_eq!(error_codes::MISSING_ACTION_ID, "C-7005");
    }

    #[test]
    fn test_diagnostics_have_stage_attribution() {
        let profile = Profile::new("Test", "Agent");
        let optimized = crate::stages::optimization::OptimizedProfile {
            profile,
            optimizations_applied: vec![],
        };

        let result = lower(&optimized, optimized.profile.profile_id);

        // Should have at least one diagnostic
        assert!(!result.diagnostics.is_empty());

        // All diagnostics should have Lowering stage
        for diag in &result.diagnostics {
            assert_eq!(diag.stage, Stage::Lowering);
        }
    }
}