//! What the imported `Project` must still know about a movement line and about the step it came
//! from, so that a later lowering can rebuild a route without re-reading the guide.
//!
//! Three facts the authoring model was silently dropping, each one load-bearing for ADR
//! `07_RUNTIME_PROFILE_SCHEMA` §7.3.3:
//!
//! 1. **`.waypoint` is a movement command.** §7.1 lists it beside `.goto` as a source of
//!    [`Op::Travel`](sentinel_models::kernel::Op::Travel) (593 corpus uses), and the decisive
//!    witness §5.7 cites — the closed patrol circuit at `A-11-23.lua:215-231` — is three `.goto`
//!    lines followed by **fourteen `.waypoint` lines**. Importing `.waypoint` as an inert comment
//!    deleted 14 of that circuit's 17 points before any compiler could see them.
//! 2. **The authored arrival radius is data.** `A-11-23.lua:215` authors `0` and `:218` authors
//!    `60`; §7.3.3 prints `radii: [0,0,0,60,…]` for the same circuit. The 5-yard reach default and
//!    the `[5,60]` clamp `ProjectBuilder` applies to `TravelAction::tolerance` are an *execution*
//!    policy (see its own comment: a typo must not make "arrived" meaninglessly wide), and they are
//!    kept — but they are applied to a value that no longer overwrites what the guide said.
//! 3. **A step owns a contiguous line range.** `Task::source` in §7.3.3 spans `211-237`,
//!    `238-242`, … — the `step` marker through the line before the next marker. Only directive
//!    entries carried a line number before, so a step whose directives sit at `:212-:214` reported
//!    itself as three lines long.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether the coordinates are right.** `build_travel_position` and the measured zone table own
//!   that, and `shared/tests/zone_table.rs` checks it against real spawns. Nothing here asserts a
//!   world coordinate.
//! * **The kernel artifact.** These are facts about `sentinel_models::authoring`. Whether a run of
//!   travel actions becomes one `Op::Travel` is the compiler's question, pinned in
//!   `compiler/tests/kernel_task_graph.rs`.
//! * **Anything about a guide with no `step` markers.** Every fixture below is a well-formed
//!   `RegisterGuide` block.

use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_models::authoring::{ActionPayload, Operation, Project, TravelAction};
use sentinel_queryclient::MemoryQueryClient;

/// A guide whose line numbers are stated in the source below, so an assertion can cite them.
///
/// Line 1 is `RXPGuides.RegisterGuide([[`. The two steps mirror `A-11-23.lua:211-231` (a `#loop`
/// circuit of `.goto` then `.waypoint`) and `:238-242` (a lone radius-less `.goto`), shortened to
/// the shapes under test.
const GUIDE: &str = "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
#group RestedXP TBC Guide (A)
step
    #sticky
    #label BuzzBox1
    #loop
    .goto 1439,36.051,44.757,0
    .waypoint 1439,36.091,51.501,60,0
    .waypoint 1439,36.051,44.757,60,0
    .complete 983,1 --Crawler Leg (6)
step
    .goto 1439,36.371,50.920
    .complete 3524,1 --Sea Creature Bones (1)
]])";

/// `GUIDE`'s first `step` marker.
const FIRST_STEP_LINE: u32 = 4;
/// `GUIDE`'s last line belonging to the first step — its `.complete`.
const FIRST_STEP_LAST_LINE: u32 = 11;
/// `GUIDE`'s second `step` marker.
const SECOND_STEP_LINE: u32 = 12;
/// `GUIDE`'s last line belonging to the second step — its `.complete`.
const SECOND_STEP_LAST_LINE: u32 = 14;

async fn imported() -> Project {
    let parsed = match parse_guide(GUIDE) {
        Ok(parsed) => parsed,
        Err(error) => panic!("the fixture guide must parse, got: {error:?}"),
    };
    match ProjectBuilder::build(&parsed, "fixture.lua", &MemoryQueryClient::new()).await {
        Ok(project) => project,
        Err(error) => panic!("the fixture guide must build into a Project, got: {error:?}"),
    }
}

/// Every `Travel` payload on `op`, in authored order.
fn travels(op: &Operation) -> Vec<&TravelAction> {
    op.actions
        .iter()
        .filter_map(|action| match &action.payload {
            ActionPayload::Travel(travel) => Some(travel),
            _ => None,
        })
        .collect()
}

#[tokio::test]
async fn a_waypoint_line_becomes_a_travel_action_exactly_as_a_goto_line_does() {
    let project = imported().await;
    let Some(step) = project.operations.first() else {
        panic!("the fixture guide authors two steps, got: {:?}", project.operations)
    };

    let travels = travels(step);
    assert_eq!(
        travels.len(),
        3,
        "ADR 07 §7.1 lists `.waypoint` (593 uses) beside `.goto` as a source of `Op::Travel`, and \
         §5.7's decisive witness `A-11-23.lua:215-231` is 3 `.goto` lines then 14 `.waypoint` \
         lines. A `.waypoint` imported as an inert comment deletes the whole circuit. got: {:?}",
        step.actions.iter().map(|a| &a.payload).collect::<Vec<_>>()
    );

    for (index, travel) in travels.iter().enumerate() {
        assert!(
            travel.position.is_some(),
            "movement action {index} carries no resolved position, so it can produce no waypoint. \
             got: {travel:?}"
        );
    }
}

#[tokio::test]
async fn a_movement_line_keeps_the_arrival_radius_it_authored_and_none_when_it_authored_one() {
    let project = imported().await;
    let Some(circuit) = project.operations.first() else {
        panic!("the fixture guide authors two steps, got: {:?}", project.operations)
    };

    let authored: Vec<Option<u16>> = travels(circuit)
        .iter()
        .map(|travel| travel.authored_radius)
        .collect();
    assert_eq!(
        authored,
        vec![Some(0), Some(60), Some(60)],
        "the guide authors `0` on the approach and `60` on the circuit (`A-11-23.lua:215` and \
         `:218`), and §7.3.3 prints `radii: [0,0,0,60,…]` for that very step. `tolerance` cannot \
         answer this: it drops a `0` and clamps into `[5,60]`, which is an execution policy \
         applied on top of the authored value, not the authored value. got: {authored:?}"
    );

    let Some(lone) = project.operations.get(1) else {
        panic!("the fixture guide authors two steps, got: {:?}", project.operations)
    };
    let unauthored: Vec<Option<u16>> = travels(lone)
        .iter()
        .map(|travel| travel.authored_radius)
        .collect();
    assert_eq!(
        unauthored,
        vec![None],
        "a 3-argument `.goto` authors no radius at all (`A-11-23.lua:240`). `None` is that fact; \
         `Some(0)` would be the different fact that the guide asked for zero yards. got: \
         {unauthored:?}"
    );
}

#[tokio::test]
async fn an_operation_spans_its_step_marker_through_the_line_before_the_next_marker() {
    let project = imported().await;
    let spans: Vec<(Option<u32>, Option<u32>)> = project
        .operations
        .iter()
        .map(|op| (op.source_line_start, op.source_line_end))
        .collect();

    assert_eq!(
        spans,
        vec![
            (Some(FIRST_STEP_LINE), Some(FIRST_STEP_LAST_LINE)),
            (Some(SECOND_STEP_LINE), Some(SECOND_STEP_LAST_LINE)),
        ],
        "ADR 07 §7.3.3 spans its eight tasks `211-237`, `238-242`, … — every line of the guide \
         from a `step` marker to the last line that belongs to it. Deriving the span from the \
         step's `#directive` lines alone reports `A-11-23.lua:211-237` as `213-213`. got: {spans:?}"
    );
}
