//! ExecutionPlan — resolver output, runtime input (ADR 09a §1.4).
//!
//! The flattened, topologically ordered form of one graph: no intent, no references, no editor
//! metadata. This is the only platform shape that crosses into the runtime, which is why every
//! enum reachable from here is adjacently tagged `{ type, payload }`.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::default_schema_version;
use crate::runtime::GuardedAction;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExecutionPlan {
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    pub campaign_id: Uuid,
    pub graph_id: Uuid,
    /// The database the operations below were resolved against. A plan produced against a
    /// different fingerprint is stale, not wrong — re-resolve rather than patch.
    pub db_fingerprint: String,
    pub content_hash: String,
    /// Topologically ordered. `next.to_index` indexes into this vector.
    #[serde(default)]
    pub operations: Vec<PlanOperation>,
}

/// One resolved node: its actions, and where control goes afterwards.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlanOperation {
    /// The [`super::Node`] this was lowered from, so runtime events and diagnostics can point back
    /// at authored intent.
    pub node_id: Uuid,
    #[serde(default)]
    pub actions: Vec<GuardedAction>,
    #[serde(default)]
    pub next: Vec<PlanTransition>,
}

impl PlanOperation {
    /// True when this operation advances the way today's linear routes do: exactly one successor,
    /// unguarded.
    pub fn is_sequential_advance(&self) -> bool {
        matches!(self.next.as_slice(), [transition] if transition.guard.is_none())
    }
}

/// An outgoing transition. `to_index` is an index into [`ExecutionPlan::operations`] rather than a
/// node id so the runtime advances without a lookup table.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlanTransition {
    pub to_index: usize,
    /// A [`super::ConditionDef`] id when the transition is gated.
    #[serde(default)]
    pub guard: Option<Uuid>,
}

/// Content hash over `operations` only, so re-stamping metadata does not invalidate a plan.
///
/// Same construction as [`crate::runtime::compute_content_hash`]: a deterministic polynomial over
/// the canonical JSON, with no random seed, because the resolver's purity requirement is that the
/// same intent and fingerprint produce byte-identical output.
pub fn compute_content_hash(plan: &ExecutionPlan) -> String {
    let operations_json = serde_json::to_string(&plan.operations).unwrap_or_default();
    let mut hash: u64 = 0;
    for byte in operations_json.bytes() {
        hash = hash.wrapping_mul(31).wrapping_add(byte as u64);
    }
    format!("{hash:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platform::PLATFORM_SCHEMA_VERSION;
    use crate::runtime::{RuntimeAcceptQuest, RuntimeAction, RuntimeTurnInQuest};
    use serde_json::json;

    fn sequential_plan() -> ExecutionPlan {
        ExecutionPlan {
            schema_version: PLATFORM_SCHEMA_VERSION,
            campaign_id: Uuid::from_u128(1),
            graph_id: Uuid::from_u128(5),
            db_fingerprint: "tbcmangos@a1b2c3".to_string(),
            content_hash: String::new(),
            operations: vec![
                PlanOperation {
                    node_id: Uuid::from_u128(6),
                    actions: vec![RuntimeAction::AcceptQuest(RuntimeAcceptQuest {
                        quest_id: 783,
                        npc_entry: 823,
                        auto_complete_dialog: false,
                        optional: false,
                    })
                    .into()],
                    next: vec![PlanTransition {
                        to_index: 1,
                        guard: None,
                    }],
                },
                PlanOperation {
                    node_id: Uuid::from_u128(7),
                    actions: vec![RuntimeAction::TurnInQuest(RuntimeTurnInQuest {
                        quest_id: 783,
                        npc_entry: 823,
                        choose_reward: None,
                        optional: false,
                    })
                    .into()],
                    next: vec![],
                },
            ],
        }
    }

    #[test]
    fn matches_the_plan_wire_shape() {
        let wire = serde_json::to_value(sequential_plan()).unwrap();
        assert_eq!(wire["schema_version"], 3);
        assert_eq!(wire["db_fingerprint"], "tbcmangos@a1b2c3");
        assert_eq!(
            wire["operations"][0]["node_id"],
            "00000000-0000-0000-0000-000000000006"
        );
        assert_eq!(
            wire["operations"][0]["next"],
            json!([{ "to_index": 1, "guard": null }])
        );
        // The frozen runtime vocabulary, adjacently tagged — this is what the Lua runtime reads.
        assert_eq!(wire["operations"][0]["actions"][0]["type"], "AcceptQuest");
        assert_eq!(
            wire["operations"][0]["actions"][0]["payload"]["quest_id"],
            783
        );
    }

    #[test]
    fn round_trips_through_json() {
        let plan = sequential_plan();
        let back: ExecutionPlan =
            serde_json::from_str(&serde_json::to_string(&plan).unwrap()).unwrap();
        assert_eq!(back, plan);
    }

    #[test]
    fn a_single_unguarded_next_is_the_sequential_advance() {
        let plan = sequential_plan();
        assert!(plan.operations[0].is_sequential_advance());
        assert!(
            !plan.operations[1].is_sequential_advance(),
            "terminal op has no next"
        );
    }

    #[test]
    fn a_guarded_transition_names_a_condition_id() {
        let mut plan = sequential_plan();
        plan.operations[0].next[0].guard = Some(Uuid::from_u128(4));
        assert!(!plan.operations[0].is_sequential_advance());
        let wire = serde_json::to_value(&plan).unwrap();
        assert_eq!(
            wire["operations"][0]["next"][0]["guard"],
            "00000000-0000-0000-0000-000000000004"
        );
    }

    #[test]
    fn the_content_hash_depends_on_operations_only() {
        let mut a = sequential_plan();
        let mut b = sequential_plan();
        b.campaign_id = Uuid::from_u128(99);
        b.db_fingerprint = "other@deadbeef".to_string();
        a.content_hash = compute_content_hash(&a);
        b.content_hash = compute_content_hash(&b);
        assert_eq!(a.content_hash, b.content_hash);
        assert!(!a.content_hash.is_empty());
    }

    #[test]
    fn a_changed_operation_changes_the_content_hash() {
        let a = sequential_plan();
        let mut b = sequential_plan();
        b.operations[0].next[0].to_index = 0;
        assert_ne!(compute_content_hash(&a), compute_content_hash(&b));
    }

    #[test]
    fn the_content_hash_is_deterministic_across_runs() {
        let plan = sequential_plan();
        assert_eq!(compute_content_hash(&plan), compute_content_hash(&plan));
    }
}
