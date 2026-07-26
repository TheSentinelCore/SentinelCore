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

/// The guide-block header: the directives above the first `step` that give the block its
/// identity and its place in the pack.
///
/// Only the five with a downstream consumer are typed here — they are exactly the KEEP rows of
/// ADR `07_RUNTIME_PROFILE_SCHEMA.md` §4.2's disposition table, and exactly the fields of
/// `kernel::GuideMeta`. `#displayname` is deliberately absent: §4.2 rules it DROP ("pure UI
/// chrome"), and it cannot stand in for `name` because a block may carry three of them, gated and
/// disagreeing (`A-11-23.lua:10-12`), while `name` is the single identity `#next` and `#include`
/// resolve against.
///
/// **Every carrier is a `Vec`, and it is not defensive.** Measured over all 277 blocks of the
/// pack: `#name` appears twice in one block (`A-1-11-Human.lua:2678`, gated `!Warlock`/`Warlock`),
/// `#subgroup` twice in four (`The Burning Crusade.lua:1165`, gated `!classic`/`classic`), `#next`
/// twice in seven. Those pairs are archetype ALTERNATIVES: collapsing them to one field here
/// would make the choice between them before anything that knows the archetype has run — the same
/// failure `Gated` exists to prevent for `#requires`. `#group` is the one key that is always
/// singular and never gated (277/277); it stays a `Vec` so that a future gated `#group` is a
/// selection problem rather than a silent drop.
///
/// `source_version` is the exception: `#version` is absent from 12 blocks, present at most once
/// in the rest, never gated, and every value in the pack parses as an integer. Narrowing it here
/// destroys nothing, because the raw string it was parsed from is still kept verbatim in
/// [`ImportMetadata::guide_version`](super::ImportMetadata).
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct GuideHeaders {
    /// `#name` — the identity `#next` and `#include` resolve against, unique within `group`.
    #[serde(default)]
    pub name: Vec<Gated<String>>,
    /// `#group` — catalogue bucket, and the namespace in which `name` is unique.
    #[serde(default)]
    pub group: Vec<Gated<String>>,
    /// `#subgroup` — level band or themed section.
    #[serde(default)]
    pub subgroup: Vec<Gated<String>>,
    /// `#version` — the upstream guide-pack revision.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_version: Option<u32>,
    /// `#next` — guide chaining. One entry per successor.
    ///
    /// A source line may name several with `;` (`#next 12-14 Loch Modan;12-14 Darkshore <<
    /// Warlock`, `A-1-11-Human.lua:2`), and each element becomes its own entry carrying that
    /// line's gate. `A-1-11-Dwarf-Gnome.lua:569` writes the very same two-successor shape as two
    /// separate gated `#next` lines instead, so the two authoring forms must — and do — flatten
    /// to the same thing.
    #[serde(default)]
    pub next: Vec<Gated<String>>,
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
