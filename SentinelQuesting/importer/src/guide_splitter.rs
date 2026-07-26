//! [`GuideSplitter`]: extract the guide body from `RXPGuides.RegisterGuide([[ ... ]])`
//! and split it into the header section (before the first `step`) and the step section.

use crate::{lexer::strip_inline_dev_comment, ImportError, LocatedLine, SourceLineNo};

/// Result of [`GuideSplitter::split`]: the guide headers and the (step-region) body lines,
/// each tagged with its original source line number.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SplitGuide {
    pub headers: Vec<LocatedLine>,
    pub body_lines: Vec<LocatedLine>,
}

/// Whether a line is a `step` marker (`step`, `step << X`, `step<<X`, with leading whitespace).
pub(crate) fn is_step_marker(line: &str) -> bool {
    let t = line.trim_start();
    t == "step" || t.starts_with("step ") || t.starts_with("step\t") || t.starts_with("step<")
}

/// The raw, unsplit `<<` tail of a `step` marker (`step << Dwarf Paladin` -> `"Dwarf Paladin"`).
///
/// [`parse_step_conditions`] splits on `/` only, which flattens `Dwarf Paladin`, `!tbc !wotlk`
/// and `Warrior skip` into single inert tokens and destroys the AND/OR/`!` grammar. This keeps
/// the tail verbatim so a later pass can still parse it.
///
/// The trailing `--` dev comment is stripped with the very same
/// [`strip_inline_dev_comment`](crate::lexer::strip_inline_dev_comment) already applied to every
/// command tail: the gate is the author's AUDIENCE, never their prose. Leaving it in conjoined
/// `-- checking if gnomes can get mount` onto `Gnome !Warlock` on 8 live corpus steps, making the
/// gate unsatisfiable for every archetype, and left the second `<<` of
/// `skip --logout skip << Warrior` inside the tail as if `Warrior` were an audience.
pub(crate) fn parse_step_gate(s: &str) -> Option<String> {
    let t = s.trim();
    let after_step = t.strip_prefix("step")?;
    let after_arrow = after_step.trim_start().strip_prefix("<<")?;
    let tail = strip_inline_dev_comment(after_arrow.trim()).trim();
    if tail.is_empty() {
        None
    } else {
        Some(tail.to_string())
    }
}

/// Parse `step << A/B/C` into `["A", "B", "C"]` (class/faction restriction list).
///
/// Shares [`parse_step_gate`]'s dev-comment stripping: this list is what `is_known_class_token`
/// reads, so a leaked comment both poisons the tokens and can split on a `/` written inside prose.
pub(crate) fn parse_step_conditions(s: &str) -> Vec<String> {
    let t = s.trim();
    let after_step = match t.strip_prefix("step") {
        Some(a) => a,
        None => return Vec::new(),
    };
    let after_arrow = match after_step.trim_start().strip_prefix("<<") {
        Some(a) => strip_inline_dev_comment(a.trim()).trim(),
        None => return Vec::new(),
    };
    if after_arrow.is_empty() {
        return Vec::new();
    }
    after_arrow
        .split('/')
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty())
        .collect()
}

pub struct GuideSplitter;

impl GuideSplitter {
    pub fn split(source: &str) -> Result<SplitGuide, ImportError> {
        let extracted = Self::extract_body(source)?;
        let body = &extracted.body;
        let start = extracted.body_start_line;

        let mut headers = Vec::new();
        let mut body_lines = Vec::new();
        let mut seen_step = false;

        for (i, raw) in body.lines().enumerate() {
            let line_no = start + i;
            let text = raw.to_string();
            if text.trim().is_empty() {
                continue; // blank lines carry no information
            }
            if !seen_step {
                if is_step_marker(&text) {
                    seen_step = true;
                    body_lines.push(LocatedLine { line_no, text });
                } else {
                    headers.push(LocatedLine { line_no, text });
                }
            } else {
                body_lines.push(LocatedLine { line_no, text });
            }
        }

        Ok(SplitGuide {
            headers,
            body_lines,
        })
    }

    /// Extract the content between `RegisterGuide([[` and the matching `]])`, tracking the
    /// original source line where the body begins (for source mapping).
    fn extract_body(source: &str) -> Result<ExtractedBody, ImportError> {
        const OPEN: &str = "RegisterGuide([[";
        let open_idx = source.find(OPEN).ok_or(ImportError::NoGuideBlock)?;
        let after_open = open_idx + OPEN.len();
        const CLOSE: &str = "]])";
        let close_rel = source[after_open..]
            .find(CLOSE)
            .ok_or(ImportError::UnterminatedGuideBlock)?;
        let body = &source[after_open..after_open + close_rel];
        // `body` begins immediately after `RegisterGuide([[`, i.e. still on the SAME source line
        // as the marker — `body.lines()` therefore yields that line's remainder as its element 0.
        // So the 1-based line of element 0 is the marker's own line, which is exactly the number
        // of lines preceding (and including) it. The historical `+ 1` here shifted every
        // `SourceLineNo` in the crate one line too far: `#requires cloth1` at
        // `The Burning Crusade.lua:24728` reported as 24729, `#label Un'Goro End` at :102579 as
        // :102580. Verified against the corpus with ripgrep line numbers as ground truth.
        let body_start_line = source[..after_open].lines().count();
        Ok(ExtractedBody {
            body: body.to_string(),
            body_start_line,
        })
    }
}

struct ExtractedBody {
    body: String,
    body_start_line: SourceLineNo,
}

/// A single `RegisterGuide([[ ... ]])` block extracted from a bundle file (IF6), tagged with the
/// number of newlines that precede its `RegisterGuide([[` marker in the ORIGINAL bundle source.
/// Adding `line_offset` to every `SourceLineNo` produced by parsing `source` alone (which numbers
/// from its own line 1) turns it into a bundle-file-absolute line number (PR1b-iii line-offset
/// fix — `parse_guide_bundle`'s lines were previously block-relative and dormant).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GuideBlock {
    pub source: String,
    pub line_offset: usize,
}

/// A malformed block boundary found while scanning a bundle (PR1b-iii hardening, IF6). The scan
/// recovers past the offending boundary so a single bad block cannot silently swallow or merge
/// with the rest of the file.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum GuideBlockError {
    #[error("RegisterGuide block starting at line {0} has no matching ]]) close")]
    UnterminatedBlock(SourceLineNo),
    #[error(
        "RegisterGuide block starting at line {0} contains a nested RegisterGuide([[ at line {1} \
         before its own ]]) close — the two blocks would otherwise merge"
    )]
    NestedOpenBeforeClose(SourceLineNo, SourceLineNo),
}

/// Extract every `RegisterGuide([[ ... ]])` block from a bundle source file as self-contained
/// guide source strings, each independently valid input to [`crate::parse_guide`] (IF6). Corpus
/// reality: `The Burning Crusade.lua` is 253 separate blocks concatenated in one file, not
/// multiple `#name` headers inside a single block — an outer scan over block boundaries, before
/// the per-guide header/step parsing [`GuideSplitter::split`] already handles unchanged.
///
/// A block whose close is missing, or whose captured span contains another `RegisterGuide([[`
/// before its own close (meaning the naive scan would otherwise merge two blocks together), is
/// reported as a [`GuideBlockError`] instead of being silently dropped or merged; the scan still
/// recovers and continues past it (PR1b-iii hardening).
pub fn extract_guide_blocks(source: &str) -> Vec<Result<GuideBlock, GuideBlockError>> {
    const OPEN: &str = "RegisterGuide([[";
    const CLOSE: &str = "]])";
    let mut results = Vec::new();
    let mut cursor = 0;
    while let Some(open_rel) = source[cursor..].find(OPEN) {
        let open_idx = cursor + open_rel;
        let after_open = open_idx + OPEN.len();
        let open_line = source[..open_idx].matches('\n').count() + 1;

        let Some(close_rel) = source[after_open..].find(CLOSE) else {
            results.push(Err(GuideBlockError::UnterminatedBlock(open_line)));
            break; // no close exists anywhere in the remainder of the file either
        };
        let close_idx = after_open + close_rel + CLOSE.len();

        if let Some(nested_rel) = source[after_open..after_open + close_rel].find(OPEN) {
            let nested_open_idx = after_open + nested_rel;
            let nested_line = source[..nested_open_idx].matches('\n').count() + 1;
            results.push(Err(GuideBlockError::NestedOpenBeforeClose(open_line, nested_line)));
            // Resume scanning at the nested OPEN: the swallowed block still gets a chance to be
            // extracted on its own, correctly-bounded terms.
            cursor = nested_open_idx;
            continue;
        }

        results.push(Ok(GuideBlock {
            source: source[open_idx..close_idx].to_string(),
            line_offset: open_line - 1,
        }));
        cursor = close_idx;
    }
    results
}

#[cfg(test)]
mod bundle_tests {
    use super::{extract_guide_blocks, GuideBlock, GuideBlockError};

    #[test]
    fn bundle_source_yields_one_block_per_registerguide_header() {
        // Corpus shape: N `RegisterGuide([[ ... ]]);` blocks concatenated in one file (IF6).
        let src = "RXPGuides.RegisterGuide([[\n#name First\nstep\n.accept 1\n]]);\n\
                   RXPGuides.RegisterGuide([[\n#name Second\nstep\n.accept 2\n]]);\n\
                   RXPGuides.RegisterGuide([[\n#name Third\nstep\n.accept 3\n]]);";
        let blocks: Vec<GuideBlock> = extract_guide_blocks(src)
            .into_iter()
            .map(|r| r.expect("well-formed block"))
            .collect();
        assert_eq!(blocks.len(), 3);
        assert!(blocks[0].source.contains("#name First"));
        assert!(blocks[1].source.contains("#name Second"));
        assert!(blocks[2].source.contains("#name Third"));
        // Line-offset fix (PR1b-iii): each block's offset is the newline count before its own
        // `RegisterGuide([[`, not 0 for every block.
        assert_eq!(blocks[0].line_offset, 0);
        assert_eq!(blocks[1].line_offset, 5);
        assert_eq!(blocks[2].line_offset, 10);
    }

    #[test]
    fn unterminated_trailing_block_is_reported_not_silently_dropped() {
        // Hardening (PR1b-iii): a good leading block plus a trailing block that never closes.
        let src = "RXPGuides.RegisterGuide([[\n#name First\nstep\n.accept 1\n]]);\n\
                   RXPGuides.RegisterGuide([[\n#name Second\nstep\n.accept 2\n";
        let results = extract_guide_blocks(src);
        assert_eq!(results.len(), 2, "the good first block must still be extracted");
        assert!(results[0].is_ok());
        match &results[1] {
            Err(GuideBlockError::UnterminatedBlock(line)) => assert_eq!(*line, 6),
            other => panic!("expected UnterminatedBlock, got {other:?}"),
        }
    }

    #[test]
    fn nested_open_before_close_is_reported_and_scan_recovers() {
        // Simulates the missing-close/merge failure mode: block A's own `]])` is absent, so a
        // naive scan finds block B's close first and would swallow B's header/body into A.
        let src = "RXPGuides.RegisterGuide([[\n#name First\nstep\n.accept 1\n\
                   RXPGuides.RegisterGuide([[\n#name Second\nstep\n.accept 2\n]]);";
        let results = extract_guide_blocks(src);
        assert_eq!(results.len(), 2);
        assert!(
            matches!(results[0], Err(GuideBlockError::NestedOpenBeforeClose(_, _))),
            "must not silently merge, got {:?}", results[0]
        );
        let recovered = results[1].as_ref().expect("the swallowed block must still be recoverable on its own");
        assert!(recovered.source.contains("#name Second"));
    }
}
