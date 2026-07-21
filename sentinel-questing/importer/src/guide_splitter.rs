//! [`GuideSplitter`]: extract the guide body from `RXPGuides.RegisterGuide([[ ... ]])`
//! and split it into the header section (before the first `step`) and the step section.

use crate::{ImportError, LocatedLine, SourceLineNo};

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

/// Parse `step << A/B/C` into `["A", "B", "C"]` (class/faction restriction list).
pub(crate) fn parse_step_conditions(s: &str) -> Vec<String> {
    let t = s.trim();
    let after_step = match t.strip_prefix("step") {
        Some(a) => a,
        None => return Vec::new(),
    };
    let after_arrow = match after_step.trim_start().strip_prefix("<<") {
        Some(a) => a.trim(),
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
        // Lines before `after_open` + 1 = the 1-based line where the body's first line lives.
        let body_start_line = source[..after_open].lines().count() + 1;
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
