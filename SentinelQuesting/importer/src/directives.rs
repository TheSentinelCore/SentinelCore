//! The **closed, versioned directive vocabulary** and the P3 ingest posture built on it
//! (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.10, D6).
//!
//! Three rules, and they only work together:
//!
//! 1. **[`KNOWN_DIRECTIVES`] is closed.** A `#token` outside it is [`ImportError::UnknownDirective`]
//!    — a refusal, not a skip. RXPGuides itself refuses (`addon.error("Invalid function call (." ..
//!    tag .. ")")`, ADR 07 §3.1), and silently dropping what it cannot classify is precisely how the
//!    previous attempt at this reached 60% coverage.
//! 2. **[`DIRECTIVE_ALIASES`] is closed too, and it is a lookup — never a spell-checker.** Six
//!    measured typos, seven instances, each admitted by corroborating corpus evidence rather than by
//!    edit distance. Similarity cannot be the rule: `#completewithTBTurnins` is edit-distance **9**
//!    from its intended form and must normalise, while `#flyable` is edit-distance **2** from
//!    `#noflyable` and must not — it is the deliberate positive half of the pair, so folding it
//!    would send a flying character down the ground route.
//! 3. **Every normalisation is reported.** One [`DirectiveDiagnostic::Normalised`] per *occurrence*,
//!    carrying the source line. A repair nobody can see is indistinguishable from correct input at
//!    every later stage.
//!
//! The table is **versioned** so a change to it cannot be invisible: [`DirectiveAliasTable::version`]
//! and the table's exact contents are pinned together by
//! `importer/tests/directive_alias_table.rs::the_alias_table_is_versioned_and_its_exact_contents_are_pinned`,
//! so editing one without the other fails. A new typo is a one-line patch, a version bump and a
//! moved assertion — never a silent widening of what ingest tolerates.
//!
//! Not owned here: malformed `.goto` arity, which is decided by
//! `shared/src/movement.rs::resolve_coordinate` (`CoordinateError::Arity`) and rendered by
//! `project_builder.rs::build_travel_position` as a `MALFORMED_MOVEMENT_ARITY` diagnostic. Two
//! implementations of one refusal can disagree — and did: the compiler held a complete second copy
//! of that check behind an entry point no compile ever called.
//!
//! [`ImportError::UnknownDirective`]: crate::ImportError::UnknownDirective

use crate::{ImportError, SourceLineNo};
use serde::{Deserialize, Serialize};

/// One entry of the closed alias table: a typo the corpus actually contains, and what its author
/// meant.
///
/// `to_value` is `None` for a plain misspelling and `Some` only for the one **missing-space**
/// defect, where the typo swallowed its own argument.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DirectiveAlias {
    /// The token as authored, without the leading `#`. Matched case-insensitively.
    pub from: &'static str,
    /// The canonical directive it normalises to.
    pub to_name: &'static str,
    /// The value the alias supplies, when the typo swallowed one. `Some` implies the authored line
    /// must carry no value of its own — see [`ImportError::AliasValueConflict`].
    ///
    /// [`ImportError::AliasValueConflict`]: crate::ImportError::AliasValueConflict
    pub to_value: Option<&'static str>,
    /// How many times this typo occurs in the vendored guide pack. Re-derived from the corpus by
    /// `the_alias_occurrence_counts_match_the_corpus_they_were_measured_from`, so the table's own
    /// arithmetic cannot drift from the pack it describes.
    pub occurrences: u32,
    /// The corpus line(s) that admitted this entry. Line numbers are cited because the RestedXP
    /// guide pack is vendored data, not living code.
    pub evidence: &'static str,
}

/// The closed alias table, carried with its version so an edit is visible and reviewable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DirectiveAliasTable {
    /// Bumped on **any** edit to [`DirectiveAliasTable::entries`].
    ///
    /// * `1` — the three typos found by inspection: `compltewith`, `requries`, `lable`.
    /// * `2` — the measured six. `completewithTBTurnins`, `completewity` and `noflyasble` were
    ///   invisible to inspection: the first is a missing space rather than a misspelling, and the
    ///   other two occur once each in a 138,000-line pack.
    pub version: u32,
    /// The entries, in canonical-target then source order.
    pub entries: &'static [DirectiveAlias],
}

/// **Six tokens, seven instances** — the whole of the measured typo damage in the RestedXP pack.
///
/// ADR 07 §4.3's directive coverage table reads `MERGE | 6 | 7` from an independent derivation, and
/// the arithmetic closes against these entries.
///
/// CENSUS NOTE, so it is not re-chased: a raw `rg '#completewith next'` over the corpus finds
/// 2669 bare + 12 gated = 2681 lines, while the importer classifies 2683 `CompleteWithTarget::Next`
/// entries. The two extra are the `#compltewith next` typos at `The Burning Crusade.lua:17117` and
/// `:122325`, folded to `completewith` here. There is no lexing gap and no header-region line
/// involved — scanning all 277 blocks for a `Token::GuideHeader` keyed `completewith`/`compltewith`
/// returns zero. Any raw-grep baseline of `#completewith` undercounts by exactly these 2.
pub const DIRECTIVE_ALIASES: DirectiveAliasTable = DirectiveAliasTable {
    version: 2,
    entries: &[
        DirectiveAlias {
            from: "compltewith",
            to_name: "completewith",
            to_value: None,
            occurrences: 2,
            evidence: "The Burning Crusade.lua:17117, :122325 — transposed `te`/`et`",
        },
        // The one entry edit distance could never have found: 9 edits from `completewith`, and the
        // only reason it is safe is corroboration. `TBTurnins` is a real label defined at `:320`,
        // and the correctly spaced `#completewith TBTurnins` is used at `:301` in the same guide.
        DirectiveAlias {
            from: "completewithTBTurnins",
            to_name: "completewith",
            to_value: Some("TBTurnins"),
            occurrences: 1,
            evidence: "The Burning Crusade.lua:211 — a MISSING SPACE; label defined :320, spaced form used :301",
        },
        DirectiveAlias {
            from: "completewity",
            to_name: "completewith",
            to_value: None,
            occurrences: 1,
            evidence: "The Burning Crusade.lua:105447 — transposed final letters",
        },
        DirectiveAlias {
            from: "lable",
            to_name: "label",
            to_value: None,
            occurrences: 1,
            evidence: "The Burning Crusade.lua:6927 — transposed `le`/`el`",
        },
        DirectiveAlias {
            from: "noflyasble",
            to_name: "noflyable",
            to_value: None,
            occurrences: 1,
            evidence: "The Burning Crusade.lua:37505 — stray `s`",
        },
        DirectiveAlias {
            from: "requries",
            to_name: "requires",
            to_value: None,
            occurrences: 1,
            evidence: "The Burning Crusade.lua:114832 — transposed `ri`/`ir`",
        },
    ],
};

/// The 43 canonical `#directive` tokens, measured over the vendored guide pack and tabulated in
/// ADR 07 §4.2. With the six [`DIRECTIVE_ALIASES`] entries this accounts for all 49 tokens the ADR
/// counts.
///
/// The list spans **both** lexical regions: `#name`/`#group`/`#version` only ever appear in a
/// guide header, `#completewith`/`#sticky`/`#label` only inside a step. One vocabulary covers both
/// because the damage is the same in either place — a mistyped header key becomes an unread
/// [`Header`](crate::Header) and the guide loses its identity just as quietly as a mistyped step
/// directive loses its link.
///
/// Six of these are here **because they were rejected** as typos of their neighbours and are
/// deliberate, distinct vocabulary: `flyable` (the positive half of the `noflyable` pair),
/// `chapters` (the parent navigator list) against `chapter` (the leaf marker), `level` against
/// `label`, `tip` against `tbc`, and `hardcoreserver`/`softcoreserver` as prefix-extensions of
/// `hardcore`/`softcore`.
pub const KNOWN_DIRECTIVES: &[&str] = &[
    "OnClick",
    "ah",
    "aldor",
    "chapter",
    "chapters",
    "classic",
    "completewith",
    "defaultfor",
    "displayname",
    "flyable",
    "group",
    "hardcore",
    "hardcoreserver",
    "hidewindow",
    "icon",
    "ignorecorpse",
    "include",
    "internal",
    "label",
    "level",
    "loop",
    "name",
    "next",
    "noflyable",
    "optional",
    "phase",
    "qremove",
    "questguide",
    "requires",
    "scryer",
    "season",
    "softcore",
    "softcoreserver",
    "ssf",
    "sticky",
    "subgroup",
    "subweight",
    "tbc",
    "tip",
    "title",
    "version",
    "wotlk",
    "xprate",
];

/// Something ingest tolerated **loudly**.
///
/// The counterpart of the hard errors on [`ImportError`]: those abort, these are carried on
/// [`ParsedGuide::diagnostics`](crate::ParsedGuide::diagnostics). One is emitted per *occurrence*,
/// never per table entry — `#compltewith` appears twice in the corpus and two different lines have
/// to be findable.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DirectiveDiagnostic {
    /// A known typo was canonicalized. `from`/`to` are written **without** the leading `#` so they
    /// correlate directly with [`Directive::original`](crate::Directive::original) and
    /// [`Directive::name`](crate::Directive::name); [`Display`](std::fmt::Display) adds the `#`
    /// back so the rendered message is greppable against the guide source.
    Normalised {
        /// Source line of the occurrence.
        line: SourceLineNo,
        /// The token as authored.
        from: String,
        /// The canonical form, including the value the alias supplied when it supplied one
        /// (`"completewith TBTurnins"`).
        to: String,
    },
}

impl std::fmt::Display for DirectiveDiagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DirectiveDiagnostic::Normalised { line, from, to } => write!(
                f,
                "line {line}: `#{from}` normalised to `#{to}` by directive alias table v{}",
                DIRECTIVE_ALIASES.version
            ),
        }
    }
}

/// A directive after the closed vocabulary has been applied to it.
pub(crate) struct ResolvedDirective {
    /// The canonical name.
    pub name: String,
    /// The value, possibly supplied by a missing-space alias.
    pub value: Option<String>,
    /// The authored token, when it differed from `name`.
    pub original: Option<String>,
    /// The report, when anything was changed.
    pub diagnostic: Option<DirectiveDiagnostic>,
}

/// Apply the closed vocabulary to one authored `#token` and its value.
///
/// Matching is case-insensitive in both directions, which is what the pack needs (`#OnClick` is the
/// only mixed-case token) and is the tolerance the alias table already had. A *known* token is
/// passed through **verbatim**, casing included: nothing downstream reads casing, and rewriting it
/// would be an unreported change.
pub(crate) fn resolve_directive(
    raw_name: &str,
    value: Option<String>,
    line: SourceLineNo,
) -> Result<ResolvedDirective, ImportError> {
    if let Some(alias) = DIRECTIVE_ALIASES
        .entries
        .iter()
        .find(|a| a.from.eq_ignore_ascii_case(raw_name))
    {
        let (value, canonical_text) = match alias.to_value {
            // The missing-space case. The alias supplies the whole `(name, value)` pair, so a line
            // that already carries a value would need the two merged — and there is no rule that
            // says which wins. Refused, like every other thing this stage will not guess at.
            // Trailing whitespace is not a value: the lexer's whitespace split yields `Some("")`
            // for `#token   `, and treating that as a collision would refuse a blank line ending.
            Some(implied) => match value.filter(|v| !v.is_empty()) {
                Some(found) => {
                    return Err(ImportError::AliasValueConflict {
                        name: raw_name.to_string(),
                        line,
                        implied: implied.to_string(),
                        found,
                    })
                }
                None => (
                    Some(implied.to_string()),
                    format!("{} {}", alias.to_name, implied),
                ),
            },
            None => (value, alias.to_name.to_string()),
        };
        return Ok(ResolvedDirective {
            name: alias.to_name.to_string(),
            value,
            original: Some(raw_name.to_string()),
            diagnostic: Some(DirectiveDiagnostic::Normalised {
                line,
                from: raw_name.to_string(),
                to: canonical_text,
            }),
        });
    }

    if KNOWN_DIRECTIVES.iter().any(|k| k.eq_ignore_ascii_case(raw_name)) {
        return Ok(ResolvedDirective {
            name: raw_name.to_string(),
            value,
            original: None,
            diagnostic: None,
        });
    }

    Err(ImportError::UnknownDirective {
        name: raw_name.to_string(),
        line,
    })
}
