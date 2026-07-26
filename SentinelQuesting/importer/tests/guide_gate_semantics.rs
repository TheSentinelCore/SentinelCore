//! RED (behavioral): gate semantics the importer gets wrong TODAY, asserted with the API that
//! already exists. These tests compile against `HEAD` and fail on behavior, not on a missing
//! type — they are the half of the task-graph work that needs no new fields.
//!
//! Companion file: `task_graph_directives.rs` holds the tests that require the new authoring
//! carriers (`Operation::labels/requires/complete_with/optional/gate/directives/placeholder`)
//! and therefore fail to compile until those land.
//!
//! ## WHAT THESE TESTS CANNOT SEE
//!
//! * **They are synthetic fragments, not the corpus.** Every asserted line is copied verbatim
//!   from a named guide line, but the surrounding steps are trimmed to the minimum. Nothing here
//!   measures corpus-scale figures (139 `<< skip` steps, 65 duplicate-label groups, 51 globally
//!   unresolvable `#completewith`); a fix that satisfies these tests can still be wrong at scale.
//! * **They are single-block.** Each guide is one `RXPGuides.RegisterGuide([[ ]])` block, so
//!   they exercise `parse_guide`, never `parse_guide_bundle`. Label-resolution *scope* — the
//!   choice between per-block (277 blocks, 80 unresolved) and per-file (54 unresolved) — is
//!   invisible here. Choosing wrong will not fail these tests.
//! * **They use `MemoryQueryClient::new()` with no fixtures.** Quests and NPCs never resolve, so
//!   actions degrade to `Comment`/`Condition`. These tests therefore assert on gating and
//!   diagnostics only, never on a resolved payload; a regression in quest resolution is invisible.
//! * **Diagnostic codes are pinned as strings.** `UNRESOLVED_REQUIRES` / `UNRESOLVED_COMPLETEWITH`
//!   are proposed names. Renaming the code fails the test with zero behavior change, and
//!   conversely a diagnostic with the right code but a useless message still passes.
//! * **They stop at the authoring boundary.** Nothing here proves the compiler lowers any of it.
//!   `compiler/src/lib.rs::resolve_operation` still hardcodes `entry_conditions`/`exit_conditions`
//!   empty,
//!   so a step gate that survives into `Operation` can still die one crate later and these tests
//!   stay green.
//! * **They assert gate *presence*, never gate *evaluation*.** No test here proves
//!   `!Paladin !Warlock !Hunter` yields the right boolean for any archetype. C2 archetype
//!   resolution is out of scope.
//! * **They cannot see the game.** Whether a disabled step *should* be disabled is the guide
//!   author's judgement, taken on faith from the `skip` sentinel.

use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_queryclient::MemoryQueryClient;

// ---------------------------------------------------------------------------
// `skip` is a DISABLE SENTINEL, not an archetype token.
// Measured: 139 occurrences, all 139 on a `step` marker, never negated, never in a `/`-list.
// Today `parse_step_conditions` splits on `/` only, `is_known_class_token` rejects the result,
// and `op.enabled` is never set false anywhere in project_builder.rs — so all 139 disabled
// steps compile into live, executing tasks.
// ---------------------------------------------------------------------------

/// `The Burning Crusade.lua:86156  step << skip Horde`
/// `A-1-11-Dwarf-Gnome.lua:2551    step << Warrior skip`
/// plus the dominant bare form (115 of 139) `step << skip`.
#[tokio::test]
async fn skip_sentinel_in_a_step_gate_disables_the_operation() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Skip Sentinel
step << skip Horde
    .complete 4002,1
step << Warrior skip
    .trainer >> Train your class spells
step << skip
    .goto Elwynn Forest,41.529,65.900
step << Horde
    .turnin 4002 >> Turn in The Eastern Kingdoms
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "skip.lua", &client).await.expect("build ok");
    assert_eq!(project.operations.len(), 4, "one operation per step");

    // TBC:86156 — a disabled duplicate of the `<< Horde` step at :86162, not a Horde-only step.
    assert!(
        !project.operations[0].enabled,
        "`step << skip Horde` (TBC:86156) must import DISABLED; `skip` absorbs the rest of the tail"
    );
    // DG:2551 — the author's note at :2550 explains why this Warrior block was turned off.
    assert!(
        !project.operations[1].enabled,
        "`step << Warrior skip` (DG:2551) must import DISABLED, not as a Warrior-only step"
    );
    assert!(
        !project.operations[2].enabled,
        "bare `step << skip` (115 of 139 occurrences) must import DISABLED"
    );
    // Control: a real gate must NOT disable the step.
    assert!(
        project.operations[3].enabled,
        "`step << Horde` (TBC:85496) is an audience gate, not a disable — it must stay enabled"
    );
}

/// `A-1-11-Dwarf-Gnome.lua:2551  step << Warrior skip`
/// `The Burning Crusade.lua:86156 step << skip Horde`
///
/// `skip` is absorbing: the other token in the tail must not become an audience restriction.
/// Treating `Warrior skip` as "Warrior-only" would resurrect a step the author turned off, and
/// treating `skip Horde` as "Horde-only" hides the disable behind a faction filter.
#[tokio::test]
async fn skip_does_not_narrow_the_step_to_the_other_token_in_its_tail() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Skip Absorbs
step << Warrior skip
    .goto Ironforge,65.905,88.405
    .trainer >> Train your class spells
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "skip.lua", &client).await.expect("build ok");
    let op = &project.operations[0];

    assert!(
        !op.enabled,
        "`skip` must absorb its tail: `step << Warrior skip` (DG:2551) is a step the author \
         turned OFF, not a Warrior-only step. Reading `Warrior` as the audience resurrects it"
    );
    for action in &op.actions {
        assert_eq!(
            action.class_restriction, None,
            "`skip` absorbs its tail: no action may be stamped with `Warrior` from `<< Warrior skip`"
        );
    }
}

// ---------------------------------------------------------------------------
// LabelGraph: the gate tail must be stripped BEFORE keying, on definitions and references alike.
// `importer/src/label_graph.rs::LabelGraphBuilder::resolve` inserted the whole value as the key,
// and checked `next` before any stripping. Both were live mis-resolutions in the shipped corpus.
// ---------------------------------------------------------------------------

/// `The Burning Crusade.lua:16241  #completewith UldaLoch`
/// `The Burning Crusade.lua:16256  #label UldaLoch << Mage`
/// `The Burning Crusade.lua:16264  #label UldaLoch`   (under `step << !Mage` at :16263)
///
/// Today `:16256` registers under the key `"UldaLoch << Mage"`, so it is unreachable and every
/// character — Mage included — binds `:16241` to `:16264`. Same shape at `:121423/121444/121452`.
#[tokio::test]
async fn label_definition_with_a_gate_tail_is_keyed_by_its_name_not_the_whole_value() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ulda
step
    #completewith UldaLoch
    .zone Loch Modan >> Travel to Loch Modan
step
    #label UldaLoch << Mage
    .turnin 17 >> Turn in Uldaman Reagent Run
step << !Mage
    #label UldaLoch
    .goto Loch Modan,33.938,50.954
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");

    assert!(
        parsed.labels.definitions.contains_key("UldaLoch"),
        "`#label UldaLoch << Mage` (TBC:16256) must be keyed by the NAME `UldaLoch`; \
         the `<< Mage` tail is an audience gate, not part of the label. Got keys: {:?}",
        parsed.labels.definitions.keys().collect::<Vec<_>>()
    );
    assert!(
        !parsed.labels.definitions.keys().any(|k| k.contains("<<")),
        "no label key may contain a `<<` tail. Got keys: {:?}",
        parsed.labels.definitions.keys().collect::<Vec<_>>()
    );
    assert!(
        parsed.labels.unresolved.is_empty(),
        "`#completewith UldaLoch` (TBC:16241) resolves — it must not be reported unresolved: {:?}",
        parsed.labels.unresolved
    );
}

/// `The Burning Crusade.lua:4065  #completewith BetterIngredientTI << Druid`
/// `The Burning Crusade.lua:4066  #completewith next << !Druid`
/// `The Burning Crusade.lua:4075  #label BetterIngredientTI`
///
/// `next` is the ONLY reserved word (2,681 uses; never used as a `#label`). Ten lines spell it
/// `#completewith next << <gate>`. `importer/src/label_graph.rs::LabelGraphBuilder::resolve`
/// compared against `next` BEFORE stripping the tail, so all ten were misfiled as references to a
/// label literally named `"next << !Druid"`,
/// which then reports as unresolved.
#[tokio::test]
async fn completewith_next_with_a_gate_is_the_reserved_word_not_a_label_reference() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ingredient
step
    #completewith BetterIngredientTI << Druid
    #completewith next << !Druid
    .zone Un'Goro Crater >>Travel to Un'Goro Crater
step
    .goto Un'Goro Crater,45.53,8.72
step
    #label BetterIngredientTI
    .turnin 3527 >> Turn in The Ancient Egg
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");

    assert!(
        !parsed.labels.references.iter().any(|r| r.label.starts_with("next")),
        "`#completewith next << !Druid` (TBC:4066) is the reserved word `next`, gated — \
         it must not be recorded as a label reference. Got: {:?}",
        parsed.labels.references
    );
    // The sibling line on the same step DOES reference a real label, and it resolves at :4075.
    assert!(
        parsed.labels.references.iter().any(|r| r.label == "BetterIngredientTI"),
        "`#completewith BetterIngredientTI << Druid` (TBC:4065) must be recorded under the bare \
         name `BetterIngredientTI`. Got: {:?}",
        parsed.labels.references
    );
    assert!(
        parsed.labels.unresolved.is_empty(),
        "both lines on TBC:4065-4066 resolve (one to :4075, one to the reserved word): {:?}",
        parsed.labels.unresolved
    );
}

// NOTE: the sibling claim "`end` is a real label, never a reserved word" (TBC:11260 / :11289 —
// 11 `#label end` definitions, 15 references) is ALREADY GREEN at HEAD, because
// `importer/src/label_graph.rs::LabelGraphBuilder::resolve` compares only against `next`. It is asserted in `task_graph_directives.rs::
// completewith_end_is_a_label_and_whitespace_targets_survive` rather than duplicated here, so this
// file stays entirely RED. It matters because the obvious fix for the two bugs above — "reserve
// the terminator keywords" — would break all 15 of those references.

// ---------------------------------------------------------------------------
// Diagnostics. `LabelGraph{definitions,references,unresolved}` is computed by `parse_guide` and
// attached to NOTHING — `project_builder.rs` never reads `guide.labels`, so an unresolved
// reference produces no project diagnostic at all. `#requires` is not even looked at.
//
// Standing ruling being locked here: unresolved is ERROR severity, the step SURVIVES, the guide
// still compiles. (Verified safe: all 51 globally-unresolvable `#completewith` steps carry their
// own completion predicate.)
// ---------------------------------------------------------------------------

/// Modeled on the 51 `#completewith` references that resolve nowhere in the corpus. The step
/// keeps its own `.turnin` completion, so dropping it would delete real route work.
#[tokio::test]
async fn unresolved_completewith_is_an_error_diagnostic_and_the_step_survives() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Dangling
step
    #completewith NeverDefinedAnywhere
    .turnin 3528 >> Turn in The God Hakkar
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "dangling.lua", &client).await.expect("build ok");

    assert_eq!(project.operations.len(), 1, "the step must NOT be dropped");
    assert!(
        !project.operations[0].actions.is_empty(),
        "the step keeps its own completion predicate as the fallback"
    );
    let d = project
        .diagnostics
        .iter()
        .find(|d| d.code == "UNRESOLVED_COMPLETEWITH")
        .unwrap_or_else(|| {
            panic!(
                "an unresolved `#completewith` must surface as a project diagnostic; \
                 LabelGraph::unresolved is currently computed and wired to nothing. Got: {:?}",
                project.diagnostics.iter().map(|d| &d.code).collect::<Vec<_>>()
            )
        });
    assert_eq!(
        d.severity,
        sentinel_models::authoring::Severity::Error,
        "unresolved `#completewith` is error-severity (the ordering intent is lost), \
         but non-fatal — the step still compiles"
    );
}

/// `A-1-11-Draenei.lua:4380  #requires prospector`
///
/// One of the 4 `#requires` values that do not resolve in-block; 2 of the 4 resolve nowhere in
/// the whole corpus. The edge is dropped, the step is kept.
#[tokio::test]
async fn unresolved_requires_is_an_error_diagnostic_and_the_step_survives() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Prospector
step
    #requires prospector
    .complete 731,1
    .isOnQuest 731
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "draenei.lua", &client).await.expect("build ok");

    assert_eq!(project.operations.len(), 1, "the step must NOT be dropped (Draenei:4379)");
    let d = project
        .diagnostics
        .iter()
        .find(|d| d.code == "UNRESOLVED_REQUIRES")
        .unwrap_or_else(|| {
            panic!(
                "an unresolved `#requires` must surface as a project diagnostic; `#requires` is \
                 currently lexed into Step.directives and read by nothing. Got: {:?}",
                project.diagnostics.iter().map(|d| &d.code).collect::<Vec<_>>()
            )
        });
    assert_eq!(
        d.severity,
        sentinel_models::authoring::Severity::Error,
        "unresolved `#requires` is error-severity, edge dropped, step retained"
    );
}
