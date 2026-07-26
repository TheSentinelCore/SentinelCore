//! RED (runtime): six ways the importer currently loses or fabricates information silently.
//!
//! Every assertion here compiles against the tree as it stands, so each failure is a legible
//! assertion failure rather than a build error. The one remaining defect — `LabelGraph::definitions`
//! must become a multimap — needs a carrier type that does not exist yet and lives in
//! `tests/label_definition_multimap.rs`, which is a deliberate compile-error RED. While that file
//! is red, `cargo test -p sentinel-importer` cannot build; run this one with
//! `cargo test -p sentinel-importer --test import_fidelity_regressions`.
//!
//! What is asserted, and the measurement behind it (all counts re-derived over the seven files of
//! `sentinel/docs/adr/restedxp guides`, 23,894 steps in 277 blocks):
//!
//! | # | Defect | Measured population |
//! |---|--------|---------------------|
//! | D1 | duplicate `#label` names need a diagnostic only when genuinely ambiguous | 65 duplicate-name groups per block |
//! | D2 | `parse_step_gate` never strips the inline `--` dev comment | 17 gates contain `--`; 8 are live enabled steps |
//! | D7 | `gate_disables` scans that same uncleaned tail for `skip` | 0 live false positives today; 1 shape away from one |
//! | D6 | `Token::StepStart::gate` has no serde attributes | serializes `"gate":null` where every sibling omits the key |
//! | D5 | a second `#optional` on one step is dropped by `.next()` | 1 step (TBC:91518) |
//! | D4 | an absorbed placeholder folds only `labels`/`requires` | 52 placeholders; 22 `#optional` + 2 `#xprate` lost |
//!
//! ## WHAT THESE TESTS CANNOT SEE
//!
//! * **They stop at `authoring::Project`.** The 8 mount-check steps are dropped by C2 archetype
//!   resolution, which does not exist yet — `compiler/src/lib.rs::resolve_operation` still discards
//!   `op.conditions` outright. Nothing here proves any gate is ever EVALUATED, only that the
//!   string reaching the model is the author's audience and not their prose.
//! * **The `--` rule is positional, not lexical.** `shared/src/source.rs::strip_inline_dev_comment`
//!   truncates at the FIRST `--`, so a gate that legitimately contained `--` would be cut too.
//!   Zero corpus gates do; that is measured, not guaranteed.
//! * **D1's diagnostic test is synthetic.** The three shapes are copied from real lines but the
//!   65-group census is not re-derived at runtime (it costs ~25s over the full corpus). Measured
//!   split: 42 groups where every definition AND its step are ungated (genuinely ambiguous),
//!   21 where the `step` markers are complementary (`Prowlers`, A-1-11-Human:1273/:1280), 2 where
//!   the `#label` directives themselves are gated (`UldaLoch`, TBC:16256/:16264). A
//!   `DUPLICATE_LABEL` rule that looks only at the DIRECTIVE gate fires 63 times — 21 of them
//!   false. That trap is what this file's first test exists to catch.
//! * **D4 accepts either remedy.** Fold the entry or diagnose its loss; the assertion is only that
//!   it does not vanish in silence. A build that folds `#optional` but still drops a gated
//!   `#completewith` from a placeholder passes — no corpus placeholder carries one (measured: 0).
//! * **They cannot see the game.** Whether a step that survives here produces the right in-game
//!   route is untested by construction.

use sentinel_importer::{parse_guide, parse_guide_bundle, ProjectBuilder, Token};
use sentinel_models::authoring::{Diagnostic, Project, Severity};
use sentinel_queryclient::MemoryQueryClient;

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../sentinel/docs/adr/restedxp guides");

async fn build(guide: &str) -> Project {
    let parsed = parse_guide(guide).expect("parse ok");
    ProjectBuilder::build(&parsed, "corpus.lua", &MemoryQueryClient::new())
        .await
        .expect("build ok")
}

/// Every `Step` of a real corpus file, keyed by its file-absolute source line.
/// `parse_guide_bundle` already shifts block-relative lines to file-absolute ones, so these keys
/// are directly comparable to `ripgrep` line numbers.
fn corpus_steps_by_line(file: &str) -> std::collections::HashMap<usize, sentinel_importer::Step> {
    let path = format!("{CORPUS}/{file}");
    let src = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("the real corpus is the fixture here — {path}: {e}"));
    let mut out = std::collections::HashMap::new();
    for guide in parse_guide_bundle(&src) {
        let guide = guide.expect("block parses");
        for step in guide.steps {
            out.insert(step.line, step);
        }
    }
    out
}

fn codes(project: &Project, code: &str) -> Vec<Diagnostic> {
    project.diagnostics.iter().filter(|d| d.code == code).cloned().collect()
}

// ===========================================================================
// D1 — a duplicated `#label` name is ambiguous only when nothing distinguishes the definitions.
// The tie-break itself belongs to C2 (it needs a resolved archetype); the importer's whole job
// here is to keep both definitions and to say so only when they are genuinely indistinguishable.
// ===========================================================================

/// `A-1-11-NightElf.lua:1016` / `:1366`  — `#label harpies` twice, both ungated, both on ungated
///                                          steps. Genuinely ambiguous: 42 groups look like this.
/// `The Burning Crusade.lua:16256` / `:16264` — `#label UldaLoch << Mage` vs `#label UldaLoch`
///                                          under `step << !Mage`. 2 groups look like this.
/// `A-1-11-Human.lua:1273` / `:1280`     — `#label Prowlers` twice, ungated DIRECTIVES on
///                                          complementary `step << Paladin` / `step << !Paladin`
///                                          markers. 21 groups look like this.
///
/// The last shape is the trap. Its `#label` lines are byte-identical and carry no tail, so a rule
/// that inspects only the directive's own gate reports it as a duplicate — 21 false warnings on
/// legitimate, complementary definitions. The gate that disambiguates lives on the `step`.
#[tokio::test]
async fn duplicate_label_is_diagnosed_only_when_nothing_distinguishes_the_definitions() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Dups
step
    #label harpies
    .goto Darkshore,45.00,32.00
step
    #label harpies
    .goto Darkshore,45.00,33.00
step
    #label UldaLoch << Mage
    .goto Loch Modan,37.067,49.379
step << !Mage
    #label UldaLoch
    .goto Loch Modan,33.938,50.954
step << Paladin
    #label Prowlers
    .goto Elwynn Forest,41.529,65.900
step << !Paladin
    #label Prowlers
    .goto Elwynn Forest,41.530,65.901
]])"#,
    )
    .await;

    let dups = codes(&project, "DUPLICATE_LABEL");

    assert_eq!(
        dups.len(),
        1,
        "exactly ONE of the three duplicate groups is ambiguous. `harpies` \
         (A-1-11-NightElf:1016/:1366) has two identical ungated definitions on two ungated steps \
         and nothing can ever choose between them — that is the only one worth reporting. \
         Got: {dups:?}"
    );
    assert!(
        dups[0].message.contains("harpies"),
        "the diagnostic must NAME the ambiguous label so an operator can find it. Got: {:?}",
        dups[0].message
    );

    assert!(
        !dups.iter().any(|d| d.message.contains("UldaLoch")),
        "TBC:16256/:16264 are disambiguated by `<< Mage` on the directive and `<< !Mage` on the \
         step. Reporting them trains operators to ignore the code. Got: {dups:?}"
    );
    assert!(
        !dups.iter().any(|d| d.message.contains("Prowlers")),
        "A-1-11-Human:1273/:1280 — the `#label` lines are IDENTICAL; only their `step` markers \
         (`Paladin` / `!Paladin`) differ. A rule that reads the directive gate alone fires here, \
         and on 20 other legitimate groups. Got: {dups:?}"
    );
}

// ===========================================================================
// D2 — `importer/src/guide_splitter.rs::parse_step_gate` never stripped the inline `--` dev
// comment. `shared/src/source.rs::strip_inline_dev_comment` already exists (re-exported as
// `importer/src/lexer.rs::strip_inline_dev_comment`) and is already applied to every COMMAND tail
// by `importer/src/lexer.rs::extract_class_suffix`. Step tails were missed.
// ===========================================================================

/// `A-23-30.lua:2998, :3886, :4971, :6064   step << Gnome !Warlock -- checking if gnomes can get mount`
/// `A-23-30.lua:3015, :3900, :4985, :6080   step << Dwarf !Paladin -- checking if dwarfs can get mount`
///
/// Eight LIVE, enabled steps. Under the documented grammar (`Gate := AndGroup (WS AndGroup)*`,
/// `AndGroup := Term ('/' Term)*`, `Term := '!'? Ident`) the tail as it currently arrives parses as
/// nine conjoined terms — `Gnome`, `!Warlock`, `--`, `checking`, `if`, `gnomes`, `can`, `get`,
/// `mount` — which is unsatisfiable for EVERY archetype. C2 will silently drop all eight.
///
/// Driven over the real file rather than a synthetic string so it pins those exact steps: a fix
/// that special-cases one shape, or a corpus edit that moves them, is caught here.
#[test]
fn a_step_gate_never_carries_its_inline_dev_comment() {
    const MOUNT_CHECKS: &[(usize, &str)] = &[
        (2998, "Gnome !Warlock"),
        (3015, "Dwarf !Paladin"),
        (3886, "Gnome !Warlock"),
        (3900, "Dwarf !Paladin"),
        (4971, "Gnome !Warlock"),
        (4985, "Dwarf !Paladin"),
        (6064, "Gnome !Warlock"),
        (6080, "Dwarf !Paladin"),
    ];

    let steps = corpus_steps_by_line("A-23-30.lua");

    for (line, expected) in MOUNT_CHECKS {
        let step = steps
            .get(line)
            .unwrap_or_else(|| panic!("A-23-30.lua:{line} is a `step` marker in the corpus"));
        assert_eq!(
            step.gate.as_deref(),
            Some(*expected),
            "A-23-30.lua:{line} — the gate is the author's AUDIENCE, not their prose. \
             `-- checking if gnomes can get mount` is a dev comment and must be stripped exactly \
             as `.collect 2589,1 << Paladin --Linen Cloth (1+)` already is on the command side"
        );
        assert_eq!(
            step.conditions,
            vec![expected.to_string()],
            "A-23-30.lua:{line} — `parse_step_conditions` shares the root cause and leaks the same \
             comment into the lossy `/`-split list that `is_known_class_token` reads"
        );
    }

    let leaking: Vec<(usize, &str)> = steps
        .iter()
        .filter_map(|(l, s)| s.gate.as_deref().filter(|g| g.contains("--")).map(|g| (*l, g)))
        .collect();
    assert!(
        leaking.is_empty(),
        "no `step` gate in A-23-30.lua may contain a `--` comment; 10 do today. Got: {leaking:?}"
    );
}

/// `A-1-11-Dwarf-Gnome.lua:1824  step << skip --logout skip << Warrior`
/// `A-23-30.lua:445, :466        step << skip --logout skip NightElf/Draenei`
///
/// The one gate in the corpus carrying a SECOND `<<`. The first-`<<` split rule
/// (`importer/src/guide_splitter.rs::parse_step_gate`) was never designed for it and hands back
/// `"skip --logout skip << Warrior"` — the whole comment, second arrow and all. Stripping the dev
/// comment first resolves it without a new rule: everything after `--` is prose, including that
/// second `<<`, so the gate is just the `skip` sentinel. The step stays DISABLED either way; what
/// changes is whether `Warrior` is readable as an audience.
#[test]
fn a_gate_whose_comment_contains_a_second_arrow_reduces_to_its_skip_sentinel() {
    let dg = corpus_steps_by_line("A-1-11-Dwarf-Gnome.lua");
    let step = &dg[&1824];
    assert_eq!(
        step.gate.as_deref(),
        Some("skip"),
        "DG:1824 — `skip --logout skip << Warrior`. `Warrior` sits INSIDE the dev comment; leaving \
         it in the gate is the difference between a disabled step and a Warrior-only step"
    );

    let a2330 = corpus_steps_by_line("A-23-30.lua");
    for line in [445usize, 466] {
        assert_eq!(
            a2330[&line].gate.as_deref(),
            Some("skip"),
            "A-23-30.lua:{line} — `skip --logout skip NightElf/Draenei`; the races are the \
             author's note about WHAT was turned off, not an audience"
        );
    }
}

// ===========================================================================
// D7 — same root cause, opposite face: `importer/src/project_builder.rs::gate_disables` scans the
// raw
// tail INCLUDING the comment for an unnegated `skip`.
// ===========================================================================

/// No corpus step triggers this today (measured: every `skip` inside a `--` comment sits on a step
/// whose gate ALSO says `skip` before the comment). It is one authored line away: the moment
/// someone writes `step << Rogue -- skip this for now`, a live Rogue step goes dark with no
/// diagnostic, no error, and no trace in the imported project.
#[tokio::test]
async fn a_skip_that_appears_only_inside_a_dev_comment_does_not_disable_the_step() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Comment Skip
step << Rogue -- skip this for now
    .accept 1598 >> Accept The Stolen Tome
]])"#,
    )
    .await;

    let op = &project.operations[0];
    assert!(
        op.enabled,
        "`skip` is a disable SENTINEL in the gate, not a word in the author's prose. The step is \
         gated `Rogue` and enabled; disabling it deletes a real step from the route silently"
    );
    assert_eq!(
        op.gate.as_ref().map(|g| g.0.as_str()),
        Some("Rogue"),
        "and the audience that survives is `Rogue`, with no comment words conjoined onto it"
    );
}

/// `A-23-30.lua:2998  step << Gnome !Warlock -- checking if gnomes can get mount`
///
/// The mirror guard: stripping the comment must not accidentally turn a live step off, and the
/// eight mount-check steps must still be enabled once their gate is clean.
#[tokio::test]
async fn the_mount_check_step_stays_enabled_with_only_its_audience_as_the_gate() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Mount Check
step << Gnome !Warlock -- checking if gnomes can get mount
    #optional
    .train 33388 >>Train Apprentice Riding
]])"#,
    )
    .await;

    let op = &project.operations[0];
    assert_eq!(
        op.gate.as_ref().map(|g| g.0.as_str()),
        Some("Gnome !Warlock"),
        "A-23-30:2998 — a RACE plus a negated CLASS, and nothing else"
    );
    assert!(op.enabled, "A-23-30:2998 is a live step the author left ON");
}

// ===========================================================================
// D6 — `importer/src/lexer.rs::Token::StepStart` gained `gate: Option<String>` with no serde
// attributes. `importer/src/lib.rs::Step::gate`, `importer/src/lib.rs::Directive::original` and
// `importer/src/lib.rs::Command::class_restriction` all carry
// `#[serde(default, skip_serializing_if = "Option::is_none")]`.
// ===========================================================================

/// MEASURED CORRECTION, stated so this test is not oversold: the *deserialize* half of this defect
/// does not exist. serde's derive already treats a missing `Option<T>` field as `None`, so a
/// payload written before the field was added still round-trips — verified below and kept as a
/// guard, not as the RED.
///
/// The real asymmetry is on the way OUT: a gateless `StepStart` emits `"gate":null` where every
/// sibling carrier in this crate omits the key entirely. That is a wire-shape divergence in a
/// public `Serialize` type, and it is exactly the kind of drift the Rust↔Lua contract rules in
/// `CLAUDE.md` say fails silently rather than loudly.
///
/// (`Token::StepDirective::original` and `Token::Command::class_restriction` have the same gap.
/// They are not asserted here because they predate this change; a fix should cover them too.)
#[test]
fn a_gateless_step_start_token_omits_the_gate_key_like_every_sibling_carrier() {
    let bare = Token::StepStart { conditions: Vec::new(), gate: None, line: 5 };
    let json = serde_json::to_value(&bare).expect("Token serializes");
    let payload = json.get("StepStart").expect("externally tagged variant");

    assert!(
        payload.get("gate").is_none(),
        "`Step::gate` writes NO `gate` key when there is none \
         (`importer/src/lib.rs::Step::gate` carries \
         `skip_serializing_if = \"Option::is_none\"`); the Token variant writes `\"gate\":null`. \
         Match it. Got: {payload}"
    );

    // Guard, already green: a payload predating the field must still load.
    let old: Token = serde_json::from_str(r#"{"StepStart":{"conditions":[],"line":5}}"#)
        .expect("a StepStart written before `gate` existed must still deserialize");
    assert_eq!(old, bare, "and it must load as an ungated step, not a defaulted-away one");

    // Guard: a real gate is still written.
    let gated = Token::StepStart {
        conditions: vec!["Mage".to_string()],
        gate: Some("Mage".to_string()),
        line: 5,
    };
    let json = serde_json::to_value(&gated).expect("Token serializes");
    assert_eq!(json["StepStart"]["gate"], serde_json::json!("Mage"));
}

// ===========================================================================
// D5 — `importer/src/project_builder.rs::step_optionals` took `.next()` and dropped the rest.
// ===========================================================================

/// `The Burning Crusade.lua:91518-91527`
/// ```text
/// 91518  step << Horde
/// 91519      #optional
/// ...
/// 91526      .turnin 5888 >> Turn in Salve via Mining
/// 91527      #optional
/// ```
/// The ONE step in the corpus that stacks two (measured over all 23,894). Both are bare, so the
/// surviving value is identical and nothing observable is lost TODAY — which is precisely why it
/// must be reported: the next one to stack two may gate them differently
/// (`#optional << Horde` + `#optional << !Horde` collapses to the first), and then the drop is
/// silent and wrong.
#[tokio::test]
async fn a_second_optional_on_one_step_is_reported_not_silently_swallowed() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Two Optional
step << Horde
    #optional
    .accept 5888 >> Accept Salve via Mining
    #optional
    .turnin 5888 >> Turn in Salve via Mining
]])"#,
    )
    .await;

    let op = &project.operations[0];
    let kept = op.optional.as_ref().expect("the first `#optional` is kept");
    assert_eq!(kept.line, 6, "TBC:91519 — the first one wins, deterministically");

    let discarded: Vec<&Diagnostic> = project
        .diagnostics
        .iter()
        .filter(|d| d.severity == Severity::Info && d.code.contains("OPTIONAL"))
        .collect();

    assert_eq!(
        discarded.len(),
        1,
        "TBC:91527 — the SECOND `#optional` is dropped by `.next()`. Dropping is an acceptable \
         rule; dropping in silence is not. Got diagnostics: {:?}",
        project.diagnostics
    );
    assert!(
        discarded[0].message.contains("line 8"),
        "the diagnostic must name the DISCARDED directive's source line (line 8 here, TBC:91527 in \
         the corpus), following the `(line {{}})` convention of UNRESOLVED_COMPLETEWITH. \
         Got: {:?}",
        discarded[0].message
    );
}

// ===========================================================================
// D4 — the placeholder fold (`importer/src/project_builder.rs::ProjectBuilder::build`, the
// `if is_placeholder_step(step)` branch) moves `labels` and `requires` onto the
// absorbing step and drops everything else the placeholder carried.
// ===========================================================================

/// `A-11-23.lua:731-741`
/// ```text
/// 731  step
/// 732      #xprate <1.5
/// 733      #optional
/// 734      #requires Relics
/// 735  --XXREQ Placeholder invis step until multiple requires per step
/// 736  step
/// 737      #xprate <1.5
/// ...
/// 741  step
/// ```
/// Measured across all 52 placeholders: 22 `#optional` and 2 `#xprate` (A-11-23:732 and :737) are
/// discarded by the fold. Zero `#completewith` and zero gated placeholders, so those two shapes are
/// out of scope by measurement, not by argument.
///
/// `#xprate` is not decoration — it decides whether a step belongs to the route at all, and the
/// absorbing step inherits the placeholder's requirement without inheriting the condition under
/// which that requirement was authored.
///
/// Either remedy satisfies this test: fold the entry onto the absorbing operation, or emit a
/// diagnostic naming what was dropped. Silence does not.
#[tokio::test]
async fn an_absorbed_placeholder_does_not_silently_lose_its_optional_and_directives() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Fold
step
#xprate <1.5
    #optional
    #requires Relics
--XXREQ Placeholder invis step until multiple requires per step
step
#xprate <1.5
    .goto Darkshore,43.30,58.20
]])"#,
    )
    .await;

    assert_eq!(project.operations.len(), 1, "A-11-23:731 — the placeholder emits no task");
    let op = &project.operations[0];

    // Guard, already green: the two directives that DO fold today still do.
    assert!(
        op.requires.iter().any(|r| r.value == "Relics"),
        "A-11-23:734 — the parked `#requires` folds in; that half already works"
    );
    assert!(
        op.directives.iter().any(|d| d.name == "xprate" && d.line == 11),
        "the absorbing step's OWN `#xprate` (A-11-23:737) is untouched — pinned so the assertion \
         below cannot be satisfied by it"
    );

    let optional_folded = op.optional.as_ref().is_some_and(|o| o.line == 7);
    let optional_diagnosed = project.diagnostics.iter().any(|d| {
        d.message.to_lowercase().contains("optional") && d.message.contains("line 7")
    });
    assert!(
        optional_folded || optional_diagnosed,
        "A-11-23:733 — the placeholder's `#optional` (line 7 here) must reach the absorbing \
         operation or be diagnosed by line. It lowers to kernel `Task.blocking = false`, so \
         losing it turns 22 non-blocking corpus steps into blocking ones. \
         Got optional={:?}, diagnostics={:?}",
        op.optional,
        project.diagnostics
    );

    let xprate_folded = op.directives.iter().any(|d| d.name == "xprate" && d.line == 6);
    let xprate_diagnosed = project
        .diagnostics
        .iter()
        .any(|d| d.message.contains("xprate") && d.message.contains("line 6"));
    assert!(
        xprate_folded || xprate_diagnosed,
        "A-11-23:732 — the placeholder's own `#xprate <1.5` (line 6 here) must reach the absorbing \
         operation or be diagnosed by line. Got directives={:?}, diagnostics={:?}",
        op.directives,
        project.diagnostics
    );
}
