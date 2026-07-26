//! C2 — **every gate resolves against a concrete archetype at compile time, and no gate survives
//! into the artifact.**
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §2.5 "Gating grammar", §5.2 (C2), §9 item 7.
//! Corpus: `sentinel/docs/adr/restedxp guides`. Every expression below is quoted with the guide
//! file and line it was measured at, so each expectation can be re-derived from the source rather
//! than trusted.
//!
//! This is not a tidiness rule. The kernel has no `ClassIs` / `RaceIs` / `FactionIs` predicate —
//! `Predicate` (`shared/src/kernel/predicate.rs`) declares none — and the Sylvanas API cannot
//! answer "am I Alliance?": `shared/src/kernel/profile.rs::Archetype`'s doc comment records that
//! `game_object:get_faction_id()` returns a *unit faction template*, that the only faction-side
//! call works in arena/battleground context only, and that no race enum is documented anywhere.
//! A residual gate is therefore **unrepresentable**, not merely untidy.
//!
//! # What these tests prove
//!
//! * **The three operators are pinned separately, each by an archetype that separates it from its
//!   plausible alternative.** A test that asserts `Dwarf Paladin` matches a Dwarf Paladin proves
//!   nothing: it holds under AND, under OR, and under "ignore the second token". Every operator
//!   test below also asserts the archetype that the *wrong* reading would have admitted.
//! * **Precedence is settled by the corpus, not chosen.** `Gnome !Warlock/Dwarf !Paladin` (14
//!   uses) has three plausible readings and exactly two archetypes separate them; both are
//!   asserted.
//! * **Ambiguity is a diagnostic, not a guess.** A gate mixing `/` and space is flagged *and*
//!   resolved by the documented rule. Because C2 resolves at compile time, a wrong choice silently
//!   includes or excludes 10 steps with no runtime trace whatsoever.
//! * **`skip` is a disable sentinel, never vocabulary.** Resolving it as an archetype token
//!   silently *enables* 140 steps the authors turned off, and the failure is invisible: the step
//!   just runs.
//! * **An unknown token is a hard error.** Silently skipping what a resolver does not understand is
//!   how a previous attempt reached 60% coverage; RXPGuides itself refuses
//!   (`addon.error("Invalid function call")`).
//! * **Resolution happens at OP granularity.** 3,052 command-level `<<` gates across 134 distinct
//!   expressions (measured; §2.5 states the counting rule), so a task-granular resolver is wrong on
//!   every one of them.
//! * **Nothing carrying a gate reaches the artifact** — asserted by walking the *serialized*
//!   profile, not the typed one, because the typed model has no gate field to inspect and a gate
//!   would have to arrive smuggled inside some other string.
//!
//! # What these tests CANNOT see
//!
//! * **Whether the derived precedence is what the guide authors meant.** §9 item 7 is explicit that
//!   authorial intent for `Alliance/Horde Hunter` is "genuinely unclear". These tests pin that the
//!   compiler applies the rule §2.5 derives *and says so out loud*; they cannot pin that the rule
//!   matches the author's head. That is precisely why the diagnostic is asserted alongside the
//!   outcome — the diagnostic is the only part of this that is unambiguously correct.
//! * **Whether the `Archetype` a caller supplies describes a legal character.** The resolver is a
//!   pure function of the archetype record. `gnome_paladin()` below is not a legal TBC combination
//!   and is used anyway, because it is the *only* assignment that separates two of the three
//!   candidate precedences. A resolver that validated race/class legality would refuse it and these
//!   tests would say so — but nothing here demands such validation, and the artifact header's
//!   archetype is provenance, not a claim of playability.
//! * **That the corpus census is complete.** Every count below was measured over the seven vendored
//!   guides with `rg`. If the corpus is later extended the counts move and these tests do not
//!   notice; they assert *behaviour on the quoted expressions*, and only the two census tests
//!   (`the_mixed_operator_census_is_eleven_expressions`, `the_normalisation_table_is_closed`)
//!   assert a total.
//! * **The importer's half of the contract.** These tests construct the authoring model directly
//!   rather than round-tripping a guide through `sentinel-importer`, so nothing here proves the
//!   importer populates `Operation::gate`, `Operation::enabled`, `Operation::directives` or
//!   `Action::gate`. That is pinned upstream by
//!   `importer/tests/task_graph_directives.rs::step_gate_is_preserved_verbatim_and_unsplit_for_every_vocabulary_family`,
//!   `::command_gate_is_carried_as_a_gate_not_narrowed_to_a_class`,
//!   `::skip_disables_the_step_while_the_tail_stays_verbatim_but_inert` and
//!   `::archetype_directives_reach_the_operation_verbatim`.
//! * **`.dungeon` provenance.** The importer currently preserves `.dungeon` as a typed inert
//!   `Comment` carrying a `COMMAND_PRESERVED_INERT` diagnostic
//!   (`importer/src/project_builder.rs::inert_preserved_action`), so no typed carrier reaches the
//!   compiler yet. Section F therefore tests `resolve_dungeon` on the raw argument and states the
//!   gap rather than pretending it is closed.
//! * **Whether `#season 0` means what these tests assume.** §9 item 6 flags `#season` (2 uses) as
//!   "mapped on weak evidence". Section E pins the *shape* — that the resolver knows the token and
//!   discriminates on it — not the semantics.
//! * **The task graph's correctness.** Section G asserts elision and renumbering; it does not
//!   assert that the surviving ops are lowered *right*. That is `kernel_lowering.rs`'s subject.
//!
//! # Surface these tests require
//!
//! ```ignore
//! // sentinel_compiler::kernel::archetype
//! pub enum GateOutcome {
//!     /// The archetype satisfies the gate; the gated thing is emitted.
//!     Applies,
//!     /// The archetype does not satisfy the gate; the gated thing is dropped.
//!     DoesNotApply,
//!     /// The gate carries the `skip` disable sentinel — the author turned this off for EVERYONE.
//!     /// Distinct from `DoesNotApply` on purpose: collapsing them makes the 140 disabled steps
//!     /// indistinguishable from an archetype mismatch, and a later "why was this dropped?" audit
//!     /// cannot tell an authored disable from a resolution result.
//!     Disabled,
//! }
//! pub struct Resolution { pub outcome: GateOutcome, pub diagnostics: Vec<Diagnostic> }
//!
//! pub fn resolve_gate(gate: &GuideGate, archetype: &Archetype) -> Result<Resolution, LoweringError>;
//! pub fn resolve_directive(d: &GuideDirective, archetype: &Archetype) -> Result<Resolution, LoweringError>;
//! pub fn resolve_dungeon(arg: &str, archetype: &Archetype) -> Result<Resolution, LoweringError>;
//!
//! pub const GATE_PRECEDENCE_AMBIGUOUS: &str = "GATE_PRECEDENCE_AMBIGUOUS";
//! pub const GATE_TOKEN_NORMALISED: &str  = "GATE_TOKEN_NORMALISED";
//! ```
//!
//! `LoweringError` gains one variant:
//!
//! ```ignore
//! UnknownGateToken { expression: String, token: String }
//! ```
//!
//! ADR 07 §9 names the normalisation diagnostic `Diagnostic::Normalised`. It is spelled here as a
//! `code` on the existing `sentinel_models::authoring::Diagnostic` struct rather than as a new enum,
//! because that struct is what `CompileReport` already carries and what
//! `kernel_lowering.rs::compile_kernel_warns_that_the_artifact_is_incomplete` already matches on by
//! `code`. One diagnostic type, not two.
//!
//! `sentinel_models::kernel::Archetype` must gain three axes it does not have today. §4.2's verdict
//! column classifies `#questguide`, `#xprate`, `#hardcoreserver`/`#softcoreserver` and `#season` as
//! archetype filters; `Archetype` covers only the first (as `ProfileMode::QuestGuide`). A resolver
//! that cannot answer the other three leaves a gate in the artifact, which C2 forbids:
//!
//! ```ignore
//! /// `#xprate <1.5` (584) / `>1.49` (130) / `>1.59` (15) / `>1.3` (4) / `>1.499` (2).
//! /// Thousandths, NOT `f32`: `Archetype` derives `Eq`, and `>1.49` versus `>1.499` are genuinely
//! /// different thresholds that float comparison at that width is exactly where a wrong answer
//! /// hides.
//! pub xp_rate_milli: u32,
//! /// `#hardcoreserver` (4) / `#softcoreserver` (2) — a property of the REALM, independent of the
//! /// player's own `#hardcore` (59) / `#softcore` (91). Aliasing the two is the failure this field
//! /// exists to prevent.
//! pub hardcore_server: bool,
//! /// `#season 0` (2). §9 item 6: mapped on weak evidence.
//! pub season: Option<u8>,
//! ```
//!
//! and `ProfileMode::Dungeon` must carry *which* dungeon, because `.dungeon Mara` and
//! `.dungeon ZF` are different archetype variants and a unit variant cannot tell them apart:
//!
//! ```ignore
//! /// 19 distinct arguments, measured after case folding: BF BFD Crypts DM Gnomer Mara MT
//! /// Ramparts RFD RFK SFK SM SP ST Stockades UB Ulda WC ZF. A closed `Copy` enum, not a `String`,
//! /// so `ProfileMode` keeps its `Copy`/`Eq`/`Hash` derives.
//! pub enum DungeonId { Bf, Bfd, Crypts, Dm, Gnomer, Mara, Mt, Ramparts, Rfd, Rfk, Sfk, Sm, Sp, St, Stockades, Ub, Ulda, Wc, Zf }
//! ProfileMode::Dungeon { instance: DungeonId }
//! ```

use sentinel_compiler::kernel::archetype::{
    resolve_directive, resolve_dungeon, resolve_gate, GateOutcome, Resolution,
    GATE_PRECEDENCE_AMBIGUOUS, GATE_TOKEN_NORMALISED,
};
use sentinel_compiler::kernel::{LoweringError, QuestMeta};
use sentinel_compiler::Compiler;
use sentinel_models::authoring::{
    new_project, AcceptQuestAction, Action, ActionPayload, Class, Diagnostic, Faction, Gated,
    GuideDirective, GuideGate, Operation, Project, Race, Severity, TravelAction,
};
use sentinel_models::kernel::{
    Allegiance, Archetype, DungeonId, Expansion, ProfileMode, QuestId,
    RuntimeProfile as KernelProfile,
};

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const HUMAN_GUIDE: &str = "A-1-11-Human.lua";
const DWARF_GNOME_GUIDE: &str = "A-1-11-Dwarf-Gnome.lua";
const A_23_30_GUIDE: &str = "A-23-30.lua";
const TBC_GUIDE: &str = "The Burning Crusade.lua";

/// A `QuestMeta` that answers nothing. Every op these tests lower is an `.accept` or a `.goto`;
/// none needs a baked objective count, so a provider that cannot answer must never be consulted.
struct SilentMeta;

impl QuestMeta for SilentMeta {
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32> {
        panic!(
            "these tests lower only `.accept` and `.goto` ops, none of which carries an objective \
             predicate — quest {quest} objective {index} was asked for, so something is lowering \
             more than this file describes"
        )
    }

    fn objective_item(&self, quest: QuestId, index: u8) -> Option<u32> {
        panic!(
            "same tripwire as `objective_need`: no fragment here authors a `.complete` line, so a              loot-filter lookup for quest {quest} objective {index} means something is lowering              more than this file describes"
        )
    }
}

/// The archetype every test below varies from. Deliberately spelled out in full rather than
/// `Default`ed: each field is a compile-time gate axis, and a defaulted one is a gate nobody chose.
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
        // The three axes `Archetype` does not have today; see the module header.
        xp_rate_milli: 1_000,
        hardcore_server: false,
        season: None,
    }
}

fn who(class: Class, race: Race, faction: Faction) -> Archetype {
    Archetype {
        class,
        race,
        faction,
        ..base()
    }
}

fn dwarf_paladin() -> Archetype {
    who(Class::Paladin, Race::Dwarf, Faction::Alliance)
}
fn dwarf_warrior() -> Archetype {
    who(Class::Warrior, Race::Dwarf, Faction::Alliance)
}
fn human_paladin() -> Archetype {
    who(Class::Paladin, Race::Human, Faction::Alliance)
}
fn human_rogue() -> Archetype {
    who(Class::Rogue, Race::Human, Faction::Alliance)
}
fn gnome_mage() -> Archetype {
    who(Class::Mage, Race::Gnome, Faction::Alliance)
}
fn gnome_warlock() -> Archetype {
    who(Class::Warlock, Race::Gnome, Faction::Alliance)
}
/// **Not a legal TBC character** — Gnomes cannot be Paladins. Used anyway: it is the only
/// assignment that separates the derived precedence from the flat left-to-right reading, and the
/// resolver is a pure function of the archetype record (module header, "What these tests cannot
/// see").
fn gnome_paladin() -> Archetype {
    who(Class::Paladin, Race::Gnome, Faction::Alliance)
}
fn night_elf_druid() -> Archetype {
    who(Class::Druid, Race::NightElf, Faction::Alliance)
}
fn night_elf_hunter() -> Archetype {
    who(Class::Hunter, Race::NightElf, Faction::Alliance)
}
fn human_hunter() -> Archetype {
    who(Class::Hunter, Race::Human, Faction::Alliance)
}
fn alliance_mage() -> Archetype {
    who(Class::Mage, Race::Human, Faction::Alliance)
}
fn horde_hunter() -> Archetype {
    who(Class::Hunter, Race::Orc, Faction::Horde)
}

fn gate(text: &str) -> GuideGate {
    GuideGate(text.to_string())
}

/// Resolve `text` against `archetype`, failing the test with the corpus citation if it errors.
fn resolved(cite: &str, text: &str, archetype: &Archetype) -> Resolution {
    resolve_gate(&gate(text), archetype).unwrap_or_else(|err| {
        panic!("{cite} — `<< {text}` must resolve, got: {err:?}")
    })
}

/// The outcome alone, for the many assertions that do not care about diagnostics.
fn outcome(cite: &str, text: &str, archetype: &Archetype) -> GateOutcome {
    resolved(cite, text, archetype).outcome
}

fn assert_applies(cite: &str, text: &str, archetype: &Archetype, why: &str) {
    let got = outcome(cite, text, archetype);
    assert_eq!(
        got,
        GateOutcome::Applies,
        "{cite} — `<< {text}` must apply to {} {} {:?}: {why}. got: {got:?}",
        format_args!("{:?}", archetype.race),
        format_args!("{:?}", archetype.class),
        archetype.faction
    );
}

fn assert_drops(cite: &str, text: &str, archetype: &Archetype, why: &str) {
    let got = outcome(cite, text, archetype);
    assert_eq!(
        got,
        GateOutcome::DoesNotApply,
        "{cite} — `<< {text}` must NOT apply to {} {} {:?}: {why}. got: {got:?}",
        format_args!("{:?}", archetype.race),
        format_args!("{:?}", archetype.class),
        archetype.faction
    );
}

fn codes(resolution: &Resolution) -> Vec<&str> {
    resolution
        .diagnostics
        .iter()
        .map(|d| d.code.as_str())
        .collect()
}

fn diagnostic_with<'a>(resolution: &'a Resolution, code: &str) -> &'a Diagnostic {
    resolution
        .diagnostics
        .iter()
        .find(|d| d.code == code)
        .unwrap_or_else(|| {
            panic!(
                "expected a `{code}` diagnostic; the resolution carried {:?}",
                codes(resolution)
            )
        })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A — the three operators, each pinned by the archetype the WRONG reading would admit
//
// §2.5 "Gating grammar" states the table; these tests are its discrimination. Asserting only the
// positive case would leave every operator interchangeable with at least one other.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn a_space_is_conjunction_not_disjunction() {
    // A-23-30.lua:380 — `step << Dwarf Paladin` (40 uses).
    // A race token AND a class token. Under OR — the single most likely mis-implementation, because
    // `/` and space sit side by side in the same expressions — a Dwarf Warrior and a Human Paladin
    // would both be admitted, and a Human Paladin would run 40 steps of the Dwarf paladin quest
    // chain.
    let cite = "A-23-30.lua:380";
    assert_applies(cite, "Dwarf Paladin", &dwarf_paladin(), "both tokens hold");

    assert_drops(
        cite,
        "Dwarf Paladin",
        &dwarf_warrior(),
        "the race holds and the class does not; a space is AND, so one out of two is not enough",
    );
    assert_drops(
        cite,
        "Dwarf Paladin",
        &human_paladin(),
        "the class holds and the race does not — the mirror of the case above, so neither token \
         can be the one being ignored",
    );
}

#[test]
fn a_slash_is_disjunction_not_conjunction() {
    // A-23-30.lua:1815 — `step << Warrior/Paladin` (28 uses).
    // Two CLASS tokens, so under AND nothing at all could satisfy it — a gate that admits nobody is
    // silent, and 28 steps would vanish from the route with no diagnostic.
    let cite = "A-23-30.lua:1815";
    assert_applies(cite, "Warrior/Paladin", &dwarf_warrior(), "the left arm holds");
    assert_applies(
        cite,
        "Warrior/Paladin",
        &human_paladin(),
        "the right arm holds — both arms are live, so neither is being ignored",
    );
    assert_drops(
        cite,
        "Warrior/Paladin",
        &human_rogue(),
        "neither arm holds",
    );
}

#[test]
fn a_bang_is_negation() {
    // A-23-30.lua:2331 — `step << !Mage` (312 uses; the single most common negated gate).
    let cite = "A-23-30.lua:2331";
    assert_drops(cite, "!Mage", &gnome_mage(), "the negated token holds");
    assert_applies(
        cite,
        "!Mage",
        &gnome_warlock(),
        "same race, different class — so the race is not what is deciding",
    );
}

#[test]
fn negation_binds_to_its_own_token_not_to_the_whole_group() {
    // A-23-30.lua:5050 — `step << NightElf !Druid` (20 uses). §2.5 gives this as the witness for
    // space=AND; it is also the witness that `!` is *per-token*.
    //
    // Per-token: NightElf ∧ ¬Druid.   Group-negation: ¬(NightElf ∧ Druid).
    // The two agree on a Night Elf Druid (both false) and on a Night Elf Hunter (both true). They
    // disagree on a HUMAN HUNTER: per-token drops it, group-negation admits it. That archetype is
    // the whole test.
    let cite = "A-23-30.lua:5050";
    assert_drops(
        cite,
        "NightElf !Druid",
        &night_elf_druid(),
        "the negated class holds",
    );
    assert_applies(
        cite,
        "NightElf !Druid",
        &night_elf_hunter(),
        "the race holds and the negated class does not",
    );
    assert_drops(
        cite,
        "NightElf !Druid",
        &human_hunter(),
        "the race does not hold. Under `!(NightElf ∧ Druid)` this would be admitted, and a Human \
         Hunter would run 20 steps of the Night Elf route",
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — precedence: `/` binds LOOSER than space
//
// §2.5: "`/` binds **looser** than space: `step << Gnome !Warlock/Dwarf !Paladin` (14 uses) reads
// `(Gnome ∧ ¬Warlock) ∨ (Dwarf ∧ ¬Paladin)`." Measured: 4 uses in A-23-30.lua, 10 in
// The Burning Crusade.lua.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// The 14-use witness that settles the precedence, and its three candidate readings:
///
/// | # | reading | expression |
/// |---|---|---|
/// | 1 | derived (`/` looser)  | `(Gnome ∧ ¬Warlock) ∨ (Dwarf ∧ ¬Paladin)` |
/// | 2 | space looser          | `Gnome ∧ (¬Warlock ∨ Dwarf) ∧ ¬Paladin` |
/// | 3 | flat left-to-right    | `((Gnome ∧ ¬Warlock) ∨ Dwarf) ∧ ¬Paladin` |
///
/// Exactly two archetypes separate all three, and both are asserted below. Every other assignment
/// agrees across at least two readings and would prove nothing.
const PRECEDENCE_WITNESS: &str = "Gnome !Warlock/Dwarf !Paladin";

#[test]
fn slash_binds_looser_than_space() {
    // A-23-30.lua:3880 and The Burning Crusade.lua:11204 — `step << Gnome !Warlock/Dwarf !Paladin`.
    let cite = "A-23-30.lua:3880";

    // Dwarf Warrior separates reading 1 from reading 2.
    //   1: (Gnome=F ∧ …) ∨ (Dwarf=T ∧ ¬Paladin=T) = TRUE
    //   2: Gnome=F ∧ … = FALSE
    assert_applies(
        cite,
        PRECEDENCE_WITNESS,
        &dwarf_warrior(),
        "the right disjunct holds. Under `Gnome ∧ (¬Warlock ∨ Dwarf) ∧ ¬Paladin` — the reading in \
         which space binds looser — the leading `Gnome` would gate the whole expression and every \
         Dwarf would be excluded from all 14 steps",
    );

    // Gnome Paladin separates reading 1 from reading 3. (Not a legal character; see the helper.)
    //   1: (Gnome=T ∧ ¬Warlock=T) ∨ (Dwarf=F ∧ …) = TRUE
    //   3: ((Gnome=T ∧ ¬Warlock=T) ∨ Dwarf=F) ∧ ¬Paladin=F = FALSE
    assert_applies(
        cite,
        PRECEDENCE_WITNESS,
        &gnome_paladin(),
        "the LEFT disjunct holds, and `!Paladin` belongs to the right disjunct only. Under a flat \
         left-to-right fold the trailing `!Paladin` would reach back across the `/` and veto a \
         match the author scoped to the Dwarf arm",
    );

    // The two assignments all three readings agree on, asserted so the test still describes the
    // expression rather than only its two hinge points.
    assert_applies(
        cite,
        PRECEDENCE_WITNESS,
        &gnome_mage(),
        "the left disjunct holds under every candidate reading",
    );
    assert_drops(
        cite,
        PRECEDENCE_WITNESS,
        &gnome_warlock(),
        "the left disjunct's negation fires and the right disjunct's race does not hold",
    );
    assert_drops(
        cite,
        PRECEDENCE_WITNESS,
        &dwarf_paladin(),
        "the right disjunct's negation fires and the left disjunct's race does not hold",
    );
}

#[test]
fn the_precedence_witness_carries_no_ambiguity_diagnostic_despite_mixing_the_operators() {
    // The counterweight to section C, and the reason the ambiguity rule cannot simply be "flag
    // every mixed gate and stop". `Gnome !Warlock/Dwarf !Paladin` mixes `/` and space too, and §2.5
    // calls it "the witness that settles the precedence" — it is symmetric, so both readings of the
    // grouping produce the same partition of the two arms and there is nothing to warn about.
    //
    // This test is what stops the C2 implementer from satisfying section C by warning on all 11
    // mixed expressions: a diagnostic that fires on the expression the ADR uses to *derive* the
    // rule is noise, and noise is tuned out.
    let resolution = resolved("A-23-30.lua:3880", PRECEDENCE_WITNESS, &dwarf_warrior());
    assert!(
        !codes(&resolution).contains(&GATE_PRECEDENCE_AMBIGUOUS),
        "`<< {PRECEDENCE_WITNESS}` is §2.5's decisive witness, not an ambiguity. got: {:?}",
        resolution.diagnostics
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// C — ambiguity is a DIAGNOSTIC, not a guess
//
// §9 item 7: "**The compiler should emit a diagnostic on any gate mixing `/` and space rather than
// silently picking.**" The operative word is *silently*. The compiler still has to emit something,
// so it picks — and both halves are asserted here: the diagnostic exists AND the pick follows the
// documented rule. Because C2 resolves at compile time, a wrong pick silently includes or excludes
// 10 steps with no runtime trace at all.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn a_gate_mixing_slash_and_space_emits_a_diagnostic() {
    // The Burning Crusade.lua:90457 — `step << Alliance/Horde Hunter` (10 uses).
    let resolution = resolved("The Burning Crusade.lua:90457", "Alliance/Horde Hunter", &alliance_mage());
    let diagnostic = diagnostic_with(&resolution, GATE_PRECEDENCE_AMBIGUOUS);

    assert_eq!(diagnostic.severity, Severity::Warning, "got: {diagnostic:?}");
    assert!(
        diagnostic.message.contains("Alliance/Horde Hunter"),
        "the diagnostic must quote the gate verbatim so the author can find all 10 of them. \
         got: {:?}",
        diagnostic.message
    );

    // Naming BOTH candidate readings, because a warning that says only "this is ambiguous" leaves
    // the reader to re-derive the two meanings from §2.5 before they can decide which the author
    // meant. §9 item 7 spells both out and so must the diagnostic.
    for reading in ["Alliance ∨ (Horde ∧ Hunter)", "(Alliance ∨ Horde) ∧ Hunter"] {
        assert!(
            diagnostic.message.contains(reading),
            "the diagnostic must name the reading `{reading}` — the author cannot adjudicate an \
             ambiguity they are not shown. got: {:?}",
            diagnostic.message
        );
    }
}

#[test]
fn a_gate_mixing_slash_and_space_does_not_silently_pick() {
    // The other half, and the one a "just warn and move on" implementation fails. The Burning
    // Crusade.lua:90457 — `step << Alliance/Horde Hunter`.
    //
    //   derived (§2.5):  Alliance ∨ (Horde ∧ Hunter)
    //   author's likely: (Alliance ∨ Horde) ∧ Hunter
    //
    // An ALLIANCE MAGE separates them: admitted by the first, refused by the second. So this single
    // archetype proves the compiler resolved by the documented rule — and the test above proves it
    // said so. Together: it picked, and the pick was not silent.
    let cite = "The Burning Crusade.lua:90457";
    assert_applies(
        cite,
        "Alliance/Horde Hunter",
        &alliance_mage(),
        "`/` binds looser, so `Alliance` alone is a complete disjunct. Under the alternative \
         reading `(Alliance ∨ Horde) ∧ Hunter` a Mage is refused, and the two readings differ on \
         10 steps with nothing at runtime to record which was chosen",
    );

    // The assignments both readings agree on, so a reader can see the disagreement is confined to
    // the archetype above.
    assert_applies(cite, "Alliance/Horde Hunter", &horde_hunter(), "both readings admit this");
    assert_drops(
        cite,
        "Alliance/Horde Hunter",
        &who(Class::Mage, Race::Orc, Faction::Horde),
        "both readings refuse this",
    );
}

#[test]
fn an_unambiguous_gate_carries_no_ambiguity_diagnostic() {
    // A gate using ONE operator has nothing to be ambiguous about. If the diagnostic fired on
    // these it would fire on nearly every gate in the corpus and be worthless.
    for (cite, expression, archetype) in [
        ("A-23-30.lua:1815", "Warrior/Paladin", dwarf_warrior()),
        ("A-23-30.lua:380", "Dwarf Paladin", dwarf_paladin()),
        ("A-23-30.lua:2331", "!Mage", gnome_warlock()),
        // The Burning Crusade.lua:97822 — `step << Horde/tbc`. Pure `/`, no space anywhere: it is
        // NOT a mixed expression, however much a class token beside an era token looks like one.
        ("The Burning Crusade.lua:97822", "Horde/tbc", horde_hunter()),
    ] {
        let resolution = resolved(cite, expression, &archetype);
        assert!(
            !codes(&resolution).contains(&GATE_PRECEDENCE_AMBIGUOUS),
            "{cite} — `<< {expression}` uses a single operator and is not ambiguous. got: {:?}",
            resolution.diagnostics
        );
    }
}

/// Every gate expression in the corpus that mixes `/` and space, measured over all seven guides.
///
/// Derived, not remembered. Step level, after `--` dev-comment stripping:
/// `rg -no '^\s*step\s*<<\s*.+$' *.lua | sed 's/.*<<\s*//;s/\s*--.*//' | rg '/' | rg ' '`
/// returns 34 uses across these 9 expressions; the same shape over `^\s*\.[a-z]+.*<<` returns 2
/// more, one use each.
const MIXED_OPERATOR_GATES: &[(&str, u32, &str, u32)] = &[
    (A_23_30_GUIDE, 3880, "Gnome !Warlock/Dwarf !Paladin", 14),
    (TBC_GUIDE, 90457, "Alliance/Horde Hunter", 10),
    ("A-11-23.lua", 2443, "!NightElf Hunter/Rogue", 3),
    (TBC_GUIDE, 16439, "Draenei !Paladin/NightElf/!Druid", 2),
    (A_23_30_GUIDE, 725, "NightElf Hunter/Draenei Hunter", 1),
    (TBC_GUIDE, 65983, "Mage/DK wotlk", 1),
    (HUMAN_GUIDE, 2108, "Human Priest/Dwarf Priest", 1),
    (A_23_30_GUIDE, 6095, "Dwarf/Gnome !Warlock", 1),
    ("A-11-23.lua", 2434, "!NightElf Hunter/!NightElf Rogue", 1),
    // Command level, not step level — the same rule applies at OP granularity (section G).
    (A_23_30_GUIDE, 5969, "Warrior wotlk/Shaman/Rogue wotlk", 1),
    ("A-11-23.lua", 2816, "Human/Dwarf Warrior/Gnome Warrior/Rogue/Warlock", 1),
];

#[test]
fn the_mixed_operator_census_is_eleven_expressions() {
    assert_eq!(
        MIXED_OPERATOR_GATES.len(),
        11,
        "the measured census is 9 step-level plus 2 command-level mixed expressions"
    );
    let uses: u32 = MIXED_OPERATOR_GATES.iter().map(|(_, _, _, n)| n).sum();
    assert_eq!(uses, 36, "34 step-level uses plus 2 command-level");
}

#[test]
fn every_mixed_operator_gate_in_the_corpus_resolves_without_erroring() {
    // The census above is not decoration: a resolver that handles `Alliance/Horde Hunter` and
    // chokes on `Draenei !Paladin/NightElf/!Druid` (three arms, two of them negated, mixed with a
    // space) fails the compile on 2 real steps. Every one must resolve — the outcome varies with
    // the archetype and is not asserted here, only that none is a hard error.
    let refused: Vec<String> = MIXED_OPERATOR_GATES
        .iter()
        .filter_map(|(file, line, expression, _)| {
            resolve_gate(&gate(expression), &night_elf_hunter())
                .err()
                .map(|err| format!("{file}:{line} `<< {expression}` -> {err:?}"))
        })
        .collect();

    assert!(
        refused.is_empty(),
        "{} of the {} mixed-operator corpus gates failed to resolve:\n  {}",
        refused.len(),
        MIXED_OPERATOR_GATES.len(),
        refused.join("\n  ")
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// D — `skip` is a DISABLE SENTINEL, never vocabulary
//
// 140 uses in gate position, measured: The Burning Crusade.lua 109, A-23-30.lua 15,
// A-1-11-Dwarf-Gnome.lua 9, A-11-23.lua 3, A-1-11-Draenei.lua 3, A-1-11-Human.lua 1. Resolving
// `skip` as an archetype token silently ENABLES every one of them, and the failure is invisible:
// the step just runs.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn a_bare_skip_disables_the_step_for_every_archetype() {
    // The Burning Crusade.lua:83003 — `step << skip` (104 step-level uses of the bare form).
    for archetype in [dwarf_warrior(), gnome_mage(), horde_hunter(), night_elf_druid()] {
        let got = outcome("The Burning Crusade.lua:83003", "skip", &archetype);
        assert_eq!(
            got,
            GateOutcome::Disabled,
            "a bare `skip` is the author switching the step off, not a token no archetype happens \
             to match. got: {got:?} for {:?} {:?}",
            archetype.race,
            archetype.class
        );
    }
}

#[test]
fn skip_disables_a_step_even_for_the_class_named_beside_it() {
    // A-1-11-Dwarf-Gnome.lua:2551 — `step << Warrior skip` (7 uses in that guide).
    //
    // THE test of this section. A resolver that treats `skip` as an unknown-but-harmless token, or
    // as vocabulary that "matches everything", reads this expression as `Warrior` and turns 7 steps
    // back on for exactly the audience the author disabled them for. Nothing fails; the bot simply
    // does the work.
    let got = outcome(
        "A-1-11-Dwarf-Gnome.lua:2551",
        "Warrior skip",
        &dwarf_warrior(),
    );
    assert_eq!(
        got,
        GateOutcome::Disabled,
        "the archetype IS a Warrior, so `Applies` is exactly what a resolver that treats `skip` as \
         vocabulary would return. got: {got:?}"
    );
    assert_ne!(
        got,
        GateOutcome::Applies,
        "stated separately because this is the silent failure: an enabled step produces no \
         diagnostic, no error and no runtime trace"
    );
}

#[test]
fn skip_beside_a_faction_token_disables_rather_than_narrowing() {
    // The Burning Crusade.lua:86156 — `step << skip Horde`, the sentinel in leading position.
    // `importer/tests/task_graph_directives.rs::skip_disables_the_step_while_the_tail_stays_verbatim_but_inert`
    // pins that the importer keeps the tail verbatim as `"skip Horde"`, so the resolver receives
    // the faction token and must not act on it.
    for archetype in [horde_hunter(), alliance_mage()] {
        let got = outcome("The Burning Crusade.lua:86156", "skip Horde", &archetype);
        assert_eq!(
            got,
            GateOutcome::Disabled,
            "`skip` absorbs its tail; `Horde` here narrows nothing. got: {got:?} for {:?}",
            archetype.faction
        );
    }
}

#[test]
fn skip_is_never_an_unknown_token() {
    // The complement of section H. `skip` must be *known* — otherwise the hard-error rule fires on
    // 140 corpus steps and no guide compiles at all — while never being *archetype vocabulary*.
    // Those are two different properties and an implementation can satisfy one and miss the other.
    let result = resolve_gate(&gate("Warrior skip"), &dwarf_warrior());
    assert!(
        result.is_ok(),
        "`skip` is known vocabulary of the DISABLE kind; refusing it as unknown fails the compile \
         on 140 corpus steps. got: {result:?}"
    );
}

#[test]
fn a_disabled_operation_is_elided_without_re_deriving_the_sentinel() {
    // The importer already decided this (`Operation::enabled == false`, 140 corpus steps), and
    // `shared/src/authoring/operation.rs::Operation::enabled` is the authority. The compiler must
    // HONOUR the flag, not re-parse the gate: an operation carrying `enabled: false` and NO gate at
    // all — which is what an editor toggle produces — must still be elided.
    let mut project = new_project("Disabled op");
    let mut op = travel_op("switched off by the author");
    op.enabled = false;
    op.gate = None;
    project.operations.push(op);
    project.operations.push(travel_op("live"));

    let (profile, _) = compile(&project, &dwarf_warrior());
    assert_eq!(
        profile.tasks.len(),
        1,
        "an operation with `enabled: false` is elided whatever its gate says — re-deriving the \
         decision from the gate string misses every disable that did not come from `skip`. \
         got: {} tasks",
        profile.tasks.len()
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// E — the `#` directive families
//
// §4.2's verdict column classifies all of these as archetype filters. Measured counts, whole
// corpus: #aldor 239 / #scryer 209, #hardcore 59 / #softcore 91, #ah 178 / #ssf 58, #flyable 3 /
// #noflyable 14, #phase 174, #tbc 277 / #wotlk 129 / #classic 125, #questguide 228, #xprate 735,
// #hardcoreserver 4 / #softcoreserver 2, #season 2.
//
// The last four were missing from §5.2's list until recently, and a resolver that does not know
// them leaves a gate in the artifact — which section H proves is impossible to represent.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

fn directive(name: &str, value: Option<&str>, line: usize) -> GuideDirective {
    GuideDirective {
        name: name.to_string(),
        value: value.map(str::to_string),
        gate: None,
        line,
    }
}

fn directive_outcome(cite: &str, d: &GuideDirective, archetype: &Archetype) -> GateOutcome {
    resolve_directive(d, archetype)
        .unwrap_or_else(|err| panic!("{cite} — `#{}` must resolve, got: {err:?}", d.name))
        .outcome
}

#[test]
fn the_allegiance_directives_resolve_against_the_shattrath_choice() {
    // The Burning Crusade.lua:7777 `#aldor` (239) and :7771 `#scryer` (209).
    let aldor = Archetype { allegiance: Some(Allegiance::Aldor), ..base() };
    let scryer = Archetype { allegiance: Some(Allegiance::Scryer), ..base() };
    let undecided = Archetype { allegiance: None, ..base() };

    let d_aldor = directive("aldor", None, 7777);
    let d_scryer = directive("scryer", None, 7771);

    assert_eq!(directive_outcome("TBC:7777", &d_aldor, &aldor), GateOutcome::Applies);
    assert_eq!(directive_outcome("TBC:7777", &d_aldor, &scryer), GateOutcome::DoesNotApply);
    assert_eq!(directive_outcome("TBC:7771", &d_scryer, &scryer), GateOutcome::Applies);
    assert_eq!(directive_outcome("TBC:7771", &d_scryer, &aldor), GateOutcome::DoesNotApply);

    // `allegiance: None` is not "both". A profile compiled before the player has chosen must not
    // carry both branches of a choice that is irreversible in-game (§5.2).
    assert_eq!(
        directive_outcome("TBC:7777", &d_aldor, &undecided),
        GateOutcome::DoesNotApply,
        "an unchosen allegiance admits neither branch; admitting both would emit 448 steps of \
         mutually exclusive quest chain"
    );
    assert_eq!(
        directive_outcome("TBC:7771", &d_scryer, &undecided),
        GateOutcome::DoesNotApply
    );
}

#[test]
fn the_player_hardcore_directives_are_not_the_server_hardcore_directives() {
    // The Burning Crusade.lua:521 `#hardcore` (59) / A-11-23.lua:2903 `#softcore` (91), against
    // The Burning Crusade.lua:4204 `#hardcoreserver` (4) / :4193 `#softcoreserver` (2).
    //
    // Two independent axes. Aliasing them — the obvious shortcut, since one name is a prefix of the
    // other — is what this test exists to refuse: a softcore character on a hardcore realm is a
    // real configuration and the guide branches on both facts separately.
    let hardcore_player_on_softcore_realm = Archetype {
        hardcore: true,
        hardcore_server: false,
        ..base()
    };

    let d_hardcore = directive("hardcore", None, 521);
    let d_softcore = directive("softcore", None, 2903);
    let d_hardcore_server = directive("hardcoreserver", None, 4204);
    let d_softcore_server = directive("softcoreserver", None, 4193);

    let a = &hardcore_player_on_softcore_realm;
    assert_eq!(directive_outcome("TBC:521", &d_hardcore, a), GateOutcome::Applies);
    assert_eq!(directive_outcome("A-11-23:2903", &d_softcore, a), GateOutcome::DoesNotApply);
    assert_eq!(
        directive_outcome("TBC:4204", &d_hardcore_server, a),
        GateOutcome::DoesNotApply,
        "`#hardcoreserver` describes the REALM. A resolver that reads `Archetype::hardcore` here \
         admits 4 realm-specific steps to every hardcore character on a normal realm"
    );
    assert_eq!(
        directive_outcome("TBC:4193", &d_softcore_server, a),
        GateOutcome::Applies
    );
}

#[test]
fn the_auction_house_directives_resolve_against_self_found() {
    // A-23-30.lua:982 `#ah` (178) / A-23-30.lua:2605 `#ssf` (58).
    let ssf = Archetype { self_found: true, ..base() };
    let ah = Archetype { self_found: false, ..base() };

    let d_ah = directive("ah", None, 982);
    let d_ssf = directive("ssf", None, 2605);

    assert_eq!(directive_outcome("A-23-30:982", &d_ah, &ah), GateOutcome::Applies);
    assert_eq!(directive_outcome("A-23-30:982", &d_ah, &ssf), GateOutcome::DoesNotApply);
    assert_eq!(directive_outcome("A-23-30:2605", &d_ssf, &ssf), GateOutcome::Applies);
    assert_eq!(directive_outcome("A-23-30:2605", &d_ssf, &ah), GateOutcome::DoesNotApply);
}

#[test]
fn the_flight_directives_resolve_against_can_fly() {
    // The Burning Crusade.lua:73799 `#flyable` (3) / :9680 `#noflyable` (14).
    let flyer = Archetype { can_fly: true, ..base() };
    let grounded = Archetype { can_fly: false, ..base() };

    let d_fly = directive("flyable", None, 73799);
    let d_nofly = directive("noflyable", None, 9680);

    assert_eq!(directive_outcome("TBC:73799", &d_fly, &flyer), GateOutcome::Applies);
    assert_eq!(directive_outcome("TBC:73799", &d_fly, &grounded), GateOutcome::DoesNotApply);
    assert_eq!(directive_outcome("TBC:9680", &d_nofly, &grounded), GateOutcome::Applies);
    assert_eq!(directive_outcome("TBC:9680", &d_nofly, &flyer), GateOutcome::DoesNotApply);
}

#[test]
fn the_phase_directive_resolves_a_range_not_a_single_value() {
    // The Burning Crusade.lua:2729 — `#phase 4-6`. Measured value census: `4-6` 166, `1` 6, `3` 2.
    // 166 of the 174 uses are a RANGE, so a resolver that parses `#phase` as `u8` fails on 95% of
    // them — and a parse that stops at the `-` reads `4-6` as phase 4 and drops 166 steps for every
    // server on phase 5 or 6.
    let d_range = directive("phase", Some("4-6"), 2729);
    let d_single = directive("phase", Some("1"), 2733);

    for phase in [4u8, 5, 6] {
        let a = Archetype { content_phase: Some(phase), ..base() };
        assert_eq!(
            directive_outcome("TBC:2729", &d_range, &a),
            GateOutcome::Applies,
            "phase {phase} is inside 4-6"
        );
    }
    for phase in [1u8, 3, 7] {
        let a = Archetype { content_phase: Some(phase), ..base() };
        assert_eq!(
            directive_outcome("TBC:2729", &d_range, &a),
            GateOutcome::DoesNotApply,
            "phase {phase} is outside 4-6"
        );
    }

    let phase_one = Archetype { content_phase: Some(1), ..base() };
    assert_eq!(directive_outcome("TBC:2733", &d_single, &phase_one), GateOutcome::Applies);
}

#[test]
fn the_expansion_directives_resolve_against_the_client() {
    // The Burning Crusade.lua carries `#tbc` (277 across the corpus); `#wotlk` (129) and
    // `#classic` (125) appear as filters within the same blocks.
    let tbc = Archetype { expansion: Expansion::Tbc, ..base() };
    let wotlk = Archetype { expansion: Expansion::Wotlk, ..base() };

    let d_tbc = directive("tbc", None, 1);
    let d_wotlk = directive("wotlk", None, 1);
    let d_classic = directive("classic", None, 1);

    assert_eq!(directive_outcome("#tbc", &d_tbc, &tbc), GateOutcome::Applies);
    assert_eq!(directive_outcome("#wotlk", &d_wotlk, &tbc), GateOutcome::DoesNotApply);
    assert_eq!(directive_outcome("#classic", &d_classic, &tbc), GateOutcome::DoesNotApply);
    assert_eq!(directive_outcome("#wotlk", &d_wotlk, &wotlk), GateOutcome::Applies);
    assert_eq!(directive_outcome("#tbc", &d_tbc, &wotlk), GateOutcome::DoesNotApply);
}

#[test]
fn the_questguide_directive_resolves_against_profile_mode() {
    // The Burning Crusade.lua:27683 — `#questguide` (228). §4.2 lists it as an archetype filter and
    // `ProfileMode::QuestGuide` already exists to carry it; nothing else in `Archetype` does.
    let d = directive("questguide", None, 27683);

    let quest_guide = Archetype { mode: ProfileMode::QuestGuide, ..base() };
    let speed_route = Archetype { mode: ProfileMode::SpeedRoute, ..base() };

    assert_eq!(directive_outcome("TBC:27683", &d, &quest_guide), GateOutcome::Applies);
    assert_eq!(
        directive_outcome("TBC:27683", &d, &speed_route),
        GateOutcome::DoesNotApply,
        "the speed route is the ABSENCE of `#questguide` (§7.1); admitting 228 do-the-quests steps \
         into it is the whole difference between the two profiles"
    );
}

#[test]
fn the_xprate_directive_resolves_a_comparison_against_the_server_rate() {
    // A-23-30.lua:8 — `#xprate <1.5`. Measured value census over 735 uses: `<1.5` 584, `>1.49` 130,
    // `>1.59` 15, `>1.3` 4, `>1.499` 2.
    //
    // `<1.5` and `>1.49` are the complementary pair that partitions the route, so a resolver that
    // ignores the operator, or that rounds, admits BOTH halves of every fork — which is 714 steps
    // of double-routing.
    let blizzlike = Archetype { xp_rate_milli: 1_000, ..base() };
    let exactly_one_five = Archetype { xp_rate_milli: 1_500, ..base() };

    let d_slow = directive("xprate", Some("<1.5"), 8);
    let d_fast = directive("xprate", Some(">1.49"), 8);

    assert_eq!(directive_outcome("A-23-30:8", &d_slow, &blizzlike), GateOutcome::Applies);
    assert_eq!(directive_outcome("A-23-30:8", &d_fast, &blizzlike), GateOutcome::DoesNotApply);

    // The boundary, where the two thresholds do NOT overlap: 1.500 is not < 1.5, and is > 1.49.
    assert_eq!(
        directive_outcome("A-23-30:8", &d_slow, &exactly_one_five),
        GateOutcome::DoesNotApply,
        "`<1.5` is strict; a rate of exactly 1.5 fails it"
    );
    assert_eq!(directive_outcome("A-23-30:8", &d_fast, &exactly_one_five), GateOutcome::Applies);

    // The three-decimal threshold, which is why the axis is thousandths and not `f32`:
    // `>1.499` and `>1.49` disagree at 1.495, and `Archetype` derives `Eq`.
    let one_four_nine_five = Archetype { xp_rate_milli: 1_495, ..base() };
    let d_precise = directive("xprate", Some(">1.499"), 8);
    assert_eq!(
        directive_outcome("A-23-30:8", &d_fast, &one_four_nine_five),
        GateOutcome::Applies
    );
    assert_eq!(
        directive_outcome("A-23-30:8", &d_precise, &one_four_nine_five),
        GateOutcome::DoesNotApply,
        "`>1.499` and `>1.49` are different thresholds and 1.495 is where they part company"
    );
}

#[test]
fn the_season_directive_resolves_against_the_season_axis() {
    // A-1-11-NightElf.lua:514 — `#season 0` (2 uses). §9 item 6 flags this as "mapped on weak
    // evidence": with two witnesses and one value, this test pins that the resolver KNOWS the token
    // and discriminates on it — not what season 0 means.
    let d = directive("season", Some("0"), 514);

    assert_eq!(
        directive_outcome("A-1-11-NightElf:514", &d, &Archetype { season: Some(0), ..base() }),
        GateOutcome::Applies
    );
    assert_eq!(
        directive_outcome("A-1-11-NightElf:514", &d, &Archetype { season: Some(1), ..base() }),
        GateOutcome::DoesNotApply
    );
    assert_eq!(
        directive_outcome("A-1-11-NightElf:514", &d, &Archetype { season: None, ..base() }),
        GateOutcome::DoesNotApply,
        "a non-seasonal character is not season 0"
    );
}

#[test]
fn a_directives_own_gate_is_resolved_before_the_directive_is() {
    // `GuideDirective::gate` exists because a directive can carry its own `<<` tail
    // (`importer/tests/task_graph_directives.rs::archetype_directive_splits_its_own_gate_tail`).
    // A gate-unsatisfied directive does not apply AT ALL — it is not a filter that happens to pass.
    //
    // The distinction bites: `#aldor << Alliance` on a Horde character must be inert, not "an
    // aldor filter that a Horde Aldor satisfies".
    let mut d = directive("aldor", None, 7777);
    d.gate = Some(gate("Alliance"));

    let horde_aldor = Archetype {
        faction: Faction::Horde,
        race: Race::BloodElf,
        allegiance: Some(Allegiance::Aldor),
        ..base()
    };

    assert_eq!(
        directive_outcome("gated #aldor", &d, &horde_aldor),
        GateOutcome::DoesNotApply,
        "the directive's own gate fails, so the directive never applies — even though the \
         archetype does satisfy the allegiance it names"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// F — `.dungeon` (1,351 uses) and the argument case split
//
// `.dungeon` is a COMMAND, not a `#` directive, and it does not reach the compiler with a typed
// carrier today: `importer/src/project_builder.rs::inert_preserved_action` wraps it as an inert
// `Comment` with a `COMMAND_PRESERVED_INERT` diagnostic. These tests therefore exercise
// `resolve_dungeon` on the raw argument; wiring a typed carrier through the importer is part of the
// work they demand.
//
// 19 distinct arguments after case folding, measured:
//   BF BFD Crypts DM Gnomer Mara MT Ramparts RFD RFK SFK SM SP ST Stockades UB Ulda WC ZF
// ═══════════════════════════════════════════════════════════════════════════════════════════════

fn maraudon() -> Archetype {
    Archetype { mode: ProfileMode::Dungeon { instance: DungeonId::Mara }, ..base() }
}

#[test]
fn a_dungeon_command_resolves_against_which_dungeon_not_merely_that_it_is_one() {
    // The Burning Crusade.lua:19089 — `.dungeon Mara` (105 uses of this spelling).
    //
    // `ProfileMode::Dungeon` is a UNIT variant today, so it can say "this artifact is a dungeon
    // run" and nothing more. That is not enough to resolve a gate: `.dungeon Mara` and
    // `.dungeon ZF` (150) are different archetype variants, and a resolver that cannot tell them
    // apart admits every dungeon's steps into every dungeon's profile.
    let mara = maraudon();
    let zf = Archetype { mode: ProfileMode::Dungeon { instance: DungeonId::Zf }, ..base() };

    let got = resolve_dungeon("Mara", &mara)
        .unwrap_or_else(|err| panic!("TBC:19089 — `.dungeon Mara` must resolve, got: {err:?}"));
    assert_eq!(got.outcome, GateOutcome::Applies, "got: {got:?}");

    let got = resolve_dungeon("Mara", &zf)
        .unwrap_or_else(|err| panic!("TBC:19089 — `.dungeon Mara` must resolve, got: {err:?}"));
    assert_eq!(
        got.outcome,
        GateOutcome::DoesNotApply,
        "a Zul'Farrak run must not pick up Maraudon's 105 steps. got: {got:?}"
    );

    // And a non-dungeon profile takes none of them.
    let got = resolve_dungeon("Mara", &base())
        .unwrap_or_else(|err| panic!("TBC:19089 — `.dungeon Mara` must resolve, got: {err:?}"));
    assert_eq!(got.outcome, GateOutcome::DoesNotApply, "got: {got:?}");
}

#[test]
fn a_negated_dungeon_argument_resolves() {
    // A-23-30.lua and The Burning Crusade.lua carry 9 negated forms, measured:
    // `!WC` 19, `!Ulda` 14, `!BFD` 9, `!SM` 6, `!RFD` 4, `!ST` 2, `!Mara` 2, `!ULDA` 1,
    // `!Stockades` 1, `!Gnomer` 1, `!BF` 1. A resolver that only handles the positive form treats
    // `!Mara` as an unknown token and hard-errors the compile.
    let mara = maraudon();
    let got = resolve_dungeon("!Mara", &mara).unwrap_or_else(|err| {
        panic!("`.dungeon !Mara` must resolve, got: {err:?}")
    });
    assert_eq!(got.outcome, GateOutcome::DoesNotApply, "got: {got:?}");

    let wc = Archetype { mode: ProfileMode::Dungeon { instance: DungeonId::Wc }, ..base() };
    let got = resolve_dungeon("!Mara", &wc).unwrap_or_else(|err| {
        panic!("`.dungeon !Mara` must resolve, got: {err:?}")
    });
    assert_eq!(got.outcome, GateOutcome::Applies, "got: {got:?}");
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// G — typo normalisation: CLOSED, VERSIONED, and every case announces itself
//
// Six normalisations, each measured. Every one emits `GATE_TOKEN_NORMALISED`, because a silent
// normalisation is indistinguishable from a resolver that got lucky, and the table has to be
// auditable against a future guide-pack revision that fixes the typo upstream.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// `(what it is cited as, authored token, canonical token, uses)`.
///
/// Derived, not remembered:
/// * `Pala` — `rg -n '<<[^>]*\bPala\b' *.lua` returns 4, all in The Burning Crusade.lua.
/// * `TBC` / `WOTLK` — extracting every `<<` tail and counting era tokens by exact case gives
///   `tbc` 689, `wotlk` 212, `classic` 30, `era` 14, `TBC` 10, `sod` 2, `WOTLK` 1. The 11
///   upper-case occurrences are the case variants.
/// * The `.dungeon` splits — `rg -no '^\s*\.dungeon\s+\S+' *.lua` gives `Mara` 105 / `MARA` 91,
///   `Ulda` 41 / `ULDA` 25, `Ramparts` 11 / `RAMPARTS` 11.
const NORMALISATIONS: &[(&str, &str, &str, u32)] = &[
    ("The Burning Crusade.lua:50101", "Pala", "Paladin", 4),
    ("The Burning Crusade.lua:75508", "TBC", "tbc", 10),
    ("The Burning Crusade.lua:75511", "WOTLK", "wotlk", 1),
    ("The Burning Crusade.lua:57349", "MARA", "Mara", 91),
    ("The Burning Crusade.lua:53416", "ULDA", "Ulda", 25),
    ("The Burning Crusade.lua:66497", "RAMPARTS", "Ramparts", 11),
];

#[test]
fn the_normalisation_table_is_closed() {
    assert_eq!(
        NORMALISATIONS.len(),
        6,
        "six normalisations: `Pala`, the two era case variants, and the three `.dungeon` argument \
         case splits. A seventh means the corpus grew a new typo and the table is stale"
    );
}

#[test]
fn pala_normalises_to_paladin_and_says_so() {
    // The Burning Crusade.lua:50101 — `>> … << Rogue/Warrior/Shaman/Pala` (2 uses), and :50102 —
    // `<< !Rogue !Warrior !Shaman !Pala` (2 more). Both spellings of the abbreviation, positive and
    // negated, because a normaliser that runs before `!` is stripped handles one and not the other.
    let resolution = resolved(
        "The Burning Crusade.lua:50101",
        "Rogue/Warrior/Shaman/Pala",
        &human_paladin(),
    );
    assert_eq!(
        resolution.outcome,
        GateOutcome::Applies,
        "a Paladin must satisfy `Pala`; the abbreviation is the author's, not a different class. \
         got: {resolution:?}"
    );
    let diagnostic = diagnostic_with(&resolution, GATE_TOKEN_NORMALISED);
    assert!(
        diagnostic.message.contains("Pala") && diagnostic.message.contains("Paladin"),
        "the diagnostic must name both the authored spelling and the canonical one, so a later \
         guide-pack revision that fixes the typo can be told from one that did not. got: {:?}",
        diagnostic.message
    );

    let negated = resolved(
        "The Burning Crusade.lua:50102",
        "!Rogue !Warrior !Shaman !Pala",
        &human_paladin(),
    );
    assert_eq!(
        negated.outcome,
        GateOutcome::DoesNotApply,
        "`!Pala` must exclude a Paladin. A normaliser that matches on the whole term rather than \
         the token misses the negated spelling and inverts the gate. got: {negated:?}"
    );
    diagnostic_with(&negated, GATE_TOKEN_NORMALISED);
}

#[test]
fn the_era_case_variants_normalise_and_say_so() {
    // The Burning Crusade.lua:75508 `<< TBC` (10 uses) and :75511 `<< WOTLK` (1).
    // Adjacent lines in the same guide, authoring the two eras in the wrong case — which is why
    // this is a normalisation and not two unrelated typos.
    let tbc_player = Archetype { expansion: Expansion::Tbc, ..base() };

    let upper_tbc = resolved("The Burning Crusade.lua:75508", "TBC", &tbc_player);
    assert_eq!(upper_tbc.outcome, GateOutcome::Applies, "got: {upper_tbc:?}");
    diagnostic_with(&upper_tbc, GATE_TOKEN_NORMALISED);

    let upper_wotlk = resolved("The Burning Crusade.lua:75511", "WOTLK", &tbc_player);
    assert_eq!(
        upper_wotlk.outcome,
        GateOutcome::DoesNotApply,
        "`WOTLK` normalises to `wotlk`, which a TBC client does not satisfy. Normalising it to \
         something that matches everything would admit the one step it gates into every profile. \
         got: {upper_wotlk:?}"
    );
    diagnostic_with(&upper_wotlk, GATE_TOKEN_NORMALISED);

    // The canonical spellings must NOT emit the diagnostic — 689 `tbc` uses would drown the 11 real
    // ones and the signal would be unusable.
    let canonical = resolved("The Burning Crusade.lua:97822", "tbc", &tbc_player);
    assert!(
        !codes(&canonical).contains(&GATE_TOKEN_NORMALISED),
        "`tbc` is already canonical; 689 spurious diagnostics would bury the 11 real ones. \
         got: {:?}",
        canonical.diagnostics
    );
}

#[test]
fn every_dungeon_argument_case_split_normalises_and_says_so() {
    // The three `.dungeon` argument splits, measured: Mara/MARA, Ulda/ULDA, Ramparts/RAMPARTS.
    // The upper-case spellings are 127 of the 1,351 uses — a resolver that hard-errors on them
    // fails the compile on nearly a tenth of all dungeon steps.
    for (cite, authored, canonical, instance) in [
        ("The Burning Crusade.lua:57349", "MARA", "Mara", DungeonId::Mara),
        ("The Burning Crusade.lua:53416", "ULDA", "Ulda", DungeonId::Ulda),
        ("The Burning Crusade.lua:66497", "RAMPARTS", "Ramparts", DungeonId::Ramparts),
    ] {
        let archetype = Archetype { mode: ProfileMode::Dungeon { instance }, ..base() };

        let upper = resolve_dungeon(authored, &archetype)
            .unwrap_or_else(|err| panic!("{cite} — `.dungeon {authored}` must resolve, got: {err:?}"));
        assert_eq!(
            upper.outcome,
            GateOutcome::Applies,
            "{cite} — `.dungeon {authored}` names the same instance as `.dungeon {canonical}`. \
             got: {upper:?}"
        );
        let diagnostic = diagnostic_with(&upper, GATE_TOKEN_NORMALISED);
        assert!(
            diagnostic.message.contains(authored) && diagnostic.message.contains(canonical),
            "{cite} — the diagnostic must name both spellings. got: {:?}",
            diagnostic.message
        );

        let lower = resolve_dungeon(canonical, &archetype)
            .unwrap_or_else(|err| panic!("{cite} — `.dungeon {canonical}` must resolve, got: {err:?}"));
        assert!(
            !codes(&lower).contains(&GATE_TOKEN_NORMALISED),
            "{cite} — `{canonical}` is the canonical spelling and must be silent. got: {:?}",
            lower.diagnostics
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// H — an unknown token is a HARD ERROR
//
// RXPGuides itself refuses (`addon.error("Invalid function call")`). Silently skipping what the
// resolver does not understand is how a previous attempt reached 60% coverage: every unrecognised
// token became a no-op, every gate carrying one became fail-open, and nothing said so.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn an_unknown_gate_token_is_a_hard_error_naming_both_the_token_and_the_expression() {
    let result = resolve_gate(&gate("Sorcerer"), &gnome_mage());
    let Err(LoweringError::UnknownGateToken { expression, token }) = &result else {
        panic!(
            "an unrecognised token must fail the compile. Anything else — skipping it, treating \
             it as always-true, treating it as always-false — silently changes which steps a real \
             character runs. got: {result:?}"
        )
    };
    assert_eq!(token.as_str(), "Sorcerer", "got: {result:?}");
    assert!(
        expression.contains("Sorcerer"),
        "the error must carry the whole expression, not only the token: a bare token name is not \
         greppable in a 138,000-line guide. got: {result:?}"
    );
}

#[test]
fn an_unknown_token_beside_a_known_one_still_fails_the_whole_expression() {
    // The failure mode that matters, and the one a "skip what you don't know" resolver produces:
    // `Warrior/Sorcerer` would degrade to `Warrior` and quietly gate on less than the author wrote,
    // or — with the operator reversed — on more.
    let disjunction = resolve_gate(&gate("Warrior/Sorcerer"), &dwarf_warrior());
    assert!(
        disjunction.is_err(),
        "an unknown token must fail the expression, not be pruned out of it. got: {disjunction:?}"
    );

    let conjunction = resolve_gate(&gate("Warrior Sorcerer"), &dwarf_warrior());
    assert!(
        conjunction.is_err(),
        "the conjunctive case too — dropping the unknown conjunct leaves `Warrior`, which admits \
         a character the author restricted further. got: {conjunction:?}"
    );
}

#[test]
fn a_class_the_expansion_has_no_archetype_for_is_known_vocabulary_not_an_unknown_token() {
    // The Burning Crusade.lua:66345 — `step << DK wotlk` (49 uses). `DK` is real gate vocabulary —
    // `shared/src/authoring/guide.rs::GuideGate`'s grammar comment names it, and §2.5 counts 81
    // uses — but `sentinel_models::authoring::Class` has nine variants and no Death Knight, because
    // TBC has none.
    //
    // So `DK` must resolve to FALSE for every representable archetype, and must NOT hard-error. The
    // two are easy to confuse and the consequences are opposite: a hard error fails the compile on
    // 49 steps that are simply not for this character.
    let result = resolve_gate(&gate("DK wotlk"), &alliance_mage());
    let resolution = result.unwrap_or_else(|err| {
        panic!(
            "The Burning Crusade.lua:66345 — `DK` is vocabulary the corpus uses 81 times; refusing \
             it as unknown fails the compile on 49 steps. got: {err:?}"
        )
    });
    assert_eq!(
        resolution.outcome,
        GateOutcome::DoesNotApply,
        "no `Class` variant is a Death Knight, so no archetype satisfies `DK`. got: {resolution:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// I — resolution happens at OP granularity, and an emptied task is elided
//
// 3,052 command-level `<<` gates across 134 distinct expressions (measured; §2.5 states the
// counting rule and calls this "the decisive evidence for P2"). A task-granular resolver is wrong
// on every one of them.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

fn accept(quest: u32, gate_text: Option<&str>) -> Action {
    Action {
        id: uuid::Uuid::new_v4(),
        enabled: true,
        condition: None,
        note: None,
        class_restriction: None,
        gate: gate_text.map(gate),
        payload: ActionPayload::AcceptQuest(AcceptQuestAction {
            quest,
            npc: None,
            auto_complete_dialog: false,
            optional: false,
        }),
    }
}

fn travel(destination: &str) -> Action {
    Action {
        id: uuid::Uuid::new_v4(),
        enabled: true,
        condition: None,
        note: None,
        class_restriction: None,
        gate: None,
        payload: ActionPayload::Travel(TravelAction {
            destination: destination.to_string(),
            position: None,
            tolerance: 5.0,
            authored_radius: None,
            mount: None,
            allow_flight: false,
            timeout: None,
        }),
    }
}

fn travel_op(name: &str) -> Operation {
    let mut op = Operation::new(name);
    op.actions.push(travel("Elwynn Forest"));
    op
}

fn compile(project: &Project, archetype: &Archetype) -> (KernelProfile, sentinel_compiler::CompileReport) {
    Compiler::compile_kernel(project, archetype, &SilentMeta)
        .unwrap_or_else(|err| panic!("`compile_kernel` must not fail on a well-formed project, got: {err:?}"))
}

/// `A-1-11-Human.lua:185-196`, the step this section is built on, verbatim in authored order:
///
/// ```text
/// 185: step
/// 186:     .goto Elwynn Forest,48.923,41.606
/// 188:     .turnin 7 >> Turn in Kobold Camp Cleanup
/// 189:     .accept 15 >> Accept Investigate Echo Ridge
/// 190:     .accept 3100 >> Accept Simple Letter    << Warrior
/// 191:     .accept 3101 >> Accept Consecrated Letter << Paladin
/// 192:     .accept 3102 >> Accept Encrypted Letter  << Rogue
/// 193:     .accept 3103 >> Accept Hallowed Letter   << Priest
/// 194:     .accept 3104 >> Accept Glyphic Letter    << Mage
/// 195:     .accept 3105 >> Accept Tainted Letter    << Warlock
/// ```
///
/// One step, six mutually exclusive class-gated `.accept`s and two ungated commands. It is the
/// cleanest OP-granularity witness in the corpus: task granularity gives a Warrior either all six
/// letters or none, and both are wrong.
fn marshal_mcbride_step() -> Operation {
    let mut op = Operation::new("Talk to Marshal McBride");
    op.actions.push(travel("Elwynn Forest"));
    op.actions.push(accept(15, None));
    op.actions.push(accept(3100, Some("Warrior")));
    op.actions.push(accept(3101, Some("Paladin")));
    op.actions.push(accept(3102, Some("Rogue")));
    op.actions.push(accept(3103, Some("Priest")));
    op.actions.push(accept(3104, Some("Mage")));
    op.actions.push(accept(3105, Some("Warlock")));
    op
}

/// Every `Op::Accept` quest id in `profile`, task by task.
fn accepted_quests(profile: &KernelProfile) -> Vec<Vec<u32>> {
    profile
        .tasks
        .iter()
        .map(|task| {
            task.ops
                .iter()
                .filter_map(|op| match op {
                    sentinel_models::kernel::Op::Accept { quest, .. } => Some(*quest),
                    _ => None,
                })
                .collect()
        })
        .collect()
}

#[test]
fn one_op_survives_and_its_siblings_are_dropped_inside_a_single_task() {
    // A-1-11-Human.lua:190-195 compiled for a Warrior.
    let mut project = new_project("Elwynn");
    project.operations.push(marshal_mcbride_step());

    let (profile, _) = compile(&project, &dwarf_warrior());

    assert_eq!(
        profile.tasks.len(),
        1,
        "the step survives — it has ungated ops. got: {} tasks",
        profile.tasks.len()
    );
    assert_eq!(
        accepted_quests(&profile),
        vec![vec![15, 3100]],
        "the ungated `.accept 15` and the Warrior's `.accept 3100` survive; 3101-3105 are dropped. \
         A task-granular resolver keeps all six letters (the step itself is ungated) and the bot \
         tries to accept five quests it cannot have"
    );
}

#[test]
fn the_same_task_keeps_a_different_op_for_a_different_archetype() {
    // The mirror, from the same corpus step. Without it, "one op survives" is satisfied by a
    // resolver that always keeps the first gated op it sees.
    let mut project = new_project("Elwynn");
    project.operations.push(marshal_mcbride_step());

    let (profile, _) = compile(&project, &gnome_mage());
    assert_eq!(
        accepted_quests(&profile),
        vec![vec![15, 3104]],
        "A-1-11-Human.lua:194 — the Mage's letter is quest 3104, and it is fifth in authored order"
    );
}

#[test]
fn a_task_whose_ops_are_all_dropped_is_elided() {
    // Synthetic on purpose, and the header says why: every corpus step whose commands are all
    // class-gated also carries an ungated `.goto`, so the corpus cannot witness this case at op
    // granularity. What it does witness is the step-level equivalent —
    // `A-1-11-Human.lua:392 step << Rogue`, whose whole task must vanish for a Mage — and both
    // shapes must produce the same outcome: no task.
    let mut project = new_project("Elwynn");
    let mut only_gated = Operation::new("Rogue-only pickup");
    only_gated.actions.push(accept(3102, Some("Rogue")));
    project.operations.push(only_gated);

    let (profile, _) = compile(&project, &gnome_mage());
    assert!(
        profile.tasks.is_empty(),
        "a task with zero executable ops is not a task; emitting an empty one gives the runner a \
         step that can never complete and a cursor that never advances. got: {:?}",
        profile.tasks
    );
}

#[test]
fn eliding_a_task_renumbers_the_survivors_and_remaps_their_dependencies() {
    // `Task::id` IS the index into `RuntimeProfile::tasks`
    // (`shared/src/kernel/task.rs::Task::id`), and `deps` carries `TaskId`s. So elision cannot just
    // remove an entry: every surviving id and every edge that points past the hole must move with
    // it. An off-by-one here is silent — the profile loads, and the runner waits on the wrong
    // predecessor forever.
    //
    // Three operations. The middle one is Rogue-only and drops for a Mage; the third `#requires`
    // the first.
    let mut project = new_project("Elwynn");

    let mut first = travel_op("first");
    first.labels.push(Gated { value: "WolfMeatEnd".to_string(), gate: None, line: 1 });
    project.operations.push(first);

    let mut middle = Operation::new("Rogue-only pickup");
    middle.actions.push(accept(3102, Some("Rogue")));
    project.operations.push(middle);

    let mut third = travel_op("third");
    third.requires.push(Gated { value: "WolfMeatEnd".to_string(), gate: None, line: 3 });
    project.operations.push(third);

    let (profile, _) = compile(&project, &gnome_mage());

    assert_eq!(profile.tasks.len(), 2, "the middle task elides. got: {} tasks", profile.tasks.len());
    assert_eq!(profile.tasks[0].id, 0, "got: {:?}", profile.tasks[0].id);
    assert_eq!(
        profile.tasks[1].id, 1,
        "the surviving third operation becomes task 1, not task 2 — `Task::id` is its index and \
         the two must not disagree. got: {:?}",
        profile.tasks[1].id
    );
    assert_eq!(
        profile.tasks[1].deps,
        vec![0],
        "the `#requires WolfMeatEnd` edge still points at the first task. got: {:?}",
        profile.tasks[1].deps
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// J — NO GATE SURVIVES INTO THE ARTIFACT
//
// The closing invariant, and the only one asserted over the SERIALIZED profile rather than the
// typed one. The typed model has no gate field to inspect — `Task`, `Op` and `Predicate` declare
// none — so a surviving gate could only arrive smuggled inside some other string, and only a walk
// of the actual bytes can find it there.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Every `(json pointer, value)` pair in `value`, depth-first, so a failure can name where it found
/// what it found rather than only that something is wrong.
fn walk(value: &serde_json::Value, at: String, out: &mut Vec<(String, serde_json::Value)>) {
    out.push((at.clone(), value.clone()));
    match value {
        serde_json::Value::Object(map) => {
            for (key, child) in map {
                walk(child, format!("{at}/{key}"), out);
            }
        }
        serde_json::Value::Array(items) => {
            for (index, child) in items.iter().enumerate() {
                walk(child, format!("{at}/{index}"), out);
            }
        }
        _ => {}
    }
}

/// A project exercising every gate-carrying field the authoring model has: a step gate
/// (`Operation::gate`), per-op gates (`Action::gate`), a legacy class restriction
/// (`Action::class_restriction`), the lossy `/`-split (`Operation::conditions`), archetype
/// directives (`Operation::directives`) and a `skip`-disabled step.
fn gate_saturated_project() -> Project {
    let mut project = new_project("Gate saturated");

    let mut gated_step = marshal_mcbride_step();
    // A-1-11-Human.lua:158 — `step << Priest/Mage/Warlock`.
    gated_step.gate = Some(gate("Priest/Mage/Warlock"));
    gated_step.conditions = vec!["Priest".into(), "Mage".into(), "Warlock".into()];
    gated_step.actions[2].class_restriction = Some("Warrior".to_string());
    gated_step.directives.push(directive("xprate", Some("<1.5"), 8));
    gated_step.directives.push(directive("aldor", None, 7777));
    project.operations.push(gated_step);

    // A-1-11-Dwarf-Gnome.lua:2551 — `step << Warrior skip`, carried verbatim by the importer.
    let mut disabled = travel_op("switched off");
    disabled.enabled = false;
    disabled.gate = Some(gate("Warrior skip"));
    project.operations.push(disabled);

    // An ungated step, so the artifact is not empty and the walk has something to walk.
    project.operations.push(travel_op("plain"));

    project
}

#[test]
fn no_string_anywhere_in_the_artifact_carries_a_gate_marker() {
    let project = gate_saturated_project();
    let (profile, _) = compile(&project, &gnome_mage());
    let json = serde_json::to_value(&profile).expect("the artifact must serialize");

    let mut nodes = Vec::new();
    walk(&json, String::new(), &mut nodes);

    let leaked: Vec<String> = nodes
        .iter()
        .filter_map(|(at, value)| {
            let text = value.as_str()?;
            (text.contains("<<") || text.contains(">>")).then(|| format!("{at} = {text:?}"))
        })
        .collect();

    assert!(
        leaked.is_empty(),
        "`<<` and `>>` are the two markers a gate or its display prose can be smuggled in on, and \
         neither may reach the artifact (§5.2, §5.8). {} string(s) carry one:\n  {}",
        leaked.len(),
        leaked.join("\n  ")
    );
}

#[test]
fn no_field_in_the_artifact_is_named_for_a_gate() {
    let project = gate_saturated_project();
    let (profile, _) = compile(&project, &gnome_mage());
    let json = serde_json::to_value(&profile).expect("the artifact must serialize");

    let mut nodes = Vec::new();
    walk(&json, String::new(), &mut nodes);

    // The five authoring-side carriers, by their serialized names. `RuntimeProfile` denies unknown
    // fields, so none of these can be *read back* — but that is a load-time check on a machine that
    // may not run one, and a `deny_unknown_fields` model can still be *written* with an extra key
    // if a future variant adds one.
    let forbidden = ["gate", "conditions", "class_restriction", "directives", "enabled"];
    let leaked: Vec<String> = nodes
        .iter()
        .filter_map(|(at, _)| {
            let key = at.rsplit('/').next()?;
            forbidden
                .contains(&key)
                .then(|| format!("{at} — a `{key}` field has no meaning after C2 resolution"))
        })
        .collect();

    assert!(
        leaked.is_empty(),
        "every gate is resolved at compile time, so the artifact has nowhere to put one. {} \
         field(s) say otherwise:\n  {}",
        leaked.len(),
        leaked.join("\n  ")
    );
}

#[test]
fn no_string_in_the_artifact_is_a_bare_gate_token() {
    // The subtler leak, and the one the `<<` scan misses: a gate that arrived already split, so the
    // marker is gone and only the token remains — `"Priest"` sitting in a `tags_used` entry, an
    // `expect_name`, or a task's provenance.
    //
    // The vocabulary scanned is deliberately narrow — the tokens with no other plausible meaning in
    // a kernel artifact. `Alliance` and `Horde` are excluded on purpose: MaNGOS creature names
    // legitimately contain them, and a false positive here would be dismissed rather than
    // investigated.
    let project = gate_saturated_project();
    let (profile, _) = compile(&project, &gnome_mage());
    let json = serde_json::to_value(&profile).expect("the artifact must serialize");

    let mut nodes = Vec::new();
    walk(&json, String::new(), &mut nodes);

    let vocabulary = [
        "skip", "tbc", "wotlk", "classic", "era", "sod", "Pala", "DK", "aldor", "scryer", "xprate",
        "questguide", "hardcoreserver", "softcoreserver", "noflyable",
    ];
    let leaked: Vec<String> = nodes
        .iter()
        // `/archetype` is exempt, for the same reason it is exempt from
        // `the_archetype_header_is_the_only_place_class_race_and_faction_appear`: §5.2 puts the
        // resolved archetype in the header as **provenance**, and `Expansion::Tbc` serializes there
        // as the bare string `"Tbc"` (§7.3.3: `"expansion": "Tbc"`). Without this filter the two
        // tests are jointly unsatisfiable — one demands the header echo the archetype exactly, the
        // other demands no string anywhere case-insensitively equal `tbc`. Everywhere *outside* the
        // header the scan is unchanged, including for the era tokens.
        .filter(|(at, _)| !at.starts_with("/archetype"))
        .filter_map(|(at, value)| {
            let text = value.as_str()?;
            vocabulary
                .iter()
                .find(|token| text.eq_ignore_ascii_case(token))
                .map(|token| format!("{at} = {text:?} (gate vocabulary `{token}`)"))
        })
        .collect();

    assert!(
        leaked.is_empty(),
        "a gate token reached the artifact with its `<<` marker already stripped — which is worse \
         than the marked case, because nothing downstream can recognise it as a gate. {} \
         occurrence(s):\n  {}",
        leaked.len(),
        leaked.join("\n  ")
    );
}

#[test]
fn the_archetype_header_is_the_only_place_class_race_and_faction_appear() {
    // §5.2 and the doc comment on `shared/src/kernel/profile.rs::RuntimeProfile`: class / race /
    // faction appear "**only here in the header**, as provenance describing which archetype it was
    // compiled for — never as a runtime test". This is the positive half of the invariant: the
    // header keeps them, and nothing else may.
    let project = gate_saturated_project();
    let archetype = gnome_mage();
    let (profile, _) = compile(&project, &archetype);

    assert_eq!(
        profile.archetype, archetype,
        "the archetype is echoed exactly — it is the record of what every gate was resolved \
         against, and a profile that does not say cannot be audited. got: {:?}",
        profile.archetype
    );

    let json = serde_json::to_value(&profile).expect("the artifact must serialize");
    let mut nodes = Vec::new();
    walk(&json, String::new(), &mut nodes);

    let leaked: Vec<String> = nodes
        .iter()
        .filter(|(at, _)| !at.starts_with("/archetype"))
        .filter_map(|(at, value)| {
            let text = value.as_str()?;
            ["Mage", "Gnome", "Warlock", "Paladin", "Rogue", "Priest", "NightElf", "Draenei"]
                .iter()
                .find(|token| text.eq_ignore_ascii_case(token))
                .map(|token| format!("{at} = {text:?} (class/race token `{token}`)"))
        })
        .collect();

    assert!(
        leaked.is_empty(),
        "outside `/archetype` the artifact has no vocabulary for a class or a race — the runtime \
         cannot evaluate either (§5.2). {} occurrence(s):\n  {}",
        leaked.len(),
        leaked.join("\n  ")
    );
}

#[test]
fn the_directives_that_selected_the_archetype_leave_no_residue() {
    // The `#` families of section E, compiled against an archetype that satisfies some and not
    // others. Whichever way each resolved, none may appear in the output: `#xprate <1.5` is a
    // compile-time question about the SERVER, and the runtime has no way to ask it.
    let project = gate_saturated_project();
    let (profile, _) = compile(&project, &Archetype {
        allegiance: Some(Allegiance::Aldor),
        xp_rate_milli: 1_000,
        ..gnome_mage()
    });

    let json = serde_json::to_string(&profile).expect("the artifact must serialize");
    for residue in ["<1.5", ">1.49", "#xprate", "#aldor", "#phase", "4-6"] {
        assert!(
            !json.contains(residue),
            "`{residue}` reached the artifact. Every `#` directive is an archetype filter (§4.2) \
             and is consumed at compile time; carrying one forward means something downstream is \
             expected to evaluate it, and nothing can"
        );
    }
}
