//! Sentinel Questing — RestedXP guide importer (Phase 4, Waves 1-3).
//!
//! ## Wave 1 – Core Parser
//!
//! ```text
//! GuideSplitter  ->  Lexer  ->  StepBuilder  ->  LabelGraph
//! ```
//!
//! It turns a raw `RXPGuides.RegisterGuide([[ ... ]])` source string into a structured
//! [`ParsedGuide`] AST. Label-reference problems are surfaced as diagnostics (see
//! [`LabelGraph::unresolved`]).
//!
//! ## Wave 2 – Project Builder
//!
//! [`ProjectBuilder`] maps a [`ParsedGuide`] into a `sentinel_models::Project`, resolving
//! NPCs, quests, and objects through the [`QueryClient`] trait. Unresolved entities are
//! recorded as diagnostics rather than hard errors.
//!
//! ## Wave 3 – Name Hints
//!
//! When NPCs cannot be resolved via explicit `.target`, hints are extracted from the
//! RestedXP color-coded text (e.g., `|cRXP_FRIENDLY_Name|r`).

mod coverage;
mod directives;
mod guide_splitter;
mod label_graph;
mod lexer;
mod name_hints;
mod project_builder;
mod step_builder;

pub use coverage::{CommandTally, CoverageReport};
pub use directives::{
    DirectiveAlias, DirectiveAliasTable, DirectiveDiagnostic, DIRECTIVE_ALIASES, KNOWN_DIRECTIVES,
};
pub use guide_splitter::{extract_guide_blocks, GuideBlock, GuideBlockError, GuideSplitter, SplitGuide};
pub use label_graph::{LabelDef, LabelGraph, LabelGraphBuilder, LabelRef};
pub use lexer::{LexedGuide, Lexer, Token};
pub use project_builder::ProjectBuilder;
pub use step_builder::StepBuilder;

use serde::{Deserialize, Serialize};

/// 1-based line number in the original guide source (for source mapping, ADR `03` §26).
pub type SourceLineNo = usize;

/// Split a directive value into `(head, gate)` on the **first** `<<`.
///
/// `#label UldaLoch << Mage` -> `("UldaLoch", Some("Mage"))`; `#optional << Dwarf Paladin` ->
/// `("", Some("Dwarf Paladin"))` (the lexer hands that directive a value with no head at all);
/// `#label Un'Goro End` -> `("Un'Goro End", None)`.
///
/// Never tokenize on whitespace: 4 label names contain a space and every gate is a whitespace-AND
/// expression, so a whitespace split truncates both. Commands split on the *last* `<<`
/// ([`lexer::Lexer::lex_command`]) because their head is free text; a directive value never
/// contains two `<<`, so first-match is the correct and stricter rule here.
pub(crate) fn split_directive_gate(value: &str) -> (String, Option<String>) {
    match value.find("<<") {
        Some(idx) => {
            let head = value[..idx].trim().to_string();
            let tail = value[idx + 2..].trim();
            let gate = if tail.is_empty() { None } else { Some(tail.to_string()) };
            (head, gate)
        }
        None => (value.trim().to_string(), None),
    }
}

/// A raw source line with its original line number.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocatedLine {
    pub line_no: SourceLineNo,
    pub text: String,
}

/// A `#directive` inside a step (e.g. `#sticky`, `#label TOME`, `#completewith TOME`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Directive {
    pub name: String,
    pub value: Option<String>,
    pub line: SourceLineNo,
    /// The raw directive name as written, when tolerated as a typo of `name` (IF5).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub original: Option<String>,
}

/// A `.command` inside a step (e.g. `.accept 1598 >> Accept ...`, `.goto Zone,x,y`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Command {
    pub name: String,
    pub args: Vec<String>,
    pub note: Option<String>,
    pub line: SourceLineNo,
    /// Trailing `<< ClassName` / `<< Class1/Class2` / `<< !Class` suffix on this command line
    /// (IF3), stripped out of `args`/`note` and carried separately.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub class_restriction: Option<String>,
}

/// A parsed `step` block: a unit of guide progression.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Step {
    /// Position of this step within the guide (0-based).
    pub index: usize,
    /// Source line where the `step` marker appeared.
    pub line: SourceLineNo,
    /// Source line of the **last** token that belongs to this step — the line before the next
    /// `step` marker, or the guide's last content line for the final step.
    ///
    /// Tracked over every token, not over commands and directives only. `A-11-23.lua:265-268` is
    /// the author's `#requires` placeholder, and its last line is the bare `--XXREQ Placeholder …`
    /// comment: a span taken from directives alone reports it as `266-267` and loses the line the
    /// author actually wrote the note on. ADR `07_RUNTIME_PROFILE_SCHEMA` §7.3.3 spans it `265-268`.
    ///
    /// `#[serde(default)]` yields `0` for a `Step` written before this field existed, which is
    /// below every real line number; consumers take `line_end.max(line)` so a legacy step reports
    /// its marker line rather than line zero.
    #[serde(default)]
    pub line_end: SourceLineNo,
    /// Class/faction restrictions from `step << ...` (e.g. `["!Human"]`, `["Priest","Mage","Warlock"]`).
    pub conditions: Vec<String>,
    /// The raw, unsplit `<<` tail of the `step` marker, when present.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<String>,
    pub directives: Vec<Directive>,
    pub commands: Vec<Command>,
    /// Instruction / chat-bubble text lines (including `>>` continuations and `+` chat lines).
    pub text: Vec<String>,
    /// NPC name hints extracted from notes (Wave 3).
    #[serde(default)]
    pub npc_name_hints: Vec<String>,
}

/// A guide-level header (`#name ...`, `#group ...`, `<< Alliance`, ...).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Header {
    pub key: String,
    pub value: String,
    pub line: SourceLineNo,
}

/// Fully parsed guide: headers, steps, and the resolved label graph.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ParsedGuide {
    pub headers: Vec<Header>,
    pub steps: Vec<Step>,
    pub labels: LabelGraph,
    /// What ingest tolerated **loudly** — one entry per normalised `#directive` occurrence
    /// (ADR `07` §5.10). Omitted from the wire when empty, like every other optional carrier in
    /// this crate, so a guide with no typos serializes exactly as it did before this field existed.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub diagnostics: Vec<DirectiveDiagnostic>,
}

/// Errors that abort parsing. Label-reference problems are *not* errors here — they are
/// surfaced as diagnostics in [`LabelGraph::unresolved`] (ADR `03` §18).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ImportError {
    #[error("no RegisterGuide block found in source")]
    NoGuideBlock,
    #[error("unterminated RegisterGuide block (missing ]])")]
    UnterminatedGuideBlock,

    /// A `#token` outside the closed vocabulary of [`KNOWN_DIRECTIVES`] and [`DIRECTIVE_ALIASES`].
    ///
    /// A refusal rather than a skip, and rather than a similarity guess. The three alternatives to
    /// failing — dropping the directive, guessing its nearest canonical neighbour, or keeping it
    /// verbatim for a later stage to ignore — each silently change which steps a real character
    /// runs, and none of them leaves a trace. RXPGuides itself refuses
    /// (`addon.error("Invalid function call")`, ADR `07` §3.1).
    #[error(
        "line {line}: `#{name}` is not a known directive; the vocabulary is closed, so a new \
         token is a table edit and a version bump, not a silent normalisation"
    )]
    UnknownDirective {
        /// The token as authored, without the leading `#`.
        name: String,
        /// Source line, so it is findable in a 138,000-line guide pack.
        line: SourceLineNo,
    },

    /// A missing-space alias — the one entry of [`DIRECTIVE_ALIASES`] that supplies a value — met a
    /// line that already carried one.
    ///
    /// Merging them would require a rule for which value wins, and there is none. `The Burning
    /// Crusade.lua:211` carries no value, so this is a guard against a *future* occurrence rather
    /// than a present one.
    #[error(
        "line {line}: `#{name}` normalises to a directive carrying `{implied}`, but the line \
         already carries `{found}`; two values cannot be merged and neither can be preferred"
    )]
    AliasValueConflict {
        /// The token as authored, without the leading `#`.
        name: String,
        /// Source line.
        line: SourceLineNo,
        /// The value the alias supplies.
        implied: String,
        /// The value the line already carried.
        found: String,
    },
}

/// Top-level entry point: raw guide source -> structured [`ParsedGuide`].
pub fn parse_guide(source: &str) -> Result<ParsedGuide, ImportError> {
    let split = GuideSplitter::split(source)?;
    let LexedGuide { tokens, diagnostics } = Lexer::tokenize(&split)?;

    let headers: Vec<Header> = tokens
        .iter()
        .filter_map(|t| match t {
            Token::GuideHeader { key, value, line } => Some(Header {
                key: key.clone(),
                value: value.clone(),
                line: *line,
            }),
            _ => None,
        })
        .collect();

    let steps = StepBuilder::build(&tokens);
    let labels = LabelGraphBuilder::resolve(&steps)?;

    Ok(ParsedGuide {
        headers,
        steps,
        labels,
        diagnostics,
    })
}

/// Bundle-level error: either a malformed block boundary ([`GuideBlockError`], PR1b-iii
/// hardening) found while scanning, or an error parsing an otherwise well-bounded block
/// ([`ImportError`]).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum GuideBundleError {
    #[error(transparent)]
    Block(#[from] GuideBlockError),
    #[error(transparent)]
    Parse(#[from] ImportError),
}

/// Bundle entry point (IF6): split a source containing N concatenated `RegisterGuide` blocks
/// (`The Burning Crusade.lua`: 253) and parse each exactly as [`parse_guide`] parses a
/// single-guide file — one [`ParsedGuide`] result per block, in source order. Each parsed
/// guide's `Header.line` / `Step.line` / `Directive.line` / `Command.line` / `LabelRef.line`
/// values are shifted by the block's `line_offset`, so they are bundle-file-absolute (PR1b-iii
/// line-offset fix — previously block-relative and dormant). A malformed block boundary
/// surfaces as `GuideBundleError::Block` without aborting the scan of subsequent blocks
/// (PR1b-iii hardening, see [`extract_guide_blocks`]).
pub fn parse_guide_bundle(source: &str) -> Vec<Result<ParsedGuide, GuideBundleError>> {
    extract_guide_blocks(source)
        .into_iter()
        .map(|block| {
            let block = block?;
            let mut guide = parse_guide(&block.source)?;
            shift_guide_lines(&mut guide, block.line_offset);
            Ok(guide)
        })
        .collect()
}

/// Shift every `SourceLineNo` recorded in `guide` by `offset`, turning block-relative line
/// numbers into bundle-file-absolute ones (PR1b-iii).
fn shift_guide_lines(guide: &mut ParsedGuide, offset: usize) {
    for header in &mut guide.headers {
        header.line += offset;
    }
    for step in &mut guide.steps {
        step.line += offset;
        step.line_end += offset;
        for directive in &mut step.directives {
            directive.line += offset;
        }
        for command in &mut step.commands {
            command.line += offset;
        }
    }
    for def in guide.labels.definitions.values_mut().flatten() {
        def.line += offset;
    }
    for label_ref in guide
        .labels
        .references
        .iter_mut()
        .chain(guide.labels.unresolved.iter_mut())
        .chain(guide.labels.requires.iter_mut())
        .chain(guide.labels.unresolved_requires.iter_mut())
    {
        label_ref.line += offset;
    }
    // A normalisation diagnostic whose line is block-relative points an author at the wrong line of
    // a 138,000-line file, which is worse than not reporting at all.
    for diagnostic in &mut guide.diagnostics {
        match diagnostic {
            DirectiveDiagnostic::Normalised { line, .. } => *line += offset,
        }
    }
}
