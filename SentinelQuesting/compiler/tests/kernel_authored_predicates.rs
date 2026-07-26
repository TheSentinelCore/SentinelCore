//! RED for the two **authored** predicates the lowering was throwing away: `.xp` and `.subzone`.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.1.1 (`Predicate::XpAtLeast`, `Predicate::InArea`),
//! §7.1 (`Task::complete_when`), and §7.3.3's worked example, whose fixture
//! `shared/tests/fixtures/adr07_worked_example.json` states both values for a real guide. Corpus:
//! `sentinel/docs/adr/restedxp guides` — a vendored, never-edited tree, so line citations into it
//! are stable (`tools/check_citation_anchors.py` exempts exactly that path).
//!
//! Unlike `kernel_task_predicates.rs`, whose two predicates are *derived* because no command
//! authors them, every predicate below is **written down by the guide author** and was being lost
//! between the lexer and the artifact. Each test therefore starts at the guide line, not at the §23
//! DSL string: the whole defect for `.xp` lived in the importer's DSL emission, so a test that
//! began at the DSL would have been green throughout.
//!
//! # A — `.xp`, and the offset it was dropping
//!
//! `.xp` has one grammar with a signed offset, and the author documents it in his own display text:
//!
//! * `.xp 10+6760 >> Grind to 6760+/7600xp` (`A-11-23.lua:271`) — 7,600 is level 10's XP
//!   requirement, so `+6760` is *6,760 XP into level 10*.
//! * `.xp 4-420 >>Grind until you are 420xp away from level 4 (980/1400)`
//!   (`A-1-11-Draenei.lua:141`) — 1,400 is the requirement and 1,400 − 420 = 980, the bar the note
//!   prints. So `-420` is *420 XP short of level 4*.
//!
//! Both are one predicate: `total_xp >= start_of_level(level) + xp_offset`, which is why §5.1.1
//! types `xp_offset` as `i32` and calls it "signed". The bare `.xp N` form is the same statement
//! with a zero offset, and `LevelAtLeast { level: N }` is exactly that — see
//! `a_bare_xp_level_stays_a_level_floor` for why it is deliberately left alone.
//!
//! The bug was arithmetic, not cosmetic. `xp_level_dsl` split on `+`, kept the level and discarded
//! the tail, so `A-11-23.lua:271` compiled to `LevelAtLeast { level: 10 }` — a grind task that
//! stops **6,760 XP early**, 89% of the way short of what the author asked for.
//!
//! # B — `.subzone`, and the id space it must not be read in
//!
//! `.subzone 442 >> Travel to Auberdine` (`A-11-23.lua:275`) lowers to
//! `InArea { area: 442, kind: SubArea }`. `442` is an **AreaTable id** — `AreaTable.dbc` record 442
//! is `Auberdine`, parent area 148 (`Darkshore`), map 1 — and it must never be resolved through
//! `sentinel_models::zone::zone_map_for`, whose keys are Classic **UiMapIDs** recovered from
//! `WorldMapArea.dbc`. The two numeric spaces overlap, so the mistake does not announce itself;
//! `a_subzone_id_that_is_also_a_ui_map_id_is_not_translated` pins a corpus id where it would land on
//! the wrong continent.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether `AreaTable.dbc` says what this file says it says.** The area names and parents quoted
//!   above were read out of `Emulators/Mangos - Classic TBC/extracted/dbc/AreaTable.dbc` (1,643
//!   records, `AreaTableEntryfmt`), which is not a build input and which nothing here opens. The
//!   assertions pin that the authored number survives *unchanged*; that 442 is Auberdine is context,
//!   not a checked fact.
//! * **Whether the runtime evaluates `XpAtLeast` against the right XP table.** `start_of_level` is a
//!   runtime concept. Nothing here executes.
//! * **The 2,025 `.xp` skip variants.** `<N,1` (1,416) and `>N,1` (603), plus 4 offset-bearing and 2
//!   decimal spellings, are RestedXP *skip-step* forms with different semantics — they stay inert,
//!   and `an_xp_skip_variant_stays_inert` pins that they were not swept in by the new parser.
//! * **`.zone`.** Its `AreaKind` is `Zone` and that mapping is stated in the model, but no corpus
//!   line supplies an argument the compiler could put in `InArea::area` — see
//!   `a_zone_command_is_not_lowered_because_the_corpus_never_gives_it_an_area_id`.
//! * **`.subzoneskip` / `.zoneskip`.** 2,852 uses whose trailing `,1` negates; out of scope here.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::Compiler;
use sentinel_models::authoring::{Class, Faction, Project, Race};
use sentinel_models::kernel::{
    AreaKind, Archetype, Expansion, Predicate, ProfileMode, QuestId, RuntimeProfile as KernelProfile,
};
use sentinel_models::zone::zone_map_for;
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A provider that answers every objective with `1` and no item. None of the fragments below
/// authors a `.complete`, so nothing consults it; it exists so a wrong predicate cannot become a
/// panic that hides which assertion failed.
struct AnswersOne;

impl QuestMeta for AnswersOne {
    fn objective_need(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        Some(1)
    }

    fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        None
    }
}

fn night_elf_hunter() -> Archetype {
    Archetype {
        class: Class::Hunter,
        race: Race::NightElf,
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

async fn import(guide: &str) -> Project {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    sentinel_importer::ProjectBuilder::build(&parsed, "corpus.lua", &MemoryQueryClient::new())
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"))
}

async fn lower(guide: &str) -> KernelProfile {
    let project = import(guide).await;
    Compiler::compile_kernel(&project, &night_elf_hunter(), &AnswersOne)
        .unwrap_or_else(|err| {
            panic!("`compile_kernel` must not refuse a well-formed fragment, got: {err:?}")
        })
        .0
}

/// One `step` carrying `commands`, under the smallest header `parse_guide` accepts.
fn fragment(commands: &str) -> String {
    format!(
        "\nRXPGuides.RegisterGuide([[\n#version 7\n#group RestedXP TBC Guide (A)\n#name 12-14 \
         Darkshore\nstep\n{commands}\n]])"
    )
}

/// The single task's `complete_when`, or a message naming what the compile actually produced.
async fn complete_when(commands: &str) -> Option<Predicate> {
    let profile = lower(&fragment(commands)).await;
    assert_eq!(
        profile.tasks.len(),
        1,
        "the fragment authors one step and must lower to one task, got: {:?}",
        profile.tasks
    );
    profile.tasks[0].complete_when.clone()
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A — `.xp`
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:271` — `.xp 10+6760 >> Grind to 6760+/7600xp`, §7.3.3 task 4's completion.
///
/// The offset is the entire content of the line: without it the task says "reach level 10", which
/// the player already is by the time the step is reached, and the grind never happens. `+6760` of
/// 7,600 is 89% of the level.
#[tokio::test]
async fn an_xp_gate_keeps_the_offset_the_author_wrote() {
    assert_eq!(
        complete_when("    .xp 10+6760 >> Grind to 6760+/7600xp").await,
        Some(Predicate::XpAtLeast { level: 10, xp_offset: 6760 }),
        "the `+6760` on A-11-23.lua:271 must reach the artifact; a `LevelAtLeast {{ level: 10 }}` \
         here is the dropped-offset bug, and it completes the grind 6,760 XP early"
    );
}

/// `A-1-11-Draenei.lua:141` — `.xp 4-420 >>Grind until you are 420xp away from level 4 (980/1400)`.
///
/// The mirror form, and the reason §5.1.1 types the offset signed rather than as a count. The
/// author's own note does the arithmetic: 1,400 − 420 = 980. 26 corpus lines use it and every one
/// was inert before this, because the old parser split on `+` and `"4-420"` is not a `u8`.
#[tokio::test]
async fn an_xp_gate_authored_as_a_deficit_lowers_to_a_negative_offset() {
    assert_eq!(
        complete_when("    .xp 4-420 >>Grind until you are 420xp away from level 4 (980/1400)")
            .await,
        Some(Predicate::XpAtLeast { level: 4, xp_offset: -420 }),
        "`N-M` is `M` XP *short of* level `N`; dropping the sign would turn a deficit into a \
         surplus and overshoot by 840 XP"
    );
}

/// `A-11-23.lua:322` — `.xp 12`, the 52 bare-level uses.
///
/// Deliberately still `LevelAtLeast`. `XpAtLeast { level: 12, xp_offset: 0 }` states the identical
/// fact, so this is not a fidelity question — it is a scope one: `LevelAtLeast` is independently
/// justified by `#level` (§5.2), the ADR-05 model can express it exactly, and the corpus authors no
/// `.xp N+0`, so the two spellings never collide on one input. Changing it is a separate decision
/// with its own blast radius, and this test is here so that decision has to be made on purpose.
#[tokio::test]
async fn a_bare_xp_level_stays_a_level_floor() {
    assert_eq!(
        complete_when("    .xp 12").await,
        Some(Predicate::LevelAtLeast { level: 12 }),
        "the offset-free form is unchanged; `LevelAtLeast {{ level: 12 }}` and \
         `XpAtLeast {{ level: 12, xp_offset: 0 }}` are the same statement"
    );
}

/// `A-1-11-Human.lua:998` — `.xp <8,1`, one of 2,025 skip-step uses.
///
/// The comparison forms are not completion gates: RestedXP reads them as "skip this step if the
/// player is already past this", the trailing `,1` being the skip flag. Lowering them as thresholds
/// would invert 1,416 `<N,1` steps into wait-forever gates. They stay inert until their skip
/// semantics are lowered on purpose, and this pins that the new signed parser did not quietly
/// acquire them by accepting `<` or a second argument.
#[tokio::test]
async fn an_xp_skip_variant_stays_inert() {
    assert_eq!(
        complete_when("    .xp <8,1").await,
        None,
        "`<N,1` is a skip-step form, not a threshold; it must produce no completion predicate"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — `.subzone`
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:275` — `.subzone 442 >> Travel to Auberdine`, §7.3.3 task 5's completion.
///
/// A **set** test, not a distance test: the step is done when the player is in the sub-area, and
/// `InArea` is what §5.1.1 added for it. `AreaKind::SubArea` comes from the *command that was
/// written*, not from `AreaTable`'s parent column — see the next test but one.
#[tokio::test]
async fn a_subzone_lowers_to_an_in_area_sub_area_predicate() {
    assert_eq!(
        complete_when("    .subzone 442 >> Travel to Auberdine").await,
        Some(Predicate::InArea { area: 442, kind: AreaKind::SubArea }),
        "A-11-23.lua:275 is the fixture's task 5 `complete_when`; a `None` here is the missing \
         lowering, and it also collapses that task's `terminate_on`"
    );
}

/// `The Burning Crusade.lua:21535` — `.subzone 1443 >> Drop down the hole into the Slag Pit`.
///
/// The trap this pins is silent. `1443` is an `AreaTable` id — record 1443 is `The Slag Pit`, map 0,
/// parent 51 (`Searing Gorge`) — **and** it is a live key in `ZONE_TABLE`, where 1443 is the UiMapID
/// for `Desolace` on map 1. Reading the payload in the wrong space therefore yields a well-formed
/// answer on the wrong continent, and the assertion that the number is *unchanged* is the only
/// thing that can tell the two apart. `zone_map_for` is called here purely to prove the collision is
/// real rather than hypothetical; nothing in the lowering may call it with this argument.
#[tokio::test]
async fn a_subzone_id_that_is_also_a_ui_map_id_is_not_translated() {
    let collision = zone_map_for("1443")
        .expect("1443 must still be a ZONE_TABLE key, or this test no longer pins anything");
    assert_eq!(
        collision.continent, 1,
        "ZONE_TABLE's 1443 is Desolace on Kalimdor while AreaTable's 1443 is in Searing Gorge on \
         map 0 — that mismatch is what makes the confusion detectable"
    );

    assert_eq!(
        complete_when("    .subzone 1443 >> Drop down the hole into the Slag Pit").await,
        Some(Predicate::InArea { area: 1443, kind: AreaKind::SubArea }),
        "the authored AreaTable id must land in `InArea::area` byte for byte; anything derived \
         from `zone_map_for` has read it as a UiMapID"
    );
}

/// `A-11-23.lua:2900` — `.subzone 1581,2 >> Enter The Deadmines Dungeon`, one of 79 two-argument
/// uses.
///
/// The second argument is `2` on all 79 (and `1`, the negation, on the 691 `*skip` uses). Nothing in
/// the corpus says what `2` means — every instance sits on an instance-portal step — so the form is
/// refused rather than guessed at. Lowering it as if the `2` were absent would silently widen 79
/// gates.
#[tokio::test]
async fn a_two_argument_subzone_is_refused_rather_than_guessed_at() {
    assert_eq!(
        complete_when("    .subzone 1581,2 >> Enter The Deadmines Dungeon").await,
        None,
        "the meaning of the `,2` flag is not derivable from the corpus; the 1-argument form is the \
         only one lowered"
    );
}

/// `The Burning Crusade.lua:1817` — `.zone 1415 >> Travel to Uldaman`.
///
/// `AreaKind::Zone` exists and `.zone` is what produces it — but no corpus line hands the compiler
/// an id it could put in `InArea::area`. Measured over the whole tree: 1,037 of 1,063 `.zone` uses
/// name a zone in *words* (`.zone Redridge Mountains`), and 25 of the remaining 26 are UiMapIDs that
/// `AreaTable.dbc` does not contain at all — `1415` is `Azeroth`/`Eastern Kingdoms` in `ZONE_TABLE`
/// and is absent from `AreaTable`. The single exception, `.zone 721,2`, is the two-argument form
/// refused above.
///
/// So emitting `InArea { area: 1415 }` would put a UiMapID in an AreaTable field — the same
/// wrong-id-space error as the previous test, made deliberately. `.zone` needs a name→AreaTable
/// resolution it does not have yet; until then it stays inert, and this test states that as a
/// decision rather than leaving it as an omission.
#[tokio::test]
async fn a_zone_command_is_not_lowered_because_the_corpus_never_gives_it_an_area_id() {
    assert!(
        zone_map_for("1415").is_some(),
        "1415 is a UiMapID, which is precisely why it must not be read as an AreaTable id"
    );
    assert_eq!(
        complete_when("    .zone 1415 >> Travel to Uldaman").await,
        None,
        "no `.zone` line in the corpus supplies a bare AreaTable id; lowering one anyway would \
         inject a UiMapID into `InArea::area`"
    );
}
