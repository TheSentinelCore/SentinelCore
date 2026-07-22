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
mod guide_splitter;
mod label_graph;
mod lexer;
mod name_hints;
mod project_builder;
mod step_builder;

pub use coverage::{CommandTally, CoverageReport};
pub use guide_splitter::{extract_guide_blocks, GuideBlock, GuideBlockError, GuideSplitter, SplitGuide};
pub use label_graph::{LabelGraph, LabelGraphBuilder, LabelRef};
pub use lexer::{Lexer, Token};
pub use project_builder::ProjectBuilder;
pub use step_builder::StepBuilder;

use serde::{Deserialize, Serialize};

/// 1-based line number in the original guide source (for source mapping, ADR `03` §26).
pub type SourceLineNo = usize;

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
    /// Class/faction restrictions from `step << ...` (e.g. `["!Human"]`, `["Priest","Mage","Warlock"]`).
    pub conditions: Vec<String>,
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
}

/// Errors that abort parsing. Label-reference problems are *not* errors here — they are
/// surfaced as diagnostics in [`LabelGraph::unresolved`] (ADR `03` §18).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ImportError {
    #[error("no RegisterGuide block found in source")]
    NoGuideBlock,
    #[error("unterminated RegisterGuide block (missing ]])")]
    UnterminatedGuideBlock,
}

/// Top-level entry point: raw guide source -> structured [`ParsedGuide`].
pub fn parse_guide(source: &str) -> Result<ParsedGuide, ImportError> {
    let split = GuideSplitter::split(source)?;
    let tokens = Lexer::tokenize(&split);

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
        for directive in &mut step.directives {
            directive.line += offset;
        }
        for command in &mut step.commands {
            command.line += offset;
        }
    }
    for label_ref in guide.labels.references.iter_mut().chain(guide.labels.unresolved.iter_mut()) {
        label_ref.line += offset;
    }
}
