//! Incremental compilation — only re-runs stages for dirty Operations.
//!
//! On first compile, runs the full 7-stage pipeline and creates a
//! [`DirtyTracker`] with all Operations marked `New`. On subsequent
//! compiles, computes the diff between the old and new [`Profile`],
//! updates the tracker, and skips stages whose inputs haven't changed.

use std::collections::HashMap;

use sentinel_schema::Profile;
use uuid::Uuid;

use crate::diagnostics::Diagnostic;
use crate::dirty::{DirtyTracker, StageFlags};
use crate::query_client::QueryClient;
use crate::runtime_profile::{RuntimeAction, RuntimeOperation, RuntimeProfile};
use crate::stages;

/// Incremental compile — only re-runs stages for dirty Operations.
///
/// # First compile
///
/// When `old_profile` is `None`, runs the full pipeline and initialises
/// `tracker` with every Operation marked `New`.
///
/// # Subsequent compiles
///
/// When `old_profile` is `Some(prev)`, computes the diff between `profile`
/// and `prev`, updates `tracker` accordingly, and skips stages whose
/// inputs haven't changed.
pub fn compile_incremental(
    profile: &Profile,
    old_profile: Option<&Profile>,
    query_client: &dyn QueryClient,
    tracker: &mut DirtyTracker,
) -> Result<RuntimeProfile, Vec<Diagnostic>> {
    // First compile: run full pipeline, initialise tracker
    let Some(old) = old_profile else {
        *tracker = DirtyTracker::from_profile(profile);
        let result = crate::compile(profile.clone(), query_client);
        if result.is_ok() {
            tracker.clear();
        }
        return result;
    };

    // Compute diff between old and new profile
    update_tracker(profile, old, tracker);

    // Collect operation IDs that need re-processing
    let _dirty_ids = tracker.dirty_operation_ids();
    let _deleted_ids = tracker.deleted_operation_ids();

    // ── Stage 1: Structural Validation ──────────────────────────────────
    let _structural_warnings = if tracker.can_skip_stage(StageFlags {
        stages_1_3: true,
        ..StageFlags::all()
    }) {
        Vec::new()
    } else {
        stages::structural::validate(profile)?
    };

    // ── Stage 2: Reference Resolution ───────────────────────────────────
    let resolved = if tracker.can_skip_stage(StageFlags {
        stages_1_3: true,
        ..StageFlags::all()
    }) {
        stages::resolved_profile_from_profile(profile)
    } else {
        stages::resolution::resolve(profile, query_client)?
    };

    // ── Stage 3: Blueprint Expansion ────────────────────────────────────
    let _expanded = if tracker.can_skip_stage(StageFlags {
        stages_1_3: true,
        ..StageFlags::all()
    }) {
        stages::expanded_profile_from_resolved(&resolved)
    } else {
        stages::expansion::expand_blueprints(&resolved, query_client)?
    };

    // ── Stage 4: Dependency Resolution ──────────────────────────────────
    let dep_order = if tracker.can_skip_stage(StageFlags {
        stage_4: true,
        ..StageFlags::all()
    }) {
        stages::empty_dependency_order()
    } else {
        stages::dependency::resolve_dependencies(profile)?
    };

    // ── Stage 5: Goal Coverage ──────────────────────────────────────────
    let _goal_diagnostics = if tracker.can_skip_stage(StageFlags {
        stage_5: true,
        ..StageFlags::all()
    }) {
        Vec::new()
    } else {
        stages::goal_coverage::validate_goals(profile)?
    };

    // ── Stage 6: Cross-Operation Optimization ───────────────────────────
    let optimized = if tracker.can_skip_stage(StageFlags {
        stage_6: true,
        ..StageFlags::all()
    }) {
        stages::optimized_profile_from_profile(profile, &dep_order)?
    } else {
        stages::optimization::optimize(profile, &dep_order)?
    };

    // ── Stage 7: Lowering ───────────────────────────────────────────────
    let runtime_profile = if tracker.can_skip_stage(StageFlags {
        stage_7: true,
        ..StageFlags::all()
    }) {
        // Skip lowering — produce a RuntimeProfile from the pass-through
        // OptimizedProfile directly.
        let profile = RuntimeProfile {
            schema_version: optimized.profile.schema_version.clone(),
            compiled_at: chrono::Utc::now(),
            compiler_version: env!("CARGO_PKG_VERSION").to_string(),
            source_profile_id: profile.profile_id,
            source_profile_hash: String::new(),
            operations: optimized
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
                        .map(|a| RuntimeAction {
                            id: a.id,
                            payload: crate::runtime_profile::ResolvedActionPayload(
                                a.payload.clone(),
                            ),
                            retry_policy: a.retry_policy.clone(),
                            timeout_ms: a.timeout_ms,
                            generated_from: None,
                        })
                        .collect(),
                })
                .collect(),
            diagnostics: crate::runtime_profile::RuntimeDiagnostics {
                errors: vec![],
                warnings: vec![],
            },
    };
        profile
    } else {
        stages::lowering::lower(&optimized, profile.profile_id).runtime_profile
    };

    // Clear tracker after successful compile
    tracker.clear();

    Ok(runtime_profile)
}

/// Compare two Profiles and update the DirtyTracker accordingly.
///
/// Scans for:
/// - New Operations (present in `new` but not `old`) → `New`
/// - Removed Operations (present in `old` but not `new`) → `Deleted`
/// - Modified Operations (present in both but with different content) → `Modified`
/// - Structural changes (dependencies, priorities, entry conditions) → `structure_dirty`
pub fn update_tracker(new: &Profile, old: &Profile, tracker: &mut DirtyTracker) {
    // Build lookup maps for old and new
    let old_ops: HashMap<Uuid, &sentinel_schema::Operation> =
        old.operations.iter().map(|op| (op.id, op)).collect();
    let new_ops: HashMap<Uuid, &sentinel_schema::Operation> =
        new.operations.iter().map(|op| (op.id, op)).collect();

    // Find removed operations
    for (id, _old_op) in &old_ops {
        if !new_ops.contains_key(id) {
            tracker.mark_deleted(*id);
        }
    }

    // Find new and modified operations
    for (id, new_op) in &new_ops {
        match old_ops.get(id) {
            None => {
                // Truly new operation (not in old profile)
                tracker.mark_new(*id);
            }
            Some(old_op) => {
                // Check if the operation content changed
                if operation_content_changed(old_op, new_op) {
                    tracker.mark_modified(*id);
                }
                // Check structural changes
                if structure_changed(old_op, new_op) {
                    tracker.mark_structure_dirty();
                }
            }
        }
    }

    // Check for global structural changes
    check_global_structure_change(new, old, tracker);
}

/// Detect global structural changes: added/removed dependencies between
/// operations, or changes to the dependency graph structure.
fn check_global_structure_change(new: &Profile, old: &Profile, tracker: &mut DirtyTracker) {
    let old_dep_count: usize = old
        .operations
        .iter()
        .map(|op| op.dependencies.len())
        .sum();
    let new_dep_count: usize = new
        .operations
        .iter()
        .map(|op| op.dependencies.len())
        .sum();

    if old_dep_count != new_dep_count {
        tracker.mark_structure_dirty();
        return;
    }

    // Check if any dependency changed its target or relationship
    for new_op in &new.operations {
        if let Some(old_op) = old.operations.iter().find(|o| o.id == new_op.id) {
            if structure_changed(old_op, new_op) {
                tracker.mark_structure_dirty();
                return;
            }
        }
    }
}

/// Check whether a single Operation's content (actions, goals) changed.
fn operation_content_changed(
    old: &sentinel_schema::Operation,
    new: &sentinel_schema::Operation,
) -> bool {
    // Action count changed
    if old.actions.len() != new.actions.len() {
        return true;
    }
    // Action IDs changed (order-sensitive)
    for (a, b) in old.actions.iter().zip(new.actions.iter()) {
        if a.id != b.id {
            return true;
        }
    }
    // Goal count changed
    if old.goals.len() != new.goals.len() {
        return true;
    }
    // Variable count changed
    if old.variables.len() != new.variables.len() {
        return true;
    }
    // Sub-operations changed
    if old.sub_operations.len() != new.sub_operations.len() {
        return true;
    }
    for (a, b) in old.sub_operations.iter().zip(new.sub_operations.iter()) {
        if a != b {
            return true;
        }
    }
    false
}

/// Check whether structural metadata (dependencies, priority, entry conditions) changed.
fn structure_changed(
    old: &sentinel_schema::Operation,
    new: &sentinel_schema::Operation,
) -> bool {
    // Priority changed
    if old.priority != new.priority {
        return true;
    }
    // Dependency count changed
    if old.dependencies.len() != new.dependencies.len() {
        return true;
    }
    // Dependency details changed
    for (a, b) in old.dependencies.iter().zip(new.dependencies.iter()) {
        if a.operation_id != b.operation_id || a.relationship != b.relationship {
            return true;
        }
    }
    // Entry conditions changed
    if old.entry_conditions.len() != new.entry_conditions.len() {
        return true;
    }
    false
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::{
        action::*,
        condition::OperationDependency,
        Action, Operation,
    };
    use crate::dirty::DirtyState;

    // -----------------------------------------------------------------------
    // Mock QueryClient
    // -----------------------------------------------------------------------

    struct MockQueryClient;

    impl QueryClient for MockQueryClient {
        fn get_npc(&self, _entry: u32) -> anyhow::Result<sentinel_schema::NpcReference> {
            Err(anyhow::anyhow!("not implemented for incremental tests"))
        }

        fn get_quest(&self, _id: u32) -> anyhow::Result<sentinel_schema::QuestReference> {
            Err(anyhow::anyhow!("not implemented for incremental tests"))
        }

        fn get_vendor(&self, _entry: u32) -> anyhow::Result<sentinel_schema::VendorEntry> {
            Err(anyhow::anyhow!("not implemented for incremental tests"))
        }

        fn get_creature(&self, _entry: u32) -> anyhow::Result<sentinel_schema::CreatureReference> {
            Err(anyhow::anyhow!("not implemented for incremental tests"))
        }

        fn search_npcs(&self, _query: &str) -> anyhow::Result<Vec<sentinel_schema::NpcReference>> {
            Ok(Vec::new())
        }

        fn get_route(
            &self,
            _from_map: u32,
            _from_x: f32,
            _from_y: f32,
            _to_map: u32,
            _to_x: f32,
            _to_y: f32,
        ) -> anyhow::Result<Vec<(f32, f32, f32)>> {
            Ok(Vec::new())
        }
    }

    // -----------------------------------------------------------------------
    // update_tracker tests
    // -----------------------------------------------------------------------

    #[test]
    fn test_tracker_diff_added_op() {
        let mut old_profile = Profile::new("Test", "Agent");
        old_profile.operations = vec![Operation::new("A")];

        let mut new_profile = Profile::new("Test", "Agent");
        new_profile.operations = vec![Operation::new("A"), Operation::new("B")];
        let new_op_id = new_profile.operations[1].id;

        let mut tracker = DirtyTracker::new();
        update_tracker(&new_profile, &old_profile, &mut tracker);

        // The new op should be New
        assert_eq!(
            tracker.get_state(new_op_id),
            Some(DirtyState::New),
            "New operation should be in New state"
        );
    }

    #[test]
    fn test_tracker_diff_removed_op() {
        let mut old_profile = Profile::new("Test", "Agent");
        let op_b = Operation::new("B");
        let b_id = op_b.id;
        old_profile.operations = vec![Operation::new("A"), op_b];

        let mut new_profile = Profile::new("Test", "Agent");
        new_profile.operations = vec![Operation::new("A")];

        let mut tracker = DirtyTracker::new();
        update_tracker(&new_profile, &old_profile, &mut tracker);

        assert_eq!(
            tracker.get_state(b_id),
            Some(DirtyState::Deleted),
            "Removed operation should be Deleted"
        );
    }

    #[test]
    fn test_tracker_diff_modified_op() {
        let id_a = Uuid::new_v4();

        let mut old_op = Operation::new("A");
        old_op.id = id_a;
        old_op.actions = vec![Action::new(
            "Wait",
            ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
        )];

        let mut new_op = Operation::new("A");
        new_op.id = id_a;
        new_op.actions = vec![
            Action::new("Wait", ActionPayload::Wait(WaitAction { duration_ms: 1000 })),
            Action::new("Wait2", ActionPayload::Wait(WaitAction { duration_ms: 2000 })),
        ];

        let mut old_profile = Profile::new("Test", "Agent");
        old_profile.operations = vec![old_op];
        let mut new_profile = Profile::new("Test", "Agent");
        new_profile.operations = vec![new_op];

        let mut tracker = DirtyTracker::new();
        update_tracker(&new_profile, &old_profile, &mut tracker);

        assert_eq!(
            tracker.get_state(id_a),
            Some(DirtyState::Modified),
            "Modified operation should be in Modified state"
        );
    }

    #[test]
    fn test_tracker_diff_structure_change() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut old_op_a = Operation::new("A");
        old_op_a.id = id_a;
        old_op_a.priority = 100;
        let mut old_op_b = Operation::new("B");
        old_op_b.id = id_b;

        let mut new_op_a = Operation::new("A");
        new_op_a.id = id_a;
        new_op_a.priority = 200; // Changed priority!
        new_op_a.dependencies = vec![OperationDependency::requires(id_b)];
        let mut new_op_b = Operation::new("B");
        new_op_b.id = id_b;

        let mut old_profile = Profile::new("Test", "Agent");
        old_profile.operations = vec![old_op_a, old_op_b];
        let mut new_profile = Profile::new("Test", "Agent");
        new_profile.operations = vec![new_op_a, new_op_b];

        let mut tracker = DirtyTracker::new();
        update_tracker(&new_profile, &old_profile, &mut tracker);

        assert!(
            tracker.is_structure_dirty(),
            "Structure should be dirty when priority or dependencies change"
        );
    }

    // -----------------------------------------------------------------------
    // compile_incremental tests
    // -----------------------------------------------------------------------

    #[test]
    fn test_first_compile_full() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut tracker = DirtyTracker::new();
        let client = MockQueryClient;

        let result = compile_incremental(&profile, None, &client, &mut tracker);

        // First compile should succeed (no references to resolve)
        assert!(result.is_ok(), "First compile should succeed");

        // Tracker should be cleared after successful compile
        assert!(!tracker.has_dirty_operations());

        // Profile should have the right number of operations
        let rp = result.unwrap();
        assert_eq!(rp.operations.len(), 1);
        assert_eq!(rp.operations[0].name, "A");
    }

    #[test]
    fn test_second_compile_no_changes() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut tracker = DirtyTracker::new();
        let client = MockQueryClient;

        // First compile
        let result1 = compile_incremental(&profile, None, &client, &mut tracker);
        assert!(result1.is_ok(), "First compile should succeed");

        // Second compile with same profile (no changes)
        let result2 = compile_incremental(&profile, Some(&profile), &client, &mut tracker);
        assert!(result2.is_ok(), "Second compile with no changes should succeed");

        // No dirty operations after second compile
        assert!(!tracker.has_dirty_operations());
    }

    #[test]
    fn test_second_compile_with_new_op() {
        let mut old_profile = Profile::new("Test", "Agent");
        old_profile.operations = vec![Operation::new("A")];

        let mut new_profile = Profile::new("Test", "Agent");
        new_profile.operations = vec![Operation::new("A"), Operation::new("B")];

        let mut tracker = DirtyTracker::new();
        let client = MockQueryClient;

        // First compile
        let result1 = compile_incremental(&old_profile, None, &client, &mut tracker);
        assert!(result1.is_ok());

        // Second compile with new op
        let result2 = compile_incremental(
            &new_profile,
            Some(&old_profile),
            &client,
            &mut tracker,
        );
        assert!(result2.is_ok(), "Second compile with new op should succeed");
        let rp = result2.unwrap();
        assert_eq!(rp.operations.len(), 2);
    }

    // -----------------------------------------------------------------------
    // can_skip_stage tests for incremental compile decisions
    // -----------------------------------------------------------------------

    #[test]
    fn test_no_dirty_ops_skip_all_stages() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut tracker = DirtyTracker::from_profile(&profile);
        tracker.clear();

        // All stages should be skippable
        assert!(tracker.can_skip_stage(StageFlags {
            stages_1_3: true,
            stage_4: true,
            stage_5: true,
            stage_6: true,
            stage_7: true,
        }));
    }

    #[test]
    fn test_dirty_op_runs_stages_1_3_5_6_7() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut tracker = DirtyTracker::from_profile(&profile);
        tracker.clear();
        tracker.mark_modified(op_id);

        // Dirty op means stages 1-3, 5, 6, 7 cannot be skipped
        assert!(!tracker.can_skip_stage(StageFlags {
            stages_1_3: true,
            ..StageFlags::all()
        }));
        assert!(!tracker.can_skip_stage(StageFlags {
            stage_5: true,
            ..StageFlags::all()
        }));
        assert!(!tracker.can_skip_stage(StageFlags {
            stage_6: true,
            ..StageFlags::all()
        }));
        assert!(!tracker.can_skip_stage(StageFlags {
            stage_7: true,
            ..StageFlags::all()
        }));
    }

    #[test]
    fn test_structure_dirty_runs_stage_4() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut tracker = DirtyTracker::from_profile(&profile);
        tracker.clear();
        tracker.mark_structure_dirty();

        // Structure dirty means stage 4 cannot be skipped
        assert!(!tracker.can_skip_stage(StageFlags {
            stage_4: true,
            ..StageFlags::all()
        }));
    }

    #[test]
    fn test_deleted_op_skip_stages() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut tracker = DirtyTracker::from_profile(&profile);
        tracker.clear();
        tracker.mark_deleted(op_id);

        // Deleted ops alone don't prevent skipping stages
        assert!(tracker.can_skip_stage(StageFlags::all()));
    }

    #[test]
    fn test_deleted_op_skipped_in_lowering() {
        // Simulate: Profile had operations A and B, then B was removed.
        // The output RuntimeProfile should only contain A.
        let mut old_profile = Profile::new("Test", "Agent");
        let op_a = Operation::new("A");
        let op_b = Operation::new("B");
        let b_id = op_b.id;
        old_profile.operations = vec![op_a, op_b];

        let mut new_profile = Profile::new("Test", "Agent");
        new_profile.operations = vec![Operation::new("A")];

        let mut tracker = DirtyTracker::new();
        let client = MockQueryClient;

        // First compile with both ops
        let result1 = compile_incremental(&old_profile, None, &client, &mut tracker);
        assert!(result1.is_ok());
        assert_eq!(result1.unwrap().operations.len(), 2);

        // Second compile with B removed
        let result2 = compile_incremental(
            &new_profile,
            Some(&old_profile),
            &client,
            &mut tracker,
        );
        assert!(result2.is_ok(), "Compile with removed op should succeed");

        let rp = result2.unwrap();
        assert_eq!(
            rp.operations.len(),
            1,
            "Deleted operation should not appear in output"
        );
        assert_eq!(rp.operations[0].name, "A");
        assert!(
            !rp.operations.iter().any(|op| op.id == b_id),
            "Removed operation B should not be in the output"
        );
    }
}
