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
            let (name, value) = match rest.split_once(char::is_whitespace) {
                Some((k, v)) => (k.to_string(), Some(v.trim().to_string())),
                None => (rest.to_string(), None),
            };
            return Some(Token::StepDirective {
                name,
                value,
                line: line.line_no,
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
