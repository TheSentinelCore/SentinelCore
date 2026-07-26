//! D6 — the P3 ingest posture for `#directive` tokens (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.10).
//!
//! Ingest is **permissive-but-loud**: a *closed, versioned* alias table maps each measured typo to
//! the token its author meant, one diagnostic is emitted per occurrence, and an **unknown** token
//! is a hard error. RXPGuides itself refuses (`addon.error("Invalid function call")`, ADR 07 §3.1);
//! silently skipping is how the previous attempt reached 60% coverage.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **They do not prove a normalised directive changes behaviour downstream.** These assert the
//!   lexer / `parse_guide` boundary only. Whether the `#completewith` recovered from
//!   `The Burning Crusade.lua:17117` actually links its task is `project_builder.rs`'s job, asserted
//!   in `task_graph_directives.rs`. A directive can normalise perfectly here and still be dropped
//!   by the next stage.
//! * **They do not police `.command` tokens.** The measured typo set is directive-only — zero
//!   command-side typos, and the nearest command pair (`.link` / `.line`) is two real, distinct
//!   commands. A command misspelling sails through every assertion in this file.
//! * **They do not re-derive malformed `.goto` arity.** That refusal already lives in
//!   `shared/src/movement.rs::resolve_coordinate` (`CoordinateError::Arity`) and is
//!   deliberately not duplicated.
//! * **The census tests read raw corpus lines, not parsed guides.** They prove the closed
//!   vocabulary covers every `#` token in the seven vendored guides; they do NOT prove each of
//!   those lines lands in a `Step` — a directive inside a block the splitter mis-bounds is
//!   invisible to them. (`every_vendored_guide_ingests_and_reports_its_normalisations_at_file_absolute_lines`
//!   closes half of that gap: it proves every block *parses*, not that every line was *seen*.)
//! * **`KNOWN_DIRECTIVES` is measured over ONE guide pack.** A future RestedXP release that adds a
//!   legitimate directive is a hard error by design — that is the posture, not a bug — but nothing
//!   here can tell "new legitimate token" from "new typo". Both need a human and a table edit.
//! * **Nothing here observes the artifact.** `Compiler::compile` is untouched by this work; that it
//!   stays byte-identical is held by the compiler's own suite, not by this file.

use sentinel_importer::{
    parse_guide, parse_guide_bundle, DirectiveDiagnostic, ImportError, DIRECTIVE_ALIASES,
    KNOWN_DIRECTIVES,
};

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../sentinel/docs/adr/restedxp guides");

/// The six measured typo tokens, their canonical form, and the corpus line that proves each.
///
/// Line numbers are permitted here: `The Burning Crusade.lua` is the vendored corpus, not living
/// code. Seven instances across six tokens — the arithmetic ADR 07 §4.3's directive MERGE row
/// ("MERGE | 6 | 7") closes against independently.
/// `reported_to` is the diagnostic's `to`, and it is deliberately **not** the whole rewritten line:
/// it names what the alias changed. For a misspelling that is the token alone — the value was
/// already the author's and reporting it back would overstate the repair. For the one missing-space
/// entry the value *is* part of what the alias supplied, so it appears, matching ADR 07 §4.2's row
/// (`#completewithTBTurnins` → `#completewith TBTurnins`).
const MEASURED_TYPOS: &[(&str, &str, Option<&str>, &str, usize)] = &[
    // (authored body, canonical name, canonical value, diagnostic `to`, corpus line in TBC.lua)
    ("#compltewith next", "completewith", Some("next"), "completewith", 17117),
    ("#compltewith next", "completewith", Some("next"), "completewith", 122325),
    (
        "#completewithTBTurnins",
        "completewith",
        Some("TBTurnins"),
        "completewith TBTurnins",
        211,
    ),
    ("#completewity next", "completewith", Some("next"), "completewith", 105447),
    ("#lable FirstKeyFrag", "label", Some("FirstKeyFrag"), "label", 6927),
    ("#noflyasble", "noflyable", None, "noflyable", 37505),
    ("#requries SalvagedKey", "requires", Some("SalvagedKey"), "requires", 114832),
];

/// A one-step guide whose only body directive is `body`.
fn guide_with_directive(body: &str) -> String {
    format!(
        "RXPGuides.RegisterGuide([[\n#name Alias Probe\nstep\n    {body}\n    .goto Durotar,1.0,2.0\n]])"
    )
}

/// Every `Normalised` diagnostic in `guide`, as `(line, from, to)` — read by predicate over the
/// collection, never by index, because emission order is an implementation detail.
fn normalisations(diagnostics: &[DirectiveDiagnostic]) -> Vec<(usize, String, String)> {
    diagnostics
        .iter()
        .map(|d| match d {
            DirectiveDiagnostic::Normalised { line, from, to } => {
                (*line, from.clone(), to.clone())
            }
        })
        .collect()
}

fn read_corpus_file(name: &str) -> String {
    let path = format!("{CORPUS}/{name}");
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("the real corpus is the fixture here — {path}: {e}"))
}

fn corpus_files() -> Vec<String> {
    let mut files: Vec<String> = std::fs::read_dir(CORPUS)
        .unwrap_or_else(|e| panic!("the real corpus is the fixture here — {CORPUS}: {e}"))
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.ends_with(".lua"))
        .collect();
    files.sort();
    assert_eq!(files.len(), 7, "the vendored pack is seven guides; got: {files:?}");
    files
}

/// The first whitespace-delimited token of a `#`-prefixed line, exactly as
/// `importer/src/lexer.rs` extracts it.
fn directive_token(line: &str) -> Option<&str> {
    let t = line.trim();
    let rest = t.strip_prefix('#')?.trim_start();
    Some(rest.split_whitespace().next().unwrap_or(rest))
}

// ===========================================================================
// Normalisation — the six, and only the six, one diagnostic per occurrence.
// ===========================================================================

#[test]
fn each_measured_typo_normalises_to_the_token_its_author_meant() {
    for (body, canonical_name, canonical_value, _, corpus_line) in MEASURED_TYPOS {
        let source = guide_with_directive(body);
        let Ok(guide) = parse_guide(&source) else {
            panic!(
                "`{body}` (The Burning Crusade.lua:{corpus_line}) must parse, not abort; got: {:?}",
                parse_guide(&source)
            );
        };
        let Some(step) = guide.steps.first() else {
            panic!(
                "`{body}` (The Burning Crusade.lua:{corpus_line}) must land in a step; got: {:?}",
                guide.steps
            );
        };
        let Some(directive) = step.directives.iter().find(|d| d.name == *canonical_name) else {
            panic!(
                "`{body}` (The Burning Crusade.lua:{corpus_line}) must normalise to \
                 `#{canonical_name}`; got: {:?}",
                step.directives
            );
        };
        assert_eq!(
            directive.value.as_deref(),
            *canonical_value,
            "`{body}` (The Burning Crusade.lua:{corpus_line}) must carry the value the canonical \
             form carries; got: {directive:?}"
        );

        let authored = directive_token(body).expect("the probe body is a `#` line");
        assert_eq!(
            directive.original.as_deref(),
            Some(authored),
            "the authored token must survive on `Directive::original`; got: {directive:?}"
        );
    }
}

#[test]
fn each_measured_typo_emits_a_normalisation_diagnostic_naming_its_source_line() {
    for (body, _, _, reported_to, corpus_line) in MEASURED_TYPOS {
        let source = guide_with_directive(body);
        let guide = parse_guide(&source).expect("the alias table normalises, it does not refuse");
        let authored = directive_token(body).expect("the probe body is a `#` line");

        // The probe guide puts the directive on line 4 of the block.
        let matching: Vec<(usize, String, String)> = normalisations(&guide.diagnostics)
            .into_iter()
            .filter(|(line, from, to)| *line == 4 && from == authored && to == reported_to)
            .collect();

        assert_eq!(
            matching.len(),
            1,
            "`{body}` (The Burning Crusade.lua:{corpus_line}) must report exactly one \
             `Normalised {{ line: 4, from: {authored:?}, to: {reported_to:?} }}`; \
             normalisation without a diagnostic is the silent repair the posture forbids. \
             Got: {:?}",
            guide.diagnostics
        );
    }
}

#[test]
fn a_normalisation_is_reported_once_per_occurrence_not_once_per_token() {
    // `#compltewith next` occurs twice in the corpus (TBC:17117 and TBC:122325). A table-keyed
    // report would collapse them to one and lose a line number.
    let source = "RXPGuides.RegisterGuide([[\n#name Twice\nstep\n    #compltewith next\n    .goto Durotar,1.0,2.0\nstep\n    #compltewith next\n    .goto Durotar,3.0,4.0\n]])";
    let guide = parse_guide(source).expect("both normalise");

    let compltewith: Vec<(usize, String, String)> = normalisations(&guide.diagnostics)
        .into_iter()
        .filter(|(_, from, _)| from == "compltewith")
        .collect();

    assert_eq!(
        compltewith.len(),
        2,
        "two occurrences, two diagnostics — one per source line; got: {:?}",
        guide.diagnostics
    );
    let lines: Vec<usize> = compltewith.iter().map(|(l, _, _)| *l).collect();
    assert!(
        lines.contains(&4) && lines.contains(&7),
        "each diagnostic must name its own source line; got: {lines:?}"
    );
}

/// `The Burning Crusade.lua:211  #completewithTBTurnins`
///
/// A **missing space**, not a misspelling — edit distance to `completewith` is 9, so no
/// distance-based repair can find it. What makes this alias safe is corroboration, not similarity:
/// `#label TBTurnins` is defined at `:320` and the correctly spaced form is used at `:301`.
#[test]
fn the_missing_space_typo_splits_into_a_name_and_the_value_it_swallowed() {
    let source = guide_with_directive("#completewithTBTurnins");
    let Ok(guide) = parse_guide(&source) else {
        panic!("TBC:211 must parse; got: {:?}", parse_guide(&source));
    };
    let Some(directive) = guide.steps.first().and_then(|s| s.directives.first()) else {
        panic!("TBC:211 must produce one directive; got: {:?}", guide.steps);
    };
    assert_eq!(
        (directive.name.as_str(), directive.value.as_deref()),
        ("completewith", Some("TBTurnins")),
        "TBC:211 is `#completewith TBTurnins` with the space lost, and `TBTurnins` is a real label \
         (TBC:320). Got: {directive:?}"
    );
}

/// The missing-space alias supplies the whole `(name, value)` pair. Applying it to a line that
/// already carries its own value would mean merging two values, and there is no rule that says
/// which wins — so it is refused, like every other thing this stage will not guess at.
#[test]
fn the_missing_space_alias_refuses_a_line_that_already_carries_a_value() {
    let source = guide_with_directive("#completewithTBTurnins SomethingElse");
    let Err(err) = parse_guide(&source) else {
        panic!(
            "a value on `#completewithTBTurnins` collides with the value the alias supplies and \
             must be refused, not merged; got: {:?}",
            parse_guide(&source)
        );
    };
    assert!(
        matches!(&err, ImportError::AliasValueConflict { name, .. } if name == "completewithTBTurnins"),
        "got: {err:?}"
    );
}

// ===========================================================================
// The rejected candidates — near misses that are real, distinct tokens.
// ===========================================================================

/// Each of these sits within a short edit distance of an alias target and each is a **deliberate**
/// part of the RestedXP vocabulary. Normalising any of them silently inverts a route: `#flyable`
/// is the positive half of the `#noflyable` pair, so folding it into `#noflyable` picks the ground
/// variant for a character that can fly.
#[test]
fn the_rejected_near_misses_survive_as_themselves_with_no_normalisation() {
    let rejected: &[(&str, &str)] = &[
        ("#flyable", "the deliberate positive half of the `#noflyable` pair (3 uses)"),
        ("#chapters Alliance 1-11", "parent navigator list (17), not the `#chapter` leaf marker"),
        ("#chapter", "leaf marker (50), not the `#chapters` navigator list"),
        ("#level 70", "a level predicate (22), not `#label`"),
        ("#tip", "informational marker (9), not the `#tbc` expansion filter"),
        ("#hardcoreserver", "realm-type variant (4), a prefix-extension of `#hardcore`"),
        ("#softcoreserver", "realm-type variant (2), a prefix-extension of `#softcore`"),
        ("#noflyable", "canonical already; must not be touched by its own alias"),
        ("#label TBTurnins", "canonical already"),
    ];

    for (body, why) in rejected {
        let source = guide_with_directive(body);
        let Ok(guide) = parse_guide(&source) else {
            panic!(
                "`{body}` is real vocabulary and must parse — {why}; got: {:?}",
                parse_guide(&source)
            );
        };
        let Some(directive) = guide.steps.first().and_then(|s| s.directives.first()) else {
            panic!("`{body}` must produce one directive; got: {:?}", guide.steps);
        };
        let authored = directive_token(body).expect("the probe body is a `#` line");
        assert_eq!(
            directive.name, authored,
            "`{body}` must survive verbatim — {why}. Got: {directive:?}"
        );
        assert_eq!(
            directive.original, None,
            "`{body}` was never normalised, so `Directive::original` must stay empty — {why}. \
             Got: {directive:?}"
        );
        assert!(
            guide.diagnostics.is_empty(),
            "`{body}` is canonical — {why} — so it must report nothing. Got: {:?}",
            guide.diagnostics
        );
    }
}

// ===========================================================================
// Unknown tokens — hard error, and the table is closed against similarity.
// ===========================================================================

#[test]
fn an_unknown_directive_token_is_a_hard_error_not_a_silent_skip() {
    let source = guide_with_directive("#thisisnotadirective");
    let Err(err) = parse_guide(&source) else {
        panic!(
            "an unrecognised `#token` must abort ingest — RXPGuides itself calls \
             `addon.error(\"Invalid function call\")` (ADR 07 §3.1), and silently skipping is how \
             the previous attempt reached 60% coverage. Got: {:?}",
            parse_guide(&source)
        );
    };
    assert!(
        matches!(&err, ImportError::UnknownDirective { name, .. } if name == "thisisnotadirective"),
        "the refusal must name the token it refused; got: {err:?}"
    );
    assert!(
        err.to_string().contains("thisisnotadirective"),
        "the message is the deliverable — it must quote the token; got: {err}"
    );
}

/// The table is a **lookup**, not a spell-checker. A token one or two edits from a canonical
/// directive, but absent from the table, must be refused rather than guessed at — that is the
/// difference between tolerating known damage and tolerating unknown damage (ADR 07 §5.10).
#[test]
fn a_near_miss_absent_from_the_closed_table_never_normalises_by_similarity() {
    // Each is edit-distance 1 or 2 from a real token and appears nowhere in the corpus.
    let near_misses = ["completewit", "labl", "requirse", "noflyabel", "stickyy", "optionl"];
    for token in near_misses {
        let source = guide_with_directive(&format!("#{token}"));
        let Err(err) = parse_guide(&source) else {
            let parsed = parse_guide(&source).expect("checked Ok above");
            panic!(
                "`#{token}` is absent from the closed alias table, so it must be REFUSED, not \
                 repaired by similarity. Got: {:?}",
                parsed.steps
            );
        };
        assert!(
            matches!(&err, ImportError::UnknownDirective { name, .. } if name == token),
            "`#{token}` must be refused as unknown, naming itself; got: {err:?}"
        );
    }
}

/// An unknown token in the **header** region is refused too. `#nmae` is not a step directive, but
/// it is the same closed vocabulary and the same silent damage: a mistyped header key becomes an
/// unread `Header` and the guide loses its identity without a word.
#[test]
fn an_unknown_header_region_directive_is_refused_like_a_step_directive() {
    let source =
        "RXPGuides.RegisterGuide([[\n#nmae Typo In The Header\nstep\n    .goto Durotar,1.0,2.0\n]])";
    let Err(err) = parse_guide(source) else {
        panic!("a mistyped header key must abort ingest; got: {:?}", parse_guide(source));
    };
    assert!(
        matches!(&err, ImportError::UnknownDirective { name, .. } if name == "nmae"),
        "got: {err:?}"
    );
}

// ===========================================================================
// The table itself — closed, versioned, self-consistent.
// ===========================================================================

/// The pin that makes an edit to the table *visible*: version and contents are asserted together,
/// so changing one without the other fails here. A new typo is meant to be a one-line patch plus a
/// version bump plus this assertion moving — never a silent widening of what ingest tolerates.
#[test]
fn the_alias_table_is_versioned_and_its_exact_contents_are_pinned() {
    assert_eq!(
        DIRECTIVE_ALIASES.version, 2,
        "v1 held the three typos found by inspection (compltewith, requries, lable); v2 is the \
         measured six. Bump this when the table changes, and change it here in the same diff."
    );

    let actual: Vec<(&str, &str, Option<&str>, u32)> = DIRECTIVE_ALIASES
        .entries
        .iter()
        .map(|a| (a.from, a.to_name, a.to_value, a.occurrences))
        .collect();

    let expected: Vec<(&str, &str, Option<&str>, u32)> = vec![
        ("compltewith", "completewith", None, 2),
        ("completewithTBTurnins", "completewith", Some("TBTurnins"), 1),
        ("completewity", "completewith", None, 1),
        ("lable", "label", None, 1),
        ("noflyasble", "noflyable", None, 1),
        ("requries", "requires", None, 1),
    ];

    assert_eq!(
        actual, expected,
        "the alias table is CLOSED: exactly six tokens, seven instances. Got: {actual:?}"
    );
    assert_eq!(
        DIRECTIVE_ALIASES.entries.iter().map(|a| a.occurrences).sum::<u32>(),
        7,
        "ADR 07 §4.3's directive MERGE row independently reads `6 | 7`; the arithmetic must close"
    );
}

#[test]
fn every_alias_target_is_itself_a_known_directive() {
    for alias in DIRECTIVE_ALIASES.entries {
        assert!(
            KNOWN_DIRECTIVES.contains(&alias.to_name),
            "`#{}` normalises to `#{}`, which is not in the closed vocabulary — a normalisation \
             that lands outside `KNOWN_DIRECTIVES` produces a token nothing downstream reads",
            alias.from,
            alias.to_name
        );
    }
}

#[test]
fn no_alias_source_is_also_a_known_directive() {
    for alias in DIRECTIVE_ALIASES.entries {
        assert!(
            !KNOWN_DIRECTIVES.contains(&alias.from),
            "`#{}` is listed BOTH as a typo and as canonical vocabulary; one of the two readings \
             silently wins and the other is dead",
            alias.from
        );
    }
}

#[test]
fn every_alias_carries_the_corpus_evidence_that_admitted_it() {
    for alias in DIRECTIVE_ALIASES.entries {
        assert!(
            alias.evidence.contains(".lua:"),
            "`#{}` must cite the corpus line that proves it — an alias with no evidence is a \
             guess with a table entry. Got: {:?}",
            alias.from,
            alias.evidence
        );
    }
}

// ===========================================================================
// The corpus — the closed vocabulary must actually close over it.
// ===========================================================================

#[test]
fn the_closed_vocabulary_covers_every_directive_token_in_the_corpus() {
    let mut seen: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    let mut unrecognised: Vec<(String, usize, String)> = Vec::new();

    for file in corpus_files() {
        let source = read_corpus_file(&file);
        for (idx, line) in source.lines().enumerate() {
            let Some(token) = directive_token(line) else { continue };
            seen.insert(token.to_string());
            let known = KNOWN_DIRECTIVES.iter().any(|k| k.eq_ignore_ascii_case(token));
            let aliased =
                DIRECTIVE_ALIASES.entries.iter().any(|a| a.from.eq_ignore_ascii_case(token));
            if !known && !aliased {
                unrecognised.push((file.clone(), idx + 1, token.to_string()));
            }
        }
    }

    assert!(
        unrecognised.is_empty(),
        "every `#` token in the vendored pack must be either canonical vocabulary or a listed \
         alias — anything else would hard-error a real guide at ingest. Got: {unrecognised:?}"
    );
    assert_eq!(
        seen.len(),
        49,
        "ADR 07 §4.2 tabulates exactly 49 directive tokens; got {}: {seen:?}",
        seen.len()
    );
    assert_eq!(
        KNOWN_DIRECTIVES.len() + DIRECTIVE_ALIASES.entries.len(),
        49,
        "43 canonical + 6 aliases = the 49 the ADR counts; got {} + {}",
        KNOWN_DIRECTIVES.len(),
        DIRECTIVE_ALIASES.entries.len()
    );
}

#[test]
fn the_alias_occurrence_counts_match_the_corpus_they_were_measured_from() {
    let mut counted: std::collections::BTreeMap<&str, u32> =
        DIRECTIVE_ALIASES.entries.iter().map(|a| (a.from, 0)).collect();

    for file in corpus_files() {
        let source = read_corpus_file(&file);
        for line in source.lines() {
            let Some(token) = directive_token(line) else { continue };
            if let Some(slot) = counted.get_mut(token) {
                *slot += 1;
            }
        }
    }

    for alias in DIRECTIVE_ALIASES.entries {
        assert_eq!(
            counted[alias.from], alias.occurrences,
            "`#{}` is tabled at {} occurrence(s) but the corpus has {}; the table's counts are \
             the evidence for its entries and must not drift from the pack they describe",
            alias.from, alias.occurrences, counted[alias.from]
        );
    }
    assert_eq!(
        counted.values().sum::<u32>(),
        7,
        "seven typo instances in total; got: {counted:?}"
    );
}

/// The whole vendored pack, through the bundle path `import-guides` actually uses.
///
/// This is the test that the hard error puts at risk: refusing an unknown token is worthless if it
/// refuses the seven guides the project ships against. It also proves what synthetic probes cannot
/// — that a diagnostic's line survives `parse_guide_bundle`'s block shifting and is
/// **file-absolute**, directly comparable to a `ripgrep` line number. A block-relative line points
/// an author at the wrong line of a 138,000-line file, which is worse than not reporting.
#[test]
fn every_vendored_guide_ingests_and_reports_its_normalisations_at_file_absolute_lines() {
    let mut reported: Vec<(String, usize, String)> = Vec::new();

    for file in corpus_files() {
        let source = read_corpus_file(&file);
        for (block, result) in parse_guide_bundle(&source).into_iter().enumerate() {
            let Ok(guide) = result else {
                panic!(
                    "{file} block {block} must ingest under the closed vocabulary — a hard error \
                     that refuses the shipped guide pack is a broken posture, not a strict one. \
                     Got: {:?}",
                    result.err()
                );
            };
            for (line, from, _) in normalisations(&guide.diagnostics) {
                reported.push((file.clone(), line, from));
            }
        }
    }

    for (body, _, _, _, corpus_line) in MEASURED_TYPOS {
        let authored = directive_token(body).expect("the probe body is a `#` line");
        let hits = reported
            .iter()
            .filter(|(file, line, from)| {
                file == "The Burning Crusade.lua" && line == corpus_line && from == authored
            })
            .count();
        assert_eq!(
            hits, 1,
            "The Burning Crusade.lua:{corpus_line} `{body}` must report exactly one normalisation \
             at that file-absolute line. Got the full report: {reported:?}"
        );
    }

    assert_eq!(
        reported.len(),
        7,
        "seven occurrences across the whole pack, seven diagnostics, and nothing else normalised. \
         Got: {reported:?}"
    );
}
