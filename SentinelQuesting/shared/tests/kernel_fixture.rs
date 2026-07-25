//! ADR 07 §7.3.3 worked example — conformance of the fixture against `sentinel_models::kernel`.
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §7.3 compiles one real corpus step range (`A-11-23.lua:211-280`)
//! into one kernel artifact and states at the close of §7.3.3 (lines 2005-2009, the "Step types exercised" note) exactly which
//! contracts that
//! artifact is supposed to demonstrate. This file is the executable form of that claim: the fixture
//! must load into the model, survive a round trip, and actually contain the things that note says it
//! contains. (§7.3.4 does not exist — §7.3 stops at §7.3.3. Earlier drafts of this header cited it.)
//!
//! Five defects in §7.3.3 were found by building the model against it. **All five are now fixed in
//! the ADR itself** (§9 items 21-24 and 26), so the fixture and the document agree; they are recorded
//! here so no future reader mistakes the fixture for a free-hand transcription. The numbering below
//! is this file's own (D5 is a serialisation note that lives in `adr07_worked_example.md`).
//!
//! * **D1** — §7.3.3 printed neither `defaults` nor `waypoint_pool`, but §7.2's root `required` list
//!   names both, so the worked example could not satisfy its own schema. Both are now in the ADR and
//!   in the fixture (§9 item 22).
//! * **D2** — §7.3.3 gave task 0 an 18-point route, but the corpus source `A-11-23.lua:215-231` is
//!   3 `.goto` plus 14 `.waypoint` = **17** lines. Every later waypoint index therefore shifts down
//!   by one, which made the one-row-per-source-line pool 28 entries rather than 29. §7.3.2 states
//!   "Nothing is invented", so the corpus won over the ADR's arithmetic and the ADR was renumbered
//!   (§9 item 21). The route length still holds; the pool was interned to 22 afterwards — see D6.
//! * **D3** — §5.1.1 spells the field `area_id` in `InArea` / `HearthBoundTo`; §7.1 and the §7.3.3
//!   fixture both spell it `area`, and §7.1 is authoritative.
//! * **D4** — `tags_used` was wrong in both directions, and unit variants were printed with an
//!   explicit `"payload": null` that serde's adjacent tagging never emits. The ADR moved on both
//!   counts (§9 items 23-24); the two tests that were quarantined for them are live again.
//! * **D6** — §7.3.3 printed a 28-slot pool holding only 22 distinct coordinates, while §7.1 and
//!   §6.4 — the two clauses that speak about the *pool* — say it is deduplicated. The pool is now
//!   **interned**: one entry per distinct `(map_id, x, y, z)`, 22 entries (§9 item 26).
//!
//! Interning changed no route *length* and no `radii` array: every route walks the identical
//! coordinate sequence it walked before. Six entries are referenced twice, for **two unrelated
//! reasons**, and conflating them is the trap this header exists to close:
//!
//! * **Task 0 — four real re-crossings.** A `Circuit` with `close: true`. `A-11-23.lua:225` re-walks
//!   `:218` (the circuit crossing itself), `:224`/`:226` re-walk the `:217`/`:216` approach, and
//!   `:231` returns to `:215` to close the loop. The bot physically walks each twice, so these
//!   survive route-level dedup untouched. Justified by geometry, **not** radius — three of the four
//!   change radius from 0 on the approach to 60 on the circuit.
//! * **Task 2 — two redundant emissions.** Not a re-crossing at all. `A-11-23.lua:247`/`:248` state
//!   the loop's anchors in 4-arg form and `:249`/`:254` re-emit the same two coordinates in 5-arg
//!   form (radii `[0,0,50,…]` corroborate). This is the §2.6 double emission, and the route-level
//!   dedup deliverable will shrink task 2 from 8 points to 6.
//!
//! Route-level dedup (§2.6, §5.7, §8) is a **different operation** from pool interning and has not
//! landed: it changes route lengths, interning never does. This fixture demonstrates interning only.

use std::collections::BTreeSet;

use sentinel_models::kernel::{
    Channel, Class, CombatPolicy, CombatStance, CompletionSource, DelegatePayload, Expansion,
    Faction, Lifetime, LootRule, NpcRef, Op, Predicate, ProfileMode, Race, Route, RouteKind,
    RuntimeProfile, Task, TaskId, TravelMode, UnknownPolicy, MAGIC, SCHEMA_VERSION,
};
use serde_json::Value;

/// Repo-relative path, quoted in failure messages so the next reader can open the file.
const FIXTURE_PATH: &str = "SentinelQuesting/shared/tests/fixtures/adr07_worked_example.json";

const FIXTURE: &str = include_str!("fixtures/adr07_worked_example.json");

/// D6: the interned pool length — one entry per *distinct* coordinate. The 28 source route lines of
/// `A-11-23.lua:211-280` visit 22 distinct points; 28 would mean the pool was never deduplicated
/// (§7.1, §2.6, §6.4, §8) and 29 would mean a waypoint was invented on top of that (D2, §7.3.2).
const POOL_LEN: usize = 22;

/// §7.3.3 lowers `A-11-23.lua:211-280` into exactly eight tasks.
const TASK_COUNT: usize = 8;

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// Deserializes the fixture, or panics with the offending line, column and source excerpt.
///
/// A bare `expected struct RuntimeProfile` tells the next engineer nothing, and C4 (§5.4) makes
/// this failure mode *likely* rather than exotic: every kernel struct is `deny_unknown_fields`, so
/// a single renamed field in either the model or the fixture surfaces here.
fn load() -> RuntimeProfile {
    match serde_json::from_str::<RuntimeProfile>(FIXTURE) {
        Ok(profile) => profile,
        Err(error) => panic!("{}", describe_load_failure(&error)),
    }
}

fn describe_load_failure(error: &serde_json::Error) -> String {
    let line = error.line();
    let column = error.column();
    let mut report = String::new();
    report.push_str(
        "the ADR 07 §7.3.3 worked example did not load into \
         `sentinel_models::kernel::RuntimeProfile`.\n",
    );
    report.push_str(&format!("  fixture   : {FIXTURE_PATH}\n"));
    report.push_str(&format!("  position  : line {line}, column {column}\n"));
    report.push_str(&format!("  category  : {:?}\n", error.classify()));
    report.push_str(&format!("  serde says: {error}\n"));

    if line > 0 {
        report.push('\n');
        let first = line.saturating_sub(3).max(1);
        let last = line + 1;
        for (offset, text) in FIXTURE.lines().enumerate() {
            let number = offset + 1;
            if number < first {
                continue;
            }
            if number > last {
                break;
            }
            report.push_str(&format!("{number:>5} | {text}\n"));
            if number == line {
                report.push_str(&format!(
                    "      | {}^\n",
                    " ".repeat(column.saturating_sub(1))
                ));
            }
        }
    }

    report.push_str(
        "\ncontract: ADR 07 §5.4 (C4) is fail-closed — every kernel struct denies unknown fields \
         and every enum it dispatches on is adjacently tagged {type, payload}. A missing field \
         means the fixture is behind the model; an unknown field means the model is behind the \
         fixture. Fix whichever one §7.1 does not describe.\n",
    );
    report
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Small accessors, so a failure names the task rather than an index
// ─────────────────────────────────────────────────────────────────────────────────────────────

fn task(profile: &RuntimeProfile, id: TaskId) -> &Task {
    let found = profile.tasks.get(id as usize).unwrap_or_else(|| {
        panic!(
            "ADR 07 §7.3.3 declares {TASK_COUNT} tasks but the fixture has {}; task {id} is missing",
            profile.tasks.len()
        )
    });
    assert_eq!(
        found.id, id,
        "ADR 07 §7.1: task order IS the TaskId — tasks[{id}] must carry id {id}, not {}",
        found.id
    );
    found
}

fn travel_route(task: &Task, op_index: usize) -> &Route {
    match task.ops.get(op_index) {
        Some(Op::Travel { route }) => route,
        Some(other) => panic!(
            "ADR 07 §7.3.3: task {} op {op_index} must be Op::Travel, but it is {other:?}",
            task.id
        ),
        None => panic!(
            "ADR 07 §7.3.3: task {} must have an op at index {op_index}; it has {} op(s)",
            task.id,
            task.ops.len()
        ),
    }
}

fn background(task: &Task) -> (&[Channel], u8, &Predicate) {
    match &task.lifetime {
        Lifetime::Background {
            channels,
            band,
            terminate_on,
        } => (channels, *band, terminate_on),
        other => panic!(
            "ADR 07 §5.3 (C3): task {} must be Lifetime::Background, but it is {other:?}",
            task.id
        ),
    }
}

fn combat(task: &Task) -> &CombatPolicy {
    task.combat.as_ref().unwrap_or_else(|| {
        panic!(
            "ADR 07 §5.6 (C6): task {} must carry a per-task combat override, but combat is None \
             (which means 'inherit ProfileDefaults::combat')",
            task.id
        )
    })
}

fn entries(npcs: &[NpcRef]) -> Vec<u32> {
    npcs.iter().map(|npc| npc.entry).collect()
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 1. It loads, and it round trips
// ─────────────────────────────────────────────────────────────────────────────────────────────

#[test]
fn worked_example_deserialises_into_the_kernel_profile() {
    let profile = load();
    assert_eq!(
        profile.tasks.len(),
        TASK_COUNT,
        "ADR 07 §7.3.3 lowers A-11-23.lua:211-280 into exactly {TASK_COUNT} tasks"
    );
    assert_eq!(
        profile.waypoint_pool.len(),
        POOL_LEN,
        "D6: the 28 route lines of A-11-23.lua:211-280 visit {POOL_LEN} distinct coordinates, and \
         §7.1 declares the pool 'deduplicated; routes index into this', so the pool is {POOL_LEN} \
         entries. {} means a waypoint was invented, dropped, or stored twice (§7.3.2: \"Nothing is \
         invented\")",
        profile.waypoint_pool.len()
    );
}

/// The real contract, and the one the ADR actually pins.
///
/// Compared as parsed `serde_json::Value`s rather than as raw text: the fixture is hand-formatted
/// and carries decimal literals such as `38.90` and `50.920` that `serde_json` renders `38.9` and
/// `50.92`. That is JSON number formatting, not a model defect, so byte comparison would report a
/// false failure.
///
/// `canonicalise_unit_variants` used to absorb one genuinely *semantic* difference — the
/// unit-variant `"payload": null` spelling — and is now a no-op on this fixture, because the audit
/// normalised both §7.3.3 and the fixture to serde's emission (§9 item 23). It is kept deliberately:
/// this test stays green if a future fixture reintroduces the explicit-null spelling, while
/// `worked_example_reserialises_to_a_byte_equal_json_value` below is the test that would catch it.
#[test]
fn worked_example_reserialises_to_a_semantically_identical_document() {
    let original: Value = serde_json::from_str(FIXTURE).expect("the fixture is valid JSON");
    let emitted: Value = reserialise_to_value();

    let left = canonicalise_unit_variants(&original);
    let right = canonicalise_unit_variants(&emitted);

    if let Some(difference) = first_difference(&left, &right, "") {
        panic!(
            "re-serialising the ADR 07 §7.3.3 worked example changed it.\n  fixture: \
             {FIXTURE_PATH}\n  first difference at {difference}\n\ncontract: §7.1 plus §7.2's \
             root `required` list — the model must be able to carry every field the artifact has, \
             losslessly, or the compiler and the kernel are describing different documents."
        );
    }
}

/// Model-level idempotency: `deserialise(serialise(deserialise(f))) == deserialise(f)`.
///
/// Complements the test above. That one proves nothing was dropped *relative to the file*; this
/// one proves the model's own emission is a fixed point, which is what R2's compiler output and
/// R3's digest over the emitted bytes will actually depend on.
#[test]
fn worked_example_round_trip_through_the_model_is_a_fixed_point() {
    let once = load();
    let text = serde_json::to_string(&once).expect("the profile serialises");
    let twice: RuntimeProfile = serde_json::from_str(&text).unwrap_or_else(|error| {
        panic!(
            "the model emitted a document it cannot read back — {error}\n  fixture: \
             {FIXTURE_PATH}\n  contract: ADR 07 §5.4 (C4), the artifact must be self-consistent"
        )
    });
    assert_eq!(
        once, twice,
        "ADR 07 §7.1: serialise → deserialise must be lossless for the kernel artifact"
    );
}

/// Strict, un-normalised `Value` equality against the fixture.
///
/// This is the comparison the brief asked for verbatim, and it now holds. It used to fail on exactly
/// one difference: §7.3.3 printed unit variants of the adjacently tagged enums as
/// `{"type": "Exclusive", "payload": null}`, while serde's canonical adjacent tagging *omits* the
/// content key for a unit variant and emits `{"type": "Exclusive"}`. §7.3.3 was not even
/// self-consistent about it — `payload: null` on `Exclusive` / `Solo` / `Block` / `TreatFalse` /
/// `Aggressive` / `Objective` / `Destination`, but bare `{"type": "OwnPredicate"}` for `completion`.
///
/// **The audit ruled that the ADR moves, not the model** (§9 item 23). §7.2's `$defs` require only
/// `["type"]` on those objects, both spellings deserialise, in Lua an absent key and a `null` key are
/// both `nil`, and the only way to make the code match the printed prose would have been eleven
/// hand-written `Serialize` impls that buy nothing. §7.3.3 and this fixture are now spelled the way
/// serde emits, so the artifact is **byte-reproducible**, not merely loadable — which is what R3's
/// digest over the emitted bytes needs.
///
/// The older spelling is still accepted on the way *in*: that half is pinned by
/// `unit_variants_accept_the_adr_7_3_3_explicit_null_payload` in `kernel_wire_shape.rs`, so
/// artifacts written against the pre-audit text keep loading.
#[test]
fn worked_example_reserialises_to_a_byte_equal_json_value() {
    let original: Value = serde_json::from_str(FIXTURE).expect("the fixture is valid JSON");
    let emitted: Value = reserialise_to_value();

    if let Some(difference) = first_difference(&original, &emitted, "") {
        panic!(
            "un-normalised re-serialisation differs from the fixture at {difference}\n  fixture: \
             {FIXTURE_PATH}"
        );
    }
}

/// Re-serialises the loaded profile **to text**, then parses that text back into a `Value`.
///
/// Going through text is load-bearing, not ceremony. `serde_json::to_value` would be the obvious
/// shortcut and it is wrong here: `Value::Number` has no `f32` arm, so `to_value` widens every
/// `Point::x` to `f64` and turns `36.051` into `36.05099868774414`. The artifact's coordinates are
/// `f32` because ADR 07 §7.1 line 1261 declares them `f32`, and the emitted *text* is `36.051` —
/// so the text is what must be compared. This is the number-precision half of "compare values, not
/// bytes": the comparison is over the JSON the model would actually write to disk.
fn reserialise_to_value() -> Value {
    let profile = load();
    let text = serde_json::to_string(&profile).expect("the profile serialises");
    serde_json::from_str(&text).expect("the model emits valid JSON")
}

/// Rewrites `{"type": T, "payload": null}` to `{"type": T}` everywhere, recursively.
///
/// Only objects whose *entire* key set is `{type, payload}` with a string tag and a null payload
/// are touched, so ordinary nullable fields (`interact_target`, `combat`, `z`, `allegiance`, …)
/// are untouched — they are values of a named key, never a two-key tagged envelope.
fn canonicalise_unit_variants(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let is_unit_variant = map.len() == 2
                && map.get("type").is_some_and(Value::is_string)
                && map.get("payload").is_some_and(Value::is_null);
            if is_unit_variant {
                let mut stripped = serde_json::Map::new();
                stripped.insert("type".to_owned(), map["type"].clone());
                return Value::Object(stripped);
            }
            Value::Object(
                map.iter()
                    .map(|(key, inner)| (key.clone(), canonicalise_unit_variants(inner)))
                    .collect(),
            )
        }
        Value::Array(items) => Value::Array(items.iter().map(canonicalise_unit_variants).collect()),
        other => other.clone(),
    }
}

/// Reports the first structural difference as a JSON-pointer-ish path, because `assert_eq!` on two
/// 370-line `Value`s is unreadable.
fn first_difference(left: &Value, right: &Value, path: &str) -> Option<String> {
    match (left, right) {
        (Value::Object(l), Value::Object(r)) => {
            for (key, left_value) in l {
                match r.get(key) {
                    None => {
                        return Some(format!(
                            "`{path}/{key}` — present in the fixture, absent after re-serialisation"
                        ))
                    }
                    Some(right_value) => {
                        let child = format!("{path}/{key}");
                        if let Some(found) = first_difference(left_value, right_value, &child) {
                            return Some(found);
                        }
                    }
                }
            }
            r.keys().find(|key| !l.contains_key(*key)).map(|key| {
                format!("`{path}/{key}` — absent in the fixture, emitted by re-serialisation")
            })
        }
        (Value::Array(l), Value::Array(r)) => {
            if l.len() != r.len() {
                return Some(format!(
                    "`{path}` — {} element(s) in the fixture, {} after re-serialisation",
                    l.len(),
                    r.len()
                ));
            }
            l.iter()
                .zip(r)
                .enumerate()
                .find_map(|(index, (left_value, right_value))| {
                    first_difference(left_value, right_value, &format!("{path}/{index}"))
                })
        }
        _ if left == right => None,
        _ => Some(format!(
            "`{path}` — fixture has {left}, re-serialisation produced {right}"
        )),
    }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 2. The container header and the archetype
// ─────────────────────────────────────────────────────────────────────────────────────────────

#[test]
fn header_identifies_a_version_1_kernel_artifact() {
    let profile = load();
    assert_eq!(
        profile.magic, MAGIC,
        "ADR 07 §7.2 / §6.2.5: the container magic is the four bytes b\"SNTL\""
    );
    assert_eq!(
        profile.magic, *b"SNTL",
        "ADR 07 §7.2: `magic` must be the literal string \"SNTL\" on the wire"
    );
    assert_eq!(
        profile.schema_version, 1,
        "ADR 07 §7.3.3 emits schema_version 1; §6.5 makes a mismatch on this axis a refusal, not a \
         warning"
    );
    assert_eq!(
        profile.schema_version, SCHEMA_VERSION,
        "the fixture and `kernel::SCHEMA_VERSION` must agree, or the model is emitting a version \
         it cannot itself read"
    );
}

#[test]
fn archetype_is_the_night_elf_hunter_of_section_7_3() {
    let profile = load();
    let archetype = &profile.archetype;

    assert_eq!(
        archetype.class,
        Class::Hunter,
        "ADR 07 §7.3.1: the worked example is compiled for a Hunter"
    );
    assert_eq!(
        archetype.race,
        Race::NightElf,
        "ADR 07 §7.3.1: … a Night Elf (the guide is A-11-23 Darkshore)"
    );
    assert_eq!(
        archetype.faction,
        Faction::Alliance,
        "ADR 07 §7.3.1: … Alliance. §5.2 (C2) keeps this as provenance only — player faction is \
         not readable from the Sylvanas API, so it must never become a runtime gate"
    );
    assert_eq!(
        archetype.expansion,
        Expansion::Tbc,
        "ADR 07 §4.2: all 277 RegisterGuide blocks carry #tbc"
    );
    assert_eq!(
        archetype.allegiance, None,
        "ADR 07 §5.2: no #aldor / #scryer in this guide range, so the Shattrath branch is absent"
    );
    assert!(
        !archetype.hardcore,
        "ADR 07 §7.3.3: the worked example is not a #hardcore compile"
    );
    assert!(
        !archetype.self_found,
        "ADR 07 §7.3.3: the worked example is not a #ssf compile"
    );
    assert!(
        !archetype.can_fly,
        "ADR 07 §7.3.3: TBC level 11-23 Darkshore, no #flyable"
    );
    assert_eq!(
        archetype.content_phase, None,
        "ADR 07 §7.3.3: no #phase in this guide"
    );
    assert_eq!(
        archetype.mode,
        ProfileMode::SpeedRoute,
        "ADR 07 §4.2: the absence of #questguide is the speed route"
    );
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 3. §7.3.3 lines 2005-2009 ("Step types exercised") — what the example claims to exercise
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// §5.3 (C3) sticky patrol + §5.7 (C7) baked circuit + §5.6 (C6) aggressive grind policy.
#[test]
fn task_0_is_a_sticky_aggressive_grind_circuit() {
    let profile = load();
    let task_0 = task(&profile, 0);

    // ── Lifetime: #sticky becomes Background holding MOVEMENT at a Goal band.
    let (channels, band, terminate_on) = background(task_0);
    assert_eq!(
        channels,
        [Channel::Movement],
        "ADR 07 §5.3 (C3): the #sticky patrol claims MOVEMENT and nothing else, so a foreground \
         turn-in can hold INTERACTION concurrently"
    );
    assert_eq!(
        band, 34,
        "ADR 07 §7.3.3: task 0 sits at band 34 (§7.2 pins the Goal band to 30..=49, offset by task \
         order so two sticky tasks cannot deadlock)"
    );
    assert_eq!(
        terminate_on,
        &Predicate::QuestTurnedIn { id: 983 },
        "ADR 07 §5.3: a background task needs a voluntary, permanent termination condition — here, \
         quest 983 being handed in. Termination is not suspension"
    );

    // ── Route: #loop becomes a closed circuit the engine must not smooth away.
    let route = travel_route(task_0, 0);
    assert_eq!(
        route.kind,
        RouteKind::Circuit { close: true },
        "ADR 07 §5.7 (C7): #loop lowers to a closed Circuit. A navmesh handed A→A returns a \
         zero-length path and cannot know the intent is to walk the loop to farm respawns — the \
         route IS the objective"
    );
    assert_eq!(
        route.mode,
        TravelMode::Ground,
        "ADR 07 §7.3.3: task 0's circuit is a ground route"
    );
    assert_eq!(
        route.points.len(),
        17,
        "D2 / ADR 07 §7.3.2: A-11-23.lua:215-231 is 3 .goto + 14 .waypoint = 17 route lines. The \
         ADR's printed 18 points is off by one, and no 18th line exists to point at. Interning the \
         pool (D6) shortened the POOL, never this route"
    );
    assert_eq!(
        route.radii.len(),
        route.points.len(),
        "ADR 07 §7.1: Route::radii is parallel to Route::points"
    );

    // ── Closure: the circuit returns to where it started.
    let first = route.points[0] as usize;
    let last = route.points[route.points.len() - 1] as usize;
    assert_eq!(
        profile.waypoint_pool[last], profile.waypoint_pool[first],
        "ADR 07 §5.7: the last .waypoint of A-11-23.lua:215-231 is byte-identical to the first \
         .goto — that identity is what makes this a circuit rather than a corridor. Compared as \
         coordinates ({first} vs {last}) so the check survives however the pool is numbered"
    );
    assert_eq!(
        first, last,
        "D6: the pool is interned, so the two ends of a closed circuit are not merely equal \
         coordinates — they are the SAME pool entry, named twice. A route that re-crosses a point \
         repeats the index (§7.1: 'deduplicated; routes index into this'); two distinct indices \
         holding one coordinate is the un-interned pool §7.1 and §6.4 rule out (not the route-level \
         doubling §8 warns about — a different operation)"
    );

    // ── Combat: #loop + .mob + .complete is the aggressive grind case.
    let policy = combat(task_0);
    assert_eq!(
        policy.stance,
        CombatStance::Aggressive,
        "ADR 07 §5.6 (C6): #loop + .mob + .complete (1,661 corpus instances) is a grind circuit, \
         and a grind circuit WANTS pulls"
    );
    assert_eq!(
        entries(&policy.targets),
        vec![2231, 2234],
        "ADR 07 §7.3.2: the two verified creature entries are 2231 and 2234"
    );
    assert_eq!(
        policy.targets[0].expect_name, "Pygmy Tide Crawler",
        "ADR 07 §5.4.1 / §5.8: expect_name is what makes content drift detectable — the \
         first-touch probe compares the observed unit name against it, because content_hash cannot \
         be checked against the server"
    );
    assert_eq!(
        policy.targets[1].expect_name, "Young Reef Crawler",
        "ADR 07 §7.3.2: entry 2234 resolves to Young Reef Crawler in tbcmangos.sqlite"
    );
}

/// §7.1 loot filter: `.collect` lowers to a `LootRule`, not to a bespoke op.
#[test]
fn task_1_is_an_exclusive_destination_with_a_quest_scoped_loot_filter() {
    let profile = load();
    let task_1 = task(&profile, 1);

    assert_eq!(
        task_1.lifetime,
        Lifetime::Exclusive,
        "ADR 07 §5.3 (C3): no #sticky means the foreground task"
    );
    assert_eq!(
        task_1.ops.len(),
        1,
        "ADR 07 §7.3.3: task 1 is a single travel op"
    );
    let route = travel_route(task_1, 0);
    assert_eq!(
        route.kind,
        RouteKind::Destination,
        "ADR 07 §5.7 (C7): a three-argument .goto is a Destination the engine may path to freely — \
         not a corridor and not a circuit"
    );
    assert_eq!(
        route.points.len(),
        1,
        "ADR 07 §7.1: a Destination carries exactly one pooled point"
    );

    assert_eq!(
        task_1.loot_filter,
        vec![LootRule {
            item: 12242,
            for_quest: Some(3524),
        }],
        "ADR 07 §4.1 / §7.1: .collect lowers to a LootRule carrying the item and its owning quest. \
         The required *count* is deliberately not here — that half lowers to Predicate::ItemCount"
    );
}

/// §7.1 step-as-container: a task's ops are **ordered** and heterogeneous.
#[test]
fn task_2_orders_travel_before_use_item() {
    let profile = load();
    let task_2 = task(&profile, 2);

    let (_, band, _) = background(task_2);
    assert_eq!(
        band, 35,
        "ADR 07 §5.3: bands are offset by task order — task 0 is 34, task 2 is 35, so two sticky \
         tasks cannot deadlock over MOVEMENT"
    );
    assert_eq!(
        travel_route(task_2, 0).kind,
        RouteKind::Circuit { close: true },
        "ADR 07 §5.7 (C7): task 2 is the second baked circuit"
    );

    assert_eq!(
        task_2.ops.len(),
        2,
        "ADR 07 §7.1: task 2 is the step-as-container witness — travel, then use the item"
    );
    assert!(
        matches!(task_2.ops[0], Op::Travel { .. }),
        "ADR 07 §7.1: op 0 must be Travel. Ordering IS the point of step-as-container — one action \
         per step cannot express 'walk the circuit, then use Tharnariun's Hope'. Got {:?}",
        task_2.ops[0]
    );
    assert_eq!(
        task_2.ops[1],
        Op::UseItem { item: 7586 },
        "ADR 07 §7.3.3: op 1 must be UseItem(7586, Tharnariun's Hope), and it must come *after* \
         the travel op"
    );

    let policy = combat(task_2);
    assert!(
        entries(&policy.watch_units).contains(&2164),
        "ADR 07 §5.6: .unitscan feeds CombatPolicy::watch_units — entry 2164 (Rabid Thistle Bear) \
         must be watched. Got {:?}",
        entries(&policy.watch_units)
    );
    assert!(
        !policy.allow_adds,
        "ADR 07 §5.6: an Objective-stance task kills what blocks the objective and refuses adds"
    );
}

/// §7.3.2 / §8: an exploration objective has no `Req*` columns, so `need` is legitimately zero.
#[test]
fn task_3_completes_on_a_zero_count_exploration_objective() {
    let profile = load();
    let task_3 = task(&profile, 3);

    let complete_when = task_3
        .complete_when
        .as_ref()
        .expect("ADR 07 §5.1 (C1): complete_when is the only completion authority");

    assert_eq!(
        complete_when,
        &Predicate::QuestObjective {
            id: 984,
            index: 1,
            need: 0,
        },
        "ADR 07 §7.3.3: task 3 completes on quest 984, objective 1"
    );

    match complete_when {
        Predicate::QuestObjective { need, .. } => assert_eq!(
            *need, 0,
            "ADR 07 §7.3.2 / §8: quest 984 (How Big a Threat?) has NO Req* columns populated — it \
             is an exploration objective satisfied by area discovery, not by a count. A \
             positive-count validation anywhere in the pipeline would make this task \
             unsatisfiable forever"
        ),
        other => panic!("expected QuestObjective, got {other:?}"),
    }
}

/// **Requirement P1.** Multi-dependency is the norm, not an edge case (349 `#requires` edges,
/// 1,246 distinct `#completewith` labels), and this is the task that proves the model expresses it.
#[test]
fn task_4_carries_multiple_ordered_dependencies_p1() {
    let profile = load();
    let task_4 = task(&profile, 4);

    assert_eq!(
        task_4.deps.len(),
        2,
        "P1 / ADR 07 §7.1: Task::deps is a Vec, not an Option. Task 4 is the folded --XXREQ \
         placeholder step and depends on TWO predecessors. If this is 1, the model has collapsed \
         back to single-dependency and R1 has failed"
    );
    assert_eq!(
        task_4.deps,
        vec![2, 0],
        "P1 / ADR 07 §7.3.3: the dependency set is [2, 0] — in that order. Order is part of the \
         value; a set-like reordering to [0, 2] is a different artifact and a different digest"
    );

    assert!(
        !task_4.blocking,
        "ADR 07 §7.1: the folded placeholder step is non-blocking — it exists to carry the \
         dependency edges, not to stall the profile"
    );
    assert!(
        task_4.ops.is_empty(),
        "ADR 07 §7.3.3: the --XXREQ placeholder has no work of its own. Got {:?}",
        task_4.ops
    );

    let complete_when = task_4
        .complete_when
        .as_ref()
        .expect("ADR 07 §5.1 (C1): task 4 must carry the folded completion predicate");

    let conjuncts = match complete_when {
        Predicate::And(conjuncts) => conjuncts,
        other => panic!(
            "P1 / ADR 07 §7.3.3: task 4's complete_when must be Predicate::And — one objective \
             predicate per predecessor. Got {other:?}"
        ),
    };
    assert_eq!(
        conjuncts.len(),
        2,
        "P1: exactly two conjuncts, one per dependency. Got {conjuncts:?}"
    );
    assert_eq!(
        conjuncts[0],
        Predicate::QuestObjective {
            id: 2118,
            index: 1,
            need: 1,
        },
        "P1 / ADR 07 §7.3.3: the first conjunct mirrors dep 2 (quest 2118)"
    );
    assert_eq!(
        conjuncts[1],
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 6,
        },
        "P1 / ADR 07 §7.3.3: the second conjunct mirrors dep 0 (quest 983, six Crawler Legs)"
    );
}

/// §8 fallback grinding: an XP goal with no target whitelist at all.
#[test]
fn task_5_is_an_xp_goal_with_open_ended_grinding() {
    let profile = load();
    let task_5 = task(&profile, 5);

    assert_eq!(
        task_5.complete_when,
        Some(Predicate::XpAtLeast {
            level: 10,
            xp_offset: 6760,
        }),
        "ADR 07 §5.1.1: .xp (2,133 uses) folds both corpus forms into a level plus a signed offset"
    );
    assert!(
        !task_5.blocking,
        "ADR 07 §7.3.3: the XP catch-up task must not stall the profile if the player is already \
         ahead"
    );
    assert_eq!(
        task_5.unknown_policy,
        UnknownPolicy::TreatFalse,
        "ADR 07 §5.1.2: grinding more XP is idempotent, so Unknown may safely be treated as 'not \
         yet satisfied'. The failure this avoids is Unknown → Block on a task that only ever adds \
         progress"
    );

    let policy = combat(task_5);
    assert_eq!(
        policy.stance,
        CombatStance::Aggressive,
        "ADR 07 §8: fallback grinding pulls proactively"
    );
    assert!(
        policy.targets.is_empty(),
        "ADR 07 §8: fallback grinding has an EMPTY whitelist — kill whatever is level-appropriate. \
         An empty .mob list is the signal, not a missing field. Got {:?}",
        entries(&policy.targets)
    );
}

/// §5.3 (C3): `Lifetime` and `CompletionSource` are independent fields.
#[test]
fn task_6_is_completewith_only_and_contends_for_nothing() {
    let profile = load();
    let task_6 = task(&profile, 6);

    let linked = match task_6.completion {
        CompletionSource::LinkedTo(target) => target,
        CompletionSource::OwnPredicate => panic!(
            "ADR 07 §5.3 (C3): task 6 is the #completewith witness — its completion must be \
             LinkedTo, not OwnPredicate"
        ),
    };
    assert_eq!(
        linked, 7,
        "ADR 07 §7.3.3: task 6's completion is linked to task 7. §5.3 requires a RESOLVED INDEX, \
         never a dangling label — RXPGuides' guide.labels[…] lookup returns nil and the edge \
         silently never fires"
    );
    assert!(
        (linked as usize) < profile.tasks.len(),
        "ADR 07 §5.3: LinkedTo({linked}) must index a task that exists; the profile has {} tasks",
        profile.tasks.len()
    );
    // On the wire the payload must be the bare integer 7, not `{"target": 7}` and not `"7"` —
    // §7.3.3 prints `"completion": {"type": "LinkedTo", "payload": 7}` and the Lua kernel reads
    // `completion.payload` directly as a task index.
    assert_eq!(
        serde_json::to_value(task_6.completion).expect("completion serialises"),
        serde_json::json!({ "type": "LinkedTo", "payload": 7 }),
        "ADR 07 §5.4 (C4) / §7.3.3: CompletionSource is adjacently tagged and LinkedTo is a newtype \
         variant, so the payload is the bare integer task index"
    );

    let (channels, _, _) = background(task_6);
    assert!(
        channels.is_empty(),
        "ADR 07 §5.3 (C3): a #completewith-only task becomes Background with an EMPTY channel set \
         — it rides along without contending for anything. Collapsing Lifetime and \
         CompletionSource into one 'background' flag is exactly what makes the RXPGuides model \
         unable to express the 37 steps carrying both. Got {channels:?}"
    );
}

/// §7.3.2 / §8: quest 983's ender is `gameobject_involvedrelation` 17182, not a creature.
#[test]
fn task_7_turns_in_at_a_gameobject_with_no_creature_target() {
    let profile = load();
    let task_7 = task(&profile, 7);

    assert_eq!(
        task_7.deps,
        vec![0],
        "ADR 07 §7.3.3: the turn-in depends on the grind circuit that fills the objective"
    );
    assert_eq!(
        task_7.interact_target, None,
        "ADR 07 §7.3.2 / §8: quest 983's ender is gameobject_involvedrelation entry 17182, NOT a \
         creature. `None` is a correct value here, not an omission — a schema that assumed every \
         turn-in has an NPC target would emit a null target and stall. Got {:?}",
        task_7.interact_target
    );

    assert_eq!(
        task_7.ops.len(),
        2,
        "ADR 07 §7.3.3: task 7 is travel, then turn in"
    );
    assert!(
        matches!(task_7.ops[0], Op::Travel { .. }),
        "ADR 07 §7.1: op 0 must be Travel — you cannot hand in a quest before arriving. Got {:?}",
        task_7.ops[0]
    );
    assert_eq!(
        task_7.ops[1],
        Op::TurnIn {
            quest: 983,
            any_of: vec![],
            reward_choice: None,
            optional: false,
            repeatable: false,
        },
        "ADR 07 §7.1: the turn-in op carries the quest id and nothing about the object. `any_of` \
         is empty because this is not the Aldor/Scryer allegiance choice point"
    );
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 4. Whole-profile invariants — loops, not eight hand-written cases, so they survive R2
//    regenerating the fixture
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// Every route's `radii` is parallel to its `points` (§7.1).
#[test]
fn every_route_has_one_radius_per_point() {
    let profile = load();
    let mut checked = 0;
    for task in &profile.tasks {
        for (index, op) in task.ops.iter().enumerate() {
            if let Op::Travel { route } = op {
                assert_eq!(
                    route.points.len(),
                    route.radii.len(),
                    "ADR 07 §7.1: Route::radii is 'arrival radius per point, parallel to points'. \
                     task {}, op {index} has {} point(s) and {} radius/radii",
                    task.id,
                    route.points.len(),
                    route.radii.len()
                );
                assert!(
                    !route.points.is_empty(),
                    "ADR 07 §5.7: task {}, op {index} is a Travel op with no points — there is \
                     nowhere to go",
                    task.id
                );
                checked += 1;
            }
        }
    }
    assert_eq!(
        checked, 5,
        "ADR 07 §7.3.3: tasks 0, 1, 2, 3 and 7 each carry exactly one Travel op; tasks 4, 5 and 6 \
         carry none"
    );
}

/// Every waypoint index anywhere in the artifact addresses a real pool entry (§7.1).
///
/// Deliberately a walk of the whole profile — routes, NPC positions, `AtLocation` predicates and
/// the corpse behaviour's resurrect point — rather than five hand-written route checks, so it keeps
/// holding when the fixture is regenerated.
#[test]
fn every_waypoint_index_addresses_a_real_pool_entry() {
    let profile = load();
    let pool_len = profile.waypoint_pool.len();
    assert_eq!(
        pool_len, POOL_LEN,
        "D6: the interned, corpus-derived pool is {POOL_LEN} distinct entries"
    );

    let references = pool_references(&profile);
    assert!(
        !references.is_empty(),
        "the fixture must reference the waypoint pool at all, or the pool is dead weight"
    );

    for (where_, index) in &references {
        assert!(
            (*index as usize) < pool_len,
            "ADR 07 §7.1: {where_} = {index} is out of bounds for a {pool_len}-entry \
             waypoint_pool. Every route point, NPC position and AtLocation predicate indexes the \
             ONE shared pool"
        );
    }

    // No orphan entries: a pool slot nothing points at is either a lowering bug or a stale
    // hand-edit, and it silently shifts every later index.
    //
    // Reachability is the invariant, NOT "referenced exactly once". That stronger form held only
    // while the pool carried one row per source route line, and D6's interning makes it unachievable
    // by construction: a closed `Circuit` returns to a point it has already visited, so it must name
    // that entry a second time. Six of the 22 entries are referenced twice, for two unrelated
    // reasons: task 0 names indices 0, 1, 2 and 3 twice because it genuinely walks those
    // coordinates twice (`A-11-23.lua:224`, `:225`, `:226` and `:231` re-visit `:217`, `:218`,
    // `:216` and `:215`), while task 2 names 14 and 15 twice only because of the §2.6 double
    // emission — `:247`/`:248` are 4-arg `.goto`s re-emitted 5-arg by `:249`/`:254`, so route-level
    // dedup will take task 2 from 8 points to 6. Both are legal here (§7.1: a route that re-crosses
    // a point repeats the *index*). In-bounds above plus reachable here is therefore the whole of
    // what multiplicity can tell us — geometry is checked by the per-task tests.
    let used: BTreeSet<u32> = references.iter().map(|(_, index)| *index).collect();
    let unused: Vec<usize> = (0..pool_len).filter(|i| !used.contains(&(*i as u32))).collect();
    assert!(
        unused.is_empty(),
        "ADR 07 §7.3.3: every pool entry must be referenced at least once. Unused indices \
         {unused:?} mean the pool and the routes disagree — a slot left behind by a bad index remap \
         (D6) or by the off-by-one D2 corrects"
    );
}

/// No two `waypoint_pool` entries hold the same coordinate (§7.1).
///
/// The pool is **interned**: one entry per distinct `(map_id, x, y, z)`, and a route that
/// re-crosses its own path says so by repeating an *index*, never by carrying a second copy of the
/// point. Two clauses of ADR 07 assert exactly this pool shape, and neither is hedged:
///
/// * §7.1:1179 — `pub waypoint_pool:  Vec<Point>,       // deduplicated; routes index into this`
/// * §6.4:1124 — the pool "deduplicates shared points across tasks"
///
/// §7.3.3 is the artifact those two clauses point at, so until it interns, it is the
/// counter-example to both rather than the demonstration of them.
///
/// Two further clauses — §2.6:232 ("An importer treating each `.goto` as a distinct route node
/// doubles the path") and §8:2038 ("an importer that does not doubles every affected route") —
/// describe a **different** operation and are *not* what this test pins. Both state a route-*length*
/// consequence, and interning changes no route's length. That route-level dedup is a later
/// deliverable (ADR 07 §9 item 26).
///
/// **What this test cannot see.** Three things, deliberately:
///
/// 1. It reads the pool alone, never a route. That the indices were remapped *correctly* — that
///    every route still traces the same sequence of world coordinates it traced before interning —
///    is invisible here. The neighbouring `every_waypoint_index_addresses_a_real_pool_entry` proves
///    only that each index is in bounds and each slot is reachable; a route whose points were
///    permuted into other valid slots passes both tests while walking a different path. Only
///    `task_0_is_a_sticky_aggressive_grind_circuit`, which compares coordinates rather than indices,
///    watches any actual geometry.
/// 2. It says nothing about repeats *within* a route, and those repeats have two unrelated causes.
///    Task 0's are real: it is a `Circuit` with `close: true` that genuinely re-crosses its own
///    path, so its 17 points must stay 17 through any later dedup. Task 2's are not: indices 14 and
///    15 repeat because of the §2.6:232 defect — one source step emitting the same coordinate
///    twice, once 4-arg (`A-11-23.lua:247`, `:248`) and once 5-arg (`:249`, `:254`) — which is a
///    route-level collapse this invariant neither performs nor forbids, and which will shorten
///    task 2 from 8 points to 6.
/// 3. Equality is `f32` value equality. Two coordinates for the same world position that differ in
///    the last ULP (`36.051` against `36.051002`) read as distinct entries and pass, so this pins
///    an importer that copies a point verbatim, not one that re-derives it at a different precision.
#[test]
fn no_two_waypoint_pool_entries_hold_the_same_coordinate() {
    let profile = load();
    let pool = &profile.waypoint_pool;

    // O(n²) over a pool this size, and `Point` is only `PartialEq` (it carries `f32`), so a
    // hash/sort key would have to be invented here — the pairwise scan compares the same values the
    // invariant is stated over.
    let duplicates: Vec<String> = pool
        .iter()
        .enumerate()
        .filter_map(|(later, point)| {
            let first = pool[..later].iter().position(|earlier| earlier == point)?;
            Some(format!(
                "slots {first} and {later} both hold (map {}, {}, {}, z {:?})",
                point.map_id, point.x, point.y, point.z
            ))
        })
        .collect();

    assert!(
        duplicates.is_empty(),
        "ADR 07 §7.1:1179 declares `waypoint_pool` 'deduplicated; routes index into this' and \
         §6.4:1124 says the pool 'deduplicates shared points across tasks'. (§2.6:232 and §8:2038 \
         are about the separate route-level collapse — §8 says an importer that does not \
         deduplicate 'doubles every affected route' — which this invariant does not pin.) {} of the \
         {} entries in {FIXTURE_PATH} are repeats of an earlier entry, so §7.3.3 is the \
         counter-example to its own schema. A route that re-crosses a point must repeat the index, \
         not the point:\n  {}",
        duplicates.len(),
        pool.len(),
        duplicates.join("\n  ")
    );
}

/// Every task cross-reference resolves to a task that exists (§5.3, §7.1).
#[test]
fn every_task_reference_resolves_to_an_existing_task() {
    let profile = load();
    let count = profile.tasks.len() as TaskId;

    for (index, task) in profile.tasks.iter().enumerate() {
        assert_eq!(
            task.id, index as TaskId,
            "ADR 07 §7.1: task order IS the TaskId, and the compiler resolves every #label to this \
             index. tasks[{index}] claims id {}",
            task.id
        );

        for dep in &task.deps {
            assert!(
                *dep < count,
                "ADR 07 §7.1: task {} depends on task {dep}, which does not exist (the profile has \
                 {count} tasks). #requires labels are resolved by the compiler and a dangling edge \
                 must never reach the artifact",
                task.id
            );
            assert_ne!(
                *dep, task.id,
                "ADR 07 §7.1: task {} depends on itself, which can never be satisfied",
                task.id
            );
        }

        if let CompletionSource::LinkedTo(target) = task.completion {
            assert!(
                target < count,
                "ADR 07 §5.3 (C3): task {} is LinkedTo({target}), which does not exist. The \
                 compiler resolves every #completewith label and emits a hard diagnostic for an \
                 unresolved one — RXPGuides' silent nil lookup is the failure mode this prevents",
                task.id
            );
            assert_ne!(
                target, task.id,
                "ADR 07 §5.3: task {} is LinkedTo itself, so its completion can never fire",
                task.id
            );
        }

        if let Some(jump) = task.jump_to {
            assert!(
                jump < count,
                "ADR 07 §4.1: task {} jumps to {jump}, which does not exist",
                task.id
            );
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 5. C4 tag census
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// §5.4 (C4) defines `tags_used` as "every op and predicate tag referenced by this artifact". The
/// fail-closed loader refuses an artifact naming a tag it does not implement, so the field is only
/// load-bearing if it is an accurate census — and it has to be exact in **both** directions. A
/// spurious tag makes a fail-closed kernel refuse an artifact it could actually have run; a missing
/// tag lets this very check pass on an artifact the kernel cannot fully evaluate, which defeats the
/// check entirely.
///
/// §7.3.3 originally failed both ways at once: it listed `Wait`, `Delegate`, `Or` and `Not`, which
/// no task uses, and **omitted `QuestComplete`**, which task 7's `applies_when` does use. The audit
/// resolved it in favour of the census — §5.10 now says "exactly", and §7.3.3 lists the ten tags the
/// artifact really references (§9 item 24). The fixture follows the corrected ADR.
#[test]
fn tags_used_is_an_accurate_census_of_ops_and_predicates() {
    let profile = load();

    let declared: BTreeSet<String> = profile.tags_used.iter().cloned().collect();
    let mut observed: BTreeSet<String> = BTreeSet::new();
    for task in &profile.tasks {
        for op in &task.ops {
            observed.insert(tag_of(op));
        }
        if let Lifetime::Background { terminate_on, .. } = &task.lifetime {
            collect_predicate_tags(terminate_on, &mut observed);
        }
        for predicate in [&task.applies_when, &task.complete_when, &task.abort_when]
            .into_iter()
            .flatten()
        {
            collect_predicate_tags(predicate, &mut observed);
        }
    }

    let missing: Vec<&String> = observed.difference(&declared).collect();
    let spurious: Vec<&String> = declared.difference(&observed).collect();

    assert!(
        missing.is_empty() && spurious.is_empty(),
        "ADR 07 §5.4 (C4): tags_used must be exactly the set of op and predicate tags the artifact \
         uses.\n  used but not declared: {missing:?}\n  declared but not used : {spurious:?}\n\
         A tag missing from the list defeats the fail-closed loader; a spurious tag makes a kernel \
         refuse an artifact it could actually run."
    );
}

fn tag_of<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_value(value)
        .expect("adjacently tagged value serialises")
        .get("type")
        .and_then(Value::as_str)
        .expect("ADR 07 §5.4 (C4): every enum the kernel dispatches on is adjacently tagged with `type`")
        .to_owned()
}

fn collect_predicate_tags(predicate: &Predicate, out: &mut BTreeSet<String>) {
    out.insert(tag_of(predicate));
    match predicate {
        Predicate::And(children) | Predicate::Or(children) => {
            for child in children {
                collect_predicate_tags(child, out);
            }
        }
        Predicate::Not(child) => collect_predicate_tags(child, out),
        _ => {}
    }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Pool-reference walker
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// Collects every `(location, waypoint_pool index)` pair in the artifact.
///
/// The `Op` and `Predicate` matches below are exhaustive on purpose: adding a variant that can
/// address the pool should break this file's compilation rather than silently escape the bounds
/// check.
fn pool_references(profile: &RuntimeProfile) -> Vec<(String, u32)> {
    let mut out = Vec::new();

    push_combat("defaults.combat", &profile.defaults.combat, &mut out);

    for task in &profile.tasks {
        let id = task.id;

        if let Some(npc) = &task.interact_target {
            push_npc(&format!("task {id}.interact_target"), npc, &mut out);
        }
        if let Some(policy) = &task.combat {
            push_combat(&format!("task {id}.combat"), policy, &mut out);
        }

        for (index, op) in task.ops.iter().enumerate() {
            let at = format!("task {id}.ops[{index}]");
            match op {
                Op::Travel { route } => {
                    for (position, point) in route.points.iter().enumerate() {
                        out.push((format!("{at}.route.points[{position}]"), *point));
                    }
                }
                Op::Interact { npc, .. } => push_npc(&format!("{at}.npc"), npc, &mut out),
                Op::Delegate { payload, .. } => push_delegate(&at, payload, &mut out),
                Op::Accept { .. }
                | Op::TurnIn { .. }
                | Op::Abandon { .. }
                | Op::UntrackQuest { .. }
                | Op::UseItem { .. }
                | Op::Cast { .. }
                | Op::DestroyItem { .. }
                | Op::Equip { .. }
                | Op::EnterVehicle
                | Op::Wait { .. } => {}
            }
        }

        if let Lifetime::Background { terminate_on, .. } = &task.lifetime {
            push_predicate(
                &format!("task {id}.lifetime.terminate_on"),
                terminate_on,
                &mut out,
            );
        }
        for (label, predicate) in [
            ("applies_when", &task.applies_when),
            ("complete_when", &task.complete_when),
            ("abort_when", &task.abort_when),
        ] {
            if let Some(predicate) = predicate {
                push_predicate(&format!("task {id}.{label}"), predicate, &mut out);
            }
        }
    }

    out
}

fn push_combat(at: &str, policy: &CombatPolicy, out: &mut Vec<(String, u32)>) {
    for (index, npc) in policy.targets.iter().enumerate() {
        push_npc(&format!("{at}.targets[{index}]"), npc, out);
    }
    for (index, npc) in policy.watch_units.iter().enumerate() {
        push_npc(&format!("{at}.watch_units[{index}]"), npc, out);
    }
}

fn push_npc(at: &str, npc: &NpcRef, out: &mut Vec<(String, u32)>) {
    if let Some(pos) = npc.pos {
        out.push((format!("{at}.pos"), pos));
    }
}

fn push_delegate(at: &str, payload: &DelegatePayload, out: &mut Vec<(String, u32)>) {
    match payload {
        DelegatePayload::Vendor { npc, .. }
        | DelegatePayload::Trainer { npc, .. }
        | DelegatePayload::FlightPath { npc, .. }
        | DelegatePayload::Bank { npc, .. }
        | DelegatePayload::Stable { npc, .. } => push_npc(&format!("{at}.payload.npc"), npc, out),
        DelegatePayload::Hearth { npc, .. } => {
            if let Some(npc) = npc {
                push_npc(&format!("{at}.payload.npc"), npc, out);
            }
        }
        DelegatePayload::Corpse { resurrect_at, .. } => {
            if let Some(point) = resurrect_at {
                out.push((format!("{at}.payload.resurrect_at"), *point));
            }
        }
    }
}

fn push_predicate(at: &str, predicate: &Predicate, out: &mut Vec<(String, u32)>) {
    match predicate {
        Predicate::And(children) | Predicate::Or(children) => {
            for (index, child) in children.iter().enumerate() {
                push_predicate(&format!("{at}[{index}]"), child, out);
            }
        }
        Predicate::Not(child) => push_predicate(&format!("{at}.not"), child, out),
        Predicate::AtLocation { point, .. } => {
            out.push((format!("{at}.AtLocation.point"), *point))
        }
        Predicate::QuestComplete { .. }
        | Predicate::QuestObjective { .. }
        | Predicate::LevelAtLeast { .. }
        | Predicate::AuraPresent { .. }
        | Predicate::Flag { .. }
        | Predicate::QuestInLog { .. }
        | Predicate::QuestTurnedIn { .. }
        | Predicate::QuestAvailable { .. }
        | Predicate::ItemCount { .. }
        | Predicate::MoneyCmp { .. }
        | Predicate::SkillCmp { .. }
        | Predicate::ReputationCmp { .. }
        | Predicate::XpAtLeast { .. }
        | Predicate::CooldownCmp { .. }
        | Predicate::InArea { .. }
        | Predicate::HearthBoundTo { .. }
        | Predicate::ItemStatCmp { .. }
        | Predicate::InGroup { .. }
        | Predicate::SpellKnown { .. }
        | Predicate::LevelAtMost { .. } => {}
    }
}
