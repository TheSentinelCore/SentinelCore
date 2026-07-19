//! DirtyTracker — incremental recompilation state tracking.
//!
//! Tracks which Operations have changed since the last successful compile,
//! and whether structural metadata (dependencies, priorities, entry conditions)
//! has changed, which affects Stages 4+.

use std::collections::HashMap;
use uuid::Uuid;

/// Whether an Operation has changed relative to the previous compile.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DirtyState {
    /// Operation was added after the last compile.
    New,
    /// Existing operation whose content (actions, goals) changed.
    Modified,
    /// Operation was removed since the last compile.
    Deleted,
    /// No change since the last successful compile.
    Unchanged,
}

/// Flags indicating which compilation stages can potentially be skipped.
///
/// Each field corresponds to one or more stages. Set a field to `true`
/// when you want to ask the tracker "can these stages be skipped?"
#[derive(Debug, Clone)]
pub struct StageFlags {
    /// Stages 1-3 (Structural, Resolution, Expansion) — skip if no ops dirty
    pub stages_1_3: bool,
    /// Stage 4 (Dependency) — skip if structure not dirty
    pub stage_4: bool,
    /// Stage 5 (Goals) — skip if no ops dirty
    pub stage_5: bool,
    /// Stage 6 (Optimization) — skip if no ops dirty
    pub stage_6: bool,
    /// Stage 7 (Lowering) — skip if no ops dirty
    pub stage_7: bool,
}

impl StageFlags {
    /// All stages can potentially be skipped (used to ask "is anything dirty at all?").
    pub const fn all() -> Self {
        Self {
            stages_1_3: true,
            stage_4: true,
            stage_5: true,
            stage_6: true,
            stage_7: true,
        }
    }
}

/// Tracks dirty state across compilations.
///
/// Created fresh on first compile (all operations → `New`), then updated
/// on each subsequent compile via `update_tracker` / manual marking.
#[derive(Debug, Clone)]
pub struct DirtyTracker {
    /// Per-Operation dirty state, keyed by Operation ID.
    operations: HashMap<Uuid, DirtyState>,
    /// Whether the Profile-level metadata changed (re-run all).
    /// Currently reserved; always `false` after initialisation.
    profile_dirty: bool,
    /// Whether dependencies, priorities, or entry_conditions changed.
    /// When true, Stage 4 (Dependency) must re-run.
    structure_dirty: bool,
}

impl DirtyTracker {
    /// Create an empty tracker (no operations tracked).
    pub fn new() -> Self {
        Self {
            operations: HashMap::new(),
            profile_dirty: false,
            structure_dirty: false,
        }
    }

    /// Initialise from a fresh Profile — every Operation is `New`,
    /// and structural metadata is dirty so that Stage 4 re-runs.
    pub fn from_profile(profile: &sentinel_schema::Profile) -> Self {
        let mut operations = HashMap::with_capacity(profile.operations.len());
        for op in &profile.operations {
            operations.insert(op.id, DirtyState::New);
        }
        Self {
            operations,
            profile_dirty: true,
            structure_dirty: true,
        }
    }

    /// Mark an Operation as modified (content changed — actions, goals, etc.).
    pub fn mark_modified(&mut self, op_id: Uuid) {
        self.operations.insert(op_id, DirtyState::Modified);
    }

    /// Mark an Operation as deleted (removed from the Profile).
    pub fn mark_deleted(&mut self, op_id: Uuid) {
        self.operations.insert(op_id, DirtyState::Deleted);
    }

    /// Mark an Operation as new (added since the last compile).
    pub fn mark_new(&mut self, op_id: Uuid) {
        self.operations.insert(op_id, DirtyState::New);
    }

    /// Mark that the dependency structure changed (dependencies, priority,
    /// or entry_conditions). This forces Stage 4 to re-run.
    pub fn mark_structure_dirty(&mut self) {
        self.structure_dirty = true;
    }

    /// Get the current dirty state of an Operation.
    ///
    /// Returns `None` if the Operation ID is not tracked (should not happen
    /// after `from_profile` or a diff).
    pub fn get_state(&self, op_id: Uuid) -> Option<DirtyState> {
        self.operations.get(&op_id).copied()
    }

    /// Return `true` if ALL stages indicated by the flags can be skipped
    /// (i.e., no relevant dirty state prevents it).
    ///
    /// # Example
    ///
    /// ```ignore
    /// if tracker.can_skip_stage(StageFlags { stages_1_3: true, .. }) {
    ///     // skip stages 1-3
    /// }
    /// ```
    pub fn can_skip_stage(&self, stage: StageFlags) -> bool {
        let has_dirty_ops = self.operations.iter().any(|(_, state)| {
            matches!(state, DirtyState::New | DirtyState::Modified)
        });

        if stage.stages_1_3 && has_dirty_ops {
            return false;
        }
        if stage.stage_4 && self.structure_dirty {
            return false;
        }
        if stage.stage_5 && has_dirty_ops {
            return false;
        }
        if stage.stage_6 && has_dirty_ops {
            return false;
        }
        if stage.stage_7 && has_dirty_ops {
            return false;
        }
        true
    }

    /// Return the set of Operation IDs that are `New` or `Modified`.
    pub fn dirty_operation_ids(&self) -> Vec<Uuid> {
        self.operations
            .iter()
            .filter(|(_, state)| matches!(state, DirtyState::New | DirtyState::Modified))
            .map(|(id, _)| *id)
            .collect()
    }

    /// Return the set of Operation IDs that are `Deleted`.
    pub fn deleted_operation_ids(&self) -> Vec<Uuid> {
        self.operations
            .iter()
            .filter(|(_, state)| matches!(state, DirtyState::Deleted))
            .map(|(id, _)| *id)
            .collect()
    }

    /// Whether any operation is dirty (New or Modified).
    pub fn has_dirty_operations(&self) -> bool {
        self.operations
            .values()
            .any(|s| matches!(s, DirtyState::New | DirtyState::Modified))
    }

    /// Whether the structure (dependencies, priorities, entry_conditions) is dirty.
    pub fn is_structure_dirty(&self) -> bool {
        self.structure_dirty
    }

    /// Clear after a successful compile.
    ///
    /// Resets all operation states to `Unchanged` and clears structural flags.
    /// Keeps the operation map so the next diff can detect additions/removals.
    pub fn clear(&mut self) {
        for state in self.operations.values_mut() {
            *state = DirtyState::Unchanged;
        }
        self.profile_dirty = false;
        self.structure_dirty = false;
    }

    /// Remove tracked state for a set of Operation IDs (e.g., deleted ops
    /// that no longer need tracking after the compile).
    pub fn forget_operations(&mut self, ids: &[Uuid]) {
        for id in ids {
            self.operations.remove(id);
        }
    }

    /// Return the set of dirty Operation IDs plus their immediate dependency
    /// neighbours (both the ops they depend on and the ops that depend on them).
    ///
    /// Used by Stage 6 (Optimization) which needs to see neighbouring
    /// Operations when one of them changes.
    pub fn dirty_ops_with_neighbors(
        &self,
        profile: &sentinel_schema::Profile,
    ) -> Vec<Uuid> {
        let dirty_ids: std::collections::HashSet<Uuid> = self
            .operations
            .iter()
            .filter(|(_, state)| matches!(state, DirtyState::New | DirtyState::Modified))
            .map(|(id, _)| *id)
            .collect();

        if dirty_ids.is_empty() {
            return Vec::new();
        }

        // Build a neighbour map: for each operation, collect its dependency targets
        // and any operation that depends on it.
        let mut result: std::collections::HashSet<Uuid> = dirty_ids.clone();
        let mut forward_deps: std::collections::HashMap<Uuid, Vec<Uuid>> =
            std::collections::HashMap::new();
        let mut reverse_deps: std::collections::HashMap<Uuid, Vec<Uuid>> =
            std::collections::HashMap::new();

        for op in &profile.operations {
            for dep in &op.dependencies {
                // op depends on dep.operation_id
                forward_deps
                    .entry(op.id)
                    .or_default()
                    .push(dep.operation_id);
                reverse_deps
                    .entry(dep.operation_id)
                    .or_default()
                    .push(op.id);
            }
        }

        // Add neighbours of each dirty op
        for dirty_id in &dirty_ids {
            if let Some(targets) = forward_deps.get(dirty_id) {
                for t in targets {
                    result.insert(*t);
                }
            }
            if let Some(dependents) = reverse_deps.get(dirty_id) {
                for d in dependents {
                    result.insert(*d);
                }
            }
        }

        result.into_iter().collect()
    }
}

impl Default for DirtyTracker {
    fn default() -> Self {
        Self::new()
    }
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::Operation;

    // -----------------------------------------------------------------------
    // DirtyTracker basic operations
    // -----------------------------------------------------------------------

    #[test]
    fn test_new_tracker_empty() {
        let t = DirtyTracker::new();
        assert!(!t.has_dirty_operations());
        assert!(!t.is_structure_dirty());
        assert!(t.dirty_operation_ids().is_empty());
    }

    #[test]
    fn test_from_profile_all_new() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A"), Operation::new("B")];

        let t = DirtyTracker::from_profile(&profile);
        assert!(t.has_dirty_operations());
        assert!(t.is_structure_dirty());
        assert_eq!(t.dirty_operation_ids().len(), 2);

        for op in &profile.operations {
            assert_eq!(t.get_state(op.id), Some(DirtyState::New));
        }
    }

    #[test]
    fn test_mark_modified() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();
        assert_eq!(t.get_state(op_id), Some(DirtyState::Unchanged));

        t.mark_modified(op_id);
        assert_eq!(t.get_state(op_id), Some(DirtyState::Modified));
        assert!(t.has_dirty_operations());
    }

    #[test]
    fn test_mark_deleted() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();
        t.mark_deleted(op_id);
        assert_eq!(t.get_state(op_id), Some(DirtyState::Deleted));
    }

    #[test]
    fn test_mark_structure_dirty() {
        let profile = sentinel_schema::Profile::new("Test", "Agent");
        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();
        assert!(!t.is_structure_dirty());

        t.mark_structure_dirty();
        assert!(t.is_structure_dirty());
    }

    #[test]
    fn test_clear_resets_state() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut t = DirtyTracker::from_profile(&profile);
        t.mark_modified(op_id);
        t.mark_structure_dirty();
        assert!(t.has_dirty_operations());
        assert!(t.is_structure_dirty());

        t.clear();
        assert!(!t.has_dirty_operations());
        assert!(!t.is_structure_dirty());
        assert_eq!(t.get_state(op_id), Some(DirtyState::Unchanged));
    }

    #[test]
    fn test_forget_operations() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut t = DirtyTracker::from_profile(&profile);
        t.forget_operations(&[op_id]);
        assert!(t.dirty_operation_ids().is_empty());
    }

    // -----------------------------------------------------------------------
    // can_skip_stage
    // -----------------------------------------------------------------------

    #[test]
    fn test_no_dirty_ops_skip_all_stages() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear(); // All Unchanged

        assert!(t.can_skip_stage(StageFlags {
            stages_1_3: true,
            stage_4: true,
            stage_5: true,
            stage_6: true,
            stage_7: true,
        }));
    }

    #[test]
    fn test_dirty_op_prevents_stages_1_3() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];
        let op_id = profile.operations[0].id;

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();
        t.mark_modified(op_id);

        assert!(!t.can_skip_stage(StageFlags {
            stages_1_3: true,
            ..StageFlags::all()
        }));
    }

    #[test]
    fn test_structure_dirty_prevents_stage_4() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();
        t.mark_structure_dirty();

        assert!(!t.can_skip_stage(StageFlags {
            stage_4: true,
            ..StageFlags::all()
        }));
    }

    #[test]
    fn test_structure_not_dirty_allows_stage_4_skip() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A")];

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();

        assert!(t.can_skip_stage(StageFlags {
            stage_4: true,
            ..StageFlags::all()
        }));
    }

    // -----------------------------------------------------------------------
    // dirty_ops_with_neighbors
    // -----------------------------------------------------------------------

    #[test]
    fn test_dirty_ops_neighbors_in_stage_6() {
        use sentinel_schema::{condition::OperationDependency, Operation};
        use uuid::Uuid;

        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();
        let id_c = Uuid::new_v4();

        // A depends on B
        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.dependencies = vec![OperationDependency::requires(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;

        let mut op_c = Operation::new("C");
        op_c.id = id_c;

        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b, op_c];

        let mut tracker = DirtyTracker::from_profile(&profile);
        tracker.clear();

        // Mark A as modified
        tracker.mark_modified(id_a);

        let neighbors = tracker.dirty_ops_with_neighbors(&profile);
        let neighbor_set: std::collections::HashSet<Uuid> =
            neighbors.into_iter().collect();

        // Should include A (dirty) and B (dependency neighbor)
        assert!(neighbor_set.contains(&id_a), "Dirty op A should be included");
        assert!(neighbor_set.contains(&id_b), "Neighbor B (depended by A) should be included");
        // C is unrelated — should NOT be in the set
        assert!(
            !neighbor_set.contains(&id_c),
            "Unrelated op C should not be included"
        );
    }

    #[test]
    fn test_no_dirty_ops_neighbors_empty() {
        let profile = sentinel_schema::Profile::new("Test", "Agent");
        let mut tracker = DirtyTracker::from_profile(&profile);
        tracker.clear();

        let neighbors = tracker.dirty_ops_with_neighbors(&profile);
        assert!(neighbors.is_empty(), "No dirty ops => no neighbors");
    }

    // -----------------------------------------------------------------------
    // dirty_operation_ids / deleted_operation_ids helpers
    // -----------------------------------------------------------------------

    #[test]
    fn test_dirty_operation_ids_filtered() {
        let mut profile = sentinel_schema::Profile::new("Test", "Agent");
        profile.operations = vec![Operation::new("A"), Operation::new("B")];
        let id_a = profile.operations[0].id;
        let id_b = profile.operations[1].id;

        let mut t = DirtyTracker::from_profile(&profile);
        t.clear();

        // Mark A as modified, B stays unchanged
        t.mark_modified(id_a);

        let dirty = t.dirty_operation_ids();
        assert_eq!(dirty.len(), 1);
        assert!(dirty.contains(&id_a));
        assert!(!dirty.contains(&id_b));
    }
}
