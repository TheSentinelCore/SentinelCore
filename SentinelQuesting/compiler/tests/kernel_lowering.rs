//! Lowering tests for the ADR 07 kernel artifact: the predicate tree, and the
//! `Compiler::compile_kernel` entry point that will one day assemble a whole profile.
//!
//! **It does not assemble one yet, and section D says so out loud.** `compile_kernel` returns a
//! profile *header* — empty pool, no tasks, zero-placeholder digests — for a project with no
//! operations. The predicate section below therefore tests `lower_predicate` directly, and section D
//! tests the entry point for the only things it currently claims: a well-formed header, and the
//! `KERNEL_PROFILE_INCOMPLETE` warning that keeps its emptiness from reading as a clean compile.
//!
//! **Coordinates are not tested here and must not be.** They were, over `parse_movement` — a
//! complete second implementation of the transform that **no compile ever called**. The live path is
//! the importer's `project_builder.rs::build_travel_position`, which implemented none of the `/`
//! raw-world discrimination and therefore dropped 929 corpus lines while twelve tests in this file
//! stayed green. There is now one transform, `sentinel_models::movement::resolve_coordinate`, and all
//! twelve tests moved unchanged in substance to `compiler/tests/kernel_coordinates.rs`, which drives
//! `parse_guide` → `ProjectBuilder::build` → `Compiler::compile_kernel` over the same corpus lines.
//!
//! **Route building is not tested here either.** `lower_route` is the pipeline's only route builder
//! now that `task_graph::flush_route` is an adapter in front of it, so its coverage belongs where a
//! compile can be observed: `kernel_route_aggregation.rs`.
//!
//! Authority: `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md`. Corpus:
//! `sentinel/docs/adr/restedxp guides`. Every test below quotes the verbatim guide line it lowers,
//! with its file and line number, so the expected value can be re-derived from the source rather
//! than trusted.
//!
//! # What these tests prove
//!
//! * **A predicate is derived from its input, not transcribed.** `QuestObjective::need` comes from
//!   the injected metadata provider; the tests change the provider and require the output to
//!   change with it.
//! * **An incomplete artifact says so.** `compile_kernel` cannot emit an empty profile silently.
//!
//! # What these tests cannot see
//!
//! * **Whether the metadata provider's `need` matches `quest_template`.** The provider is a stub.
//!   These tests prove the value *travels from the provider into the predicate*; that the provider
//!   reads the right `ReqItemCount*` column is the query layer's contract, not this one's.
//! * **Anything `compile_kernel` does not do yet** — the two BLAKE3 digests and world provenance.
//!   Section D pins the *placeholders*, which is a statement about today's honesty, not about
//!   tomorrow's correctness.
//! * **`HasItem`, which is now refused by both sinks and has no test here.** An earlier revision of
//!   this file asserted that the kernel sink folded `HasItem(item)` into
//!   `ItemCount { cmp: Ge, count: 1 }`, justified as "a legal ADR-05 authoring input reachable
//!   through the editor's `/compile` endpoint". That justification was false and one grep refuted
//!   it: `compiler/src/condition.rs`'s `RuntimeConditionSink::leaf` has no `HasItem` arm, so the
//!   ADR-05 parser refuses the name; no importer emitter produces the string; and
//!   `RuntimeCondition::HasItem` is declared in `shared/src/runtime/condition.rs` and constructed
//!   nowhere. The arm was removed rather than kept, so the two sinks — which share one parser —
//!   accept exactly the same leaf vocabulary. That symmetry is pinned by
//!   `sentinel_compiler::kernel::predicate::tests::has_item_is_refused_by_both_sinks`, a unit test
//!   because only crate-internal code can reach both sinks.
//!
//! # Surface these tests require of `sentinel_compiler::kernel`
//!
//! ```ignore
//! pub trait QuestMeta {
//!     /// `Some(0)` is "this objective needs no count"; `None` is "the world database could not
//!     /// answer". The two must not be collapsed — see
//!     /// `an_objective_the_provider_cannot_answer_is_a_hard_error_not_a_zero`.
//!     fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32>;
//! }
//! pub fn lower_predicate(expression: &str, meta: &dyn QuestMeta) -> Result<Predicate, LoweringError>;
//!
//! pub enum LoweringError {                                                          // + Debug
//!     UnknownObjective { quest: QuestId, index: u8 },
//!     UnmappablePredicate { expression: String, /* … */ },
//!     // … plus whatever the gate resolver needs
//! }
//! ```
//!
//! Section D additionally requires `Compiler::compile_kernel(&Project, &Archetype, &dyn QuestMeta)`
//! to return `(kernel::RuntimeProfile, CompileReport)`.
//!
//! `lower_predicate` must keep `compiler/src/condition.rs`'s hardened lexer/parser rather than
//! re-implement it: `MAX_CONDITION_DEPTH = 64` and `MAX_CONDITION_TOKENS = 4096` close a
//! network-reachable stack-overflow DoS on the editor's `/compile` endpoint, pinned by
//! `condition::tests::recursion_depth_is_bounded`. A rewrite that loses them reintroduces a remote
//! crash. Only the `ConditionSink` implementation — `KernelSink`'s three combinators and its `leaf`
//! mapping — is model-specific.

use sentinel_compiler::kernel::{lower_predicate, LoweringError, QuestMeta};
use sentinel_compiler::Compiler;
use sentinel_models::authoring::{new_project, Class, Faction, Race, Severity};
use sentinel_models::kernel::{
    Archetype, Cmp, CombatStance, Expansion, Predicate, ProfileMode, QuestId,
    RuntimeProfile as KernelProfile, UnknownPolicy, MAGIC, SCHEMA_VERSION,
};

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DWARF_GNOME_GUIDE: &str = "A-1-11-Dwarf-Gnome.lua";

/// A stub `QuestMeta`. `objective_need` answers only for the pairs it was built with; everything
/// else is `None`, which the lowering must treat as a hard error rather than as `need: 0`.
struct StubMeta(Vec<((QuestId, u8), u32)>);

impl StubMeta {
    fn with(pairs: &[((QuestId, u8), u32)]) -> Self {
        StubMeta(pairs.to_vec())
    }

    /// A provider that knows nothing. Used to prove `need` is not invented when the world database
    /// cannot answer.
    fn empty() -> Self {
        StubMeta(Vec::new())
    }
}

impl QuestMeta for StubMeta {
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32> {
        self.0
            .iter()
            .find(|((q, i), _)| *q == quest && *i == index)
            .map(|(_, need)| *need)
    }

    /// No objective in this file is an item objective, so nothing here needs a loot rule. `None`
    /// is "not an item", never "could not answer" — see the trait's own doc comment.
    fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        None
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// C — predicate lowering
//
// The input is the `02_DATA_MODEL.md` §23 DSL string the importer emits for a corpus command
// (`importer/src/project_builder.rs::gating_condition_dsl`), and each test quotes both the corpus
// line and the DSL it produces so the chain can be re-walked.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

fn predicate(expression: &str, meta: &dyn QuestMeta) -> Predicate {
    lower_predicate(expression, meta)
        .unwrap_or_else(|err| panic!("`{expression}` must lower, got: {err:?}"))
}

#[test]
fn is_on_quest_with_a_multi_id_list_lowers_to_an_or_of_quest_in_log() {
    // A-11-23.lua:1426 — `.isOnQuest 9699,9584,9643,9580,10063`
    // `quest_ids_dsl` joins one `QuestAccepted(id)` per id with ` || `; the kernel maps
    // QuestAccepted → QuestInLog, the "in the log, neither complete nor turned in" state (§5.1.1).
    let meta = StubMeta::empty();
    let lowered = predicate(
        "QuestAccepted(9699) || QuestAccepted(9584) || QuestAccepted(9643) || QuestAccepted(9580) \
         || QuestAccepted(10063)",
        &meta,
    );

    assert_eq!(
        lowered,
        Predicate::Or(vec![
            Predicate::QuestInLog { id: 9699 },
            Predicate::QuestInLog { id: 9584 },
            Predicate::QuestInLog { id: 9643 },
            Predicate::QuestInLog { id: 9580 },
            Predicate::QuestInLog { id: 10063 },
        ]),
        "got: {lowered:?}"
    );
}

#[test]
fn is_quest_complete_lowers_to_quest_complete() {
    // A-11-23.lua:473 — `.isQuestComplete 955` → DSL `QuestCompleted(955)`.
    // "Objectives met, not yet handed in" — distinct from QuestTurnedIn, and a resumed run cannot
    // tell the two apart without both (§5.1.1).
    let meta = StubMeta::empty();
    let lowered = predicate("QuestCompleted(955)", &meta);
    assert_eq!(lowered, Predicate::QuestComplete { id: 955 }, "got: {lowered:?}");
}

#[test]
fn is_quest_turned_in_lowers_to_quest_turned_in() {
    // A-11-23.lua:480 — `.isQuestTurnedIn 955` → DSL `QuestRewarded(955)`.
    let meta = StubMeta::empty();
    let lowered = predicate("QuestRewarded(955)", &meta);
    assert_eq!(lowered, Predicate::QuestTurnedIn { id: 955 }, "got: {lowered:?}");
}

#[test]
fn an_xp_level_gate_lowers_to_level_at_least() {
    // A-11-23.lua:322 — `.xp 12` → DSL `LevelAtLeast(12)` (`xp_level_dsl`).
    // §5.2 keeps this a runtime predicate rather than resolving it at compile time: player level
    // changes during play, and caching it is the RXP `applies()` bug.
    let meta = StubMeta::empty();
    let lowered = predicate("LevelAtLeast(12)", &meta);
    assert_eq!(lowered, Predicate::LevelAtLeast { level: 12 }, "got: {lowered:?}");
}

#[test]
fn item_count_with_a_less_than_operator_lowers_to_cmp_lt() {
    // A-1-11-Dwarf-Gnome.lua:631 — `.itemcount 16321,<1 --Grimoire of Blood Pact (Rank 1)`
    //
    // The §23 DSL has only an at-least primitive, so `item_count_dsl`
    // (`importer/src/project_builder.rs`) encodes `<n` as `NOT ItemCount(item,n)`. The kernel has
    // `Cmp`, so the negation folds away: NOT (count >= 1) is exactly (count < 1). Emitting
    // `Not(ItemCount { cmp: Ge, .. })` instead would be a second way to spell one thing, which
    // §5.1.1 is explicit about avoiding.
    let meta = StubMeta::empty();
    let lowered = predicate("NOT ItemCount(16321,1)", &meta);

    assert_eq!(
        lowered,
        Predicate::ItemCount {
            id: 16321,
            cmp: Cmp::Lt,
            count: 1,
        },
        "the operator authored on {DWARF_GNOME_GUIDE}:631 must survive as a `Cmp`, not as a `Not` \
         wrapper around the at-least primitive. got: {lowered:?}"
    );
}

#[test]
fn a_collect_count_lowers_to_cmp_ge() {
    // A-11-23.lua:139 — `.collect 4592,15 --Longjaw Mud Snapper` → DSL `ItemCount(4592,15)`.
    // The unoperated form is the at-least case, and it is the complement of the `<` case above.
    let meta = StubMeta::empty();
    let lowered = predicate("ItemCount(4592,15)", &meta);
    assert_eq!(
        lowered,
        Predicate::ItemCount {
            id: 4592,
            cmp: Cmp::Ge,
            count: 15,
        },
        "got: {lowered:?}"
    );
}

#[test]
fn an_objective_takes_its_need_from_the_metadata_provider() {
    // A-11-23.lua:234 — `.complete 983,1 --Crawler Leg (6)` → DSL `Objective(983,1)`.
    //
    // The DSL carries the quest and the 1-based objective index and NOTHING ELSE. `need` is baked
    // offline from `quest_template.ReqItemCount1` so the runtime never parses a localized progress
    // string (§7.3.2) — the `(6)` in the trailing dev comment is prose, stripped at lex time
    // (`lexer.rs::strip_inline_dev_comment`), and is not an input to anything.
    //
    // Two providers, one expression. If `need` were transcribed from the ADR fixture, or read off
    // the dev comment, or defaulted, the second assertion would still say 6.
    let truthful = StubMeta::with(&[((983, 1), 6)]);
    assert_eq!(
        predicate("Objective(983,1)", &truthful),
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 6,
        },
        "got: {:?}",
        predicate("Objective(983,1)", &truthful)
    );

    let contradicting = StubMeta::with(&[((983, 1), 99)]);
    assert_eq!(
        predicate("Objective(983,1)", &contradicting),
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 99,
        },
        "`need` must be read from the provider on every lowering, not from a constant that happens \
         to agree with it. got: {:?}",
        predicate("Objective(983,1)", &contradicting)
    );
}

#[test]
fn an_exploration_objective_lowers_to_need_zero() {
    // A-11-23.lua:264 — `.complete 984,1 -- Find a corrupt furbolg camp` → DSL `Objective(984,1)`.
    //
    // Quest 984 (`How Big a Threat?`) has no `Req*` columns populated at all: it is satisfied by
    // area discovery, not by a count. §7.3.2 and §8 call `need: 0` legal and load-bearing, and the
    // doc comment on `Predicate::QuestObjective::need` (`shared/src/kernel/predicate.rs`) says a
    // positive-count validation here "would make it unsatisfiable". The provider answering 0 is a
    // real answer and must survive as one.
    let meta = StubMeta::with(&[((984, 1), 0)]);
    let lowered = predicate("Objective(984,1)", &meta);
    assert_eq!(
        lowered,
        Predicate::QuestObjective {
            id: 984,
            index: 1,
            need: 0,
        },
        "got: {lowered:?}"
    );
}

#[test]
fn an_objective_the_provider_cannot_answer_is_a_hard_error_not_a_zero() {
    // The distinction the test above depends on: `Some(0)` is "this objective needs no count" and
    // `None` is "the world database could not answer". Collapsing the second into the first
    // manufactures an exploration objective out of a lookup failure, and the resulting task
    // completes the instant it is evaluated.
    let meta = StubMeta::empty();
    let result = lower_predicate("Objective(983,1)", &meta);
    assert!(
        matches!(result, Err(LoweringError::UnknownObjective { quest: 983, index: 1 })),
        "got: {result:?}"
    );
}

#[test]
fn an_unmappable_expression_is_a_hard_error_never_always_true() {
    // The ADR-05 compiler fails open here: the `ActionPayload::Condition(cond)` arm of
    // `resolve_action` (`compiler/src/lib.rs`) records an
    // `UNMAPPED_CONDITION` diagnostic and substitutes `RuntimeCondition::AlwaysTrue`
    // (`compiler/tests/compiler.rs::unmappable_condition_expression_records_diagnostic_and_fails_open`
    // pins that behaviour, and it stays pinned — `Compiler::compile` is unchanged).
    //
    // The kernel cannot do that and must not try: its 24 `Predicate` variants contain no
    // always-true, by design. Per the P3 ingest posture an expression that cannot be mapped is a
    // hard error.
    let meta = StubMeta::empty();
    let result = lower_predicate("NotARealPredicate(1)", &meta);
    let Err(LoweringError::UnmappablePredicate { expression, .. }) = &result else {
        panic!(
            "an unmappable expression must fail the compile, not gate open. got: {result:?}"
        )
    };
    assert!(
        expression.contains("NotARealPredicate"),
        "the error must name the expression it could not map. got: {result:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// D — the entry point: `Compiler::compile_kernel`
//
// Everything above calls `parse_movement` / `lower_route` / `lower_predicate` directly, which says
// nothing about the function that is supposed to assemble them. What `compile_kernel` emits today
// is a **header with an empty pool and no tasks** — deliberately, because the task graph is a later
// deliverable — and the single thing that stops that emptiness reading as a clean compile is the
// `KERNEL_PROFILE_INCOMPLETE` warning. These tests exist so a later edit cannot drop the warning and
// stay green.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A `QuestMeta` that fails the test if it is consulted.
///
/// `compile_kernel` accepts a provider it does not yet use (no task is lowered, so nothing needs a
/// baked `need`). That is a fact worth pinning rather than assuming: see
/// `the_metadata_provider_is_not_consulted_until_the_task_graph_lands`.
struct ForbiddenMeta;

impl QuestMeta for ForbiddenMeta {
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32> {
        panic!(
            "`compile_kernel` consulted the metadata provider for quest {quest} objective {index}. \
             If task lowering now runs, this tripwire has done its job — replace it with a stub \
             that answers, and assert the baked `need` reaches the task's predicate."
        )
    }

    fn objective_item(&self, quest: QuestId, index: u8) -> Option<u32> {
        panic!(
            "`compile_kernel` consulted the metadata provider for the loot filter of quest              {quest} objective {index}. Same tripwire, same remedy."
        )
    }
}

/// The archetype under test. `compile_kernel` takes it as an **input** (C2, §5.2): faction is not
/// readable from the Sylvanas API and there is no race enum, so every static gate is resolved at
/// compile time and one artifact is emitted per archetype.
fn night_elf_druid() -> Archetype {
    Archetype {
        class: Class::Druid,
        race: Race::NightElf,
        faction: Faction::Alliance,
        expansion: Expansion::Tbc,
        allegiance: None,
        hardcore: false,
        self_found: false,
        can_fly: false,
        content_phase: None,
        mode: ProfileMode::SpeedRoute,
        // The three axes §4.2 classifies as archetype filters and `Archetype` gained with C2:
        // `#xprate` in thousandths (1_000 is blizzlike), `#hardcoreserver`, `#season`.
        xp_rate_milli: 1_000,
        hardcore_server: false,
        season: None,
    }
}

fn compiled_kernel() -> (KernelProfile, sentinel_compiler::CompileReport) {
    let project = new_project("Darkshore 11-23");
    Compiler::compile_kernel(&project, &night_elf_druid(), &ForbiddenMeta)
        .unwrap_or_else(|err| panic!("`compile_kernel` must not fail on a well-formed project, got: {err:?}"))
}

#[test]
fn compile_kernel_warns_that_the_artifact_is_incomplete() {
    let (_, report) = compiled_kernel();

    let warning = report
        .unmapped_conditions
        .iter()
        .find(|d| d.code == "KERNEL_PROFILE_INCOMPLETE")
        .unwrap_or_else(|| {
            panic!(
                "`compile_kernel` returns an empty pool and no tasks. Without a \
                 KERNEL_PROFILE_INCOMPLETE diagnostic that emptiness is indistinguishable from a \
                 clean compile of a trivial guide, and the artifact would look shippable. \
                 got: {:?}",
                report.unmapped_conditions
            )
        });

    assert_eq!(
        warning.severity,
        Severity::Warning,
        "got: {warning:?}"
    );
    assert_eq!(
        warning.entity.as_deref(),
        Some("Darkshore 11-23"),
        "the diagnostic must name the guide it refers to. got: {warning:?}"
    );
    // Naming each gap individually, so a partial implementation that closes one of them cannot keep
    // a message that still claims all three.
    for gap in ["task graph", "waypoint pool", "content_hash"] {
        assert!(
            warning.message.contains(gap),
            "the warning must name `{gap}` as a gap, so a reader knows what is missing rather than \
             only that something is. got: {:?}",
            warning.message
        );
    }
    assert_eq!(
        report.unresolved, 0,
        "nothing was resolved, so nothing failed to resolve; `unresolved` counts NPC/object \
         reference failures and must not be repurposed as an incompleteness signal. got: {report:?}"
    );
}

#[test]
fn compile_kernel_emits_zero_placeholder_digests_not_computed_ones() {
    let (profile, _) = compiled_kernel();

    // §5.4 / §5.4.1 make these BLAKE3 digests. They are not computed yet, and the placeholder is
    // all-zero *on purpose*: a wrong-but-plausible digest would pass every shape check and fail
    // only at load, on a machine with no compiler.
    assert_eq!(
        profile.schema_hash, [0u8; 32],
        "got: {:?}",
        profile.schema_hash
    );
    assert_eq!(
        profile.integrity.content_hash, [0u8; 32],
        "got: {:?}",
        profile.integrity.content_hash
    );
    assert!(
        profile.integrity.world_source.is_empty() && profile.integrity.world_build.is_empty(),
        "world provenance is not resolved either, and an invented value would be worse than an \
         empty one. got: {:?}",
        profile.integrity
    );
}

#[test]
fn compile_kernel_emits_a_well_formed_header_for_the_archetype_it_was_given() {
    let (profile, _) = compiled_kernel();

    assert_eq!(profile.magic, MAGIC, "got: {:?}", profile.magic);
    assert_eq!(profile.schema_version, SCHEMA_VERSION);
    assert_eq!(
        profile.archetype,
        night_elf_druid(),
        "the archetype is an input and must be echoed exactly — it is what every compile-time gate \
         was resolved against. got: {:?}",
        profile.archetype
    );
    assert_eq!(
        profile.meta.name, "Darkshore 11-23",
        "got: {:?}",
        profile.meta
    );

    // §5.6: `Defensive` is the profile-level default — 16,438 of 23,894 corpus tasks carry no
    // combat token at all. §5.1.2: `Defer` is the compiler's default for `complete_when`, with the
    // 60-tick budget §7.3.3 uses.
    assert_eq!(
        profile.defaults.combat.stance,
        CombatStance::Defensive,
        "got: {:?}",
        profile.defaults.combat
    );
    assert_eq!(
        profile.defaults.unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 60 },
        "got: {:?}",
        profile.defaults.unknown_policy
    );

    // What it does *not* do yet, asserted so the header above stays honest.
    assert!(profile.waypoint_pool.is_empty(), "got: {:?}", profile.waypoint_pool);
    assert!(profile.tasks.is_empty(), "got: {} tasks", profile.tasks.len());
    assert!(
        profile.tags_used.is_empty(),
        "`tags_used` is every op and predicate tag the artifact references (§5.4); with no tasks \
         there are none, and a non-empty list would name tags nothing uses. got: {:?}",
        profile.tags_used
    );
}

#[test]
fn the_header_compile_kernel_emits_survives_a_serde_round_trip() {
    let (profile, _) = compiled_kernel();

    // "Well-formed as far as it goes": the model denies unknown fields and requires every one of
    // §7.2's root fields, so a header that re-reads as itself is a header no field was left out of.
    // This is a shape check and nothing more — it cannot see that the pool and tasks are empty,
    // which is what `compile_kernel_warns_that_the_artifact_is_incomplete` is for.
    let json = serde_json::to_string(&profile).expect("the emitted header must serialize");
    let reloaded: KernelProfile =
        serde_json::from_str(&json).unwrap_or_else(|err| panic!("emitted header did not re-load: {err}\n{json}"));

    assert_eq!(reloaded, profile, "round trip changed the artifact");
}

#[test]
fn the_metadata_provider_is_not_consulted_until_the_task_graph_lands() {
    // A tripwire, not a requirement. `meta` exists to bake `Predicate::QuestObjective::need` from
    // `quest_template`, and the only consumer of that is a lowered task's `complete_when` — of
    // which `compile_kernel` currently emits none. `ForbiddenMeta` panics on contact, so this test
    // fails the day the provider is genuinely wired in, which is the moment its accompanying
    // assertions should be written.
    let (profile, _) = compiled_kernel();
    assert!(
        profile.tasks.is_empty(),
        "tasks are being lowered now, so the provider must be threaded into their predicates and \
         this tripwire replaced. got: {} tasks",
        profile.tasks.len()
    );
}

#[test]
fn an_unmappable_leaf_is_never_silently_dropped_from_a_tree() {
    // The second half of the same rule, and the easier one to get wrong. Omitting an unmappable
    // leaf from an `And`/`Or` leaves a predicate that still *looks* well-formed:
    // `QuestAccepted(983) && NotARealPredicate(1)` would lower to `QuestInLog { id: 983 }` alone.
    // No gate is fail-open by another name — the dropped conjunct was the restrictive one.
    let meta = StubMeta::empty();
    let result = lower_predicate("QuestAccepted(983) && NotARealPredicate(1)", &meta);

    assert!(
        result.is_err(),
        "an unmappable leaf must fail the whole expression, not be pruned out of it. got: {result:?}"
    );
    assert_ne!(
        result.ok(),
        Some(Predicate::QuestInLog { id: 983 }),
        "the unmappable conjunct was dropped and the surviving predicate gates on less than the \
         author wrote"
    );
}
