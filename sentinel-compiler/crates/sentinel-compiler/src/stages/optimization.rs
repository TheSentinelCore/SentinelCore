//! Stage 6: Cross-Operation Optimization
//!
//! Walks adjacent Operations in compile order and applies merge rules:
//! - Drop redundant GoTo where destination matches expected position from prior action
//! - Collapse consecutive Vendor + Repair into one interaction
//! - Reorder within Operation when `allow_reordering: true`
//!
//! Optimization never changes goal coverage.
//!
//! See: docs/adr/008-compilation-pipeline.md §9

use std::collections::HashMap;

use sentinel_schema::action::{
    ActionPayload,
};
use sentinel_schema::{Action, Operation, Profile, Waypoint};
use uuid::Uuid;

use crate::stages::dependency::DependencyOrder;

/// Merge distance threshold in game yards.
const MERGE_DISTANCE: f32 = 50.0;

/// Result of Stage 6 — optimized profile with audit log.
#[derive(Debug, Clone)]
pub struct OptimizedProfile {
    pub profile: Profile,
    pub optimizations_applied: Vec<OptimizationLog>,
}

/// A record of one optimization applied.
#[derive(Debug, Clone)]
pub struct OptimizationLog {
    pub description: String,
    pub operation_id: Uuid,
    pub action_ids: Vec<Uuid>,
}

impl OptimizationLog {
    fn new(description: impl Into<String>, operation_id: Uuid) -> Self {
        Self {
            description: description.into(),
            operation_id,
            action_ids: Vec::new(),
        }
    }

    fn with_actions(mut self, ids: Vec<Uuid>) -> Self {
        self.action_ids = ids;
        self
    }
}

/// Stage 6: Cross-operation optimization using dependency ordering.
pub fn optimize(
    profile: &Profile,
    dep_order: &DependencyOrder,
) -> Result<OptimizedProfile, Vec<crate::diagnostics::Diagnostic>> {
    let mut optimizations: Vec<OptimizationLog> = Vec::new();

    // Build a lookup from Operation ID to Operation.
    let op_map: HashMap<Uuid, &Operation> =
        profile.operations.iter().map(|op| (op.id, op)).collect();

    // Work on a cloned profile so we can modify the action lists.
    let mut profile = profile.clone();

    // Phase 1: Within each operation, reorder if allowed.
    for i in 0..dep_order.ordered.len() {
        let op_id = dep_order.ordered[i];
        if let Some(op) = op_map.get(&op_id) {
            if op.optimization_policy.allow_reordering {
                // Simple waypoint-clustering: group GoTo actions by map proximity.
                // For now, just check if there's any reordering to be done.
                let ops = &profile.operations;
                let _op_idx = ops.iter().position(|o| o.id == op_id).unwrap();
                // Record that reordering was available but no actual change needed yet.
                // In a full implementation, this would sort actions by waypoint proximity.
            }
        }
    }

    // Phase 2: Collapse consecutive Vendor + Repair actions within each operation.
    for op in &mut profile.operations {
        let mut new_actions: Vec<Action> = Vec::with_capacity(op.actions.len());
        let mut i = 0;
        while i < op.actions.len() {
            if i + 1 < op.actions.len() {
                let can_merge = matches!(
                    (&op.actions[i].payload, &op.actions[i + 1].payload),
                    (ActionPayload::Vendor(_), ActionPayload::Repair(_))
                );
                if can_merge {
                    // Merge: turn the Vendor action into a Vendor-with-repair.
                    if let ActionPayload::Vendor(vendor) = &op.actions[i].payload {
                        let mut merged = vendor.clone();
                        merged.repair = true;
                        let merged_action = Action {
                            id: op.actions[i].id,
                            enabled: op.actions[i].enabled,
                            name: format!(
                                "{} + Repair",
                                op.actions[i].name
                            ),
                            notes: op.actions[i].notes.clone(),
                            tags: op.actions[i].tags.clone(),
                            retry_policy: op.actions[i].retry_policy.clone(),
                            timeout_ms: op.actions[i].timeout_ms,
                            conditions: op.actions[i].conditions.clone(),
                            payload: ActionPayload::Vendor(merged),
                        };
                        new_actions.push(merged_action);
                        optimizations.push(
                            OptimizationLog::new(
                                format!(
                                    "Collapsed Vendor '{}' + Repair into single action",
                                    op.actions[i].name
                                ),
                                op.id,
                            )
                            .with_actions(vec![op.actions[i].id, op.actions[i + 1].id]),
                        );
                        i += 2; // Skip the Repair
                        continue;
                    }
                }
            }
            new_actions.push(op.actions[i].clone());
            i += 1;
        }
        op.actions = new_actions;
    }

    // Phase 3: Drop redundant GoTo at the start of an Operation when the
    // previous Operation's last action already positions the player nearby.
    // Walk adjacent Operations in compile order.
    for i in 1..dep_order.ordered.len() {
        let prev_id = dep_order.ordered[i - 1];
        let curr_id = dep_order.ordered[i];

        let prev_end_pos = get_operation_end_position(&profile, prev_id);
        let _last_action_id = get_last_action_id(&profile, prev_id);

        if let Some(end_pos) = prev_end_pos {
            // Find the current operation and look at its first action.
            if let Some(curr_op) = profile.operations.iter_mut().find(|o| o.id == curr_id) {
                if !curr_op.actions.is_empty() {
                    if let ActionPayload::GoTo(goto) = &curr_op.actions[0].payload {
                        if end_pos.distance_2d(&goto.destination) <= MERGE_DISTANCE
                            && end_pos.map == goto.destination.map
                        {
                            // Drop the redundant GoTo.
                            let removed = curr_op.actions.remove(0);
                            optimizations.push(
                                OptimizationLog::new(
                                    format!(
                                        "Dropped redundant GoTo '{}' — already at destination from previous Operation",
                                        removed.name
                                    ),
                                    curr_id,
                                )
                                .with_actions(vec![removed.id]),
                            );
                        }
                    }
                }
            }
        }
    }

    Ok(OptimizedProfile {
        profile,
        optimizations_applied: optimizations,
    })
}

/// Get the position where an Operation ends — typically the destination of its
/// last GoTo, or the NPC position of its last Talk/Pickup/TurnIn action.
fn get_operation_end_position(profile: &Profile, op_id: Uuid) -> Option<Waypoint> {
    let op = profile.operations.iter().find(|o| o.id == op_id)?;
    if let Some(last_action) = op.actions.last() {
        extract_position_from_action(&last_action.payload)
    } else {
        None
    }
}

/// Get the last action ID of an Operation.
fn get_last_action_id(profile: &Profile, op_id: Uuid) -> Option<Uuid> {
    let op = profile.operations.iter().find(|o| o.id == op_id)?;
    op.actions.last().map(|a| a.id)
}

/// Extract a position from an action payload, if applicable.
fn extract_position_from_action(payload: &ActionPayload) -> Option<Waypoint> {
    match payload {
        ActionPayload::GoTo(a) => Some(a.destination.clone()),
        ActionPayload::TalkToNpc(a) => Some(a.npc.position.clone()),
        ActionPayload::PickupQuest(a) => Some(a.npc.position.clone()),
        ActionPayload::TurnInQuest(a) => Some(a.npc.position.clone()),
        ActionPayload::Vendor(a) => Some(a.vendor.npc.position.clone()),
        ActionPayload::Repair(a) => Some(a.vendor.npc.position.clone()),
        ActionPayload::Train(a) => Some(a.trainer.position.clone()),
        ActionPayload::Mailbox(a) => Some(a.mailbox.position.clone()),
        ActionPayload::Bank(a) => Some(a.banker.position.clone()),
        ActionPayload::DeathSkip(a) => Some(a.spirit_healer.position.clone()),
        ActionPayload::UseItem(a) => a.target.as_ref().map(|n| n.position.clone()),
        ActionPayload::Escort(a) => Some(a.npc.position.clone()),
        ActionPayload::FlightPath(a) => {
            Some(Waypoint::new(0, "", a.to.id as f32, 0.0, 0.0, 5.0))
        }
        ActionPayload::Hearth(_) => Some(Waypoint::zero()),
        _ => None,
    }
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::action::*;
    use sentinel_schema::reference::*;
    use sentinel_schema::enums::OptimizationPolicy;
    use sentinel_schema::{Action, Operation, Profile, Waypoint};
    use uuid::Uuid;

    fn test_waypoint(x: f32, y: f32) -> Waypoint {
        Waypoint::new(0, "Test", x, y, 0.0, 5.0)
    }

    fn test_npc(name: &str, x: f32, y: f32) -> NpcReference {
        NpcReference::new(1, name, "Test", test_waypoint(x, y))
    }

    #[test]
    fn test_no_optimization_needed() {
        let mut profile = Profile::new("Test", "Agent");
        let mut op = Operation::new("SingleOp");
        op.actions = vec![Action::new(
            "Wait",
            ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
        )];
        profile.operations.push(op);

        let dep_order = DependencyOrder {
            ordered: vec![profile.operations[0].id],
            order_map: [(profile.operations[0].id, 0)].into(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        assert_eq!(result.optimizations_applied.len(), 0);
        assert_eq!(result.profile.operations[0].actions.len(), 1);
    }

    #[test]
    fn test_drop_redundant_goto() {
        let mut profile = Profile::new("Test", "Agent");

        let mut op1 = Operation::new("Op1");
        op1.actions = vec![Action::new(
            "GoTo",
            ActionPayload::GoTo(GoToAction {
                destination: test_waypoint(100.0, 200.0),
                arrival_radius: 5.0,
            }),
        )];

        let mut op2 = Operation::new("Op2");
        op2.actions = vec![
            Action::new(
                "GoToStart",
                ActionPayload::GoTo(GoToAction {
                    destination: test_waypoint(110.0, 200.0), // within 50 yards of (100,200)
                    arrival_radius: 5.0,
                }),
            ),
            Action::new(
                "Talk",
                ActionPayload::TalkToNpc(TalkToNpcAction {
                    npc: test_npc("Marshal", 110.0, 200.0),
                    gossip_option: None,
                }),
            ),
        ];

        profile.operations.push(op1);
        profile.operations.push(op2);

        let op1_id = profile.operations[0].id;
        let op2_id = profile.operations[1].id;
        let dep_order = DependencyOrder {
            ordered: vec![op1_id, op2_id],
            order_map: [(op1_id, 0), (op2_id, 1)].into(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        // The GoTo at the start of Op2 should be dropped
        assert_eq!(
            result.profile.operations[1].actions.len(),
            1,
            "GoTo should be dropped, only Talk remains"
        );
        assert!(result
            .optimizations_applied
            .iter()
            .any(|o| o.description.contains("redundant GoTo")));
    }

    #[test]
    fn test_keep_distant_goto() {
        let mut profile = Profile::new("Test", "Agent");

        let mut op1 = Operation::new("Op1");
        op1.actions = vec![Action::new(
            "GoTo",
            ActionPayload::GoTo(GoToAction {
                destination: test_waypoint(100.0, 200.0),
                arrival_radius: 5.0,
            }),
        )];

        let mut op2 = Operation::new("Op2");
        op2.actions = vec![Action::new(
            "GoToFar",
            ActionPayload::GoTo(GoToAction {
                destination: test_waypoint(500.0, 800.0), // way more than 50 yards
                arrival_radius: 5.0,
            }),
        )];

        profile.operations.push(op1);
        profile.operations.push(op2);

        let op1_id = profile.operations[0].id;
        let op2_id = profile.operations[1].id;
        let dep_order = DependencyOrder {
            ordered: vec![op1_id, op2_id],
            order_map: [(op1_id, 0), (op2_id, 1)].into(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        assert_eq!(result.profile.operations[1].actions.len(), 1);
    }

    #[test]
    fn test_collapse_vendor_repair() {
        let vendor_npc = test_npc("Brother Danil", 0.0, 0.0);
        let vendor_entry = VendorEntry {
            npc: vendor_npc,
            sells: vec![],
            repairs: false,
        };

        let mut op = Operation::new("Op");
        op.actions = vec![
            Action::new(
                "SellGreys",
                ActionPayload::Vendor(VendorAction {
                    vendor: vendor_entry.clone(),
                    repair: false,
                    sell_gray: true,
                    sell_white: false,
                    buy: vec![],
                }),
            ),
            Action::new(
                "RepairGear",
                ActionPayload::Repair(RepairAction {
                    vendor: vendor_entry,
                }),
            ),
        ];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations.push(op);

        let op_id = profile.operations[0].id;
        let dep_order = DependencyOrder {
            ordered: vec![op_id],
            order_map: [(op_id, 0)].into(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        // Should be merged into 1 action with repair=true
        assert_eq!(
            result.profile.operations[0].actions.len(),
            1,
            "Vendor+Repair should be collapsed into 1 action"
        );
        if let ActionPayload::Vendor(v) = &result.profile.operations[0].actions[0].payload {
            assert!(v.repair, "Merged Vendor should have repair=true");
        } else {
            panic!("Expected Vendor action after merge");
        }
    }

    #[test]
    fn test_no_reorder_without_policy() {
        let mut policy = OptimizationPolicy::default();
        policy.allow_reordering = false;

        let mut op = Operation::new("Op");
        op.optimization_policy = policy;
        op.actions = vec![
            Action::new(
                "B",
                ActionPayload::Wait(WaitAction { duration_ms: 200 }),
            ),
            Action::new(
                "A",
                ActionPayload::Wait(WaitAction { duration_ms: 100 }),
            ),
        ];

        let mut profile = Profile::new("Test", "Agent");
        let _a_id = op.actions[1].id; // Before push, capture ID
        profile.operations.push(op);

        let op_id = profile.operations[0].id;
        let dep_order = DependencyOrder {
            ordered: vec![op_id],
            order_map: [(op_id, 0)].into(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        // Order should be preserved since allow_reordering is false
        assert_eq!(
            result.profile.operations[0].actions[0].name, "B",
            "Without allow_reordering, original order should be preserved"
        );
    }

    #[test]
    fn test_preserves_operation_count() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations.push(Operation::new("A"));
        profile.operations.push(Operation::new("B"));

        let ids: Vec<Uuid> = profile.operations.iter().map(|o| o.id).collect();
        let dep_order = DependencyOrder {
            ordered: ids.clone(),
            order_map: ids.into_iter().enumerate().map(|(i, id)| (id, i)).collect(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        assert_eq!(result.profile.operations.len(), 2);
    }

    #[test]
    fn test_empty_operations() {
        let profile = Profile::new("Test", "Agent");
        let dep_order = DependencyOrder {
            ordered: vec![],
            order_map: HashMap::new(),
        };
        let result = optimize(&profile, &dep_order).unwrap();
        assert_eq!(result.profile.operations.len(), 0);
    }

    #[test]
    fn test_goto_in_same_operation_no_redundant_drop() {
        // Verify that a GoTo followed by a Talk within the same operation
        // doesn't get incorrectly dropped (only cross-operation drops happen).
        let mut op = Operation::new("Op");
        op.actions = vec![
            Action::new(
                "GoTo",
                ActionPayload::GoTo(GoToAction {
                    destination: test_waypoint(100.0, 200.0),
                    arrival_radius: 5.0,
                }),
            ),
            Action::new(
                "Talk",
                ActionPayload::TalkToNpc(TalkToNpcAction {
                    npc: test_npc("NPC", 100.0, 200.0),
                    gossip_option: None,
                }),
            ),
        ];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations.push(op);

        let op_id = profile.operations[0].id;
        let dep_order = DependencyOrder {
            ordered: vec![op_id],
            order_map: [(op_id, 0)].into(),
        };

        let result = optimize(&profile, &dep_order).unwrap();
        assert_eq!(result.profile.operations[0].actions.len(), 2);
    }
}
