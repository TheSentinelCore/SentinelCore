//! Lexical rules of RestedXP guide source that more than one lowering has to obey.
//!
//! A guide line carries two kinds of prose alongside its arguments, and neither is data:
//!
//! * `>> …` — the display text shown to the player.
//! * `-- …` — a dev comment (`.complete 983,1 --Crawler Leg (6)`).
//!
//! Both markers are stripped before a line's arguments are parsed. `sentinel-importer`'s lexer is
//! the only ingest that reads a guide *line*, and this module holds the `--` rule so a second
//! implementation cannot appear beside it — the same reason [`crate::zone`] holds the one measured
//! zone table and [`crate::movement`] the one coordinate transform. (The compiler had exactly such
//! a second copy, in a `parse_movement` no compile ever called.)

/// Strip a trailing `--` dev comment from a command's args portion. The `--` marker never appears
/// in a valid numeric/id arg, so truncating at its first occurrence is unambiguous.
///
/// Applied by the importer to every command's args and to `step` marker tails
/// (`lexer::lex_body_line`, `guide_splitter::parse_step_gate`). 38 corpus movement lines carry one,
/// and a lowering that skips this refuses all 38 as malformed numbers —
/// `.goto 1439,42.017,58.866,0 --NE spawn` reads its arrival radius as `0 --NE spawn`.
pub fn strip_inline_dev_comment(s: &str) -> &str {
    match s.find("--") {
        Some(idx) => s[..idx].trim_end(),
        None => s,
    }
}

#[cfg(test)]
mod tests {
    use super::strip_inline_dev_comment;

    /// The three authored spacings, verbatim from the corpus.
    #[test]
    fn strips_the_comment_and_the_whitespace_before_it() {
        // A-11-23.lua:663 — no space between the argument and the marker.
        assert_eq!(
            strip_inline_dev_comment(".goto 1439,42.017,58.866,0 --NE spawn"),
            ".goto 1439,42.017,58.866,0"
        );
        // A-11-23.lua:4248 — a space on both sides.
        assert_eq!(
            strip_inline_dev_comment(".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
            ".goto 1414/1,-2036.9180,-796.8898"
        );
        // A-1-11-Dwarf-Gnome.lua:631 — the marker abutting the argument itself.
        assert_eq!(
            strip_inline_dev_comment("16321,<1 --Grimoire of Blood Pact (Rank 1)"),
            "16321,<1"
        );
    }

    /// A line without a marker is returned untouched — including its trailing whitespace, because
    /// callers that care already trim and one that does not must not have its input silently
    /// rewritten.
    #[test]
    fn a_line_without_a_comment_is_unchanged() {
        assert_eq!(
            strip_inline_dev_comment(".goto 1439,36.051,44.757,0"),
            ".goto 1439,36.051,44.757,0"
        );
        assert_eq!(strip_inline_dev_comment("  spaced  "), "  spaced  ");
    }

    /// A negative coordinate is a single `-`; nothing in the corpus authors `--` inside a number, so
    /// truncating at the first occurrence cannot eat one.
    #[test]
    fn a_negative_coordinate_is_not_a_comment() {
        assert_eq!(
            strip_inline_dev_comment("1948/530,34.200,-5187.100,70,0"),
            "1948/530,34.200,-5187.100,70,0"
        );
    }
}
