//! ADR 07 §7.3 end to end: the corpus excerpt `A-11-23.lua:211-280` lowered by the **real**
//! pipeline — `sentinel_importer::parse_guide` → `ProjectBuilder` → `Compiler::compile_kernel` —
//! and compared, field for field, against the hand-authored fixture
//! `shared/tests/fixtures/adr07_worked_example.json`.
//!
//! The fixture is the **specification**. It was authored from §7.3.3 before the lowering existed,
//! and §7.3.2 verified every game id in it against `tbcmangos.sqlite`. When this test fails, the
//! thing under test is the compiler; the fixture is not to be edited to match it. That direction is
//! the entire point of having authored the fixture first, and it is restated here because the
//! cheapest way to make a conformance test green is to move the specification.
//!
//! # What the fixture pins, and why each one is load-bearing
//!
//! * **8 tasks.** §7.3.1's excerpt is eight `step` markers.
//! * **A 22-entry INTERNED waypoint pool.** One entry per distinct `(map_id, x, y, z)` over the
//!   excerpt's 28 route lines (§7.1, §6.4). 28 would mean the pool was never deduplicated.
//! * **Task 0 — a sticky aggressive `Circuit` with `close: true`, 17 route points, band 34.**
//! * **Task 3 — `need: 0`.** Quest 984 has no `Req*` columns; it is an exploration objective, and
//!   that zero is a real answer rather than a lookup failure (§7.3.2, and
//!   `kernel::LoweringError::UnknownObjective`'s own doc comment).
//! * **Task 4 — `deps == [2, 0]`,** the multi-dependency task.
//! * **Task 6 — `CompletionSource::LinkedTo(7)` with EMPTY channels.** A ride-along contends for
//!   nothing.
//! * **Task 7 — a GAMEOBJECT turn-in, so `interact_target` is `None`,** and that is correct rather
//!   than missing: quest 983's ender is `gameobject_involvedrelation` 17182 (§7.3.2).
//!
//! # The four fields deliberately NOT compared
//!
//! [`EXCLUDED`] names them, they are redacted on **both** sides with a sentinel that says so, and
//! the failure message reprints the list. They are R3's deliverable (the two digests and world
//! provenance) and the fixture carries placeholder values for them — comparing a placeholder
//! against a zero would report a difference that means nothing.
//!
//! `tags_used` is **not** among them. §5.4 (C4) makes it a census of the op and predicate tags the
//! artifact actually uses, so this file *computes* it from the compiled artifact with the same
//! walk `kernel_fixture.rs::tags_used_is_an_accurate_census_of_ops_and_predicates` uses, and
//! reports the emitted list, the computed census and the fixture's declaration side by side. A
//! transcribed list is exactly what that arrangement catches.
//!
//! # WHAT THIS TEST CANNOT SEE
//!
//! * **Whether the fixture is right.** It pins agreement with a document, not with the game. If
//!   §7.3.3 and the fixture are both wrong in the same direction, this test goes green on a wrong
//!   artifact. The one guard against that is §7.3.2, which is a database check this file does not
//!   re-run — `MemoryQueryClient::new()` resolves nothing and [`Verified`] hard-codes the four
//!   objective counts §7.3.2 verified.
//! * **The rest of the corpus.** One 70-line excerpt out of 277 guide blocks and 23,894 steps. A
//!   lowering can satisfy every assertion here and be wrong on shapes that occur nowhere in
//!   Darkshore — `.groundgoto`, `<<`-gated ops, cross-file label collisions, `#completewith` naming
//!   a label rather than `next`.
//! * **The runtime.** Nothing here executes. Whether band 34 really outranks band 30 in the live
//!   scheduler, and whether a `Background` task actually yields `MOVEMENT` to a foreground lease,
//!   are ADR 08 behaviour.
//! * **Positional task alignment past a count divergence.** The diff walks `tasks` by index. If the
//!   two sides disagree on how many tasks the excerpt has, every index after the divergence is
//!   comparing unrelated steps and the entries below it are noise. The count difference is
//!   therefore printed **first**, on its own, so it is read before the detail it invalidates.
//! * **Anything the excerpt reduction changed.** [`excerpt`] blanks every line of the guide outside
//!   the header and 211-280 rather than deleting it, so retained lines keep their real numbers and
//!   `Task::source` stays comparable. What it cannot preserve is *neighbourhood*: a step whose
//!   `#completewith next` or XXREQ fold reaches outside 211-280 would behave differently in the
//!   whole file. No step in this range does, but nothing here proves that.

use std::collections::BTreeSet;

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::Project;
use sentinel_models::kernel::{
    Archetype, Class, Expansion, Faction, ProfileMode, QuestId, Race,
    RuntimeProfile as KernelProfile,
};
use sentinel_queryclient::MemoryQueryClient;
use serde_json::Value;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Inputs
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// The real guide, verbatim. Not a transcription: §7.3.2 says "Nothing is invented", and a
/// transcribed excerpt is the one input that can drift from the corpus without anything noticing.
const GUIDE: &str = include_str!("../../../sentinel/docs/adr/restedxp guides/A-11-23.lua");

/// The hand-authored fixture — the specification this compares against.
const FIXTURE: &str = include_str!("../../shared/tests/fixtures/adr07_worked_example.json");

/// Repo-relative paths, quoted in the failure message so the next reader can open both sides.
const FIXTURE_PATH: &str = "SentinelQuesting/shared/tests/fixtures/adr07_worked_example.json";
const GUIDE_PATH: &str = "sentinel/docs/adr/restedxp guides/A-11-23.lua";

/// Fields R3 owns. Redacted on both sides rather than dropped, so the comparison cannot silently
/// stop covering them if the redaction ever stops matching a real path.
const EXCLUDED: [&[&str]; 4] = [
    &["schema_hash"],
    &["integrity", "content_hash"],
    &["integrity", "world_source"],
    &["integrity", "world_build"],
];

/// What a redacted field is replaced with. A string, so it survives `deny_unknown_fields`-free
/// `Value` comparison and reads as an explicit exclusion in any dump of either side.
const REDACTED: &str = "<excluded from this comparison: R3 owns this field>";

/// §7.3.1's excerpt, with the guide's own header, at its real line numbers.
///
/// Every line outside `1..=15` (the `RegisterGuide` prologue and the guide header) and `211..=280`
/// (the excerpt) is **blanked, not removed**, and the closing `]])` is kept. Blanking is what makes
/// `Task::source` comparable: the fixture pins `line_start: 211`, and a reduction that deleted the
/// intervening 195 lines would renumber every step in the excerpt.
fn excerpt() -> String {
    let retained = |line_number: usize| {
        (1..=15).contains(&line_number)
            || (211..=280).contains(&line_number)
            || line_number == CLOSING_BRACKET_LINE
    };
    GUIDE
        .split('\n')
        .enumerate()
        .map(|(offset, text)| if retained(offset + 1) { text } else { "" })
        .collect::<Vec<_>>()
        .join("\n")
}

/// The `]])` that closes the guide's single `RegisterGuide` block.
const CLOSING_BRACKET_LINE: usize = 6010;

/// The four objective counts §7.3.2 verified against `tbcmangos.sqlite`, and nothing else.
///
/// Panics on any other lookup rather than answering `Some(1)`: a provider that answers everything
/// turns "the lowering consulted a quest it should not have" into a silently plausible number, and
/// this is the one test where every consultation is enumerable.
///
/// `984 -> Some(0)` is the load-bearing entry. Quest 984 has no `Req*` columns at all, so zero is
/// the world database's real answer; `None` would mean it could not answer, and the two must not
/// collapse (see `kernel::LoweringError::UnknownObjective`).
struct Verified;

impl QuestMeta for Verified {
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32> {
        match (quest, index) {
            (983, 1) => Some(6),   // ReqItemId1 = 5385 Crawler Leg, ReqItemCount1 = 6
            (3524, 1) => Some(1),  // Sea Creature Bones (1)
            (2118, 1) => Some(1),  // Rabid Thistle Bear Captured (1)
            (984, 1) => Some(0),   // exploration objective: no Req* columns
            other => panic!(
                "the §7.3.1 excerpt authors exactly four `.complete` objectives and §7.3.2 verified \
                 all four; the lowering asked for one that is not among them, got: {other:?}"
            ),
        }
    }

    /// `quest_template.ReqItemId<index>`, for the same four objectives and no others.
    ///
    /// Both `Some` answers are §7.3.2's own verified rows, and both are corroborated inside the
    /// excerpt by the author's comments: quest 983 objective 1 is item **5385** (`Crawler Leg`,
    /// `A-11-23.lua:234` `--Crawler Leg (6)`) and quest 3524 objective 1 is item **12242**
    /// (`Sea Creature Bones`, `:241`). The other two are not items — quest 2118's objective is the
    /// creature `Captured Rabid Thistle Bear` (11836) and quest 984 has no `Req*` columns at all —
    /// so they answer `None`, which here means "not an item" and never "could not answer".
    fn objective_item(&self, quest: QuestId, index: u8) -> Option<u32> {
        match (quest, index) {
            (983, 1) => Some(5385),    // ReqItemId1 = 5385 Crawler Leg
            (3524, 1) => Some(12242),  // ReqItemId1 = 12242 Sea Creature Bones
            (2118, 1) => None,         // creature objective: Captured Rabid Thistle Bear (11836)
            (984, 1) => None,          // exploration objective: no Req* columns
            other => panic!(
                "the §7.3.1 excerpt authors exactly four `.complete` objectives and §7.3.2 verified \
                 all four; the lowering asked for one that is not among them, got: {other:?}"
            ),
        }
    }
}

/// §7.3.3's archetype: "a Night Elf Hunter, Alliance, TBC, softcore, AH-permitted".
///
/// Spelled out in full rather than defaulted — every field is a compile-time gate axis, and a
/// defaulted one is a gate nobody chose.
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The pipeline
// ═══════════════════════════════════════════════════════════════════════════════════════════════

async fn lower_the_excerpt() -> (KernelProfile, CompileReport) {
    let source = excerpt();

    let parsed = match sentinel_importer::parse_guide(&source) {
        Ok(parsed) => parsed,
        Err(error) => panic!("the §7.3.1 excerpt must parse, got: {error:?}"),
    };

    let project: Project = match sentinel_importer::ProjectBuilder::build(
        &parsed,
        "A-11-23.lua",
        &MemoryQueryClient::new(),
    )
    .await
    {
        Ok(project) => project,
        Err(error) => panic!("the §7.3.1 excerpt must build into a Project, got: {error:?}"),
    };

    match Compiler::compile_kernel(&project, &night_elf_hunter(), &Verified) {
        Ok(compiled) => compiled,
        Err(error) => panic!(
            "`compile_kernel` must not refuse the excerpt §7.3.3 says it compiles, got: {error:?}"
        ),
    }
}

/// The fixture, round-tripped through the model rather than parsed as raw JSON.
///
/// Loading it into `RuntimeProfile` first is what makes the comparison a comparison of *artifacts*
/// and not of two hand-formatted files: whitespace, key order and the `1439` vs `1439.0` spelling
/// of a number all normalise, and a fixture that no longer satisfies `deny_unknown_fields` fails
/// here with its own message instead of surfacing as a hundred phantom differences.
fn fixture() -> Value {
    match serde_json::from_str::<KernelProfile>(FIXTURE) {
        Ok(profile) => to_value(&profile),
        Err(error) => panic!(
            "the specification fixture must load into `sentinel_models::kernel::RuntimeProfile` \
             before anything can be compared against it ({FIXTURE_PATH}), got: {error:?}"
        ),
    }
}

fn to_value(profile: &KernelProfile) -> Value {
    match serde_json::to_value(profile) {
        Ok(value) => value,
        Err(error) => panic!("a kernel artifact must serialize, got: {error:?}"),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Comparison
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// One leaf disagreement, addressed by its dotted JSON path.
#[derive(Debug)]
struct Difference {
    path: String,
    fixture: String,
    compiled: String,
}

/// Replaces every [`EXCLUDED`] path with [`REDACTED`], and panics if one of them is absent.
///
/// The panic is the point. A redaction that silently no-ops because a field was renamed would keep
/// this comparison green while quietly no longer excluding anything — or, worse, while quietly
/// excluding a field that still exists under a new name and is never compared again.
fn redact(value: &mut Value, side: &str) {
    for path in EXCLUDED {
        let pointer = path.iter().fold(String::new(), |mut acc, key| {
            acc.push('/');
            acc.push_str(key);
            acc
        });
        let Some(slot) = value.pointer_mut(&pointer) else {
            panic!(
                "the {side} artifact carries no `{}`, so the exclusion list no longer matches the \
                 schema — either that field would now be compared silently, or a field that still \
                 exists under a new name is no longer excluded",
                path.join(".")
            )
        };
        *slot = Value::String(REDACTED.to_owned());
    }
}

/// Structural diff, fixture first. Arrays report their length difference and then walk the common
/// prefix; objects report keys present on one side only.
fn diff(fixture: &Value, compiled: &Value, path: &str, out: &mut Vec<Difference>) {
    match (fixture, compiled) {
        (Value::Object(left), Value::Object(right)) => {
            let keys: BTreeSet<&String> = left.keys().chain(right.keys()).collect();
            for key in keys {
                let child = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                match (left.get(key), right.get(key)) {
                    (Some(a), Some(b)) => diff(a, b, &child, out),
                    (Some(a), None) => out.push(Difference {
                        path: child,
                        fixture: brief(a),
                        compiled: "<absent>".to_owned(),
                    }),
                    (None, Some(b)) => out.push(Difference {
                        path: child,
                        fixture: "<absent>".to_owned(),
                        compiled: brief(b),
                    }),
                    (None, None) => unreachable!("key came from one of the two maps"),
                }
            }
        }
        (Value::Array(left), Value::Array(right)) => {
            if left.len() != right.len() {
                out.push(Difference {
                    path: format!("{path}.len()"),
                    fixture: left.len().to_string(),
                    compiled: right.len().to_string(),
                });
            }
            for (index, (a, b)) in left.iter().zip(right.iter()).enumerate() {
                diff(a, b, &format!("{path}[{index}]"), out);
            }
        }
        (a, b) if a != b => out.push(Difference {
            path: path.to_owned(),
            fixture: brief(a),
            compiled: brief(b),
        }),
        _ => {}
    }
}

/// A one-line rendering, truncated so a whole route does not swamp the report.
fn brief(value: &Value) -> String {
    let text = value.to_string();
    if text.chars().count() <= 120 {
        return text;
    }
    let head: String = text.chars().take(120).collect();
    format!("{head}… ({} chars)", text.chars().count())
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The §5.4 tag census, computed rather than read
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Every op and predicate tag the artifact actually uses.
///
/// The same walk as `kernel_fixture.rs::tags_used_is_an_accurate_census_of_ops_and_predicates`,
/// over the serialized artifact rather than the typed one. Reading the wire form is the stricter
/// of the two: `tags_used` is a list of **wire** tags, so a census taken from Rust variant names
/// could agree with the model while disagreeing with what a Lua loader will actually see.
///
/// `tags_used` itself is never read here — a census that consulted it to check it would prove
/// nothing.
fn tag_census(profile: &Value) -> BTreeSet<String> {
    let mut observed = BTreeSet::new();
    let Some(tasks) = profile.get("tasks").and_then(Value::as_array) else {
        panic!("a kernel artifact carries a `tasks` array, got: {profile:?}")
    };
    for task in tasks {
        for op in task.get("ops").and_then(Value::as_array).into_iter().flatten() {
            observed.insert(tag_of(op));
        }
        // §7.1: `terminate_on` is a predicate, and it is the one that lives inside a lifetime
        // payload rather than on the task, so a census that walked only the task's own three
        // predicate slots would miss every `Background` termination condition.
        if let Some(terminate_on) = task
            .get("lifetime")
            .and_then(|lifetime| lifetime.get("payload"))
            .and_then(|payload| payload.get("terminate_on"))
        {
            collect_predicate_tags(terminate_on, &mut observed);
        }
        for slot in ["applies_when", "complete_when", "abort_when"] {
            match task.get(slot) {
                Some(Value::Null) | None => {}
                Some(predicate) => collect_predicate_tags(predicate, &mut observed),
            }
        }
    }
    observed
}

fn tag_of(value: &Value) -> String {
    let Some(tag) = value.get("type").and_then(Value::as_str) else {
        panic!(
            "ADR 07 §5.4 (C4): every enum the kernel dispatches on is adjacently tagged with \
             `type`, got: {value:?}"
        )
    };
    tag.to_owned()
}

fn collect_predicate_tags(predicate: &Value, out: &mut BTreeSet<String>) {
    let tag = tag_of(predicate);
    let payload = predicate.get("payload");
    out.insert(tag.clone());
    match (tag.as_str(), payload) {
        ("And" | "Or", Some(Value::Array(children))) => {
            for child in children {
                collect_predicate_tags(child, out);
            }
        }
        ("Not", Some(child)) => collect_predicate_tags(child, out),
        _ => {}
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The check
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn the_excerpt_lowered_end_to_end_equals_the_hand_authored_fixture() {
    let (compiled, _report) = lower_the_excerpt().await;

    let declared: BTreeSet<String> = compiled.tags_used.iter().cloned().collect();

    let mut left = fixture();
    let mut right = to_value(&compiled);
    let census = tag_census(&right);
    redact(&mut left, "fixture");
    redact(&mut right, "compiled");

    let mut differences = Vec::new();
    diff(&left, &right, "", &mut differences);

    // Counts first: once the two sides disagree on how many tasks or pool entries the excerpt has,
    // every positional entry after the divergence compares unrelated things.
    differences.sort_by_key(|difference| !difference.path.ends_with(".len()"));

    if differences.is_empty() {
        return;
    }

    let mut report = String::new();
    report.push_str(
        "ADR 07 §7.3: the excerpt lowered through the real pipeline does not equal the \
         hand-authored fixture.\n\n\
         The FIXTURE is the specification — do not edit it to match the compiler.\n",
    );
    report.push_str(&format!("  specification : {FIXTURE_PATH}\n"));
    report.push_str(&format!("  corpus source : {GUIDE_PATH}:211-280\n"));
    report.push_str(&format!("  archetype     : {:?}\n", night_elf_hunter().race));
    report.push_str("  excluded (R3-owned, redacted on BOTH sides, never compared):\n");
    for path in EXCLUDED {
        report.push_str(&format!("      {}\n", path.join(".")));
    }
    report.push_str(&format!(
        "\n  §5.4 tag census, computed from the compiled artifact rather than read off it:\n\
         \x20     emitted in `tags_used` : {declared:?}\n\
         \x20     actually used         : {census:?}\n"
    ));
    report.push_str(&format!(
        "\n  {} differences, fixture -> compiled (count mismatches first):\n",
        differences.len()
    ));
    for difference in &differences {
        report.push_str(&format!(
            "\n    .{}\n        fixture : {}\n        compiled: {}\n",
            difference.path, difference.fixture, difference.compiled
        ));
    }

    panic!("{report}");
}
