//! [`LabelGraphBuilder`]: resolve `#label` definitions and `#completewith` references.
//!
//! RXP guides reference steps by label. A label is *defined* by `#label X` and *referenced* by
//! `#completewith X`. Per ADR `03` §18 (Import Diagnostics) these are reported, not fatal: the
//! graph records [`LabelGraph::unresolved`] for any reference whose target is never defined.
//!
//! `next` is a reserved RXP keyword (`#completewith next` = "complete with the following step")
//! and is intentionally skipped.

use crate::{ImportError, Step, SourceLineNo};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A `#completewith X` reference, tagged with where it occurred.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LabelRef {
    pub label: String,
    pub from_step: usize,
    pub line: SourceLineNo,
}

/// Resolved label graph for a parsed guide.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct LabelGraph {
    /// `label` -> owning step index.
    pub definitions: HashMap<String, usize>,
    /// Every `#completewith X` reference (excluding the reserved `next`).
    pub references: Vec<LabelRef>,
    /// Subset of [`references`](LabelGraph::references) whose target label is undefined.
    pub unresolved: Vec<LabelRef>,
}

pub struct LabelGraphBuilder;

impl LabelGraphBuilder {
    pub fn resolve(steps: &[Step]) -> Result<LabelGraph, ImportError> {
        let mut graph = LabelGraph::default();

        for step in steps {
            for d in &step.directives {
                if d.name.eq_ignore_ascii_case("label") {
                    if let Some(label) = d.value.as_ref().map(|v| v.trim().to_string()) {
                        if !label.is_empty() {
                            graph.definitions.insert(label, step.index);
                        }
                    }
                }
            }
        }

        for step in steps {
            for d in &step.directives {
                if d.name.eq_ignore_ascii_case("completewith") {
                    let label = match d.value.as_ref().map(|v| v.trim().to_string()) {
                        Some(l) if !l.is_empty() => l,
                        _ => continue,
                    };
                    if label.eq_ignore_ascii_case("next") {
                        continue; // reserved keyword, not a label
                    }
                    let r#ref = LabelRef {
                        label: label.clone(),
                        from_step: step.index,
                        line: d.line,
                    };
                    if !graph.definitions.contains_key(&label) {
                        graph.unresolved.push(r#ref.clone());
                    }
                    graph.references.push(r#ref);
                }
            }
        }

        Ok(graph)
    }
}
