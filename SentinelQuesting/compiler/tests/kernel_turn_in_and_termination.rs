//! Items E and C — the two predicates a `.turnin` step implies, and what is left of the
//! never-satisfiable `terminate_on` once they exist.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 (`Task::applies_when`, `Task::complete_when`,
//! `Op::TurnIn`), §5.3 (`Lifetime::Background::terminate_on`), §5.1.1 (one way to say one thing),
//! and §7.3.3's worked example — fixture `shared/tests/fixtures/adr07_worked_example.json`.
//!
//! # E — a hand-in is its own applicability gate and its own completion
//!
//! `A-11-23.lua:280` is `.turnin 983` and the whole step is that one command plus the walk to it.
//! The fixture's task 6 nonetheless carries both predicates:
//!
//! ```text
//! "applies_when":  { "type": "QuestComplete",  "payload": { "id": 983 } }
//! "complete_when": { "type": "QuestTurnedIn",  "payload": { "id": 983 } }
//! ```
//!
//! Neither is authored. Both follow from what a hand-in **is**: you can only hand in a quest whose
//! objectives are done, and the hand-in is finished exactly when the quest is turned in. The two
//! are one derivation with two halves and the lowering emits them together or not at all — a task
//! that knows when it is finished but not when it may start is a task the runner will walk to and
//! stall at, and a task gated on `QuestComplete` with no completion never leaves.
//!
//! The alternative — leaving both `null`, which is what the compiler did — is not neutral. A task
//! whose `completion` is `OwnPredicate` and whose `complete_when` is `null` has no completion
//! authority at all; §5.3's cursor is the only thing that can move past it, and 4,988 corpus tasks
//! carrying an `Op::TurnIn` are in exactly that state.
//!
//! # C — what is left of `Or([])`
//!
//! `lower_lifetime` gives a `Background` task with no derivable termination the empty disjunction:
//! never satisfiable, which is the honest reading of "the guide states no termination condition"
//! and is deliberately *not* the empty conjunction, which is vacuously true and would end a
//! `#sticky` patrol before it walked anywhere. It has always been paired with a
//! `BACKGROUND_WITHOUT_TERMINATION` diagnostic.
//!
//! Two deliverables have shrunk the population that reaches it. `.subzone` lowering gave the
//! excerpt's rider its own `InArea` completion (`kernel_authored_predicates.rs`); item E now gives
//! every single-quest hand-in a `QuestTurnedIn`, which a rider linked to one **inherits** through
//! §5.3's "the linked task's completion" route. What remains is a genuine case and is named below.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether `QuestComplete` is the right gate rather than `QuestInLog`.** It is what the fixture
//!   says, and it is stricter: a quest in the log whose objectives are unfinished cannot be handed
//!   in, so gating on the log alone would send the runner to an NPC that has nothing to say. But
//!   §8's repeatable-quest note observes that `QuestInLog` is the reliable gate for a `.daily`, and
//!   no corpus daily turn-in is exercised here.
//! * **Multi-quest hand-ins.** 540 corpus tasks carry more than one `Op::TurnIn` and the fixture
//!   has none. The pair is derived only for a single hand-in; see
//!   `a_step_handing_in_two_quests_derives_neither_half`, which pins the refusal *and* states what
//!   the two candidate answers were.
//! * **`Op::TurnIn::any_of`.** `.turninmultiple` (1 corpus use, the Aldor/Scryer choice point, §8)
//!   means "hand in whichever of these was taken", so `QuestTurnedIn` of the named quest is not the
//!   completion. The guard exists and no test reaches it: the authoring model does not carry
//!   `any_of`, so every lowered `Op::TurnIn` has an empty one today.
//! * **Whether the runner can actually read `QuestComplete`.** §5.1.2 is explicit that the quest log
//!   has no readiness contract, which is the whole reason `unknown_policy` exists; that these
//!   predicates read `Unknown` after a loading screen is expected, and item D decides what happens
//!   then (`kernel_unknown_policy.rs`).
//! * **The rest of the corpus.** Every fragment below is synthetic and tiny. The corpus figures
//!   quoted are measurements, re-derived by no assertion here.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race};
use sentinel_models::kernel::{
    Archetype, Expansion, Lifetime, Predicate, ProfileMode, QuestId,
    RuntimeProfile as KernelProfile,
};
use sentinel_query_types::QuestDetail;
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

/// A world database that knows the named quests and nothing else.
///
/// The importer degrades an unresolvable `.turnin` to an inert `Comment`, so a client that knows
/// nothing produces no `Op::TurnIn` at all and every test in this file would pass vacuously.
/// `finisher_entry: None` is quest 983's §7.3.2-verified shape — its ender is
/// `gameobject_involvedrelation` 17182, which is why the fixture's `interact_target` is `null`.
fn world_knowing(quests: &[u32]) -> MemoryQueryClient {
    quests.iter().fold(MemoryQueryClient::new(), |client, quest| {
        client.with_quest(QuestDetail {
            id: *quest,
            title: format!("quest {quest}"),
            level: 12,
            min_level: 10,
            required_quests: Vec::new(),
            next_quests: Vec::new(),
            giver_entry: None,
            finisher_entry: None,
            objectives: Vec::new(),
            structured_objectives: Vec::new(),
        })
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

async fn lower_with_report(guide: &str) -> (KernelProfile, CompileReport) {
    compile(&import_with(guide, &MemoryQueryClient::new()).await)
}

fn guide(steps: &str) -> String {
    format!(
        "\nRXPGuides.RegisterGuide([[\n#version 7\n#group RestedXP TBC Guide (A)\n#name 12-14 \
         Darkshore\n{steps}\n]])"
    )
}

/// The `terminate_on` of a background task, or a message naming what it actually was.
fn terminate_on(profile: &KernelProfile, task: usize) -> &Predicate {
    match &profile.tasks[task].lifetime {
        Lifetime::Background { terminate_on, .. } => terminate_on,
        other => panic!("task {task} must be `Background` for this test, got: {other:?}"),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// E — the hand-in pair
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:276-280`, fixture task 6 — the whole of item E in one assertion pair.
#[tokio::test]
async fn a_hand_in_applies_once_the_quest_is_complete_and_finishes_once_it_is_turned_in() {
    let profile = lower_against(
        &guide("step\n    .goto 1439,36.634,46.250\n    .turnin 983"),
        &world_knowing(&[983]),
    )
    .await;

    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::QuestComplete { id: 983 }),
        "got: {:?}",
        profile.tasks[0]
    );
    assert_eq!(
        profile.tasks[0].complete_when,
        Some(Predicate::QuestTurnedIn { id: 983 }),
        "got: {:?}",
        profile.tasks[0]
    );
}

/// The same discipline `quest_log_gate` already follows: derive only where the author was silent.
///
/// A step that both works an objective and hands the quest in has said what finishes it — the
/// objective — and the derived `QuestTurnedIn` must not replace it. `applies_when` follows the
/// completion it belongs to, so this task keeps the `QuestInLog` gate its objective implies rather
/// than the `QuestComplete` a hand-in would.
#[tokio::test]
async fn an_authored_completion_is_not_replaced_by_the_hand_in_pair() {
    let profile = lower_against(
        &guide("step\n    .complete 983,1\n    .turnin 983"),
        &world_knowing(&[983]),
    )
    .await;

    assert_eq!(
        profile.tasks[0].complete_when,
        Some(Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 1
        }),
        "got: {:?}",
        profile.tasks[0]
    );
    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::QuestInLog { id: 983 }),
        "got: {:?}",
        profile.tasks[0]
    );
}

/// An authored `.isOnQuest` is the author saying something the derivation cannot know, and it wins
/// the `applies_when` slot outright — while the hand-in still supplies the completion, because
/// nothing was authored there.
///
/// This is the case that proves the two halves are **derived** together but not **decided**
/// together: an authored gate does not suppress the derived completion, it only occupies the slot
/// it was written for.
#[tokio::test]
async fn an_authored_gate_keeps_its_slot_and_the_hand_in_still_supplies_the_completion() {
    let profile = lower_against(
        &guide("step\n    .isOnQuest 984\n    .turnin 983"),
        &world_knowing(&[983]),
    )
    .await;

    assert_eq!(
        profile.tasks[0].applies_when,
        Some(Predicate::QuestInLog { id: 984 }),
        "the author's own gate is the whole gate; got: {:?}",
        profile.tasks[0]
    );
    assert_eq!(
        profile.tasks[0].complete_when,
        Some(Predicate::QuestTurnedIn { id: 983 }),
        "got: {:?}",
        profile.tasks[0]
    );
}

/// 540 corpus tasks hand in more than one quest and the fixture has none, so this pins a **refusal**
/// and names what it refused.
///
/// `complete_when` had an unambiguous answer — `And` of both `QuestTurnedIn`s, since the step is
/// finished when both are handed in. `applies_when` had none: `And` of both `QuestComplete`s stalls
/// the whole hub when one of the two quests was never picked up, and `Or` of them starts the task
/// with a hand-in that is not yet possible *and* puts a disjunction into `tags_used` that no author
/// wrote. Emitting the half that is answerable would split a pair this file's header says is one
/// derivation, so neither is emitted and the gap is a diagnostic instead.
#[tokio::test]
async fn a_step_handing_in_two_quests_derives_neither_half() {
    let (profile, report) = compile(
        &import_with(
            &guide("step\n    .turnin 983\n    .turnin 3524"),
            &world_knowing(&[983, 3524]),
        )
        .await,
    );

    assert_eq!(profile.tasks[0].applies_when, None, "got: {:?}", profile.tasks[0]);
    assert_eq!(profile.tasks[0].complete_when, None, "got: {:?}", profile.tasks[0]);
    assert!(
        report
            .unmapped_conditions
            .iter()
            .any(|diagnostic| diagnostic.code == "HAND_IN_PREDICATES_NOT_DERIVED"),
        "the gap must be loud rather than an absent field; got: {:?}",
        report.unmapped_conditions
    );
}

/// `#optional` is **not** a reason to withhold the pair.
///
/// 458 corpus turn-in tasks sit under an `#optional` step. `#optional` lowers to `blocking: false`,
/// which is precisely the field that says "if this never finishes, the profile still moves on" — so
/// the risk a withheld completion would be guarding against is already carried, by name, one field
/// away. Withholding here would leave those 458 tasks with no completion authority at all and buy
/// nothing.
#[tokio::test]
async fn an_optional_hand_in_still_gets_the_pair_because_blocking_already_carries_that() {
    let profile = lower_against(
        &guide("step\n#optional\n    .turnin 983"),
        &world_knowing(&[983]),
    )
    .await;

    assert!(!profile.tasks[0].blocking, "got: {:?}", profile.tasks[0]);
    assert_eq!(
        profile.tasks[0].complete_when,
        Some(Predicate::QuestTurnedIn { id: 983 }),
        "got: {:?}",
        profile.tasks[0]
    );
}

/// A step whose `.turnin` did not resolve is a step with no `Op::TurnIn`, and the derivation must
/// key on the **op**, not on the source command.
///
/// The importer degrades an unresolvable `.turnin` to an inert `Comment` (`project_builder.rs`), so
/// there is no hand-in in the artifact for the runner to perform. Deriving `QuestTurnedIn` anyway
/// would give the task a completion condition nothing in it can ever satisfy — the same defect as
/// terminating a patrol on a hand-in this artifact never performs (`kernel_task_predicates.rs`).
#[tokio::test]
async fn a_turn_in_the_world_database_could_not_resolve_derives_nothing() {
    let profile = lower(&guide("step\n    .goto 1439,36.634,46.250\n    .turnin 983")).await;

    assert_eq!(profile.tasks[0].complete_when, None, "got: {:?}", profile.tasks[0]);
    assert_eq!(profile.tasks[0].applies_when, None, "got: {:?}", profile.tasks[0]);
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// C — `terminate_on`, and the residue
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// The inheritance §5.3 already describes — "normally the linked task's completion" — now that the
/// linked task has one.
///
/// A `#completewith next` rider in front of a hand-in used to reach the empty disjunction, because
/// the hand-in step carried no `complete_when` for the rider to inherit. Item E supplies it, and the
/// rider terminates on the hand-in it is riding to.
#[tokio::test]
async fn a_rider_in_front_of_a_hand_in_terminates_on_that_hand_in() {
    let profile = lower_against(
        &guide(
            "step\n    #completewith next\n    .goto 1439,36.523,48.554\nstep\n    .goto \
             1439,36.634,46.250\n    .turnin 983",
        ),
        &world_knowing(&[983]),
    )
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::QuestTurnedIn { id: 983 },
        "got: {:?}",
        profile.tasks[0].lifetime
    );
}

/// §5.3's "the linked task's completion" read to the end of the chain rather than one hop.
///
/// A rider whose target is itself a rider has no completion of its own to inherit — but its target
/// does, transitively, because that is what `CompletionSource::LinkedTo` means: the linked task's
/// completion completes this one, and if the linked task defers in turn then the authority is
/// whatever it defers to. Stopping at one hop left 43 corpus tasks on the empty disjunction while a
/// real completion sat two links away.
#[tokio::test]
async fn a_rider_pointing_at_another_rider_inherits_the_completion_at_the_end_of_the_chain() {
    let profile = lower(&guide(
        "step\n    #completewith next\n    .goto 1439,36.523,48.554\nstep\n    #completewith \
         next\n    .goto 1439,36.634,46.250\nstep\n    .complete 983,1",
    ))
    .await;

    let expected = Predicate::QuestObjective {
        id: 983,
        index: 1,
        need: 1,
    };
    assert_eq!(
        terminate_on(&profile, 1),
        &expected,
        "one hop; got: {:?}",
        profile.tasks[1].lifetime
    );
    assert_eq!(
        terminate_on(&profile, 0),
        &expected,
        "two hops; got: {:?}",
        profile.tasks[0].lifetime
    );
}

/// The guard that keeps the chain walk from being a hang.
///
/// Two steps whose `#completewith` labels name each other form a cycle. `resolve_completion` refuses
/// only the *self*-link, so this pair is constructible, and a walk without a visited set would
/// follow it forever. Neither task authors a completion, so the chain finds none and both fall to
/// the empty disjunction — the same answer a one-hop reading gave, reached without looping.
#[tokio::test]
async fn a_cycle_of_riders_terminates_the_walk_instead_of_the_compiler() {
    let profile = lower(&guide(
        "step\n    #label one\n    #completewith two\n    .goto 1439,36.523,48.554\nstep\n    \
         #label two\n    #completewith one\n    .goto 1439,36.634,46.250",
    ))
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::Or(Vec::new()),
        "got: {:?}",
        profile.tasks[0].lifetime
    );
    assert_eq!(
        terminate_on(&profile, 1),
        &Predicate::Or(Vec::new()),
        "got: {:?}",
        profile.tasks[1].lifetime
    );
}

/// **The residue, pinned deliberately.** Two walking steps, the first riding along with the second,
/// and no completion command anywhere in the guide.
///
/// This is a real authoring shape — 894 corpus tasks are a `#completewith` rider whose whole content
/// is movement and whose link chain ends without a completion — and there is nothing to derive from
/// it. The guide states no termination condition, so the artifact says so: `Or([])` is never
/// satisfiable, and §5.3's second route, the profile cursor passing the task, still ends it.
///
/// The empty **conjunction** is the alternative that must never be emitted here: `And([])` is
/// vacuously true and would terminate the task on the tick it started. An invented predicate is
/// worse than either, because a plausible wrong one is indistinguishable from a right one at every
/// later stage. The diagnostic is what keeps this from being a silent degeneracy.
#[tokio::test]
async fn a_rider_whose_chain_states_no_completion_keeps_the_never_satisfiable_disjunction() {
    let (profile, report) = lower_with_report(&guide(
        "step\n    #completewith next\n    .goto 1439,36.523,48.554\nstep\n    .goto \
         1439,36.634,46.250",
    ))
    .await;

    assert_eq!(
        terminate_on(&profile, 0),
        &Predicate::Or(Vec::new()),
        "got: {:?}",
        profile.tasks[0].lifetime
    );
    assert!(
        report
            .unmapped_conditions
            .iter()
            .any(|diagnostic| diagnostic.code == "BACKGROUND_WITHOUT_TERMINATION"),
        "got: {:?}",
        report.unmapped_conditions
    );
}
