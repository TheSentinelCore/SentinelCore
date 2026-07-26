//! Route aggregation: a consecutive run of movement lines becomes **one** [`Op::Travel`] carrying
//! the whole route (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.7, §7.1, §7.3.3).
//!
//! # Why one op and not one per line
//!
//! §5.7's decisive witness is `A-11-23.lua:215-231`: three `.goto` lines walking in, then fourteen
//! `.waypoint` lines whose last is byte-identical to the first `.goto`. That is a closed patrol
//! circuit, and the *route is the objective* — "a navmesh asked to path from A to A returns a
//! zero-length path; it cannot know the intent is to walk a 15-node loop repeatedly to farm
//! respawns". Seventeen separate `Destination` ops say the opposite of that: each one invites the
//! engine to smooth its own single hop, and nothing in the artifact records that they are one walk.
//! §7.3.3 prints the step as one `Travel` with 17 points, and
//! [`ResumeCursor`](sentinel_models::kernel::ResumeCursor) is built on the same assumption — its
//! `waypoint` field exists because "one `Op::Travel` carries the whole route".
//!
//! # What breaks a run, measured
//!
//! **An op breaks a run. A command that is not an op does not.** Measured over the whole corpus
//! (23,894 steps in 277 blocks):
//!
//! * 3,689 steps hold a run of two or more movement lines.
//! * 691 steps hold movement lines in **more than one** authored run.
//! * Of those 691, **151** are separated only by commands that are not operations — `.complete`,
//!   `.collect`, `.itemcount` and `.isOnQuest` (task predicates), `.mob` and `.unitscan` (the
//!   combat whitelist), `.target` (the step-wide interact target), `.money`, `.itemStat`. Splitting
//!   on those would fabricate **293** extra routes for walks the author wrote as one.
//!   `A-1-11-Draenei.lua:4203` is the shape: `.complete`, nine `.goto`s, `.complete`, one more
//!   `.goto` — ten coordinates of one walk, with a completion predicate written in the middle of
//!   it.
//! * The other 540 are separated by real operations — `.accept` (620 occurrences between runs),
//!   `.turnin` (568), `.train` (25), `.vendor` (17), `.use` (3). `A-1-11-Draenei.lua:83` is the
//!   shape: `.goto`, `.accept`, `.goto` — walk to one quest giver, take the quest, walk to the
//!   next. Merging across that would hand the engine one route and drop the accept out of its
//!   place in the order.
//!
//! So the boundary is drawn on the **authored action kind**, not on whether this deliverable can
//! lower it yet: `.turnin` has no kernel op today, and a boundary drawn on emitted ops would merge
//! the two halves of all 568 turn-in-separated steps until the day `TurnIn` lands, then silently
//! split them again.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether a coordinate is right.** Every fixture below is compared by pool index and route
//!   length. `shared/tests/zone_table.rs` owns the transform's accuracy against real spawns.
//! * **`.groundgoto` / `.flygoto`.** `ProjectBuilder` does not lower them to a travel action at all,
//!   so no route this compiler builds can be `Ground` or `Air` yet, and the 27 corpus steps that
//!   mix travel media inside one step are unreachable from here. Refusal of a mixed-medium route
//!   lives in `kernel::lower_route` and is pinned by `kernel_lowering.rs`.
//! * **The runtime.** Whether the engine actually walks a `Circuit` repeatedly, or honours a
//!   0-yard arrival radius, is ADR 08 behaviour. Nothing here executes.
//! * **Route-level collapse (§2.6).** A single step emitting the same coordinate twice — once
//!   4-argument, once 5-argument — still emits both points. That collapse is a separate
//!   deliverable and `a_route_that_recrosses_a_point_repeats_the_index` below deliberately pins the
//!   un-collapsed length.

use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race};
use sentinel_models::kernel::{
    Archetype, Expansion, Op, ProfileMode, QuestId, Route, RouteKind, RuntimeProfile as KernelProfile,
    TravelMode,
};
use sentinel_compiler::kernel::QuestMeta;
use sentinel_queryclient::{MemoryQueryClient, QuestDetail};

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Answers every objective with `1`. These tests drive routes, not objective counts; a provider
/// that refused would turn a route failure into a panic about a quest.
struct AnswersOne;

impl QuestMeta for AnswersOne {
    fn objective_need(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        Some(1)
    }

    /// No fragment here works an item objective, so no task needs a loot rule. `None` is "not an
    /// item", never "could not answer" — see the trait's own doc comment.
    fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        None
    }
}

/// The Night Elf Hunter of §7.3.3, spelled out in full: every field is a gate axis and a defaulted
/// one is a gate nobody chose.
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

/// The world the importer resolves against.
///
/// Quest 983 (`Buzzbox 827`, §7.3.2) is present because `ProjectBuilder` lowers `.accept` to an
/// `AcceptQuest` action **only** when the quest resolves, and to an inert comment otherwise. A
/// comment is not an op, so an empty client would quietly turn the one test that needs an op
/// between two walks into a test of two walks with nothing between them.
fn world() -> MemoryQueryClient {
    MemoryQueryClient::new().with_quest(QuestDetail {
        id: 983,
        title: "Buzzbox 827".to_string(),
        level: 12,
        min_level: 10,
        required_quests: vec![],
        next_quests: vec![],
        giver_entry: None,
        finisher_entry: None,
        objectives: vec![],
        structured_objectives: vec![],
    })
}

async fn import(guide: &str) -> Project {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    sentinel_importer::ProjectBuilder::build(&parsed, "A-11-23.lua", &world())
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"))
}

async fn lower(guide: &str) -> (KernelProfile, CompileReport) {
    let project = import(guide).await;
    Compiler::compile_kernel(&project, &night_elf_hunter(), &AnswersOne)
        .unwrap_or_else(|err| panic!("`compile_kernel` must not refuse the fragment, got: {err:?}"))
}

/// The routes of task `index`, in op order — so an assertion reads as a property of the task's
/// route list and never as an index into `ops`.
fn routes(profile: &KernelProfile, index: usize) -> Vec<&Route> {
    let Some(task) = profile.tasks.get(index) else {
        panic!(
            "the fragment authors a task {index}, got {} tasks: {:?}",
            profile.tasks.len(),
            profile.tasks
        )
    };
    task.ops
        .iter()
        .filter_map(|op| match op {
            Op::Travel { route } => Some(route),
            _ => None,
        })
        .collect()
}

/// The single route of task `index`, or a panic naming what was found instead.
fn only_route(profile: &KernelProfile, index: usize) -> &Route {
    let routes = routes(profile, index);
    let [route] = routes.as_slice() else {
        panic!(
            "task {index} must carry exactly one `Op::Travel`, got {} of them: {routes:?}",
            routes.len()
        )
    };
    route
}

/// The wire tag of each op, so a test can state the op *order* without matching on payloads.
fn op_tags(profile: &KernelProfile, index: usize) -> Vec<String> {
    let Some(task) = profile.tasks.get(index) else {
        panic!("the fragment authors a task {index}, got {} tasks", profile.tasks.len())
    };
    task.ops
        .iter()
        .map(|op| {
            serde_json::to_value(op)
                .expect("an op serialises")
                .get("type")
                .and_then(serde_json::Value::as_str)
                .expect("ADR 07 §5.4 (C4): every op is adjacently tagged with `type`")
                .to_owned()
        })
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Fixtures — real corpus lines, at their real shapes
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:211-237`, verbatim: the `#sticky #loop` circuit §5.7 argues from.
const CIRCUIT: &str = "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    #sticky
    #label BuzzBox1
    #loop
    .goto 1439,36.051,44.757,0
    .goto 1439,36.280,50.071,0
    .goto 1439,35.275,53.464,0
    .waypoint 1439,36.091,51.501,60,0
    .waypoint 1439,37.115,52.368,60,0
    .waypoint 1439,37.130,53.663,60,0
    .waypoint 1439,36.740,55.221,60,0
    .waypoint 1439,35.655,55.872,60,0
    .waypoint 1439,35.088,55.085,60,0
    .waypoint 1439,35.275,53.464,60,0
    .waypoint 1439,36.091,51.501,60,0
    .waypoint 1439,36.280,50.071,60,0
    .waypoint 1439,36.523,48.554,60,0
    .waypoint 1439,35.977,48.408,60,0
    .waypoint 1439,35.902,47.145,60,0
    .waypoint 1439,35.759,45.455,60,0
    .waypoint 1439,36.051,44.757,60,0
    >>Kill Pygmy Tide Crawlers
    .complete 983,1 --Crawler Leg (6)
    .mob Pygmy Tide Crawler
    .isOnQuest 983
]])";

/// The `A-1-11-Draenei.lua:4203` shape: a completion predicate written **inside** the walk.
const PREDICATE_MID_WALK: &str = "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    .complete 983,1
    .goto 1439,36.051,44.757,0
    .goto 1439,36.280,50.071,0
    .mob Pygmy Tide Crawler
    .goto 1439,35.275,53.464,0
]])";

/// The `A-1-11-Draenei.lua:83` shape: an operation written between two walks.
const OP_MID_WALK: &str = "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .accept 983
    .goto 1439,36.280,50.071,0
]])";

/// `A-11-23.lua:238-242`: a lone three-argument `.goto` that authors no radius.
const LONE_DESTINATION: &str = "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    .isOnQuest 3524
    .goto 1439,36.371,50.920
    .complete 3524,1
]])";

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The run
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_consecutive_run_of_movement_lines_becomes_one_travel_op() {
    let (profile, _report) = lower(CIRCUIT).await;
    let route = only_route(&profile, 0);

    assert_eq!(
        (route.points.len(), route.radii.len()),
        (17, 17),
        "`A-11-23.lua:215-231` is 3 `.goto` lines then 14 `.waypoint` lines — one walk of 17 \
         coordinates, which §7.3.3 prints as one `Travel` with 17 points and 17 radii. got: {route:?}"
    );
}

#[tokio::test]
async fn a_command_that_is_not_an_op_does_not_split_the_route() {
    let (profile, _report) = lower(PREDICATE_MID_WALK).await;
    let route = only_route(&profile, 0);

    assert_eq!(
        route.points.len(),
        3,
        "`.complete` is the task's completion predicate and `.mob` is its combat whitelist \
         (§7.3.3 task 0 puts both outside `ops`); neither executes between two steps of a walk. \
         Measured, 151 corpus steps write one of them mid-walk, and splitting there fabricates \
         293 routes — `A-1-11-Draenei.lua:4203` is `.complete`, nine `.goto`s, `.complete`, one \
         more `.goto`. got: {route:?}"
    );
}

#[tokio::test]
async fn an_operation_between_two_movement_lines_splits_the_route() {
    let (profile, _report) = lower(OP_MID_WALK).await;

    assert_eq!(
        op_tags(&profile, 0),
        vec!["Travel", "Accept", "Travel"],
        "`A-1-11-Draenei.lua:83` walks to a quest giver, accepts, then walks to the next — 620 \
         `.accept` and 568 `.turnin` lines sit between two movement runs in the corpus. Merging \
         across one would hand the engine a single route and lose the accept's place in the order. \
         got: {:?}",
        op_tags(&profile, 0)
    );

    let routes = routes(&profile, 0);
    assert!(
        routes.iter().all(|route| route.points.len() == 1),
        "each half of a split walk is its own one-point route, not a shared one. got: {routes:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Kind, medium and radii
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_loop_step_lowers_its_run_as_a_closed_circuit() {
    let (profile, _report) = lower(CIRCUIT).await;
    let route = only_route(&profile, 0);

    assert_eq!(
        route.kind,
        RouteKind::Circuit { close: true },
        "§4.3 maps `#loop` (1,661 uses) to `Route.kind = RouteKind::Circuit`, and §5.7 says the \
         compiler emits `Circuit` for `#loop` tasks. `close` states the *cycling* intent rather \
         than a geometric property: §7.3.3 prints `close: true` for both of its circuits, and only \
         one of them returns to its first point (`A-11-23.lua:231` does; `:254` does not). got: \
         {:?}",
        route.kind
    );
}

#[tokio::test]
async fn a_lone_movement_line_is_a_destination_and_a_run_in_a_non_loop_step_is_a_corridor() {
    let (lone, _report) = lower(LONE_DESTINATION).await;
    assert_eq!(
        only_route(&lone, 0).kind,
        RouteKind::Destination,
        "§5.7: the compiler emits `Destination` for an isolated `.goto` — the 16,231 three-argument \
         lines where the coordinate is just the place the NPC stands and the navmesh paths better \
         than a 2004-era waypoint chain. got: {:?}",
        only_route(&lone, 0).kind
    );

    let (run, _report) = lower(PREDICATE_MID_WALK).await;
    assert_eq!(
        only_route(&run, 0).kind,
        RouteKind::Corridor,
        "§5.7: `Corridor` for a run of `.goto`/`.waypoint` in a **non-loop** task — ordered points \
         the engine may smooth between, which is exactly what a `Circuit` may not do. got: {:?}",
        only_route(&run, 0).kind
    );
}

#[tokio::test]
async fn a_route_carries_the_radius_each_line_authored() {
    let (profile, _report) = lower(CIRCUIT).await;
    let route = only_route(&profile, 0);

    let mut expected = vec![0u16, 0, 0];
    expected.extend(std::iter::repeat(60u16).take(14));
    assert_eq!(
        route.radii, expected,
        "§7.3.3 prints `radii: [0,0,0,60 × 14]` for this step, matching the source exactly: \
         `A-11-23.lua:215-217` author `0` on the approach and `:218-231` author `60` on the \
         circuit. A `0` replaced by the importer's 5-yard execution default is a different fact — \
         the guide asked for zero yards. got: {:?}",
        route.radii
    );

    let (lone, _report) = lower(LONE_DESTINATION).await;
    assert_eq!(
        only_route(&lone, 0).radii,
        vec![5u16],
        "a three-argument `.goto` authors no radius (`A-11-23.lua:240`), and §7.3.3 prints `5` for \
         it — the reach default the importer applies when the guide states nothing. got: {:?}",
        only_route(&lone, 0).radii
    );
}

#[tokio::test]
async fn a_route_built_from_goto_and_waypoint_commits_to_no_travel_medium() {
    let (profile, _report) = lower(CIRCUIT).await;

    assert_eq!(
        only_route(&profile, 0).mode,
        TravelMode::Any,
        "§7.1 maps the media one way and one way only: `.goto`/`.waypoint` to `Any`, `.groundgoto` \
         to `Ground`, `.flygoto` to `Air`. `.groundgoto` (114) exists to *override* the engine's \
         preferred line through mountain paths, caves and stairs (§5.7); reading a circuit as \
         ground-forced because it is a circuit would mark all 38,087 ordinary `.goto` routes the \
         same way. got: {:?}",
        only_route(&profile, 0).mode
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The pool
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_route_that_recrosses_a_point_repeats_the_index_and_keeps_its_length() {
    let (profile, _report) = lower(CIRCUIT).await;
    let route = only_route(&profile, 0);

    assert_eq!(
        route.points,
        vec![0, 1, 2, 3, 4, 5, 6, 7, 8, 2, 3, 1, 9, 10, 11, 12, 0],
        "the circuit really re-crosses itself: `A-11-23.lua:224` re-walks `:217`, `:225` re-walks \
         `:218`, `:226` re-walks `:216`, and `:231` returns to `:215` to close the loop. §7.3.3 \
         says a route that re-crosses a point says so by repeating the **index**, never by \
         carrying a second copy of the point — so interning shrinks the pool and never the route. \
         got: {:?}",
        route.points
    );

    assert_eq!(
        profile.waypoint_pool.len(),
        13,
        "17 route lines over 13 distinct coordinates: four of the circuit's points are visited \
         twice. A pool of 17 would mean it was never interned. got: {:?}",
        profile.waypoint_pool
    );
}

#[tokio::test]
async fn a_lowered_waypoint_carries_no_z_because_the_compiler_has_no_navmesh_probe() {
    let (profile, _report) = lower(CIRCUIT).await;

    let with_height: Vec<_> = profile
        .waypoint_pool
        .iter()
        .filter(|point| point.z.is_some())
        .collect();
    assert!(
        with_height.is_empty(),
        "§5.7: `z` is `Option` because the corpus never supplies it — the compiler fills it from \
         the navmesh where it can and leaves `None` otherwise, letting the engine ground-snap. The \
         importer's `Position::world_z` is a structural `0.0` placeholder for exactly that \
         (`build_travel_position`: \"Z is always 0 here; the runtime resolves ground height on \
         arrival\"), and `Some(0.0)` turns that placeholder into an assertion that the waypoint is \
         at sea level. Baking the radius argument as Z once buried waypoints 35 yd inside terrain \
         and wedged travel in `awaiting_path` forever. got: {with_height:?}"
    );
}
