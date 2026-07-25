//! Wire-shape contract for the kernel artifact model (`sentinel_models::kernel`).
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §5.4 (contract C4) and §7.2.
//!
//! **Every assertion in this file is made against JSON, never against a Rust value.** That is the
//! whole point. The defect this file exists to prevent was invisible in Rust and lived only on the
//! wire: `sentinel_models::runtime::RuntimeCondition` was *externally* tagged, so every non-unit
//! condition arrived in Lua as `{"ClassIs": "Mage"}` instead of `{"type": "ClassIs", …}`, the
//! `cond.type` dispatch missed, and every such condition fell through to a fail-open `true`.
//! Condition gating silently stopped gating. A Rust-level `assert_eq!(round_trip, original)` would
//! have passed the whole time.
//!
//! Two rules are enforced here, and they are not interchangeable:
//!
//! 1. **Enums the kernel dispatches on are adjacently tagged** — `Lifetime`, `CompletionSource`,
//!    `UnknownPolicy`, `Op`, `RouteKind`, `GossipPolicy`, `DelegatePayload`, `CombatStance`,
//!    `GroupExpectation`, `Cmp`, `Predicate`. On the wire: an object whose only keys are `type` and
//!    `payload` (§5.4, §7.2). The rule is **role, not arity** — `CombatStance`, `GroupExpectation`
//!    and `Cmp` carry no payload on any variant and are tagged anyway, because a reader dispatches
//!    on them. Testing for "carries a payload" would wrongly exempt all three.
//! 2. **Scalar vocabulary is a bare JSON string** — `Class`, `Race`, `Faction`, `Expansion`,
//!    `Allegiance`, `ProfileMode`, `Channel`, `TravelMode`, `AreaKind`, `UnitRef`, `SkillLine`,
//!    `Standing`, `CooldownKind`, `ItemStat`, `BehaviorId`, `VendorMode`, `FlightMode`,
//!    `HearthMode`, `BankMode`, `StableMode`, `CorpseIntent`. §7.3.3 depends on this: it contains
//!    `"class": "Hunter"`, `"expansion": "Tbc"`, `"mode": "Ground"`, `"kind": "SubArea"`,
//!    `"channels": ["MOVEMENT"]`.
//!
//! `shape_check_rejects_external_internal_and_untagged_enums` is the control experiment: it runs
//! this file's own shape checker against locally declared externally-tagged, internally-tagged and
//! untagged enums and asserts the checker *rejects* all three. A shape check that cannot fail is
//! not a check.

use serde::Serialize;
use serde_json::{json, Value};

use sentinel_models::kernel::{
    Allegiance, AreaKind, BankMode, BehaviorId, Channel, Class, Cmp, CombatStance, CompletionSource,
    CooldownKind, CorpseIntent, DelegatePayload, Expansion, Faction, FlightMode, GossipPolicy,
    GroupExpectation, HearthMode, ItemStat, Lifetime, NpcRef, Op, Predicate, ProfileMode, Race,
    Route, RouteKind, SkillLine, StableMode, Standing, TravelMode, UnitRef, UnknownPolicy,
    VendorMode,
};

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Contract citations, quoted verbatim in every failure message so the next engineer is told
// *what* broke and *where it is written down*.
// ─────────────────────────────────────────────────────────────────────────────────────────────

const C4: &str = "ADR 07 §5.4 (contract C4) + §7.2: kernel enums the runtime DISPATCHES ON must be \
                  adjacently tagged, `#[serde(tag = \"type\", content = \"payload\")]`, i.e. a JSON \
                  object whose only keys are `type` and `payload`. By role, not by arity — \
                  `CombatStance`, `GroupExpectation` and `Cmp` carry no payload and are tagged \
                  anyway. External tagging (`{\"Variant\": …}`) is the bug this repo already \
                  shipped once: it made every non-unit condition fail OPEN in Lua";

const SCALAR: &str = "ADR 07 §7.3.3: scalar vocabulary enums are BARE JSON STRINGS \
                      (`\"class\": \"Hunter\"`, `\"mode\": \"Ground\"`, `\"kind\": \"SubArea\"`). \
                      Adjacently tagging one of these would stop the §7.3.3 fixture parsing";

const FIELDS: &str = "ADR 07 §7.1 (the authoritative Rust structs)";

// ─────────────────────────────────────────────────────────────────────────────────────────────
// The shape checker. Fallible on purpose — `shape_check_rejects_…` depends on it returning `Err`.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// Validate one serialized value against the adjacent-tagging contract and return its `payload`
/// (`Value::Null` when the key is absent, which is how serde spells a unit variant).
///
/// Rejects, in order: a non-object (a bare string is what a scalar-vocabulary enum looks like, and
/// a tagged enum must never degrade into one), any key that is neither `type` nor `payload`
/// (this is what catches BOTH external tagging, where the variant name *is* the key, and internal
/// tagging, where the payload fields are hoisted alongside `type`), a missing or non-string `type`,
/// and finally a `type` that is not the expected variant name.
fn adjacent_shape(value: &Value, expected_type: &str) -> Result<Value, String> {
    let object = match value {
        Value::Object(map) => map,
        other => {
            return Err(format!(
                "expected a JSON object, got the {} `{other}` — an adjacently tagged variant is \
                 never a bare scalar",
                kind_of(other)
            ))
        }
    };

    let mut stray: Vec<&str> = object
        .keys()
        .map(String::as_str)
        .filter(|key| *key != "type" && *key != "payload")
        .collect();
    stray.sort_unstable();
    if !stray.is_empty() {
        return Err(format!(
            "unexpected key(s) {stray:?} beside `type`/`payload`. Either the enum is EXTERNALLY \
             tagged (the variant name became the key) or INTERNALLY tagged (the payload fields \
             were hoisted)"
        ));
    }

    let tag = object
        .get("type")
        .ok_or_else(|| "no `type` key at all — this value carries no discriminant".to_owned())?;
    let tag = tag.as_str().ok_or_else(|| {
        format!(
            "`type` must be a string, got the {} `{tag}`",
            kind_of(tag)
        )
    })?;
    if tag != expected_type {
        return Err(format!(
            "`type` is {tag:?} but this variant must serialize as {expected_type:?}; a \
             `#[serde(rename)]` has drifted from the ADR vocabulary"
        ));
    }

    Ok(object.get("payload").cloned().unwrap_or(Value::Null))
}

fn kind_of(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

/// Serialize, then enforce adjacent tagging. Returns the `payload`.
#[track_caller]
fn assert_adjacent<T: Serialize>(label: &str, value: &T, expected_type: &str) -> Value {
    let json = serde_json::to_value(value)
        .unwrap_or_else(|error| panic!("{label}: serialization failed: {error}"));
    adjacent_shape(&json, expected_type).unwrap_or_else(|why| {
        panic!("{label} breaks the wire contract.\n  problem: {why}\n  serialized: {json}\n  contract: {C4}")
    })
}

/// A variant that carries data: `payload` must be present.
#[track_caller]
fn assert_adjacent_with_payload<T: Serialize>(label: &str, value: &T, expected_type: &str) -> Value {
    let json = serde_json::to_value(value)
        .unwrap_or_else(|error| panic!("{label}: serialization failed: {error}"));
    let payload = assert_adjacent(label, value, expected_type);
    assert!(
        json.get("payload").is_some(),
        "{label}: variant carries data but emitted no `payload` key.\n  serialized: {json}\n  \
         contract: {C4}"
    );
    payload
}

/// A variant that carries nothing: `payload` must be absent or explicitly null, and the value must
/// still be a tagged OBJECT rather than the bare string `"Aggressive"`.
///
/// Both spellings are admitted here because the model *emits* the absent form while artifacts
/// written against ADR 07's pre-audit text carry the explicit `null`. The audit (§9 item 23) settled
/// which one is canonical — serde's, i.e. absent — and moved §7.3.3 to match; see the note above
/// `unit_variants_accept_the_adr_7_3_3_explicit_null_payload`.
#[track_caller]
fn assert_adjacent_unit<T: Serialize>(label: &str, value: &T, expected_type: &str) {
    let json = serde_json::to_value(value)
        .unwrap_or_else(|error| panic!("{label}: serialization failed: {error}"));
    assert!(
        !json.is_string(),
        "{label}: a unit variant of an adjacently tagged enum serialized as the BARE STRING \
         {json} instead of a tagged object. Lua dispatches on `x.type`; a bare string has none.\n  \
         contract: {C4}"
    );
    let payload = assert_adjacent(label, value, expected_type);
    assert!(
        payload.is_null(),
        "{label}: a unit variant must carry no data, but `payload` is {payload}.\n  contract: {C4}"
    );
}

/// Assert a payload object's field-name set, exactly. Extra or renamed fields fail.
#[track_caller]
fn assert_payload_fields(label: &str, payload: &Value, expected: &[&str]) {
    let object = payload.as_object().unwrap_or_else(|| {
        panic!("{label}: expected a struct-variant payload OBJECT, got {payload}\n  contract: {FIELDS}")
    });
    let mut got: Vec<&str> = object.keys().map(String::as_str).collect();
    got.sort_unstable();
    let mut want: Vec<&str> = expected.to_vec();
    want.sort_unstable();
    assert_eq!(
        got, want,
        "{label}: payload field names disagree with {FIELDS}.\n  emitted: {got:?}\n  \
         required: {want:?}"
    );
}

/// Assert a scalar-vocabulary enum is a bare JSON string with the exact expected spelling.
#[track_caller]
fn assert_bare_string<T: Serialize>(label: &str, value: &T, expected: &str) {
    let json = serde_json::to_value(value)
        .unwrap_or_else(|error| panic!("{label}: serialization failed: {error}"));
    match &json {
        Value::String(text) => assert_eq!(
            text, expected,
            "{label}: wrong wire spelling.\n  contract: {SCALAR}"
        ),
        other => panic!(
            "{label}: expected a bare JSON string {expected:?}, got the {} {other}. Someone \
             adjacently tagged a leaf vocabulary.\n  contract: {SCALAR}",
            kind_of(other)
        ),
    }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────────────────────

fn npc() -> NpcRef {
    NpcRef {
        entry: 2231,
        expect_name: "Pygmy Tide Crawler".to_owned(),
        pos: Some(3),
    }
}

fn route() -> Route {
    Route {
        kind: RouteKind::Circuit { close: true },
        mode: TravelMode::Ground,
        points: vec![0, 1, 2],
        radii: vec![0, 0, 60],
    }
}

/// One instance of each of the 24 `Predicate` variants, in ADR §7.2 declaration order.
fn all_predicates() -> Vec<Predicate> {
    vec![
        Predicate::And(vec![Predicate::LevelAtLeast { level: 10 }]),
        Predicate::Or(vec![Predicate::QuestInLog { id: 983 }]),
        Predicate::Not(Box::new(Predicate::QuestTurnedIn { id: 983 })),
        Predicate::QuestComplete { id: 983 },
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 6,
        },
        Predicate::AtLocation {
            point: 17,
            radius: 5.0,
        },
        Predicate::LevelAtLeast { level: 11 },
        Predicate::AuraPresent {
            spell: 5384,
            on: UnitRef::Player,
        },
        Predicate::Flag {
            key: "kernel.resumed".to_owned(),
        },
        Predicate::QuestInLog { id: 2118 },
        Predicate::QuestTurnedIn { id: 984 },
        Predicate::QuestAvailable { id: 990 },
        Predicate::ItemCount {
            id: 5385,
            cmp: Cmp::Ge,
            count: 6,
        },
        Predicate::MoneyCmp {
            cmp: Cmp::Lt,
            copper: 4800,
        },
        Predicate::SkillCmp {
            line: SkillLine::Cooking,
            cmp: Cmp::Lt,
            value: 50,
        },
        Predicate::ReputationCmp {
            faction: 576,
            standing: Standing::Honored,
            cmp: Cmp::Ge,
            value: 0,
        },
        Predicate::XpAtLeast {
            level: 12,
            xp_offset: 6760,
        },
        Predicate::CooldownCmp {
            kind: CooldownKind::Item,
            id: 6948,
            cmp: Cmp::Gt,
            secs: 2.0,
        },
        Predicate::InArea {
            area: 442,
            kind: AreaKind::SubArea,
        },
        Predicate::HearthBoundTo { area: 148 },
        Predicate::ItemStatCmp {
            slot: 16,
            stat: ItemStat::DamagePerSecond,
            cmp: Cmp::Lt,
            value: 25.6,
        },
        Predicate::InGroup {
            cmp: Cmp::Ge,
            size: 2,
        },
        Predicate::SpellKnown { spell: 5384 },
        Predicate::LevelAtMost { level: 19 },
    ]
}

/// The Rust-side variant name of a predicate.
///
/// **This match is exhaustive on purpose.** Adding a 25th `Predicate` variant makes this file stop
/// compiling, which is the earliest possible signal that ADR 07 §7.2's `enum` list needs updating.
/// `predicate_tag_census_matches_adr_7_2` then turns the same drift into a readable assertion.
fn predicate_tag(predicate: &Predicate) -> &'static str {
    match predicate {
        Predicate::And(_) => "And",
        Predicate::Or(_) => "Or",
        Predicate::Not(_) => "Not",
        Predicate::QuestComplete { .. } => "QuestComplete",
        Predicate::QuestObjective { .. } => "QuestObjective",
        Predicate::AtLocation { .. } => "AtLocation",
        Predicate::LevelAtLeast { .. } => "LevelAtLeast",
        Predicate::AuraPresent { .. } => "AuraPresent",
        Predicate::Flag { .. } => "Flag",
        Predicate::QuestInLog { .. } => "QuestInLog",
        Predicate::QuestTurnedIn { .. } => "QuestTurnedIn",
        Predicate::QuestAvailable { .. } => "QuestAvailable",
        Predicate::ItemCount { .. } => "ItemCount",
        Predicate::MoneyCmp { .. } => "MoneyCmp",
        Predicate::SkillCmp { .. } => "SkillCmp",
        Predicate::ReputationCmp { .. } => "ReputationCmp",
        Predicate::XpAtLeast { .. } => "XpAtLeast",
        Predicate::CooldownCmp { .. } => "CooldownCmp",
        Predicate::InArea { .. } => "InArea",
        Predicate::HearthBoundTo { .. } => "HearthBoundTo",
        Predicate::ItemStatCmp { .. } => "ItemStatCmp",
        Predicate::InGroup { .. } => "InGroup",
        Predicate::SpellKnown { .. } => "SpellKnown",
        Predicate::LevelAtMost { .. } => "LevelAtMost",
    }
}

/// One instance of each of the 13 `Op` variants, in ADR §7.2 declaration order.
fn all_ops() -> Vec<Op> {
    vec![
        Op::Travel { route: route() },
        Op::Accept {
            quest: 983,
            repeatable: false,
        },
        Op::TurnIn {
            quest: 983,
            any_of: vec![],
            reward_choice: Some(2),
            optional: false,
            repeatable: false,
        },
        Op::Abandon { quests: vec![983] },
        Op::UntrackQuest { quest: 984 },
        Op::Interact {
            npc: npc(),
            gossip: GossipPolicy::AutoAdvance,
        },
        Op::UseItem { item: 7586 },
        Op::Cast { spell: 5384 },
        Op::DestroyItem { item: 5385 },
        Op::Equip {
            slot: 16,
            item: 2488,
        },
        Op::EnterVehicle,
        Op::Wait {
            secs: 30,
            label: "scripted RP".to_owned(),
        },
        Op::Delegate {
            behavior: BehaviorId::Hearth,
            payload: DelegatePayload::Hearth {
                mode: HearthMode::Use,
                npc: None,
            },
        },
    ]
}

/// Exhaustive on purpose, exactly like [`predicate_tag`].
fn op_tag(op: &Op) -> &'static str {
    match op {
        Op::Travel { .. } => "Travel",
        Op::Accept { .. } => "Accept",
        Op::TurnIn { .. } => "TurnIn",
        Op::Abandon { .. } => "Abandon",
        Op::UntrackQuest { .. } => "UntrackQuest",
        Op::Interact { .. } => "Interact",
        Op::UseItem { .. } => "UseItem",
        Op::Cast { .. } => "Cast",
        Op::DestroyItem { .. } => "DestroyItem",
        Op::Equip { .. } => "Equip",
        Op::EnterVehicle => "EnterVehicle",
        Op::Wait { .. } => "Wait",
        Op::Delegate { .. } => "Delegate",
    }
}

fn all_delegate_payloads() -> Vec<(DelegatePayload, &'static str)> {
    vec![
        (
            DelegatePayload::Vendor {
                npc: npc(),
                mode: VendorMode::Buy,
                items: vec![4540],
                gold_floor: Some(1000),
            },
            "Vendor",
        ),
        (
            DelegatePayload::Trainer {
                npc: npc(),
                spell: Some(5384),
            },
            "Trainer",
        ),
        (
            DelegatePayload::FlightPath {
                npc: npc(),
                mode: FlightMode::Discover,
                dest_node: Some("Auberdine".to_owned()),
            },
            "FlightPath",
        ),
        (
            DelegatePayload::Hearth {
                mode: HearthMode::Bind,
                npc: Some(npc()),
            },
            "Hearth",
        ),
        (
            DelegatePayload::Bank {
                npc: npc(),
                mode: BankMode::Withdraw,
                items: vec![5385],
            },
            "Bank",
        ),
        (
            DelegatePayload::Stable {
                npc: npc(),
                mode: StableMode::Visit,
            },
            "Stable",
        ),
        (
            DelegatePayload::Corpse {
                intent: CorpseIntent::DeliberateDeath,
                resurrect_at: Some(26),
            },
            "Corpse",
        ),
    ]
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// The control experiment: prove the shape checker can fail.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// A shape check that cannot fail is not a check.
///
/// These three local enums reproduce, byte for byte, the three wrong wire shapes ADR 07 §5.4
/// forbids. `ExternallyTagged` is the exact shape of the shipped `RuntimeCondition` bug.
#[test]
fn shape_check_rejects_external_internal_and_untagged_enums() {
    #[derive(Serialize)]
    enum ExternallyTagged {
        QuestInLog { id: u32 },
    }

    #[derive(Serialize)]
    #[serde(tag = "type")]
    enum InternallyTagged {
        QuestInLog { id: u32 },
    }

    #[derive(Serialize)]
    #[serde(untagged)]
    enum Untagged {
        QuestInLog { id: u32 },
    }

    #[derive(Serialize)]
    enum BareUnit {
        Aggressive,
    }

    // Sanity: these really do produce the shapes we claim they do.
    let external = serde_json::to_value(ExternallyTagged::QuestInLog { id: 983 }).unwrap();
    assert_eq!(external, json!({ "QuestInLog": { "id": 983 } }));
    let internal = serde_json::to_value(InternallyTagged::QuestInLog { id: 983 }).unwrap();
    assert_eq!(internal, json!({ "type": "QuestInLog", "id": 983 }));
    let untagged = serde_json::to_value(Untagged::QuestInLog { id: 983 }).unwrap();
    assert_eq!(untagged, json!({ "id": 983 }));
    let bare = serde_json::to_value(BareUnit::Aggressive).unwrap();
    assert_eq!(bare, json!("Aggressive"));

    // The checker must reject every one of them.
    let external_error = adjacent_shape(&external, "QuestInLog")
        .expect_err("EXTERNAL tagging must be rejected — this is the shipped fail-open bug");
    assert!(
        external_error.contains("EXTERNALLY tagged"),
        "external tagging must be diagnosed by name, got: {external_error}"
    );

    let internal_error = adjacent_shape(&internal, "QuestInLog")
        .expect_err("INTERNAL tagging must be rejected: the payload fields were hoisted");
    assert!(
        internal_error.contains("INTERNALLY tagged"),
        "internal tagging must be diagnosed by name, got: {internal_error}"
    );

    adjacent_shape(&untagged, "QuestInLog")
        .expect_err("an UNTAGGED payload must be rejected: no discriminant to dispatch on");
    adjacent_shape(&bare, "Aggressive")
        .expect_err("a BARE STRING must be rejected where a tagged object is required");
    adjacent_shape(&json!({ "type": "QuestTurnedIn", "payload": { "id": 983 } }), "QuestInLog")
        .expect_err("a mismatched `type` must be rejected: a rename has drifted from the ADR");

    // And the shape it must accept.
    let payload = adjacent_shape(
        &json!({ "type": "QuestInLog", "payload": { "id": 983 } }),
        "QuestInLog",
    )
    .expect("the canonical adjacently tagged shape must be accepted");
    assert_eq!(payload, json!({ "id": 983 }));
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Per-enum wire shape: every variant of every adjacently tagged enum.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// All 24 `Predicate` variants (§7.2). None of them is a unit variant — every one carries data.
#[test]
fn predicate_every_variant_is_adjacently_tagged() {
    for predicate in all_predicates() {
        let tag = predicate_tag(&predicate);
        assert_adjacent_with_payload(&format!("Predicate::{tag}"), &predicate, tag);
    }
}

/// All 13 `Op` variants (§7.2). `EnterVehicle` is the only unit variant.
#[test]
fn op_every_variant_is_adjacently_tagged() {
    for op in all_ops() {
        let tag = op_tag(&op);
        let label = format!("Op::{tag}");
        if tag == "EnterVehicle" {
            assert_adjacent_unit(&label, &op, tag);
        } else {
            assert_adjacent_with_payload(&label, &op, tag);
        }
    }
}

/// §5.3 (C3): `Lifetime` and `CompletionSource` are independent fields, and both are tagged.
#[test]
fn lifetime_every_variant_is_adjacently_tagged() {
    assert_adjacent_unit("Lifetime::Exclusive", &Lifetime::Exclusive, "Exclusive");

    let background = Lifetime::Background {
        channels: vec![Channel::Movement],
        band: 30,
        terminate_on: Predicate::QuestTurnedIn { id: 983 },
    };
    let payload = assert_adjacent_with_payload("Lifetime::Background", &background, "Background");
    assert_payload_fields(
        "Lifetime::Background",
        &payload,
        &["channels", "band", "terminate_on"],
    );
    assert_eq!(
        payload["channels"],
        json!(["MOVEMENT"]),
        "§7.2 pins the channel spellings SCREAMING_SNAKE inside `Lifetime::Background`"
    );
    // A predicate nested inside another enum's payload must keep its own tagging.
    adjacent_shape(&payload["terminate_on"], "QuestTurnedIn").unwrap_or_else(|why| {
        panic!("Lifetime::Background.terminate_on lost its tagging when nested: {why}\n  contract: {C4}")
    });
}

#[test]
fn completion_source_every_variant_is_adjacently_tagged() {
    assert_adjacent_unit(
        "CompletionSource::OwnPredicate",
        &CompletionSource::OwnPredicate,
        "OwnPredicate",
    );
    let payload = assert_adjacent_with_payload(
        "CompletionSource::LinkedTo",
        &CompletionSource::LinkedTo(7),
        "LinkedTo",
    );
    assert_eq!(
        payload,
        json!(7),
        "§7.3.3 task 6: `\"completion\": {{\"type\": \"LinkedTo\", \"payload\": 7}}` — a newtype \
         variant carries the value BARE under `payload`, not wrapped in an object"
    );
}

/// §5.1.2: the tri-state policy. `Defer` is the only variant with data.
#[test]
fn unknown_policy_every_variant_is_adjacently_tagged() {
    assert_adjacent_unit("UnknownPolicy::Block", &UnknownPolicy::Block, "Block");
    assert_adjacent_unit(
        "UnknownPolicy::TreatFalse",
        &UnknownPolicy::TreatFalse,
        "TreatFalse",
    );
    assert_adjacent_unit(
        "UnknownPolicy::TreatTrue",
        &UnknownPolicy::TreatTrue,
        "TreatTrue",
    );

    let payload = assert_adjacent_with_payload(
        "UnknownPolicy::Defer",
        &UnknownPolicy::Defer { budget_ticks: 60 },
        "Defer",
    );
    assert_payload_fields("UnknownPolicy::Defer", &payload, &["budget_ticks"]);
    assert_eq!(payload["budget_ticks"], json!(60));
}

/// §5.7 (C7): a destination and a baked circuit are not interchangeable, so the discriminant has
/// to survive the wire.
#[test]
fn route_kind_every_variant_is_adjacently_tagged() {
    assert_adjacent_unit("RouteKind::Destination", &RouteKind::Destination, "Destination");
    assert_adjacent_unit("RouteKind::Corridor", &RouteKind::Corridor, "Corridor");

    let payload = assert_adjacent_with_payload(
        "RouteKind::Circuit",
        &RouteKind::Circuit { close: true },
        "Circuit",
    );
    assert_payload_fields("RouteKind::Circuit", &payload, &["close"]);
    assert_eq!(payload["close"], json!(true));
}

#[test]
fn gossip_policy_every_variant_is_adjacently_tagged() {
    assert_adjacent_unit("GossipPolicy::None", &GossipPolicy::None, "None");
    assert_adjacent_unit(
        "GossipPolicy::AutoAdvance",
        &GossipPolicy::AutoAdvance,
        "AutoAdvance",
    );

    let index =
        assert_adjacent_with_payload("GossipPolicy::Index", &GossipPolicy::Index(3), "Index");
    assert_eq!(
        index,
        json!(3),
        "`.gossip <npc>,<index>` — a newtype variant carries a BARE number under `payload`"
    );

    let option_id = assert_adjacent_with_payload(
        "GossipPolicy::OptionId",
        &GossipPolicy::OptionId(9),
        "OptionId",
    );
    assert_eq!(
        option_id,
        json!(9),
        "`.gossipoption <id>` — a newtype variant carries a BARE number under `payload`"
    );
}

/// §5.5 (C5): all seven delegate payloads are struct variants.
#[test]
fn delegate_payload_every_variant_is_adjacently_tagged() {
    for (payload, tag) in all_delegate_payloads() {
        assert_adjacent_with_payload(&format!("DelegatePayload::{tag}"), &payload, tag);
    }
}

/// §5.6 (C6). §7.3.3 shows `"stance": {"type": "Aggressive", …}` — an object, never the bare
/// string `"Aggressive"`.
#[test]
fn combat_stance_every_variant_is_adjacently_tagged() {
    for (stance, tag) in [
        (CombatStance::Avoid, "Avoid"),
        (CombatStance::Defensive, "Defensive"),
        (CombatStance::Objective, "Objective"),
        (CombatStance::Aggressive, "Aggressive"),
    ] {
        assert_adjacent_unit(&format!("CombatStance::{tag}"), &stance, tag);
    }
}

#[test]
fn group_expectation_every_variant_is_adjacently_tagged() {
    assert_adjacent_unit("GroupExpectation::Solo", &GroupExpectation::Solo, "Solo");
    assert_adjacent_unit(
        "GroupExpectation::Dungeon",
        &GroupExpectation::Dungeon,
        "Dungeon",
    );

    let payload = assert_adjacent_with_payload(
        "GroupExpectation::Party",
        &GroupExpectation::Party { size: 5 },
        "Party",
    );
    assert_payload_fields("GroupExpectation::Party", &payload, &["size"]);
}

/// §5.1.1: `Cmp` exists so the 15 new predicates do not each re-invent threshold parsing. It is
/// tagged like everything else, and it appears *nested inside* other payloads.
#[test]
fn cmp_every_variant_is_adjacently_tagged() {
    for (cmp, tag) in [
        (Cmp::Lt, "Lt"),
        (Cmp::Le, "Le"),
        (Cmp::Eq, "Eq"),
        (Cmp::Ge, "Ge"),
        (Cmp::Gt, "Gt"),
    ] {
        assert_adjacent_unit(&format!("Cmp::{tag}"), &cmp, tag);
    }
}

/// A tagged enum nested one level down must not lose its tagging: `Predicate::ItemCount.cmp`,
/// `Op::Travel.route.kind`, `Op::Delegate.payload`.
#[test]
fn nested_tagged_enums_keep_their_tagging() {
    let item_count = assert_adjacent_with_payload(
        "Predicate::ItemCount",
        &Predicate::ItemCount {
            id: 5385,
            cmp: Cmp::Ge,
            count: 6,
        },
        "ItemCount",
    );
    adjacent_shape(&item_count["cmp"], "Ge").unwrap_or_else(|why| {
        panic!("Predicate::ItemCount.cmp lost its tagging when nested: {why}\n  contract: {C4}")
    });

    let travel = assert_adjacent_with_payload(
        "Op::Travel",
        &Op::Travel { route: route() },
        "Travel",
    );
    adjacent_shape(&travel["route"]["kind"], "Circuit").unwrap_or_else(|why| {
        panic!("Op::Travel.route.kind lost its tagging when nested: {why}\n  contract: {C4}")
    });

    let delegate = assert_adjacent_with_payload(
        "Op::Delegate",
        &Op::Delegate {
            behavior: BehaviorId::Corpse,
            payload: DelegatePayload::Corpse {
                intent: CorpseIntent::DeliberateDeath,
                resurrect_at: Some(26),
            },
        },
        "Delegate",
    );
    assert_payload_fields("Op::Delegate", &delegate, &["behavior", "payload"]);
    adjacent_shape(&delegate["payload"], "Corpse").unwrap_or_else(|why| {
        panic!("Op::Delegate.payload lost its tagging when nested: {why}\n  contract: {C4}")
    });
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Unit variants: objects, never bare strings.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// The single most dangerous degradation: a unit variant collapsing to `"Aggressive"`. Lua
/// dispatches on `x.type`; a bare string has no `type`, so it would take the fall-through branch —
/// the exact mechanism of the shipped fail-open bug.
#[test]
fn unit_variants_are_tagged_objects_never_bare_strings() {
    let cases: Vec<(&str, Value, &str)> = vec![
        ("Lifetime::Exclusive", serde_json::to_value(Lifetime::Exclusive).unwrap(), "Exclusive"),
        (
            "CompletionSource::OwnPredicate",
            serde_json::to_value(CompletionSource::OwnPredicate).unwrap(),
            "OwnPredicate",
        ),
        ("UnknownPolicy::Block", serde_json::to_value(UnknownPolicy::Block).unwrap(), "Block"),
        (
            "UnknownPolicy::TreatFalse",
            serde_json::to_value(UnknownPolicy::TreatFalse).unwrap(),
            "TreatFalse",
        ),
        (
            "RouteKind::Destination",
            serde_json::to_value(RouteKind::Destination).unwrap(),
            "Destination",
        ),
        ("GossipPolicy::None", serde_json::to_value(GossipPolicy::None).unwrap(), "None"),
        (
            "CombatStance::Aggressive",
            serde_json::to_value(CombatStance::Aggressive).unwrap(),
            "Aggressive",
        ),
        ("GroupExpectation::Solo", serde_json::to_value(GroupExpectation::Solo).unwrap(), "Solo"),
        ("Cmp::Ge", serde_json::to_value(Cmp::Ge).unwrap(), "Ge"),
        ("Op::EnterVehicle", serde_json::to_value(Op::EnterVehicle).unwrap(), "EnterVehicle"),
    ];

    for (label, json, tag) in cases {
        assert!(
            json.is_object(),
            "{label} serialized as {json}, not as a tagged object. §7.3.3 prints \
             `{{\"type\": {tag:?}, …}}`; a bare string cannot be dispatched on in Lua.\n  \
             contract: {C4}"
        );
        let payload = adjacent_shape(&json, tag)
            .unwrap_or_else(|why| panic!("{label}: {why}\n  serialized: {json}\n  contract: {C4}"));
        assert!(payload.is_null(), "{label}: unit variant carries data {payload}");
    }
}

/// Backward compatibility, not fidelity to the current text. §7.3.3 and the fixture *used* to write
/// unit variants as `{"type": "Exclusive", "payload": null}`; the audit (§9 item 23) ruled serde's
/// canonical form authoritative and rewrote both, so neither carries that spelling today.
///
/// The loader must still accept it. §7.2 requires only `["type"]`, so the explicit `null` remains
/// legal, and any artifact compiled against the pre-audit text carries it. Refusing it here would
/// silently turn every such artifact into a load failure.
#[test]
fn unit_variants_accept_the_adr_7_3_3_explicit_null_payload() {
    let lifetime: Lifetime =
        serde_json::from_value(json!({ "type": "Exclusive", "payload": null })).unwrap();
    assert_eq!(lifetime, Lifetime::Exclusive);

    let stance: CombatStance =
        serde_json::from_value(json!({ "type": "Aggressive", "payload": null })).unwrap();
    assert_eq!(stance, CombatStance::Aggressive);

    let policy: UnknownPolicy =
        serde_json::from_value(json!({ "type": "Block", "payload": null })).unwrap();
    assert_eq!(policy, UnknownPolicy::Block);

    // …and the payload-less spelling §7.3.3 also uses (`"completion": {"type": "OwnPredicate"}`).
    let completion: CompletionSource =
        serde_json::from_value(json!({ "type": "OwnPredicate" })).unwrap();
    assert_eq!(completion, CompletionSource::OwnPredicate);

    // A bare string must NOT be accepted: that would re-open the degradation on the read side.
    assert!(
        serde_json::from_value::<CombatStance>(json!("Aggressive")).is_err(),
        "a bare string must not deserialize into an adjacently tagged enum.\n  contract: {C4}"
    );
}

// A test named `adr_7_3_3_unit_variants_emit_an_explicit_null_payload` used to live here, ignored,
// asserting the *emitted* form was `{"type": "X", "payload": null}` because that is what ADR 07
// §7.3.3 printed. It was the exact mirror of `worked_example_reserialises_to_a_byte_equal_json_value`
// in `kernel_fixture.rs`, and only one of the two could ever pass.
//
// The audit resolved the disagreement in favour of **serde's canonical form** (§9 item 23): the
// content key is omitted for a unit variant, so the model emits `{"type": "Exclusive"}`, and §7.3.3
// plus the fixture were rewritten to match. The alternative — eleven hand-written `Serialize` impls
// to reproduce a printed `null` that §7.2's `$defs` never required — was rejected. So this test now
// asserts a spelling that is wrong, and it is deleted rather than un-ignored.
//
// Nothing is uncovered by the deletion. `unit_variants_omit_payload_and_accept_null` (in
// `kernel/mod.rs`) pins the emitted form, and `unit_variants_accept_the_adr_7_3_3_explicit_null_payload`
// directly above pins the *load* side — the guarantee that artifacts written against the pre-audit
// text still parse. That one must survive.

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Payload shapes: arrays, nested objects, bare scalars.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// §7.3.3 task 4 proves `And`'s payload is a JSON ARRAY, not an object. `Predicate::And(vec![])`
/// must still emit `[]` rather than collapsing to a unit variant.
#[test]
fn container_predicates_carry_a_json_array_payload() {
    let empty = assert_adjacent_with_payload("Predicate::And([])", &Predicate::And(vec![]), "And");
    assert_eq!(
        empty,
        json!([]),
        "an empty `And` must still emit an ARRAY payload; collapsing it to a unit variant would \
         make an empty conjunction indistinguishable from a missing one (§7.3.3 task 4)"
    );

    let filled = assert_adjacent_with_payload(
        "Predicate::And",
        &Predicate::And(vec![
            Predicate::QuestObjective {
                id: 2118,
                index: 1,
                need: 1,
            },
            Predicate::QuestObjective {
                id: 983,
                index: 1,
                need: 6,
            },
        ]),
        "And",
    );
    assert_eq!(
        filled,
        json!([
            { "type": "QuestObjective", "payload": { "id": 2118, "index": 1, "need": 1 } },
            { "type": "QuestObjective", "payload": { "id": 983,  "index": 1, "need": 6 } }
        ]),
        "§7.3.3 task 4 (the folded multi-`#requires` step) pins this exact shape"
    );

    let or = assert_adjacent_with_payload(
        "Predicate::Or",
        &Predicate::Or(vec![Predicate::QuestInLog { id: 983 }]),
        "Or",
    );
    assert!(
        or.is_array(),
        "`Or`'s payload must be an ARRAY (`.isOnQuest` takes any-of lists), got {or}"
    );
}

/// `Not` carries a single nested predicate OBJECT, not an array and not a bare id.
#[test]
fn not_predicate_carries_a_nested_predicate_object() {
    let payload = assert_adjacent_with_payload(
        "Predicate::Not",
        &Predicate::Not(Box::new(Predicate::QuestTurnedIn { id: 983 })),
        "Not",
    );
    assert_eq!(
        payload,
        json!({ "type": "QuestTurnedIn", "payload": { "id": 983 } }),
        "`Not`'s payload is one nested, still-adjacently-tagged predicate (§5.1.1)"
    );
}

/// §7.1's exact field names for every struct-variant `Predicate` payload.
///
/// `area` is the load-bearing one: §5.1.1 writes `area_id` for `InArea` and `HearthBoundTo`, §7.1
/// and the §7.3.3 fixture both write `area`, and §7.1 is authoritative.
#[test]
fn predicate_struct_variant_payload_field_names_match_adr_7_1() {
    let expected: Vec<(&str, &[&str])> = vec![
        ("QuestComplete", &["id"]),
        ("QuestObjective", &["id", "index", "need"]),
        ("AtLocation", &["point", "radius"]),
        ("LevelAtLeast", &["level"]),
        ("AuraPresent", &["spell", "on"]),
        ("Flag", &["key"]),
        ("QuestInLog", &["id"]),
        ("QuestTurnedIn", &["id"]),
        ("QuestAvailable", &["id"]),
        ("ItemCount", &["id", "cmp", "count"]),
        ("MoneyCmp", &["cmp", "copper"]),
        ("SkillCmp", &["line", "cmp", "value"]),
        ("ReputationCmp", &["faction", "standing", "cmp", "value"]),
        ("XpAtLeast", &["level", "xp_offset"]),
        ("CooldownCmp", &["kind", "id", "cmp", "secs"]),
        ("InArea", &["area", "kind"]),
        ("HearthBoundTo", &["area"]),
        ("ItemStatCmp", &["slot", "stat", "cmp", "value"]),
        ("InGroup", &["cmp", "size"]),
        ("SpellKnown", &["spell"]),
        ("LevelAtMost", &["level"]),
    ];

    for predicate in all_predicates() {
        let tag = predicate_tag(&predicate);
        let Some((_, fields)) = expected.iter().find(|(name, _)| *name == tag) else {
            // And / Or / Not carry containers, not structs; covered by their own tests.
            continue;
        };
        let payload = assert_adjacent_with_payload(&format!("Predicate::{tag}"), &predicate, tag);
        assert_payload_fields(&format!("Predicate::{tag}"), &payload, fields);
    }

    assert_eq!(
        expected.len(),
        21,
        "24 predicate variants minus the 3 container variants (And/Or/Not) — if this number moved, \
         a struct variant was added or removed without updating {FIELDS}"
    );
}

/// D3, isolated so its failure is unmissable: the field is `area`, NOT `area_id`.
#[test]
fn in_area_and_hearth_bound_to_spell_the_field_area_not_area_id() {
    let in_area = assert_adjacent_with_payload(
        "Predicate::InArea",
        &Predicate::InArea {
            area: 442,
            kind: AreaKind::SubArea,
        },
        "InArea",
    );
    assert_eq!(
        in_area,
        json!({ "area": 442, "kind": "SubArea" }),
        "ADR 07 §5.1.1 writes `area_id`, but §7.1 and the §7.3.3 fixture (task 6, `\"area\": 442`) \
         both write `area`, and §7.1 is authoritative"
    );
    assert!(
        in_area.get("area_id").is_none(),
        "`area_id` is §5.1.1's spelling and must not reach the wire; §7.1 wins"
    );

    let hearth = assert_adjacent_with_payload(
        "Predicate::HearthBoundTo",
        &Predicate::HearthBoundTo { area: 148 },
        "HearthBoundTo",
    );
    assert_eq!(
        hearth,
        json!({ "area": 148 }),
        "same §5.1.1-vs-§7.1 disagreement as `InArea`; §7.1 wins"
    );
}

/// §7.1's exact field names for every struct-variant `Op` payload.
#[test]
fn op_struct_variant_payload_field_names_match_adr_7_1() {
    let expected: Vec<(&str, &[&str])> = vec![
        ("Travel", &["route"]),
        ("Accept", &["quest", "repeatable"]),
        (
            "TurnIn",
            &["quest", "any_of", "reward_choice", "optional", "repeatable"],
        ),
        ("Abandon", &["quests"]),
        ("UntrackQuest", &["quest"]),
        ("Interact", &["npc", "gossip"]),
        ("UseItem", &["item"]),
        ("Cast", &["spell"]),
        ("DestroyItem", &["item"]),
        ("Equip", &["slot", "item"]),
        ("Wait", &["secs", "label"]),
        ("Delegate", &["behavior", "payload"]),
    ];

    for op in all_ops() {
        let tag = op_tag(&op);
        if tag == "EnterVehicle" {
            continue; // unit variant, no payload
        }
        let (_, fields) = expected
            .iter()
            .find(|(name, _)| *name == tag)
            .unwrap_or_else(|| panic!("Op::{tag} has no expected field list — update {FIELDS}"));
        let payload = assert_adjacent_with_payload(&format!("Op::{tag}"), &op, tag);
        assert_payload_fields(&format!("Op::{tag}"), &payload, fields);
    }

    assert_eq!(
        expected.len(),
        12,
        "13 op variants minus the 1 unit variant (EnterVehicle) — if this number moved, update \
         {FIELDS}"
    );
}

/// §7.1 / §5.5 field names for the seven delegate payloads.
#[test]
fn delegate_payload_field_names_match_adr_7_1() {
    let expected: Vec<(&str, &[&str])> = vec![
        ("Vendor", &["npc", "mode", "items", "gold_floor"]),
        ("Trainer", &["npc", "spell"]),
        ("FlightPath", &["npc", "mode", "dest_node"]),
        ("Hearth", &["mode", "npc"]),
        ("Bank", &["npc", "mode", "items"]),
        ("Stable", &["npc", "mode"]),
        ("Corpse", &["intent", "resurrect_at"]),
    ];

    for (payload, tag) in all_delegate_payloads() {
        let (_, fields) = expected
            .iter()
            .find(|(name, _)| *name == tag)
            .unwrap_or_else(|| panic!("DelegatePayload::{tag} unexpected — update {FIELDS}"));
        let label = format!("DelegatePayload::{tag}");
        let body = assert_adjacent_with_payload(&label, &payload, tag);
        assert_payload_fields(&label, &body, fields);
    }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// The converse rule: scalar vocabulary is a bare string.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// §7.3.3 contains `"class": "Hunter"`, `"race": "NightElf"`, `"expansion": "Tbc"`,
/// `"mode": "SpeedRoute"`, `"mode": "Ground"`, `"kind": "SubArea"`. Adjacently tagging any of these
/// would break the worked example.
#[test]
fn scalar_vocabulary_enums_are_bare_json_strings() {
    assert_bare_string("Class::Hunter", &Class::Hunter, "Hunter");
    assert_bare_string("Race::NightElf", &Race::NightElf, "NightElf");
    assert_bare_string("Faction::Alliance", &Faction::Alliance, "Alliance");
    assert_bare_string("Expansion::Tbc", &Expansion::Tbc, "Tbc");
    assert_bare_string("Allegiance::Aldor", &Allegiance::Aldor, "Aldor");
    assert_bare_string("ProfileMode::SpeedRoute", &ProfileMode::SpeedRoute, "SpeedRoute");
    assert_bare_string("TravelMode::Ground", &TravelMode::Ground, "Ground");
    assert_bare_string("TravelMode::Any", &TravelMode::Any, "Any");
    assert_bare_string("AreaKind::SubArea", &AreaKind::SubArea, "SubArea");
    assert_bare_string("AreaKind::Zone", &AreaKind::Zone, "Zone");
    assert_bare_string("UnitRef::Player", &UnitRef::Player, "Player");
    assert_bare_string("SkillLine::FirstAid", &SkillLine::FirstAid, "FirstAid");
    assert_bare_string("Standing::Honored", &Standing::Honored, "Honored");
    assert_bare_string("CooldownKind::Item", &CooldownKind::Item, "Item");
    assert_bare_string("ItemStat::Quality", &ItemStat::Quality, "Quality");
    assert_bare_string(
        "ItemStat::DamagePerSecond",
        &ItemStat::DamagePerSecond,
        "DamagePerSecond",
    );

    // The delegate mode vocabularies — bare strings too (§7.1 annotates none of them).
    assert_bare_string("BehaviorId::FlightPath", &BehaviorId::FlightPath, "FlightPath");
    assert_bare_string("VendorMode::Buy", &VendorMode::Buy, "Buy");
    assert_bare_string("FlightMode::Discover", &FlightMode::Discover, "Discover");
    assert_bare_string("HearthMode::Bind", &HearthMode::Bind, "Bind");
    assert_bare_string("BankMode::Withdraw", &BankMode::Withdraw, "Withdraw");
    assert_bare_string("StableMode::Visit", &StableMode::Visit, "Visit");
    assert_bare_string(
        "CorpseIntent::DeliberateDeath",
        &CorpseIntent::DeliberateDeath,
        "DeliberateDeath",
    );
}

/// §7.2 enumerates the channels SCREAMING_SNAKE, and §7.3.3 carries `"channels": ["MOVEMENT"]`.
#[test]
fn channel_variants_are_screaming_snake_case_strings() {
    let cases = [
        (Channel::Movement, "MOVEMENT"),
        (Channel::Facing, "FACING"),
        (Channel::Casting, "CASTING"),
        (Channel::Targeting, "TARGETING"),
        (Channel::Interaction, "INTERACTION"),
        (Channel::Items, "ITEMS"),
        (Channel::Camera, "CAMERA"),
    ];
    for (channel, spelling) in cases {
        assert_bare_string(&format!("Channel::{spelling}"), &channel, spelling);
    }

    assert_eq!(
        serde_json::to_value(cases.map(|(channel, _)| channel).to_vec()).unwrap(),
        json!([
            "MOVEMENT",
            "FACING",
            "CASTING",
            "TARGETING",
            "INTERACTION",
            "ITEMS",
            "CAMERA"
        ]),
        "ADR 07 §7.2 pins this exact enum list for `Lifetime::Background.channels`"
    );
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Anti-drift: the emitted tag vocabulary must equal ADR 07 §7.2's enum lists.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// The 24 predicate tag strings §7.2 enumerates, verbatim from the ADR (lines 1448-1452).
const ADR_7_2_PREDICATE_TAGS: [&str; 24] = [
    "And",
    "Or",
    "Not",
    "QuestComplete",
    "QuestObjective",
    "AtLocation",
    "LevelAtLeast",
    "AuraPresent",
    "Flag",
    "QuestInLog",
    "QuestTurnedIn",
    "QuestAvailable",
    "ItemCount",
    "MoneyCmp",
    "SkillCmp",
    "ReputationCmp",
    "XpAtLeast",
    "CooldownCmp",
    "InArea",
    "HearthBoundTo",
    "ItemStatCmp",
    "InGroup",
    "SpellKnown",
    "LevelAtMost",
];

/// The 13 op tag strings §7.2 enumerates, verbatim from the ADR (lines 1461-1462).
const ADR_7_2_OP_TAGS: [&str; 13] = [
    "Travel",
    "Accept",
    "TurnIn",
    "Abandon",
    "UntrackQuest",
    "Interact",
    "UseItem",
    "Cast",
    "DestroyItem",
    "Equip",
    "EnterVehicle",
    "Wait",
    "Delegate",
];

/// Compare an emitted tag census against an ADR list and report both directions of drift.
#[track_caller]
fn assert_census(what: &str, mut emitted: Vec<String>, adr: &[&str]) {
    emitted.sort();
    emitted.dedup();

    let mut expected: Vec<String> = adr.iter().map(|s| (*s).to_owned()).collect();
    expected.sort();

    let added: Vec<&String> = emitted.iter().filter(|t| !expected.contains(t)).collect();
    let missing: Vec<&String> = expected.iter().filter(|t| !emitted.contains(t)).collect();

    assert!(
        added.is_empty() && missing.is_empty(),
        "{what} tag vocabulary has drifted from ADR 07 §7.2 — UPDATE ADR 07 §7.2.\n  \
         emitted but not in §7.2: {added:?}\n  in §7.2 but never emitted: {missing:?}\n  \
         §7.2's `\"type\": {{\"enum\": […]}}` list is the loader's allow-list; a tag missing from \
         it fails closed at load (C4, §5.4)."
    );
    assert_eq!(
        emitted.len(),
        expected.len(),
        "{what} emits {} distinct tags but ADR 07 §7.2 enumerates {} — UPDATE ADR 07 §7.2",
        emitted.len(),
        expected.len()
    );
}

/// Serialize one instance of every `Predicate` variant and assert the resulting set of `type`
/// strings is exactly §7.2's 24-name list. A 25th variant fails here (and, earlier, fails to
/// compile in [`predicate_tag`]).
#[test]
fn predicate_tag_census_matches_adr_7_2() {
    let predicates = all_predicates();
    assert_eq!(
        predicates.len(),
        24,
        "`all_predicates()` must hold one instance of every variant — UPDATE ADR 07 §7.2 if the \
         variant count really changed"
    );

    let mut emitted = Vec::new();
    for predicate in &predicates {
        let json = serde_json::to_value(predicate).unwrap();
        let tag = json["type"]
            .as_str()
            .unwrap_or_else(|| panic!("no string `type` in {json}"))
            .to_owned();
        assert_eq!(
            tag,
            predicate_tag(predicate),
            "the serde variant name drifted from the Rust variant name — a `#[serde(rename)]` \
             would silently break Lua's `cond.type` dispatch (C4, §5.4)"
        );
        emitted.push(tag);
    }

    assert_census("Predicate", emitted, &ADR_7_2_PREDICATE_TAGS);
}

/// The same anti-drift guard for `Op`'s 13 names.
#[test]
fn op_tag_census_matches_adr_7_2() {
    let ops = all_ops();
    assert_eq!(
        ops.len(),
        13,
        "`all_ops()` must hold one instance of every variant — UPDATE ADR 07 §7.2 if the variant \
         count really changed"
    );

    let mut emitted = Vec::new();
    for op in &ops {
        let json = serde_json::to_value(op).unwrap();
        let tag = json["type"]
            .as_str()
            .unwrap_or_else(|| panic!("no string `type` in {json}"))
            .to_owned();
        assert_eq!(
            tag,
            op_tag(op),
            "the serde variant name drifted from the Rust variant name — a `#[serde(rename)]` \
             would silently break Lua's `op.type` dispatch (C4, §5.4)"
        );
        emitted.push(tag);
    }

    assert_census("Op", emitted, &ADR_7_2_OP_TAGS);
}

/// §5.1.1 removed `HasItem` in favour of `ItemCount`, of which `HasItem` is the `cmp: Ge` case.
///
/// A deleted variant cannot be named in compiling Rust, so this is asserted behaviourally: the old
/// wire form must be REFUSED, not silently ignored (C4, §5.4 — refuse, don't degrade). An artifact
/// compiled against the old vocabulary must fail at load rather than drop a condition.
#[test]
fn has_item_predicate_no_longer_exists_on_the_wire() {
    let error = serde_json::from_value::<Predicate>(json!({
        "type": "HasItem",
        "payload": { "id": 1, "count": 1 }
    }))
    .expect_err(
        "ADR 07 §5.1.1 replaced `HasItem` with `ItemCount`; the old tag must be REFUSED at load, \
         not accepted or silently dropped (C4, §5.4)",
    );
    let message = error.to_string();
    assert!(
        message.contains("HasItem") || message.contains("unknown variant"),
        "the refusal must name the offending tag so the failure is diagnosable, got: {message}"
    );

    assert!(
        !ADR_7_2_PREDICATE_TAGS.contains(&"HasItem"),
        "ADR 07 §7.2's enum list must not carry `HasItem` either (§5.1.1)"
    );

    // The replacement is the `Ge` case and it does load.
    let replacement: Predicate = serde_json::from_value(json!({
        "type": "ItemCount",
        "payload": { "id": 1, "cmp": { "type": "Ge" }, "count": 1 }
    }))
    .expect("`ItemCount { cmp: Ge }` is the sanctioned replacement for `HasItem` (§5.1.1)");
    assert_eq!(
        replacement,
        Predicate::ItemCount {
            id: 1,
            cmp: Cmp::Ge,
            count: 1
        }
    );
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Load-side refusal — the direction the shipped defect actually hurt.
//
// Everything above this line is serialize-side: it proves the model WRITES the adjacent form.
// That is only half the contract. ADR 07 §7.2:1581 states the other half verbatim:
//
//     "$comment": "Adjacently tagged per C4. An externally-tagged variant fails closed at load."
//
// and it is the half that matters most, because `RuntimeCondition`'s damage happened at the
// CONSUMER: a wrongly-tagged condition arrived, the `cond.type` dispatch missed, and the
// evaluator fell through to `true`. A producer that writes correctly does not protect a loader
// that accepts anything. These tests feed the two wrong spellings to the deserializers and
// require them to ERROR rather than to accept, ignore, or partially absorb.
// ─────────────────────────────────────────────────────────────────────────────────────────────

const LOAD_CLOSED: &str = "ADR 07 §7.2:1581 — \"Adjacently tagged per C4. An externally-tagged \
                           variant fails closed at load.\" §5.4:729 states the contract as \
                           refuse-don't-degrade: an artifact the model does not understand must \
                           be REFUSED, never silently reinterpreted";

/// Assert a wire form is REFUSED by the deserializer.
macro_rules! assert_load_refuses {
    ($ty:ty, $json:expr, $why:expr) => {{
        let candidate: Value = $json;
        let outcome = serde_json::from_value::<$ty>(candidate.clone());
        assert!(
            outcome.is_err(),
            "`{}` ACCEPTED a wire form it must refuse: {candidate}\n  why this matters: {}\n  \
             contract: {LOAD_CLOSED}",
            stringify!($ty),
            $why
        );
    }};
}

/// The exact historical defect, asserted on the read side, for the two enums that carry the
/// artifact's semantics: `Predicate` (gating) and `Op` (execution).
///
/// External tagging is `{"Variant": payload}`; internal tagging is
/// `{"type": "Variant", ...fields hoisted}`. Both round-trip perfectly within Rust, which is
/// precisely why `RuntimeCondition` shipped broken — so both must be rejected here explicitly.
#[test]
fn externally_and_internally_tagged_predicates_and_ops_fail_closed_at_load() {
    // ── external: the shipped defect's exact shape ──
    assert_load_refuses!(
        Predicate,
        json!({ "QuestInLog": { "id": 983 } }),
        "this is byte-for-byte the shape `RuntimeCondition` emitted. Accepting it would let a \
         stale or hand-edited artifact re-enter the fail-open path (§5.4:733)"
    );
    assert_load_refuses!(
        Op,
        json!({ "UseItem": { "item": 7586 } }),
        "an externally-tagged op would leave `op.type` nil in Lua and the op would be skipped \
         silently instead of executed"
    );

    // ── internal: fields hoisted alongside the tag, no `payload` envelope ──
    assert_load_refuses!(
        Predicate,
        json!({ "type": "QuestInLog", "id": 983 }),
        "internal tagging puts the payload fields as siblings of `type`; Lua reads \
         `cond.payload.id` and would get nil, so the predicate would evaluate against a missing id"
    );
    assert_load_refuses!(
        Op,
        json!({ "type": "UseItem", "item": 7586 }),
        "same hazard on the execution side: `op.payload` would be nil"
    );

    // ── the sanctioned form still loads, so the assertions above are not vacuous ──
    let predicate: Predicate =
        serde_json::from_value(json!({ "type": "QuestInLog", "payload": { "id": 983 } }))
            .expect("the adjacent form is the contract and must load");
    assert_eq!(predicate, Predicate::QuestInLog { id: 983 });

    let op: Op = serde_json::from_value(json!({ "type": "UseItem", "payload": { "item": 7586 } }))
        .expect("the adjacent form is the contract and must load");
    assert_eq!(op, Op::UseItem { item: 7586 });
}

/// The external form must be refused for **every** adjacently tagged enum, not just the two
/// above. With adjacent tagging serde rejects on the unexpected KEY before it ever looks at the
/// content, so a `null` payload is sufficient to exercise the refusal.
#[test]
fn every_adjacently_tagged_enum_refuses_the_external_form_at_load() {
    let why = "one unguarded enum is enough to reintroduce the defect on the path it guards";

    assert_load_refuses!(Lifetime, json!({ "Exclusive": null }), why);
    assert_load_refuses!(CompletionSource, json!({ "LinkedTo": 7 }), why);
    assert_load_refuses!(UnknownPolicy, json!({ "Defer": { "budget_ticks": 60 } }), why);
    assert_load_refuses!(Op, json!({ "EnterVehicle": null }), why);
    assert_load_refuses!(RouteKind, json!({ "Circuit": { "close": true } }), why);
    assert_load_refuses!(GossipPolicy, json!({ "Index": 3 }), why);
    assert_load_refuses!(DelegatePayload, json!({ "Hearth": null }), why);
    assert_load_refuses!(CombatStance, json!({ "Aggressive": null }), why);
    assert_load_refuses!(GroupExpectation, json!({ "Solo": null }), why);
    assert_load_refuses!(Cmp, json!({ "Ge": null }), why);
    assert_load_refuses!(Predicate, json!({ "LevelAtMost": { "level": 60 } }), why);
}

/// The converse of `scalar_vocabularies_are_bare_string_enums`: a bare string must never
/// deserialize into an adjacently tagged enum.
///
/// `unit_variants_accept_the_adr_7_3_3_explicit_null_payload` pins this for `CombatStance` alone.
/// A bare string has no `type` key, so in Lua it cannot be dispatched at all — if any of these
/// eleven accepted one, the tagged and scalar vocabularies would have quietly merged.
#[test]
fn no_adjacently_tagged_enum_accepts_a_bare_string_at_load() {
    let why = "a bare string carries no `type` key, so Lua's `x.type` dispatch has nothing to \
               read; accepting it merges the tagged and scalar vocabularies";

    assert_load_refuses!(Lifetime, json!("Exclusive"), why);
    assert_load_refuses!(CompletionSource, json!("OwnPredicate"), why);
    assert_load_refuses!(UnknownPolicy, json!("Block"), why);
    assert_load_refuses!(Op, json!("EnterVehicle"), why);
    assert_load_refuses!(RouteKind, json!("Destination"), why);
    assert_load_refuses!(GossipPolicy, json!("None"), why);
    assert_load_refuses!(DelegatePayload, json!("Hearth"), why);
    assert_load_refuses!(CombatStance, json!("Aggressive"), why);
    assert_load_refuses!(GroupExpectation, json!("Solo"), why);
    assert_load_refuses!(Cmp, json!("Ge"), why);
    assert_load_refuses!(Predicate, json!("QuestInLog"), why);
}
