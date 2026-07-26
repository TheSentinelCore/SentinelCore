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
//! * [`parse_movement`] / [`lower_route`] / [`WaypointPool`] — coordinates. Two authored systems
//!   normalise to one world frame, and the pool interns them.
//! * [`lower_predicate`] — the `02_DATA_MODEL.md` §23 condition DSL → [`Predicate`].
//! * [`archetype`] — C2 gate resolution. Every `<<` tail, archetype-filter `#directive` and
//!   `.dungeon` argument is decided here against one concrete
//!   [`Archetype`](sentinel_models::kernel::Archetype), so no gate survives into the artifact.
//! * `task_graph` — the step graph. `#label` / `#requires` / `#completewith` / `#sticky` /
//!   `#optional` become [`Task`](sentinel_models::kernel::Task) edges, lifetimes and flags, and the
//!   label vocabulary is consumed rather than carried.
//!
//! # Three rules the tests exist to hold
//!
//! 1. **A percentage must never survive compilation** (ADR 06 invariant 3). `zone,x,y` is
//!    zone-relative and `<uiMapId>/<mapId>,x,y` is already world; the discriminator is the `/` in
//!    field 0 and *nothing else*. A range test ("0..100 means percentage") reclassifies
//!    `.goto 1944/530,4341.30029,97.1` and transforms coordinates that were already correct.
//! 2. **A malformed line is refused, never repaired.** The corpus's 67 six-argument `.goto` lines
//!    are three unrelated defects and every plausible repair corrupts the other two.
//! 3. **An unmappable expression is a hard error.** The ADR-05 path substitutes
//!    `RuntimeCondition::AlwaysTrue` and records a diagnostic; the kernel's 24 [`Predicate`]
//!    variants contain no always-true by design, and omitting the leaf instead would be fail-open
//!    by another name.

pub mod archetype;
mod predicate;
mod route;
mod task_graph;

pub use predicate::{lower_predicate, QuestMeta};
pub use route::{lower_route, parse_movement, Movement, WaypointPool};
pub(crate) use task_graph::lower_task_graph;

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

/// One line of guide source, carried so a refusal can quote what it refused.
///
/// The diagnostic is the deliverable when a line is malformed: an author who is told only "arity
/// error" has to find the line themselves among 38,087 `.goto`s.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceLine<'a> {
    /// Guide file the line came from, e.g. `"A-11-23.lua"`.
    pub file: &'a str,
    /// 1-based line number within that file.
    pub line: u32,
    /// The line itself, verbatim.
    pub text: &'a str,
}

/// Everything that stops a guide line becoming artifact.
///
/// Every variant is a **refusal**, never a repair or a fallback value. That posture is the whole
/// point: a repaired coordinate and a correct one are indistinguishable at every later stage, and a
/// substituted predicate gates nothing.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum LoweringError {
    /// A movement line carried the wrong number of comma-separated arguments.
    ///
    /// The corpus's 67 six-argument `.goto` lines are three distinct defects — 60 stray trailing
    /// zero, 4 comma-typed decimal (`20.6,60,4` was meant to be `20.6,60.4`), 3 stray leading zero
    /// — and each defect's obvious repair produces wrong coordinates for the other two. Fewer than
    /// three arguments lands here too: a zone-only `.goto` names a destination but carries no
    /// coordinate, so it is not a waypoint.
    #[error(
        "{file}:{line}: `{text}` carries {found} comma-separated arguments; a movement line has \
         3..5 and a malformed one is refused, not repaired"
    )]
    MalformedArity {
        /// Guide file.
        file: String,
        /// Line number.
        line: u32,
        /// The line, verbatim, so the author can find it.
        text: String,
        /// How many arguments were actually present.
        found: usize,
    },

    /// The line is not one of the five coordinate-bearing movement commands.
    #[error("{file}:{line}: `{text}` is not a movement command")]
    NotAMovement {
        /// Guide file.
        file: String,
        /// Line number.
        line: u32,
        /// The line, verbatim.
        text: String,
    },

    /// A coordinate, radius or map id would not parse as a number.
    #[error("{file}:{line}: `{text}`: {what} `{value}` is not a number")]
    MalformedNumber {
        /// Guide file.
        file: String,
        /// Line number.
        line: u32,
        /// The line, verbatim.
        text: String,
        /// Which field, e.g. `"world X"`.
        what: String,
        /// The text that failed to parse.
        value: String,
    },

    /// The zone is absent from the measured [`zone table`](sentinel_models::zone::ZONE_TABLE), so
    /// its percentages cannot be converted.
    ///
    /// No position is emitted rather than a guessed one — ADR 06 invariant 3.
    #[error(
        "{file}:{line}: `{text}`: zone `{zone}` is absent from the measured zone table, so its \
         percentages cannot be converted to world coordinates"
    )]
    UnknownZone {
        /// Guide file.
        file: String,
        /// Line number.
        line: u32,
        /// The line, verbatim.
        text: String,
        /// The unresolvable zone name or ui map id.
        zone: String,
    },

    /// One route mixed travel media. [`Route`](sentinel_models::kernel::Route) carries a single
    /// `mode`, so picking one silently would drop a `.groundgoto`'s whole reason for existing:
    /// it overrides the engine's preferred line through mountain paths, caves and stairs (§5.7).
    #[error("{file}:{line}: `{text}` is {found:?} but the route so far is {expected:?}")]
    MixedTravelModes {
        /// Guide file.
        file: String,
        /// Line number.
        line: u32,
        /// The line, verbatim.
        text: String,
        /// The mode this line demands.
        found: sentinel_models::kernel::TravelMode,
        /// The mode the route already committed to.
        expected: sentinel_models::kernel::TravelMode,
    },

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

impl LoweringError {
    /// [`LoweringError::MalformedArity`] for `src`.
    fn arity(src: SourceLine<'_>, found: usize) -> Self {
        LoweringError::MalformedArity {
            file: src.file.to_owned(),
            line: src.line,
            text: src.text.to_owned(),
            found,
        }
    }
}
