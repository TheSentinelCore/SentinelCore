//! [`Lexer`]: classify each [`LocatedLine`](crate::LocatedLine) into a [`Token`].
//!
//! Header-region lines become [`Token::GuideHeader`]; step-region lines become
//! [`Token::StepStart`], [`Token::StepDirective`], [`Token::Command`], or [`Token::Text`].
//!
//! Every `#token`, in **either** region, is resolved against the closed vocabulary in
//! [`crate::directives`]: known tokens pass through, the six measured typos normalise with a
//! [`DirectiveDiagnostic`] apiece, and anything else aborts the lex (ADR 07 §5.10). That is why
//! [`Lexer::tokenize`] returns a [`Result`] and a [`LexedGuide`] rather than a bare `Vec<Token>` —
//! an infallible entry point next to a fallible one is a back door around the posture.

use crate::{
    directives::{resolve_directive, DirectiveDiagnostic},
    guide_splitter::{is_step_marker, parse_step_conditions, parse_step_gate},
    ImportError, LocatedLine, SourceLineNo, SplitGuide,
};
use serde::{Deserialize, Serialize};

/// A single classified lexical token.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Token {
    GuideHeader {
        key: String,
        value: String,
        line: SourceLineNo,
    },
    StepStart {
        conditions: Vec<String>,
        /// The raw, unsplit `<<` tail of the marker (IF3). `conditions` is the lossy `/`-only
        /// split kept for wire compatibility; this is the full gate expression.
        ///
        /// Absent-when-`None` on the wire, matching its carrier [`Step::gate`](crate::Step::gate):
        /// an optional field that serializes as an explicit `null` in one type and is omitted in
        /// its sibling is exactly the silent Rust↔consumer drift `CLAUDE.md` warns about.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        gate: Option<String>,
        line: SourceLineNo,
    },
    StepDirective {
        name: String,
        value: Option<String>,
        line: SourceLineNo,
        /// The raw directive name as written, when it was a tolerated typo canonicalized to
        /// `name` (IF5). `None` when the directive was already spelled canonically. Omitted from
        /// the wire when absent, like [`Directive::original`](crate::Directive::original).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        original: Option<String>,
    },
    Command {
        name: String,
        args: Vec<String>,
        note: Option<String>,
        line: SourceLineNo,
        /// Trailing `<< ClassName` / `<< Class1/Class2` / `<< !Class` suffix, when present
        /// (IF3). Extracted from whichever of `note`/args-tail carries the line's tail text.
        /// Omitted from the wire when absent, like
        /// [`Command::class_restriction`](crate::Command::class_restriction).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        class_restriction: Option<String>,
    },
    Text {
        content: String,
        line: SourceLineNo,
    },
}

/// Strip a trailing `--` dev comment from a command's args portion.
///
/// Re-exported from [`sentinel_models::source`], not defined here: the compiler's ADR-07 movement
/// lowering (`kernel::parse_movement`) obeys the same rule over the same corpus lines, and two
/// implementations of one lexical rule can disagree. Also applied to `step` marker tails by
/// [`parse_step_gate`](crate::guide_splitter::parse_step_gate).
pub(crate) use sentinel_models::source::strip_inline_dev_comment;

/// Extract a trailing `<< ClassName` / `<< Class1/Class2` / `<< !Class` suffix (IF3) from the
/// tail portion of a command line (either its note, or its args when there is no note). Returns
/// the cleaned text and the raw suffix (unparsed — the compiler's class filter, PR2b, interprets
/// the `/`-list and `!`-negation grammar).
fn extract_class_suffix(s: &str) -> (String, Option<String>) {
    match s.rfind("<<") {
        Some(idx) => {
            let (head, tail) = s.split_at(idx);
            // CRITICAL fix: corpus-dominant ordering is `<< Class --comment` (dev comment trails
            // the class, not the args) — strip it from the class tail so class_restriction never
            // absorbs it. This does not touch the note (already split off before this runs).
            let tail = strip_inline_dev_comment(tail[2..].trim());
            (head.trim().to_string(), Some(tail.to_string()))
        }
        None => (s.to_string(), None),
    }
}

/// The token stream of one guide, plus everything ingest tolerated **loudly** while producing it.
///
/// The two travel together because a normalisation that is not carried alongside the token it
/// changed is a silent repair: `#compltewith` and `#completewith` are indistinguishable once
/// lexing is over, and only the diagnostic still knows which line was authored wrong.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct LexedGuide {
    /// The classified tokens, in source order.
    pub tokens: Vec<Token>,
    /// One entry per normalised occurrence, in source order.
    pub diagnostics: Vec<DirectiveDiagnostic>,
}

pub struct Lexer;

impl Lexer {
    /// Classify `split`, applying the closed directive vocabulary (ADR 07 §5.10).
    ///
    /// Fails on the first `#token` that is neither canonical nor a listed alias. There is no
    /// infallible sibling of this function by design — one would be a way to lex a guide without
    /// the posture, and the posture is the only thing standing between an unknown token and a
    /// silently dropped step.
    pub fn tokenize(split: &SplitGuide) -> Result<LexedGuide, ImportError> {
        let mut lexed = LexedGuide::default();
        for hl in &split.headers {
            if let Some(tok) = Self::lex_header(hl, &mut lexed.diagnostics)? {
                lexed.tokens.push(tok);
            }
        }
        for bl in &split.body_lines {
            if let Some(tok) = Self::lex_body_line(bl, &mut lexed.diagnostics)? {
                lexed.tokens.push(tok);
            }
        }
        Ok(lexed)
    }

    fn lex_header(
        line: &LocatedLine,
        diagnostics: &mut Vec<DirectiveDiagnostic>,
    ) -> Result<Option<Token>, ImportError> {
        let t = line.text.trim();
        if t.is_empty() {
            return Ok(None);
        }
        if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start();
            let (raw_key, value) = match rest.split_once(char::is_whitespace) {
                Some((k, v)) => (k.to_string(), Some(v.trim().to_string())),
                None => (rest.to_string(), None),
            };
            // Same closed vocabulary as the step region. `Token::GuideHeader` has no `original`
            // field and gains none here — no header-region typo exists in the pack, so adding a
            // carrier for it would be an unmeasured wire change; the diagnostic holds the authored
            // spelling either way.
            let resolved = resolve_directive(&raw_key, value, line.line_no)?;
            if let Some(diag) = resolved.diagnostic {
                diagnostics.push(diag);
            }
            return Ok(Some(Token::GuideHeader {
                key: resolved.name,
                value: resolved.value.unwrap_or_default(),
                line: line.line_no,
            }));
        }
        if let Some(rest) = t.strip_prefix("<<") {
            return Ok(Some(Token::GuideHeader {
                key: "faction".to_string(),
                value: rest.trim().to_string(),
                line: line.line_no,
            }));
        }
        // Any other header-region line (rare) is captured verbatim.
        Ok(Some(Token::GuideHeader {
            key: "raw".to_string(),
            value: t.to_string(),
            line: line.line_no,
        }))
    }

    fn lex_body_line(
        line: &LocatedLine,
        diagnostics: &mut Vec<DirectiveDiagnostic>,
    ) -> Result<Option<Token>, ImportError> {
        let t = line.text.trim();
        if t.is_empty() {
            return Ok(None);
        }
        if is_step_marker(t) {
            return Ok(Some(Token::StepStart {
                conditions: parse_step_conditions(t),
                gate: parse_step_gate(t),
                line: line.line_no,
            }));
        }
        if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start();
            let (raw_name, value) = match rest.split_once(char::is_whitespace) {
                Some((k, v)) => (k.to_string(), Some(v.trim().to_string())),
                None => (rest.to_string(), None),
            };
            let resolved = resolve_directive(&raw_name, value, line.line_no)?;
            if let Some(diag) = resolved.diagnostic {
                diagnostics.push(diag);
            }
            return Ok(Some(Token::StepDirective {
                name: resolved.name,
                value: resolved.value,
                line: line.line_no,
                original: resolved.original,
            }));
        }
        if let Some(rest) = t.strip_prefix('.') {
            return Ok(Some(Self::lex_command(rest, line.line_no)));
        }
        // Everything else is instructional text (including ">>" continuations and "+" chat lines).
        Ok(Some(Token::Text {
            content: t.to_string(),
            line: line.line_no,
        }))
    }

    fn lex_command(rest: &str, line: SourceLineNo) -> Token {
        // Split the human-readable note off on ">>".
        let (left, note) = match rest.split_once(">>") {
            Some((l, n)) => (l.trim().to_string(), Some(n.trim().to_string())),
            None => (rest.trim().to_string(), None),
        };
        // IF3: a trailing `<< Class` suffix lives on whichever segment is the line's tail — the
        // note when one exists (`.turnin 33,2 >> note << Warrior`), otherwise the args portion
        // itself (`.collect 7972,1 << Priest`).
        let (left, class_from_left) = extract_class_suffix(&left);
        let (note, class_restriction) = match note {
            Some(n) => {
                let (n, class_from_note) = extract_class_suffix(&n);
                (Some(n), class_from_note.or(class_from_left))
            }
            None => (None, class_from_left),
        };
        // Strip a trailing `--` dev comment before further parsing (REL-1 root cause: RestedXP
        // guides routinely append these after the last numeric arg, e.g.
        // `.complete 1598,1 --Collect Powers of the Void (x1)`). Doing this once, here, replaces
        // the per-callsite defensive stripping previously duplicated in project_builder.rs.
        let left = strip_inline_dev_comment(&left);
        // Command name is the first whitespace-delimited token.
        let mut parts = left.splitn(2, char::is_whitespace);
        let name = parts.next().unwrap_or("").to_string();
        let args_part = parts.next().unwrap_or("").trim();
        // Remainder is comma-separated (handles `.goto Zone,x,y` and `.collect id,count`).
        let args: Vec<String> = if args_part.is_empty() {
            Vec::new()
        } else {
            args_part
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        };
        Token::Command { name, args, note, line, class_restriction }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_inline_dev_comment_before_splitting_args() {
        // REL-1 root cause (deferred from PR1a): the `--` dev comment must be stripped at lex
        // time so downstream args are already clean numeric strings.
        match Lexer::lex_command("itemcount 2449,<5 --Earthroot (<5)", 1) {
            Token::Command { name, args, .. } => {
                assert_eq!(name, "itemcount");
                assert_eq!(args, vec!["2449".to_string(), "<5".to_string()]);
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn strips_inline_dev_comment_on_goto_coords() {
        match Lexer::lex_command("goto Darnassus,55.239,23.996 -- Argent Guard Manados", 1) {
            Token::Command { args, .. } => {
                assert_eq!(
                    args,
                    vec!["Darnassus".to_string(), "55.239".to_string(), "23.996".to_string()]
                );
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn dev_comment_stripping_does_not_eat_a_human_readable_note() {
        match Lexer::lex_command("accept 1598 >> Accept The Stolen Tome", 1) {
            Token::Command { args, note, .. } => {
                assert_eq!(args, vec!["1598".to_string()]);
                assert_eq!(note.as_deref(), Some("Accept The Stolen Tome"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn class_suffix_without_note_is_extracted_from_args() {
        // IF3, corpus-proven (2688 occurrences in The Burning Crusade.lua).
        match Lexer::lex_command("collect 7972,1 << Priest", 1) {
            Token::Command { args, note, class_restriction, .. } => {
                assert_eq!(args, vec!["7972".to_string(), "1".to_string()]);
                assert!(note.is_none());
                assert_eq!(class_restriction.as_deref(), Some("Priest"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn class_suffix_after_note_is_extracted_and_note_is_cleaned() {
        let cmd = "turnin 33,2 >> Turn in Wolves Across The Border << Warrior/Paladin/Rogue";
        match Lexer::lex_command(cmd, 1) {
            Token::Command { note, class_restriction, .. } => {
                assert_eq!(note.as_deref(), Some("Turn in Wolves Across The Border"));
                assert_eq!(class_restriction.as_deref(), Some("Warrior/Paladin/Rogue"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn negated_class_suffix_after_note_is_extracted() {
        match Lexer::lex_command("fly Ironforge >> Fly to Ironforge << !Shaman", 1) {
            Token::Command { class_restriction, .. } => {
                assert_eq!(class_restriction.as_deref(), Some("!Shaman"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn class_suffix_trailing_dev_comment_is_stripped_without_note() {
        // CRITICAL fix, corpus-dominant ordering (A-1-11-Human.lua:665; 99 lines/5 sampled
        // guides): `<< Class --comment` must not leak the dev comment into class_restriction.
        match Lexer::lex_command("collect 2589,1 << Paladin --Linen Cloth (1+)", 1) {
            Token::Command { args, class_restriction, .. } => {
                assert_eq!(args, vec!["2589".to_string(), "1".to_string()]);
                assert_eq!(class_restriction.as_deref(), Some("Paladin"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn negated_and_multi_class_suffix_trailing_dev_comments_are_stripped() {
        match Lexer::lex_command("fly Ironforge << !Shaman --comment text", 1) {
            Token::Command { class_restriction, .. } => {
                assert_eq!(class_restriction.as_deref(), Some("!Shaman"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
        match Lexer::lex_command("collect 1,1 << Warrior/Paladin --comment text", 1) {
            Token::Command { class_restriction, .. } => {
                assert_eq!(class_restriction.as_deref(), Some("Warrior/Paladin"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn class_suffix_after_note_strips_trailing_dev_comment_but_keeps_note_intact() {
        // `--` inside the `>>` note must remain untouched — only the class tail is cleaned.
        let cmd = "turnin 33,2 >> Turn in Wolves Across The Border << Warrior --dev note";
        match Lexer::lex_command(cmd, 1) {
            Token::Command { note, class_restriction, .. } => {
                assert_eq!(note.as_deref(), Some("Turn in Wolves Across The Border"));
                assert_eq!(class_restriction.as_deref(), Some("Warrior"));
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn command_without_class_suffix_leaves_class_restriction_none() {
        match Lexer::lex_command("accept 1598 >> Accept The Stolen Tome", 1) {
            Token::Command { class_restriction, .. } => {
                assert!(class_restriction.is_none());
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }

    #[test]
    fn early_mid_line_dev_comment_truncates_subsequent_args() {
        // Review follow-up (PR1b): `--` truncates at its FIRST occurrence, so a mid-line "--"
        // (zero corpus matches today) drops the trailing coords too, not just a dev comment.
        // Pinned explicitly so a future corpus hit is a conscious decision, not a surprise.
        match Lexer::lex_command("goto Zone--Name,1.0,2.0 -- note", 1) {
            Token::Command { name, args, .. } => {
                assert_eq!(name, "goto");
                assert_eq!(args, vec!["Zone".to_string()]);
            }
            other => panic!("expected Command token, got {other:?}"),
        }
    }
}
