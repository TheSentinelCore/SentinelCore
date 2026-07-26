//! Three things the artifact must say about itself: **where a task came from**, **which quests it
//! serves**, and **which tags it uses** (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.4, §7.1, §7.3.3).
//!
//! # `source` — provenance the whole point of which is to be openable
//!
//! §7.1 calls `SourceSpan` "the one thing worth carrying across the authoring/runtime boundary, so
//! a runtime failure points at a corpus line", and costs it at ~20 bytes per task. A span derived
//! from the step's `#directive` lines alone reports `A-11-23.lua:211-237` as `213-213` — the
//! `#label` line — which points a reader at a line that is *in* the step and is not the step.
//! §7.3.3's eight spans tile `211-280` without a gap.
//!
//! # `serves_quests` — a census, and the tension with §7.1's annotation
//!
//! §7.1 annotates the field "`.requires quest,<id>`" (445 uses) and warns that it is distinct from
//! the `#requires` *metadata* tag, which lowers to `deps`. That warning is kept — conflating the
//! two is silent and wrong — but the annotation alone cannot produce §7.3.3's values: **the
//! excerpt `A-11-23.lua:211-280` contains no `.requires` command at all**, and §7.3.3 still gives
//! its tasks `[983]`, `[3524]`, `[2118]`, `[984]`, `[2118, 983]` and `[983]`. Those are exactly the
//! quest ids each task's own ops and predicates name, in first-seen order — including the *pair*,
//! in the printed order, on the multi-dependency task. So the field is lowered as a **census over
//! the task**, of which an explicit `.requires quest,<id>` is one more reference rather than the
//! only one. §4.1 gives the purpose that settles it: whole-chain pruning when a quest is
//! unobtainable, which needs every task that touches the quest and not only the ones that annotate
//! it.
//!
//! # `tags_used` — computed, never transcribed
//!
//! §5.4 (C4) makes the artifact fail-closed: a loader refuses a tag it does not implement. §5.10
//! states the consequence in both directions — a **spurious** tag makes a fail-closed kernel refuse
//! an artifact it could have run, and a **missing** tag lets the check pass on an artifact the
//! kernel cannot fully evaluate, which defeats the check entirely. A hand-maintained list is wrong
//! the first time a lowering changes; §7.3.3's own list was wrong in both directions at once (four
//! tags used by no task, one used by task 7 and absent) until the R1 audit recomputed it.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **Whether the emitted order of `tags_used` is anyone's preference.** The field is a *set*.
//!   These tests assert its contents; the sorted spelling is asserted only as being stable, not as
//!   being the one §7.3.3 printed (it is not — §7.3.3 groups ops before predicates and orders
//!   neither).
//! * **A `.requires quest,<id>` command.** `ProjectBuilder` does not lower one, so the census below
//!   is exercised only through ops and predicates.
//! * **Editor-authored projects.** Every fixture here comes through the importer, so every
//!   operation carries a source span. The `None` fallback is exercised by
//!   `an_operation_with_no_authored_span_reports_zero_rather_than_line_one`.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Operation, Project, Race};
use sentinel_models::kernel::{
    Archetype, Expansion, ProfileMode, QuestId, RuntimeProfile as KernelProfile, SourceSpan,
};
use sentinel_queryclient::{MemoryQueryClient, QuestDetail};

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Answers `1` for every objective, and names the one item objective §7.3.2 verified.
///
/// `(983, 1) -> 5385` is `quest_template.ReqItemId1` for `Buzzbox 827` — the Crawler Leg the guide
/// author's own comment corroborates (`A-11-23.lua:234`, `--Crawler Leg (6)`). Every other
/// objective answers `None`, which is "this objective is not an item" and not "the database could
/// not answer": a provider that cannot answer has already failed the compile through
/// `objective_need`.
struct AnswersOne;

impl QuestMeta for AnswersOne {
    fn objective_need(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        Some(1)
    }

    fn objective_item(&self, quest: QuestId, index: u8) -> Option<u32> {
        match (quest, index) {
            (983, 1) => Some(5385),
            _ => None,
        }
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

/// Quest 983 resolves so `.accept` / `.turnin` become real actions rather than inert comments.
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

fn compile(project: &Project) -> (KernelProfile, CompileReport) {
    Compiler::compile_kernel(project, &night_elf_hunter(), &AnswersOne)
        .unwrap_or_else(|err| panic!("`compile_kernel` must not refuse the fragment, got: {err:?}"))
}

async fn lower(guide: &str) -> (KernelProfile, CompileReport) {
    compile(&import(guide).await)
}

/// A two-step fragment whose line numbers are stated here so an assertion can cite them.
///
/// Line 1 is `RXPGuides.RegisterGuide([[`; the first `step` marker is line 3 and the second is
/// line 8. The trailing `--` comment on line 7 belongs to the first step and is its last line —
/// the `A-11-23.lua:268` shape, where the author's `--XXREQ` note is the last thing in the step.
const FRAGMENT: &str = "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    #label BuzzBox1
    .goto 1439,36.634,46.250
    .turnin 983
-- author's note, still part of this step
step
    .goto 1439,36.371,50.920
    .complete 3524,1
]])";

/// `FRAGMENT`'s two step spans, as §7.3.3 would print them.
const FIRST_SPAN: (u32, u32) = (3, 7);
const SECOND_SPAN: (u32, u32) = (8, 10);

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// source
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_task_spans_the_whole_step_it_was_authored_from() {
    let (profile, _report) = lower(FRAGMENT).await;

    let spans: Vec<(&str, u32, u32)> = profile
        .tasks
        .iter()
        .map(|task| {
            (
                task.source.file.as_str(),
                task.source.line_start,
                task.source.line_end,
            )
        })
        .collect();

    assert_eq!(
        spans,
        vec![
            ("A-11-23.lua", FIRST_SPAN.0, FIRST_SPAN.1),
            ("A-11-23.lua", SECOND_SPAN.0, SECOND_SPAN.1),
        ],
        "§7.1 carries `SourceSpan` so a runtime failure points at a corpus line, and §7.3.3's eight \
         spans tile `A-11-23.lua:211-280` without a gap. A span taken from the step's `#directive` \
         entries reports the first step here as `4-4` — the `#label` line — which is inside the \
         step and is not the step, and reports a step with no directives at all as `0-0`. got: \
         {spans:?}"
    );
}

#[tokio::test]
async fn an_operation_with_no_authored_span_reports_zero_rather_than_line_one() {
    // An editor-authored operation: never parsed from a guide, so it has no line of its own.
    let mut project = import(FRAGMENT).await;
    let mut authored = Operation::new("hand authored");
    authored.actions = project.operations[0].actions.clone();
    project.operations = vec![authored];

    let (profile, _report) = compile(&project);
    let Some(task) = profile.tasks.first() else {
        panic!("one operation lowers to one task, got: {:?}", profile.tasks)
    };

    assert_eq!(
        task.source,
        SourceSpan { file: "A-11-23.lua".to_string(), line_start: 0, line_end: 0 },
        "an operation the editor created has no guide line, though the project it lives in still \
         has a source file. `0` is the admission; `1` would point a reader at a line that exists \
         and is not the one they want, which is the failure mode `SourceSpan` exists to prevent. \
         got: {:?}",
        task.source
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// serves_quests
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_task_serves_every_quest_its_ops_and_predicates_name() {
    let (profile, _report) = lower(FRAGMENT).await;

    let served: Vec<&[QuestId]> = profile
        .tasks
        .iter()
        .map(|task| task.serves_quests.as_slice())
        .collect();

    assert_eq!(
        served,
        vec![[983].as_slice(), [3524].as_slice()],
        "§7.3.3 gives its turn-in task `serves_quests: [983]` and its `.complete 3524,1` task \
         `[3524]`, and the excerpt contains no `.requires quest,<id>` command anywhere — so the \
         field is the census of quest ids the task's own ops and predicates name. §4.1's purpose \
         settles it: whole-chain pruning when a quest is unobtainable needs every task that touches \
         the quest, not only the ones that annotate it. got: {served:?}"
    );
}

#[tokio::test]
async fn a_task_serving_two_quests_lists_both_in_the_order_it_names_them() {
    // Two objectives on one step: §7.3.3 task 4's shape, whose `complete_when` is an `And` over one
    // objective per predecessor and whose `serves_quests` is `[2118, 983]` — plural, in that order,
    // and deliberately not sorted.
    let (profile, _report) = lower(
        "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    .goto 1439,36.634,46.250
    .complete 2118,1
    .complete 983,1
]])",
    )
    .await;

    let Some(task) = profile.tasks.first() else {
        panic!("the fragment authors one step, got: {:?}", profile.tasks)
    };
    assert_eq!(
        task.serves_quests,
        vec![2118, 983],
        "the multi-dependency task of §7.3.3 lists both quests, in the order its `And` names them. \
         A sorted list would print `[983, 2118]` and lose the correspondence with the predicate; a \
         deduplicated-but-unordered one would be unstable across compiles. got: {:?}",
        task.serves_quests
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// loot_filter
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn an_item_objective_puts_the_item_it_needs_in_the_loot_filter() {
    let (profile, _report) = lower(
        "\
RXPGuides.RegisterGuide([[
#name 10-14 Darkshore
step
    .goto 1439,36.051,44.757,0
    .complete 983,1 --Crawler Leg (6)
step
    .goto 1439,36.371,50.920
    .complete 2118,1 --Rabid Thistle Bear Captured (1)
]])",
    )
    .await;

    let filters: Vec<Vec<(u32, Option<QuestId>)>> = profile
        .tasks
        .iter()
        .map(|task| {
            task.loot_filter
                .iter()
                .map(|rule| (rule.item, rule.for_quest))
                .collect()
        })
        .collect();

    assert_eq!(
        filters,
        vec![vec![(5385, Some(983))], vec![]],
        "§7.3.3 task 0 carries `loot_filter: [{{ item: 5385, for_quest: 983 }}]` and its only \
         relevant source line is `.complete 983,1`; §7.3.2 verifies `quest_template` row 983 as \
         `ReqItemId1 = 5385, ReqItemCount1 = 6`, matching the author's own `--Crawler Leg (6)`. A \
         task working an objective whose requirement is an item has to keep that item or the \
         objective can never advance. Quest 2118's objective is a creature (`Captured Rabid \
         Thistle Bear`, §7.3.2), so it contributes nothing — an empty filter there is the right \
         answer, not a lookup that failed. got: {filters:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// tags_used
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Every op and predicate tag the artifact actually uses, walked from the **serialized** form.
///
/// The wire form is the stricter reading of §5.4: `tags_used` is a list of wire tags, so a census
/// taken from Rust variant names could agree with the model while disagreeing with what a Lua
/// loader sees. Deliberately never reads `tags_used` itself — a census that consulted the list to
/// check the list would prove nothing.
fn census(profile: &KernelProfile) -> std::collections::BTreeSet<String> {
    let value = serde_json::to_value(profile).expect("a kernel artifact serialises");
    let mut observed = std::collections::BTreeSet::new();
    let Some(tasks) = value.get("tasks").and_then(serde_json::Value::as_array) else {
        panic!("a kernel artifact carries a `tasks` array, got: {value:?}")
    };
    for task in tasks {
        for op in task
            .get("ops")
            .and_then(serde_json::Value::as_array)
            .into_iter()
            .flatten()
        {
            observed.insert(tag_of(op));
        }
        if let Some(terminate_on) = task
            .get("lifetime")
            .and_then(|lifetime| lifetime.get("payload"))
            .and_then(|payload| payload.get("terminate_on"))
        {
            collect(terminate_on, &mut observed);
        }
        for slot in ["applies_when", "complete_when", "abort_when"] {
            match task.get(slot) {
                Some(serde_json::Value::Null) | None => {}
                Some(predicate) => collect(predicate, &mut observed),
            }
        }
    }
    observed
}

fn tag_of(value: &serde_json::Value) -> String {
    let Some(tag) = value.get("type").and_then(serde_json::Value::as_str) else {
        panic!("ADR 07 §5.4 (C4): every enum the kernel dispatches on is adjacently tagged with `type`, got: {value:?}")
    };
    tag.to_owned()
}

fn collect(predicate: &serde_json::Value, out: &mut std::collections::BTreeSet<String>) {
    let tag = tag_of(predicate);
    out.insert(tag.clone());
    match (tag.as_str(), predicate.get("payload")) {
        ("And" | "Or", Some(serde_json::Value::Array(children))) => {
            for child in children {
                collect(child, out);
            }
        }
        ("Not", Some(child)) => collect(child, out),
        _ => {}
    }
}

#[tokio::test]
async fn tags_used_is_computed_from_the_artifact_and_is_wrong_in_neither_direction() {
    let (profile, _report) = lower(FRAGMENT).await;

    let declared: std::collections::BTreeSet<String> =
        profile.tags_used.iter().cloned().collect();
    let observed = census(&profile);

    let missing: Vec<&String> = observed.difference(&declared).collect();
    let spurious: Vec<&String> = declared.difference(&observed).collect();
    assert!(
        missing.is_empty() && spurious.is_empty(),
        "ADR 07 §5.4 (C4) / §5.10: `tags_used` must be exactly the tag set the artifact uses.\n  \
         used but not declared: {missing:?}\n  declared but not used : {spurious:?}\n\
         A missing tag lets a fail-closed loader admit an artifact it cannot evaluate; a spurious \
         one makes it refuse an artifact it could have run."
    );

    assert!(
        !profile.tags_used.is_empty(),
        "the fragment lowers travel ops and quest predicates, so an empty census means the field \
         was never computed rather than that nothing is used. got: {:?}",
        profile.tags_used
    );
}

#[tokio::test]
async fn tags_used_is_emitted_in_one_canonical_order() {
    let (profile, _report) = lower(FRAGMENT).await;

    let mut sorted = profile.tags_used.clone();
    sorted.sort();
    assert_eq!(
        profile.tags_used, sorted,
        "the census is a set, and a set has to be *spelled* somehow. Sorted is the only spelling \
         that does not move when an unrelated task is added, reordered or elided — which is what \
         R3's content digest over the emitted bytes will depend on. got: {:?}",
        profile.tags_used
    );

    let mut deduplicated = sorted.clone();
    deduplicated.dedup();
    assert_eq!(
        profile.tags_used, deduplicated,
        "a tag used by two tasks is still one tag. got: {:?}",
        profile.tags_used
    );
}
