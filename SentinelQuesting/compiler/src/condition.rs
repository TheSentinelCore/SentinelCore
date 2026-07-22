//! `02_DATA_MODEL.md` §23 condition DSL → typed `RuntimeCondition` parser (design Decision 2).
//! Unmappable expressions return `Err`, never a silent guess.
//!
//! Grammar: `expr := or_expr`; `or_expr := and_expr ('||' and_expr)*`; `and_expr := not_expr
//! ('&&' not_expr)*`; `not_expr := 'NOT' not_expr | primary`; `primary := predicate | '(' expr
//! ')'`; `predicate := IDENT '(' [NUMBER (',' NUMBER)*] ')'`. Only the §23 subset the importer
//! currently emits — §23 also documents `Level >= N` -> `LevelAtLeast`, deferred until a guide
//! form emits it, not implemented here. Precedence (tightest→loosest): `NOT` > `&&` > `||` —
//! §23 gives no explicit table; corroborated by `NOT X || NOT Y || NOT Z` only parsing sensibly
//! if `NOT` binds one predicate before `||` combines results.

use sentinel_models::runtime::RuntimeCondition;

/// A condition expression could not be parsed or mapped to a known `RuntimeCondition` predicate.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[error("{0}")]
pub struct ConditionParseError(pub String);

fn err<T>(msg: impl Into<String>) -> Result<T, ConditionParseError> {
    Err(ConditionParseError(msg.into()))
}

/// Recursion cap for paren-nesting / `NOT`-chaining — closes a network-reachable stack-overflow
/// DoS (editor `/compile` on an unbounded `Condition{expression}`). Corpus nests 0 deep; 64 is
/// ~6x headroom. `MAX_CONDITION_TOKENS` is cheap defense-in-depth insurance alongside it.
const MAX_CONDITION_DEPTH: usize = 64;
const MAX_CONDITION_TOKENS: usize = 4096;

#[derive(Debug, Clone, PartialEq)]
enum Token { LParen, RParen, Comma, And, Or, Not, Ident(String), Number(u64) }

fn tokenize(input: &str) -> Result<Vec<Token>, ConditionParseError> {
    let chars: Vec<char> = input.chars().collect();
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_whitespace() { i += 1; }
        else if c == '(' { tokens.push(Token::LParen); i += 1; }
        else if c == ')' { tokens.push(Token::RParen); i += 1; }
        else if c == ',' { tokens.push(Token::Comma); i += 1; }
        else if c == '&' && chars.get(i + 1) == Some(&'&') { tokens.push(Token::And); i += 2; }
        else if c == '|' && chars.get(i + 1) == Some(&'|') { tokens.push(Token::Or); i += 2; }
        else if c.is_ascii_digit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_digit() { i += 1; }
            let text: String = chars[start..i].iter().collect();
            let n = text.parse::<u64>().map_err(|_| ConditionParseError(format!("invalid number '{text}'")))?;
            tokens.push(Token::Number(n));
        } else if c.is_ascii_alphabetic() {
            let start = i;
            while i < chars.len() && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') { i += 1; }
            let text: String = chars[start..i].iter().collect();
            tokens.push(if text == "NOT" { Token::Not } else { Token::Ident(text) });
        } else {
            return err(format!("unexpected character '{c}' at offset {i}"));
        }
    }
    Ok(tokens)
}

struct Parser<'a> { tokens: &'a [Token], pos: usize, depth: usize }

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<&Token> { self.tokens.get(self.pos) }
    fn advance(&mut self) -> Option<&Token> {
        let tok = self.tokens.get(self.pos);
        if tok.is_some() { self.pos += 1; }
        tok
    }
    /// Bumps recursion depth; errors out before the caller recurses further (never a panic).
    fn enter(&mut self) -> Result<(), ConditionParseError> {
        self.depth += 1;
        if self.depth > MAX_CONDITION_DEPTH {
            return err(format!("condition expression exceeds max nesting depth ({MAX_CONDITION_DEPTH})"));
        }
        Ok(())
    }
    fn parse_expr(&mut self) -> Result<RuntimeCondition, ConditionParseError> { self.parse_or() }

    fn parse_or(&mut self) -> Result<RuntimeCondition, ConditionParseError> {
        let mut terms = vec![self.parse_and()?];
        while matches!(self.peek(), Some(Token::Or)) { self.advance(); terms.push(self.parse_and()?); }
        Ok(if terms.len() == 1 { terms.pop().unwrap() } else { RuntimeCondition::Any(terms) })
    }

    fn parse_and(&mut self) -> Result<RuntimeCondition, ConditionParseError> {
        let mut terms = vec![self.parse_not()?];
        while matches!(self.peek(), Some(Token::And)) { self.advance(); terms.push(self.parse_not()?); }
        Ok(if terms.len() == 1 { terms.pop().unwrap() } else { RuntimeCondition::All(terms) })
    }

    fn parse_not(&mut self) -> Result<RuntimeCondition, ConditionParseError> {
        if matches!(self.peek(), Some(Token::Not)) {
            self.advance();
            self.enter()?;
            let inner = self.parse_not()?;
            self.depth -= 1;
            return Ok(RuntimeCondition::Not(Box::new(inner)));
        }
        self.parse_primary()
    }

    fn parse_primary(&mut self) -> Result<RuntimeCondition, ConditionParseError> {
        match self.advance() {
            Some(Token::LParen) => {
                self.enter()?;
                let inner = self.parse_expr()?;
                self.depth -= 1;
                match self.advance() {
                    Some(Token::RParen) => Ok(inner),
                    other => err(format!("expected closing ')', found {other:?}")),
                }
            }
            Some(Token::Ident(name)) => { let name = name.clone(); self.parse_predicate(&name) }
            other => err(format!("expected an expression, found {other:?}")),
        }
    }

    fn parse_predicate(&mut self, name: &str) -> Result<RuntimeCondition, ConditionParseError> {
        if !matches!(self.advance(), Some(Token::LParen)) {
            return err(format!("expected '(' after predicate '{name}'"));
        }
        let mut args = Vec::new();
        if !matches!(self.peek(), Some(Token::RParen)) {
            loop {
                match self.advance() {
                    Some(Token::Number(n)) => args.push(*n),
                    other => return err(format!(
                        "expected a numeric argument in '{name}(...)', found {other:?}"
                    )),
                }
                if matches!(self.peek(), Some(Token::Comma)) { self.advance(); } else { break; }
            }
        }
        if !matches!(self.advance(), Some(Token::RParen)) {
            return err(format!("expected ')' to close '{name}(...)'"));
        }
        build_predicate(name, &args)
    }
}

fn as_u32(n: u64, what: &str) -> Result<u32, ConditionParseError> {
    u32::try_from(n).map_err(|_| ConditionParseError(format!("{what} value {n} exceeds u32 range")))
}

fn as_u8(n: u64, what: &str) -> Result<u8, ConditionParseError> {
    u8::try_from(n).map_err(|_| ConditionParseError(format!("{what} value {n} exceeds u8 range")))
}

/// Maps a predicate + args to `RuntimeCondition` per `design.md`'s command → DSL → variant table.
/// Only predicates the real importer emits are supported; anything else is a diagnostic, not a guess.
fn build_predicate(name: &str, args: &[u64]) -> Result<RuntimeCondition, ConditionParseError> {
    match (name, args) {
        ("QuestAccepted", [id]) => Ok(RuntimeCondition::QuestAccepted(as_u32(*id, "quest id")?)),
        ("QuestCompleted", [id]) => Ok(RuntimeCondition::QuestCompleted(as_u32(*id, "quest id")?)),
        ("QuestRewarded", [id]) => Ok(RuntimeCondition::QuestRewarded(as_u32(*id, "quest id")?)),
        ("Objective", [q, idx]) => Ok(RuntimeCondition::ObjectiveComplete(
            as_u32(*q, "quest id")?,
            as_u8(*idx, "objective index")?,
        )),
        ("ItemCount", [item, n]) => {
            Ok(RuntimeCondition::ItemCountAtLeast(as_u32(*item, "item id")?, as_u32(*n, "count")?))
        }
        (other, _) => err(format!("unknown predicate '{other}' with {} argument(s)", args.len())),
    }
}

/// Parses a §23 condition expression into a typed `RuntimeCondition`. Never panics: malformed
/// input (unbalanced parens, unknown predicate, trailing garbage, empty) yields `Err`.
pub fn parse_condition(input: &str) -> Result<RuntimeCondition, ConditionParseError> {
    let trimmed = input.trim();
    if trimmed.is_empty() { return err("condition expression is empty"); }
    let tokens = tokenize(trimmed)?;
    if tokens.len() > MAX_CONDITION_TOKENS {
        return err(format!("condition expression exceeds max token count ({MAX_CONDITION_TOKENS})"));
    }
    let mut parser = Parser { tokens: &tokens, pos: 0, depth: 0 };
    let result = parser.parse_expr()?;
    if parser.pos != tokens.len() {
        return err(format!("unexpected trailing input after token {}", parser.pos));
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verbatim DSL strings emitted by `project_builder.rs` — frozen as expectations in
    /// `importer/tests/mapper.rs`. Every one of these MUST parse.
    #[test]
    fn parses_full_emission_corpus() {
        // Leading/trailing/inner whitespace tolerance, verified inline (requirement: whitespace-tolerant).
        assert_eq!(parse_condition("  Objective( 1234 , 1 )  ").unwrap(), RuntimeCondition::ObjectiveComplete(1234, 1));
        assert_eq!(parse_condition("ItemCount(159,10)").unwrap(), RuntimeCondition::ItemCountAtLeast(159, 10));
        assert_eq!(parse_condition("ItemCount(2139,1)").unwrap(), RuntimeCondition::ItemCountAtLeast(2139, 1));
        assert_eq!(parse_condition("QuestAccepted(5624)").unwrap(), RuntimeCondition::QuestAccepted(5624));
        assert_eq!(parse_condition("QuestCompleted(1234)").unwrap(), RuntimeCondition::QuestCompleted(1234));
        assert_eq!(parse_condition("QuestRewarded(5624)").unwrap(), RuntimeCondition::QuestRewarded(5624));
        assert_eq!(parse_condition("NOT QuestRewarded(42)").unwrap(), RuntimeCondition::Not(Box::new(RuntimeCondition::QuestRewarded(42))));
        assert_eq!(parse_condition("NOT ItemCount(2449,5)").unwrap(), RuntimeCondition::Not(Box::new(RuntimeCondition::ItemCountAtLeast(2449, 5))));
        assert_eq!(parse_condition("ItemCount(19003,1)").unwrap(), RuntimeCondition::ItemCountAtLeast(19003, 1));
        assert_eq!(parse_condition("ItemCount(100,3)").unwrap(), RuntimeCondition::ItemCountAtLeast(100, 3));
        assert_eq!(parse_condition("ItemCount(21377,6)").unwrap(), RuntimeCondition::ItemCountAtLeast(21377, 6));
        assert_eq!(parse_condition("Objective(1598,1)").unwrap(), RuntimeCondition::ObjectiveComplete(1598, 1));
        assert_eq!(parse_condition("QuestRewarded(418)").unwrap(), RuntimeCondition::QuestRewarded(418));
        assert_eq!(parse_condition("NOT ItemCount(100,5)").unwrap(), RuntimeCondition::Not(Box::new(RuntimeCondition::ItemCountAtLeast(100, 5))));
    }

    #[test]
    fn parses_or_chains_from_corpus() {
        assert_eq!(
            parse_condition(
                "QuestAccepted(9699) || QuestAccepted(9584) || QuestAccepted(9643) || QuestAccepted(9580) || QuestAccepted(10063)"
            ).unwrap(),
            RuntimeCondition::Any(vec![
                RuntimeCondition::QuestAccepted(9699),
                RuntimeCondition::QuestAccepted(9584),
                RuntimeCondition::QuestAccepted(9643),
                RuntimeCondition::QuestAccepted(9580),
                RuntimeCondition::QuestAccepted(10063),
            ])
        );
        assert_eq!(
            parse_condition(
                "QuestRewarded(3789) || QuestRewarded(3790) || QuestRewarded(10520) || QuestRewarded(3763)"
            ).unwrap(),
            RuntimeCondition::Any(vec![
                RuntimeCondition::QuestRewarded(3789),
                RuntimeCondition::QuestRewarded(3790),
                RuntimeCondition::QuestRewarded(10520),
                RuntimeCondition::QuestRewarded(3763),
            ])
        );
        assert_eq!(
            parse_condition(
                "NOT QuestRewarded(9717) || NOT QuestRewarded(9719) || NOT QuestRewarded(9738)"
            ).unwrap(),
            RuntimeCondition::Any(vec![
                RuntimeCondition::Not(Box::new(RuntimeCondition::QuestRewarded(9717))),
                RuntimeCondition::Not(Box::new(RuntimeCondition::QuestRewarded(9719))),
                RuntimeCondition::Not(Box::new(RuntimeCondition::QuestRewarded(9738))),
            ])
        );
    }

    #[test]
    fn precedence_and_grouping() {
        // NOT > && > || : `A || B && C` == `A || (B && C)`; `NOT A && B` == `(NOT A) && B`.
        assert_eq!(
            parse_condition("QuestAccepted(1) || QuestCompleted(2) && QuestRewarded(3)").unwrap(),
            RuntimeCondition::Any(vec![
                RuntimeCondition::QuestAccepted(1),
                RuntimeCondition::All(vec![RuntimeCondition::QuestCompleted(2), RuntimeCondition::QuestRewarded(3)]),
            ])
        );
        assert_eq!(
            parse_condition("NOT QuestAccepted(1) && QuestCompleted(2)").unwrap(),
            RuntimeCondition::All(vec![
                RuntimeCondition::Not(Box::new(RuntimeCondition::QuestAccepted(1))),
                RuntimeCondition::QuestCompleted(2),
            ])
        );
        // Parens override default precedence.
        assert_eq!(
            parse_condition("(QuestAccepted(1) || QuestCompleted(2)) && QuestRewarded(3)").unwrap(),
            RuntimeCondition::All(vec![
                RuntimeCondition::Any(vec![RuntimeCondition::QuestAccepted(1), RuntimeCondition::QuestCompleted(2)]),
                RuntimeCondition::QuestRewarded(3),
            ])
        );
    }

    #[test]
    fn rejects_malformed_input_without_panicking() {
        assert!(parse_condition("").is_err(), "empty expression must error");
        assert!(parse_condition("QuestAccepted(1").is_err(), "unbalanced parens must error");
        assert!(parse_condition("FooBar(1)").is_err(), "unknown predicate must error");
        assert!(parse_condition("QuestAccepted(1) extra").is_err(), "trailing garbage must error");
    }

    #[test]
    fn recursion_depth_is_bounded() {
        // Pre-fix these abort the process with a real stack overflow (the RED signal); post-fix
        // Err, never a panic/abort. 200 is below MAX_CONDITION_TOKENS but above
        // MAX_CONDITION_DEPTH, exercising the depth guard specifically.
        assert!(parse_condition(&"(".repeat(100_000)).is_err());
        assert!(parse_condition(&"(".repeat(200)).is_err());
        assert!(parse_condition(&format!("{}QuestAccepted(1)", "NOT ".repeat(100_000))).is_err());
        // Well under the limit (10 << 64): must still parse fine.
        let parens = format!("{}QuestAccepted(1){}", "(".repeat(10), ")".repeat(10));
        assert_eq!(parse_condition(&parens).unwrap(), RuntimeCondition::QuestAccepted(1));
    }

    #[test]
    fn never_panics_on_garbage_input() {
        let garbage = [
            "", "(", ")", "&&", "||", "NOT", "QuestAccepted(abc)", "日本語",
            "QuestAccepted(99999999999999999999)", ",,,", "&& QuestAccepted(1)",
        ];
        for input in garbage {
            let result = std::panic::catch_unwind(|| parse_condition(input));
            assert!(result.is_ok(), "parse_condition must never panic, input: {input:?}");
        }
    }
}
