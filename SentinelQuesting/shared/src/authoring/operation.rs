//! Operations — the primary authoring unit (ADR `02_DATA_MODEL` §11, ADR-007).
//!
//! Operations mirror how humans think about leveling ("Northshire", "Goldshire") rather than
//! individual guide steps. Each operation owns an ordered list of [`Action`]s.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::action::Action;
use super::guide::{CompleteWithTarget, Gated, GuideDirective, GuideGate};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Operation {
    pub id: Uuid,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_level: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maximum_level: Option<u8>,
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Gate expressions evaluated before the operation is entered.
    #[serde(default)]
    pub conditions: Vec<String>,
    /// `#sticky` directive (IF4): the operation should be revisited rather than treated as
    /// one-shot.
    #[serde(default)]
    pub sticky: bool,
    /// `#loop` directive (IF4): the operation should repeat rather than advance linearly.
    #[serde(default)]
    pub looping: bool,
    /// `#label NAME` definitions on this step, in source order, each with its own `<<` gate.
    /// A `Vec` because a single step may define more than one name.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub labels: Vec<Gated<String>>,
    /// `#requires LABEL` edges, raw and unresolved, each with its own `<<` gate.
    ///
    /// RestedXP has no separator: multiplicity is stacked lines, so each entry keeps its own
    /// gate. Gate-unsatisfied entries drop at resolution and whatever survives is ANDed.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requires: Vec<Gated<String>>,
    /// `#completewith TARGET` entries, raw and unresolved, each with its own `<<` gate.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub complete_with: Vec<Gated<CompleteWithTarget>>,
    /// `#optional` — the step is non-blocking (kernel `Task.blocking = false`) when its gate is
    /// satisfied. Bare in the overwhelming majority; a gate makes it archetype-conditional, so it
    /// collapses to a bool only after archetype resolution.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub optional: Option<Gated<()>>,
    /// The raw, unsplit `<<` tail of the `step` marker.
    ///
    /// Distinct from [`conditions`](Operation::conditions), which is the lossy `/`-only split
    /// kept for wire compatibility. New consumers read this.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<GuideGate>,
    /// Every other step-body `#directive`, verbatim (`#xprate`, `#phase`, `#aldor`, …).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub directives: Vec<GuideDirective>,
    /// This operation came from a *requirement placeholder* — a directive-only step that exists
    /// solely to park an extra `#requires` because RestedXP has no multi-requires syntax.
    /// Normally folded into the following real step and never emitted; `true` only for a trailing
    /// run with no step left to absorb it.
    ///
    /// MEASURED, so it is not mistaken for live signal: across the whole RestedXP corpus (23,894
    /// steps in 277 blocks, 52 placeholders) this is `true` on **0** of 23,842 operations — every
    /// placeholder is followed by a real step, so the trailing-run case never occurs. Its only
    /// exercise is a synthetic test. Kept rather than deleted because it is the only signal a
    /// consumer would have if a future guide *did* end on a placeholder, and dropping a
    /// `#[serde(default)]` field from a persisted authoring model breaks stored projects; do not
    /// read it as evidence that the fold is producing placeholder operations.
    #[serde(default)]
    pub placeholder: bool,
    /// Source line of the `step` marker this operation came from, 1-based.
    ///
    /// `None` for an editor-authored operation, which has no guide line — inventing `1` would be
    /// worse than admitting the gap, because a runtime failure would then point at a line that
    /// exists. Together with [`source_line_end`](Self::source_line_end) this is
    /// [`SourceSpan`](sentinel_models::kernel::SourceSpan)'s only honest source: the step's
    /// `#directive` entries carry lines of their own, but a step whose directives sit at `:212-214`
    /// really spans `:211-237` (ADR `07_RUNTIME_PROFILE_SCHEMA` §7.3.3 task 0).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_line_start: Option<u32>,
    /// Last source line belonging to this operation, 1-based and inclusive.
    ///
    /// A step owns every line from its marker up to the line before the next marker, which is why
    /// §7.3.3's eight spans tile `211-280` without a gap — including task 4's `265-268`, whose last
    /// line is the author's `--XXREQ` comment and not a directive at all.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_line_end: Option<u32>,
    pub actions: Vec<Action>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

fn default_true() -> bool {
    true
}

impl Operation {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: Vec::new(),
            sticky: false,
            looping: false,
            labels: Vec::new(),
            requires: Vec::new(),
            complete_with: Vec::new(),
            optional: None,
            gate: None,
            directives: Vec::new(),
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: Vec::new(),
            notes: None,
        }
    }
}
