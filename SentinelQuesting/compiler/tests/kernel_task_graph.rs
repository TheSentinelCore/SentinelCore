//! RED for **D5, task-graph lowering**: `#label`, `#requires`, `#completewith`, `#sticky` and
//! `#optional` become `Task::deps`, `Task::completion`, `Task::lifetime` and `Task::blocking`, or
//! they are not lowered at all.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.3 "Concurrency", §7.1 "Task", §7.2 (the `band`
//! bound), and §7.3.3 "Worked example" — whose fixture, `shared/tests/fixtures/
//! adr07_worked_example.json`, is lowered from `A-11-23.lua:211-280` and is the only place in the
//! repository that states what a lowered `Lifetime::Background` actually looks like. Corpus:
//! `sentinel/docs/adr/restedxp guides`. Every test below quotes the guide lines it lowers, with
//! file and line, so the expected value is re-derivable from the source rather than trusted.
//!
//! # What `compile_kernel` does today, measured, so the RED is not mistaken for a mystery
//!
//! `compiler/src/lib.rs::assemble_tasks` resolves `#requires` into `deps` and `#optional` into
//! `blocking`, and hardcodes `lifetime: Lifetime::Exclusive` and
//! `completion: CompletionSource::OwnPredicate` on **every** task. `Operation::complete_with` —
//! the carrier the importer already fills, 5,469 corpus uses — is read by nothing in this crate,
//! and `Operation::sticky` — 311 uses — is read by nothing either. So the four `completewith`
//! tests, the two `sticky`/`Background` tests and the band-census test below fail on the value,
//! not on the shape; they are asserting a lowering that has no code yet.
//!
//! Three tests are **already green** and are here as regression guards on work D5 must not undo,
//! because the natural D5 implementation rewrites exactly the function that produces them:
//! `two_stacked_requires_lines_become_two_deps_because_the_stacking_is_an_and`,
//! `a_faction_exclusive_requires_pair_collapses_to_one_satisfiable_dep` and
//! `the_xxreq_fold_still_yields_a_multi_entry_deps_on_the_successor`. They are named as guards
//! here rather than left implicit, so a reader does not mistake a passing test for an unwritten one.
//!
//! # The three facts these tests are built on, measured over the corpus
//!
//! * **`#label` is a compiler symbol table and nothing else.** 2,581 occurrences, 1,560 distinct
//!   values, and resolution is scoped to the **guide block** (277 blocks, one `Project` per
//!   `RegisterGuide`) rather than to the file — 768 names are defined in more than one file. Four
//!   values contain spaces and four carry a `<<` tail, so a whitespace tokeniser truncates both and
//!   fabricates a dangling edge. None of that vocabulary may reach the artifact: the kernel resolves
//!   by `TaskId`, and a name that survives is a name something can still look up at runtime.
//! * **`#requires` multiplicity is stacked lines, and the two stackings mean different things.**
//!   Exactly one label per line, no separator. `TBC:24728/24729` `cloth1`/`cloth2` is an AND;
//!   `TBC:91092/91093` `FlyMoongladeH << Horde` / `FlyMoongladeA << Alliance` is a
//!   faction-exclusive OR. Each entry carries its **own** gate, so resolving gates first and ANDing
//!   the survivors makes the OR collapse for a fixed archetype and needs no operator in the model.
//! * **The `#requires` graph is acyclic by construction.** All 346 resolvable edges point backward
//!   (target index < referencing index); zero forward, zero self. `the_lowered_task_graph_is_acyclic`
//!   therefore guards a future authoring change, not a present risk — see its own doc comment.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **They pin shape, not census.** Every asserted line is copied from a named corpus line, but the
//!   guide fragments are synthetic and tiny. The measured populations (2,581 `#label`, 350
//!   `#requires`, 5,469 `#completewith`, 311 `#sticky`, 3,067 `#optional`, 80 block-scope-unresolved
//!   `#completewith`, 4 unresolved `#requires`, 44 undecidable duplicate-label groups) are not
//!   re-derived. An implementation can satisfy every assertion here and still mishandle a shape that
//!   occurs only in the other 23,800 steps.
//! * **They are single-block, so resolution SCOPE is invisible.** Each fragment is one
//!   `RegisterGuide([[ ]])` block, which is exactly one `Project` and exactly one `compile_kernel`
//!   call. A lowering that resolved labels across blocks, or across files, would pass every test
//!   below. The 768 cross-file redefinitions are the population that would break it, and nothing
//!   here reaches them.
//! * **`MemoryQueryClient::new()` resolves no quests and no NPCs.** `.turnin`, `.accept` and
//!   `.subzone` therefore degrade to `Comment`/`Condition` authoring actions, and `lower_op` lowers
//!   only `AcceptQuest` and `Travel` today, so most tasks below carry zero or one `Op`. That is
//!   deliberate — these tests are about the graph between tasks, not the ops inside them — but it
//!   means **op contents are never asserted for correctness**, only counted where a count
//!   distinguishes two candidate tasks.
//! * **`#completewith next` on the LAST surviving task has no successor, and no test covers it.**
//!   The corpus has 2,681 `next` links and this file exercises the ordinary case only. A lowering
//!   that panicked, or silently emitted `LinkedTo(self)`, at the end of a guide would pass here.
//!   `the_lowered_task_graph_is_acyclic` would catch `LinkedTo(self)` only if such a task were
//!   present in its fragment, and it is not.
//! * **They cannot see the runtime.** Whether a `Background` task actually yields its channels to a
//!   foreground lease, whether a `LinkedTo` target's terminal state is really inherited, and whether
//!   band 34 outranks band 30 in the live scheduler are all ADR 08 kernel behaviour. Nothing here
//!   executes anything.
//! * **`terminate_on` is asserted only in its *derived* relationship** — see
//!   `a_background_terminate_on_is_derived_from_the_task_not_invented`, which is deliberately
//!   coupled to `.complete` predicate baking and says so.
//! * **The band ORDERING rule is untested.** §5.3 says the band is "offset by task order so two
//!   sticky tasks cannot deadlock"; §7.3.3 shows 34 then 35 for two stickies and 30 for a
//!   ride-along. `every_emitted_background_band_sits_inside_the_goal_band` asserts only the range.
//!   A lowering that gave every `Background` band 30 would pass it, and would reintroduce exactly
//!   the deadlock the offset exists to prevent.
//!
//! # Surface these tests require of D5
//!
//! No new types. Every type used below already exists; what does not exist is the code that
//! produces the values. Concretely, `Compiler::compile_kernel` must additionally:
//!
//! ```ignore
//! // `Operation::complete_with: Vec<Gated<CompleteWithTarget>>`  (already carried by the importer)
//! //   CompleteWithTarget::Next      -> CompletionSource::LinkedTo(<successor task id>)
//! //   CompleteWithTarget::Label(l)  -> CompletionSource::LinkedTo(<task defining l>)
//! //   unresolved                    -> CompletionSource::OwnPredicate + Severity::Error diagnostic
//! //   any of the above              -> Lifetime::Background { channels: vec![], band, .. }
//! //                                    (§7.3.3 task 6: a ride-along holds nothing)
//! //
//! // `Operation::sticky: bool`                                   (already carried by the importer)
//! //   true -> Lifetime::Background { channels, band, terminate_on }
//! //           channels: Channel::Movement iff the task carries a movement op
//! //           band:     30..=49, offset by task order (§5.3, §7.2)
//! //
//! // `#requires` naming a label no surviving step defines
//! //   -> edge dropped + Severity::Error diagnostic (today: Severity::Warning)
//! ```

use std::collections::{BTreeSet, HashMap, HashSet};

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{Class, Faction, Project, Race, Severity};
use sentinel_models::kernel::{
    Archetype, Channel, CompletionSource, Expansion, Lifetime, ProfileMode, QuestId,
    RuntimeProfile as KernelProfile, TaskId,
};
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A `QuestMeta` that answers every objective with `1`.
///
/// Not `SilentMeta` (which panics, as `kernel_archetype_gates.rs` uses): the `#sticky` tests below
/// deliberately drive `complete_when`, which is a baked predicate, so a provider that refuses to
/// answer would turn a value failure into a panic and hide which of the two is actually missing.
/// `Some(1)` is a legal answer for every `.complete <quest>,1` line quoted here.
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

/// The archetype every test varies from. Spelled out in full rather than `Default`ed: each field is
/// a compile-time gate axis, and a defaulted one is a gate nobody chose.
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

fn alliance_warrior() -> Archetype {
    base()
}

fn horde_warrior() -> Archetype {
    Archetype {
        faction: Faction::Horde,
        race: Race::Orc,
        ..base()
    }
}

fn gnome_mage() -> Archetype {
    Archetype {
        class: Class::Mage,
        race: Race::Gnome,
        ..base()
    }
}

fn gnome_warlock() -> Archetype {
    Archetype {
        class: Class::Warlock,
        race: Race::Gnome,
        ..base()
    }
}

/// Guide source → `authoring::Project`, through the real importer.
///
/// The importer path is used rather than a hand-built `Project` on purpose: `#label`'s `<<` tail
/// stripping, the `#requires` per-entry gate, and the XXREQ placeholder fold all happen there, and a
/// hand-built `Project` would let a test assert a lowering of an input the importer never produces.
async fn import(guide: &str) -> Project {
    let parsed = sentinel_importer::parse_guide(guide)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    sentinel_importer::ProjectBuilder::build(&parsed, "corpus.lua", &MemoryQueryClient::new())
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"))
}

fn compile(project: &Project, archetype: &Archetype) -> (KernelProfile, CompileReport) {
    Compiler::compile_kernel(project, archetype, &AnswersOne).unwrap_or_else(|err| {
        panic!("`compile_kernel` must not refuse a well-formed fragment, got: {err:?}")
    })
}

async fn lower(guide: &str, archetype: &Archetype) -> (KernelProfile, CompileReport) {
    let project = import(guide).await;
    compile(&project, archetype)
}

/// Every diagnostic code at `severity`, as a set — so assertions read as a predicate over the
/// collection and never as an index into it.
fn codes_at(report: &CompileReport, severity: Severity) -> BTreeSet<&str> {
    report
        .unmapped_conditions
        .iter()
        .filter(|d| d.severity == severity)
        .map(|d| d.code.as_str())
        .collect()
}

/// Whether any diagnostic in `report` has `code` and mentions `needle` anywhere.
///
/// Both halves matter: the code alone does not say *which* label was dropped, and in a guide with
/// two unresolved references a code-only assertion passes on the wrong one.
fn has_diagnostic_naming(
    report: &CompileReport,
    severity: Severity,
    code: &str,
    needle: &str,
) -> bool {
    report.unmapped_conditions.iter().any(|d| {
        d.severity == severity
            && d.code == code
            && (d.message.contains(needle) || d.entity.as_deref() == Some(needle))
    })
}

/// Every string in a serialized profile — object **keys** included.
///
/// Keys are walked, not just values, because the cheapest way to leak a symbol table into an
/// artifact is to emit it as a map keyed by label name. A value-only walk would not see it.
fn every_string(value: &serde_json::Value) -> Vec<String> {
    fn walk(value: &serde_json::Value, out: &mut Vec<String>) {
        match value {
            serde_json::Value::String(s) => out.push(s.clone()),
            serde_json::Value::Array(items) => items.iter().for_each(|item| walk(item, out)),
            serde_json::Value::Object(map) => map.iter().for_each(|(key, item)| {
                out.push(key.clone());
                walk(item, out);
            }),
            _ => {}
        }
    }
    let mut out = Vec::new();
    walk(value, &mut out);
    out
}

fn as_json(profile: &KernelProfile) -> serde_json::Value {
    serde_json::to_value(profile)
        .unwrap_or_else(|err| panic!("a compiled profile must serialize, got: {err:?}"))
}

/// The `LinkedTo` target of `task`, or a panic naming what was found instead.
fn linked_target(profile: &KernelProfile, task: TaskId) -> TaskId {
    let Some(found) = profile.tasks.get(task as usize) else {
        panic!(
            "task {task} is absent from the artifact; it holds {} tasks",
            profile.tasks.len()
        )
    };
    let CompletionSource::LinkedTo(target) = found.completion else {
        panic!(
            "task {task} must complete with the task its `#completewith` names, got: {:?}",
            found.completion
        )
    };
    target
}

/// The `Background` payload of `task`, or a panic naming what was found instead.
fn background_of(profile: &KernelProfile, task: TaskId) -> (Vec<Channel>, u8) {
    let Some(found) = profile.tasks.get(task as usize) else {
        panic!(
            "task {task} is absent from the artifact; it holds {} tasks",
            profile.tasks.len()
        )
    };
    let Lifetime::Background {
        ref channels,
        band,
        terminate_on: _,
    } = found.lifetime
    else {
        panic!(
            "task {task} must be a concurrent task, got: {:?}",
            found.lifetime
        )
    };
    (channels.clone(), band)
}

/// How many waypoints a task walks, summed over its routes.
///
/// The discriminator [`only_task_with_route_length`] uses. It counts **points**, not ops, because a
/// consecutive run of movement lines is aggregated into one `Op::Travel` carrying the whole route
/// (§5.7, `compiler/tests/kernel_route_aggregation.rs`) — so the two `.goto` lines at
/// `TBC:16258-16259` are one op with two points, and an op-count census reports `1` for both
/// candidate definitions and separates nothing.
fn route_length(task: &sentinel_models::kernel::Task) -> usize {
    task.ops
        .iter()
        .map(|op| match op {
            sentinel_models::kernel::Op::Travel { route } => route.points.len(),
            _ => 0,
        })
        .sum()
}

/// The one task in `profile`, other than `referencing`, that walks `points` waypoints — or a panic
/// listing the census.
///
/// Used where two candidate *definitions* must be told apart and the only artifact-visible
/// difference is how many movement lines survived. Fails loudly when the discriminator stops
/// discriminating rather than silently picking the first match.
///
/// **`referencing` is excluded because the step that writes `#completewith` is not a candidate for
/// what it resolves to, and it carries a `.goto` of its own.** `TBC:16240-16242` — the referencing
/// step — has one `.goto`, and so does the `step << !Mage` definition at `TBC:16263-16265`; a census
/// over *every* task therefore reports two one-point routes for a non-Mage and can name neither.
/// Excluding the referencing task is not a weakening: it cannot be its own target (a self-link is
/// refused by `compiler/src/kernel/task_graph.rs::resolve_completion`), so the ambiguity it creates
/// is spurious. The candidate set is still both definitions, which is the pair the test exists to
/// separate.
fn only_task_with_route_length(
    profile: &KernelProfile,
    points: usize,
    referencing: TaskId,
) -> TaskId {
    let matches: Vec<TaskId> = profile
        .tasks
        .iter()
        .filter(|t| t.id != referencing && route_length(t) == points)
        .map(|t| t.id)
        .collect();
    let [single] = matches[..] else {
        panic!(
            "expected exactly one task other than {referencing} walking {points} waypoint(s) so \
             the two label definitions can be told apart, got: {:?} (route census: {:?})",
            matches,
            profile.tasks.iter().map(route_length).collect::<Vec<_>>()
        )
    };
    single
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A. `#label` — a compiler symbol table, and nothing that reaches the artifact
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `The Burning Crusade.lua:102578-102582`, and its reference 1,200 lines later:
///
/// ```text
/// 102578: step << Alliance
/// 102579: #label Un'Goro End
/// 102581: .accept 4144 >> Accept Bloodpetal Sprouts
///     …
/// 103797: step
/// 103798: #completewith Un'Goro End
/// 103799: .deathskip >> Die and Respawn In Marshall's Refuge
/// ```
///
/// `Un'Goro End` is one of the 4 label values in the corpus that contain a space, and it carries an
/// apostrophe as well. Both survive the importer verbatim
/// (`importer/tests/task_graph_directives.rs::label_keeps_internal_whitespace_and_apostrophes_verbatim`).
/// Neither may survive the **compiler**.
///
/// The assertion is deliberately in two halves, and one half alone is worthless:
///
/// 1. the link RESOLVED — `LinkedTo(0)`, not `OwnPredicate`; and
/// 2. the name is absent from every string in the serialized artifact, keys included.
///
/// Half 2 alone passes today, trivially, because nothing resolves anything and `Task` has no name
/// field. Half 1 alone would pass an implementation that resolved the link and also emitted a
/// `{"labels": {"Un'Goro End": 0}}` map beside the tasks — which is precisely the shape a symbol
/// table wants to become. Together they say: resolve it, then lose it.
///
/// The walk is over the SERIALIZED JSON rather than over the Rust struct on purpose. A Rust-side
/// check can only look where the author remembered to look; the JSON is what actually ships.
///
/// The fragment's `#name` is deliberately **not** a substring-relative of the label. `GuideMeta::name`
/// (§7.2) is the guide's own name and legitimately ships in the artifact, so a fragment headed
/// `#name Ungoro` makes the leak walk report `["Ungoro"]` for a name that is not the label and is
/// not a leak. The walk's two needles have to stay aimed at the label alone: `Un'Goro` as authored,
/// and `Ungoro` as a de-apostrophised spelling of it.
#[tokio::test]
async fn a_resolved_label_name_appears_nowhere_in_the_serialized_artifact() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Crater Route
step << Alliance
#label Un'Goro End
.goto Un'Goro Crater,43.0,9.6
step
#completewith Un'Goro End
.goto Silithus,84.91,20.97,10
]])"#;

    let (profile, _) = lower(guide, &alliance_warrior()).await;

    assert_eq!(
        profile.tasks.len(),
        2,
        "both steps apply to an Alliance character, got: {:?}",
        profile.tasks.iter().map(|t| t.id).collect::<Vec<_>>()
    );
    assert_eq!(
        linked_target(&profile, 1),
        0,
        "`#completewith Un'Goro End` must resolve to the task defining that label, got: {:?}",
        profile.tasks[1].completion
    );

    let strings = every_string(&as_json(&profile));
    let leaked: Vec<&String> = strings
        .iter()
        .filter(|s| s.contains("Un'Goro") || s.contains("Ungoro"))
        .collect();
    assert!(
        leaked.is_empty(),
        "`#label` is a compiler symbol table: the name must not appear anywhere in the artifact, \
         keys included. Leaked: {leaked:?}"
    );
}

/// `The Burning Crusade.lua:16255-16264`, the two `UldaLoch` definitions — one gate on the
/// `#label` line, one on the `step` marker:
///
/// ```text
/// 16255: step
/// 16256:     #label UldaLoch << Mage
/// 16263: step << !Mage
/// 16264:     #label UldaLoch
/// ```
///
/// A `<<` tail on a `#label` line is the second of the two shapes that break a whitespace
/// tokeniser. This asserts the *compiler's* half: neither the bare name nor the gated spelling may
/// reach the artifact, for either archetype.
#[tokio::test]
async fn a_gated_label_leaks_neither_its_name_nor_its_gate_into_the_artifact() {
    let (mage_profile, _) = lower(ULDALOCH, &gnome_mage()).await;
    let (warrior_profile, _) = lower(ULDALOCH, &alliance_warrior()).await;

    for (who, profile) in [("Mage", &mage_profile), ("Warrior", &warrior_profile)] {
        let strings = every_string(&as_json(profile));
        let leaked: Vec<&String> = strings
            .iter()
            .filter(|s| s.contains("UldaLoch") || s.contains("<<"))
            .collect();
        assert!(
            leaked.is_empty(),
            "the {who} artifact leaked label vocabulary: {leaked:?}"
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B. `#requires` — stacked lines, each with its own gate, into concrete `TaskId`s
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `The Burning Crusade.lua:24706-24729`, the Ironforge cloth turn-ins:
///
/// ```text
/// 24706: #label cloth1
/// 24717: #label cloth2
/// 24727: step
/// 24728:     #requires cloth1
/// 24729:     #requires cloth2
/// 24732:     .goto Ironforge,33.4,20.0,70,0
/// ```
///
/// RestedXP has no separator for `#requires`; multiplicity is stacked lines. Both entries here are
/// ungated, so both survive resolution and are ANDed — this is one of the 5 steps in the corpus
/// that stack two, and the AND half of the pair. The OR half is the next test, and the two are
/// distinguished by their gates alone.
///
/// **ALREADY GREEN.** `compiler/src/lib.rs::assemble_tasks` produces this today. It is a guard: D5
/// rewrites that function, and a `deps` that silently became `Option<TaskId>`-shaped again — the
/// single-dependency model requirement P1 exists to prevent — would fail here.
#[tokio::test]
async fn two_stacked_requires_lines_become_two_deps_because_the_stacking_is_an_and() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Cloth
step
#label cloth1
.goto Ironforge,43.224,31.500
step
#label cloth2
.goto Ironforge,43.224,31.574
step
#requires cloth1
#requires cloth2
.goto Ironforge,33.4,20.0,70,0
]])"#;

    let (profile, report) = lower(guide, &alliance_warrior()).await;

    let Some(dependent) = profile.tasks.last() else {
        panic!("the fragment lowers three steps; the artifact has none")
    };
    assert_eq!(
        dependent.deps,
        vec![0, 1],
        "two stacked ungated `#requires` lines are an AND over both predecessors, got: {:?}",
        dependent.deps
    );
    assert!(
        dependent.deps.iter().all(|d| (*d as usize) < profile.tasks.len()),
        "every dep must name a task the artifact actually holds, got: {:?} against {} tasks",
        dependent.deps,
        profile.tasks.len()
    );
    assert!(
        !dependent.deps.contains(&dependent.id),
        "a task may not depend on itself, got: {:?}",
        dependent.deps
    );
    assert!(
        codes_at(&report, Severity::Error).is_empty(),
        "both labels resolve, so nothing here is an error, got: {:?}",
        codes_at(&report, Severity::Error)
    );
}

/// `The Burning Crusade.lua:91057-91093`, the Moonglade flight:
///
/// ```text
/// 91057: step << Horde
/// 91059:     #label FlyMoongladeH
/// 91062:     .fly Moonglade >>Fly to Moonglade
/// 91067: step << Alliance
/// 91069:     #label FlyMoongladeA
/// 91072:     .fly Moonglade >>Fly to Moonglade
/// 91090: step
/// 91092:     #requires FlyMoongladeH << Horde
/// 91093:     #requires FlyMoongladeA << Alliance
/// ```
///
/// Same stacked-lines syntax as `cloth1`/`cloth2`, opposite meaning. The two entries are mutually
/// exclusive by faction, so a lowering that ANDs before resolving gates produces a dep list naming
/// a step that does not exist in this artifact — the defining step was gated out — and the runner
/// waits on it forever. Resolving each entry's OWN gate first and ANDing the survivors makes the OR
/// collapse to exactly one dep for a fixed archetype, with no `Or` operator in the model.
///
/// The cross-archetype half is what proves the *right* survivor was kept rather than the first one:
/// the Horde and Alliance artifacts must not resolve to the same waypoint.
///
/// **ALREADY GREEN**, as a guard, for the same reason as the AND test above.
#[tokio::test]
async fn a_faction_exclusive_requires_pair_collapses_to_one_satisfiable_dep() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Moonglade
step << Horde
#label FlyMoongladeH
.goto Winterspring,60.47,36.30
step << Alliance
#label FlyMoongladeA
.goto Winterspring,62.334,36.609
step
#requires FlyMoongladeH << Horde
#requires FlyMoongladeA << Alliance
.goto Winterspring,60.00,36.00
]])"#;

    let mut resolved_points = Vec::new();

    for (who, archetype) in [
        ("Horde", horde_warrior()),
        ("Alliance", alliance_warrior()),
    ] {
        let (profile, report) = lower(guide, &archetype).await;

        assert_eq!(
            profile.tasks.len(),
            2,
            "{who}: the opposite faction's step is gated out, leaving the survivor and the \
             dependent, got: {:?}",
            profile.tasks.iter().map(|t| t.id).collect::<Vec<_>>()
        );

        let Some(dependent) = profile.tasks.last() else {
            panic!("{who}: the dependent step must survive; the artifact has no tasks")
        };
        let [dep] = dependent.deps[..] else {
            panic!(
                "{who}: exactly one of the faction-exclusive pair may survive, or the dep list is \
                 an impossible AND, got: {:?}",
                dependent.deps
            )
        };
        assert!(
            (dep as usize) < profile.tasks.len(),
            "{who}: the surviving dep must name a task the artifact holds, got: {dep} against {} \
             tasks",
            profile.tasks.len()
        );
        assert!(
            codes_at(&report, Severity::Error).is_empty(),
            "{who}: an entry dropped by its own gate is not an unresolved label and must not be \
             reported as one, got: {:?}",
            codes_at(&report, Severity::Error)
        );

        // The gate-resolved survivor differs per faction, so its interned waypoint must too. Two
        // identical points would mean the same step was kept for both, i.e. the gate was ignored
        // and source order broke the tie.
        let json = as_json(&profile);
        resolved_points.push(json["waypoint_pool"].clone());
    }

    assert_ne!(
        resolved_points[0], resolved_points[1],
        "Horde and Alliance must resolve `#requires` to DIFFERENT steps; identical waypoint pools \
         mean the per-entry gate was not consulted, got: {:?}",
        resolved_points[0]
    );
}

/// `A-1-11-Human.lua:3414-3422`, the author's multi-`#requires` workaround:
///
/// ```text
/// 3414: step
/// 3415:     #optional
/// 3416:     #requires RabidThistle
/// 3417: --XXREQ Placeholder invis step until multiple requires per step
/// 3418: step
/// 3419:     #requires BuzzBox1
/// 3420:     .goto 1439,36.634,46.250
/// 3422:     .turnin 983 >> Turn in Buzzbox 827
/// ```
///
/// RestedXP allows one `#requires` per step, so an author who needs two parks the extra on an empty
/// directive-only step and marks it `--XXREQ`. The importer folds those 52 placeholders into the
/// following real step.
///
/// **This test, not ADR 07 §7.3.3, is where the plural case is witnessed.** §7.3.3's excerpt has
/// exactly one `--XXREQ` placeholder and the step it folds into carries one other `#requires`, so
/// after the fold its task 4 is `"deps": [2]` — singular. An earlier revision of this comment cited
/// it as `[2, 0]`, which was the pre-fold eight-task listing (ADR 07 §9 item 28). The fragment below
/// stacks two placeholders on purpose so the plural edge is exercised somewhere.
///
/// The fold is upstream and done. What this pins is that the compiler does not undo it: the
/// successor must come out with **both** edges, from two different `#requires` lines on two
/// different authored steps, and `#optional` must ride along with them.
///
/// **ALREADY GREEN**, as a guard. The failure it exists to catch is a D5 rewrite that reads
/// `Operation::requires.first()`.
#[tokio::test]
async fn the_xxreq_fold_still_yields_a_multi_entry_deps_on_the_successor() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Xxreq
step
#label RabidThistle
.goto Darkshore,38.90,53.59
step
#label BuzzBox1
.goto Darkshore,36.05,44.75
step
    #optional
    #requires RabidThistle
--XXREQ Placeholder invis step until multiple requires per step
step
    #requires BuzzBox1
    .goto 1439,36.634,46.250
]])"#;

    let (profile, _) = lower(guide, &alliance_warrior()).await;

    assert_eq!(
        profile.tasks.len(),
        3,
        "the placeholder is folded away, not emitted, got: {:?}",
        profile.tasks.iter().map(|t| t.id).collect::<Vec<_>>()
    );

    let Some(successor) = profile.tasks.last() else {
        panic!("the fold's successor must survive; the artifact has no tasks")
    };
    let deps: HashSet<TaskId> = successor.deps.iter().copied().collect();
    assert_eq!(
        deps,
        HashSet::from([0, 1]),
        "the folded placeholder's edge and the successor's own edge must both survive, got: {:?}",
        successor.deps
    );
    assert!(
        !successor.blocking,
        "the placeholder carried `#optional`, so the folded step is non-blocking, got: {:?}",
        successor.blocking
    );
}

/// `A-23-30.lua:1566-1584`, a `#requires` whose label is defined in no step of the block:
///
/// ```text
/// 1566: step << !Dwarf Rogue
/// 1567:     #optional
/// 1568:     #requires AntiVenomEnd
/// 1569:     #completewith FirstAidEnd
/// 1575: step << !Dwarf Rogue
/// 1576:     #requires AntiVenomEnd
/// 1584:     #label FirstAidEnd
/// ```
///
/// `AntiVenomEnd` is one of the 4 block-scope-unresolved `#requires` in the corpus. The ruling: the
/// edge is DROPPED and the guide still compiles, because a dropped edge runs the step early while a
/// fabricated one stalls it forever — but the diagnostic is **ERROR** severity, not a warning. An
/// author cannot fix what is filed alongside the 9 `KERNEL_OP_NOT_LOWERED` warnings a normal
/// compile already emits.
///
/// **RED on severity.** `assemble_tasks` emits `UNRESOLVED_REQUIRES_LABEL` at
/// `Severity::Warning` today.
#[tokio::test]
async fn an_unresolved_requires_drops_the_edge_with_an_error_diagnostic_and_the_step_survives() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name AntiVenom
step
    #requires AntiVenomEnd
    .goto 1453,43.070,26.155
]])"#;

    let (profile, report) = lower(guide, &alliance_warrior()).await;

    let [task] = &profile.tasks[..] else {
        panic!(
            "an unresolvable `#requires` must not drop the step, got: {:?}",
            profile.tasks.iter().map(|t| t.id).collect::<Vec<_>>()
        )
    };
    assert!(
        task.deps.is_empty(),
        "the unresolvable edge is dropped, never pointed at a neighbour, got: {:?}",
        task.deps
    );
    assert!(
        has_diagnostic_naming(
            &report,
            Severity::Error,
            "UNRESOLVED_REQUIRES_LABEL",
            "AntiVenomEnd"
        ),
        "a dropped dependency edge is an ERROR the author must fix, not a warning filed beside \
         the routine ones. Errors emitted: {:?}",
        codes_at(&report, Severity::Error)
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// C. `#completewith` — the reserved `next`, a label, and the unresolved case
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `The Burning Crusade.lua:16270-16277`, a class-gated ride-along:
///
/// ```text
/// 16270: step << Mage
/// 16271:     #optional
/// 16272:     #completewith next
/// 16273:     .cast 3562 >>|cRXP_WARN_Cast|r |T135757:0|t[Teleport: Ironforge]
/// 16276: step << Mage
/// 16277:     .goto Ironforge,27.18,8.60
/// ```
///
/// `next` is the reserved literal — 2,681 of the corpus's 5,469 `#completewith` values — and the
/// **only** reserved word in that value space (`end` is a real label with 11 definitions). It means
/// "finish when the following step finishes", so it lowers to `LinkedTo` of the SUCCESSOR's id.
///
/// Successor in the **artifact**, not in the source. Both steps here are `<< Mage`, so for a Mage
/// they are adjacent survivors; a lowering that recorded the authored index instead would point one
/// task past the end for any archetype that gated out a step in between.
///
/// **RED.** `assemble_tasks` hardcodes `CompletionSource::OwnPredicate`; `Operation::complete_with`
/// is read by nothing in this crate.
#[tokio::test]
async fn completewith_next_links_to_the_successor_task_id() {
    let (profile, _) = lower(ULDALOCH, &gnome_mage()).await;

    let Some(rider) = profile
        .tasks
        .iter()
        .find(|t| matches!(t.completion, CompletionSource::LinkedTo(_)) && !t.blocking)
    else {
        panic!(
            "the `#optional` + `#completewith next` step must link to its successor, got: {:?}",
            profile
                .tasks
                .iter()
                .map(|t| (t.id, t.blocking, &t.completion))
                .collect::<Vec<_>>()
        )
    };
    assert_eq!(
        linked_target(&profile, rider.id),
        rider.id + 1,
        "`next` means the following SURVIVING task, got: {:?}",
        rider.completion
    );
}

/// `The Burning Crusade.lua:103797-103799` referencing `:102579`, quoted in full in
/// `a_resolved_label_name_appears_nowhere_in_the_serialized_artifact` above.
///
/// The named-label form: 2,788 of the corpus's 5,469 `#completewith` values name one of 1,245
/// labels, and 2,670 of those links point FORWARD — this one spans 1,219 source lines. So the
/// resolver cannot be a lookahead over what it has already emitted; it needs the whole block's
/// symbol table before it can lower any completion.
///
/// RXPGuides itself gets this wrong in the opposite direction: its `guide.labels[…]` lookup returns
/// nil for an unresolved name and the edge silently never fires (§3.1). `CompletionSource::LinkedTo`
/// carries a resolved index precisely so that failure has nowhere to live.
///
/// **RED**, same cause as `completewith_next_links_to_the_successor_task_id`.
#[tokio::test]
async fn completewith_a_label_links_to_the_resolved_task_id() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ungoro
step << Alliance
#label Un'Goro End
.goto Un'Goro Crater,43.0,9.6
step
#completewith Un'Goro End
.goto Silithus,84.91,20.97,10
]])"#;

    let (profile, report) = lower(guide, &alliance_warrior()).await;

    assert_eq!(
        linked_target(&profile, 1),
        0,
        "a backward `#completewith <label>` resolves to the defining task, got: {:?}",
        profile.tasks[1].completion
    );
    assert!(
        codes_at(&report, Severity::Error).is_empty(),
        "the label resolves, so nothing here is an error, got: {:?}",
        codes_at(&report, Severity::Error)
    );
}

/// `A-1-11-Human.lua:1994-2000`, a `#completewith` whose label is defined in no step of the block:
///
/// ```text
/// 1994: step << Warlock
/// 1995:     #optional
/// 1996:     #completewith TheBinding
/// 1997:     .goto Redridge Mountains,17.4,69.6
/// 1999:     >>|cRXP_WARN_Grind en-route. Make sure you have at least 2 Soul Shards
/// 2000:     .collect 6265,2 --Soul Shard (2)
/// ```
///
/// One of the 80 block-scope-unresolved `#completewith` references. The ruling, already decided:
/// **not fatal, and the step is not dropped.** It falls back to `CompletionSource::OwnPredicate`
/// with an ERROR-severity diagnostic. That is safe because every one of the 52 truly-unresolvable
/// steps carries its own completion anyway — 37 via `.complete`/`.collect`/`.accept` and 15 via a
/// side-effect command that finishes on execution. This step is one of the 37: `.collect 6265,2`
/// is its own completion authority.
///
/// Dropping the step instead would delete the Soul Shard farm from every Warlock's route; falling
/// back silently would leave an author with no way to learn that a rename broke a link.
///
/// **RED.** No diagnostic of any severity is emitted for `#completewith` today — the directive is
/// not read at all — so the artifact is *accidentally* right about `OwnPredicate` and silent about
/// why.
#[tokio::test]
async fn an_unresolved_completewith_falls_back_to_own_predicate_with_an_error_diagnostic() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Binding
step << Warlock
    #optional
    #completewith TheBinding
    .goto Redridge Mountains,17.4,69.6
]])"#;

    let (profile, report) = lower(guide, &gnome_warlock()).await;

    let [task] = &profile.tasks[..] else {
        panic!(
            "an unresolvable `#completewith` must not drop the step, got: {:?}",
            profile.tasks.iter().map(|t| t.id).collect::<Vec<_>>()
        )
    };
    assert_eq!(
        task.completion,
        CompletionSource::OwnPredicate,
        "an unresolvable link falls back to the task's own completion authority, got: {:?}",
        task.completion
    );
    assert!(
        has_diagnostic_naming(
            &report,
            Severity::Error,
            "UNRESOLVED_COMPLETEWITH_LABEL",
            "TheBinding"
        ),
        "a silently-dropped completion link is the RXPGuides failure this model exists to \
         prevent; it must be an ERROR naming the label. Errors emitted: {:?}",
        codes_at(&report, Severity::Error)
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// D. Duplicate labels the importer deliberately refused to decide
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `The Burning Crusade.lua:16240-16277`. Two definitions of `UldaLoch`, distinguishable only by a
/// gate, and one reference that must bind to whichever the archetype makes real:
///
/// ```text
/// 16240: step
/// 16241:     #completewith UldaLoch
/// 16242:     .goto Badlands,49.52,9.83,0
/// 16255: step
/// 16256:     #label UldaLoch << Mage
/// 16258:     .goto Loch Modan,36.50,48.35,15,0
/// 16259:     .goto Loch Modan,37.067,49.379
/// 16261:     .turnin 17 >> Turn in Uldaman Reagent Run
/// 16263: step << !Mage
/// 16264:     #label UldaLoch
/// 16265:     .goto Loch Modan,33.938,50.954
/// 16267:     .fly Ironforge >> Fly to Ironforge
/// ```
///
/// A Mage teleports; everyone else takes the gryphon. The disambiguating information is split
/// across two lines — the gate on the `#label` at 16256, the gate on the `step` marker at 16263 —
/// which is exactly why `LabelGraph::definitions` is a MULTIMAP that keeps both and ranks neither
/// (`importer/src/label_graph.rs`, module header). Ranking requires a resolved archetype, and that
/// is C2, i.e. this compiler.
///
/// The failure this test exists to catch is the tie-break: `assemble_tasks` currently resolves
/// `#requires` through a `HashMap` whose later `insert` wins, with a `DUPLICATE_STEP_LABEL`
/// warning. Applied to `#completewith`, last-wins binds every Mage to the gryphon step. First-wins
/// binds every non-Mage to the teleport step. Both are silent and both are wrong; the archetype
/// already decided, and neither tie-break asks it.
///
/// The two candidates are told apart by **route length** — 2 surviving `.goto`s versus 1 — because
/// `MemoryQueryClient` leaves `.turnin` and `.fly` unlowered and the walk is then the only
/// artifact-visible difference. Not by op *count*: a consecutive run of movement lines is one
/// `Op::Travel` carrying the whole route (§5.7), so both candidates carry exactly one op and only
/// its `points` separate them. `only_task_with_route_length` fails loudly if that stops being true.
///
/// **RED**, same cause as the other `#completewith` tests.
#[tokio::test]
async fn a_gate_disambiguated_label_pair_binds_by_archetype_not_by_source_order() {
    // A Mage: `step << !Mage` is gated out entirely, so the teleport step's gated `#label` is the
    // only surviving definition. Its step carries two `.goto`s.
    let (mage_profile, mage_report) = lower(ULDALOCH, &gnome_mage()).await;
    let mage_target = only_task_with_route_length(&mage_profile, 2, 0);
    assert_eq!(
        linked_target(&mage_profile, 0),
        mage_target,
        "a Mage must bind `#completewith UldaLoch` to the `#label UldaLoch << Mage` step, got: \
         {:?}",
        mage_profile.tasks[0].completion
    );

    // Anyone else: the `<< Mage` label is dropped by its own gate — the step it sits on is UNGATED
    // and survives, defining nothing — and the `step << !Mage` definition becomes the only one.
    // That step carries one `.goto`.
    let (warrior_profile, warrior_report) = lower(ULDALOCH, &alliance_warrior()).await;
    let warrior_target = only_task_with_route_length(&warrior_profile, 1, 0);
    assert_eq!(
        linked_target(&warrior_profile, 0),
        warrior_target,
        "a non-Mage must bind `#completewith UldaLoch` to the `step << !Mage` definition, got: \
         {:?}",
        warrior_profile.tasks[0].completion
    );

    for (who, report) in [("Mage", &mage_report), ("Warrior", &warrior_report)] {
        let codes: BTreeSet<&str> = report
            .unmapped_conditions
            .iter()
            .map(|d| d.code.as_str())
            .collect();
        assert!(
            !codes.contains("DUPLICATE_STEP_LABEL"),
            "{who}: the gate decided this, so there is no duplicate left to tie-break and no \
             warning to emit, got: {codes:?}"
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// E. `#sticky` and `#optional` — lifetime and blocking
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `A-11-23.lua:211-237`, the BuzzBox1 patrol circuit — ADR 07 §7.3.3's task 0, and the reason
/// `ResumeCursor` has a `waypoint` field at all:
///
/// ```text
/// 211: step
/// 212:     #sticky
/// 213:     #label BuzzBox1
/// 214:     #loop
/// 215:     .goto 1439,36.051,44.757,0
/// 218:     .waypoint 1439,36.091,51.501,60,0
/// 234:     .complete 983,1 --Crawler Leg (6)
/// ```
///
/// `#sticky` (311 uses; its payload is 416 `.waypoint` and 296 `.goto` lines) is the whole reason
/// `Lifetime` is an enum. §7.3.3 lowers this step to
/// `Background { channels: ["MOVEMENT"], band: 34, … }`: the patrol holds MOVEMENT for its lifetime
/// while a foreground turn-in holds INTERACTION, and the two coexist. Collapsing that into
/// `Exclusive` is what makes the RXPGuides model unable to express these steps at all.
///
/// The `band` assertion is the §7.2 range only — the ORDERING rule is not tested here, see the
/// module header.
///
/// **RED.** `Operation::sticky` reaches the compiler and is read by nothing;
/// `assemble_tasks` hardcodes `Lifetime::Exclusive`.
#[tokio::test]
async fn sticky_becomes_a_background_lifetime_holding_the_movement_channel() {
    let (profile, _) = lower(BUZZBOX, &alliance_warrior()).await;

    let (channels, band) = background_of(&profile, 0);
    assert!(
        channels.contains(&Channel::Movement),
        "a sticky patrol's whole purpose is to hold MOVEMENT while a foreground task interacts, \
         got: {channels:?}"
    );
    assert!(
        (30..=49).contains(&band),
        "ADR 07 §7.2 pins the Goal band to 30..=49, got: {band}"
    );
}

/// `A-11-23.lua:272-275`, ADR 07 §7.3.3's task 6 — the ride-along that holds nothing:
///
/// ```text
/// 272: step
/// 273:     #label Auber1
/// 274:     #completewith next
/// 275:     .subzone 442 >> Travel to Auberdine
/// ```
///
/// §7.3.3 lowers this to `Background { channels: [], band: 30, … }` with
/// `completion: LinkedTo(7)`. `#sticky` and `#completewith` are disjoint as authored — this step
/// carries no `#sticky` — yet a `#completewith` task is concurrent at runtime by definition: it
/// cannot be the foreground task if the task it finishes with is. So it becomes `Background` with an
/// **empty** channel set and rides along without contending.
///
/// That asymmetry is why `Lifetime` and `CompletionSource` are independent fields rather than one
/// "background" flag, and it is the single most likely thing for a D5 implementation to collapse:
/// deriving `channels` from the step's ops would give this task MOVEMENT the moment `.subzone`
/// gains a travel lowering, and it would then contend with the very task it is waiting for.
///
/// **RED**, on both fields.
#[tokio::test]
async fn a_completewith_only_task_rides_along_in_background_with_no_channel() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Auberdine
step
    #label Auber1
    #completewith next
    .subzone 442 >> Travel to Auberdine
step
    #requires Auber1
    .goto 1439,36.634,46.250
]])"#;

    let (profile, _) = lower(guide, &alliance_warrior()).await;

    assert_eq!(
        linked_target(&profile, 0),
        1,
        "`#completewith next` links to the following task, got: {:?}",
        profile.tasks[0].completion
    );
    let (channels, band) = background_of(&profile, 0);
    assert!(
        channels.is_empty(),
        "a `#completewith` ride-along contends for nothing; giving it a channel makes it fight \
         the task it is waiting for, got: {channels:?}"
    );
    assert!(
        (30..=49).contains(&band),
        "ADR 07 §7.2 pins the Goal band to 30..=49, got: {band}"
    );
}

/// `A-11-23.lua:211-237` again, on the third field of `Background`.
///
/// §7.3.3 gives task 2 — the `#sticky` `RabidThistle` step at `A-11-23.lua:243-260` — a
/// `terminate_on` of `QuestObjective { id: 2118, index: 1, need: 1 }`, which is character-for-
/// character its own `complete_when`. §7.3.3's task 6 does the same with `InArea { area: 442 }`.
/// `terminate_on` is DERIVED from what the task is for; it is not a field a lowering gets to invent.
///
/// The failure this catches is the obvious placeholder: a `Background` whose `terminate_on` is some
/// never-satisfied constant is a task that holds MOVEMENT until the profile ends. §5.3 distinguishes
/// termination (voluntary, permanent) from suspension (involuntary loss of a lease); a patrol that
/// cannot terminate is suspended and resumed forever and the guide never advances past it.
///
/// **DELIBERATELY COUPLED, and RED for two reasons.** `terminate_on` cannot be asserted without
/// `complete_when`, and `compile_kernel` bakes no predicates yet — `complete_when` is `None` on
/// every task today. If D5 lands the graph before the predicates, this test stays RED until both
/// are in. That is the intended reading: a `Background` emitted before its terminating predicate
/// exists is not a partial artifact, it is a non-terminating one.
#[tokio::test]
async fn a_background_terminate_on_is_derived_from_the_task_not_invented() {
    let (profile, _) = lower(BUZZBOX, &alliance_warrior()).await;

    let Some(patrol) = profile.tasks.first() else {
        panic!("the sticky patrol must survive; the artifact has no tasks")
    };
    let Lifetime::Background {
        ref terminate_on, ..
    } = patrol.lifetime
    else {
        panic!(
            "`#sticky` must lower to a concurrent task, got: {:?}",
            patrol.lifetime
        )
    };
    let Some(complete_when) = patrol.complete_when.as_ref() else {
        panic!(
            "`.complete 983,1` is this task's completion authority and must be baked, got: {:?}",
            patrol.complete_when
        )
    };
    assert_eq!(
        terminate_on, complete_when,
        "a self-completing sticky task terminates on its own completion; anything else is an \
         invented predicate, got: {terminate_on:?}"
    );
}

/// `The Burning Crusade.lua:16270-16277`, quoted in full in
/// `completewith_next_links_to_the_successor_task_id`.
///
/// `#optional` (3,067 uses) means failing or skipping the step does not stall the profile. The
/// paired assertion is what gives it teeth: the neighbouring ungated step must stay blocking, so a
/// lowering that defaulted every task to non-blocking — which would make the whole profile
/// unstallable and every failure silent — cannot pass by accident.
///
/// **ALREADY GREEN.** `assemble_tasks` lowers `Operation::optional` today, gate and all. Kept as a
/// guard over the function D5 rewrites.
#[tokio::test]
async fn optional_becomes_a_non_blocking_task_and_its_neighbour_stays_blocking() {
    let (profile, _) = lower(ULDALOCH, &gnome_mage()).await;

    let non_blocking: Vec<TaskId> = profile
        .tasks
        .iter()
        .filter(|t| !t.blocking)
        .map(|t| t.id)
        .collect();
    assert_eq!(
        non_blocking.len(),
        1,
        "exactly one step in the fragment carries `#optional`, got: {non_blocking:?}"
    );
    assert!(
        profile.tasks.iter().any(|t| t.blocking),
        "an ungated step with no `#optional` stalls the profile when it fails; a profile of \
         entirely non-blocking tasks fails silently, got: {:?}",
        profile
            .tasks
            .iter()
            .map(|t| (t.id, t.blocking))
            .collect::<Vec<_>>()
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// F. The band invariant — §7.2's range, which no schema and no type expresses
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// ADR 07 §7.2 constrains the scheduler band to `{ "type": "integer", "minimum": 30, "maximum": 49 }`
/// — the Goal band of §5.3, above the 20s where opportunistic work lives and below the 90s safety
/// net that `#ignorecorpse` exists to switch off.
///
/// **Nothing in this repository enforces it.** `Lifetime::Background::band` is a `u8`, so the
/// generated schema carries no bound, and
/// `shared/tests/kernel_schema.rs::lifetime_band_range_is_not_expressed_by_the_generated_schema`
/// asserts that absence as a recorded R1 limitation. That test is honest about today and is not the
/// hole; the hole is that no OTHER test closes it. A D5 lowering that emitted `band: 200` — one
/// arithmetic slip in the per-task offset — would place every sticky patrol above the safety net
/// and pass the entire existing suite, silently.
///
/// This test is the compiler half: whatever bands D5 assigns, every one of them is in range.
/// `shared/tests/kernel_band_invariant.rs` is the model half — an out-of-range band must not load
/// off the wire either, or a hand-edited artifact walks straight past this.
///
/// **RED.** The fragment carries two `#sticky` steps and a `#completewith`, and the artifact
/// contains no `Background` task at all, so the "at least one" guard fires first. That guard is not
/// decoration: a range assertion over an empty collection is vacuously true and would go green the
/// moment D5 emitted nothing.
#[tokio::test]
async fn every_emitted_background_band_sits_inside_the_goal_band() {
    let (profile, _) = lower(WORKED_EXAMPLE, &alliance_warrior()).await;

    let bands: Vec<(TaskId, u8)> = profile
        .tasks
        .iter()
        .filter_map(|t| match t.lifetime {
            Lifetime::Background { band, .. } => Some((t.id, band)),
            Lifetime::Exclusive => None,
        })
        .collect();

    assert!(
        !bands.is_empty(),
        "the fragment carries two `#sticky` steps and a `#completewith next`, so the artifact must \
         hold at least one concurrent task — otherwise this range check is vacuous. Lifetimes: \
         {:?}",
        profile
            .tasks
            .iter()
            .map(|t| (t.id, &t.lifetime))
            .collect::<Vec<_>>()
    );

    let out_of_range: Vec<(TaskId, u8)> = bands
        .iter()
        .copied()
        .filter(|(_, band)| !(30..=49).contains(band))
        .collect();
    assert!(
        out_of_range.is_empty(),
        "ADR 07 §7.2 pins the Goal band to 30..=49; a band above it outranks the safety net and a \
         band below it loses every lease. Out of range: {out_of_range:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// G. Acyclicity
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// The lowered graph — `deps` edges and `LinkedTo` completion edges together — has no cycle.
///
/// **The corpus makes this true by construction, and that is exactly why the test exists.** All 346
/// resolvable `#requires` edges point backward (target index < referencing index); zero forward,
/// zero self. So no cycle-detection pass belongs in the compiler: it would be dead code over this
/// input, and dead code that reports nothing is indistinguishable from dead code that is broken.
///
/// What this guards is a **future authoring change**, not a present risk. Two shapes would break it
/// and neither is exotic: a forward `#requires` written by hand in the editor (which has no
/// ordering constraint at all), and a `#completewith` pair that names each other — the completion
/// edges are 2,670 forward against 38 backward, so unlike `deps` they are not directional by
/// convention and nothing but this test says they may not close a loop.
///
/// A cycle in either edge set deadlocks the runner in the quietest possible way: every task in the
/// cycle is waiting, none is blocked, and the profile reports "running" forever.
///
/// **Expected GREEN today** — with `deps` correct and every completion `OwnPredicate`, the graph is
/// the `#requires` edges alone. It goes on failing to be interesting until `LinkedTo` exists, and
/// then it starts guarding the edge set that actually needs it.
#[tokio::test]
async fn the_lowered_task_graph_is_acyclic() {
    let (profile, _) = lower(WORKED_EXAMPLE, &alliance_warrior()).await;

    let mut edges: HashMap<TaskId, Vec<TaskId>> = HashMap::new();
    for task in &profile.tasks {
        let out = edges.entry(task.id).or_default();
        out.extend(task.deps.iter().copied());
        if let CompletionSource::LinkedTo(target) = task.completion {
            out.push(target);
        }
    }

    // Iterative depth-first search with an explicit colouring, rather than recursion: a cycle in
    // the input is the thing being looked for, and a recursive walk would overflow the stack on it
    // instead of reporting it.
    #[derive(Clone, Copy, PartialEq)]
    enum Colour {
        White,
        Grey,
        Black,
    }
    let mut colour: HashMap<TaskId, Colour> = profile
        .tasks
        .iter()
        .map(|t| (t.id, Colour::White))
        .collect();

    for task in &profile.tasks {
        if colour[&task.id] != Colour::White {
            continue;
        }
        let mut stack = vec![(task.id, 0usize)];
        while let Some((node, index)) = stack.pop() {
            if index == 0 {
                colour.insert(node, Colour::Grey);
            }
            let out = edges.get(&node).map(Vec::as_slice).unwrap_or_default();
            if index < out.len() {
                let next = out[index];
                stack.push((node, index + 1));
                match colour.get(&next).copied() {
                    Some(Colour::Grey) => panic!(
                        "the task graph must be acyclic: task {node} reaches task {next}, which is \
                         still open on this path. Every task in a cycle waits and none is blocked, \
                         so the runner reports `running` forever. Edges: {edges:?}"
                    ),
                    Some(Colour::White) => stack.push((next, 0)),
                    Some(Colour::Black) => {}
                    None => panic!(
                        "task {node} names task {next}, which is absent from the artifact's {} \
                         tasks — a dangling edge, not a cycle, but the runner stalls the same way",
                        profile.tasks.len()
                    ),
                }
            } else {
                colour.insert(node, Colour::Black);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Fragments shared by more than one test
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `The Burning Crusade.lua:16240-16277`, condensed to the directives under test.
///
/// Carries, in one block: a backward `#completewith <label>`, the gate-disambiguated `UldaLoch`
/// pair, an `#optional` + `#completewith next` ride-along, and an ungated step that must stay
/// blocking. The `.turnin` / `.cast` / `.fly` commands are dropped from the fragment rather than
/// quoted, because `MemoryQueryClient` leaves them unlowered and they would only add noise to the
/// op census the duplicate-label test discriminates on.
const ULDALOCH: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ulda
step
#completewith UldaLoch
.goto Badlands,49.52,9.83,0
step
#label UldaLoch << Mage
.goto Loch Modan,36.50,48.35,15,0
.goto Loch Modan,37.067,49.379
step << !Mage
#label UldaLoch
.goto Loch Modan,33.938,50.954
step << Mage
#optional
#completewith next
.goto Loch Modan,33.900,50.900
step << Mage
.goto Ironforge,27.18,8.60
]])"#;

/// `A-11-23.lua:211-237` plus the step that requires it, condensed.
///
/// The `#sticky` `#label BuzzBox1` `#loop` circuit — ADR 07 §7.3.3's task 0. One `.goto` and one
/// `.waypoint` stand in for the authored 3 and 15; the count is irrelevant to lifetime, and the
/// route-collapse rules that decide how many `Op::Travel`s they become are a different deliverable.
const BUZZBOX: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#name BuzzBox
step
    #sticky
    #label BuzzBox1
    #loop
    .goto 1439,36.051,44.757,0
    .waypoint 1439,36.091,51.501,60,0
    .complete 983,1 --Crawler Leg (6)
    .isOnQuest 983
step
    #requires BuzzBox1
    .goto 1439,36.634,46.250
]])"#;

/// `A-11-23.lua:211-280`, the span ADR 07 §7.3.3 lowers into its seven-task worked example.
///
/// Condensed to what the graph tests need: two `#sticky` steps (§7.3.3 tasks 0 and 2), the XXREQ
/// placeholder and the grind step it folds into (task 4, `"deps": [2]`), the `#completewith next`
/// ride-along (task 5), and the `#requires BuzzBox1` turn-in that closes the chain (task 6). Whether
/// the authored 70 lines produce exactly seven tasks is a route- and op-lowering question this file
/// does not ask — `kernel_worked_example.rs` does; what it asks is that whatever they produce has no
/// cycle in it, and holds at least one concurrent task.
const WORKED_EXAMPLE: &str = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Worked
step
    #sticky
    #label BuzzBox1
    #loop
    .goto 1439,36.051,44.757,0
    .waypoint 1439,36.091,51.501,60,0
    .complete 983,1 --Crawler Leg (6)
    .isOnQuest 983
step
    .isOnQuest 3524
    .goto 1439,36.371,50.920
step
    #sticky
    #label RabidThistle
    .goto Darkshore,38.79,53.75,0
    .complete 2118,1 --Rabid Thistle Bear Captured (1)
step
    .goto Darkshore,38.90,53.59
    .complete 984,1
step
    #optional
    #requires RabidThistle
--XXREQ Placeholder invis step until multiple requires per step
step
#optional
    .xp 10+6760 >> Grind to 6760+/7600xp
step
    #label Auber1
    #completewith next
    .subzone 442 >> Travel to Auberdine
step
    #requires BuzzBox1
    .goto 1439,36.634,46.250
]])"#;
