//! C2 — **archetype gate resolution**: every `<<` expression, every archetype-filter `#directive`
//! and every `.dungeon` argument is evaluated here, at compile time, against one concrete
//! [`Archetype`]. Nothing this module resolves may reach the artifact.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §2.5 "Gating grammar", §4.2 (the directive verdict
//! table), §5.2 (C2), §9 item 7. Corpus: `sentinel/docs/adr/restedxp guides`, seven vendored guides.
//!
//! # Why this is forced rather than tidy
//!
//! The kernel has no `ClassIs` / `RaceIs` / `FactionIs` predicate — `Predicate`
//! (`sentinel_models::kernel::Predicate`) declares none — and the Sylvanas API cannot answer "am I
//! Alliance?": `game_object:get_faction_id()` returns a *unit faction template*, the only
//! faction-side call works in arena/battleground context only, and no race enum is documented
//! anywhere. A gate that survived into the artifact would be **unrepresentable**, not merely untidy.
//!
//! # The grammar, as measured
//!
//! ```text
//! Gate := Arm ('/' Arm)*      -- `/` is OR and binds LOOSER than a space
//! Arm  := Term (WS Term)*     -- a space is AND
//! Term := '!'? Ident          -- `!` negates its OWN token, never the group
//! ```
//!
//! The precedence is derived, not chosen: `step << Gnome !Warlock/Dwarf !Paladin` (14 uses) reads
//! `(Gnome ∧ ¬Warlock) ∨ (Dwarf ∧ ¬Paladin)` (§2.5).
//!
//! # Three rules that are easy to get backwards
//!
//! 1. **`skip` is a disable sentinel, not vocabulary.** 140 corpus steps carry it in gate position
//!    (`step << skip`, `step << Warrior skip`). Resolving it as an archetype token silently
//!    *enables* every one of them, and the failure leaves no trace: the step simply runs. It is
//!    recognised before anything else and reported as [`GateOutcome::Disabled`], which is
//!    deliberately distinct from [`GateOutcome::DoesNotApply`] so a later audit can tell an authored
//!    disable from an archetype mismatch.
//! 2. **An unknown token is a hard error.** RXPGuides itself refuses
//!    (`addon.error("Invalid function call")`). Skipping what the resolver does not understand is
//!    how a previous attempt reached 60% coverage: every unrecognised token became a no-op and every
//!    gate carrying one became fail-open.
//! 3. **Known-but-unrepresentable is *false*, never an error.** `DK` is real vocabulary
//!    (`sentinel_models::authoring::GuideGate`'s grammar comment names it) and `Class` has no Death
//!    Knight, because TBC has none. `DK` must resolve `false` for every archetype; hard-erroring
//!    would fail the compile on 49 steps that are simply not for this character. `era`, `sod` and
//!    the single numeric level bound are the same shape.

use sentinel_models::authoring::{
    Class, Diagnostic, Faction, GuideDirective, GuideGate, Race, Severity,
};
use sentinel_models::kernel::{Allegiance, Archetype, DungeonId, Expansion, ProfileMode};

use super::LoweringError;

/// A gate mixed `/` and a space in a way that groups two ways (§9 item 7).
pub const GATE_PRECEDENCE_AMBIGUOUS: &str = "GATE_PRECEDENCE_AMBIGUOUS";

/// An authored token was mapped to its canonical spelling (§9, `Diagnostic::Normalised`).
pub const GATE_TOKEN_NORMALISED: &str = "GATE_TOKEN_NORMALISED";

/// What resolving a gate against an archetype decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GateOutcome {
    /// The archetype satisfies the gate; the gated thing is emitted.
    Applies,
    /// The archetype does not satisfy the gate; the gated thing is dropped.
    DoesNotApply,
    /// The gate carries the `skip` disable sentinel — the author turned this off for EVERYONE.
    ///
    /// Distinct from [`GateOutcome::DoesNotApply`] on purpose: collapsing them makes the 140
    /// disabled steps indistinguishable from an archetype mismatch, and a later "why was this
    /// dropped?" audit cannot tell an authored disable from a resolution result.
    Disabled,
}

/// A decision plus everything the compiler should say out loud about how it was reached.
#[derive(Debug, Clone, PartialEq)]
pub struct Resolution {
    /// The decision.
    pub outcome: GateOutcome,
    /// Normalisations applied and ambiguities flagged, in the order they were found.
    pub diagnostics: Vec<Diagnostic>,
}

impl Resolution {
    fn new(outcome: GateOutcome, diagnostics: Vec<Diagnostic>) -> Self {
        Self {
            outcome,
            diagnostics,
        }
    }

    fn bare(outcome: GateOutcome) -> Self {
        Self::new(outcome, Vec::new())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Vocabulary — closed, measured, and versioned
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// The **complete** token vocabulary of the corpus's `<<` tails: 32 distinct tokens over the seven
/// vendored guides, after `!` stripping.
///
/// Measured, not remembered — extracting every `<<` tail (dev comments stripped), splitting on `/`
/// and whitespace and counting gives: `Warrior` 1664, `Rogue` 1588, `Mage` 1427, `Hunter` 1068,
/// `Warlock` 1031, `Shaman` 998, `Horde` 955, `Paladin` 924, `Alliance` 809, `Druid` 780,
/// `Priest` 712, `tbc` 689, `DK` 300, `wotlk` 212, `Dwarf` 147, `skip` 140, `NightElf` 107,
/// `Draenei` 94, `Gnome` 65, `Human` 56, `classic` 30, `Undead` 27, `BloodElf` 21, `Tauren` 17,
/// `era` 14, `Troll` 14, `TBC` 10, `Orc` 7, `Pala` 4, `sod` 2, `WOTLK` 1, `70` 1.
///
/// Anything outside this set is a hard error, so extending the corpus means extending this module.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Vocabulary {
    /// One of the nine `Class` variants.
    Class(Class),
    /// One of the ten `Race` variants.
    Race(Race),
    /// `Alliance` (809) / `Horde` (955).
    Faction(Faction),
    /// `tbc` (689) / `wotlk` (212) / `classic` (30).
    Expansion(Expansion),
    /// Known vocabulary that **no representable archetype can satisfy**, so it resolves `false`:
    ///
    /// * `DK` (300) — `Class` has nine variants and no Death Knight, because TBC has none.
    /// * `era` (14) and `sod` (2) — Classic Era and Season of Discovery. `Expansion` has
    ///   `Classic` / `Tbc` / `Wotlk`; folding `era` into `Classic` would be a guess, and folding
    ///   `sod` into anything would be a worse one.
    /// * `70` (1) — a level bound, on a display line. `Archetype` has no level axis; inventing one
    ///   from a single use would be modelling by anecdote.
    ///
    /// This is *not* the unknown-token case: these are recognised, and recognising them is what
    /// stops the hard-error rule firing on 317 corpus tokens.
    Unrepresentable,
}

/// The closed typo table (§9's `Diagnostic::Normalised`): `(authored, canonical, corpus uses)`.
///
/// Every entry emits [`GATE_TOKEN_NORMALISED`], because a silent normalisation is indistinguishable
/// from a resolver that got lucky, and this table has to stay auditable against a future guide-pack
/// revision that fixes the typo upstream. Applied **after** `!` stripping, so `!Pala` normalises too.
const NORMALISATIONS: &[(&str, &str, u32)] = &[
    ("Pala", "Paladin", 4),
    ("TBC", "tbc", 10),
    ("WOTLK", "wotlk", 1),
];

/// The `.dungeon` argument table: `(authored, canonical, instance)`.
///
/// 19 distinct arguments after case folding, plus the three case splits — `MARA` 91 beside `Mara`
/// 105, `ULDA` 25 beside `Ulda` 41, `RAMPARTS` 11 beside `Ramparts` 11. The upper-case spellings are
/// 127 of the 1,351 uses, so a resolver that hard-errors on them fails the compile on nearly a tenth
/// of all dungeon steps.
///
/// An entry whose authored and canonical spellings differ emits [`GATE_TOKEN_NORMALISED`]; the
/// canonical spellings stay silent.
const DUNGEON_ARGUMENTS: &[(&str, DungeonId)] = &[
    ("BF", DungeonId::Bf),
    ("BFD", DungeonId::Bfd),
    ("Crypts", DungeonId::Crypts),
    ("DM", DungeonId::Dm),
    ("Gnomer", DungeonId::Gnomer),
    ("Mara", DungeonId::Mara),
    ("MT", DungeonId::Mt),
    ("Ramparts", DungeonId::Ramparts),
    ("RFD", DungeonId::Rfd),
    ("RFK", DungeonId::Rfk),
    ("SFK", DungeonId::Sfk),
    ("SM", DungeonId::Sm),
    ("SP", DungeonId::Sp),
    ("ST", DungeonId::St),
    ("Stockades", DungeonId::Stockades),
    ("UB", DungeonId::Ub),
    ("Ulda", DungeonId::Ulda),
    ("WC", DungeonId::Wc),
    ("ZF", DungeonId::Zf),
];

/// The three measured case splits: `(authored, canonical)`.
const DUNGEON_NORMALISATIONS: &[(&str, &str)] = &[
    ("MARA", "Mara"),
    ("ULDA", "Ulda"),
    ("RAMPARTS", "Ramparts"),
];

/// The disable sentinel, in gate position 140 times.
const SKIP: &str = "skip";

fn classify(token: &str) -> Option<Vocabulary> {
    let class = match token {
        "Warrior" => Some(Class::Warrior),
        "Paladin" => Some(Class::Paladin),
        "Hunter" => Some(Class::Hunter),
        "Rogue" => Some(Class::Rogue),
        "Priest" => Some(Class::Priest),
        "Shaman" => Some(Class::Shaman),
        "Mage" => Some(Class::Mage),
        "Warlock" => Some(Class::Warlock),
        "Druid" => Some(Class::Druid),
        _ => None,
    };
    if let Some(class) = class {
        return Some(Vocabulary::Class(class));
    }

    let race = match token {
        "Human" => Some(Race::Human),
        "Orc" => Some(Race::Orc),
        "Dwarf" => Some(Race::Dwarf),
        "NightElf" => Some(Race::NightElf),
        "Undead" => Some(Race::Undead),
        "Tauren" => Some(Race::Tauren),
        "Gnome" => Some(Race::Gnome),
        "Troll" => Some(Race::Troll),
        "BloodElf" => Some(Race::BloodElf),
        "Draenei" => Some(Race::Draenei),
        _ => None,
    };
    if let Some(race) = race {
        return Some(Vocabulary::Race(race));
    }

    match token {
        "Alliance" => Some(Vocabulary::Faction(Faction::Alliance)),
        "Horde" => Some(Vocabulary::Faction(Faction::Horde)),
        "tbc" => Some(Vocabulary::Expansion(Expansion::Tbc)),
        "wotlk" => Some(Vocabulary::Expansion(Expansion::Wotlk)),
        "classic" => Some(Vocabulary::Expansion(Expansion::Classic)),
        "DK" | "era" | "sod" => Some(Vocabulary::Unrepresentable),
        // A bare level bound. `70` is the only one in the corpus.
        _ if !token.is_empty() && token.bytes().all(|b| b.is_ascii_digit()) => {
            Some(Vocabulary::Unrepresentable)
        }
        _ => None,
    }
}

fn satisfied(vocabulary: Vocabulary, archetype: &Archetype) -> bool {
    match vocabulary {
        Vocabulary::Class(class) => archetype.class == class,
        Vocabulary::Race(race) => archetype.race == race,
        Vocabulary::Faction(faction) => archetype.faction == faction,
        Vocabulary::Expansion(expansion) => archetype.expansion == expansion,
        Vocabulary::Unrepresentable => false,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// `<<` gates
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// One `'!'? Ident` of a gate, as authored and as canonicalised.
struct Term<'a> {
    negated: bool,
    /// The token exactly as written, including any `!`, for diagnostics and error messages.
    authored: &'a str,
    /// The `!`-stripped, normalisation-applied spelling that is classified.
    canonical: String,
}

/// Resolve a `<<` tail against an archetype.
///
/// Errors only on an unrecognised token, and then for the **whole expression**: pruning the unknown
/// conjunct out of `Warrior Sorcerer` leaves `Warrior`, which admits a character the author
/// restricted further, and pruning it out of `Warrior/Sorcerer` gates on less than was written.
pub fn resolve_gate(gate: &GuideGate, archetype: &Archetype) -> Result<Resolution, LoweringError> {
    let expression = gate.0.trim();

    // The disable sentinel is recognised BEFORE archetype vocabulary and before the unknown-token
    // rule. `step << Warrior skip` reads as a Warrior gate to anything that treats `skip` as a
    // token, and turns 7 steps back on for exactly the audience the author disabled them for.
    // Its tail is not validated: the author switched the step off, so refusing the compile over a
    // token inside a dead expression would be noise.
    if expression
        .split(['/', ' ', '\t'])
        .any(|token| token.trim() == SKIP)
    {
        return Ok(Resolution::bare(GateOutcome::Disabled));
    }

    let mut diagnostics = Vec::new();
    let mut arms: Vec<Vec<Term<'_>>> = Vec::new();

    for arm in expression.split('/') {
        let mut terms = Vec::new();
        for authored in arm.split_whitespace() {
            let (negated, rest) = match authored.strip_prefix('!') {
                Some(stripped) => (true, stripped),
                None => (false, authored),
            };
            let canonical = normalise_token(rest, expression, &mut diagnostics);
            terms.push(Term {
                negated,
                authored,
                canonical,
            });
        }
        if terms.is_empty() {
            // An empty arm — `Warrior/`, or an empty expression. There is no reading of it that is
            // safe to invent: an empty conjunction is vacuously true and would fail open.
            return Err(LoweringError::UnknownGateToken {
                expression: expression.to_owned(),
                token: String::new(),
            });
        }
        arms.push(terms);
    }

    // Classify EVERY token before evaluating any of them, so an unknown token beside a satisfied
    // one still fails the expression rather than being short-circuited past.
    let mut classified: Vec<Vec<(bool, Vocabulary)>> = Vec::with_capacity(arms.len());
    for arm in &arms {
        let mut row = Vec::with_capacity(arm.len());
        for term in arm {
            let Some(vocabulary) = classify(&term.canonical) else {
                return Err(LoweringError::UnknownGateToken {
                    expression: expression.to_owned(),
                    token: term.canonical.clone(),
                });
            };
            row.push((term.negated, vocabulary));
        }
        classified.push(row);
    }

    if let Some(diagnostic) = ambiguity(expression, &arms) {
        diagnostics.push(diagnostic);
    }

    let applies = classified.iter().any(|arm| {
        arm.iter()
            .all(|(negated, vocabulary)| satisfied(*vocabulary, archetype) != *negated)
    });

    Ok(Resolution::new(
        if applies {
            GateOutcome::Applies
        } else {
            GateOutcome::DoesNotApply
        },
        diagnostics,
    ))
}

/// Map an authored token to its canonical spelling, announcing the change.
fn normalise_token(token: &str, expression: &str, diagnostics: &mut Vec<Diagnostic>) -> String {
    for (authored, canonical, uses) in NORMALISATIONS {
        if token == *authored {
            diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: GATE_TOKEN_NORMALISED.to_owned(),
                message: format!(
                    "gate `{expression}` spells `{authored}`, which is normalised to `{canonical}` \
                     ({uses} corpus uses). The table is closed and versioned: if a guide-pack \
                     revision fixes the spelling upstream this diagnostic stops appearing, which is \
                     how the entry is retired."
                ),
                entity: Some(expression.to_owned()),
                action: None,
            });
            return (*canonical).to_owned();
        }
    }
    token.to_owned()
}

/// §9 item 7: "emit a diagnostic on any gate mixing `/` and space rather than **silently** picking".
///
/// The operative word is *silently* — the compiler still has to emit something, so it picks by the
/// precedence §2.5 derives and says so. What it must not do is warn on every mixed expression:
/// `Gnome !Warlock/Dwarf !Paladin` mixes both operators and is the witness §2.5 uses to *derive* the
/// rule. A diagnostic that fires on the deciding witness is noise, and noise is tuned out.
///
/// The discriminator is **arm arity**. When every `/`-separated arm has the same number of terms the
/// author has written parallel groups and the grouping reads only one way; when one arm is a bare
/// token beside a multi-token arm — `Alliance/Horde Hunter` — the `/` may have been meant to bind
/// either side of the space, and the two readings differ on real archetypes.
fn ambiguity(expression: &str, arms: &[Vec<Term<'_>>]) -> Option<Diagnostic> {
    if arms.len() < 2 {
        return None;
    }
    let arity = arms[0].len();
    if arms.iter().all(|arm| arm.len() == arity) {
        return None;
    }

    let derived = arms
        .iter()
        .map(|arm| {
            let conjunction = arm
                .iter()
                .map(|term| term.authored)
                .collect::<Vec<_>>()
                .join(" ∧ ");
            if arm.len() > 1 {
                format!("({conjunction})")
            } else {
                conjunction
            }
        })
        .collect::<Vec<_>>()
        .join(" ∨ ");

    let alternative = expression
        .split_whitespace()
        .map(|chunk| {
            if chunk.contains('/') {
                format!("({})", chunk.split('/').collect::<Vec<_>>().join(" ∨ "))
            } else {
                chunk.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(" ∧ ");

    Some(Diagnostic {
        severity: Severity::Warning,
        code: GATE_PRECEDENCE_AMBIGUOUS.to_owned(),
        message: format!(
            "gate `{expression}` mixes `/` and a space, and its arms are not parallel, so it groups \
             two ways: `{derived}` — the reading ADR 07 §2.5 derives, in which `/` binds looser, and \
             the one used here — or `{alternative}`, which is what the author may have meant. C2 \
             resolves this at compile time, so the two readings differ on which steps exist in the \
             artifact and nothing at runtime records which was chosen."
        ),
        entity: Some(expression.to_owned()),
        action: None,
    })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// `#` directives
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Resolve an archetype-filter `#directive` against an archetype.
///
/// The families, with their measured corpus counts: `#aldor` 239 / `#scryer` 209, `#hardcore` 59 /
/// `#softcore` 91, `#hardcoreserver` 4 / `#softcoreserver` 2, `#ah` 178 / `#ssf` 58, `#flyable` 3 /
/// `#noflyable` 14, `#phase` 174, `#tbc` 277 / `#wotlk` 129 / `#classic` 125, `#questguide` 228,
/// `#xprate` 735, `#season` 2.
///
/// A directive this list does not name resolves to [`GateOutcome::Applies`] and is **not** an error,
/// which is the one place this module deliberately fails open. `Operation::directives` is the
/// catch-all bucket for *every* step-body directive preserved verbatim by the importer — §4.2
/// classifies about ninety of them and only the families above are archetype filters — so refusing
/// an unrecognised name would fail the compile on directives that gate nothing. A name outside this
/// set does not narrow the audience, and saying so is the whole of its effect here.
pub fn resolve_directive(
    directive: &GuideDirective,
    archetype: &Archetype,
) -> Result<Resolution, LoweringError> {
    // A directive can carry its own `<<` tail, and a gate-unsatisfied directive does not apply AT
    // ALL — it is not a filter that happens to pass. `#aldor << Alliance` on a Horde character is
    // inert, not "an aldor filter that a Horde Aldor satisfies".
    let mut diagnostics = Vec::new();
    if let Some(gate) = &directive.gate {
        let gated = resolve_gate(gate, archetype)?;
        if gated.outcome != GateOutcome::Applies {
            return Ok(gated);
        }
        diagnostics = gated.diagnostics;
    }

    let name = directive.name.trim().to_ascii_lowercase();
    let value = directive.value.as_deref().map(str::trim);

    let applies = match name.as_str() {
        "aldor" => archetype.allegiance == Some(Allegiance::Aldor),
        "scryer" => archetype.allegiance == Some(Allegiance::Scryer),
        "hardcore" => archetype.hardcore,
        "softcore" => !archetype.hardcore,
        "hardcoreserver" => archetype.hardcore_server,
        "softcoreserver" => !archetype.hardcore_server,
        "ah" => !archetype.self_found,
        "ssf" => archetype.self_found,
        "flyable" => archetype.can_fly,
        "noflyable" => !archetype.can_fly,
        "questguide" => archetype.mode == ProfileMode::QuestGuide,
        "tbc" => archetype.expansion == Expansion::Tbc,
        "wotlk" => archetype.expansion == Expansion::Wotlk,
        "classic" => archetype.expansion == Expansion::Classic,
        "phase" => phase_applies(&name, value, archetype)?,
        "xprate" => xp_rate_applies(&name, value, archetype)?,
        "season" => season_applies(&name, value, archetype)?,
        _ => true,
    };

    Ok(Resolution::new(
        if applies {
            GateOutcome::Applies
        } else {
            GateOutcome::DoesNotApply
        },
        diagnostics,
    ))
}

/// A directive value that cannot be read. Reuses the unknown-token error rather than growing the
/// error enum a second time: the token is the value, and the "expression" is the directive as
/// authored.
fn malformed(name: &str, value: Option<&str>) -> LoweringError {
    LoweringError::UnknownGateToken {
        expression: match value {
            Some(value) => format!("#{name} {value}"),
            None => format!("#{name}"),
        },
        token: value.unwrap_or_default().to_owned(),
    }
}

/// `#phase 4-6` (166 of the 174 uses) or `#phase 1` (6) / `#phase 3` (2).
///
/// A resolver that parses the value as a `u8` fails on 95% of them, and one that stops at the `-`
/// reads `4-6` as phase 4 and drops 166 steps for every server on phase 5 or 6.
fn phase_applies(
    name: &str,
    value: Option<&str>,
    archetype: &Archetype,
) -> Result<bool, LoweringError> {
    let text = value.ok_or_else(|| malformed(name, value))?;
    let (low, high) = match text.split_once('-') {
        Some((low, high)) => (
            low.trim()
                .parse::<u8>()
                .map_err(|_| malformed(name, value))?,
            high.trim()
                .parse::<u8>()
                .map_err(|_| malformed(name, value))?,
        ),
        None => {
            let single = text.parse::<u8>().map_err(|_| malformed(name, value))?;
            (single, single)
        }
    };

    // An artifact compiled without a phase does not satisfy a phase filter, for the same reason an
    // unchosen allegiance satisfies neither `#aldor` nor `#scryer`: "unknown" is not "both".
    Ok(matches!(archetype.content_phase, Some(phase) if phase >= low && phase <= high))
}

/// `#xprate <1.5` (584) / `>1.49` (130) / `>1.59` (15) / `>1.3` (4) / `>1.499` (2).
///
/// `<1.5` and `>1.49` are the complementary pair that partitions the route, so a resolver that
/// ignores the operator — or that rounds — admits BOTH halves of every fork, which is 714 steps of
/// double-routing. The comparison is integer thousandths throughout: `>1.49` and `>1.499` disagree
/// at 1.495, and that is precisely the width at which a float comparison hides a wrong answer.
fn xp_rate_applies(
    name: &str,
    value: Option<&str>,
    archetype: &Archetype,
) -> Result<bool, LoweringError> {
    let text = value.ok_or_else(|| malformed(name, value))?;
    let (less_than, rest) = match text.strip_prefix('<') {
        Some(rest) => (true, rest),
        None => (
            false,
            text.strip_prefix('>').ok_or_else(|| malformed(name, value))?,
        ),
    };
    let threshold = parse_milli(rest.trim()).ok_or_else(|| malformed(name, value))?;

    Ok(if less_than {
        archetype.xp_rate_milli < threshold
    } else {
        archetype.xp_rate_milli > threshold
    })
}

/// A decimal rate to thousandths, exactly — `"1.5"` → 1500, `"1.499"` → 1499, `"3"` → 3000.
///
/// Refuses more than three decimal places rather than truncating: a fourth digit would change the
/// answer the model cannot represent, and silently dropping it is the rounding this axis exists to
/// avoid.
fn parse_milli(text: &str) -> Option<u32> {
    let (whole, fraction) = match text.split_once('.') {
        Some((whole, fraction)) => (whole, fraction),
        None => (text, ""),
    };
    if whole.is_empty() || !whole.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if fraction.len() > 3 || !fraction.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut milli = whole.parse::<u32>().ok()?.checked_mul(1_000)?;
    let mut scale = 100;
    for digit in fraction.bytes() {
        milli = milli.checked_add(u32::from(digit - b'0') * scale)?;
        scale /= 10;
    }
    Some(milli)
}

/// `#season 0` (2 uses). §9 item 6 records the mapping as weak evidence; what is asserted is that
/// the token is known and discriminated on, not what season 0 means.
fn season_applies(
    name: &str,
    value: Option<&str>,
    archetype: &Archetype,
) -> Result<bool, LoweringError> {
    let text = value.ok_or_else(|| malformed(name, value))?;
    let season = text.parse::<u8>().map_err(|_| malformed(name, value))?;
    Ok(archetype.season == Some(season))
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// `.dungeon`
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Resolve a `.dungeon` argument (1,351 uses) against an archetype.
///
/// Takes the raw argument rather than a typed carrier because there is no typed carrier yet: the
/// importer preserves `.dungeon` as an inert `Comment` with a `COMMAND_PRESERVED_INERT` diagnostic
/// (`importer/src/project_builder.rs::inert_preserved_action`), so nothing reaches the compiler with
/// the instance attached. Wiring that through is the other half of this work; this function is the
/// half that decides.
///
/// The negated forms are real: `!WC` 19, `!Ulda` 14, `!BFD` 9, `!SM` 6, `!RFD` 4, `!ST` 2,
/// `!Mara` 2, `!ULDA` 1, `!Stockades` 1, `!Gnomer` 1, `!BF` 1. A resolver that handles only the
/// positive form treats `!Mara` as an unknown token and hard-errors the compile.
pub fn resolve_dungeon(argument: &str, archetype: &Archetype) -> Result<Resolution, LoweringError> {
    let trimmed = argument.trim();
    let (negated, rest) = match trimmed.strip_prefix('!') {
        Some(rest) => (true, rest.trim()),
        None => (false, trimmed),
    };

    let mut diagnostics = Vec::new();
    let canonical = match DUNGEON_NORMALISATIONS
        .iter()
        .find(|(authored, _)| *authored == rest)
    {
        Some((authored, canonical)) => {
            diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: GATE_TOKEN_NORMALISED.to_owned(),
                message: format!(
                    "`.dungeon {authored}` names the same instance as `.dungeon {canonical}`; the \
                     argument is normalised to `{canonical}`. The upper-case spellings are 127 of \
                     the 1,351 corpus uses, so this is a case split in the guide pack, not a \
                     different dungeon."
                ),
                entity: Some(trimmed.to_owned()),
                action: None,
            });
            *canonical
        }
        None => rest,
    };

    let Some((_, instance)) = DUNGEON_ARGUMENTS
        .iter()
        .find(|(authored, _)| *authored == canonical)
    else {
        return Err(LoweringError::UnknownGateToken {
            expression: format!(".dungeon {trimmed}"),
            token: rest.to_owned(),
        });
    };

    let matched = matches!(archetype.mode, ProfileMode::Dungeon { instance: compiled } if compiled == *instance);

    Ok(Resolution::new(
        if matched != negated {
            GateOutcome::Applies
        } else {
            GateOutcome::DoesNotApply
        },
        diagnostics,
    ))
}
