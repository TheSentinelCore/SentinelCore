//! ExecutionPlan — resolver output, runtime input (ADR 09a §1.4).
//!
//! The flattened, topologically ordered form of one graph: no intent, no references, no editor
//! metadata. This is the only platform shape that crosses into the runtime, which is why every
//! enum reachable from here is adjacently tagged `{ type, payload }`.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{default_schema_version, ConditionDef};
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
    /// Every [`ConditionDef`] the transitions above name, and nothing else.
    ///
    /// A `PlanTransition.guard` is an id, and the runtime has no campaign, no database and no
    /// network to dereference it against — so before this field existed every guarded edge arrived
    /// in Lua as an id with nothing behind it, `select_transition` marked it `unresolved` and
    /// failed closed, and the route terminated at its first branch. Linear routes have no guards,
    /// which is exactly why the whole corpus executed and nothing caught it.
    ///
    /// Skipped when empty: every plan stored before this field is guard-free, and emitting
    /// `"conditions": []` for them would change their bytes and, through
    /// [`compute_content_hash`], invalidate every stored hash at once for no information.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub conditions: Vec<ConditionDef>,
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

/// Content hash over what the plan executes — `operations`, plus `conditions` when it has any — so
/// re-stamping metadata does not invalidate a plan.
///
/// Conditions are in because re-authoring a guard leaves the operations byte-identical: two plans
/// that branch on different conditions would otherwise share a hash, and hot-reload and the
/// profile cache both key on it, so a corrected branch would keep executing the old condition.
///
/// The conditions JSON is appended only when non-empty, matching the field's
/// `skip_serializing_if`. The hash covers what is on the wire, and an absent field puts nothing
/// there — which is what keeps every guard-free plan already stored in the corpus hashing to the
/// value it was stamped with. Concatenating the two arrays is unambiguous: each is a balanced
/// bracket run, so no `(operations, conditions)` pair can alias another's bytes.
///
/// Same construction as [`crate::runtime::compute_content_hash`]: a deterministic polynomial over
/// the canonical JSON, with no random seed, because the resolver's purity requirement is that the
/// same intent and fingerprint produce byte-identical output.
pub fn compute_content_hash(plan: &ExecutionPlan) -> String {
    let mut canonical = serde_json::to_string(&plan.operations).unwrap_or_default();
    if !plan.conditions.is_empty() {
        canonical.push_str(&serde_json::to_string(&plan.conditions).unwrap_or_default());
    }
    let mut hash: u64 = 0;
    for byte in canonical.bytes() {
        hash = hash.wrapping_mul(31).wrapping_add(byte as u64);
    }
    format!("{hash:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platform::{ConditionDef, PLATFORM_SCHEMA_VERSION};
    use crate::runtime::{
        RuntimeAcceptQuest, RuntimeAction, RuntimeCondition, RuntimeTurnInQuest,
    };
    use serde_json::json;

    fn sequential_plan() -> ExecutionPlan {
        ExecutionPlan {
            schema_version: PLATFORM_SCHEMA_VERSION,
            campaign_id: Uuid::from_u128(1),
            graph_id: Uuid::from_u128(5),
            db_fingerprint: "tbcmangos@a1b2c3".to_string(),
            content_hash: String::new(),
            conditions: Vec::new(),
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

    /// The same plan, with its one guard actually defined — what a branching route emits.
    fn guarded_plan() -> ExecutionPlan {
        let mut plan = sequential_plan();
        plan.operations[0].next[0].guard = Some(Uuid::from_u128(4));
        plan.conditions = vec![ConditionDef {
            id: Uuid::from_u128(4),
            condition: RuntimeCondition::LevelAtLeast(10),
        }];
        plan
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

    /// The defect this field exists to close: before it, `guard` named a [`ConditionDef`] that
    /// lived only in the campaign, and the campaign never crosses into the runtime. Every guarded
    /// edge therefore reached Lua as an id with nothing behind it, `select_transition` marked it
    /// `unresolved`, and the route died at the first branch.
    #[test]
    fn a_guarded_plan_carries_the_definition_its_guard_names() {
        let plan = guarded_plan();
        let guard = plan.operations[0].next[0]
            .guard
            .expect("the transition is guarded");
        assert!(
            plan.conditions.iter().any(|def| def.id == guard),
            "a plan must be executable without the campaign that produced it"
        );
    }

    /// `index_conditions` in `execution_plan.lua` reads a list entry as `{ id, type, payload }` —
    /// the id and the condition in ONE table, which is what `#[serde(flatten)]` produces. Nesting
    /// the condition under a key would leave `by_id[id]` holding a table with no `type`, and
    /// `RuntimeAction.evaluate_condition` fails open on an unknown type.
    #[test]
    fn a_condition_serializes_in_the_flattened_shape_the_lua_loader_indexes() {
        let wire = serde_json::to_value(guarded_plan()).unwrap();
        assert_eq!(
            wire["conditions"][0]["id"],
            "00000000-0000-0000-0000-000000000004"
        );
        assert_eq!(wire["conditions"][0]["type"], "LevelAtLeast");
        assert_eq!(wire["conditions"][0]["payload"], 10);
    }

    /// Every plan stored before this field existed is guard-free. Emitting `"conditions": []` for
    /// them would change their bytes and — since the hash covers what is on the wire — invalidate
    /// every stored `content_hash` in the corpus at once, for a field carrying no information.
    #[test]
    fn a_guard_free_plan_puts_no_conditions_key_on_the_wire() {
        let wire = serde_json::to_value(sequential_plan()).unwrap();
        assert!(
            wire.get("conditions").is_none(),
            "an empty conditions list must not reach the wire: {wire}"
        );
    }

    /// The other half of that promise, pinned as bytes: this is the hash the fixture produced
    /// before `conditions` existed. A guard-free plan's identity must not have moved.
    #[test]
    fn adding_conditions_did_not_move_a_guard_free_plans_content_hash() {
        assert_eq!(compute_content_hash(&sequential_plan()), "d7d6bee88e917e35");
    }

    /// Two plans with identical operations and different guards are different plans. If the hash
    /// cannot tell them apart, neither can hot-reload or the profile cache, and a re-authored
    /// branch keeps executing the old condition.
    #[test]
    fn a_changed_condition_changes_the_content_hash() {
        let a = guarded_plan();
        let mut b = guarded_plan();
        b.conditions[0].condition = RuntimeCondition::LevelAtLeast(11);
        assert_ne!(compute_content_hash(&a), compute_content_hash(&b));
    }

    #[test]
    fn a_guarded_plan_round_trips_through_json() {
        let plan = guarded_plan();
        let back: ExecutionPlan =
            serde_json::from_str(&serde_json::to_string(&plan).unwrap()).unwrap();
        assert_eq!(back, plan);
    }

    #[test]
    fn the_content_hash_ignores_restamped_metadata() {
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
