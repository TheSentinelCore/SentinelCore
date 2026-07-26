//! The scheduler band is an **ordering**, and today nothing guards the ordering.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.3 "Concurrency" — the band is "offset by task
//! order so two sticky tasks cannot deadlock" — and §7.3.3 "Worked example", whose two `#sticky`
//! patrols are bands **34** and **35** in task order while its `#completewith` ride-along sits at
//! **30**.
//!
//! # The hole this closes
//!
//! Two tests already pin the band's *range*. `shared/tests/kernel_band_invariant.rs` refuses an
//! out-of-range band on the wire, and
//! `compiler/tests/kernel_task_graph.rs::every_emitted_background_band_sits_inside_the_goal_band`
//! pins that the lowering never emits one. **Both are satisfied by a lowering that gives every
//! concurrent task the same band**, and both say so in their own headers: band 34 is in range, and
//! so is band 34 again, and again.
//!
//! That is not a hypothetical. `compiler/src/kernel/task_graph.rs::lower_lifetime` advances its
//! running offset with a single `*holding_band += 1`. Changing that `1` to a `0` collapses every
//! channel-holding background task in a guide onto one band, and the entire suite stays green —
//! measured, not assumed. What it reintroduces is the exact failure §5.3's offset exists to
//! prevent: two patrols that both hold `MOVEMENT` at equal priority, neither able to outrank the
//! other, each waiting for a lease the other will not yield.
//!
//! Range is a *bound*; this file asserts a *relation*. They are different properties and a test for
//! one cannot substitute for the other, which is why the range is deliberately not re-asserted
//! below — see "what these tests cannot see".
//!
//! # Why the offset is spent only on holders
//!
//! The Goal band affords 20 values (30..=49) and the offset starts at 34, so a guide gets 16
//! distinct holder bands before `lower_lifetime` clamps and warns `BAND_OFFSET_SATURATED`. A
//! ride-along holds no channels — §7.3.3 task 6 is `Background { channels: [], band: 30 }` — so it
//! cannot deadlock against anything and must not consume one of those 16. The corpus has 2,788
//! label-valued `#completewith` links against 311 `#sticky` steps: spending the offset on
//! ride-alongs would saturate guides that today do not come close.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **They cannot see liveness.** "Concurrently live" is approximated by "present in the same
//!   lowered profile", because that is all the lowering itself knows — it has no liveness analysis
//!   and assigns bands from authored order alone. Two patrols whose lifetimes provably never
//!   overlap at runtime are still required here to hold distinct bands. That is conservative in the
//!   safe direction, but it does mean a future lowering that computed real overlap and reused a
//!   band would fail these tests while being correct.
//! * **They cannot see the RANGE, on purpose.** Nothing below asserts `30..=49`. A lowering that
//!   emitted strictly increasing bands `200, 201, 202` passes every assertion here. The range is
//!   the other half, and it is already pinned twice — on the wire by
//!   `shared/tests/kernel_band_invariant.rs` and in the compiler by
//!   `compiler/tests/kernel_task_graph.rs::every_emitted_background_band_sits_inside_the_goal_band`.
//!   Duplicating it here would mean two tests fail for one cause and neither names it.
//! * **They cannot see saturation.** Every fragment below carries three holders, well under the 16
//!   the Goal band affords, and the ordering assertion is guarded by a check that
//!   `BAND_OFFSET_SATURATED` did *not* fire. What the clamp does past the 16th holder — where §5.3's
//!   separation is knowingly given up — is asserted by nothing, here or anywhere.
//! * **They cannot see across guide blocks.** `holding_band` is one counter per `Project`, so every
//!   block restarts at 34 and tasks from two different profiles collide by construction. Whether
//!   that is right is unknowable from here: nothing in this repository runs two profiles at once.
//! * **They cannot see WHICH channel.** The distinctness rule is written over *intersecting* channel
//!   sets, which is the general statement, but `Channel::Movement` is the only channel
//!   `lower_lifetime` ever assigns. Every non-empty set in the corpus is `[MOVEMENT]`, so the
//!   intersecting-but-unequal case — the one that will matter when `INTERACTION` is assigned — is
//!   exercised by nothing.
//! * **They cannot see the runtime.** Whether band 35 actually outranks band 34 in a live lease, and
//!   whether distinct bands really do break the deadlock, is ADR 08 kernel behaviour. Nothing here
//!   executes a scheduler. These tests assert that the artifact carries the *information* the
//!   scheduler needs, not that the scheduler uses it.
//! * **`MemoryQueryClient::new()` resolves no quests and no NPCs**, so `.complete`/`.subzone`
//!   degrade and most tasks below carry one or two `Op::Travel`s and nothing else. Op contents are
//!   never asserted; only whether a task ended up holding `MOVEMENT`.

use std::collections::BTreeMap;

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race, Severity};
use sentinel_models::kernel::{
    Archetype, Channel, Expansion, Lifetime, ProfileMode, QuestId, RuntimeProfile as KernelProfile,
    TaskId,
};
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A `QuestMeta` that answers every objective with `1`.
///
/// The fragments below carry `.complete` lines only so that a `#sticky` task has a `complete_when`
/// to derive `terminate_on` from; the counts are irrelevant to the band. A provider that refused to
/// answer would turn that into a panic and hide which of the two is missing.
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

/// The archetype these tests compile for. Spelled out in full rather than `Default`ed: each field is
/// a compile-time gate axis, and a defaulted one is a gate nobody chose. No fragment below carries a
/// `<<` tail, so the choice decides nothing — which is the point, and why it is stated once.
fn alliance_warrior() -> Archetype {
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

/// Guide source → lowered profile, through the real importer.
///
/// The importer path is used rather than a hand-built `Project` because `#sticky` is a directive the
/// importer parses; a hand-built `Project` would let this file assert a lowering of an input the
/// importer never produces.
async fn lower(guide: &str) -> (KernelProfile, CompileReport) {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    let project: Project =
        sentinel_importer::ProjectBuilder::build(&parsed, "corpus.lua", &MemoryQueryClient::new())
            .await
            .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"));
    Compiler::compile_kernel(&project, &alliance_warrior(), &AnswersOne).unwrap_or_else(|err| {
        panic!("`compile_kernel` must not refuse a well-formed fragment, got: {err:?}")
    })
}

/// Every concurrent task in the artifact, in task order, as `(id, channels, band)`.
///
/// `Exclusive` tasks are dropped: they hold nothing and carry no band at all.
fn concurrent_tasks(profile: &KernelProfile) -> Vec<(TaskId, Vec<Channel>, u8)> {
    let mut found: Vec<(TaskId, Vec<Channel>, u8)> = profile
        .tasks
        .iter()
        .filter_map(|task| match &task.lifetime {
            Lifetime::Background { channels, band, .. } => {
                Some((task.id, channels.clone(), *band))
            }
            Lifetime::Exclusive => None,
        })
        .collect();
    found.sort_by_key(|(id, _, _)| *id);
    found
}

/// The concurrent tasks that hold at least one channel — the only ones that can deadlock, and
/// therefore the only ones §5.3's per-task offset is about.
fn channel_holders(profile: &KernelProfile) -> Vec<(TaskId, Vec<Channel>, u8)> {
    concurrent_tasks(profile)
        .into_iter()
        .filter(|(_, channels, _)| !channels.is_empty())
        .collect()
}

/// Whether the lowering gave up on separating holders in this compile.
///
/// Asserted as absent wherever a strict ordering is expected: past the 16th holder `lower_lifetime`
/// clamps and warns instead of pushing a band above the safety net, and a clamped compile shares a
/// band *by design*. A test that did not exclude it would be asserting the opposite of the ADR.
fn saturated(report: &CompileReport) -> bool {
    report
        .unmapped_conditions
        .iter()
        .any(|d| d.code == "BAND_OFFSET_SATURATED" && d.severity == Severity::Warning)
}

/// A census of every lifetime in the artifact, for failure messages.
///
/// Printed rather than the bands alone: when a holder is missing, the useful question is what that
/// task became instead, and a list of bands cannot answer it.
fn lifetime_census(profile: &KernelProfile) -> Vec<(TaskId, &Lifetime)> {
    profile.tasks.iter().map(|t| (t.id, &t.lifetime)).collect()
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The ordering
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// No two channel-holding concurrent tasks whose channel sets intersect share a band.
///
/// This is the deadlock property itself, stated at the smallest scope that carries it. §5.3's offset
/// exists so that "two sticky tasks cannot deadlock", and two tasks deadlock precisely when they
/// contend for the same channel at the same priority: the scheduler has no tie-break, so neither
/// outranks the other and neither yields. Distinctness is what supplies the tie-break.
///
/// **This is the test that fails under `*holding_band += 0`.** Under that mutation the three patrols
/// below all come out at 34 — every one of them still inside §7.2's range, so both existing band
/// tests stay green.
///
/// Asserted over *intersecting* sets rather than over all holders, because the rule is about
/// contention and two tasks holding disjoint channels cannot contend. Today every non-empty set is
/// `[MOVEMENT]`, so the two readings coincide; when they stop coinciding this assertion is the one
/// that stays true.
#[tokio::test]
async fn patrols_holding_the_same_channel_are_never_given_the_same_band() {
    let (profile, report) = lower(THREE_PATROLS).await;
    let holders = channel_holders(&profile);

    // The clamp gives distinctness up deliberately — its own diagnostic says the saturated task
    // "shares a band with its predecessor" — so a saturated compile is the one input for which this
    // assertion is the wrong expectation. Three holders against sixteen available bands cannot
    // reach it; the guard is here so that a future edit to the fragment cannot quietly turn this
    // test into an assertion against the ADR.
    assert!(
        !saturated(&report),
        "three holders is far below the sixteen the Goal band affords, so the clamp must not have \
         fired. Diagnostics: {:?}",
        report
            .unmapped_conditions
            .iter()
            .map(|d| (d.severity, d.code.as_str()))
            .collect::<Vec<_>>()
    );
    assert!(
        holders.len() >= 3,
        "the fragment carries three `#sticky` steps that each walk, so the artifact must hold three \
         channel-holding concurrent tasks — with fewer than two, a distinctness assertion is \
         vacuously true and would go green on a lowering that emitted nothing. Lifetimes: {:?}",
        lifetime_census(&profile)
    );

    let mut collisions: Vec<((TaskId, TaskId), u8, Vec<Channel>)> = Vec::new();
    for (index, (left_id, left_channels, left_band)) in holders.iter().enumerate() {
        for (right_id, right_channels, right_band) in &holders[index + 1..] {
            if left_band != right_band {
                continue;
            }
            let shared: Vec<Channel> = left_channels
                .iter()
                .filter(|channel| right_channels.contains(channel))
                .copied()
                .collect();
            if !shared.is_empty() {
                collisions.push(((*left_id, *right_id), *left_band, shared));
            }
        }
    }

    assert!(
        collisions.is_empty(),
        "ADR 07 §5.3 offsets the band by task order so two sticky tasks cannot deadlock. These \
         tasks contend for a channel at an identical band, so the scheduler has no tie-break \
         between them and neither can outrank the other into a lease — `(a, b), band, shared \
         channels`: {collisions:?}. All holders: {holders:?}"
    );
}

/// The offset advances with task order: holder bands strictly increase in task id.
///
/// The mechanism §5.3 actually names, as opposed to the property it buys. Distinctness alone would
/// be satisfied by any injective assignment — hashing the task id, say — and §7.3.3 is specific:
/// its patrols are tasks 0 and 2 at bands 34 and 35, in that order, so a later patrol outranks an
/// earlier one. That direction is a semantic, not an artefact: the bands are a total order over
/// lease priority, and "the most recently entered patrol wins the tie" is a rule an author can
/// reason about while "whichever the hash favoured" is not.
///
/// **Also fails under `*holding_band += 0`** — equal bands are not strictly increasing — and it is
/// not redundant with the test above: it additionally fails a lowering that offsets *backwards*, or
/// that offsets only the first pair.
///
/// The saturation guard is load-bearing. Past the 16th holder the lowering deliberately clamps and
/// warns, and a clamped compile shares a band by design; asserting strictness over one would assert
/// the opposite of the ADR.
#[tokio::test]
async fn the_band_offset_advances_with_task_order() {
    let (profile, report) = lower(THREE_PATROLS).await;
    let holders = channel_holders(&profile);

    assert!(
        !saturated(&report),
        "this fragment carries three holders and the Goal band affords sixteen, so the clamp must \
         not have fired — a clamped compile shares a band deliberately and strict ordering is the \
         wrong expectation for it. Diagnostics: {:?}",
        report
            .unmapped_conditions
            .iter()
            .map(|d| (d.severity, d.code.as_str()))
            .collect::<Vec<_>>()
    );
    assert!(
        holders.len() >= 3,
        "three `#sticky` walking steps must produce three channel-holding tasks; two would let a \
         single comparison stand in for an ordering. Lifetimes: {:?}",
        lifetime_census(&profile)
    );

    let out_of_order: Vec<((TaskId, u8), (TaskId, u8))> = holders
        .windows(2)
        .filter(|pair| pair[0].2 >= pair[1].2)
        .map(|pair| ((pair[0].0, pair[0].2), (pair[1].0, pair[1].2)))
        .collect();

    assert!(
        out_of_order.is_empty(),
        "ADR 07 §5.3 offsets the band BY TASK ORDER, and §7.3.3's two patrols are 34 then 35 for \
         tasks 0 then 2 — so a later channel-holding task must carry a strictly higher band than \
         every earlier one. These adjacent pairs do not, as `(earlier task, band), (later task, \
         band)`: {out_of_order:?}. All holders: {holders:?}"
    );
}

/// The offset is spent on holders only: ride-alongs share one band, and it is below every patrol's.
///
/// The guard against over-correcting. The cheapest way to make the two tests above pass is to hand
/// every `Background` task its own band, and that is wrong twice over. It burns the 16-value budget
/// on tasks that hold nothing and therefore cannot deadlock — §7.3.3 task 6 is
/// `Background { channels: [], band: 30 }` and the corpus has an order of magnitude more
/// `#completewith` links than `#sticky` steps — and it lifts a ride-along above the patrol it is
/// riding along with.
///
/// The fragment interleaves its ride-alongs *between* the patrols precisely so that a lowering which
/// advanced the offset for non-holders would be caught: the patrols would come out 34, 36, 38 and
/// still be strictly increasing, still distinct, still in range.
///
/// **Expected GREEN today**, and it must stay green through any fix to the two above.
#[tokio::test]
async fn ride_alongs_hold_nothing_so_they_do_not_consume_the_offset() {
    let (profile, _) = lower(THREE_PATROLS).await;
    let concurrent = concurrent_tasks(&profile);

    let ride_alongs: Vec<(TaskId, u8)> = concurrent
        .iter()
        .filter(|(_, channels, _)| channels.is_empty())
        .map(|(id, _, band)| (*id, *band))
        .collect();
    let holders: Vec<(TaskId, u8)> = concurrent
        .iter()
        .filter(|(_, channels, _)| !channels.is_empty())
        .map(|(id, _, band)| (*id, *band))
        .collect();

    assert!(
        ride_alongs.len() >= 2,
        "the fragment carries two `#completewith next` steps that walk nowhere, so the artifact \
         must hold two channel-less concurrent tasks — with fewer, 'they share a band' is a claim \
         about nothing. Lifetimes: {:?}",
        lifetime_census(&profile)
    );

    let by_band: BTreeMap<u8, Vec<TaskId>> =
        ride_alongs
            .iter()
            .fold(BTreeMap::new(), |mut acc, (id, band)| {
                acc.entry(*band).or_default().push(*id);
                acc
            });
    assert_eq!(
        by_band.len(),
        1,
        "a ride-along holds no channels, so it cannot deadlock against another one and must not \
         consume one of the sixteen holder bands. They are spread across several instead, as \
         `band -> tasks`: {by_band:?}"
    );

    let Some((ride_along_band, _)) = by_band.iter().next() else {
        panic!("a map of length 1 must have a first entry, got: {by_band:?}")
    };
    let not_below: Vec<(TaskId, u8)> = holders
        .iter()
        .copied()
        .filter(|(_, band)| band <= ride_along_band)
        .collect();
    assert!(
        not_below.is_empty(),
        "§7.3.3 puts the ride-along at band 30, below both patrols at 34 and 35: a task that holds \
         nothing must not outrank the task it is waiting on. Ride-alongs sit at {ride_along_band}, \
         and these holders do not beat it: {not_below:?}"
    );

    // The whole point of interleaving the ride-alongs between the patrols: if the offset were spent
    // on them too, the holders would be 34, 36, 38 — still increasing, still distinct, still in
    // range, and every other assertion in this file would stay green.
    let steps: Vec<u8> = holders
        .windows(2)
        .map(|pair| pair[1].1.saturating_sub(pair[0].1))
        .collect();
    assert!(
        steps.iter().all(|step| *step == 1),
        "two ride-alongs sit between the three patrols in this fragment, and the offset must have \
         skipped them: consecutive holders are one band apart. Gaps between adjacent holder bands: \
         {steps:?}, holders: {holders:?}, ride-alongs: {ride_alongs:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Fragment
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Three `#sticky` patrols with two `#completewith` ride-alongs interleaved between them.
///
/// The patrols are `A-11-23.lua:659-682` (`#label Anaya`), `A-11-23.lua:683-706` (`#label Relics`)
/// and `A-11-23.lua:747-761` (`#label bears1A`) — three real circuits in one guide block, in
/// authored order. Each is condensed to one `.goto` and one movement line: the count of waypoints is
/// irrelevant to the lifetime, and how many `Op::Travel`s they collapse into is a different
/// deliverable. Their `#xprate <1.5` step gates are dropped rather than quoted, so that no
/// assertion here depends on an archetype axis this file is not about.
///
/// The ride-alongs are `A-11-23.lua:272-275`'s `#completewith next` shape — ADR 07 §7.3.3's task 6,
/// the one place the ADR states what a lowered ride-along looks like. They are placed
/// *between* the patrols on purpose — see
/// `ride_alongs_hold_nothing_so_they_do_not_consume_the_offset`.
///
/// The closing `#requires` step is the ordinary non-concurrent tail, present so the artifact is not
/// made entirely of concurrent tasks — a shape no real guide has.
const THREE_PATROLS: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Bands
step
    #sticky
    #label Anaya
    .goto 1439,42.017,58.866,0
    .waypoint 1439,42.311,58.645,50,0
    .complete 963,1 --Anaya's Pendant (1)
step
    #optional
    #completewith next
    .subzone 442 >> Travel to Auberdine
step
    #sticky
    #label Relics
    .goto 1439,42.670,57.390,0
    .waypoint 1439,41.708,57.888,55,0
    .complete 953,1 --Relic Coffer Key (1)
step
    #optional
    #completewith next
    .subzone 442 >> Travel to Auberdine
step
    #sticky
    #label bears1A
    #loop
    .goto Darkshore,39.03,67.32,0
    .goto Darkshore,42.54,67.76,70,0
    .complete 2138,1 --Rabid Thistle Bear slain (20)
step
    #requires bears1A
    .goto 1439,36.634,46.250
]])"#;
