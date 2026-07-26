//! RED (compile-error): a `#label` name may be DEFINED more than once in one guide block, and the
//! importer must not pick a winner.
//!
//! `importer/src/label_graph.rs::LabelGraphBuilder::resolve` did
//! `graph.definitions.entry(name).or_insert(step.index)` over a
//! `HashMap<String, usize>` — naive first-wins over a name whose `<<` tail has just been stripped.
//! Measured on `The Burning Crusade.lua`:
//!
//! ```text
//! 16241  #completewith UldaLoch
//! 16255  step                       <- no gate on the marker
//! 16256      #label UldaLoch << Mage     <- gate lives on the DIRECTIVE
//! 16263  step << !Mage              <- gate lives on the STEP MARKER
//! 16264      #label UldaLoch             <- directive itself is ungated
//! ```
//!
//! Before the gate-stripping change the key was the whole value `"UldaLoch << Mage"`, so it never
//! collided and `:16264` won for everyone — the Mage target was unreachable. After it, both key on
//! `"UldaLoch"` and `:16256` (Mage-ONLY) wins for EVERYONE. That is the mirror-image error, and the
//! probe confirms it today: `definitions["UldaLoch"] == 126`, the step of `:16256`.
//!
//! The importer cannot break the tie: choosing needs a resolved ARCHETYPE, which is C2 — the
//! COMPILER's job. So the carrier must keep BOTH:
//!
//! ```text
//! LabelDef { step: usize, gate: Option<String>, line: SourceLineNo }
//! LabelGraph::definitions: HashMap<String, Vec<LabelDef>>   // source order, never overwritten
//! ```
//!
//! A name is unresolved only when its vector is EMPTY. Until `LabelDef` exists this file does not
//! compile — the intended RED for a missing Rust carrier (`E0432 unresolved import`), never a wrong
//! assertion. The rest of the defect set is asserted at RUNTIME in
//! `tests/import_fidelity_regressions.rs`, including the `DUPLICATE_LABEL` diagnostic that pairs
//! with this change; that file compiles today and must be run with
//! `cargo test -p sentinel-importer --test import_fidelity_regressions` while this one is red.
//!
//! ## WHAT THIS TEST CANNOT SEE
//!
//! * **It does not resolve anything.** Keeping both definitions is necessary for a correct
//!   archetype-aware binding; it is not sufficient. No assertion here proves a Mage ever reaches
//!   `:16256`. `compiler/src/lib.rs` has no `LabelDef` consumer at all, so this can be fully green
//!   with the in-game route still wrong.
//! * **It pins ONE group.** The corpus has 65 duplicate-name groups per block. The other 64 are
//!   not re-derived here; the census lives in `import_fidelity_regressions.rs`'s header.
//! * **The two gates of this group are NOT in the same place** — `:16256` carries its gate on the
//!   `#label` directive, `:16264` carries `!Mage` on its `step` marker. `LabelDef.gate` therefore
//!   holds only HALF the disambiguating information for this group; the other half is recovered
//!   through `LabelDef.step`. That indirection is asserted below because a resolver that reads
//!   `gate` alone sees "one gated, one ungated" and cannot tell this group apart from a genuinely
//!   ambiguous one.
//! * **It reads ONE block, not the file.** `The Burning Crusade.lua` is 253 concatenated
//!   `RegisterGuide` blocks; parsing all of them costs ~21s, so only the block containing
//!   `:16256` is parsed. Cross-block duplicate names are invisible here by construction.

use sentinel_importer::{extract_guide_blocks, parse_guide, LabelDef, ParsedGuide};

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../sentinel/docs/adr/restedxp guides");

/// Parse ONLY the `RegisterGuide([[ ... ]])` block of `file` that contains the absolute source line
/// `abs_line`, and return it with that block's line offset. `parse_guide` numbers a block from its
/// own line 1, exactly as `parse_guide_bundle` does before shifting; adding `line_offset` makes a
/// reported line file-absolute and directly comparable to a `ripgrep` line number.
fn block_containing(file: &str, abs_line: usize) -> (ParsedGuide, usize) {
    let path = format!("{CORPUS}/{file}");
    let src = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("the real corpus is the fixture here — {path}: {e}"));
    for block in extract_guide_blocks(&src) {
        let block = block.expect("well-formed block");
        let start = block.line_offset + 1;
        let end = start + block.source.lines().count();
        if (start..=end).contains(&abs_line) {
            let parsed = parse_guide(&block.source).expect("block parses");
            return (parsed, block.line_offset);
        }
    }
    panic!("no RegisterGuide block in {file} contains line {abs_line}");
}

/// `The Burning Crusade.lua:16256  #label UldaLoch << Mage`
/// `The Burning Crusade.lua:16263  step << !Mage`
/// `The Burning Crusade.lua:16264  #label UldaLoch`
/// (the same shape repeats at `:121444` / `:121452`, referenced from `:121423`)
///
/// THE decisive test. `label_definition_with_a_gate_tail_is_keyed_by_its_name_not_the_whole_value`
/// in `guide_gate_semantics.rs` asserts only `definitions.contains_key("UldaLoch")` — which is true
/// whichever definition won, so it stays green while the binding is inverted. This asserts WHICH
/// definitions survive.
#[test]
fn both_definitions_of_a_duplicated_label_survive_with_their_gates_and_lines() {
    let (guide, offset) = block_containing("The Burning Crusade.lua", 16256);

    let defs: &Vec<LabelDef> = guide
        .labels
        .definitions
        .get("UldaLoch")
        .expect("TBC:16256/:16264 both define `UldaLoch` in this block");

    assert_eq!(
        defs.len(),
        2,
        "TBC:16256 and TBC:16264 are TWO definitions of one name. `or_insert` keeps the first and \
         DISCARDS the second, which silently binds `#completewith UldaLoch` (TBC:16241) to the \
         Mage-only step for every non-Mage character. Got: {defs:?}"
    );

    // Source order, not HashMap order: :16256 precedes :16264.
    assert_eq!(
        defs[0].line + offset,
        16256,
        "first definition, in SOURCE order — the importer must not reorder what it cannot rank"
    );
    assert_eq!(
        defs[0].gate.as_deref(),
        Some("Mage"),
        "TBC:16256 — `#label UldaLoch << Mage`. The `<< Mage` tail is this DEFINITION's audience; \
         stripping it off the key without keeping it on the entry is what makes the two \
         definitions indistinguishable and the tie-break arbitrary"
    );

    assert_eq!(defs[1].line + offset, 16264, "second definition, in source order");
    assert_eq!(
        defs[1].gate, None,
        "TBC:16264 — the `#label` line itself carries no tail; its `!Mage` audience is on the \
         `step` marker at TBC:16263, one line above"
    );

    // The half of the disambiguation that `gate` cannot hold must still be reachable, or a
    // resolver cannot tell this group from a genuinely ambiguous one.
    assert_ne!(defs[0].step, defs[1].step, "two definitions on two different steps");
    assert_eq!(
        guide.steps[defs[1].step].gate.as_deref(),
        Some("!Mage"),
        "TBC:16263 — `LabelDef.step` must point at the step whose marker carries `!Mage`, or the \
         `Mage` / `!Mage` complement that makes this group legitimate is unrecoverable"
    );
    assert_eq!(
        guide.steps[defs[0].step].gate, None,
        "TBC:16255 — the Mage definition's own step marker is bare; its gate is on the directive"
    );

    // A name is unresolved only when its vector is EMPTY.
    assert!(
        !guide.labels.unresolved.iter().any(|r| r.label == "UldaLoch"),
        "TBC:16241 `#completewith UldaLoch` resolves — two definitions is still resolved, not \
         ambiguous-therefore-missing. Got: {:?}",
        guide.labels.unresolved
    );
}
