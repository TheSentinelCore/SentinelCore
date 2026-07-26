//! Item D — `Task::unknown_policy`, chosen per task instead of stamped `Defer { 60 }` on all of
//! them.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.1.2 (the tri-state requirement and the policy
//! table), §7.1 (`UnknownPolicy`), §9 item 25 (the magnitudes), and §7.3.3's worked example — whose
//! fixture, `shared/tests/fixtures/adr07_worked_example.json`, is the **only** place in the
//! repository that shows more than one policy on one profile.
//!
//! # The four witnesses, and the rule they force
//!
//! The fixture's seven tasks carry four distinct values, and they are the entire evidence base:
//!
//! | task | source | ops | `complete_when` | policy |
//! |---|---|---|---|---|
//! | 0 | `A-11-23.lua:211-237` | `Travel` | `QuestObjective 983` | `Defer { 60 }` |
//! | 1 | `:238-242` | `Travel` | `QuestObjective 3524` | `Defer { 60 }` |
//! | 2 | `:243-260` | `Travel`, `UseItem 7586` | `QuestObjective 2118` | `Defer { 60 }` |
//! | 3 | `:261-264` | `Travel` | `QuestObjective 984` | `Defer { 60 }` |
//! | 4 | `:265-271` | — | `XpAtLeast { 10, 6760 }` | `TreatFalse` |
//! | 5 | `:272-275` | — | `InArea { 442, SubArea }` | `Defer { 30 }` |
//! | 6 | `:276-280` | `Travel`, `TurnIn 983` | `QuestTurnedIn 983` | `Block` |
//!
//! Read in that order the rule is about **what the task does** and **what its completion measures**,
//! never about where the task sits:
//!
//! 1. **`Block` — the task performs something irreversible.** §5.1.2's own table states this
//!    default verbatim: "`complete_when` on any task with a `DELEGATE` or irreversible op (turn-in,
//!    abandon, destroy, deathskip)". Task 6 hands quest 983 in. A hand-in fired on a predicate that
//!    read `Unknown` cannot be taken back, and there is no reading of the quest log that makes
//!    guessing cheaper than stopping and saying so.
//! 2. **`TreatFalse` — the completion can only rise, so re-doing the work is free.** §5.1.2 admits
//!    `Treat(False)` only where "the work is idempotent". Task 4's completion is total experience,
//!    which in TBC never decreases: there is no de-levelling and no XP loss. An `Unknown` read
//!    therefore costs one more grind tick and the threshold is *closer* than it was, never further.
//! 3. **`Defer` — everything else**, which is §5.1.2's stated default for `complete_when`, and the
//!    value the artifact's own `defaults` block declares.
//!
//! # The negative that keeps rule 2 from swallowing rules 1 and 3
//!
//! A `QuestObjective` counter looks monotone and is not, and tasks 0-3 are the four witnesses that
//! it must not take the `TreatFalse` arm. The counter exists **only while the quest is in the log**
//! — before the quest is accepted there is nothing to read, and after the hand-in the objective is
//! gone. `Unknown -> false -> "not complete" -> redo the step` on a farm whose quest was already
//! turned in is precisely the failure mode §5.1.2 exists to kill, quoted in that section's last
//! line. So "the number only goes up" is not the test; "the reading cannot silently disappear" is,
//! and only a player statistic satisfies it.
//!
//! Task 2 is the second negative, and a sharper one: it consumes `Tharnariun's Hope` (`.use 7586`),
//! an item the guide itself warns is unrecoverable — "You can waste the trap and make the quest
//! impossible to complete!" (`A-11-23.lua:257`). The fixture still gives it `Defer { 60 }`, not
//! `Block`. So `Op::UseItem` is **not** in the irreversible set, and the set is exactly §5.1.2's
//! four named kinds plus `Delegate`, not a judgement about what an op might cost.
//!
//! # WHAT THIS RULE CANNOT SEE
//!
//! * **Why 30 rather than 60.** It cannot see it, and neither can the corpus. §9 item 25 already
//!   records `budget_ticks: 60` as a magnitude that "appear[s] only inside §7.3.3's listing" and is
//!   stated in no section of the ADR; 30 is in exactly the same position, one line further down the
//!   same listing. RestedXP has no notion of an escalation budget, so **no** number of corpus
//!   measurements can produce either value. What the fixture does show is a *relation*: its one
//!   ride-along — the only task whose completion authority is another task — carries a **smaller**
//!   budget than every own-predicate task. That relation is what is encoded, with the two witnessed
//!   magnitudes as its endpoints. It is unstated and defaulted, and calling it derived would be a
//!   fabrication.
//! * **Whether a ride-along deserves a smaller budget at all.** One witness, and its two candidate
//!   causes are inseparable on it: task 5 is the only `CompletionSource::LinkedTo` *and* the only
//!   `Background` holding no channels. `LinkedTo` is the more primitive of the two — it is what
//!   `lower_lifetime` reads to make the rider channel-less in the first place — so it is what the
//!   rule keys on. A second witness that separated them would settle it; the corpus has none,
//!   because both properties come from the same directive.
//! * **`Abandon`, `DestroyItem` and `Delegate`.** All three are in the irreversible set and none is
//!   reachable: no op lowering produces them yet (`task_graph::lower_op` emits `Accept`, `TurnIn`,
//!   `Travel` and `UseItem`). The classifier names them anyway and is exhaustive over `Op`, so a new
//!   variant is a compile error rather than a silent `Defer`, but nothing here exercises them.
//! * **`TreatTrue`.** §5.1.2: "Never a default. Requires an explicit compiler opt-in and emits a
//!   diagnostic." Nothing opts in, so the compiler never emits it and no test can.
//! * **Whether any of this is right at runtime.** Nothing here executes. Whether `Block` really
//!   surfaces a `blocked_reason` in the cockpit, and whether a `Defer` budget really escalates after
//!   its ticks, is ADR 08 behaviour.
//! * **`abort_when`.** The field is one of the three the policy governs and no lowering produces it,
//!   so every task's policy is decided against two live predicate slots rather than three.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race};
use sentinel_models::kernel::{
    Archetype, Expansion, ProfileMode, QuestId, RuntimeProfile as KernelProfile, UnknownPolicy,
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

/// A world database that knows one quest and nothing else.
///
/// Load-bearing for every `.turnin` fragment below: the importer degrades an unresolvable `.turnin`
/// to an inert `Comment`, so a client that knows nothing produces no `Op::TurnIn` and the
/// irreversible-op rule would have nothing to fire on. `finisher_entry: None` is quest 983's
/// §7.3.2-verified shape — its ender is `gameobject_involvedrelation` 17182, not a creature.
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

/// One `step` per entry, under the smallest header `parse_guide` accepts.
fn guide(steps: &str) -> String {
    format!(
        "\nRXPGuides.RegisterGuide([[\n#version 7\n#group RestedXP TBC Guide (A)\n#name 12-14 \
         Darkshore\n{steps}\n]])"
    )
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Block — the irreversible op
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:276-280` — the Buzzbox hand-in, fixture task 6.
///
/// §5.1.2's table names the turn-in first among the irreversible ops. A hand-in fired because the
/// quest log read `Unknown` cannot be undone, and the reward, the follow-up chain and the log slot
/// are all spent.
#[tokio::test]
async fn a_turn_in_blocks_rather_than_guessing_at_the_quest_log() {
    let profile = lower_against(
        &guide(
            "step\n    .goto 1439,36.634,46.250\n    .turnin 983",
        ),
        &world_knowing(983),
    )
    .await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::Block,
        "got: {:?}",
        profile.tasks[0]
    );
}

/// `A-11-23.lua:243-260`, fixture task 2 — and the sharpest negative in this file.
///
/// The step consumes `Tharnariun's Hope`, which the guide itself warns is unrecoverable: "You can
/// waste the trap and make the quest impossible to complete!" (`:257`). The fixture still gives it
/// `Defer { 60 }`. The irreversible set is §5.1.2's four named op kinds plus `Delegate`, not an
/// open-ended judgement about consequences — otherwise `Op::UseItem` (1,678 corpus uses) would take
/// 1,678 tasks off the default for a reason the ADR never states.
#[tokio::test]
async fn consuming_a_quest_item_is_not_an_irreversible_op() {
    let profile = lower(&guide(
        "step\n    .goto 1439,38.226,52.780,0\n    .complete 2118,1\n    .use 7586",
    ))
    .await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 60 },
        "got: {:?}",
        profile.tasks[0]
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TreatFalse — the monotone completion
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:269-271` — `.xp 10+6760 >> Grind to 6760+/7600xp`, fixture task 4.
///
/// Total experience never decreases in TBC. An `Unknown` read means one more grind tick and a
/// threshold that is closer, never further — the definition of §5.1.2's "safe only when the work is
/// idempotent".
#[tokio::test]
async fn an_experience_threshold_may_redo_its_work_because_experience_only_rises() {
    let profile = lower(&guide("step\n#optional\n    .xp 10+6760")).await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::TreatFalse,
        "got: {:?}",
        profile.tasks[0]
    );
}

/// The same rule at the other precision: `.xp 24` is a bare level floor and lowers to
/// `LevelAtLeast`, which is the same statistic read coarsely (`kernel_authored_predicates.rs`).
/// Character level is monotone for exactly the reason experience is, so the two must not disagree.
#[tokio::test]
async fn a_bare_level_floor_is_monotone_for_the_same_reason() {
    let profile = lower(&guide("step\n#optional\n    .xp 24")).await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::TreatFalse,
        "got: {:?}",
        profile.tasks[0]
    );
}

/// `A-11-23.lua:211-237` and its three siblings, fixture tasks 0-3 — **the negative that defines
/// the `TreatFalse` arm.**
///
/// An objective counter rises too, and it is still not monotone in the sense that matters: it
/// exists only while the quest is in the log. Once 983 is handed in the objective is gone, the read
/// is `Unknown`, and `TreatFalse` would send the runner back to farm six more Crawler Legs for a
/// quest it has already finished. That is `Unknown -> false -> redo the step`, the failure §5.1.2
/// closes with.
#[tokio::test]
async fn an_objective_counter_defers_because_it_disappears_on_hand_in() {
    let profile = lower(&guide(
        "step\n    .goto 1439,36.051,44.757,0\n    .complete 983,1\n    .isOnQuest 983",
    ))
    .await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 60 },
        "got: {:?}",
        profile.tasks[0]
    );
}

/// Precedence, stated as a test rather than left to the order of two `if`s.
///
/// A step that grinds experience **and** hands a quest in satisfies both rules. Irreversibility
/// wins: the cost of guessing wrong on `TreatFalse` is one wasted grind tick, and the cost of
/// guessing wrong on the hand-in is the hand-in. Synthetic — no corpus step pairs `.xp` with
/// `.turnin` — and here because the alternative is a rule whose answer depends on which branch was
/// written first.
#[tokio::test]
async fn an_irreversible_op_outranks_a_monotone_completion() {
    let profile = lower_against(
        &guide("step\n#optional\n    .xp 10+6760\n    .turnin 983"),
        &world_knowing(983),
    )
    .await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::Block,
        "got: {:?}",
        profile.tasks[0]
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Defer — the default, and the one witnessed departure from its magnitude
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:272-275` — the `#completewith next` rider, fixture task 5, the profile's **only**
/// `Defer { 30 }`.
///
/// See this file's header: 30 is unstated and defaulted, exactly as §9 item 25 already says of 60.
/// What is witnessed is the relation — the one task whose completion authority is another task
/// carries a smaller budget than every task that decides for itself — and that relation is what is
/// encoded, with the fixture's two magnitudes as its endpoints.
#[tokio::test]
async fn a_ride_along_takes_a_smaller_budget_than_a_task_that_decides_for_itself() {
    let profile = lower(&guide(
        "step\n    #completewith next\n    .subzone 442\nstep\n    .goto 1439,36.634,46.250",
    ))
    .await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 30 },
        "got: {:?}",
        profile.tasks[0]
    );
    assert_eq!(
        profile.tasks[1].unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 60 },
        "the task the rider links to decides for itself; got: {:?}",
        profile.tasks[1]
    );
}

/// Precedence again, and the arm that keeps the budget rule from overriding safety: a rider that
/// hands a quest in is still handing a quest in. 35 corpus tasks are in exactly this position — a
/// `#completewith` step carrying an `Op::TurnIn` — so this is a measured shape, not a hypothetical.
#[tokio::test]
async fn a_ride_along_that_hands_a_quest_in_still_blocks() {
    let profile = lower_against(
        &guide("step\n    #completewith next\n    .turnin 983\nstep\n    .goto 1439,36.634,46.250"),
        &world_knowing(983),
    )
    .await;

    assert_eq!(
        profile.tasks[0].unknown_policy,
        UnknownPolicy::Block,
        "got: {:?}",
        profile.tasks[0]
    );
}

/// The plain case, and the one that pins the per-task value against the profile-level declaration.
///
/// `defaults.unknown_policy` is part of the artifact (§7.2's root `required` array). A task that
/// departs from nothing must carry the value the same artifact declares as its default, or the two
/// halves of §5.1.2 disagree inside one file.
#[tokio::test]
async fn an_ordinary_task_carries_the_policy_the_artifact_declares_as_its_default() {
    let profile = lower(&guide("step\n    .goto 1439,36.371,50.920\n    .complete 3524,1")).await;

    assert_eq!(
        profile.defaults.unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 60 },
        "the profile-level default"
    );
    assert_eq!(
        profile.tasks[0].unknown_policy, profile.defaults.unknown_policy,
        "got: {:?}",
        profile.tasks[0]
    );
}

/// The rule is over task **content**, never over task **index**.
///
/// The same three steps in the opposite order must produce the same three policies, permuted with
/// them. A rule that keyed on position — "the last task blocks", "task 4 is the grind" — reproduces
/// the fixture exactly and is wrong on every other guide in the corpus, and nothing else in this
/// file would notice.
#[tokio::test]
async fn reordering_the_steps_permutes_the_policies_with_them() {
    let forwards = lower_against(
        &guide(
            "step\n#optional\n    .xp 10+6760\nstep\n    .goto 1439,36.634,46.250\n    .turnin \
             983\nstep\n    .goto 1439,36.371,50.920\n    .complete 3524,1",
        ),
        &world_knowing(983),
    )
    .await;
    let backwards = lower_against(
        &guide(
            "step\n    .goto 1439,36.371,50.920\n    .complete 3524,1\nstep\n    .goto \
             1439,36.634,46.250\n    .turnin 983\nstep\n#optional\n    .xp 10+6760",
        ),
        &world_knowing(983),
    )
    .await;

    let policies = |profile: &KernelProfile| -> Vec<UnknownPolicy> {
        profile.tasks.iter().map(|task| task.unknown_policy).collect()
    };

    assert_eq!(
        policies(&forwards),
        vec![
            UnknownPolicy::TreatFalse,
            UnknownPolicy::Block,
            UnknownPolicy::Defer { budget_ticks: 60 },
        ],
        "got: {forwards:?}"
    );
    assert_eq!(
        policies(&backwards),
        vec![
            UnknownPolicy::Defer { budget_ticks: 60 },
            UnknownPolicy::Block,
            UnknownPolicy::TreatFalse,
        ],
        "got: {backwards:?}"
    );
}
