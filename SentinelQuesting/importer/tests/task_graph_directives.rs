//! RED (compile-error): the RestedXP task graph must survive the importer boundary.
//!
//! `#requires`, `#completewith`, `#optional`, the `#` archetype selectors, and the full `<<` gate
//! expression are all lexed into `sentinel_importer::Step` today and then dropped — `Operation`
//! has nowhere to put them. These tests name the carriers the implementation must add:
//!
//! ```text
//! authoring::GuideGate(String)                     // raw `<<` tail, unparsed
//! authoring::Gated<T> { value, gate, line }        // one directive entry + its own audience
//! authoring::CompleteWithTarget { Next, Label(_) } // adjacently tagged
//! authoring::GuideDirective { name, value, gate, line }
//!
//! Operation::labels:        Vec<Gated<String>>
//! Operation::requires:      Vec<Gated<String>>
//! Operation::complete_with: Vec<Gated<CompleteWithTarget>>
//! Operation::optional:      Option<Gated<()>>
//! Operation::gate:          Option<GuideGate>
//! Operation::directives:    Vec<GuideDirective>
//! Operation::placeholder:   bool
//! Action::gate:             Option<GuideGate>
//! ```
//!
//! Until those exist this file does not compile. That is the intended RED for Rust: the failure
//! is `E0609 no field` / `E0432 unresolved import`, never a wrong assertion.
//!
//! ## WHAT THESE TESTS CANNOT SEE
//!
//! * **They pin shape, not census.** Every asserted line is copied verbatim from a named corpus
//!   line, but the guide fragments are synthetic and tiny. The measured population — 2,581
//!   `#label`, 350 `#requires`, 5,470 `#completewith`, 3,067 `#optional`, 139 `<< skip`, 49
//!   requirement placeholders — is NOT re-derived here. An implementation can satisfy every
//!   assertion below and still mishandle a shape that occurs only in the other 17,700 steps.
//! * **`GuideGate` is asserted as a verbatim string. Nothing here parses or evaluates it.**
//!   `Gate := AndGroup (WS AndGroup)*`, `AndGroup := Term ('/' Term)*`, `Term := '!'? Ident` is
//!   documented, not tested. No assertion proves `!Paladin !Warlock !Hunter` yields the right
//!   boolean for any archetype — C2 archetype resolution is a later change. These tests only
//!   prove the string reaches `Operation`/`Action` intact so C2 *can* be written.
//! * **They are single-block, so resolution SCOPE is invisible.** Each fragment is one
//!   `RegisterGuide([[ ]])` block. The per-block (277 blocks, 80 unresolved) vs per-file (54
//!   unresolved) decision, and the duplicate-name tie-break across 65 groups, are not exercised.
//! * **They stop at `authoring::Project`.** Nothing proves the compiler lowers any of it.
//!   `compiler/src/lib.rs::resolve_operation` hardcodes `entry_conditions`/`exit_conditions` empty
//!   and
//!   `parse_class_guard` still fails open on every non-class token; both can stay broken with
//!   this file fully green. No kernel `Task.blocking` / `Task.deps` lowering is asserted.
//! * **They say nothing about ordering or acyclicity.** The measured fact that 346/346 resolvable
//!   `#requires` edges point backward is not re-checked; a fix that introduces a forward edge
//!   passes.
//! * **`MemoryQueryClient::new()` resolves no quests or NPCs**, so actions degrade to
//!   `Comment`/`Condition`. Assertions are on directives and gates only.
//! * **`.requires quest,4004 << Horde` (TBC:86258) is a COMMAND, not the `#requires` directive.**
//!   No test here distinguishes them; a builder that conflated the two would not be caught.
//! * **They cannot see the game.** Whether a folded placeholder or a disabled step produces the
//!   right in-game route is untested by construction.

use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_models::authoring::{CompleteWithTarget, GuideGate};
use sentinel_queryclient::MemoryQueryClient;

async fn build(guide: &str) -> sentinel_models::authoring::Project {
    let parsed = parse_guide(guide).expect("parse ok");
    ProjectBuilder::build(&parsed, "corpus.lua", &MemoryQueryClient::new())
        .await
        .expect("build ok")
}

/// Helper: the raw tail string of an optional gate, for readable assertions.
fn gate_str(g: &Option<GuideGate>) -> Option<&str> {
    g.as_ref().map(|g| g.0.as_str())
}

// ===========================================================================
// #label — 2,581 definitions, 1,560 distinct values.
// Survives today ONLY as the Operation's NAME (`importer/src/project_builder.rs::operation_name`
// formats `label:{}`),
// which conflates the label with the display name and cannot represent two labels on one step.
// ===========================================================================

/// `The Burning Crusade.lua:102579  #label Un'Goro End`
/// referenced by `The Burning Crusade.lua:103798  #completewith Un'Goro End`
///
/// 4 of the 1,560 distinct label values contain whitespace. A whitespace tokeniser truncates
/// this to `Un'Goro` and fabricates an edge to a label that does not exist.
#[tokio::test]
async fn label_keeps_internal_whitespace_and_apostrophes_verbatim() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ungoro
step
    #label Un'Goro End
    .goto Un'Goro Crater,45.53,8.72
]])"#,
    )
    .await;

    let labels = &project.operations[0].labels;
    assert_eq!(labels.len(), 1, "one `#label` on the step");
    assert_eq!(
        labels[0].value, "Un'Goro End",
        "TBC:102579 — the label name is `Un'Goro End`, spaces and apostrophe intact; \
         never split on whitespace"
    );
    assert_eq!(gate_str(&labels[0].gate), None, "no `<<` tail on this line");
    assert_eq!(labels[0].line, 6, "source line of the `#label` directive, for diagnostics");
}

/// `A-1-11-Human.lua:1383      #label WarlockPrincess << Warlock`
/// `A-1-11-Human.lua:1395      #label Deed << !Warlock`
/// `The Burning Crusade.lua:16256  #label UldaLoch << Mage`
///
/// 4 definitions carry an audience tail. It must split off the NAME on the FIRST `<<` — the tail
/// is a gate, not part of the label. Today `importer/src/label_graph.rs::LabelGraphBuilder::resolve`
/// keys on the whole value, which
/// makes the Mage-specific `UldaLoch` at TBC:16256 unreachable for everyone.
#[tokio::test]
async fn label_splits_its_gate_tail_off_the_name() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Gated Labels
step
    #label WarlockPrincess << Warlock
    .complete 88,1
step
    #label Deed << !Warlock
    .goto Elwynn Forest,70.5,77.6,60,0
]])"#,
    )
    .await;

    let a = &project.operations[0].labels[0];
    assert_eq!(a.value, "WarlockPrincess", "A-1-11-Human:1383 — name only, tail stripped");
    assert_eq!(
        gate_str(&a.gate),
        Some("Warlock"),
        "A-1-11-Human:1383 — the `<< Warlock` tail is carried as a gate, not discarded"
    );

    let b = &project.operations[1].labels[0];
    assert_eq!(b.value, "Deed", "A-1-11-Human:1395 — name only");
    assert_eq!(
        gate_str(&b.gate),
        Some("!Warlock"),
        "A-1-11-Human:1395 — negation is preserved verbatim inside the gate"
    );
}

/// `The Burning Crusade.lua:16256  #label UldaLoch << Mage`   (its own step)
/// `The Burning Crusade.lua:16263  step << !Mage`
/// `The Burning Crusade.lua:16264  #label UldaLoch`
///
/// Two definitions of the SAME name inside one block, disambiguated only by their gates. 2 of the
/// 65 duplicate-name groups are this shape, so a pure first-definition-wins tie-break is wrong;
/// both definitions must reach the model with their gates so resolution can choose.
#[tokio::test]
async fn same_name_labels_are_both_kept_with_their_distinguishing_gates() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ulda
step
    #label UldaLoch << Mage
    .turnin 17 >> Turn in Uldaman Reagent Run
step << !Mage
    #label UldaLoch
    .goto Loch Modan,33.938,50.954
]])"#,
    )
    .await;

    let mage = &project.operations[0].labels[0];
    assert_eq!(mage.value, "UldaLoch");
    assert_eq!(
        gate_str(&mage.gate),
        Some("Mage"),
        "TBC:16256 — the Mage-only definition keeps its gate; without it this definition is \
         indistinguishable from TBC:16264 and silently loses the tie-break"
    );

    let other = &project.operations[1].labels[0];
    assert_eq!(other.value, "UldaLoch");
    assert_eq!(gate_str(&other.gate), None, "TBC:16264 — ungated definition of the same name");
}

/// `The Burning Crusade.lua:118138  #label end`
/// `The Burning Crusade.lua:118139  #label ExitSoS`
///
/// One step, two labels. `labels` must be a `Vec`; the current name-only carrier
/// (`importer/src/project_builder.rs::operation_name`) picks the first and drops the second,
/// dangling
/// every reference to it.
#[tokio::test]
async fn two_labels_on_one_step_are_both_captured() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Two Labels
step
    #label end
    #label ExitSoS
    #completewith ExitBL
    .goto Swamp of Sorrows,33.23,67.31,0
]])"#,
    )
    .await;

    let names: Vec<&str> = project.operations[0].labels.iter().map(|l| l.value.as_str()).collect();
    assert_eq!(
        names,
        vec!["end", "ExitSoS"],
        "TBC:118138-118139 — both labels on one step, in source order"
    );
}

// ===========================================================================
// #requires — 350 occurrences. Lexed into Step.directives and READ BY NOTHING; the only mention
// in the whole Rust tree outside the lexer is the typo alias in
// `importer/src/lexer.rs::DIRECTIVE_TYPOS` (`("requries", "requires")`).
// ===========================================================================

/// `The Burning Crusade.lua:24728  #requires cloth1`
/// `The Burning Crusade.lua:24729  #requires cloth2`
/// (`#label cloth2` is at `:24717`; `cloth1` is the Bubulo Acerbus turn-in set.)
///
/// Stacking is how RestedXP expresses multiplicity — there is no separator anywhere in the corpus
/// (zero commas, zero semicolons in any `#requires` value). Both entries are ungated, so both
/// survive archetype resolution and are ANDed: this step needs BOTH cloth turn-in sets done.
#[tokio::test]
async fn requires_is_a_list_and_two_stacked_ungated_entries_are_both_kept() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Cloth
step
    #label cloth2
    .turnin 7802 >> Turn in A Donation of Wool
step
    #requires cloth1
    #requires cloth2
    .goto Ironforge,33.4,20.0,70,0
]])"#,
    )
    .await;

    let reqs = &project.operations[1].requires;
    assert_eq!(
        reqs.len(),
        2,
        "TBC:24728-24729 — two stacked `#requires` lines are two entries, not one overwritten by \
         the other. Got: {reqs:?}"
    );
    assert_eq!(reqs[0].value, "cloth1");
    assert_eq!(reqs[1].value, "cloth2");
    assert_eq!(gate_str(&reqs[0].gate), None, "ungated — always applies");
    assert_eq!(gate_str(&reqs[1].gate), None, "ungated — always applies");
    // CORRECTED DURING GREEN (was 8/9 — an arithmetic slip in the fixture's line count, not a
    // behavior claim). Counting the raw string above with its leading empty line as line 1:
    // 1 ``, 2 `RXPGuides…`, 3 `#version`, 4 `#name`, 5 `step`, 6 `#label`, 7 `.turnin`, 8 `step`,
    // 9 `#requires cloth1`, 10 `#requires cloth2`. Three independent proofs that 9/10 is right:
    //   (a) the two sibling assertions in this file — `label_keeps_internal_whitespace…` and
    //       `bare_optional_is_captured_on_the_operation`, both expecting 6 — use exactly this
    //       convention; under the count that yields 8/9 here they would both have to be 5;
    //   (b) ripgrep over the real corpus puts `#requires cloth1` on `The Burning Crusade.lua:24728`
    //       and `#label Un'Goro End` on `:102579`, and the importer now reports those verbatim;
    //   (c) that agreement required fixing a real off-by-one in `guide_splitter.rs::extract_body`
    //       (`lines().count() + 1`), which had shifted EVERY SourceLineNo in the crate one line
    //       high. Reverting to 8/9 would mean re-breaking (a) and (b).
    assert_eq!(reqs[0].line, 9, "TBC:24728 maps to its own source line");
    assert_eq!(reqs[1].line, 10, "TBC:24729 maps to its own source line");
}

/// `The Burning Crusade.lua:91092  #requires FlyMoongladeH << Horde`
/// `The Burning Crusade.lua:91093  #requires FlyMoongladeA << Alliance`
///
/// THE test that forces the per-entry gate. These two stack exactly like `cloth1`/`cloth2`
/// (TBC:24728-24729) but mean the opposite: they are mutually unsatisfiable for a fixed
/// character. Merging the gate into one step-level field, or ANDing the raw values, produces an
/// unsatisfiable requirement for every Alliance character in Felwood. Carried per entry, the
/// gate-unsatisfied one is dropped at C2 and the remaining single edge is correct.
#[tokio::test]
async fn stacked_requires_keep_their_own_audience_tails_separately() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Moonglade
step
    #completewith TimbermawEndOne
    #requires FlyMoongladeH << Horde
    #requires FlyMoongladeA << Alliance
    .zoneskip Moonglade
]])"#,
    )
    .await;

    let reqs = &project.operations[0].requires;
    assert_eq!(reqs.len(), 2, "TBC:91092-91093 — two entries");
    assert_eq!(reqs[0].value, "FlyMoongladeH", "name only; the `<<` tail is not part of it");
    assert_eq!(
        gate_str(&reqs[0].gate),
        Some("Horde"),
        "TBC:91092 — the Horde gate belongs to THIS entry alone"
    );
    assert_eq!(reqs[1].value, "FlyMoongladeA");
    assert_eq!(
        gate_str(&reqs[1].gate),
        Some("Alliance"),
        "TBC:91093 — the Alliance gate belongs to THIS entry alone; if the two gates merge, the \
         faction-exclusive OR is destroyed before resolution can use it"
    );
}

/// `A-1-11-Dwarf-Gnome.lua:407  #requires TroggEnd << !Paladin !Warlock !Hunter`
///
/// The gate is a multi-token AND of negated class terms. Whitespace is the AND operator, so a
/// whitespace tokeniser that keeps only the first token silently widens the gate from
/// "not paladin AND not warlock AND not hunter" to "not paladin".
#[tokio::test]
async fn requires_gate_keeps_every_negated_term_in_a_multi_token_tail() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Trogg
step
    #requires TroggEnd << !Paladin !Warlock !Hunter
    .turnin 182 >> Turn in The Troll Cave
]])"#,
    )
    .await;

    let req = &project.operations[0].requires[0];
    assert_eq!(req.value, "TroggEnd");
    assert_eq!(
        gate_str(&req.gate),
        Some("!Paladin !Warlock !Hunter"),
        "DG:407 — the whole tail is the gate, verbatim and unsplit; whitespace is AND"
    );
}

// ===========================================================================
// #completewith — 5,470 occurrences. Survives today only as import diagnostics in
// `label_graph.rs`; `LabelGraph` is computed and attached to nothing.
// ===========================================================================

/// `The Burning Crusade.lua:4065  #completewith BetterIngredientTI << Druid`
/// `The Burning Crusade.lua:4066  #completewith next << !Druid`
///
/// `next` (2,681 uses) is the ONLY reserved word and must be a distinct variant, not a label
/// named "next". It is never used as a `#label` (0 occurrences), so the namespaces do not
/// collide. The gate must strip FIRST — otherwise these 10 gated `next` lines are misfiled.
#[tokio::test]
async fn completewith_distinguishes_the_reserved_next_from_a_label_target() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ingredient
step
    #completewith BetterIngredientTI << Druid
    #completewith next << !Druid
    .zone Un'Goro Crater >>Travel to Un'Goro Crater
]])"#,
    )
    .await;

    let cw = &project.operations[0].complete_with;
    assert_eq!(cw.len(), 2, "TBC:4065-4066 — two stacked entries (9 steps in the corpus do this)");

    assert_eq!(
        cw[0].value,
        CompleteWithTarget::Label("BetterIngredientTI".to_string()),
        "TBC:4065 — a label target, name only"
    );
    assert_eq!(gate_str(&cw[0].gate), Some("Druid"));

    assert_eq!(
        cw[1].value,
        CompleteWithTarget::Next,
        "TBC:4066 — `next` is the reserved literal, even when it carries a `<<` tail; \
         the tail must be stripped BEFORE the `next` comparison"
    );
    assert_eq!(gate_str(&cw[1].gate), Some("!Druid"));
}

/// `The Burning Crusade.lua:11260  #completewith end`
/// `The Burning Crusade.lua:11289  #label end`
/// `The Burning Crusade.lua:103798 #completewith Un'Goro End`
///
/// `end` is a real label (11 definitions, 15 references) — reserving it would break them all.
/// `Un'Goro End` is the one `#completewith` value containing whitespace.
#[tokio::test]
async fn completewith_end_is_a_label_and_whitespace_targets_survive() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Ends
step
    #completewith end
    .goto Ironforge,43.224,31.574
step
    #completewith Un'Goro End
    .goto Un'Goro Crater,45.53,8.72
]])"#,
    )
    .await;

    assert_eq!(
        project.operations[0].complete_with[0].value,
        CompleteWithTarget::Label("end".to_string()),
        "TBC:11260 — `end` is a LABEL; only `next` is reserved"
    );
    assert_eq!(
        project.operations[1].complete_with[0].value,
        CompleteWithTarget::Label("Un'Goro End".to_string()),
        "TBC:103798 — internal whitespace preserved; it must resolve to `#label Un'Goro End` \
         at TBC:102579"
    );
}

// ===========================================================================
// #optional — 3,067 occurrences, bare in 3,038, gated in 29. Maps to kernel `Task.blocking=false`.
// Today it is inspected only inside `.accept`/`.turnin` lowering
// (`importer/src/project_builder.rs::ProjectBuilder`, the `AcceptQuestAction`/`TurnInQuestAction`
// arms)
// to set `AcceptQuestAction::optional`; the step-level fact never reaches `Operation`.
// ===========================================================================

/// `A-1-11-Human.lua:3103  step << Mage/Priest/Warlock`
/// `A-1-11-Human.lua:3104  #optional`
///
/// The bare form (3,038 of 3,067). Note the lexer yields `value: None` here, and `value: Some("")`
/// for the 2 lines written `#optional ` with a trailing space — both are bare.
#[tokio::test]
async fn bare_optional_is_captured_on_the_operation() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Wand
step << Mage/Priest/Warlock
    #optional
    .use 11288
]])"#,
    )
    .await;

    let opt = project.operations[0]
        .optional
        .as_ref()
        .expect("A-1-11-Human:3104 — a bare `#optional` must reach the Operation; \
                 it lowers to kernel Task.blocking = false");
    assert_eq!(gate_str(&opt.gate), None, "bare — no audience tail");
    assert_eq!(opt.line, 6);
}

/// `A-23-30.lua:433               #optional << Dwarf Paladin`
/// `The Burning Crusade.lua:35668 #optional << tbc/wotlk`
/// `A-11-23.lua:133               #optional << !NightElf`
/// `A-1-11-Human.lua:938          #optional << Warrior/Rogue/Paladin`
///
/// 29 of 3,067 carry a gate. Gated `#optional` means "non-blocking FOR THIS ARCHETYPE, blocking
/// otherwise" — it collapses to a bool only after C2, so the gate must survive the importer.
/// The lexer hands this directive a value of `"<< Dwarf Paladin"` (no head before the `<<`), so
/// the gate parse must tolerate a leading `<<` with an empty head.
#[tokio::test]
async fn gated_optional_carries_its_full_gate() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Optional Gates
step
    #optional << Dwarf Paladin
    .goto Dun Morogh,25.076,75.713
step
    #optional << tbc/wotlk
    .zone Blasted Lands >> Travel to the Blasted Lands
step
    #optional << !NightElf
    .goto 1439,36.634,46.250
step
    #optional << Warrior/Rogue/Paladin
    .goto Elwynn Forest,41.529,65.900
]])"#,
    )
    .await;

    let g = |i: usize| {
        project.operations[i]
            .optional
            .as_ref()
            .unwrap_or_else(|| panic!("operation {i} must carry `#optional`"))
            .gate
            .as_ref()
            .map(|g| g.0.clone())
    };

    assert_eq!(
        g(0).as_deref(),
        Some("Dwarf Paladin"),
        "A-23-30:433 — a two-token RACE+CLASS conjunction. `parse_step_conditions` splits only \
         on `/`, so this is exactly the shape that currently degrades to an inert single token"
    );
    assert_eq!(
        g(1).as_deref(),
        Some("tbc/wotlk"),
        "TBC:35668 — an ERA gate. `<<` carries tbc/wotlk/classic/era/sod 958 times; it is not a \
         class-only language"
    );
    assert_eq!(g(2).as_deref(), Some("!NightElf"), "A-11-23:133 — a negated RACE gate");
    assert_eq!(
        g(3).as_deref(),
        Some("Warrior/Rogue/Paladin"),
        "A-1-11-Human:938 — `/` is OR within one group; the group must stay intact, not be \
         shredded into three unrelated tokens"
    );
}

// ===========================================================================
// `<<` gates — step level and command level, VERBATIM and in full.
// Vocabulary measured over every `<<` tail in the corpus: 10 classes + DK(178)/Pala(2); races
// Dwarf Draenei NightElf Gnome Human BloodElf Troll Tauren Undead Orc; factions Alliance(809)
// Horde(953); eras tbc(241)/wotlk(121)/classic(4)/era(14)/sod; a level bound !70; and `skip`(139).
// The compiler's 10-entry KNOWN_CLASSES sees a small minority of that.
// ===========================================================================

/// `A-1-11-Human.lua:3103          step << Mage/Priest/Warlock`   (class OR-group)
/// `The Burning Crusade.lua:4875   step << !tbc !wotlk`           (ERA, whitespace-AND)
/// `A-23-30.lua:380                step << Dwarf Paladin`          (RACE + CLASS, whitespace-AND)
/// `The Burning Crusade.lua:85496  step << Horde`                  (FACTION)
/// `A-1-11-Human.lua:14            step << !Human`                 (negated RACE)
/// `The Burning Crusade.lua:47908  step << BloodElf !Warlock !Paladin` (RACE + two negated CLASSes)
///
/// `importer/src/guide_splitter.rs::parse_step_conditions` splits on `/` ONLY, then
/// `importer/src/project_builder.rs` stamps a class guard only when EVERY token passes the 10-name
/// `importer/src/project_builder.rs::is_known_class_token`. So the era, race, faction and mixed
/// gates below all produce NO guard today; `op.conditions` is then discarded outright by
/// `compiler/src/lib.rs::resolve_operation`. The raw
/// tail must be preserved unsplit so the AND/OR/`!` grammar is still recoverable at C2.
#[tokio::test]
async fn step_gate_is_preserved_verbatim_and_unsplit_for_every_vocabulary_family() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Gates
step << Mage/Priest/Warlock
    .use 11288
step << !tbc !wotlk
    .goto 1419/0,-3196.90015,-11815.10059
step << Dwarf Paladin
    .goto Dun Morogh,25.076,75.713
step << Horde
    .turnin 4002 >> Turn in The Eastern Kingdoms
step << !Human
    .goto Elwynn Forest,41.529,65.900
step << BloodElf !Warlock !Paladin
    .complete 11055,1
step
    .goto Ironforge,43.224,31.574
]])"#,
    )
    .await;

    let gate = |i: usize| gate_str(&project.operations[i].gate).map(str::to_string);

    assert_eq!(
        gate(0).as_deref(),
        Some("Mage/Priest/Warlock"),
        "A-1-11-Human:3103 — CLASS OR-group kept as one expression, not three tokens"
    );
    assert_eq!(
        gate(1).as_deref(),
        Some("!tbc !wotlk"),
        "TBC:4875 — ERA gate. 49 steps say `<< DK wotlk`, 19 say `<< !tbc !wotlk`; all of them \
         are inert today"
    );
    assert_eq!(
        gate(2).as_deref(),
        Some("Dwarf Paladin"),
        "A-23-30:380 — RACE+CLASS conjunction (40 occurrences), inert today"
    );
    assert_eq!(
        gate(3).as_deref(),
        Some("Horde"),
        "TBC:85496 — FACTION gate. Horde appears 953 times and Alliance 809 in `<<` tails; \
         neither is a class"
    );
    assert_eq!(
        gate(4).as_deref(),
        Some("!Human"),
        "A-1-11-Human:14 — negated RACE gate, inert today"
    );
    assert_eq!(
        gate(5).as_deref(),
        Some("BloodElf !Warlock !Paladin"),
        "TBC:47908 — RACE plus two negated CLASSes (16 occurrences); mixed tails never pass \
         `is_known_class_token`, so nothing is stamped"
    );
    assert_eq!(gate(6), None, "a bare `step` has no gate");
}

/// `A-1-11-Human.lua:665           .collect 2589,1 << Paladin --Linen Cloth (1+)`  (CLASS, with a
///                                 trailing dev comment that must not leak into the gate)
/// `The Burning Crusade.lua:7210   .goto 1419/0,-3196.90015,-11815.10059 << !tbc !wotlk`  (ERA)
/// `The Burning Crusade.lua:86266  .complete 4003,1 << Horde`                             (FACTION)
/// `A-23-30.lua:3883               .zone Dun Morogh >>...[Ram] << Dwarf !Paladin`         (RACE)
///
/// MEASURED CAVEAT, stated so this test is not oversold: the raw tail ALREADY survives verbatim
/// into `Action::class_restriction` today (confirmed by probe — `"!tbc !wotlk"` and
/// `"BloodElf !Warlock"` both arrive intact). This test is RED only because there is no gate-typed,
/// non-class-named carrier. That naming is load-bearing, not cosmetic: everything downstream of
/// `class_restriction` — `compiler/src/lib.rs::parse_class_guard` against a 10-entry
/// `KNOWN_CLASSES` — treats the field as a class list and degrades every race/faction/era tail to
/// an `UNKNOWN_CLASS_RESTRICTION` warning with no guard. An implementation may instead widen
/// `class_restriction` in place; if it does, delete `Action::gate` from this test and assert the
/// same strings on the existing field.
#[tokio::test]
async fn command_gate_is_carried_as_a_gate_not_narrowed_to_a_class() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Command Gates
step
    .collect 2589,1 << Paladin --Linen Cloth (1+)
    .goto 1419/0,-3196.90015,-11815.10059 << !tbc !wotlk
    .complete 4003,1 << Horde
    .zone Dun Morogh >> Travel to Amberstill Ranch and buy your Ram << Dwarf !Paladin
]])"#,
    )
    .await;

    let actions = &project.operations[0].actions;
    assert_eq!(actions.len(), 4, "one action per command");

    assert_eq!(
        gate_str(&actions[0].gate),
        Some("Paladin"),
        "A-1-11-Human:665 — CLASS gate, with the trailing `--Linen Cloth (1+)` dev comment \
         stripped off the tail"
    );
    assert_eq!(
        gate_str(&actions[1].gate),
        Some("!tbc !wotlk"),
        "TBC:7210 — ERA gate on a command; `parse_class_guard` fails open on this today"
    );
    assert_eq!(
        gate_str(&actions[2].gate),
        Some("Horde"),
        "TBC:86266 — FACTION gate on a command; fails open today"
    );
    assert_eq!(
        gate_str(&actions[3].gate),
        Some("Dwarf !Paladin"),
        "A-23-30:3883 — RACE plus negated CLASS on a command; fails open today"
    );
}

/// `The Burning Crusade.lua:86156  step << skip Horde`
/// `A-1-11-Dwarf-Gnome.lua:2551    step << Warrior skip`
///
/// `skip` disables the step and ABSORBS the rest of the tail (it is never negated, never appears
/// in a `/`-list, and never occurs outside a `step` marker). The tail is still carried verbatim
/// so the import stays auditable, but it must NOT be readable as an archetype restriction —
/// `Horde` and `Warrior` here are the author's note about *what* was turned off, not an audience.
#[tokio::test]
async fn skip_disables_the_step_while_the_tail_stays_verbatim_but_inert() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Skip
step << skip Horde
    .complete 4002,1
step << Warrior skip
    .trainer >> Train your class spells
]])"#,
    )
    .await;

    assert!(!project.operations[0].enabled, "TBC:86156 — disabled");
    assert!(!project.operations[1].enabled, "DG:2551 — disabled");

    assert_eq!(
        gate_str(&project.operations[0].gate),
        Some("skip Horde"),
        "the raw tail is preserved verbatim for provenance — an import that silently drops it \
         cannot be audited against the source guide"
    );
    for op in &project.operations {
        for action in &op.actions {
            assert_eq!(
                action.gate, None,
                "`skip` absorbs its tail: no action may inherit `Horde` or `Warrior` as an \
                 audience gate from a disabled step"
            );
        }
    }
}

// ===========================================================================
// `#` archetype selectors — lexed into Step.directives and read by NOTHING. `project_builder.rs`
// inspects Step.directives at exactly four sites (label :793, optional :904/:945, sticky :1405,
// loop :1406) plus the typo-diagnostic loop at :1408. `Operation` has no directives field, so
// every other directive dies at the importer boundary.
// ===========================================================================

/// `A-11-23.lua:302                #xprate <1.5`     (721 occurrences, takes a value)
/// `The Burning Crusade.lua:2729   #phase 4-6`       (174, takes a value)
/// `The Burning Crusade.lua:7777   #aldor`           (238, bare)
/// `The Burning Crusade.lua:7771   #scryer`          (208, bare)
/// `The Burning Crusade.lua:521    #hardcore`        (59, bare)
///
/// These are the archetype selectors C2 resolution needs. `#xprate` and `#phase` in particular
/// decide whether a step belongs to the route at all.
#[tokio::test]
async fn archetype_directives_reach_the_operation_verbatim() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Archetypes
step
    #xprate <1.5
    #phase 4-6
    #aldor
    .goto 1439,35.743,43.710
step
    #scryer
    #hardcore
    .goto Shattrath City,54.751,44.322
]])"#,
    )
    .await;

    let find = |i: usize, name: &str| {
        project.operations[i]
            .directives
            .iter()
            .find(|d| d.name == name)
            .unwrap_or_else(|| {
                panic!(
                    "`#{name}` must reach Operation::directives; got {:?}",
                    project.operations[i]
                        .directives
                        .iter()
                        .map(|d| &d.name)
                        .collect::<Vec<_>>()
                )
            })
    };

    assert_eq!(
        find(0, "xprate").value.as_deref(),
        Some("<1.5"),
        "A-11-23:302 — `#xprate` carries a comparison value; dropping it makes the 721 xp-rate \
         branches unselectable"
    );
    assert_eq!(
        find(0, "phase").value.as_deref(),
        Some("4-6"),
        "TBC:2729 — `#phase` carries a range value"
    );
    assert_eq!(find(0, "aldor").value, None, "TBC:7777 — bare");
    assert_eq!(find(1, "scryer").value, None, "TBC:7771 — bare");
    assert_eq!(find(1, "hardcore").value, None, "TBC:521 — bare");

    // The four already-consumed directives must not be duplicated into the passthrough bag,
    // and the passthrough bag must not swallow them either — pin the boundary explicitly.
    assert!(
        !project.operations[0].directives.iter().any(|d| d.name == "label"),
        "`#label` has a typed carrier (Operation::labels) and must not also appear in the \
         untyped passthrough bag"
    );
}

/// `A-11-23.lua:8  #xprate >1.49 << Human Warlock`
///
/// A directive value may itself carry a `<<` tail. (This particular line sits in the HEADER
/// region, before the first `step`, so it lands in `Token::GuideHeader` rather than
/// `Step.directives` — the shape is reproduced here in step position, where 721 other `#xprate`
/// lines live, to pin the gate split for archetype directives too.)
#[tokio::test]
async fn archetype_directive_splits_its_own_gate_tail() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Gated Archetype
step
    #xprate >1.49 << Human Warlock
    .goto 1439,35.743,43.710
]])"#,
    )
    .await;

    let d = &project.operations[0].directives[0];
    assert_eq!(d.name, "xprate");
    assert_eq!(d.value.as_deref(), Some(">1.49"), "value only — the tail is not part of it");
    assert_eq!(
        gate_str(&d.gate),
        Some("Human Warlock"),
        "A-11-23:8 — a RACE+CLASS gate on an archetype directive, split off the value"
    );
}

// ===========================================================================
// Requirement placeholder steps — the XXREQ idiom. The structural pattern occurs 49 times; only
// 6 carry the `--XXREQ` comment, so the comment must NOT be the detector.
// ===========================================================================

/// `A-1-11-Human.lua:3414-3420`
/// ```text
/// 3414  step
/// 3415      #optional
/// 3416      #requires RabidThistle
/// 3417  --XXREQ Placeholder invis step until multiple requires per step
/// 3418  step
/// 3419      #requires BuzzBox1
/// 3420      .goto 1439,36.634,46.250
/// ```
/// The real step at `:3418` wants `RabidThistle` AND `BuzzBox1`; the second requirement is parked
/// in the empty step above it because RestedXP has no multi-requires syntax.
///
/// Detection rule (structural, per the measurement): a step is a placeholder iff, after
/// discarding blanks and `--` comments, it contains no `Command` and no `Text` token — only
/// `StepDirective` — AND carries at least one `#requires`. `#optional` is present on only 12 of
/// the 49, so it must not be part of the predicate.
#[tokio::test]
async fn requirement_placeholder_folds_its_requires_into_the_next_real_step() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Placeholder
step
    #optional
    #requires RabidThistle
--XXREQ Placeholder invis step until multiple requires per step
step
    #requires BuzzBox1
    .goto 1439,36.634,46.250
    .turnin 983 >> Turn in Buzzbox 827
]])"#,
    )
    .await;

    assert_eq!(
        project.operations.len(),
        1,
        "A-1-11-Human:3414 — the placeholder emits no task of its own; only the real step at \
         :3418 survives. Got {} operations",
        project.operations.len()
    );
    let reqs: Vec<&str> = project.operations[0].requires.iter().map(|r| r.value.as_str()).collect();
    assert_eq!(
        reqs,
        vec!["RabidThistle", "BuzzBox1"],
        "the parked `#requires` from the placeholder is folded in AHEAD of the step's own, \
         in source order"
    );
    assert!(
        !project.operations[0].placeholder,
        "the surviving step is a real step, not a placeholder"
    );
}

/// `The Burning Crusade.lua:113121-113138` — a run of SEVEN consecutive placeholders, none of
/// which carries `#optional` or the `--XXREQ` comment. This is why the detector must be
/// structural and must fold a maximal RUN, not a single step.
#[tokio::test]
async fn a_run_of_placeholders_folds_wholesale_into_the_following_step() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Mudlump
step
#requires NetherwingCrystals
step
#requires NethermineFlayerHide
step
#requires NetherciteOre
step
#requires NetherdustPollen
step
#requires PeonPoisoned
step
#requires NetherwingRelics
step
#requires PeonDisciplined
step
.isOnQuest 11055
.goto 1948/530,547.900,-5105.000
]])"#,
    )
    .await;

    assert_eq!(
        project.operations.len(),
        1,
        "TBC:113121-113135 — seven placeholders collapse into the single real step at :113136"
    );
    let reqs: Vec<&str> = project.operations[0].requires.iter().map(|r| r.value.as_str()).collect();
    assert_eq!(
        reqs,
        vec![
            "NetherwingCrystals",
            "NethermineFlayerHide",
            "NetherciteOre",
            "NetherdustPollen",
            "PeonPoisoned",
            "NetherwingRelics",
            "PeonDisciplined",
        ],
        "all seven parked requirements land on the absorbing step, in source order"
    );
}

/// `A-1-11-Dwarf-Gnome.lua:1961-1967`
/// ```text
/// 1961  step
/// 1962      #optional
/// 1963      #label RockjawEnd
/// 1964      #requires Skullthumpers
/// 1965  --XXREQ Placeholder invis step until multiple requires per step
/// 1966  step
/// 1967      >>...Talk to Foreman Stonebrow and Senator Mehr Stonehallow
/// ```
/// The ONE placeholder of the 49 that also defines a label. Emitting no task for it is correct,
/// but the label must still be DEFINED — pointing at the absorbing step — or every
/// `#completewith RockjawEnd` dangles.
#[tokio::test]
async fn a_label_on_a_placeholder_survives_on_the_absorbing_step() {
    let project = build(
        r#"
RXPGuides.RegisterGuide([[
#version 7
#name Rockjaw
step
    #optional
    #label RockjawEnd
    #requires Skullthumpers
--XXREQ Placeholder invis step until multiple requires per step
step
    >>Talk to Foreman Stonebrow and Senator Mehr Stonehallow
    .turnin 313 >> Turn in In Defense of the King's Lands
]])"#,
    )
    .await;

    assert_eq!(project.operations.len(), 1, "DG:1961 — the placeholder emits no task");
    let op = &project.operations[0];
    assert!(
        op.labels.iter().any(|l| l.value == "RockjawEnd"),
        "DG:1963 — `#label RockjawEnd` must still resolve, now to the absorbing step at :1966; \
         dropping it dangles every reference. Got: {:?}",
        op.labels
    );
    assert!(
        op.requires.iter().any(|r| r.value == "Skullthumpers"),
        "DG:1964 — the parked requirement folds in too"
    );
}
