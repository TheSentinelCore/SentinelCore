//! Lowering from RestedXP guide source into the **kernel artifact** of ADR
//! `07_RUNTIME_PROFILE_SCHEMA`.
//!
//! This is a second, additive lowering. It does not replace, wrap or derive from
//! [`Compiler::compile`](crate::Compiler::compile), which still produces the ADR-05
//! [`sentinel_models::runtime::RuntimeProfile`] that the Lua runtime executes today and is byte-for-byte
//! unchanged by anything here. The two artifacts coexist deliberately (see
//! [`sentinel_models::kernel`]).
//!
//! # What this module owns
//!
//! * [`lower_route`] / [`WaypointPool`] — routes and the interned coordinate pool.
//!   [`lower_route`] is the **only** route builder: `task_graph::flush_route` turns surviving travel
//!   actions into [`Movement`]s and hands them straight to it, so a route's kind, its medium, its
//!   indices and its boundaries are decided in one place. They were not always — `flush_route` used
//!   to build routes itself and hardcode `TravelMode::Any`, which left this module's medium mapping
//!   unreachable from any compile while tests went on pinning it.
//!   **The coordinate transform is not here at all**: it is
//!   [`sentinel_models::movement::resolve_coordinate`], which the importer calls, and this module
//!   held a second complete copy of it (`parse_movement`) that no compile ever ran while the live
//!   one dropped all 929 raw-world corpus lines.
//! * [`lower_predicate`] — the `02_DATA_MODEL.md` §23 condition DSL → [`Predicate`].
//! * [`archetype`] — C2 gate resolution. Every `<<` tail, archetype-filter `#directive` and
//!   `.dungeon` argument is decided here against one concrete
//!   [`Archetype`](sentinel_models::kernel::Archetype), so no gate survives into the artifact.
//! * `task_graph` — the step graph. `#label` / `#requires` / `#completewith` / `#sticky` /
//!   `#optional` become [`Task`](sentinel_models::kernel::Task) edges, lifetimes and flags, and the
//!   label vocabulary is consumed rather than carried. It also owns the two predicates the guide
//!   never writes down: the `QuestInLog` gate a completion objective implies, and the
//!   `QuestTurnedIn` a background farm terminates on when this artifact performs the hand-in.
//! * `meta` — the guide-block header (`#name` / `#group` / `#subgroup` / `#version` / `#next`) into
//!   [`GuideMeta`](sentinel_models::kernel::GuideMeta), with each entry's own `<<` tail decided by
//!   the same [`archetype`] resolver.
//! * `combat` — C6. `.mob` and `.unitscan` into a [`CombatPolicy`](sentinel_models::kernel::CombatPolicy),
//!   and the profile-level default every per-task override is measured against — a task whose
//!   derivation lands on the default carries none.
//!
//! # Two rules the tests exist to hold
//!
//! (The two about coordinates moved with the transform, to
//! [`sentinel_models::movement`] and `compiler/tests/kernel_coordinates.rs`.)
//!
//! 1. **A run that changes travel medium is split, never flattened and never refused.** `Route`
//!    carries one `mode`; a medium change is a run boundary exactly as an intervening op is.
//! 2. **An unmappable expression is a hard error.** The ADR-05 path substitutes
//!    `RuntimeCondition::AlwaysTrue` and records a diagnostic; the kernel's 24 [`Predicate`]
//!    variants contain no always-true by design, and omitting the leaf instead would be fail-open
//!    by another name.

pub mod archetype;
mod combat;
mod meta;
mod predicate;
mod route;
mod task_graph;

pub use predicate::{lower_predicate, QuestMeta};
pub use route::{lower_route, Movement, WaypointPool};
pub(crate) use combat::profile_default as default_combat_policy;
pub(crate) use meta::lower_guide_meta;
pub(crate) use task_graph::lower_task_graph;
pub(crate) use task_graph::profile_default_unknown_policy as default_unknown_policy;

use std::collections::BTreeSet;

use sentinel_models::kernel::{Lifetime, Predicate, QuestId, Task};

/// The §5.4 (C4) tag census: every op and predicate tag `tasks` actually references.
///
/// # Computed, never transcribed
///
/// C4 makes the artifact **fail-closed**: a loader refuses any tag it does not implement, and
/// `tags_used` is what it checks before executing anything. §5.10 states the cost of getting it
/// wrong in each direction, and they are different failures — a **spurious** tag makes a
/// fail-closed kernel refuse an artifact it could have run, while a **missing** tag lets the check
/// pass on an artifact the kernel cannot fully evaluate, which defeats the check entirely. A
/// hand-maintained list is wrong the first time a lowering changes; §7.3.3's own printed list was
/// wrong in *both* directions at once (four tags no task used, one tag task 7 used and the list
/// omitted) until the R1 audit recomputed it.
///
/// # What is walked
///
/// Every op, and all four predicate slots — `applies_when`, `complete_when`, `abort_when`, and the
/// `terminate_on` that lives inside a [`Lifetime::Background`] payload rather than on the task.
/// A census that walked only the task's own three slots would miss every background termination
/// condition. `And` / `Or` / `Not` recurse: the combinator's own tag *and* its operands' are all
/// referenced, and a loader that cannot evaluate a leaf cannot evaluate the tree it is in.
///
/// # The spelling
///
/// Tags are read off the **serialized** form rather than from Rust variant names. `tags_used` is a
/// list of wire tags — what a Lua loader compares against — so a census taken from variant names
/// could agree with the model while disagreeing with the artifact. The result is sorted and
/// deduplicated: a census is a set, and sorted is the only spelling that does not move when an
/// unrelated task is added, reordered or elided, which is what a digest over the emitted bytes
/// depends on.
pub(crate) fn tag_census(tasks: &[Task]) -> Vec<String> {
    let mut observed: BTreeSet<String> = BTreeSet::new();
    for task in tasks {
        for op in &task.ops {
            let serialized = match serde_json::to_value(op) {
                Ok(serialized) => serialized,
                Err(error) => panic!("a kernel op must serialize, got: {error:?} for {op:?}"),
            };
            observed.insert(wire_tag(&serialized));
        }
        if let Lifetime::Background { terminate_on, .. } = &task.lifetime {
            collect_predicate_tags(terminate_on, &mut observed);
        }
        for predicate in [&task.applies_when, &task.complete_when, &task.abort_when]
            .into_iter()
            .flatten()
        {
            collect_predicate_tags(predicate, &mut observed);
        }
    }
    observed.into_iter().collect()
}

fn collect_predicate_tags(predicate: &Predicate, out: &mut BTreeSet<String>) {
    let serialized = match serde_json::to_value(predicate) {
        Ok(serialized) => serialized,
        Err(error) => panic!("a kernel predicate must serialize, got: {error:?} for {predicate:?}"),
    };
    out.insert(wire_tag(&serialized));
    match predicate {
        Predicate::And(children) | Predicate::Or(children) => {
            for child in children {
                collect_predicate_tags(child, out);
            }
        }
        Predicate::Not(child) => collect_predicate_tags(child, out),
        _ => {}
    }
}

/// The `type` an adjacently tagged value serialized with.
///
/// Panics rather than substituting a placeholder: every enum the kernel dispatches on is adjacently
/// tagged by C4 (§5.4), so a value without a `type` means the model stopped satisfying C4 — and a
/// census that quietly filed such a value under `"unknown"` would emit a tag no loader implements,
/// turning a model defect into a refused artifact with no explanation attached.
fn wire_tag(serialized: &serde_json::Value) -> String {
    match serialized.get("type").and_then(serde_json::Value::as_str) {
        Some(tag) => tag.to_owned(),
        None => panic!(
            "ADR 07 §5.4 (C4): every enum the kernel dispatches on is adjacently tagged with \
             `type`, got: {serialized:?}"
        ),
    }
}

/// Everything that stops a guide line becoming artifact.
///
/// Every variant is a **refusal**, never a repair or a fallback value. That posture is the whole
/// point: a repaired coordinate and a correct one are indistinguishable at every later stage, and a
/// substituted predicate gates nothing.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum LoweringError {
    /// A movement line's own refusals are **not** here.
    ///
    /// Arity, an unmappable zone, a malformed coordinate — those are decided by
    /// [`sentinel_models::movement::resolve_coordinate`] and rendered by the importer as
    /// `MALFORMED_MOVEMENT_ARITY` / `UNMAPPED_GOTO_ZONE` / `MALFORMED_MOVEMENT_COORDINATE`
    /// diagnostics against the line, which then reaches the compiler as a travel action with
    /// `position: None`. They used to be four variants here, raised by a `parse_movement` no compile
    /// called, while the live path made those same decisions differently and silently.
    ///
    /// `MixedTravelModes` is gone for a different reason: a run that changes medium is **split**,
    /// not refused (see [`lower_route`]). Refusing cost 9 of the corpus's 277 guide blocks their
    /// whole artifact.

    /// The metadata provider could not answer what an objective requires.
    ///
    /// Distinct from an answer of `0`: `Some(0)` is "this objective needs no count" — quest 984 is
    /// satisfied by area discovery and has no `Req*` columns at all — while `None` is "the world
    /// database could not answer". Collapsing the second into the first manufactures an exploration
    /// objective out of a lookup failure, and the resulting task completes the instant it is
    /// evaluated.
    #[error(
        "quest {quest} objective {index}: the world database could not supply a required count; \
         `need: 0` is a real answer and must not be invented for a lookup failure"
    )]
    UnknownObjective {
        /// The quest.
        quest: QuestId,
        /// 1-based objective index, as authored.
        index: u8,
    },

    /// A §23 condition expression could not be mapped to a [`Predicate`](sentinel_models::kernel::Predicate).
    ///
    /// The ADR-05 compiler fails open here (diagnostic plus `RuntimeCondition::AlwaysTrue`). The
    /// kernel cannot: it has no always-true variant, and dropping the leaf out of an `And`/`Or`
    /// leaves a predicate that still looks well-formed while gating on less than the author wrote.
    #[error("condition expression `{expression}` could not be mapped to a Predicate: {reason}")]
    UnmappablePredicate {
        /// The whole expression, so the author can find it.
        expression: String,
        /// Why it could not be mapped.
        reason: String,
    },

    /// A `<<` gate, an archetype-filter directive value or a `.dungeon` argument used a token the
    /// closed vocabulary of [`archetype`] does not contain.
    ///
    /// A refusal, like every variant above, and for the same reason stated more sharply: the three
    /// alternatives to failing — skipping the token, treating it as always-true, treating it as
    /// always-false — each silently change which steps a real character runs, and none of them
    /// leaves a trace. RXPGuides itself refuses (`addon.error("Invalid function call")`).
    ///
    /// Both fields are carried because neither is sufficient: the token alone is not greppable in a
    /// 138,000-line guide pack, and the expression alone does not say which of its tokens was the
    /// problem.
    #[error("gate `{expression}`: `{token}` is not gate vocabulary")]
    UnknownGateToken {
        /// The whole expression, verbatim.
        expression: String,
        /// The token that was not recognised, after normalisation.
        token: String,
    },
}
