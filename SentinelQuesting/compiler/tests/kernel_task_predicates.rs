//! RED for **items G and H** — the two task predicates the guide does not write down.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 (`Task::applies_when`, `Task::complete_when`),
//! §5.3 (`Lifetime::Background::terminate_on`), §5.1.1 (one way to say one thing), and §7.3.3's
//! worked example, whose fixture `shared/tests/fixtures/adr07_worked_example.json` is the only
//! place in the repository that states what these two fields hold for a real guide.
//!
//! Both fields are **derived**. Neither has an authoring command: nothing in the RestedXP grammar
//! says "this step applies while quest 2118 is in the log" or "this patrol ends when 983 is handed
//! in". The compiler has to conclude them, and the whole risk is that a plausible conclusion is
//! indistinguishable from a right one at every later stage.
//!
//! # G — `applies_when` from the completion objective
//!
//! A `.complete <quest>,<index>` line makes the task's completion a `QuestObjective`. An objective
//! can only advance while the quest is **in the log**: before it is accepted the counter does not
//! exist, and after it is turned in the objective is gone. So a task whose completion is an
//! objective of quest *q* applies only while *q* is in the log — unless the author already said so
//! with `.isOnQuest`, in which case the authored gate stands and nothing is added to it.
//!
//! §7.3.3's four objective tasks are the witnesses: tasks 0 and 1 carry `.isOnQuest` explicitly
//! (`A-11-23.lua:237`, `:239`) and tasks 2 and 3 carry none (`:243-260`, `:261-264`) — and the
//! fixture gives all four the same `QuestInLog` gate. Two authored, two derived, one value.
//!
//! # H — `terminate_on` for a `Background` lifetime
//!
//! §5.3 says only "normally the linked task's completion or its own `complete_when`", which
//! underdetermines all three of §7.3.3's background tasks: task 0 terminates on
//! `QuestTurnedIn(983)`, which is neither. The rule that fits all three is a *scope* rule — a
//! sticky patrol that farms an objective must outlive the objective, because the quest is not
//! finished until it is handed in, and the hand-in is a different task:
//!
//! > A background task whose completion is an objective of quest *q* terminates on
//! > `QuestTurnedIn(q)` **iff this artifact contains the turn-in of *q***. Otherwise it terminates
//! > on its own `complete_when`.
//!
//! The `iff` is load-bearing in both directions. Task 0's turn-in is task 6 (`A-11-23.lua:280`), so
//! the patrol keeps `MOVEMENT` until the Buzzbox is handed in. Task 2's quest 2118 has no turn-in
//! anywhere in the excerpt, so terminating it on a hand-in this artifact will never perform would
//! hang the patrol forever — it terminates on its own objective instead. Task 5 has no objective at
//! all and keeps the existing fallback.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether the derivations are *true of the game*.** That an objective counter only advances
//!   while the quest is in the log, and that a `#sticky` farm loop should outlive its objective
//!   until hand-in, are claims about WoW and about the runtime. Nothing here executes; these tests
//!   pin that the compiler concluded what the fixture says, not that the fixture is right.
//! * **The census.** 7,218 `.complete` lines, 311 `#sticky` steps and 7,712 `.turnin` lines exist;
//!   the fragments below are synthetic and tiny, and every corpus figure quoted above is re-derived
//!   in no assertion.
//! * **Multi-quest completions have no corpus witness.** After the XXREQ fold there is no task in
//!   §7.3.3 with more than one objective, so `a_completion_naming_two_quests_gates_on_both` pins a
//!   *synthetic* shape. It is here because the alternative — deriving nothing when a task carries
//!   two `.complete` lines — silently drops the gate on exactly the tasks that need it most, and
//!   because a rule that only reproduces the worked example is not a lowering.
//! * **`terminate_on` when the quest is turned in by a task that is GATED OUT.** The census below
//!   is taken over surviving ops, so an archetype that loses the turn-in step also loses the
//!   `QuestTurnedIn` termination — which is the intent, since the artifact will never perform that
//!   hand-in. No test drives that combination, so the intent is stated rather than pinned.
//! * **Suspension.** §5.3 distinguishes voluntary termination from involuntary loss of a lease to a
//!   higher band. Only the first is a `Predicate`, and only the first is visible here.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race};
use sentinel_models::kernel::{
    AreaKind, Archetype, Expansion, Lifetime, Predicate, ProfileMode, QuestId,
    RuntimeProfile as KernelProfile,
};
use sentinel_query_types::QuestDetail;
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A `QuestMeta` that answers every objective with `1` and no item.
///
/// The counts are not what these tests are about — `kernel_worked_example.rs` pins the four real
/// ones against `tbcmangos.sqlite` — but a provider that panicked would turn a wrong *predicate*
/// into a crash and hide which of the two failed.
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

/// A world database that knows one quest and nothing else.
///
/// `.turnin` degrades to an inert `Comment` when the quest does not resolve, so a client that knows
/// nothing cannot produce an `Op::TurnIn` — and item H's whole rule turns on whether the turn-in is
/// present. `finisher_entry: None` is the §7.3.2-verified shape for quest 983, whose ender is
/// `gameobject_involvedrelation` 17182 rather than a creature.
fn world_knowing(quest: u32) -> MemoryQueryClient {
    MemoryQueryClient::new().with_quest(QuestDetail {
        id: quest,
        title: format!("quest {quest}"),
        level: 12,
        min_level: 10,
        required_quests: Vec::new(),
        next_quests: Vec::new(),
        giver_entry: None,
        finisher_entry: None,
        objectives: Vec::new(),
        // Left empty deliberately: a structured objective makes the importer synthesise the action
        // that satisfies it, which would add ops these fragments do not author.
        structured_objectives: Vec::new(),
    })
}

async fn import_with(guide: &str, client: &MemoryQueryClient) -> Project {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    sentinel_importer::ProjectBuilder::build(&parsed, "corpus.lua", client)
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"))
}

fn compile(project: &Project) -> (KernelProfile, CompileReport) {
    Compiler::compile_kernel(project, &night_elf_hunter(), &AnswersOne).unwrap_or_else(|err| {
        panic!("`compile_kernel` must not refuse a well-formed fragment, got: {err:?}")
    })
}

async fn lower(guide: &str) -> KernelProfile {
    compile(&import_with(guide, &MemoryQueryClient::new()).await).0
}

async fn lower_against(guide: &str, client: &MemoryQueryClient) -> KernelProfile {
    compile(&import_with(guide, client).await).0
}

/// The `terminate_on` of a background task, or a message naming what it actually was.
fn terminate_on(profile: &KernelProfile, task: usize) -> &Predicate {
    match &profile.tasks[task].lifetime {
        Lifetime::Background { terminate_on, .. } => terminate_on,
        other => panic!("task {task} must be `Background` for this test, got: {other:?}"),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// G — `applies_when`
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:243-260` and `:261-264` — two steps that work an objective and carry no
/// `.isOnQuest`. The fixture gates both on the quest being in the log anyway, because an objective
/// counter does not exist before the quest is accepted and is gone after it is turned in.
#[tokio::test]
async fn a_task_completing_an_objective_is_gated_on_having_that_quest_in_the_log() {
    let profile = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,38.226,52.780,0
    .complete 2118,1
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::QuestInLog { id: 2118 }),
        "got: {:?}",
        profile.tasks[0]
    );
}

/// `A-11-23.lua:234-237` — `.complete 983,1` *and* `.isOnQuest 983`, the shape §7.3.3 task 0 has.
///
/// The authored gate is already exactly the derived one, and the fixture carries a bare
/// `QuestInLog`, not an `And` of two identical terms. §5.1.1: there is one way to say one thing,
/// and a conjunction of a predicate with itself is a second spelling of it.
#[tokio::test]
async fn an_authored_is_on_quest_is_not_duplicated_by_the_derived_gate() {
    let profile = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .isOnQuest 983
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::QuestInLog { id: 983 }),
        "got: {:?}",
        profile.tasks[0]
    );
}

/// An authored gate on a *different* quest is the author saying something the derivation cannot
/// know — "do this Buzzbox loop only while you are also on 984" — and it must survive whole.
///
/// This is the test that separates "derive when the author was silent" from "derive and AND it in".
/// The second would quietly narrow 7,218 `.complete` tasks by a condition nobody wrote.
#[tokio::test]
async fn an_authored_gate_naming_another_quest_is_kept_and_not_widened() {
    let profile = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .isOnQuest 984
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::QuestInLog { id: 984 }),
        "the author's own gate is the whole gate; got: {:?}",
        profile.tasks[0]
    );
}

/// `A-11-23.lua:269-271` — the grind step, whose completion is an XP threshold and names no quest.
/// There is nothing to gate on, and `applies_when` stays absent rather than becoming a vacuous
/// truth.
#[tokio::test]
async fn a_completion_that_names_no_quest_derives_no_gate() {
    let profile = lower(
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
        profile.tasks[0].applies_when, None,
        "got: {:?}",
        profile.tasks[0]
    );
}

/// **Synthetic**, and named as such in this file's header: after the XXREQ fold no task in §7.3.3
/// carries two objectives. The rule is nonetheless the same rule applied to each objective the
/// completion names — a task advancing objectives of two quests needs both in the log — and the
/// conjunction is built by the same `fold_and` the step's own `.complete` terms go through, so
/// there is one spelling of a conjunction in this lowering and not two.
#[tokio::test]
async fn a_completion_naming_two_quests_gates_on_both() {
    let profile = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .complete 2118,1
]])"#,
    )
    .await;

    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::And(vec![
            Predicate::QuestInLog { id: 983 },
            Predicate::QuestInLog { id: 2118 },
        ])),
        "got: {:?}",
        profile.tasks[0]
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// H — `terminate_on`
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:211-237` plus its hand-in at `:276-280`: a `#sticky #loop` farm for quest 983's
/// objective, and, later in the same guide, the `.turnin 983` that finishes it.
///
/// The objective completes six Crawler Legs before the Buzzbox is clicked, and the patrol has to
/// keep holding `MOVEMENT` across that gap — so it terminates on the hand-in, not on the count.
#[tokio::test]
async fn a_sticky_objective_farm_terminates_on_the_turn_in_this_artifact_performs() {
    let profile = lower_against(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    #sticky
    #loop
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .isOnQuest 983
step
    .goto 1439,36.634,46.250
    .turnin 983
]])"#,
        &world_knowing(983),
    )
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::QuestTurnedIn { id: 983 },
        "got: {:?}",
        profile.tasks[0].lifetime
    );
}

/// `A-11-23.lua:243-260` — the identical `#sticky #loop` shape for quest 2118, whose turn-in is
/// nowhere in the excerpt.
///
/// This is the same fragment as the test above with the turn-in step deleted, so the two differ in
/// exactly one fact. Terminating on a `QuestTurnedIn` this artifact will never perform would hang
/// the patrol on `MOVEMENT` forever; it ends on its own objective instead.
#[tokio::test]
async fn the_same_farm_without_a_turn_in_terminates_on_its_own_objective() {
    let profile = lower_against(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    #sticky
    #loop
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .isOnQuest 983
]])"#,
        &world_knowing(983),
    )
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 1
        },
        "got: {:?}",
        profile.tasks[0].lifetime
    );
}

/// A turn-in of a *different* quest must not terminate this patrol. The census is per quest, not
/// "does this artifact turn anything in".
#[tokio::test]
async fn a_turn_in_of_another_quest_does_not_terminate_the_patrol() {
    let profile = lower_against(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    #sticky
    #loop
    .goto 1439,36.051,44.757,0
    .complete 983,1
    .isOnQuest 983
step
    .goto 1439,36.634,46.250
    .turnin 3524
]])"#,
        &world_knowing(3524),
    )
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 1
        },
        "got: {:?}",
        profile.tasks[0].lifetime
    );
}

/// `A-11-23.lua:272-275` — the `#completewith next` ride-along, which has no objective.
///
/// Item H's rule is scoped to a task whose completion is a `QuestObjective`, so this rider falls
/// past it into §5.3's own-`complete_when` case. **It reaches that case only because `.subzone` now
/// lowers**: this test previously asserted `Or([])`, the never-satisfiable empty disjunction, and it
/// did so truthfully, because `.subzone 442` was inert and the task had no `complete_when` for the
/// branch to use. Fixing the lowering (`kernel_authored_predicates.rs`) supplied one, and §7.3.3's
/// fixture agrees — its task 5 terminates on `InArea { area: 442, kind: SubArea }`.
///
/// The empty disjunction has not been removed and is not this test's subject: a rider that authors
/// no completion command at all still degenerates to it. Pinning *that* is a separate deliverable.
#[tokio::test]
async fn a_ride_along_with_no_objective_terminates_on_its_own_completion() {
    let profile = lower(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#group RestedXP TBC Guide (A)
#name 12-14 Darkshore
step
    #completewith next
    .subzone 442
step
    .goto 1439,36.634,46.250
]])"#,
    )
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::InArea {
            area: 442,
            kind: AreaKind::SubArea
        },
        "got: {:?}",
        profile.tasks[0].lifetime
    );
}
