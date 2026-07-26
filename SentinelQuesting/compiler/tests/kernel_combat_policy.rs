//! RED for **item F, C6**: the per-task combat policy — `.mob` and `.unitscan` into
//! `CombatPolicy`, and a stance chosen from what the step is actually doing.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.6 (C6, the corpus mapping table), §7.1
//! (`CombatPolicy`, `Task::combat`, `ProfileDefaults`), §5.8 / §5.4.1 (`NpcRef::expect_name` and
//! the first-touch probe), and §7.3.3's worked example — whose fixture
//! `shared/tests/fixtures/adr07_worked_example.json` is the only place in the repository that
//! states three lowered policies side by side.
//!
//! Today `Compiler::compile_kernel` writes `combat: None` on every task and a profile default of
//! `leash_yards: 0, allow_adds: false`, so every assertion below fails on the value.
//!
//! # The rule, derived from the three witnesses rather than from them
//!
//! §5.6's table maps four corpus signals. The fixture's three policies fix what the table leaves
//! open, and the rule that produces all three — and produces `None` for the other four tasks — is:
//!
//! ```text
//! targets      = every creature the step's combat commands name (.mob ∪ .unitscan), first seen
//! watch_units  = the .unitscan subset of those
//! stance       = Aggressive, when the task's completion cannot advance without killing:
//!                  (a) the completion is an experience threshold  (the `.xp` grind step), or
//!                  (b) #loop + .mob + .complete                   (§5.6's 1,661-use row)
//!                Objective,  when the step names any combat target (§5.6's 7,456-use row)
//!                otherwise the profile default
//! leash_yards  = the largest arrival radius the task's own routes authored, on a #loop circuit
//!                (§5.6: "leash from route radius"); otherwise the profile default
//! allow_adds   = Aggressive => true (a grind circuit wants pulls); Objective => false (§5.6:
//!                "kills only what blocks the objective and refuses adds"); else the default
//! expect_group = the profile default
//! ```
//!
//! and the policy is **emitted only when it differs from the profile default**, which is §5.6's own
//! scope decision: 16,438 of 23,894 tasks carry no combat token, and a per-task copy of the default
//! on two-thirds of tasks is exactly the redundancy the default exists to remove.
//!
//! Two consequences are worth naming because they look like special cases and are not. `.unitscan`
//! feeds `targets` as well as `watch_units`: §7.3.3 task 2 carries **no** `.mob` at all, and the
//! fixture still gives it `stance: Objective` with `2164` in the whitelist — a unit worth noticing
//! is a unit this task fights. And the `.xp` grind step (task 4) carries no combat command
//! whatsoever, yet is `Aggressive`: nothing else can satisfy `Grind to 6760+/7600xp`.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether the stance is right for the game.** That a `#loop` farm should pull proactively and
//!   an objective step should refuse adds are claims about play, not about lowering. Nothing here
//!   executes; C6's whole point is that the *combat service* decides how to fight, and none of it
//!   is in this repository's Rust.
//! * **The two default magnitudes are illustrative, and these tests pin them anyway.** ADR 07 §9
//!   item 25 says so in as many words: `leash_yards: 40` "appears only inside §7.3.3's listing …
//!   treat the printed values as illustrative". Pinning an illustrative constant is the honest
//!   thing to do — the artifact has to carry *some* number and the fixture is the specification —
//!   but a later deliberate choice will change these tests, and that is not a regression.
//! * **`expect_group` is never anything but `Solo` here.** `.solo` (13), `.group [n]` (190) and
//!   `.dungeon` (1,351) are §5.6's other three rows and none of them reaches the compiler yet, so
//!   the party axis is untested for every value that is not the default.
//! * **Census, not shape.** 7,456 `.mob` lines, 735 `.unitscan`, 1,661 `#loop`+`.mob`+`.complete`
//!   steps: no assertion below re-derives any of them, and the fragments are synthetic.
//! * **The leash reduction is `max`, and only a circuit exercises it.** A circuit whose radii are
//!   all zero, or one wide outlier among narrow points, would take a leash these tests never look
//!   at.
//! * **A name the world database does not have.** `expect_name` exists for §5.4.1's first-touch
//!   probe, and these tests supply a database that always answers. What a `.mob` naming a creature
//!   the database has never heard of should do is asserted only as "contributes no target".

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race};
use sentinel_models::kernel::{
    Archetype, CombatPolicy, CombatStance, Expansion, GroupExpectation, NpcRef, ProfileMode,
    QuestId, RuntimeProfile as KernelProfile,
};
use sentinel_query_types::NpcDetail;
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

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

/// The three Darkshore creatures §7.3.2 verified against `tbcmangos.sqlite`, and nothing else.
///
/// Entry and name both come from `creature_template`: 2231 `Pygmy Tide Crawler`, 2234
/// `Young Reef Crawler` (§7.3.3 task 0's two `.mob` lines, `A-11-23.lua:235-236`) and 2164
/// `Rabid Thistle Bear` (task 2's `.unitscan`, `:259`). A `.mob` resolves through
/// `QueryClient::search_npcs`, so a client that knows nothing produces an empty whitelist and the
/// policy under test would be vacuous.
fn darkshore() -> MemoryQueryClient {
    let creature = |entry: u32, name: &str| NpcDetail {
        entry,
        name: name.to_string(),
        faction: "Beast".to_string(),
        positions: Vec::new(),
        roles: Vec::new(),
    };
    MemoryQueryClient::new()
        .with_npc(creature(2231, "Pygmy Tide Crawler"))
        .with_npc(creature(2234, "Young Reef Crawler"))
        .with_npc(creature(2164, "Rabid Thistle Bear"))
}

async fn lower(guide: &str) -> (KernelProfile, CompileReport) {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    let project: Project = sentinel_importer::ProjectBuilder::build(&parsed, "corpus.lua", &darkshore())
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"));
    Compiler::compile_kernel(&project, &night_elf_hunter(), &AnswersOne).unwrap_or_else(|err| {
        panic!("`compile_kernel` must not refuse a well-formed fragment, got: {err:?}")
    })
}

fn npc(entry: u32, name: &str) -> NpcRef {
    NpcRef {
        entry,
        expect_name: name.to_string(),
        // §7.3.3 prints `pos: null` for all three: nothing in the corpus says where a `.mob` stands,
        // and the route the task walks is not the creature's spawn point.
        pos: None,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The three fixture policies
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:211-237`, reduced to its combat-bearing lines — §7.3.3 task 0.
///
/// `#loop` + two `.mob` + a `.complete` objective is §5.6's 1,661-use Aggressive row, and the leash
/// is the circuit's own radius: the three entry `.goto` lines carry `0` and the fourteen
/// `.waypoint` lines carry `60`.
#[tokio::test]
async fn a_loop_farm_with_a_kill_whitelist_pulls_proactively_and_leashes_to_its_circuit() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    #sticky
    #loop
    .goto 1439,36.051,44.757,0
    .waypoint 1439,36.091,51.501,60,0
    .waypoint 1439,36.051,44.757,60,0
    .complete 983,1
    .mob Pygmy Tide Crawler
    .mob Young Reef Crawler
    .isOnQuest 983
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].combat,
        Some(CombatPolicy {
            stance: CombatStance::Aggressive,
            targets: vec![
                npc(2231, "Pygmy Tide Crawler"),
                npc(2234, "Young Reef Crawler")
            ],
            watch_units: Vec::new(),
            leash_yards: 60,
            allow_adds: true,
            expect_group: GroupExpectation::Solo,
        }),
        "got: {:?}",
        profile.tasks[0].combat
    );
}

/// `A-11-23.lua:243-260` — §7.3.3 task 2, which carries **no** `.mob` at all.
///
/// Its one combat command is `.unitscan Rabid Thistle Bear` (`:259`), and the fixture puts 2164 in
/// `targets` *and* in `watch_units`: a roamer worth noticing is a unit this task fights. The stance
/// is `Objective` and not `Aggressive` because §5.6's grind row wants a `.mob` whitelist — this
/// step is trapping one specific bear with `.use 7586`, not farming respawns — and `allow_adds` is
/// therefore `false`.
#[tokio::test]
async fn a_unitscan_names_a_unit_to_notice_and_a_unit_to_fight() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    #sticky
    #loop
    .goto 1439,38.226,52.780,0
    .goto 1439,38.527,54.661,50,0
    .complete 2118,1
    .unitscan Rabid Thistle Bear
    .use 7586
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].combat,
        Some(CombatPolicy {
            stance: CombatStance::Objective,
            targets: vec![npc(2164, "Rabid Thistle Bear")],
            watch_units: vec![npc(2164, "Rabid Thistle Bear")],
            leash_yards: 50,
            allow_adds: false,
            expect_group: GroupExpectation::Solo,
        }),
        "got: {:?}",
        profile.tasks[0].combat
    );
}

/// `A-11-23.lua:269-271` — §7.3.3 task 4, `.xp 10+6760 >> Grind to 6760+/7600xp`.
///
/// No combat command, no `#loop`, no route, and the fixture still makes it `Aggressive`. Nothing
/// else can satisfy an experience threshold: the task's whole content is killing, so the stance is
/// read off the completion rather than off a whitelist that is not there. The leash and
/// `allow_adds` fall back to the profile default, which is what makes the emitted policy differ
/// from the default in exactly one field.
#[tokio::test]
async fn an_experience_threshold_completion_is_a_grind_and_pulls() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
#optional
    .xp 10+6760
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].combat,
        Some(CombatPolicy {
            stance: CombatStance::Aggressive,
            targets: Vec::new(),
            watch_units: Vec::new(),
            leash_yards: 40,
            allow_adds: true,
            expect_group: GroupExpectation::Solo,
        }),
        "got: {:?}",
        profile.tasks[0].combat
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The four tasks that carry nothing, and why that is the point
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// §7.3.3 tasks 1, 3, 5 and 6 carry `combat: null`, and §5.6's scope decision is the reason: 16,438
/// of 23,894 corpus tasks name no combat at all, so a per-task copy of the profile default on
/// two-thirds of the artifact is precisely the redundancy the default exists to remove.
#[tokio::test]
async fn a_task_that_names_no_combat_and_grinds_nothing_carries_no_policy() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.371,50.920
    .complete 3524,1
]])"#,
    )
    .await;

    assert_eq!(profile.tasks[0].combat, None, "got: {:?}", profile.tasks[0]);
}

/// §5.6 takes the leash "from route radius" on a **grind circuit**, and a `Destination` radius is
/// not one. `.goto 1439,36.371,50.920` authors no radius at all and the importer gives it the
/// 5-yard arrival default; a leash of five yards would make an objective step refuse to fight
/// anything it is standing next to.
///
/// The step below names a `.mob`, so it does carry a policy — this test is about which number the
/// leash takes, not about whether one is emitted.
#[tokio::test]
async fn a_destination_arrival_radius_is_not_a_leash() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.371,50.920
    .complete 983,1
    .mob Pygmy Tide Crawler
]])"#,
    )
    .await;

    let policy = profile.tasks[0]
        .combat
        .as_ref()
        .unwrap_or_else(|| panic!("a `.mob` step carries a policy, got: {:?}", profile.tasks[0]));
    assert_eq!(policy.stance, CombatStance::Objective, "got: {policy:?}");
    assert_eq!(
        policy.leash_yards, 40,
        "the 5-yard arrival radius of a `Destination` is not a leash; got: {policy:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// `expect_name` is the database's spelling, not the author's
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// §5.4.1: the first-touch probe compares the observed unit name against `expect_name` and fails
/// the task on mismatch. So the name has to be the one `creature_template` holds — the author's
/// spelling is what the *lookup* used, and carrying it forward would fail every probe on a
/// case-different or abbreviated `.mob`.
#[tokio::test]
async fn expect_name_carries_the_world_database_spelling_and_not_the_authored_one() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .mob pygmy tide crawler
]])"#,
    )
    .await;

    let policy = profile.tasks[0]
        .combat
        .as_ref()
        .unwrap_or_else(|| panic!("a `.mob` step carries a policy, got: {:?}", profile.tasks[0]));
    assert_eq!(
        policy.targets,
        vec![npc(2231, "Pygmy Tide Crawler")],
        "got: {policy:?}"
    );
}

/// A `.mob` the world database cannot resolve contributes no target — never an entry with an empty
/// name, which would be a first-touch probe that fails on every unit it ever sees.
#[tokio::test]
async fn an_unresolvable_mob_contributes_no_target() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .mob Nonexistent Abomination
]])"#,
    )
    .await;

    let targets = profile.tasks[0]
        .combat
        .as_ref()
        .map(|policy| policy.targets.clone())
        .unwrap_or_default();
    assert!(targets.is_empty(), "got: {targets:?}");
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The profile default every override is measured against
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// §7.3.3's `defaults.combat`, which is what `Task::combat: None` resolves to at runtime.
///
/// `stance: Defensive` is §5.6's own default row. The two magnitudes are **not** derived: ADR 07 §9
/// item 25 records that `leash_yards: 40` "appears only inside §7.3.3's listing" and asks for it to
/// be chosen deliberately later. It is pinned here because the artifact must carry a number and the
/// fixture is the specification, not because 40 has an argument behind it.
#[tokio::test]
async fn the_profile_default_is_defensive_with_the_worked_examples_magnitudes() {
    let (profile, _report) = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.371,50.920
]])"#,
    )
    .await;

    assert_eq!(
        profile.defaults.combat,
        CombatPolicy {
            stance: CombatStance::Defensive,
            targets: Vec::new(),
            watch_units: Vec::new(),
            leash_yards: 40,
            allow_adds: true,
            expect_group: GroupExpectation::Solo,
        },
        "got: {:?}",
        profile.defaults
    );
}
