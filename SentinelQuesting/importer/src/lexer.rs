//! [`Lexer`]: classify each [`LocatedLine`](crate::LocatedLine) into a [`Token`].
//!
//! Header-region lines become [`Token::GuideHeader`]; step-region lines become
//! [`Token::StepStart`], [`Token::StepDirective`], [`Token::Command`], or [`Token::Text`].

use crate::{
    guide_splitter::{is_step_marker, parse_step_conditions},
    LocatedLine, SourceLineNo, SplitGuide,
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
        line: SourceLineNo,
    },
    StepDirective {
        name: String,
        value: Option<String>,
        line: SourceLineNo,
        /// The raw directive name as written, when it was a tolerated typo canonicalized to
        /// `name` (IF5). `None` when the directive was already spelled canonically.
        original: Option<String>,
    },
    Command {
        name: String,
        args: Vec<String>,
        note: Option<String>,
        line: SourceLineNo,
    },
    Text {
        content: String,
        line: SourceLineNo,
    },
}

/// Strip a trailing `--` dev comment from a command's args portion. The `--` marker never
/// appears in a valid numeric/id arg, so truncating at its first occurrence is unambiguous.
fn strip_inline_dev_comment(s: &str) -> &str {
    match s.find("--") {
        Some(idx) => s[..idx].trim_end(),
        None => s,
    }
}

/// Known single-edit-distance directive typo variants observed in the RestedXP corpus
/// (`The Burning Crusade.lua`), canonicalized here rather than dropped (IF5).
const DIRECTIVE_TYPOS: &[(&str, &str)] = &[
    ("compltewith", "completewith"),
    ("requries", "requires"),
    ("lable", "label"),
];

/// Canonicalize a directive name, returning `(canonical, original_if_typo)`. `original` is
/// `None` when `name` was already canonical.
fn canonicalize_directive(name: &str) -> (String, Option<String>) {
    for (typo, canonical) in DIRECTIVE_TYPOS {
        if name.eq_ignore_ascii_case(typo) {
            return (canonical.to_string(), Some(name.to_string()));
        }
    }
    (name.to_string(), None)
}

pub struct Lexer;

impl Lexer {
    pub fn tokenize(split: &SplitGuide) -> Vec<Token> {
        let mut tokens = Vec::new();
        for hl in &split.headers {
            if let Some(tok) = Self::lex_header(hl) {
                tokens.push(tok);
            }
        }
        for bl in &split.body_lines {
            if let Some(tok) = Self::lex_body_line(bl) {
                tokens.push(tok);
            }
        }
        tokens
    }

    fn lex_header(line: &LocatedLine) -> Option<Token> {
        let t = line.text.trim();
        if t.is_empty() {
            return None;
        }
        if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start();
            let (key, value) = match rest.split_once(char::is_whitespace) {
                Some((k, v)) => (k.to_string(), v.trim().to_string()),
                None => (rest.to_string(), String::new()),
            };
            return Some(Token::GuideHeader {
                key,
                value,
                line: line.line_no,
            });
        }
        if let Some(rest) = t.strip_prefix("<<") {
            return Some(Token::GuideHeader {
                key: "faction".to_string(),
                value: rest.trim().to_string(),
                line: line.line_no,
            });
        }
        // Any other header-region line (rare) is captured verbatim.
        Some(Token::GuideHeader {
            key: "raw".to_string(),
            value: t.to_string(),
            line: line.line_no,
        })
    }

    fn lex_body_line(line: &LocatedLine) -> Option<Token> {
        let t = line.text.trim();
        if t.is_empty() {
            return None;
        }
        if is_step_marker(t) {
            return Some(Token::StepStart {
                conditions: parse_step_conditions(t),
                line: line.line_no,
            });
        }
        if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start();
            let (raw_name, value) = match rest.split_once(char::is_whitespace) {
                Some((k, v)) => (k.to_string(), Some(v.trim().to_string())),
                None => (rest.to_string(), None),
            };
            let (name, original) = canonicalize_directive(&raw_name);
            return Some(Token::StepDirective {
                name,
                value,
                line: line.line_no,
                original,
            });
        }
        if let Some(rest) = t.strip_prefix('.') {
            return Some(Self::lex_command(rest, line.line_no));
        }
        // Everything else is instructional text (including ">>" continuations and "+" chat lines).
        Some(Token::Text {
            content: t.to_string(),
            line: line.line_no,
        })
    }

    fn lex_command(rest: &str, line: SourceLineNo) -> Token {
        // Split the human-readable note off on ">>".
        let (left, note) = match rest.split_once(">>") {
            Some((l, n)) => (l.trim(), Some(n.trim().to_string())),
            None => (rest.trim(), None),
        };
        // Strip a trailing `--` dev comment before further parsing (REL-1 root cause: RestedXP
        // guides routinely append these after the last numeric arg, e.g.
        // `.complete 1598,1 --Collect Powers of the Void (x1)`). Doing this once, here, replaces
        // the per-callsite defensive stripping previously duplicated in project_builder.rs.
        let left = strip_inline_dev_comment(left);
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
        Token::Command { name, args, note, line }
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
}
