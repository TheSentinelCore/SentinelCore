//! The guide-block header into [`GuideMeta`](k::GuideMeta) — `#name`, `#group`, `#subgroup`,
//! `#version`, `#next`.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 ([`GuideMeta`](k::GuideMeta)), §4.2 (the header
//! disposition table), §6.5 (the three version axes), §5.2 (C2).
//!
//! # One rule, applied twice with a different arity
//!
//! Every header entry arrives as a [`Gated<String>`] — value plus the raw `<<` tail the author
//! wrote — and is kept iff this artifact's [`Archetype`](k::Archetype) satisfies that tail. The
//! resolver is [`archetype::resolve_gate`], the same one every `#requires`, `#label` and command
//! gate goes through, so the guide pack has one gate vocabulary and not two. What differs between
//! the fields is only how many survivors the wire shape can hold:
//!
//! * `name` / `group` / `subgroup` are single-valued, so the **first** survivor wins. The corpus's
//!   one multi-`#name` block (`A-1-11-Human.lua:2678`) gates its pair `!Warlock` / `Warlock`, and
//!   the four multi-`#subgroup` blocks gate theirs `!classic` / `classic`; both pairs are mutually
//!   exclusive, so on every real input "first survivor" and "the only survivor" are the same entry.
//!   A block where they are not is a defect, and it is reported rather than silently resolved.
//! * `next` is a list, so **every** survivor is kept in source order. `A-1-11-Human.lua:2` writes
//!   two successors as one `;` list and `A-1-11-Dwarf-Gnome.lua:569` writes the identical shape as
//!   two separately gated lines; the importer already flattens both to one entry per successor, and
//!   keeping only the first survivor here would truncate one spelling while leaving the other
//!   whole.
//!
//! # `#displayname` is not here, and that is the point
//!
//! §4.2 rules it DROP — "pure UI chrome" — and [`GuideHeaders`] has no field for it, so this module
//! could not read one if it wanted to. It matters because the temptation is real: `A-11-23.lua`
//! carries three `#displayname` lines, gated and disagreeing (`10-14` / `11-14` / `12-14`), while
//! `#name` is the single identity `#next` and `#include` resolve against. A `meta.name` taken from
//! a displayname would be archetype-dependent, and every chaining edge in the pack points at a
//! `#name`.

use sentinel_models::authoring::{Diagnostic, Gated, GuideGate, Project, Severity};
use sentinel_models::kernel as k;

use super::{archetype, LoweringError};

/// The `name` this artifact carries came from no header entry this archetype satisfies.
pub const GUIDE_NAME_UNGATED_FALLBACK: &str = "GUIDE_NAME_UNGATED_FALLBACK";

/// More than one entry of a single-valued header survived gate resolution.
pub const AMBIGUOUS_GUIDE_HEADER: &str = "AMBIGUOUS_GUIDE_HEADER";

/// Assemble [`GuideMeta`](k::GuideMeta) for one resolved archetype.
///
/// Returns a [`LoweringError`] only for what [`archetype::resolve_gate`] itself refuses — a token
/// outside the closed `<<` vocabulary. A header gated on a word the compiler cannot read is a
/// header whose audience it cannot decide, and guessing there picks the wrong guide identity for a
/// whole profile.
pub(crate) fn lower_guide_meta(
    project: &Project,
    archetype: &k::Archetype,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<k::GuideMeta, LoweringError> {
    let headers = &project.guide_headers;

    let name = match single("#name", &headers.name, archetype, diagnostics)? {
        Some(name) => name,
        None => {
            // The project's own name, which the importer derived from this very header before any
            // archetype existed. Announced rather than taken quietly: `GuideMeta` has no `Option`
            // here, an empty name is a profile nothing can chain to, and a name chosen by a rule
            // the author did not write is exactly the substitution the rest of this lowering
            // refuses to make in silence.
            if !headers.name.is_empty() {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: GUIDE_NAME_UNGATED_FALLBACK.to_string(),
                    message: format!(
                        "no `#name` in this block applies to the compiled archetype, so the \
                         artifact is named '{}' — the name the importer already recorded. An \
                         artifact with no name cannot be chained to by another guide's `#next`",
                        project.metadata.name
                    ),
                    entity: Some(project.metadata.name.clone()),
                    action: None,
                });
            }
            project.metadata.name.clone()
        }
    };

    Ok(k::GuideMeta {
        name,
        // Empty, never invented. `#group` is present and ungated in all 277 blocks, so an empty one
        // here means an editor-authored project or a block that genuinely declared none — and the
        // catalogue bucket is not derivable from anything else the project carries.
        group: single("#group", &headers.group, archetype, diagnostics)?.unwrap_or_default(),
        subgroup: single("#subgroup", &headers.subgroup, archetype, diagnostics)?,
        // `0` is "this block declared no revision", and it is a required `u32` on the wire. The
        // alternative — a plausible `1` — would compare equal to a real revision 1 and silence the
        // §6.5 recompile warning that is this axis's only purpose. The `Option` narrowing itself
        // happened at import; the raw string survives in `ImportMetadata::guide_version`.
        source_version: headers.source_version.unwrap_or(0),
        next: surviving(&headers.next, archetype, diagnostics)?,
    })
}

/// Every entry whose gate `archetype` satisfies, in source order.
fn surviving(
    entries: &[Gated<String>],
    archetype: &k::Archetype,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<Vec<String>, LoweringError> {
    let mut kept = Vec::new();
    for entry in entries {
        if applies(entry.gate.as_ref(), archetype, diagnostics)? {
            kept.push(entry.value.clone());
        }
    }
    Ok(kept)
}

/// The one survivor of a single-valued header, or `None` when the archetype satisfies none.
///
/// A second survivor is a **warning, not a refusal**: the value chosen is still one the author
/// wrote for an audience that includes this archetype, so the artifact is usable, and refusing the
/// whole compile over a duplicated `#subgroup` would delete a working guide over a catalogue label.
/// What must not happen is choosing in silence — the corpus's real multi-entry blocks are all
/// mutually exclusive pairs, so a second survivor means the gates stopped being exclusive and
/// nobody would otherwise find out.
fn single(
    directive: &str,
    entries: &[Gated<String>],
    archetype: &k::Archetype,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<Option<String>, LoweringError> {
    let kept = surviving(entries, archetype, diagnostics)?;
    if kept.len() > 1 {
        diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: AMBIGUOUS_GUIDE_HEADER.to_string(),
            message: format!(
                "{} `{directive}` entries apply to the compiled archetype, and `GuideMeta` carries \
                 one. The first is used and the rest are dropped — the corpus's multi-entry \
                 headers are all mutually exclusive gated pairs, so more than one survivor means \
                 the gates no longer separate them",
                kept.len()
            ),
            entity: kept.first().cloned(),
            action: None,
        });
    }
    Ok(kept.into_iter().next())
}

/// Resolve one header entry's `<<` tail, collecting whatever the resolver had to say.
///
/// `None` is "no gate", which applies to everyone — not to be confused with a gate that resolved to
/// [`GateOutcome::DoesNotApply`](archetype::GateOutcome::DoesNotApply), and not with the `skip`
/// sentinel either, which the resolver reports as its own outcome.
fn applies(
    gate: Option<&GuideGate>,
    archetype: &k::Archetype,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<bool, LoweringError> {
    let Some(gate) = gate else {
        return Ok(true);
    };
    let resolution = archetype::resolve_gate(gate, archetype)?;
    diagnostics.extend(resolution.diagnostics);
    Ok(resolution.outcome == archetype::GateOutcome::Applies)
}
