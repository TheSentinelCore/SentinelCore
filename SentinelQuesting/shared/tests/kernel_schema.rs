//! Agreement between the **Rust structs** and **ADR 07 §7.2's hand-written JSON Schema excerpt**,
//! with the structs as the single source of truth.
//!
//! ADR: `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md`, §7.2 "JSON Schema (excerpt — the
//! load-bearing shapes)" — the single fenced JSON block that opens with
//! `"title": "Sentinel Runtime Profile"` and closes just before `## 7.3 Worked example`.
//!
//! # Why this file exists
//!
//! §7.2 is *hand-written prose*, and the model in `shared/src/kernel/` is *code*. Two
//! hand-maintained descriptions of one wire format drift — this repository already carries the
//! proof in the Lua-side `_kernel_table()` duplication, and in the externally-tagged
//! `RuntimeCondition` that made every non-unit condition fail open. So this file never re-types the
//! schema by hand: it **generates** the schema from the structs with `schemars` and pins §7.2's
//! claims against the generated output. The ADR's own lists are hardcoded here as the *expected*
//! constants, each paired with an `*_ANCHOR`: the verbatim §7.2 text a failure must send the reader
//! to search for.
//!
//! The load-bearing test is the anti-drift guard: add a `Predicate` variant and
//! [`predicate_tag_set_matches_adr_7_2_predicate_type_enum`] fails with the file to edit and the
//! exact string to search for inside it.
//!
//! # What this file deliberately does not do
//!
//! It does **not** formally validate the §7.3.3 fixture against the generated schema. The
//! `jsonschema` validator crate is not in the offline registry cache and adding a dependency is out
//! of scope. The stricter check is in force anyway: every kernel struct is
//! `#[serde(deny_unknown_fields)]`, so `kernel_fixture.rs`'s deserialization rejects more than
//! §7.2's excerpt would — §7.2 sets no `additionalProperties` on its objects at all.

use std::collections::BTreeSet;
use std::sync::OnceLock;

use schemars::schema_for;
use serde_json::Value;

use sentinel_models::kernel::RuntimeProfile;

/// Where a drift failure must send the reader.
const ADR: &str = "sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md";

// ── The ADR's own lists, transcribed verbatim with a greppable anchor each ───────────────────────
//
// These are the *expected* side of every comparison below. They are the only hand-copied thing in
// this file; everything they are compared against is generated from the structs.
//
// Each list carries an `*_ANCHOR`: a verbatim slice of §7.2's JSON block that a reader can paste
// into ripgrep to land on the exact array a failure is about. Line numbers were used here until
// they rotted four separate times in one day — an edit anywhere above §7.2 retargets every one of
// them onto a different line that still exists, so nothing fails and no one notices. An anchor
// either still matches the ADR or visibly does not.

/// Search anchor for §7.2's root `required` array.
const ROOT_REQUIRED_ANCHOR: &str = r#""required": ["magic","schema_version","schema_hash""#;

/// §7.2's root `required` array (search: [`ROOT_REQUIRED_ANCHOR`]).
const ROOT_REQUIRED: &[&str] = &[
    "magic",
    "schema_version",
    "schema_hash",
    "tags_used",
    "integrity",
    "archetype",
    "meta",
    "defaults",
    "waypoint_pool",
    "tasks",
];

/// Search anchor for §7.2's `integrity.required` array.
const INTEGRITY_REQUIRED_ANCHOR: &str =
    r#""required": ["content_hash","world_source","world_build"]"#;

/// §7.2's `integrity.required` array (search: [`INTEGRITY_REQUIRED_ANCHOR`]).
const INTEGRITY_REQUIRED: &[&str] = &["content_hash", "world_source", "world_build"];

/// Search anchor for §7.2's `waypoint_pool.items.required` array.
const POINT_REQUIRED_ANCHOR: &str = r#""required": ["map_id","x","y"]"#;

/// §7.2's `waypoint_pool.items.required` (search: [`POINT_REQUIRED_ANCHOR`]). `z` is nullable and
/// therefore absent.
const POINT_REQUIRED: &[&str] = &["map_id", "x", "y"];

/// Search anchor for §7.2's `$defs.Task.required` array.
const TASK_REQUIRED_ANCHOR: &str = r#""required": ["id","deps","blocking","lifetime""#;

/// §7.2's `$defs.Task.required` (search: [`TASK_REQUIRED_ANCHOR`]).
const TASK_REQUIRED: &[&str] = &[
    "id",
    "deps",
    "blocking",
    "lifetime",
    "completion",
    "unknown_policy",
    "ops",
    "source",
];

/// Search anchor for §7.2's `$defs.Task.properties.source.required` array.
const SOURCE_REQUIRED_ANCHOR: &str = r#""required": ["file","line_start","line_end"]"#;

/// §7.2's `$defs.Task.properties.source.required` (search: [`SOURCE_REQUIRED_ANCHOR`]).
const SOURCE_REQUIRED: &[&str] = &["file", "line_start", "line_end"];

/// Search anchor for §7.2's `$defs.Lifetime.properties.type.enum`.
const LIFETIME_TAGS_ANCHOR: &str = r#""enum": ["Exclusive","Background"]"#;

/// §7.2's `$defs.Lifetime.properties.type.enum` (search: [`LIFETIME_TAGS_ANCHOR`]).
const LIFETIME_TAGS: &[&str] = &["Exclusive", "Background"];

/// Search anchor for §7.2's `$defs.CompletionSource.properties.type.enum`.
const COMPLETION_SOURCE_TAGS_ANCHOR: &str = r#""enum": ["OwnPredicate","LinkedTo"]"#;

/// §7.2's `$defs.CompletionSource.properties.type.enum` (search:
/// [`COMPLETION_SOURCE_TAGS_ANCHOR`]).
const COMPLETION_SOURCE_TAGS: &[&str] = &["OwnPredicate", "LinkedTo"];

/// Search anchor for §7.2's `$defs.UnknownPolicy.properties.type.enum`.
const UNKNOWN_POLICY_TAGS_ANCHOR: &str = r#""enum": ["Block","Defer","TreatFalse","TreatTrue"]"#;

/// §7.2's `$defs.UnknownPolicy.properties.type.enum` (search: [`UNKNOWN_POLICY_TAGS_ANCHOR`]).
const UNKNOWN_POLICY_TAGS: &[&str] = &["Block", "Defer", "TreatFalse", "TreatTrue"];

/// Search anchor for §7.2's `$defs.Predicate.properties.type.enum`.
const PREDICATE_TAGS_ANCHOR: &str = r#""enum": ["And","Or","Not","QuestComplete""#;

/// §7.2's `$defs.Predicate.properties.type.enum` (search: [`PREDICATE_TAGS_ANCHOR`]). 24 variants.
///
/// There is deliberately **no `HasItem`**: §5.1.1 replaced it with `ItemCount { cmp: Ge }`.
const PREDICATE_TAGS: &[&str] = &[
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

/// Search anchor for §7.2's `$defs.Op.properties.type.enum`.
const OP_TAGS_ANCHOR: &str = r#""enum": ["Travel","Accept","TurnIn","Abandon""#;

/// §7.2's `$defs.Op.properties.type.enum` (search: [`OP_TAGS_ANCHOR`]). 13 variants.
const OP_TAGS: &[&str] = &[
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

/// Search anchor for §7.2's `Lifetime.payload.channels.items.enum`.
const CHANNELS_ANCHOR: &str = r#""MOVEMENT","FACING","CASTING","TARGETING""#;

/// §7.2's channel vocabulary, SCREAMING_SNAKE (search: [`CHANNELS_ANCHOR`]).
const CHANNELS: &[&str] = &[
    "MOVEMENT",
    "FACING",
    "CASTING",
    "TARGETING",
    "INTERACTION",
    "ITEMS",
    "CAMERA",
];

/// Every enum §7.1 annotates with `#[serde(tag = "type", content = "payload")]` (C4, §5.4).
const ADJACENTLY_TAGGED: &[&str] = &[
    "Lifetime",
    "CompletionSource",
    "UnknownPolicy",
    "Op",
    "RouteKind",
    "GossipPolicy",
    "DelegatePayload",
    "CombatStance",
    "GroupExpectation",
    "Cmp",
    "Predicate",
];

/// Of [`ADJACENTLY_TAGGED`], the ones that have at least one payload-carrying variant and must
/// therefore expose a `payload` property somewhere in their generated schema.
///
/// `Cmp` and `CombatStance` are the complement: every one of their variants is a unit variant, so
/// there is no payload to schematise. Adding a payload-carrying variant to either — or removing the
/// last one from any enum listed here — moves it across this boundary and trips
/// [`adjacently_tagged_enums_expose_payload_exactly_where_variants_carry_one`].
const TAGGED_WITH_PAYLOAD: &[&str] = &[
    "Lifetime",
    "CompletionSource",
    "UnknownPolicy",
    "Op",
    "RouteKind",
    "GossipPolicy",
    "DelegatePayload",
    "GroupExpectation",
    "Predicate",
];

/// Scalar vocabulary that must stay a **bare string** on the wire (§7.3.3: `"expansion": "Tbc"`,
/// `"mode": "Ground"`, `"kind": "SubArea"`, `"channels": ["MOVEMENT"]`).
///
/// `Class` / `Race` / `Faction` are reused from `crate::authoring` and described as `String` rather
/// than as named definitions, so they are checked separately in
/// [`scalar_vocabularies_are_bare_string_enums`].
/// `ProfileMode` is deliberately **absent**: its `Dungeon` variant carries which dungeon (§5.2), so
/// it is a mixed enum and only its two unit variants are bare strings. Its shape is pinned by
/// [`profile_mode_is_a_bare_string_except_for_the_dungeon_it_names`] instead. `DungeonId` — the
/// payload — is scalar vocabulary and is checked here like the rest.
const SCALAR_VOCABULARY: &[&str] = &[
    "Expansion",
    "Allegiance",
    "DungeonId",
    "Channel",
    "TravelMode",
    "AreaKind",
    "UnitRef",
    "SkillLine",
    "Standing",
    "CooldownKind",
    "ItemStat",
    "BehaviorId",
    "VendorMode",
    "FlightMode",
    "HearthMode",
    "BankMode",
    "StableMode",
    "CorpseIntent",
];

// ── Generation: one `schema_for!`, shared by every test ──────────────────────────────────────────

/// The schema generated from the structs. `schema_for!` runs once for the whole binary.
fn schema() -> &'static Value {
    static SCHEMA: OnceLock<Value> = OnceLock::new();
    SCHEMA.get_or_init(|| {
        serde_json::to_value(schema_for!(RuntimeProfile))
            .expect("the generated RootSchema must serialize to JSON")
    })
}

/// A named entry of the generated `definitions` map.
///
/// schemars 0.8 emits draft-07, so the map is `definitions`, not `$defs` as §7.2 writes it. That is
/// a dialect difference, not a contract difference: §7.2 declares draft 2020-12 and this file pins
/// the *shapes* it describes, not the dialect it is written in.
fn def(name: &str) -> &'static Value {
    schema()
        .get("definitions")
        .and_then(|defs| defs.get(name))
        .unwrap_or_else(|| {
            panic!(
                "generated schema has no definition {name:?} — ADR 07 §7.2 refers to it; \
                 available: {:?}",
                definition_names()
            )
        })
}

fn definition_names() -> Vec<String> {
    schema()["definitions"]
        .as_object()
        .map(|map| map.keys().cloned().collect())
        .unwrap_or_default()
}

/// The alternative branches of a schema node: `oneOf`, `anyOf`, or the node itself.
///
/// schemars picks the keyword by construction — adjacently tagged enums come out as `oneOf`,
/// `Option<T>` comes out as `anyOf` — so nothing here may assume one shape.
fn branches(node: &Value) -> Vec<&Value> {
    for keyword in ["oneOf", "anyOf", "allOf"] {
        if let Some(list) = node.get(keyword).and_then(Value::as_array) {
            return list.iter().collect();
        }
    }
    vec![node]
}

/// The `type` keyword of a schema node, normalised to a set.
///
/// JSON Schema allows both a single name and an array of names, and schemars uses both: a plain
/// field gets `"type": "number"`, an `Option<f32>` gets `"type": ["number", "null"]`.
fn type_names(node: &Value) -> BTreeSet<String> {
    match node.get("type") {
        Some(Value::String(name)) => BTreeSet::from([name.clone()]),
        Some(Value::Array(names)) => names
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect(),
        _ => BTreeSet::new(),
    }
}

fn required_set(node: &Value) -> BTreeSet<String> {
    node.get("required")
        .and_then(Value::as_array)
        .map(|list| {
            list.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn expected_set(names: &[&str]) -> BTreeSet<String> {
    names.iter().map(|name| (*name).to_owned()).collect()
}

/// The discriminator values of an adjacently tagged enum, read out of the generated schema.
///
/// Each branch is an object schema whose `properties.type` is a single-valued string enum. Anything
/// else means the enum stopped being adjacently tagged, which is exactly the C4 regression this
/// file guards, so it panics loudly rather than returning an empty set.
fn tagged_variant_names(enum_name: &str) -> BTreeSet<String> {
    tagged_variant_names_of(enum_name, def(enum_name))
}

/// [`tagged_variant_names`] against an arbitrary node, so the extractor can be exercised on a
/// throwaway type in [`drift_guard_reads_variants_out_of_the_derive`].
fn tagged_variant_names_of(enum_name: &str, node: &Value) -> BTreeSet<String> {
    branches(node)
        .into_iter()
        .map(|branch| {
            let tag = branch
                .get("properties")
                .and_then(|props| props.get("type"))
                .and_then(|tag| tag.get("enum"))
                .and_then(Value::as_array)
                .and_then(|values| values.first())
                .and_then(Value::as_str)
                .unwrap_or_else(|| {
                    panic!(
                        "{enum_name} branch is not an adjacently tagged object — C4 (ADR 07 §5.4, \
                         {ADR}) requires #[serde(tag = \"type\", content = \"payload\")] on it. \
                         Branch was: {branch}"
                    )
                });
            tag.to_owned()
        })
        .collect()
}

/// The values of a bare-string enum, whether schemars emitted one flat `enum` or a `oneOf` of
/// single-valued enums (it does the latter when the variants carry doc comments).
fn string_enum_values(node: &Value) -> BTreeSet<String> {
    let mut values = BTreeSet::new();
    for branch in branches(node) {
        let list = branch
            .get("enum")
            .and_then(Value::as_array)
            .unwrap_or_else(|| panic!("expected a string enum branch, got: {branch}"));
        for value in list {
            let text = value
                .as_str()
                .unwrap_or_else(|| panic!("expected a string enum value, got: {value}"));
            values.insert(text.to_owned());
        }
    }
    values
}

/// Compares a generated set against the ADR's transcribed list and renders the drift as an
/// instruction: *which* names, and *where they are written down*.
///
/// `adr_anchor` is a verbatim slice of §7.2's JSON block — the reader greps for it rather than
/// jumping to a line number. A line number silently retargets on the next ADR edit; a quoted
/// slice either still matches or fails to match, which is a question the reader can answer.
///
/// Returns `None` when the two agree.
fn drift(
    what: &str,
    adr_anchor: &str,
    generated: &BTreeSet<String>,
    adr: &BTreeSet<String>,
) -> Option<String> {
    if generated == adr {
        return None;
    }
    let mut lines = Vec::new();
    for added in generated.difference(adr) {
        lines.push(format!(
            "ADR 07 §7.2 {what} is now out of date — add {added} to {ADR} §7.2 \
             (search: {adr_anchor})"
        ));
    }
    for removed in adr.difference(generated) {
        lines.push(format!(
            "ADR 07 §7.2 {what} is now out of date — remove {removed} from {ADR} §7.2 \
             (search: {adr_anchor}) (the Rust model no longer has it)"
        ));
    }
    lines.push(format!(
        "generated from the structs: {generated:?}\n\
         written in {ADR} §7.2 (search: {adr_anchor}): {adr:?}"
    ));
    Some(lines.join("\n"))
}

/// Panics with [`drift`]'s message when the generated set and the ADR's list disagree.
fn assert_tag_set(what: &str, adr_anchor: &str, generated: BTreeSet<String>, adr: &[&str]) {
    if let Some(message) = drift(what, adr_anchor, &generated, &expected_set(adr)) {
        panic!("{message}");
    }
}

// ── Root shape (§7.2, from `"title": "Sentinel Runtime Profile"` to `"$defs": {`) ─────────────────

/// §7.2's root `required` array (search: `"required": ["magic","schema_version","schema_hash"`).
/// Exact set, both directions: a field the ADR requires and the struct dropped is as much a break
/// as a field the struct gained and the ADR never mentions.
#[test]
fn root_required_set_is_exactly_adr_7_2_root_required() {
    assert_tag_set(
        "RuntimeProfile root `required`",
        ROOT_REQUIRED_ANCHOR,
        required_set(schema()),
        ROOT_REQUIRED,
    );
}

/// C4 (§5.4) at the schema level: the root refuses unknown properties, mirroring
/// `#[serde(deny_unknown_fields)]`. §7.2's excerpt does not spell this out — the structs are
/// stricter than the ADR here, which is the safe direction.
#[test]
fn root_refuses_unknown_properties() {
    assert_eq!(
        schema().get("additionalProperties"),
        Some(&Value::Bool(false)),
        "C4 (ADR 07 §5.4, {ADR}) requires the artifact to refuse rather than degrade; \
         RuntimeProfile must stay #[serde(deny_unknown_fields)]"
    );
}

/// §7.2's three root string fields (search: `"magic":`, `"schema_hash":`, `"content_hash":`).
/// `magic` is `{ "const": "SNTL" }` and the two digests are
/// `{ "type": "string", "pattern": "^[0-9a-f]{64}$" }` — i.e. all three are **strings** on the
/// wire, even though Rust holds them as `[u8; 4]` and `[u8; 32]`.
///
/// What is asserted here is the type only. `schemars` cannot derive the `const` or the `pattern`
/// from `#[schemars(with = "String")]`, so neither is present in the generated schema and this test
/// does not claim otherwise. Both are enforced by the deserializers in
/// `shared/src/kernel/ids.rs` (`magic::deserialize` accepts only `"SNTL"`; `hex32::deserialize`
/// accepts only 64 lowercase hex characters) and are covered by the wire-shape tests in
/// `shared/src/kernel/mod.rs` and by `kernel_roundtrip.rs`.
#[test]
fn magic_and_digests_are_schematised_as_strings() {
    let root_properties = &schema()["properties"];
    assert_eq!(
        root_properties["magic"].get("type"),
        Some(&Value::String("string".to_owned())),
        "ADR 07 §7.2 ({ADR}, search: `\"magic\":`) pins `magic` to the string const \"SNTL\"; the \
         generated schema must not describe it as an array of integers, which is what a plain \
         [u8; 4] would produce"
    );
    assert_eq!(
        root_properties["schema_hash"].get("type"),
        Some(&Value::String("string".to_owned())),
        "ADR 07 §7.2 ({ADR}, search: `\"schema_hash\":`) pins `schema_hash` to a 64-character \
         lowercase hex string"
    );
    assert_eq!(
        def("ContentIntegrity")["properties"]["content_hash"].get("type"),
        Some(&Value::String("string".to_owned())),
        "ADR 07 §7.2 ({ADR}, search: `\"content_hash\":`) pins `integrity.content_hash` to a \
         64-character lowercase hex string"
    );

    // Recorded honestly rather than claimed: the `^[0-9a-f]{64}$` pattern is *not* in the
    // generated schema, because `#[schemars(with = "String")]` carries no pattern.
    for (label, node) in [
        ("schema_hash", &root_properties["schema_hash"]),
        (
            "integrity.content_hash",
            &def("ContentIntegrity")["properties"]["content_hash"],
        ),
    ] {
        assert!(
            node.get("pattern").is_none(),
            "{label} now carries a schema-level pattern. That is an improvement, but this test and \
             the R1 report both record its absence — update both."
        );
    }
}

/// §7.2's two remaining root scalars (search: `"schema_version":`, `"tags_used":`).
#[test]
fn root_scalar_types_match_adr_7_2_root_properties() {
    let root_properties = &schema()["properties"];
    assert_eq!(
        root_properties["schema_version"].get("type"),
        Some(&Value::String("integer".to_owned())),
        "ADR 07 §7.2 ({ADR}, search: `\"schema_version\":`) pins `schema_version` to an integer"
    );
    assert_eq!(
        root_properties["tags_used"]["items"].get("type"),
        Some(&Value::String("string".to_owned())),
        "ADR 07 §7.2 ({ADR}, search: `\"tags_used\":`) pins `tags_used` to an array of strings — \
         the C4 tag census"
    );
}

/// §7.2's `integrity.required` (search: [`INTEGRITY_REQUIRED_ANCHOR`]).
#[test]
fn integrity_required_set_matches_adr_7_2_integrity_required() {
    assert_tag_set(
        "ContentIntegrity `required`",
        INTEGRITY_REQUIRED_ANCHOR,
        required_set(def("ContentIntegrity")),
        INTEGRITY_REQUIRED,
    );
}

/// §7.2's `waypoint_pool.items` (search: [`POINT_REQUIRED_ANCHOR`]): a pooled waypoint requires
/// `map_id`, `x` and `y`; `z` is nullable because the corpus never supplies it (§5.7).
#[test]
fn waypoint_pool_point_shape_matches_adr_7_2_waypoint_pool_items() {
    let point = def("Point");
    assert_tag_set(
        "Point `required`",
        POINT_REQUIRED_ANCHOR,
        required_set(point),
        POINT_REQUIRED,
    );

    let z_types = branches(&point["properties"]["z"])
        .into_iter()
        .flat_map(type_names)
        .collect::<BTreeSet<_>>();
    assert!(
        z_types.contains("null"),
        "ADR 07 §7.2 ({ADR}, search: `\"z\": {{ \"type\": [\"number\",\"null\"] }}`) types `z` as \
         [\"number\",\"null\"]; the generated schema offers {z_types:?}. Point::z must stay \
         Option<f32> — the compiler leaves it None and lets the engine ground-snap (§5.7)."
    );
}

// ── Task (§7.2's `$defs.Task`, search: `"Task": {`) ──────────────────────────────────────────────

/// §7.2's `$defs.Task.required` (search: [`TASK_REQUIRED_ANCHOR`]). The ADR's list is a *minimum*:
/// it excerpts the load-bearing fields rather than enumerating the struct, so this asserts
/// coverage, and names the surplus so a reader can see what the excerpt omits.
#[test]
fn task_required_set_covers_adr_7_2_task_required() {
    let generated = required_set(def("Task"));
    let adr = expected_set(TASK_REQUIRED);
    let missing = adr.difference(&generated).collect::<Vec<_>>();
    assert!(
        missing.is_empty(),
        "ADR 07 §7.2 ({ADR}, search: {TASK_REQUIRED_ANCHOR}) requires {missing:?} on every Task, \
         but the generated schema does not. Either the field became Option/defaulted in \
         shared/src/kernel/task.rs, or the ADR list needs editing."
    );

    // Not a failure — recorded so the excerpt's incompleteness is visible rather than surprising.
    let surplus = generated.difference(&adr).collect::<Vec<_>>();
    assert_eq!(
        surplus,
        vec!["loot_filter", "serves_quests", "suppress"],
        "the set of Task fields required by the structs but omitted from ADR 07 §7.2's Task \
         `required` excerpt ({ADR}, search: {TASK_REQUIRED_ANCHOR}) has changed. §7.2 is an \
         excerpt, so surplus is legal — but it must stay a deliberate, listed set, not drift \
         silently."
    );
}

/// §7.2's three Task predicate slots are `oneOf [Predicate, null]`
/// (search: `"oneOf": [{ "$ref": "#/$defs/Predicate" }` — three hits, one per slot).
///
/// schemars emits `anyOf` where §7.2 writes `oneOf`. For a two-branch `[T, null]` union the two are
/// equivalent — a value cannot be both a Predicate object and `null` — so the contract asserted
/// here is the one that matters: **a `null` branch exists**, i.e. the field is `Option<Predicate>`
/// and an absent gate is legal. Task 0 of §7.3.3 has no `applies_when`.
#[test]
fn task_predicate_slots_are_nullable_per_adr_7_2_task_properties() {
    let task_properties = &def("Task")["properties"];
    for slot in ["applies_when", "complete_when", "abort_when"] {
        let node = &task_properties[slot];
        let branch_shapes = branches(node);

        let has_null = branch_shapes
            .iter()
            .any(|branch| type_names(branch).contains("null"));
        assert!(
            has_null,
            "ADR 07 §7.2 ({ADR}, search: `\"oneOf\": [{{ \"$ref\": \"#/$defs/Predicate\" }}` — \
             three hits, one per slot; this is the `{slot}` one) types Task.{slot} as \
             oneOf [Predicate, null]; the generated schema has no null branch, so the field \
             stopped being Option<Predicate>. Node was: {node}"
        );

        let has_predicate = branch_shapes.iter().any(|branch| {
            branch.get("$ref") == Some(&Value::String("#/definitions/Predicate".to_owned()))
        });
        assert!(
            has_predicate,
            "ADR 07 §7.2 ({ADR}, search: `\"oneOf\": [{{ \"$ref\": \"#/$defs/Predicate\" }}` — \
             three hits, one per slot; this is the `{slot}` one) types Task.{slot} as \
             oneOf [Predicate, null], but the non-null branch no longer references Predicate. \
             C1 (§5.1) allows exactly one condition language. Node was: {node}"
        );
    }
}

/// §7.2's `$defs.Task.properties.source` (search: [`SOURCE_REQUIRED_ANCHOR`]).
#[test]
fn source_span_shape_matches_adr_7_2_task_source_required() {
    assert_tag_set(
        "SourceSpan `required`",
        SOURCE_REQUIRED_ANCHOR,
        required_set(def("SourceSpan")),
        SOURCE_REQUIRED,
    );
}

// ── The anti-drift guard (§7.2's `$defs`, search: `"$defs": {`) ──────────────────────────────────
//
// Each of the five tests below reads the discriminator values out of the *generated* schema and
// compares them to the list the ADR literally writes. This is the reason the file exists.
//
// Does the guard actually bite? Trace a 25th Predicate variant, say `Predicate::HasMount { id }`,
// added to shared/src/kernel/predicate.rs and nowhere else:
//
//   1. `#[derive(JsonSchema)]` regenerates `definitions.Predicate.oneOf` with 25 branches, because
//      schemars derives from the enum, not from any list maintained by hand.
//   2. `tagged_variant_names("Predicate")` returns 25 names — it walks the branches, it does not
//      count against a constant.
//   3. `generated.difference(adr)` yields exactly `{"HasMount"}`.
//   4. `drift` renders: `ADR 07 §7.2 Predicate `type` enum is now out of date — add HasMount to
//      sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md §7.2 (search: "enum": ["And","Or","Not",
//      "QuestComplete")`.
//   5. `assert_tag_set` panics with that message and the test fails.
//
// Removing a variant takes the mirrored path through `adr.difference(generated)`. Renaming one
// trips both halves and prints both instructions. `drift_guard_bites_on_a_new_variant` exercises
// steps 3-4 directly against a synthetic 25th name, so the mechanism is verified rather than
// merely argued.

/// §7.2's Predicate tag list (search: [`PREDICATE_TAGS_ANCHOR`]). **The** guard: 24 predicate tags,
/// no more, no fewer, no `HasItem`.
#[test]
fn predicate_tag_set_matches_adr_7_2_predicate_type_enum() {
    let generated = tagged_variant_names("Predicate");
    assert!(
        !generated.contains("HasItem"),
        "§5.1.1 ({ADR}) removed `HasItem` in favour of ItemCount {{ cmp: Ge }} so there is one way \
         to say one thing; it is back in shared/src/kernel/predicate.rs"
    );
    assert_tag_set(
        "Predicate `type` enum",
        PREDICATE_TAGS_ANCHOR,
        generated,
        PREDICATE_TAGS,
    );
}

/// §7.2's Op tag list (search: [`OP_TAGS_ANCHOR`]). 13 op tags.
#[test]
fn op_tag_set_matches_adr_7_2_op_type_enum() {
    assert_tag_set(
        "Op `type` enum",
        OP_TAGS_ANCHOR,
        tagged_variant_names("Op"),
        OP_TAGS,
    );
}

/// §7.2's Lifetime tag list (search: [`LIFETIME_TAGS_ANCHOR`]).
#[test]
fn lifetime_tag_set_matches_adr_7_2_lifetime_type_enum() {
    assert_tag_set(
        "Lifetime `type` enum",
        LIFETIME_TAGS_ANCHOR,
        tagged_variant_names("Lifetime"),
        LIFETIME_TAGS,
    );
}

/// §7.2's CompletionSource tag list (search: [`COMPLETION_SOURCE_TAGS_ANCHOR`]).
#[test]
fn completion_source_tag_set_matches_adr_7_2_completion_source_type_enum() {
    assert_tag_set(
        "CompletionSource `type` enum",
        COMPLETION_SOURCE_TAGS_ANCHOR,
        tagged_variant_names("CompletionSource"),
        COMPLETION_SOURCE_TAGS,
    );
}

/// §7.2's UnknownPolicy tag list (search: [`UNKNOWN_POLICY_TAGS_ANCHOR`]).
#[test]
fn unknown_policy_tag_set_matches_adr_7_2_unknown_policy_type_enum() {
    assert_tag_set(
        "UnknownPolicy `type` enum",
        UNKNOWN_POLICY_TAGS_ANCHOR,
        tagged_variant_names("UnknownPolicy"),
        UNKNOWN_POLICY_TAGS,
    );
}

/// Closes the one link the reasoning above states but does not execute: that the extractor reads
/// variant names **out of the `JsonSchema` derive**, so a variant added to the Rust enum shows up
/// without anyone touching this file.
///
/// A throwaway enum is used rather than a temporary edit to `shared/src/kernel/predicate.rs`,
/// because it proves the same thing without mutating the model. Together with
/// [`drift_guard_bites_on_a_new_variant`] the whole chain is executed: derive → extractor → drift
/// message → panic.
#[test]
fn drift_guard_reads_variants_out_of_the_derive() {
    /// Shaped exactly like `Predicate`: adjacently tagged, one unit variant, one payload-carrying
    /// variant. Not part of the model — it exists only to exercise the extractor.
    #[derive(serde::Serialize, schemars::JsonSchema)]
    #[serde(tag = "type", content = "payload", deny_unknown_fields)]
    // Never constructed on purpose: only its derived schema is read.
    #[allow(dead_code)]
    enum GuardProbe {
        Unit,
        Carrying { field: u8 },
        AddedLater(u32),
    }

    let probe = serde_json::to_value(schema_for!(GuardProbe)).expect("probe schema serializes");
    assert_eq!(
        tagged_variant_names_of("GuardProbe", &probe),
        expected_set(&["Unit", "Carrying", "AddedLater"]),
        "the extractor must enumerate whatever the derive produced — if it misses a variant, the \
         Predicate and Op guards would silently accept a new variant"
    );
}

/// Verifies the guard mechanism itself: given a generated set carrying a 25th name the ADR does not
/// list, [`drift`] must name the variant, the ADR file and the exact text to search for in it.
#[test]
fn drift_guard_bites_on_a_new_variant() {
    let mut generated = tagged_variant_names("Predicate");
    generated.insert("HasMount".to_owned());

    let message = drift(
        "Predicate `type` enum",
        PREDICATE_TAGS_ANCHOR,
        &generated,
        &expected_set(PREDICATE_TAGS),
    )
    .expect("a 25th variant must be reported as drift, not accepted");

    assert!(
        message.contains(
            "ADR 07 §7.2 Predicate `type` enum is now out of date — add HasMount to \
             sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md §7.2 (search: \
             \"enum\": [\"And\",\"Or\",\"Not\",\"QuestComplete\")"
        ),
        "the drift message must tell the next engineer what to add and where. Got:\n{message}"
    );

    // And the mirrored direction: a variant the ADR lists but the model dropped.
    let mut shrunk = tagged_variant_names("Predicate");
    shrunk.remove("LevelAtMost");
    let message = drift(
        "Predicate `type` enum",
        PREDICATE_TAGS_ANCHOR,
        &shrunk,
        &expected_set(PREDICATE_TAGS),
    )
    .expect("a removed variant must be reported as drift");
    assert!(
        message.contains(
            "remove LevelAtMost from sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md §7.2 \
             (search: \"enum\": [\"And\",\"Or\",\"Not\",\"QuestComplete\")"
        ),
        "the drift message must also catch removals. Got:\n{message}"
    );

    // Sanity: agreement is silence.
    assert!(
        drift(
            "Predicate `type` enum",
            PREDICATE_TAGS_ANCHOR,
            &tagged_variant_names("Predicate"),
            &expected_set(PREDICATE_TAGS),
        )
        .is_none(),
        "the guard must not fire when the model and the ADR agree"
    );
}

/// §7.2's ControlBroker channels, SCREAMING_SNAKE (search: [`CHANNELS_ANCHOR`]).
/// `"channels": ["MOVEMENT"]` in §7.3.3 depends on the spelling.
#[test]
fn channel_enum_matches_adr_7_2_lifetime_payload_channels() {
    assert_tag_set(
        "Lifetime.payload.channels enum",
        CHANNELS_ANCHOR,
        string_enum_values(def("Channel")),
        CHANNELS,
    );
}

// ── Tagging discipline at the schema level (C4, §5.4) ────────────────────────────────────────────

/// The schema-level counterpart of the wire-shape tests in `shared/src/kernel/mod.rs`.
///
/// Every adjacently tagged enum must generate **object** branches carrying a `type` discriminator.
/// A bare string enum here would mean the payload had been dropped; an externally tagged enum would
/// generate `{"VariantName": {...}}` — one property per variant, no `type` at all — which is the
/// exact shape that made `RuntimeCondition` fail open in Lua.
#[test]
fn adjacently_tagged_enums_are_tagged_objects_not_bare_strings() {
    for enum_name in ADJACENTLY_TAGGED {
        for branch in branches(def(enum_name)) {
            assert_eq!(
                branch.get("type"),
                Some(&Value::String("object".to_owned())),
                "C4 (ADR 07 §5.4, {ADR}): {enum_name} must serialize as a tagged object. This \
                 branch is not an object, so the enum is a bare string enum or externally tagged. \
                 Branch: {branch}"
            );
            assert!(
                branch.get("enum").is_none(),
                "C4 (ADR 07 §5.4, {ADR}): {enum_name} branch is a bare string enum. Branch: {branch}"
            );
            let tag = branch
                .get("properties")
                .and_then(|props| props.get("type"))
                .unwrap_or_else(|| {
                    panic!(
                        "C4 (ADR 07 §5.4, {ADR}): {enum_name} branch has no `type` discriminator \
                         property — #[serde(tag = \"type\", content = \"payload\")] is missing. \
                         Branch: {branch}"
                    )
                });
            assert_eq!(
                tag.get("enum").and_then(Value::as_array).map(Vec::len),
                Some(1),
                "C4 (ADR 07 §5.4, {ADR}): {enum_name}'s `type` must pin exactly one variant name \
                 per branch. Got: {tag}"
            );
            assert!(
                required_set(branch).contains("type"),
                "C4 (ADR 07 §5.4, {ADR}): {enum_name}'s `type` discriminator must be required — \
                 §7.2 writes `\"required\": [\"type\"]` on every one of these. Branch: {branch}"
            );
        }
    }
}

/// The `content = "payload"` half of C4, and the boundary between the payload-carrying tagged enums
/// and the two all-unit ones.
///
/// Unit variants legitimately carry no `payload` — serde omits the content field for them, which is
/// why §7.2 marks only `type` as required. So the assertion is per enum, not per branch: an enum
/// with payload-carrying variants must expose `payload` on exactly those branches, and `Cmp` /
/// `CombatStance`, whose variants are all unit variants, must expose none.
#[test]
fn adjacently_tagged_enums_expose_payload_exactly_where_variants_carry_one() {
    let expected_with_payload = expected_set(TAGGED_WITH_PAYLOAD);
    let mut actual_with_payload = BTreeSet::new();

    for enum_name in ADJACENTLY_TAGGED {
        for branch in branches(def(enum_name)) {
            let properties = branch
                .get("properties")
                .and_then(Value::as_object)
                .unwrap_or_else(|| panic!("{enum_name} branch has no properties: {branch}"));
            if properties.contains_key("payload") {
                actual_with_payload.insert((*enum_name).to_owned());
                assert!(
                    required_set(branch).contains("payload"),
                    "C4 (ADR 07 §5.4, {ADR}): {enum_name} declares a `payload` on this branch but \
                     does not require it, so a payload-carrying variant could load with its \
                     payload missing. Branch: {branch}"
                );
            }
            let unexpected = properties
                .keys()
                .filter(|key| key.as_str() != "type" && key.as_str() != "payload")
                .collect::<Vec<_>>();
            assert!(
                unexpected.is_empty(),
                "C4 (ADR 07 §5.4, {ADR}): {enum_name} branch carries {unexpected:?} beside \
                 type/payload. Adjacent tagging admits exactly those two keys — anything else \
                 means the enum was re-tagged (internally tagged or untagged). Branch: {branch}"
            );
        }
    }

    assert_eq!(
        actual_with_payload, expected_with_payload,
        "the set of adjacently tagged enums that carry a payload has changed. Cmp and CombatStance \
         are all-unit-variant enums and must stay payload-free; every other enum in ADR 07 §7.1's \
         adjacently tagged list must expose `payload` somewhere. If this is intentional, update \
         TAGGED_WITH_PAYLOAD here and the enum's own §7.1 entry in {ADR}."
    );
}

/// The mirror rule: scalar vocabulary must stay **bare strings**, never adjacently tagged.
///
/// §7.3.3 contains `"class": "Hunter"`, `"expansion": "Tbc"`, `"mode": "Ground"`,
/// `"kind": "SubArea"`. Tagging any of these would turn the fixture — and every artifact already
/// compiled — into an unloadable file.
#[test]
fn scalar_vocabularies_are_bare_string_enums() {
    for name in SCALAR_VOCABULARY {
        for branch in branches(def(name)) {
            assert_eq!(
                branch.get("type"),
                Some(&Value::String("string".to_owned())),
                "{name} is scalar vocabulary: §7.3.3 ({ADR}) serializes it as a bare string. This \
                 branch is not a string, so it acquired a payload or a tag. Branch: {branch}"
            );
            assert!(
                branch.get("properties").is_none(),
                "{name} must not be adjacently tagged — §7.3.3 ({ADR}) shows it unwrapped. \
                 Branch: {branch}"
            );
        }
        assert!(
            !string_enum_values(def(name)).is_empty(),
            "{name} generated no enum values at all"
        );
    }

    // Class / Race / Faction are reused from `crate::authoring` and described with
    // `#[schemars(with = "String")]`, so they are inlined into Archetype rather than named in
    // `definitions`. The wire type is still a bare string, which is what §7.3.3 requires.
    let archetype_properties = &def("Archetype")["properties"];
    for field in ["class", "race", "faction"] {
        assert_eq!(
            archetype_properties[field].get("type"),
            Some(&Value::String("string".to_owned())),
            "§7.3.3 ({ADR}) has \"class\": \"Hunter\", \"race\": \"NightElf\", \
             \"faction\": \"Alliance\" — Archetype.{field} must stay a bare string on the wire"
        );
    }
}

/// `ProfileMode` is the one **mixed** vocabulary: two unit variants that stay bare strings, and a
/// `Dungeon` variant that names which dungeon (§5.2, C2).
///
/// The split matters in both directions. `"mode": "SpeedRoute"` is what §7.3.3 prints and what every
/// artifact compiled so far carries, so tagging the whole enum would make them unloadable; and a
/// `Dungeon` that could not say *which* dungeon would admit Maraudon's 105 steps into a Zul'Farrak
/// profile, which is the reason the payload exists.
#[test]
fn profile_mode_is_a_bare_string_except_for_the_dungeon_it_names() {
    let branches = branches(def("ProfileMode"));

    // schemars gives each documented variant its own branch, so the two unit variants are two
    // single-valued string branches rather than one two-valued one.
    let values: Vec<String> = branches
        .iter()
        .filter(|branch| branch.get("type") == Some(&Value::String("string".to_owned())))
        .flat_map(|branch| {
            branch["enum"]
                .as_array()
                .unwrap_or_else(|| panic!("a string branch must enumerate its values: {branch}"))
                .iter()
                .map(|value| value.as_str().unwrap_or_default().to_owned())
        })
        .collect();
    assert_eq!(
        values,
        vec!["SpeedRoute".to_owned(), "QuestGuide".to_owned()],
        "§7.3.3 ({ADR}) prints \"mode\": \"SpeedRoute\"; both unit variants must stay unwrapped. \
         Branches: {branches:?}"
    );

    let dungeon = branches
        .iter()
        .find(|branch| branch.get("properties").is_some())
        .unwrap_or_else(|| panic!("ProfileMode must have an object branch: {branches:?}"));
    let instance = &dungeon["properties"]["Dungeon"]["properties"]["instance"];
    assert!(
        !instance.is_null(),
        "the Dungeon branch must carry `instance` — a unit variant cannot tell `.dungeon Mara` \
         (105) from `.dungeon ZF` (150). Branch: {dungeon}"
    );

    // And the instance vocabulary is the closed, measured 19-argument set.
    assert_eq!(
        string_enum_values(def("DungeonId")).len(),
        19,
        "19 distinct `.dungeon` arguments after case folding: BF BFD Crypts DM Gnomer Mara MT \
         Ramparts RFD RFK SFK SM SP ST Stockades UB Ulda WC ZF"
    );
}

// ── A recorded R1 limitation ─────────────────────────────────────────────────────────────────────

/// §7.2 constrains the scheduler band (search: `"band": { "type": "integer", "minimum": 30`):
/// `{ "type": "integer", "minimum": 30, "maximum": 49 }` — the Goal band of §5.3.
///
/// **The generated schema does not carry that bound.** `Lifetime::Background::band` is a `u8`, and
/// `u8` cannot express 30..=49 in the type system, so `#[derive(JsonSchema)]` emits
/// `{"type": "integer", "format": "uint8", "minimum": 0.0}` — the bound of the *Rust* type, not of
/// the ADR's contract. This is a genuine R1 gap and it is recorded rather than papered over: adding
/// a range validator, or a newtype that enforces it, is new behaviour, and the band is assigned
/// during lowering, which is R2's work.
///
/// What is asserted: the field exists and is an integer. What is asserted *about the gap*: that the
/// bound is still absent — so whoever closes it is forced through this test and through the R1
/// limitation note that accompanies it.
#[test]
fn lifetime_band_range_is_not_expressed_by_the_generated_schema() {
    let background = branches(def("Lifetime"))
        .into_iter()
        .find(|branch| {
            branch["properties"]["type"]["enum"]
                .as_array()
                .and_then(|values| values.first())
                .and_then(Value::as_str)
                == Some("Background")
        })
        .expect(
            "Lifetime must still have a Background variant (ADR 07 §7.2, search: \
             `\"enum\": [\"Exclusive\",\"Background\"]`)",
        );

    let band = &background["properties"]["payload"]["properties"]["band"];
    assert_eq!(
        band.get("type"),
        Some(&Value::String("integer".to_owned())),
        "ADR 07 §7.2 ({ADR}, search: `\"band\": {{ \"type\": \"integer\"`) types \
         Lifetime.payload.band as an integer; got {band}"
    );
    assert!(
        required_set(&background["properties"]["payload"]).contains("band"),
        "a Background lifetime without a band has no scheduler priority (ADR 07 §5.3)"
    );

    assert_eq!(
        band.get("minimum"),
        Some(&Value::from(0.0)),
        "R1 limitation, recorded on purpose: `band` is a u8, so the generated schema carries the \
         u8 floor (0), not the `minimum: 30` of ADR 07 §7.2 (search: `\"minimum\": 30, \
         \"maximum\": 49`). If this now fails because someone \
         added a range-enforcing newtype, that is welcome — update this test and the R1 \
         limitation note that cites it."
    );
    assert!(
        band.get("maximum").is_none(),
        "R1 limitation, recorded on purpose: ADR 07 §7.2 ({ADR}, search: `\"maximum\": 49`) sets \
         `maximum: 49` and the \
         generated schema cannot express it from a u8. A `maximum` appearing here means the bound \
         landed — update this test and the R1 limitation note."
    );
}
