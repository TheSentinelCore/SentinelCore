//! RED (compile-error): the guide-block header must survive the importer boundary.
//!
//! `#name`, `#group`, `#subgroup`, `#version` and `#next` sit above the first `step` of every
//! `RXPGuides.RegisterGuide([[ ]])` block. They are lexed into `Token::GuideHeader` and reach
//! `ParsedGuide::headers` today — and then all but two of them die there: `ProjectBuilder::build`
//! reads `#name` (to name the project) and `#version` (into `ImportMetadata::guide_version`) and
//! drops `#group`, `#subgroup` and `#next` on the floor. `authoring::Project` has nowhere to put
//! them, so the profile's guide identity cannot be assembled one crate later.
//!
//! These tests name the carrier the implementation must add:
//!
//! ```text
//! authoring::GuideHeaders {
//!     name:           Vec<Gated<String>>,
//!     group:          Vec<Gated<String>>,
//!     subgroup:       Vec<Gated<String>>,
//!     source_version: Option<u32>,
//!     next:           Vec<Gated<String>>,
//! }
//! Project::guide_headers: GuideHeaders   // #[serde(default)] — additive
//! ```
//!
//! Until it exists this file does not compile. That is the intended RED for Rust: the failure is
//! `E0609 no field` / `E0432 unresolved import`, never a wrong assertion.
//!
//! ## WHAT THESE TESTS CANNOT SEE
//!
//! * **They stop at the authoring boundary.** Nothing here proves the compiler assembles
//!   `kernel::GuideMeta` from these fields, or that `meta.name` is what `#next`/`#include`
//!   resolve against. A header that reaches `Project` intact can still die one crate later and
//!   every assertion below stays green.
//! * **They never evaluate a gate.** `Gated::gate` is asserted as a verbatim string. No test
//!   here proves `!Warlock` selects the right one of `A-1-11-Human.lua:2678`'s two `#name`
//!   lines for any archetype — that selection is the compiler's, and picking wrong is invisible
//!   here. The tests only prove both candidates and both gates arrive, so the choice *can* be
//!   made.
//! * **They pin shape, not census.** The corpus figures that motivated every cardinality below
//!   (277 blocks; `#name` 1×276 / 2×1; `#group` 1×277, never gated; `#subgroup` 0×9 / 1×264 /
//!   2×4; `#version` 0×12 / 1×265, always numeric; `#next` 0×128 / 1×142 / 2×7) are re-derived
//!   in no assertion. An implementation can satisfy this file and still mishandle a header shape
//!   that occurs in the other 276 blocks.
//! * **`#displayname` is asserted ABSENT, not handled.** These tests prove it never becomes
//!   `name`. They do not prove it is unreachable by some other route, and they say nothing about
//!   the other headers with no typed carrier (`#defaultfor`, `#xprate`, `#tbc`, `#include`, …),
//!   which remain dropped.
//! * **Only the first block of a corpus file is read.** `parse_guide` stops at the first `]])`,
//!   so the multi-block header shapes (`A-1-11-Human.lua:2678`, `A-1-11-Dwarf-Gnome.lua:569`)
//!   are reproduced as synthetic fragments rather than measured in place.
//! * **`MemoryQueryClient::new()` has no fixtures**, so nothing in the step bodies resolves. That
//!   is deliberate — a header is not a quest — but it means these projects are otherwise inert.

use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_models::authoring::{Gated, Project};
use sentinel_queryclient::MemoryQueryClient;

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../sentinel/docs/adr/restedxp guides");

async fn build(source: &str) -> Project {
    let guide = parse_guide(source).expect("parse ok");
    let client = MemoryQueryClient::new();
    ProjectBuilder::build(&guide, "test.lua", &client).await.expect("build ok")
}

/// The first `RegisterGuide` block of a corpus file, verbatim.
fn first_block_of(file: &str) -> String {
    let path = format!("{CORPUS}/{file}");
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("the real corpus is the fixture here — {path}: {e}"))
}

/// Values only, in source order — the gate is asserted separately where it matters.
fn values(entries: &[Gated<String>]) -> Vec<&str> {
    entries.iter().map(|g| g.value.as_str()).collect()
}

fn gates(entries: &[Gated<String>]) -> Vec<Option<&str>> {
    entries.iter().map(|g| g.gate.as_ref().map(|g| g.0.as_str())).collect()
}

// ===========================================================================
// The whole header of one real block, end to end.
// ===========================================================================

/// `A-11-23.lua:5-15` — the header of the block the ADR 07 worked example is drawn from:
///
/// ```text
///  5  #version 7
///  6  #group RestedXP TBC Guide (A)
///  7  << Alliance
///  8  #xprate >1.49 << Human Warlock
///  9  #name 12-14 Darkshore
/// 10  #displayname 10-14 Darkshore << Dwarf Hunter
/// 11  #displayname 11-14 Darkshore << !Human !Mage
/// 12  #displayname 12-14 Darkshore << Gnome Mage
/// 13  #subgroup RestedXP Alliance 1-20
/// 14  #defaultfor Human/NightElf/Dwarf/Gnome !Warlock
/// 15  #next 14-20 Bloodmyst
/// ```
#[tokio::test]
async fn the_guide_block_header_reaches_the_project() {
    let project = build(&first_block_of("A-11-23.lua")).await;
    let h = &project.guide_headers;

    assert_eq!(values(&h.name), vec!["12-14 Darkshore"], "got: {:?}", h.name);
    assert_eq!(values(&h.group), vec!["RestedXP TBC Guide (A)"], "got: {:?}", h.group);
    assert_eq!(values(&h.subgroup), vec!["RestedXP Alliance 1-20"], "got: {:?}", h.subgroup);
    assert_eq!(h.source_version, Some(7), "got: {:?}", h.source_version);
    assert_eq!(values(&h.next), vec!["14-20 Bloodmyst"], "got: {:?}", h.next);
}

/// `#displayname` is DROP, not an alias for `#name`.
///
/// The obvious wrong implementation — prefer `#displayname` when the block has one — is
/// plausible and produces `"10-14 Darkshore"` for `A-11-23.lua`, which is what the ADR 07
/// worked example printed before it was corrected. Two independent reasons it is wrong:
///
/// 1. `#displayname` is pure UI chrome (ADR `07_RUNTIME_PROFILE_SCHEMA.md` §4.2, disposition
///    table). `name` is the identity `#next` and `#include` resolve against — a display string
///    cannot be that, because three of them can coexist in one block.
/// 2. All three of this block's `#displayname` lines are gated, and they disagree
///    (`10-14`/`11-14`/`12-14`). "Take the first" is not a rule, it is a coin toss.
#[tokio::test]
async fn displayname_never_becomes_the_guide_name() {
    let project = build(&first_block_of("A-11-23.lua")).await;
    let h = &project.guide_headers;

    assert_eq!(values(&h.name), vec!["12-14 Darkshore"], "got: {:?}", h.name);
    for field in [&h.name, &h.group, &h.subgroup, &h.next] {
        assert!(
            !field.iter().any(|g| g.value.starts_with("10-14") || g.value.starts_with("11-14")),
            "a `#displayname` leaked into a typed header carrier; got: {field:?}"
        );
    }
    assert_eq!(
        project.metadata.name, "12-14 Darkshore",
        "the project is named by `#name`, not by any `#displayname`; got: {:?}",
        project.metadata.name
    );
}

// ===========================================================================
// A header directive carries its own `<<` gate — 31 corpus lines across the five keys.
// ===========================================================================

/// `A-1-11-Dwarf-Gnome.lua:569  #name 6-11 Dun Morogh << !Hunter`
///
/// The gate must be split OFF the value, exactly as `#label`/`#requires`/`#xprate` already are.
/// Leaving it attached is not hypothetical: the last `import-guides` run over the pack emitted
/// `.questing/projects/11-12-Loch-Modan-<<-!Warlock-2.json` (generated output, gitignored), which
/// is the gate tail of `A-1-11-Human.lua:2678` glued onto a project name and then onto a filename.
#[tokio::test]
async fn a_gated_name_header_splits_its_gate_off_the_value() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 6-11 Dun Morogh << !Hunter
step
    .goto 1439,35.743,43.710
]])"#,
    )
    .await;
    let h = &project.guide_headers;

    assert_eq!(values(&h.name), vec!["6-11 Dun Morogh"], "value only — the tail is not part of it");
    assert_eq!(gates(&h.name), vec![Some("!Hunter")], "got: {:?}", h.name);
    assert_eq!(
        project.metadata.name, "6-11 Dun Morogh",
        "the gate tail must not reach the project name; got: {:?}",
        project.metadata.name
    );
}

/// `A-1-11-Human.lua:2678` — the one block in the pack with TWO `#name` lines:
///
/// ```text
/// #name 11-12 Loch Modan << !Warlock
/// #name 12-14 Loch Modan << Warlock
/// ```
///
/// They are archetype alternatives, not a duplicate to deduplicate. Both must arrive with their
/// own gate, or the choice between them has already been made — silently, and for every
/// archetype — before anything that knows the archetype has run.
#[tokio::test]
async fn two_gated_name_headers_both_survive_with_their_own_gates() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name 11-12 Loch Modan << !Warlock
#name 12-14 Loch Modan << Warlock
step
    .goto 1439,35.743,43.710
]])"#,
    )
    .await;
    let h = &project.guide_headers;

    assert_eq!(values(&h.name), vec!["11-12 Loch Modan", "12-14 Loch Modan"], "got: {:?}", h.name);
    assert_eq!(gates(&h.name), vec![Some("!Warlock"), Some("Warlock")], "got: {:?}", h.name);
}

// ===========================================================================
// `#next` — the `;` list and the gate are independent.
// ===========================================================================

/// `A-1-11-Human.lua:2` and `:3`:
///
/// ```text
/// #next 12-14 Loch Modan;12-14 Darkshore << Warlock
/// #next 11-12 Loch Modan;12-14 Darkshore << !Warlock
/// ```
///
/// `;` separates chained successors *within* one line; two `#next` lines with different gates are
/// archetype alternatives. `A-1-11-Dwarf-Gnome.lua:569` writes the same two-successor shape as
/// two separate gated lines instead, which is why a `;` element and a whole line flatten to the
/// same thing: one entry apiece, each carrying its line's gate.
#[tokio::test]
async fn semicolon_separated_next_alternatives_become_one_entry_each() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name 1-11 Elwynn Forest
#next 12-14 Loch Modan;12-14 Darkshore << Warlock
#next 11-12 Loch Modan;12-14 Darkshore << !Warlock
step
    .goto 1439,35.743,43.710
]])"#,
    )
    .await;
    let h = &project.guide_headers;

    assert_eq!(
        values(&h.next),
        vec!["12-14 Loch Modan", "12-14 Darkshore", "11-12 Loch Modan", "12-14 Darkshore"],
        "got: {:?}",
        h.next
    );
    assert_eq!(
        gates(&h.next),
        vec![Some("Warlock"), Some("Warlock"), Some("!Warlock"), Some("!Warlock")],
        "each `;` element inherits its own line's gate; got: {:?}",
        h.next
    );
}

// ===========================================================================
// `#version` — numeric, and the raw string is still kept where it already was.
// ===========================================================================

/// `#version` is the upstream guide-pack revision (265 of 277 blocks carry one; every value in
/// the pack parses as an integer). It is typed here because a profile compares versions, and it
/// stays a raw `String` in `ImportMetadata::guide_version` so an unparseable future value is
/// preserved rather than destroyed by the narrowing.
#[tokio::test]
async fn version_is_carried_as_a_number_without_discarding_the_raw_string() {
    let project = build(&first_block_of("A-11-23.lua")).await;

    assert_eq!(project.guide_headers.source_version, Some(7));
    assert_eq!(
        project.import_metadata.as_ref().map(|m| m.guide_version.as_str()),
        Some("7"),
        "got: {:?}",
        project.import_metadata
    );
}

/// A block with no `#version` (12 of 277) is not version zero.
#[tokio::test]
async fn a_block_without_a_version_header_carries_none_not_zero() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#group RestedXP TBC Guide (A)
#name Versionless
step
    .goto 1439,35.743,43.710
]])"#,
    )
    .await;

    assert_eq!(
        project.guide_headers.source_version, None,
        "got: {:?}",
        project.guide_headers.source_version
    );
}

/// A block with none of the five (9 of 277 have no `#subgroup`, 128 no `#next`) yields empty
/// carriers, not a panic and not a placeholder.
#[tokio::test]
async fn absent_headers_yield_empty_carriers() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#name Bare
step
    .goto 1439,35.743,43.710
]])"#,
    )
    .await;
    let h = &project.guide_headers;

    assert!(h.group.is_empty(), "got: {:?}", h.group);
    assert!(h.subgroup.is_empty(), "got: {:?}", h.subgroup);
    assert!(h.next.is_empty(), "got: {:?}", h.next);
    assert_eq!(h.source_version, None, "got: {:?}", h.source_version);
    assert_eq!(values(&h.name), vec!["Bare"], "got: {:?}", h.name);
}

// ===========================================================================
// Provenance.
// ===========================================================================

/// Every entry keeps the source line it was authored on. A header carrier without provenance is
/// unfixable from a diagnostic: `#next` names a guide that may not exist in the pack, and the
/// reader needs the line, not the value, to go correct it.
#[tokio::test]
async fn every_header_entry_keeps_its_source_line() {
    // Line 1 is `RXPGuides.RegisterGuide([[`, so `#version` is line 2 and `#next` is line 5.
    let project = build(
        "RXPGuides.RegisterGuide([[\n\
         #version 7\n\
         #group G\n\
         #name N\n\
         #next X\n\
         step\n\
         \x20   .goto 1439,35.743,43.710\n\
         ]])",
    )
    .await;
    let h = &project.guide_headers;

    assert_eq!(h.group.first().map(|g| g.line), Some(3), "got: {:?}", h.group);
    assert_eq!(h.name.first().map(|g| g.line), Some(4), "got: {:?}", h.name);
    assert_eq!(h.next.first().map(|g| g.line), Some(5), "got: {:?}", h.next);
}
