//! [`Task`] — the step-as-container, plus its concurrency and completion vocabulary.
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 for the shape, §5.3 (C3) for [`Lifetime`] /
//! [`CompletionSource`] / [`Channel`] / [`ResumeCursor`], §5.1.2 for [`UnknownPolicy`].
//!
//! The one structural decision worth restating: [`Lifetime`] and [`CompletionSource`] are
//! **independent fields**, because `#sticky` and `#completewith` are disjoint as authored (§2.4)
//! yet `#completewith` implies sticky at runtime (§3.1). Collapsing them into one "background" flag
//! is what makes the RXPGuides model unable to express the 37 steps that carry both.

use serde::{Deserialize, Deserializer, Serialize};

use super::ids::{QuestId, TaskId};
use super::op::{BehaviorId, LootRule, NpcRef, Op};
use super::predicate::Predicate;
use super::profile::CombatPolicy;

/// Provenance: where in the guide pack this task came from (§6.6, §7.1).
///
/// The one thing worth carrying across the authoring/runtime boundary, so a runtime failure points
/// at a corpus line. Costs ~20 bytes per task.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceSpan {
    /// Guide file name, e.g. `"A-11-23.lua"`.
    pub file: String,
    /// First source line of the step, inclusive.
    pub line_start: u32,
    /// Last source line of the step, inclusive.
    pub line_end: u32,
}

/// A ControlBroker channel a background task may hold (§5.3; §7.2 pins the wire spellings).
///
/// Serialized as SCREAMING_SNAKE — `"MOVEMENT"`, `"FACING"`, … — matching §7.2's enum list and the
/// `"channels": ["MOVEMENT"]` in §7.3.3.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Channel {
    /// Movement. What a sticky patrol or grind loop claims: the `#sticky` payload is 416
    /// `.waypoint` + 296 `.goto` lines (§5.3).
    Movement,
    /// Facing. Claimed transiently by foreground turn-ins and accepts.
    Facing,
    /// Spell casting. Delegated to `service.combat` separately per C6, not claimed by the patrol.
    Casting,
    /// Target selection. Delegated with `Casting` per C6.
    Targeting,
    /// NPC / object interaction. Claimed by foreground turn-in and accept tasks, and by
    /// vendor/bank/trainer delegations together with [`Channel::Items`] (§5.3).
    Interaction,
    /// Inventory manipulation.
    Items,
    /// Camera control.
    Camera,
}

/// ADR 07 §7.2's scheduler band, **inclusive at both ends**: `{ "minimum": 30, "maximum": 49 }`.
///
/// The Goal band of §5.3 — above the 20s where opportunistic work lives, below the 90-99 safety net
/// that `#ignorecorpse` exists to switch off so deliberate death can work at all (§8). Exported
/// because the compiler that *assigns* bands and the model that *refuses* them must agree on one
/// range, and two transcriptions of `30..=49` are two chances to write `30..49`.
pub const GOAL_BAND: std::ops::RangeInclusive<u8> = 30..=49;

/// Refuse a scheduler band outside [`GOAL_BAND`] at the wire boundary.
///
/// The range cannot be expressed in the type — `band` is a `u8` — and therefore cannot reach the
/// generated schema either (`shared/tests/kernel_schema.rs::
/// lifetime_band_range_is_not_expressed_by_the_generated_schema` records that gap). So the refusal
/// lives here, on load, and not only in the compiler: a profile is a JSON file that outlives the
/// compiler that wrote it (§6.5), and a hand-edited artifact, an artifact from an older compiler or
/// one from a future compiler all walk straight past a compiler-side check. C4 is fail-closed
/// (§5.4) — the model refuses what it cannot execute, at the boundary.
///
/// What is refused is not hypothetical: one arithmetic slip in the per-task offset §5.3 requires
/// puts a sticky patrol above the safety net, where it holds `MOVEMENT` through a corpse run.
fn deserialize_band<'de, D>(deserializer: D) -> Result<u8, D::Error>
where
    D: Deserializer<'de>,
{
    let band = u8::deserialize(deserializer)?;
    if !GOAL_BAND.contains(&band) {
        return Err(serde::de::Error::custom(format!(
            "scheduler band {band} is outside ADR 07 §7.2's Goal band of {}..={}; a band above it \
             outranks the band 90-99 safety net and a band below it is outranked by opportunistic \
             work",
            GOAL_BAND.start(),
            GOAL_BAND.end()
        )));
    }
    Ok(band)
}

/// How long a task lives and what it holds while alive (C3, §5.3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum Lifetime {
    /// The foreground task. Acquires its ops' channels as needed.
    Exclusive,
    /// A concurrent task holding `channels` at `band` until `terminate_on` (`#sticky`, 311 uses).
    ///
    /// This is the case ADR-000 §4.1 calls out: a sticky patrol holds
    /// [`Channel::Movement`] while a foreground turn-in holds [`Channel::Interaction`], and the two
    /// coexist. A `#completewith`-only task becomes `Background` with an *empty* channel set, so it
    /// rides along without contending (§7.3.3 task 5).
    Background {
        /// Channels claimed for the task's lifetime. May be empty.
        channels: Vec<Channel>,
        /// Scheduler band, **30..=49** — the Goal band of ADR-000 §4.2, offset by task order so two
        /// sticky tasks cannot deadlock. §7.2 pins `minimum: 30, maximum: 49`.
        ///
        /// The range is enforced **on load** by [`deserialize_band`], because neither the type nor
        /// the schema generated from it can carry the bound. The compiler that assigns the band
        /// enforces the same [`GOAL_BAND`] on the way out; both halves are needed, and neither is
        /// redundant — see [`deserialize_band`] for why a compiler-side check alone is not enough.
        #[serde(deserialize_with = "deserialize_band")]
        band: u8,
        /// Voluntary, permanent termination condition. Normally the linked task's completion or the
        /// task's own `complete_when`. Distinct from *suspension*, which is involuntary loss of a
        /// lease to a higher band (§5.3).
        terminate_on: Predicate,
    },
}

/// Who decides that a task is done (C3, §5.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum CompletionSource {
    /// The task's own `complete_when` decides.
    OwnPredicate,
    /// `#completewith` (5,469 uses) — the named task's completion completes this one.
    ///
    /// Always a **resolved index, never a dangling label**. RXPGuides ships the opposite: its
    /// `guide.labels[…]` lookup returns nil and the edge silently never fires (§3.1). The compiler
    /// resolves every link and emits a hard diagnostic for any unresolved label, so an unresolvable
    /// link cannot reach the artifact (§5.3). At runtime, a link whose target is skipped inherits
    /// the target's terminal state.
    LinkedTo(TaskId),
}

/// What to do when a predicate evaluates `Unknown` rather than true or false (C1, §5.1.2).
///
/// `satisfied()` returns `Truth { True, False, Unknown }`, not `bool` (kernel change K2), because
/// the API forces it: the quest log has no readiness contract and no events, `is_complete` is a
/// documented tri-state whose `-1` means *failed* and is truthy in Lua, and the profession API
/// returns safe defaults indistinguishable from real zeroes.
///
/// The failure mode this exists to kill is `Unknown → false → "not complete" → redo the step`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum UnknownPolicy {
    /// The task does not start; the runner reports `blocked_reason` and nothing advances.
    ///
    /// The compiler's default for `complete_when` on any task carrying a
    /// [`Delegate`](crate::kernel::Op::Delegate) or an irreversible op — turn-in, abandon, destroy,
    /// deathskip (§5.1.2).
    Block,
    /// Yield this tick and retry next; after `budget_ticks` escalate to [`UnknownPolicy::Block`].
    /// The compiler's default for `complete_when`.
    Defer {
        /// Tick budget before escalation, e.g. `60` in §7.3.3.
        budget_ticks: u16,
    },
    /// Proceed as if not satisfied — redo the work. Safe only when the work is idempotent; the
    /// compiler's default for `applies_when` on pure-travel tasks.
    TreatFalse,
    /// Proceed as if satisfied — skip the work. **Never a default.** Requires an explicit compiler
    /// opt-in and emits a diagnostic (§5.1.2).
    TreatTrue,
}

/// A unit of guide work: one authored `step`, lowered into an ordered container of ops (§7.1).
///
/// Requirement P1 lives here: [`deps`](Self::deps) is a `Vec`, not an `Option`. The corpus has
/// 1,246 distinct `#completewith` labels and 349 `#requires` edges, so non-adjacent dependency is
/// the norm rather than an edge case, and authors already work around single-`#requires` steps with
/// an empty placeholder step (the `--XXREQ` hack the compiler folds away, §7.3.3 task 4).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Task {
    /// This task's index in [`RuntimeProfile::tasks`](crate::kernel::RuntimeProfile::tasks).
    pub id: TaskId,
    /// **Multi-dependency** predecessor set, from `#requires` (349 uses). Plural by design (P1).
    pub deps: Vec<TaskId>,
    /// Whether failing or skipping this task stalls the profile. `#optional` (3,067) ⇒ `false`.
    pub blocking: bool,
    /// How long the task lives and what it holds — from `#sticky`.
    pub lifetime: Lifetime,
    /// Who decides the task is done — from `#completewith`.
    pub completion: CompletionSource,
    /// Gate: whether the task applies at all. Re-evaluated against live state every tick; the
    /// cursor says where we are, never what is true (§6.1).
    pub applies_when: Option<Predicate>,
    /// **The only completion authority** (C1). `.complete` (7,218) lowers here.
    pub complete_when: Option<Predicate>,
    /// Failure / abandon condition, e.g. a timed quest's failed state (`is_complete == -1`, §8).
    pub abort_when: Option<Predicate>,
    /// What to do when any of the three predicates reads `Unknown`.
    pub unknown_policy: UnknownPolicy,
    /// **Ordered** operations — the step-as-container.
    pub ops: Vec<Op>,
    /// The NPC that `.accept` / `.turnin` / `.train` act on, in `.target`'s step-wide form (13,352
    /// uses).
    ///
    /// `None` is a **correct** value, not an omission. Quest 983's ender is
    /// `gameobject_involvedrelation` entry 17182, not a creature, which is exactly why §7.3.3 task 6
    /// has a `.turnin` with no `.target`. A schema that assumed every turn-in has an NPC target
    /// would emit a null target and stall (§7.3.2, §8).
    pub interact_target: Option<NpcRef>,
    /// Per-task combat override (C6). `None` means use
    /// [`ProfileDefaults::combat`](crate::kernel::ProfileDefaults::combat) — which is why 18,404 of
    /// 23,894 corpus steps (77.0%) carry no policy at all (§5.6).
    ///
    /// That figure counts steps carrying none of `.mob`, `.unitscan`, `.solo`, `.group` or
    /// `.dungeon`, i.e. the steps for which every field of [`CombatPolicy`] would have to be
    /// defaulted. An earlier revision said `16,438`, which was `23,894 − 7,456` — a step count minus
    /// an *instance* count, and `.mob` occurs 7,456 times across only 3,526 steps (ADR 07 §9 item
    /// 28).
    pub combat: Option<CombatPolicy>,
    /// Items to keep while this task is active. `.collect` (3,044) and `.addquestitem` (32).
    pub loot_filter: Vec<LootRule>,
    /// Which quests this task exists to serve, from the `.requires quest,<id>` command form (445
    /// uses). Used for whole-chain pruning when a quest is unobtainable (§4.1). Distinct from the
    /// `#requires` *metadata* tag, which lowers to [`deps`](Self::deps).
    pub serves_quests: Vec<QuestId>,
    /// Behaviours to switch off for the duration. `#ignorecorpse` (1) ⇒ `[BehaviorId::Corpse]`, the
    /// only lever that makes deliberate death work against the band 90-99 safety net (§8).
    pub suppress: Vec<BehaviorId>,
    /// Forward jump target, from the 2-argument `.maxlevel` form (§4.1).
    pub jump_to: Option<TaskId>,
    /// Where this task came from in the guide pack.
    pub source: SourceSpan,
}

/// Where a preempted task resumes from (C3, §5.3, kernel change K8).
///
/// ADR-000 asserts resume-after-preemption but never defines the unit; this struct is that
/// definition. Three levels because the corpus needs three: a 15-waypoint patrol circuit
/// (`A-11-23.lua:218-231`) preempted by combat must not restart the circuit — that is a
/// minutes-long regression per interruption — and `op_index` alone is insufficient because one
/// [`Op::Travel`] carries the whole route.
///
/// The cursor restores position and is **never trusted for truth**: preconditions are re-checked
/// against live state every tick (§6.1, §8).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ResumeCursor {
    /// Which task.
    pub task: TaskId,
    /// Which op within that task's ordered `ops`.
    pub op_index: u16,
    /// Which waypoint within that op's route, if it is a travel op.
    pub waypoint: u16,
    /// Circuit iteration, for `#loop` tasks.
    pub loop_iter: u32,
}
