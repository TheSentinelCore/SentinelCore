//! Guide-import carriers: the RestedXP task graph as it survives the importer boundary.
//!
//! RestedXP expresses step ordering with four directives — `#label`, `#requires`,
//! `#completewith`, `#optional` — and gates every one of them (plus `step` markers and
//! `.commands`) with a trailing `<< …` audience tail. None of that had a home in
//! [`Operation`](super::Operation) before, so the whole task graph died at the importer boundary.
//!
//! Nothing here is *resolved*: labels stay raw strings and gates stay raw expressions. Resolution
//! of a label to a task id belongs to the compiler, which needs the raw name to report a useful
//! diagnostic; evaluation of a gate against a resolved archetype belongs to the same later pass.

use serde::{Deserialize, Serialize};

/// 1-based line number in the original guide source, for diagnostics and provenance.
pub type SourceLineNo = usize;

/// A raw `<<` tail, carried verbatim and **unparsed**.
///
/// Grammar (measured over every `<<` tail in the RestedXP corpus):
///
/// ```text
/// Gate     := AndGroup (WS AndGroup)*     -- whitespace = AND
/// AndGroup := Term ('/' Term)*            -- slash      = OR
/// Term     := '!'? Ident                  -- per-token negation
/// ```
///
/// The vocabulary is **not** class-only: ten classes plus the `DK`/`Pala` abbreviations, ten
/// races, `Alliance`/`Horde`, the eras `tbc`/`wotlk`/`classic`/`era`/`sod`, a level bound, and
/// the `skip` disable sentinel. Anything that narrows this to a class list loses the majority of
/// its uses, which is why the expression has to survive intact this far.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GuideGate(pub String);

/// A directive entry plus the gate that decides whether it applies to a resolved archetype.
///
/// Gate-unsatisfied entries are dropped at resolution; whatever survives is ANDed. That is what
/// makes `#requires cloth1` + `#requires cloth2` (both ungated — a genuine AND) and
/// `#requires FlyMoongladeH << Horde` + `#requires FlyMoongladeA << Alliance` (a
/// faction-exclusive OR that resolves away) both come out right. Merging the gate into a single
/// per-step field destroys that distinction before resolution can use it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Gated<T> {
    pub value: T,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<GuideGate>,
    pub line: SourceLineNo,
}

/// The target of a `#completewith` directive.
///
/// `next` is the **only** reserved word in the directive's value space — `end` is a real label.
/// Adjacently tagged (`{type, payload}`) like every other enum that may cross into a profile.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum CompleteWithTarget {
    /// The reserved literal `next`: "complete together with the following step".
    Next,
    /// A `#label` name, raw and unresolved.
    Label(String),
}

/// Any step-body `#directive` without a typed carrier, preserved verbatim so nothing is silently
/// dropped a second time (`#xprate`, `#phase`, `#aldor`/`#scryer`, `#hardcore`, `#ssf`, …).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GuideDirective {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<GuideGate>,
    pub line: SourceLineNo,
}
