//! [`LabelGraphBuilder`]: resolve `#label` definitions against `#completewith` and `#requires`.
//!
//! RXP guides reference steps by label. A label is *defined* by `#label X` and *referenced* by
//! `#completewith X` (ordering: "finish together with X") or `#requires X` (ordering: "X must
//! already be done"). Per ADR `03` §18 (Import Diagnostics) these are reported, not fatal: the
//! graph records [`LabelGraph::unresolved`] / [`LabelGraph::unresolved_requires`] for any
//! reference whose target is never defined.
//!
//! `next` is a reserved RXP keyword (`#completewith next` = "complete with the following step")
//! and is intentionally skipped. It is the *only* reserved word — `end` is a real label with 11
//! definitions and 15 references in the corpus, so reserving terminator-looking names breaks them.
//!
//! Every directive value may carry a trailing `<< audience` gate. The gate is stripped **before**
//! keying, on definitions and references alike; keying on the whole value made
//! `#label UldaLoch << Mage` unreachable and silently bound `#completewith UldaLoch` to the wrong
//! step, and comparing `next` before stripping misfiled every `#completewith next << <gate>` line
//! as a reference to a label literally named `"next << !Druid"`.
//!
//! Stripping the gate makes two definitions of one name collide, and **the importer must not break
//! that tie**. Choosing between `#label UldaLoch << Mage` and the `#label UldaLoch` that sits under
//! `step << !Mage` requires a resolved ARCHETYPE, and archetype resolution is C2 — the compiler's
//! job. So every definition is kept, in source order, with the gate written on its own `#label`
//! line and the index of the step that carries it; the compiler picks later. See [`LabelDef`].

use crate::{split_directive_gate, ImportError, SourceLineNo, Step};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A `#completewith X` / `#requires X` reference, tagged with where it occurred.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LabelRef {
    pub label: String,
    pub from_step: usize,
    pub line: SourceLineNo,
}

/// A single `#label NAME [<< gate]` definition, kept whole so two definitions of one name stay
/// distinguishable.
///
/// `gate` is only HALF the disambiguating information: in the corpus's 2 gate-disambiguated groups
/// one half is written on the directive (`#label UldaLoch << Mage`) and the other on the step
/// marker (`step << !Mage`, with a bare `#label UldaLoch` under it). `step` is the route to the
/// second half — index into [`ParsedGuide::steps`](crate::ParsedGuide::steps).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LabelDef {
    /// Index of the step whose body carries this `#label` directive.
    pub step: usize,
    /// The `<<` tail of the `#label` line itself, when it has one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<String>,
    /// Source line of the `#label` directive.
    pub line: SourceLineNo,
}

/// Resolved label graph for a parsed guide.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct LabelGraph {
    /// `label` -> EVERY definition of that name, in source order, never overwritten.
    ///
    /// A multimap because one name may legitimately be defined more than once in a guide (66
    /// collisions across the corpus's 277 blocks) and the importer has no archetype with which to
    /// rank them — see the module header. Consequently a name is *unresolved* only when it has no
    /// definition at all (no key, or an empty vector), never when it has more than one.
    pub definitions: HashMap<String, Vec<LabelDef>>,
    /// Every `#completewith X` reference (excluding the reserved `next`).
    pub references: Vec<LabelRef>,
    /// Subset of [`references`](LabelGraph::references) whose target label is undefined.
    pub unresolved: Vec<LabelRef>,
    /// Every `#requires X` edge.
    #[serde(default)]
    pub requires: Vec<LabelRef>,
    /// Subset of [`requires`](LabelGraph::requires) whose target label is undefined.
    #[serde(default)]
    pub unresolved_requires: Vec<LabelRef>,
}

pub struct LabelGraphBuilder;

impl LabelGraphBuilder {
    pub fn resolve(steps: &[Step]) -> Result<LabelGraph, ImportError> {
        let mut graph = LabelGraph::default();

        for step in steps {
            for d in &step.directives {
                if d.name.eq_ignore_ascii_case("label") {
                    let (name, gate) = split_directive_gate(d.value.as_deref().unwrap_or_default());
                    if !name.is_empty() {
                        // Keep every definition. `or_insert` (first wins) and `insert` (last wins)
                        // are both arbitrary tie-breaks over a name whose `<<` tail has just been
                        // stripped, and an arbitrary tie-break here silently binds
                        // `#completewith X` to the wrong audience's step.
                        graph.definitions.entry(name).or_default().push(LabelDef {
                            step: step.index,
                            gate,
                            line: d.line,
                        });
                    }
                }
            }
        }

        for step in steps {
            for d in &step.directives {
                let is_completewith = d.name.eq_ignore_ascii_case("completewith");
                let is_requires = d.name.eq_ignore_ascii_case("requires");
                if !is_completewith && !is_requires {
                    continue;
                }
                let (name, _gate) = split_directive_gate(d.value.as_deref().unwrap_or_default());
                if name.is_empty() {
                    continue;
                }
                if is_completewith && name.eq_ignore_ascii_case("next") {
                    continue; // reserved keyword, not a label
                }
                let r#ref = LabelRef {
                    label: name.clone(),
                    from_step: step.index,
                    line: d.line,
                };
                // Unresolved means NO definition, not "no unique definition": two definitions of
                // one name is still a resolved reference, to be disambiguated downstream.
                let resolved = graph.definitions.get(&name).is_some_and(|d| !d.is_empty());
                if is_completewith {
                    if !resolved {
                        graph.unresolved.push(r#ref.clone());
                    }
                    graph.references.push(r#ref);
                } else {
                    if !resolved {
                        graph.unresolved_requires.push(r#ref.clone());
                    }
                    graph.requires.push(r#ref);
                }
            }
        }

        Ok(graph)
    }
}
