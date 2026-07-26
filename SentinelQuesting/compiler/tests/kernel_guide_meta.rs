//! RED for **item E, `meta`**: the guide-block header must become `kernel::GuideMeta`.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 (`GuideMeta`), §4.2 (the header disposition
//! table), §5.2 (C2 — every gate is decided against one archetype at compile time).
//!
//! `authoring::GuideHeaders` already carries all five directives across the importer boundary, and
//! `importer/tests/guide_headers.rs` pins that arrival. It also states, in its own "what these
//! tests cannot see" list, exactly the gap this file closes: *"Nothing here proves the compiler
//! assembles `kernel::GuideMeta` from these fields"*, and *"They never evaluate a gate … that
//! selection is the compiler's, and picking wrong is invisible here."* Today
//! `Compiler::compile_kernel` writes `group: String::new()`, `subgroup: None`,
//! `source_version: 0`, `next: Vec::new()` unconditionally, so every assertion below fails on the
//! value.
//!
//! # The selection rule these tests pin
//!
//! A header entry is kept iff the artifact's archetype satisfies its `<<` gate — the same
//! `kernel::archetype` resolver every `#requires`, `#label` and command gate goes through, so there
//! is one gate vocabulary and not two. Then:
//!
//! * `name`, `group`, `subgroup` are **single-valued** on the wire, so the FIRST survivor wins.
//!   The corpus's only multi-`#name` block gates its two alternatives `!Warlock` / `Warlock`, which
//!   are mutually exclusive, so "first survivor" and "the only survivor" coincide on every real
//!   input; a block where they do not is a defect the compiler must say out loud rather than
//!   silently pick from.
//! * `next` is a **list** on the wire, so EVERY survivor is kept, in source order. A `;` list and
//!   two separately gated lines are the same authored shape (`A-1-11-Human.lua:2` versus
//!   `A-1-11-Dwarf-Gnome.lua:569`), and keeping only the first would silently truncate the first
//!   spelling while leaving the second intact.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether the values are the RIGHT identity.** They pin that the header reaches `meta`
//!   unmangled and that the gate decided the choice. Nothing here proves that `meta.name` is what
//!   another guide's `#next` will actually resolve against — no cross-guide resolution exists yet,
//!   in this crate or any other, so the whole chaining contract of §4.2 is unexercised.
//! * **Census, not shape.** The cardinalities that motivate every rule above (277 blocks; `#name`
//!   1×276 / 2×1; `#group` 1×277 never gated; `#subgroup` 0×9 / 1×264 / 2×4; `#version` 0×12 /
//!   1×265; `#next` 0×128 / 1×142 / 2×7) are re-derived in no assertion below. A lowering can
//!   satisfy this file and still mishandle a header shape that occurs in the other 276 blocks.
//! * **`#displayname` is asserted absent from `meta`, not *handled*.** §4.2 rules it DROP. These
//!   tests prove it never becomes `name`; they cannot prove some later deliverable will not route
//!   it somewhere else, and they say nothing about the other headers with no typed carrier
//!   (`#defaultfor`, `#xprate`, `#include`, …), which stay dropped.
//! * **One block per fragment.** `parse_guide` stops at the first `]])`, so the multi-block header
//!   shapes are reproduced as synthetic fragments quoting real corpus lines rather than measured in
//!   place.
//! * **Nothing executes.** Whether a runtime that reads `meta.next` chains to the right profile is
//!   ADR 08 behaviour.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race, Severity};
use sentinel_models::kernel::{
    Archetype, Expansion, ProfileMode, QuestId, RuntimeProfile as KernelProfile,
};
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A `QuestMeta` that answers every objective with `1`.
///
/// No fragment below works an objective — these are header tests — but `compile_kernel` takes the
/// provider unconditionally, and a panicking one would turn an unrelated lowering change into a
/// crash in a file that is not about objectives.
struct AnswersOne;

impl QuestMeta for AnswersOne {
    fn objective_need(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        Some(1)
    }

    fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        None
    }
}

fn base() -> Archetype {
    Archetype {
        class: Class::Warrior,
        race: Race::Human,
        faction: Faction::Alliance,
        expansion: Expansion::Tbc,
        allegiance: None,
        hardcore: false,
        self_found: false,
        can_fly: false,
        content_phase: None,
        mode: ProfileMode::SpeedRoute,
        xp_rate_milli: 1_000,
        hardcore_server: false,
        season: None,
    }
}

fn human_warrior() -> Archetype {
    base()
}

fn gnome_warlock() -> Archetype {
    Archetype {
        class: Class::Warlock,
        race: Race::Gnome,
        ..base()
    }
}

async fn import(guide: &str) -> Project {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    sentinel_importer::ProjectBuilder::build(&parsed, "corpus.lua", &MemoryQueryClient::new())
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"))
}

async fn lower(guide: &str, archetype: &Archetype) -> (KernelProfile, CompileReport) {
    let project = import(guide).await;
    Compiler::compile_kernel(&project, archetype, &AnswersOne).unwrap_or_else(|err| {
        panic!("`compile_kernel` must not refuse a well-formed fragment, got: {err:?}")
    })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The whole header of one real block
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:5-15`, verbatim — the header of the block ADR 07 §7.3's worked example is drawn
/// from, and the one place in the repository that states all five values at once:
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
const DARKSHORE_HEADER: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
<< Alliance
#xprate >1.49 << Human Warlock
#name 12-14 Darkshore
#displayname 10-14 Darkshore << Dwarf Hunter
#displayname 11-14 Darkshore << !Human !Mage
#displayname 12-14 Darkshore << Gnome Mage
#subgroup RestedXP Alliance 1-20
#defaultfor Human/NightElf/Dwarf/Gnome !Warlock
#next 14-20 Bloodmyst
step
    .goto 1439,36.634,46.250
]])"#;

#[tokio::test]
async fn the_five_header_directives_of_a_real_block_become_the_artifact_meta() {
    let (profile, _report) = lower(DARKSHORE_HEADER, &human_warrior()).await;

    assert_eq!(profile.meta.name, "12-14 Darkshore", "got: {:?}", profile.meta);
    assert_eq!(
        profile.meta.group, "RestedXP TBC Guide (A)",
        "got: {:?}",
        profile.meta
    );
    assert_eq!(
        profile.meta.subgroup.as_deref(),
        Some("RestedXP Alliance 1-20"),
        "got: {:?}",
        profile.meta
    );
    assert_eq!(profile.meta.source_version, 7, "got: {:?}", profile.meta);
    assert_eq!(
        profile.meta.next,
        vec!["14-20 Bloodmyst".to_string()],
        "got: {:?}",
        profile.meta
    );
}

/// §4.2 rules `#displayname` DROP — "pure UI chrome" — and it cannot stand in for `name`: this one
/// block carries THREE of them, gated and disagreeing, while `#name` is the single identity `#next`
/// and `#include` resolve against.
///
/// The check is over the whole serialized `meta` rather than over `name` alone, because a
/// displayname that leaked into `subgroup` or `next` would be just as wrong and an assertion on
/// `name` would not see it.
#[tokio::test]
async fn no_displayname_reaches_meta_under_any_archetype() {
    for archetype in [human_warrior(), gnome_warlock()] {
        let (profile, _report) = lower(DARKSHORE_HEADER, &archetype).await;
        let serialized = serde_json::to_string(&profile.meta).expect("meta must serialize");

        assert_eq!(
            profile.meta.name, "12-14 Darkshore",
            "`meta.name` is the `#name` identity, never a `#displayname`; got: {:?}",
            profile.meta
        );
        for chrome in ["10-14 Darkshore", "11-14 Darkshore"] {
            assert!(
                !serialized.contains(chrome),
                "`#displayname {chrome}` is a §4.2 DROP row and must reach no `meta` field, \
                 got: {serialized}"
            );
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The gate decides, and it is the archetype's gate
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-1-11-Human.lua:2678` — the corpus's one multi-`#name` block, whose two alternatives are
/// mutually exclusive:
///
/// ```text
/// #name 11-12 Loch Modan << !Warlock
/// #name 12-14 Loch Modan << Warlock
/// ```
///
/// Source order would give every archetype the first line. That is the failure `Gated` exists to
/// prevent, one directive family later.
const GATED_NAMES: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 11-12 Loch Modan << !Warlock
#name 12-14 Loch Modan << Warlock
step
    .goto 1439,35.743,43.710
]])"#;

#[tokio::test]
async fn a_gated_name_is_chosen_by_the_archetype_and_not_by_source_order() {
    let (warrior, _) = lower(GATED_NAMES, &human_warrior()).await;
    let (warlock, _) = lower(GATED_NAMES, &gnome_warlock()).await;

    assert_eq!(
        warrior.meta.name, "11-12 Loch Modan",
        "got: {:?}",
        warrior.meta
    );
    assert_eq!(
        warlock.meta.name, "12-14 Loch Modan",
        "a Warlock artifact must not inherit the `!Warlock` name merely because it is written \
         first; got: {:?}",
        warlock.meta
    );
}

/// `A-1-11-Human.lua:2-3`:
///
/// ```text
/// #next 12-14 Loch Modan;12-14 Darkshore << Warlock
/// #next 11-12 Loch Modan;12-14 Darkshore << !Warlock
/// ```
///
/// `next` is a list on the wire, so every survivor is kept — `;` separates chained successors
/// within one line, and two gated lines are archetype alternatives. Keeping only the first survivor
/// would truncate this spelling while leaving `A-1-11-Dwarf-Gnome.lua:569`'s two-line spelling of
/// the identical shape intact, which is the drift the importer's flattening exists to prevent.
const GATED_NEXT: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 1-11 Elwynn Forest
#next 12-14 Loch Modan;12-14 Darkshore << Warlock
#next 11-12 Loch Modan;12-14 Darkshore << !Warlock
step
    .goto 1439,35.743,43.710
]])"#;

#[tokio::test]
async fn every_next_the_archetype_satisfies_survives_and_not_only_the_first() {
    let (warrior, _) = lower(GATED_NEXT, &human_warrior()).await;
    let (warlock, _) = lower(GATED_NEXT, &gnome_warlock()).await;

    assert_eq!(
        warlock.meta.next,
        vec![
            "12-14 Loch Modan".to_string(),
            "12-14 Darkshore".to_string()
        ],
        "got: {:?}",
        warlock.meta
    );
    assert_eq!(
        warrior.meta.next,
        vec![
            "11-12 Loch Modan".to_string(),
            "12-14 Darkshore".to_string()
        ],
        "got: {:?}",
        warrior.meta
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Absence
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `#version` is absent from 12 of the 277 blocks and `#subgroup` from 9, and neither absence is an
/// error: §6.5 makes the guide-pack revision the one version axis whose mismatch is a *warning*.
///
/// `subgroup` is `Option` and stays `None`; `source_version` is a required `u32` and reports `0` —
/// "this block declared no revision" — rather than a plausible `1`, which would compare equal to a
/// real revision 1 and silence the very warning §6.5 asks for.
#[tokio::test]
async fn a_block_that_declares_no_version_or_subgroup_invents_neither() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.634,46.250
]])"#,
        &human_warrior(),
    )
    .await;

    assert_eq!(profile.meta.source_version, 0, "got: {:?}", profile.meta);
    assert_eq!(profile.meta.subgroup, None, "got: {:?}", profile.meta);
    assert!(profile.meta.next.is_empty(), "got: {:?}", profile.meta);
}

/// A block whose every `#name` is gated out for this archetype still has to be named — `GuideMeta`
/// has no `Option` there, an artifact is written per archetype, and an empty name is a profile
/// nothing can chain to.
///
/// The fallback is the project's own name, which the importer derived from the same header, and it
/// is announced: a name chosen by a rule the author did not write is exactly the kind of quiet
/// substitution the rest of this lowering refuses, so it is a diagnostic rather than a silent pick.
#[tokio::test]
async fn a_name_no_archetype_survivor_supplies_falls_back_and_says_so() {
    let (profile, report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore << Warlock
step
    .goto 1439,36.634,46.250
]])"#,
        &human_warrior(),
    )
    .await;

    assert!(
        !profile.meta.name.is_empty(),
        "an artifact with no name cannot be chained to; got: {:?}",
        profile.meta
    );
    assert!(
        report.unmapped_conditions.iter().any(|diagnostic| {
            diagnostic.severity == Severity::Warning && diagnostic.code == "GUIDE_NAME_UNGATED_FALLBACK"
        }),
        "the fallback must be announced, got: {:?}",
        report
            .unmapped_conditions
            .iter()
            .map(|d| (d.severity, d.code.as_str()))
            .collect::<Vec<_>>()
    );
}
