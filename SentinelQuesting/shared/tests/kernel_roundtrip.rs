//! Wire-contract tests for `sentinel_models::kernel`, the ADR 07 kernel artifact model.
//!
//! Authority: `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md`.
//!
//! What this file proves, and why each proof exists:
//!
//! * **Lossless round trip** (§7.1, §7.2). A maximally-populated [`RuntimeProfile`] survives
//!   `to_string -> from_str -> to_string` byte-identically *and* compares equal to the original.
//!   Byte equality catches representation and key-order drift; value equality catches a field that
//!   was silently dropped on the way through. Neither check subsumes the other.
//! * **`None` is a value, not an absence** (§7.3.2). Quest 983's ender is `gameobject` 17182, not a
//!   creature, so `interact_target: None` is the *correct* answer for a real turn-in. A model that
//!   elided it would make "no NPC" indistinguishable from "forgot the NPC".
//! * **Empty is a value, not an absence** (§7.3.3). Task 6 carries `channels: []` and task 4 carries
//!   `ops: []`; an empty vector must serialize as `[]`, never disappear.
//! * **Fail-closed** (C4, §5.4). The magic, the digests, and every struct in the artifact must
//!   *refuse* input they do not understand rather than degrade. The regression this guards is
//!   already in this repository's history: an externally tagged condition enum made every non-unit
//!   condition fall through to a fail-open `true` in Lua, and gating silently stopped gating.
//! * **Load-bearing edge cases** (§7.3.2, §8). `QuestObjective { need: 0 }` (quest 984 is an
//!   exploration objective with no `Req*` rows) and `deps: [2, 0]` (order is the compiler's to
//!   choose, not the model's to normalise).
//!
//! Scope note: this file is model-level only. It builds no artifact from the authoring model, hashes
//! nothing, and asserts nothing about waypoint deduplication — those are lowering concerns.

use std::collections::BTreeSet;
use std::fmt::Debug;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use sentinel_models::kernel::{
    hex32, magic, Allegiance, AreaKind, Archetype, BankMode, BehaviorId, Channel, Class, Cmp,
    CombatPolicy, CombatStance, CompletionSource, ContentIntegrity, CooldownKind, CorpseIntent,
    DelegatePayload, Expansion, Faction, FlightMode, GossipPolicy, GroupExpectation, GuideMeta,
    HearthMode, ItemStat, Lifetime, LootRule, NpcRef, Op, Point, Predicate, ProfileDefaults,
    ProfileMode, Race, ResumeCursor, Route, RouteKind, RuntimeProfile, SkillLine, SourceSpan,
    StableMode, Standing, Task, TravelMode, UnitRef, UnknownPolicy, VendorMode, MAGIC,
    SCHEMA_VERSION,
};

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Serialize, re-read, and re-serialize, asserting both the bytes and the value are unchanged.
///
/// `contract` names the ADR clause the caller is enforcing, so a failure tells the next engineer
/// *what* broke and *where it is written down*.
fn round_trip<T>(value: &T, contract: &str) -> T
where
    T: Serialize + DeserializeOwned + PartialEq + Debug,
{
    let first = serde_json::to_string(value)
        .unwrap_or_else(|err| panic!("{contract}: serialization failed: {err}"));
    let parsed: T = serde_json::from_str(&first).unwrap_or_else(|err| {
        panic!("{contract}: the model cannot re-read its own output: {err}\nemitted json: {first}")
    });
    let second = serde_json::to_string(&parsed)
        .unwrap_or_else(|err| panic!("{contract}: re-serialization failed: {err}"));

    assert_eq!(
        first, second,
        "{contract}: the wire form is not stable under a round trip. \
         Key order or a value representation changed between the first and the second write."
    );
    assert_eq!(
        &parsed, value,
        "{contract}: the value changed across the round trip. A field was dropped, defaulted, \
         or normalised on the way through serde."
    );
    parsed
}

/// Inject one unknown key into an otherwise valid object and assert the model refuses it.
///
/// This is C4 refuse-don't-degrade (ADR 07 §5.4): an artifact carrying a field this model does not
/// understand must fail to load, not load partially.
fn reject_extra_key<T>(valid: &T, key: &str, what: &str)
where
    T: Serialize + DeserializeOwned + Debug,
{
    let mut value = serde_json::to_value(valid)
        .unwrap_or_else(|err| panic!("{what}: could not serialize the valid baseline: {err}"));
    let rendered = value.to_string();
    let object = value.as_object_mut().unwrap_or_else(|| {
        panic!("{what}: expected a JSON object so an unknown key could be injected, got {rendered}")
    });
    object.insert(key.to_owned(), json!("prose"));

    match serde_json::from_value::<T>(value) {
        Ok(_) => panic!(
            "C4 fail-closed broken (ADR 07 §5.4): `{what}` accepted the unknown key `{key}`. \
             An artifact carrying a field this model does not understand must refuse to load; \
             `#[serde(deny_unknown_fields)]` is missing or was removed."
        ),
        Err(err) => assert!(
            err.to_string().contains("unknown field"),
            "C4 fail-closed (ADR 07 §5.4): `{what}` rejected the unknown key `{key}`, but not \
             because it was unknown — the error was: {err}"
        ),
    }
}

fn npc(entry: u32, name: &str, pos: Option<u32>) -> NpcRef {
    NpcRef {
        entry,
        expect_name: name.to_owned(),
        pos,
    }
}

fn point(x: f32, y: f32, z: Option<f32>) -> Point {
    Point {
        map_id: 1439,
        x,
        y,
        z,
    }
}

fn combat(stance: CombatStance, expect_group: GroupExpectation) -> CombatPolicy {
    CombatPolicy {
        stance,
        targets: vec![npc(2231, "Pygmy Tide Crawler", Some(0))],
        watch_units: vec![npc(2232, "Encrusted Tide Crawler", Some(1))],
        leash_yards: 40,
        allow_adds: true,
        expect_group,
    }
}

fn span(line_start: u32, line_end: u32) -> SourceSpan {
    SourceSpan {
        file: "A-11-23.lua".to_owned(),
        line_start,
        line_end,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Variant tag helpers
//
// Each of these is an EXHAUSTIVE match with no wildcard arm: adding a variant to the model breaks
// the compilation of this test file, which is the point. When that happens, add the arm here AND
// add the new tag to the corresponding `*_TAGS` list below, then exercise it in the corpus builders.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PREDICATE_TAGS: [&str; 24] = [
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

const OP_TAGS: [&str; 13] = [
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

const DELEGATE_TAGS: [&str; 7] = [
    "Vendor",
    "Trainer",
    "FlightPath",
    "Hearth",
    "Bank",
    "Stable",
    "Corpse",
];

const CMP_TAGS: [&str; 5] = ["Lt", "Le", "Eq", "Ge", "Gt"];
const LIFETIME_TAGS: [&str; 2] = ["Exclusive", "Background"];
const COMPLETION_TAGS: [&str; 2] = ["OwnPredicate", "LinkedTo"];
const UNKNOWN_POLICY_TAGS: [&str; 4] = ["Block", "Defer", "TreatFalse", "TreatTrue"];
const ROUTE_KIND_TAGS: [&str; 3] = ["Destination", "Corridor", "Circuit"];
const GOSSIP_TAGS: [&str; 4] = ["None", "AutoAdvance", "Index", "OptionId"];
const STANCE_TAGS: [&str; 4] = ["Avoid", "Defensive", "Objective", "Aggressive"];
const GROUP_TAGS: [&str; 3] = ["Solo", "Party", "Dungeon"];

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

fn delegate_tag(payload: &DelegatePayload) -> &'static str {
    match payload {
        DelegatePayload::Vendor { .. } => "Vendor",
        DelegatePayload::Trainer { .. } => "Trainer",
        DelegatePayload::FlightPath { .. } => "FlightPath",
        DelegatePayload::Hearth { .. } => "Hearth",
        DelegatePayload::Bank { .. } => "Bank",
        DelegatePayload::Stable { .. } => "Stable",
        DelegatePayload::Corpse { .. } => "Corpse",
    }
}

fn cmp_tag(cmp: &Cmp) -> &'static str {
    match cmp {
        Cmp::Lt => "Lt",
        Cmp::Le => "Le",
        Cmp::Eq => "Eq",
        Cmp::Ge => "Ge",
        Cmp::Gt => "Gt",
    }
}

fn lifetime_tag(lifetime: &Lifetime) -> &'static str {
    match lifetime {
        Lifetime::Exclusive => "Exclusive",
        Lifetime::Background { .. } => "Background",
    }
}

fn completion_tag(completion: &CompletionSource) -> &'static str {
    match completion {
        CompletionSource::OwnPredicate => "OwnPredicate",
        CompletionSource::LinkedTo(_) => "LinkedTo",
    }
}

fn unknown_policy_tag(policy: &UnknownPolicy) -> &'static str {
    match policy {
        UnknownPolicy::Block => "Block",
        UnknownPolicy::Defer { .. } => "Defer",
        UnknownPolicy::TreatFalse => "TreatFalse",
        UnknownPolicy::TreatTrue => "TreatTrue",
    }
}

fn route_kind_tag(kind: &RouteKind) -> &'static str {
    match kind {
        RouteKind::Destination => "Destination",
        RouteKind::Corridor => "Corridor",
        RouteKind::Circuit { .. } => "Circuit",
    }
}

fn gossip_tag(policy: &GossipPolicy) -> &'static str {
    match policy {
        GossipPolicy::None => "None",
        GossipPolicy::AutoAdvance => "AutoAdvance",
        GossipPolicy::Index(_) => "Index",
        GossipPolicy::OptionId(_) => "OptionId",
    }
}

fn stance_tag(stance: &CombatStance) -> &'static str {
    match stance {
        CombatStance::Avoid => "Avoid",
        CombatStance::Defensive => "Defensive",
        CombatStance::Objective => "Objective",
        CombatStance::Aggressive => "Aggressive",
    }
}

fn group_tag(expectation: &GroupExpectation) -> &'static str {
    match expectation {
        GroupExpectation::Solo => "Solo",
        GroupExpectation::Party { .. } => "Party",
        GroupExpectation::Dungeon => "Dungeon",
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Coverage walkers
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[derive(Default)]
struct Coverage {
    predicates: BTreeSet<&'static str>,
    ops: BTreeSet<&'static str>,
    delegates: BTreeSet<&'static str>,
    cmps: BTreeSet<&'static str>,
    lifetimes: BTreeSet<&'static str>,
    completions: BTreeSet<&'static str>,
    unknown_policies: BTreeSet<&'static str>,
    route_kinds: BTreeSet<&'static str>,
    gossips: BTreeSet<&'static str>,
    stances: BTreeSet<&'static str>,
    groups: BTreeSet<&'static str>,
}

impl Coverage {
    fn of(profile: &RuntimeProfile) -> Self {
        let mut coverage = Coverage::default();
        coverage.walk_unknown_policy(&profile.defaults.unknown_policy);
        coverage.walk_combat(&profile.defaults.combat);
        for task in &profile.tasks {
            coverage.walk_task(task);
        }
        coverage
    }

    fn walk_task(&mut self, task: &Task) {
        self.lifetimes.insert(lifetime_tag(&task.lifetime));
        if let Lifetime::Background { terminate_on, .. } = &task.lifetime {
            self.walk_predicate(terminate_on);
        }
        self.completions.insert(completion_tag(&task.completion));
        self.walk_unknown_policy(&task.unknown_policy);
        for predicate in [&task.applies_when, &task.complete_when, &task.abort_when]
            .into_iter()
            .flatten()
        {
            self.walk_predicate(predicate);
        }
        if let Some(policy) = &task.combat {
            self.walk_combat(policy);
        }
        for op in &task.ops {
            self.walk_op(op);
        }
    }

    fn walk_op(&mut self, op: &Op) {
        self.ops.insert(op_tag(op));
        match op {
            Op::Travel { route } => {
                self.route_kinds.insert(route_kind_tag(&route.kind));
            }
            Op::Interact { gossip, .. } => {
                self.gossips.insert(gossip_tag(gossip));
            }
            Op::Delegate { payload, .. } => {
                self.delegates.insert(delegate_tag(payload));
            }
            _ => {}
        }
    }

    fn walk_combat(&mut self, policy: &CombatPolicy) {
        self.stances.insert(stance_tag(&policy.stance));
        self.groups.insert(group_tag(&policy.expect_group));
    }

    fn walk_unknown_policy(&mut self, policy: &UnknownPolicy) {
        self.unknown_policies.insert(unknown_policy_tag(policy));
    }

    fn walk_predicate(&mut self, predicate: &Predicate) {
        self.predicates.insert(predicate_tag(predicate));
        match predicate {
            Predicate::And(children) | Predicate::Or(children) => {
                for child in children {
                    self.walk_predicate(child);
                }
            }
            Predicate::Not(inner) => self.walk_predicate(inner),
            Predicate::ItemCount { cmp, .. }
            | Predicate::MoneyCmp { cmp, .. }
            | Predicate::SkillCmp { cmp, .. }
            | Predicate::ReputationCmp { cmp, .. }
            | Predicate::CooldownCmp { cmp, .. }
            | Predicate::ItemStatCmp { cmp, .. }
            | Predicate::InGroup { cmp, .. } => {
                self.cmps.insert(cmp_tag(cmp));
            }
            _ => {}
        }
    }
}

fn assert_covers(found: &BTreeSet<&'static str>, expected: &[&'static str], what: &str) {
    let expected: BTreeSet<&'static str> = expected.iter().copied().collect();
    let missing: Vec<&&str> = expected.difference(found).collect();
    assert!(
        missing.is_empty(),
        "the maximally-populated profile does not exercise every {what} variant — missing {missing:?}. \
         ADR 07 §7.1 declares them all, so every one of them must be proven to survive the wire."
    );
    let unexpected: Vec<&&str> = found.difference(&expected).collect();
    assert!(
        unexpected.is_empty(),
        "the corpus produced {what} tags this test does not know about: {unexpected:?}. \
         A variant was added to ADR 07 §7.1's model — extend the `*_TAGS` list in this file."
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Corpus: a maximally-populated artifact
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Every leaf [`Predicate`] variant, using all five [`Cmp`] values between them.
///
/// The shapes follow ADR 07 §5.1.1's justifications: `.itemcount 5385,6`, `.money <0.0480`,
/// `.skill cooking,<50`, `.reputation 576,honored`, `.cooldown item,6948,>2`,
/// `.itemStat 16,ITEM_MOD_DAMAGE_PER_SECOND_SHORT,<25.6`, `.subzone 442`.
fn every_predicate_leaf() -> Vec<Predicate> {
    vec![
        Predicate::QuestComplete { id: 983 },
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 6,
        },
        Predicate::AtLocation {
            point: 0,
            radius: 5.5,
        },
        Predicate::LevelAtLeast { level: 11 },
        Predicate::AuraPresent {
            spell: 1130,
            on: UnitRef::Player,
        },
        Predicate::AuraPresent {
            spell: 5118,
            on: UnitRef::Target,
        },
        Predicate::Flag {
            key: "kernel.first_touch_ok".to_owned(),
        },
        Predicate::QuestInLog { id: 2118 },
        Predicate::QuestTurnedIn { id: 984 },
        Predicate::QuestAvailable { id: 985 },
        Predicate::ItemCount {
            id: 5385,
            cmp: Cmp::Ge,
            count: 6,
        },
        Predicate::MoneyCmp {
            cmp: Cmp::Lt,
            copper: 480,
        },
        Predicate::SkillCmp {
            line: SkillLine::Cooking,
            cmp: Cmp::Le,
            value: 50,
        },
        Predicate::ReputationCmp {
            faction: 576,
            standing: Standing::Honored,
            cmp: Cmp::Eq,
            value: 4200,
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
        Predicate::CooldownCmp {
            kind: CooldownKind::Spell,
            id: 556,
            cmp: Cmp::Lt,
            secs: 0.25,
        },
        Predicate::InArea {
            area: 442,
            kind: AreaKind::SubArea,
        },
        Predicate::InArea {
            area: 148,
            kind: AreaKind::Zone,
        },
        Predicate::HearthBoundTo { area: 149 },
        Predicate::ItemStatCmp {
            slot: 16,
            stat: ItemStat::DamagePerSecond,
            cmp: Cmp::Lt,
            value: 25.6,
        },
        Predicate::ItemStatCmp {
            slot: 18,
            stat: ItemStat::Quality,
            cmp: Cmp::Lt,
            value: 7.0,
        },
        Predicate::InGroup {
            cmp: Cmp::Ge,
            size: 2,
        },
        Predicate::SpellKnown { spell: 2973 },
        Predicate::LevelAtMost { level: 14 },
    ]
}

/// The seven [`DelegatePayload`] variants with every `Option` populated (C5, §5.5).
fn every_delegate_payload_populated() -> Vec<DelegatePayload> {
    vec![
        DelegatePayload::Vendor {
            npc: npc(3479, "Sentinel Selarin", Some(2)),
            mode: VendorMode::Buy,
            items: vec![4540, 159],
            gold_floor: Some(5_000),
        },
        DelegatePayload::Trainer {
            npc: npc(3596, "Lairn", Some(3)),
            spell: Some(1978),
        },
        DelegatePayload::FlightPath {
            npc: npc(4267, "Caylais Moonfeather", Some(4)),
            mode: FlightMode::Fly,
            dest_node: Some("Auberdine".to_owned()),
        },
        DelegatePayload::Hearth {
            mode: HearthMode::Bind,
            npc: Some(npc(6736, "Innkeeper Shaussiy", Some(5))),
        },
        DelegatePayload::Bank {
            npc: npc(4551, "Sirra Von'Indi", Some(6)),
            mode: BankMode::Withdraw,
            items: vec![5385],
        },
        DelegatePayload::Stable {
            npc: npc(3707, "Ulthir", Some(7)),
            mode: StableMode::Store,
        },
        DelegatePayload::Corpse {
            intent: CorpseIntent::DeliberateDeath,
            resurrect_at: Some(4),
        },
    ]
}

/// The same seven payloads with every `Option` empty, and the complementary mode values.
fn every_delegate_payload_emptied() -> Vec<DelegatePayload> {
    vec![
        DelegatePayload::Vendor {
            npc: npc(3479, "Sentinel Selarin", None),
            mode: VendorMode::Sell,
            items: Vec::new(),
            gold_floor: None,
        },
        DelegatePayload::Trainer {
            npc: npc(3596, "Lairn", None),
            spell: None,
        },
        DelegatePayload::FlightPath {
            npc: npc(4267, "Caylais Moonfeather", None),
            mode: FlightMode::Discover,
            dest_node: None,
        },
        DelegatePayload::Hearth {
            mode: HearthMode::Use,
            npc: None,
        },
        DelegatePayload::Bank {
            npc: npc(4551, "Sirra Von'Indi", None),
            mode: BankMode::Deposit,
            items: Vec::new(),
        },
        DelegatePayload::Stable {
            npc: npc(3707, "Ulthir", None),
            mode: StableMode::Visit,
        },
        DelegatePayload::Corpse {
            intent: CorpseIntent::Accidental,
            resurrect_at: None,
        },
    ]
}

fn delegate_ops(payloads: Vec<DelegatePayload>) -> Vec<Op> {
    payloads
        .into_iter()
        .map(|payload| {
            let behavior = match &payload {
                DelegatePayload::Vendor { .. } => BehaviorId::Vendor,
                DelegatePayload::Trainer { .. } => BehaviorId::Trainer,
                DelegatePayload::FlightPath { .. } => BehaviorId::FlightPath,
                DelegatePayload::Hearth { .. } => BehaviorId::Hearth,
                DelegatePayload::Bank { .. } => BehaviorId::Bank,
                DelegatePayload::Stable { .. } => BehaviorId::Stable,
                DelegatePayload::Corpse { .. } => BehaviorId::Corpse,
            };
            Op::Delegate { behavior, payload }
        })
        .collect()
}

/// A [`RuntimeProfile`] in which every enum variant is present and every `Option` is `Some`.
///
/// It is not a lowering of any guide — it is a *shape* corpus. Ids and names are borrowed from
/// §7.3's Darkshore worked example so a reader can recognise them.
fn maximal_profile() -> RuntimeProfile {
    let task_0 = Task {
        id: 0,
        deps: vec![],
        blocking: true,
        lifetime: Lifetime::Exclusive,
        completion: CompletionSource::OwnPredicate,
        // And / Or / Not plus every leaf, so all 24 predicate tags appear in one artifact.
        applies_when: Some(Predicate::And(every_predicate_leaf())),
        complete_when: Some(Predicate::Or(vec![
            Predicate::QuestObjective {
                id: 983,
                index: 1,
                need: 6,
            },
            Predicate::QuestTurnedIn { id: 983 },
        ])),
        abort_when: Some(Predicate::Not(Box::new(Predicate::QuestComplete {
            id: 983,
        }))),
        unknown_policy: UnknownPolicy::Block,
        ops: vec![
            Op::Travel {
                route: Route {
                    kind: RouteKind::Destination,
                    mode: TravelMode::Any,
                    points: vec![0],
                    radii: vec![5],
                },
            },
            Op::Accept {
                quest: 983,
                repeatable: false,
            },
            Op::TurnIn {
                quest: 983,
                any_of: vec![10346, 10347],
                reward_choice: Some(2),
                optional: true,
                repeatable: true,
            },
            Op::Abandon {
                quests: vec![984, 985],
            },
            Op::UntrackQuest { quest: 986 },
            Op::Interact {
                npc: npc(3583, "Sentinel Glynda Nal'Shea", Some(1)),
                gossip: GossipPolicy::None,
            },
        ],
        interact_target: Some(npc(3583, "Sentinel Glynda Nal'Shea", Some(1))),
        combat: Some(combat(CombatStance::Avoid, GroupExpectation::Solo)),
        loot_filter: vec![LootRule {
            item: 5385,
            for_quest: Some(983),
        }],
        serves_quests: vec![2118, 983],
        suppress: vec![
            BehaviorId::Vendor,
            BehaviorId::Trainer,
            BehaviorId::FlightPath,
            BehaviorId::Hearth,
            BehaviorId::Bank,
            BehaviorId::Stable,
            BehaviorId::Corpse,
        ],
        jump_to: Some(3),
        source: span(211, 237),
    };

    let task_1 = Task {
        id: 1,
        deps: vec![0],
        blocking: false,
        lifetime: Lifetime::Background {
            // All seven channels, so the SCREAMING_SNAKE spelling of every one is on the wire.
            channels: vec![
                Channel::Movement,
                Channel::Facing,
                Channel::Casting,
                Channel::Targeting,
                Channel::Interaction,
                Channel::Items,
                Channel::Camera,
            ],
            band: 30,
            terminate_on: Predicate::QuestTurnedIn { id: 983 },
        },
        completion: CompletionSource::LinkedTo(0),
        applies_when: Some(Predicate::QuestInLog { id: 983 }),
        complete_when: Some(Predicate::QuestComplete { id: 983 }),
        abort_when: Some(Predicate::LevelAtMost { level: 14 }),
        unknown_policy: UnknownPolicy::Defer { budget_ticks: 60 },
        ops: vec![
            Op::Travel {
                route: Route {
                    kind: RouteKind::Corridor,
                    mode: TravelMode::Ground,
                    points: vec![1, 2, 3],
                    radii: vec![60, 60, 60],
                },
            },
            Op::UseItem { item: 7586 },
            Op::Cast { spell: 2973 },
            Op::DestroyItem { item: 5385 },
            Op::Equip {
                slot: 16,
                item: 2488,
            },
            Op::EnterVehicle,
            Op::Wait {
                secs: 12,
                label: "RP: escort dialogue".to_owned(),
            },
            Op::Interact {
                npc: npc(3585, "Cerellean Whiteclaw", Some(2)),
                gossip: GossipPolicy::AutoAdvance,
            },
        ],
        interact_target: Some(npc(3585, "Cerellean Whiteclaw", Some(2))),
        combat: Some(combat(
            CombatStance::Defensive,
            GroupExpectation::Party { size: 5 },
        )),
        loot_filter: vec![LootRule {
            item: 7586,
            for_quest: Some(2118),
        }],
        serves_quests: vec![983],
        suppress: vec![BehaviorId::Corpse],
        jump_to: Some(2),
        source: span(240, 246),
    };

    let task_2 = Task {
        id: 2,
        deps: vec![0, 1],
        blocking: true,
        lifetime: Lifetime::Exclusive,
        completion: CompletionSource::OwnPredicate,
        applies_when: Some(Predicate::InArea {
            area: 442,
            kind: AreaKind::SubArea,
        }),
        complete_when: Some(Predicate::XpAtLeast {
            level: 12,
            xp_offset: 6760,
        }),
        abort_when: Some(Predicate::MoneyCmp {
            cmp: Cmp::Lt,
            copper: 480,
        }),
        unknown_policy: UnknownPolicy::TreatFalse,
        ops: {
            let mut ops = vec![
                Op::Travel {
                    route: Route {
                        kind: RouteKind::Circuit { close: true },
                        mode: TravelMode::Air,
                        points: vec![4, 5, 6, 7],
                        radii: vec![50, 50, 50, 50],
                    },
                },
                Op::Interact {
                    npc: npc(3706, "Gwennyth Bly'Leggonde", Some(3)),
                    gossip: GossipPolicy::Index(2),
                },
            ];
            ops.extend(delegate_ops(every_delegate_payload_populated()));
            ops
        },
        interact_target: Some(npc(3706, "Gwennyth Bly'Leggonde", Some(3))),
        combat: Some(combat(CombatStance::Objective, GroupExpectation::Dungeon)),
        loot_filter: vec![LootRule {
            item: 4306,
            for_quest: Some(984),
        }],
        serves_quests: vec![984],
        suppress: vec![BehaviorId::Vendor],
        jump_to: Some(3),
        source: span(247, 261),
    };

    let task_3 = Task {
        id: 3,
        // Authored order, and it is NOT sorted: §7.3.3 task 4 prints [2, 0].
        deps: vec![2, 0],
        blocking: false,
        lifetime: Lifetime::Background {
            channels: vec![Channel::Movement],
            band: 49,
            terminate_on: Predicate::QuestComplete { id: 984 },
        },
        completion: CompletionSource::LinkedTo(2),
        applies_when: Some(Predicate::HearthBoundTo { area: 149 }),
        complete_when: Some(Predicate::AtLocation {
            point: 7,
            radius: 5.0,
        }),
        abort_when: Some(Predicate::SpellKnown { spell: 556 }),
        unknown_policy: UnknownPolicy::TreatTrue,
        ops: vec![
            Op::Travel {
                route: Route {
                    kind: RouteKind::Circuit { close: false },
                    mode: TravelMode::Any,
                    points: vec![7, 6],
                    radii: vec![5, 5],
                },
            },
            Op::Interact {
                npc: npc(3924, "Terenthis", Some(6)),
                gossip: GossipPolicy::OptionId(41),
            },
        ],
        interact_target: Some(npc(3924, "Terenthis", Some(6))),
        combat: Some(combat(CombatStance::Aggressive, GroupExpectation::Solo)),
        loot_filter: vec![LootRule {
            item: 4291,
            for_quest: Some(985),
        }],
        serves_quests: vec![985],
        suppress: vec![BehaviorId::Hearth],
        jump_to: Some(0),
        source: span(262, 277),
    };

    RuntimeProfile {
        magic: MAGIC,
        schema_version: SCHEMA_VERSION,
        schema_hash: [0xab; 32],
        tags_used: PREDICATE_TAGS
            .iter()
            .chain(OP_TAGS.iter())
            .map(|tag| (*tag).to_owned())
            .collect(),
        integrity: ContentIntegrity {
            content_hash: [0x5a; 32],
            world_source: "tbcmangos.sqlite".to_owned(),
            world_build: "sha256:0f0f; quest_template=6599 creature_template=18799".to_owned(),
        },
        archetype: Archetype {
            class: Class::Hunter,
            race: Race::NightElf,
            faction: Faction::Alliance,
            expansion: Expansion::Tbc,
            allegiance: Some(Allegiance::Aldor),
            hardcore: true,
            self_found: true,
            can_fly: true,
            content_phase: Some(5),
            mode: ProfileMode::SpeedRoute,
        },
        meta: GuideMeta {
            name: "10-14 Darkshore".to_owned(),
            group: "RestedXP TBC Guide (A)".to_owned(),
            subgroup: Some("RestedXP Alliance 1-20".to_owned()),
            source_version: 7,
            next: vec!["14-16 Loch Modan".to_owned()],
        },
        defaults: ProfileDefaults {
            combat: combat(CombatStance::Defensive, GroupExpectation::Solo),
            unknown_policy: UnknownPolicy::Defer { budget_ticks: 60 },
        },
        waypoint_pool: vec![
            point(4_000.5, 200.25, Some(11.5)),
            point(4_010.5, 210.25, Some(12.0)),
            point(4_020.5, 220.25, Some(12.5)),
            point(4_030.5, 230.25, Some(13.0)),
            point(4_040.5, 240.25, Some(13.5)),
            point(4_050.5, 250.25, Some(14.0)),
            point(4_060.5, 260.25, Some(14.5)),
            point(4_070.5, 270.25, Some(15.0)),
        ],
        tasks: vec![task_0, task_1, task_2, task_3],
    }
}

/// The mirror image of [`maximal_profile`]: every `Option` is `None` and every collection that may
/// legally be empty is empty.
fn emptied_profile() -> RuntimeProfile {
    let task_0 = Task {
        id: 0,
        deps: Vec::new(),
        blocking: true,
        lifetime: Lifetime::Exclusive,
        completion: CompletionSource::OwnPredicate,
        applies_when: None,
        complete_when: None,
        abort_when: None,
        unknown_policy: UnknownPolicy::TreatFalse,
        // §7.3.3 task 4: a folded `--XXREQ` placeholder step is a real task with no operations.
        ops: Vec::new(),
        // §7.3.2: quest 983's ender is gameobject 17182, not a creature. `None` is the answer,
        // not the absence of one.
        interact_target: None,
        combat: None,
        loot_filter: Vec::new(),
        serves_quests: Vec::new(),
        suppress: Vec::new(),
        jump_to: None,
        source: span(265, 268),
    };

    let task_1 = Task {
        id: 1,
        deps: Vec::new(),
        blocking: false,
        // §7.3.3 task 6: a `#completewith`-only task is Background with an EMPTY channel set — it
        // rides along without contending for any lease.
        lifetime: Lifetime::Background {
            channels: Vec::new(),
            band: 30,
            terminate_on: Predicate::QuestTurnedIn { id: 983 },
        },
        completion: CompletionSource::LinkedTo(0),
        applies_when: None,
        complete_when: None,
        abort_when: None,
        unknown_policy: UnknownPolicy::Block,
        ops: {
            let mut ops = vec![
                Op::Travel {
                    route: Route {
                        kind: RouteKind::Destination,
                        mode: TravelMode::Any,
                        points: Vec::new(),
                        radii: Vec::new(),
                    },
                },
                Op::TurnIn {
                    quest: 983,
                    any_of: Vec::new(),
                    reward_choice: None,
                    optional: false,
                    repeatable: false,
                },
            ];
            ops.extend(delegate_ops(every_delegate_payload_emptied()));
            ops
        },
        interact_target: None,
        combat: Some(CombatPolicy {
            stance: CombatStance::Defensive,
            targets: Vec::new(),
            watch_units: Vec::new(),
            leash_yards: 0,
            allow_adds: false,
            expect_group: GroupExpectation::Solo,
        }),
        loot_filter: vec![LootRule {
            item: 5385,
            for_quest: None,
        }],
        serves_quests: Vec::new(),
        suppress: Vec::new(),
        jump_to: None,
        source: span(269, 272),
    };

    RuntimeProfile {
        magic: MAGIC,
        schema_version: SCHEMA_VERSION,
        schema_hash: [0x00; 32],
        tags_used: Vec::new(),
        integrity: ContentIntegrity {
            content_hash: [0xff; 32],
            world_source: "tbcmangos.sqlite".to_owned(),
            world_build: String::new(),
        },
        archetype: Archetype {
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
        },
        meta: GuideMeta {
            name: "10-14 Darkshore".to_owned(),
            group: "RestedXP TBC Guide (A)".to_owned(),
            subgroup: None,
            source_version: 7,
            next: Vec::new(),
        },
        defaults: ProfileDefaults {
            combat: CombatPolicy {
                stance: CombatStance::Defensive,
                targets: Vec::new(),
                watch_units: Vec::new(),
                leash_yards: 40,
                allow_adds: true,
                expect_group: GroupExpectation::Solo,
            },
            unknown_policy: UnknownPolicy::Defer { budget_ticks: 60 },
        },
        // The compiler never resolved a Z for these; §5.7 leaves `None` and lets the engine snap.
        waypoint_pool: vec![point(4_000.5, 200.25, None)],
        tasks: vec![task_0, task_1],
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// §7.1 / §7.2 — lossless round trip
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn maximal_profile_round_trips_without_loss() {
    let profile = maximal_profile();
    round_trip(
        &profile,
        "ADR 07 §7.1/§7.2 (the artifact is the contract): RuntimeProfile",
    );
}

/// Collect the JSON pointer of every `null` in a document.
fn collect_nulls(value: &Value, path: &mut String, found: &mut Vec<String>) {
    match value {
        Value::Null => found.push(path.clone()),
        Value::Array(items) => {
            for (index, item) in items.iter().enumerate() {
                let mark = path.len();
                path.push('/');
                path.push_str(&index.to_string());
                collect_nulls(item, path, found);
                path.truncate(mark);
            }
        }
        Value::Object(members) => {
            for (key, member) in members {
                let mark = path.len();
                path.push('/');
                path.push_str(key);
                collect_nulls(member, path, found);
                path.truncate(mark);
            }
        }
        _ => {}
    }
}

#[test]
fn maximal_profile_leaves_no_option_field_unpopulated() {
    // The maximal corpus is only maximal if every `Option` in it is `Some`. Every `Option` in this
    // model serializes to `null` when empty and no field is skipped, so "no nulls anywhere" is an
    // exact proof of that — and it fails loudly if ADR 07 §7.1 grows an Option this file forgot.
    let value = serde_json::to_value(maximal_profile()).unwrap();
    let mut path = String::new();
    let mut nulls = Vec::new();
    collect_nulls(&value, &mut path, &mut nulls);
    assert!(
        nulls.is_empty(),
        "the corpus meant to populate every Option field of ADR 07 §7.1 left these null: {nulls:?}. \
         Populate them, or the `Some(..)` half of the round-trip contract is untested for them."
    );
}

#[test]
fn maximal_profile_exercises_every_variant_adr_07_declares() {
    let profile = maximal_profile();
    let coverage = Coverage::of(&profile);

    assert_covers(&coverage.predicates, &PREDICATE_TAGS, "Predicate (§5.1.1)");
    assert_covers(&coverage.ops, &OP_TAGS, "Op (§7.1)");
    assert_covers(&coverage.delegates, &DELEGATE_TAGS, "DelegatePayload (§5.5)");
    assert_covers(&coverage.cmps, &CMP_TAGS, "Cmp (§5.1.1)");
    assert_covers(&coverage.lifetimes, &LIFETIME_TAGS, "Lifetime (§5.3)");
    assert_covers(
        &coverage.completions,
        &COMPLETION_TAGS,
        "CompletionSource (§5.3)",
    );
    assert_covers(
        &coverage.unknown_policies,
        &UNKNOWN_POLICY_TAGS,
        "UnknownPolicy (§5.1.2)",
    );
    assert_covers(&coverage.route_kinds, &ROUTE_KIND_TAGS, "RouteKind (§5.7)");
    assert_covers(&coverage.gossips, &GOSSIP_TAGS, "GossipPolicy (§7.1)");
    assert_covers(&coverage.stances, &STANCE_TAGS, "CombatStance (§5.6)");
    assert_covers(&coverage.groups, &GROUP_TAGS, "GroupExpectation (§5.6)");
}

#[test]
fn every_predicate_variant_round_trips_on_its_own() {
    for predicate in every_predicate_leaf() {
        let tag = predicate_tag(&predicate);
        round_trip(&predicate, &format!("ADR 07 §5.1.1: Predicate::{tag}"));
    }
    for compound in [
        Predicate::And(every_predicate_leaf()),
        Predicate::Or(every_predicate_leaf()),
        Predicate::Not(Box::new(Predicate::And(every_predicate_leaf()))),
    ] {
        let tag = predicate_tag(&compound);
        round_trip(
            &compound,
            &format!("ADR 07 §5.1 (one condition language, nestable): Predicate::{tag}"),
        );
    }
}

#[test]
fn every_op_and_delegate_payload_round_trips_on_its_own() {
    let profile = maximal_profile();
    for task in &profile.tasks {
        for op in &task.ops {
            let tag = op_tag(op);
            round_trip(op, &format!("ADR 07 §7.1 (step-as-container): Op::{tag}"));
        }
    }
    for payload in every_delegate_payload_populated()
        .into_iter()
        .chain(every_delegate_payload_emptied())
    {
        let tag = delegate_tag(&payload);
        round_trip(
            &payload,
            &format!("ADR 07 §5.5 (delegate, don't reimplement): DelegatePayload::{tag}"),
        );
    }
}

#[test]
fn tagged_enums_expose_a_type_key_never_an_outer_variant_key() {
    // C4, ADR 07 §5.4. The externally tagged shape `{"QuestInLog": {...}}` is the bug this
    // repository already shipped once: Lua dispatches on `.type`, found nil, and failed OPEN.
    let samples: Vec<(&str, Value)> = vec![
        (
            "Predicate",
            serde_json::to_value(Predicate::QuestInLog { id: 983 }).unwrap(),
        ),
        ("Cmp", serde_json::to_value(Cmp::Ge).unwrap()),
        (
            "Lifetime",
            serde_json::to_value(Lifetime::Exclusive).unwrap(),
        ),
        (
            "CompletionSource",
            serde_json::to_value(CompletionSource::LinkedTo(7)).unwrap(),
        ),
        (
            "UnknownPolicy",
            serde_json::to_value(UnknownPolicy::Defer { budget_ticks: 60 }).unwrap(),
        ),
        (
            "Op",
            serde_json::to_value(Op::UseItem { item: 7586 }).unwrap(),
        ),
        (
            "RouteKind",
            serde_json::to_value(RouteKind::Circuit { close: true }).unwrap(),
        ),
        (
            "GossipPolicy",
            serde_json::to_value(GossipPolicy::Index(2)).unwrap(),
        ),
        (
            "DelegatePayload",
            serde_json::to_value(DelegatePayload::Corpse {
                intent: CorpseIntent::Accidental,
                resurrect_at: None,
            })
            .unwrap(),
        ),
        (
            "CombatStance",
            serde_json::to_value(CombatStance::Aggressive).unwrap(),
        ),
        (
            "GroupExpectation",
            serde_json::to_value(GroupExpectation::Party { size: 5 }).unwrap(),
        ),
    ];

    for (name, value) in samples {
        let object = value.as_object().unwrap_or_else(|| {
            panic!("C4 (ADR 07 §5.4): `{name}` must serialize as an object, got {value}")
        });
        assert!(
            object.contains_key("type"),
            "C4 (ADR 07 §5.4): `{name}` is not adjacently tagged — no `type` key in {value}. \
             Lua dispatches on `.type`; without it every value falls through to fail-open."
        );
        for key in object.keys() {
            assert!(
                key == "type" || key == "payload",
                "C4 (ADR 07 §5.4): `{name}` emitted the key `{key}`; adjacent tagging permits only \
                 `type` and `payload`. Value: {value}"
            );
        }
    }
}

#[test]
fn scalar_vocabulary_round_trips_as_bare_strings() {
    // ADR 07 §7.3.3 forces this: the fixture contains "class": "Hunter", "expansion": "Tbc",
    // "mode": "Ground", "kind": "SubArea". Adjacently tagging these would break that fixture.
    macro_rules! assert_bare_string {
        ($what:expr, $($value:expr),+ $(,)?) => {
            $({
                let value = $value;
                let encoded = serde_json::to_value(value)
                    .expect("scalar vocabulary must serialize");
                assert!(
                    encoded.is_string(),
                    "ADR 07 §7.3.3: `{}` must serialize as a bare string, got {}",
                    $what, encoded
                );
                round_trip(&value, &format!("ADR 07 §7.3.3 (bare scalar vocabulary): {}", $what));
            })+
        };
    }

    assert_bare_string!(
        "Class",
        Class::Warrior,
        Class::Paladin,
        Class::Hunter,
        Class::Rogue,
        Class::Priest,
        Class::Shaman,
        Class::Mage,
        Class::Warlock,
        Class::Druid,
    );
    assert_bare_string!(
        "Race",
        Race::Human,
        Race::Orc,
        Race::Dwarf,
        Race::NightElf,
        Race::Undead,
        Race::Tauren,
        Race::Gnome,
        Race::Troll,
        Race::BloodElf,
        Race::Draenei,
    );
    assert_bare_string!(
        "Faction",
        Faction::Alliance,
        Faction::Horde,
        Faction::Neutral,
    );
    assert_bare_string!(
        "Expansion",
        Expansion::Classic,
        Expansion::Tbc,
        Expansion::Wotlk,
    );
    assert_bare_string!("Allegiance", Allegiance::Aldor, Allegiance::Scryer);
    assert_bare_string!(
        "ProfileMode",
        ProfileMode::SpeedRoute,
        ProfileMode::QuestGuide,
        ProfileMode::Dungeon,
    );
    assert_bare_string!(
        "TravelMode",
        TravelMode::Any,
        TravelMode::Ground,
        TravelMode::Air,
    );
    assert_bare_string!("AreaKind", AreaKind::Zone, AreaKind::SubArea);
    assert_bare_string!("UnitRef", UnitRef::Player, UnitRef::Target);
    assert_bare_string!(
        "SkillLine",
        SkillLine::Cooking,
        SkillLine::Enchanting,
        SkillLine::Engineering,
        SkillLine::FirstAid,
        SkillLine::Herbalism,
        SkillLine::Lockpicking,
        SkillLine::Mining,
        SkillLine::Riding,
        SkillLine::Skinning,
        SkillLine::Tailoring,
    );
    assert_bare_string!(
        "Standing",
        Standing::Unfriendly,
        Standing::Neutral,
        Standing::Friendly,
        Standing::Honored,
        Standing::Revered,
        Standing::Exalted,
    );
    assert_bare_string!("CooldownKind", CooldownKind::Item, CooldownKind::Spell);
    assert_bare_string!("ItemStat", ItemStat::Quality, ItemStat::DamagePerSecond);
    assert_bare_string!(
        "BehaviorId",
        BehaviorId::Vendor,
        BehaviorId::Trainer,
        BehaviorId::FlightPath,
        BehaviorId::Hearth,
        BehaviorId::Bank,
        BehaviorId::Stable,
        BehaviorId::Corpse,
    );
    assert_bare_string!("VendorMode", VendorMode::Sell, VendorMode::Buy);
    assert_bare_string!("FlightMode", FlightMode::Fly, FlightMode::Discover);
    assert_bare_string!("HearthMode", HearthMode::Use, HearthMode::Bind);
    assert_bare_string!("BankMode", BankMode::Withdraw, BankMode::Deposit);
    assert_bare_string!(
        "StableMode",
        StableMode::Visit,
        StableMode::Store,
        StableMode::Retrieve,
    );
    assert_bare_string!(
        "CorpseIntent",
        CorpseIntent::Accidental,
        CorpseIntent::DeliberateDeath,
    );
}

#[test]
fn channels_are_screaming_snake_case_and_round_trip() {
    // ADR 07 §7.2 pins the enum list; §7.3.3 prints "channels": ["MOVEMENT"].
    let expected = [
        (Channel::Movement, "MOVEMENT"),
        (Channel::Facing, "FACING"),
        (Channel::Casting, "CASTING"),
        (Channel::Targeting, "TARGETING"),
        (Channel::Interaction, "INTERACTION"),
        (Channel::Items, "ITEMS"),
        (Channel::Camera, "CAMERA"),
    ];
    for (channel, wire) in expected {
        assert_eq!(
            serde_json::to_value(channel).unwrap(),
            json!(wire),
            "ADR 07 §7.2: Channel must serialize SCREAMING_SNAKE"
        );
        round_trip(&channel, &format!("ADR 07 §7.2: Channel::{wire}"));
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// §7.3.2 — `None` is a value, not an absence
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn emptied_profile_round_trips_with_every_option_none() {
    let profile = emptied_profile();
    round_trip(
        &profile,
        "ADR 07 §7.1: RuntimeProfile with every Option field set to None",
    );

    let value = serde_json::to_value(&profile).unwrap();
    for (pointer, what) in [
        ("/archetype/allegiance", "Archetype::allegiance (§5.2)"),
        ("/archetype/content_phase", "Archetype::content_phase (§5.2)"),
        ("/meta/subgroup", "GuideMeta::subgroup (§7.1)"),
        ("/waypoint_pool/0/z", "Point::z (§5.7)"),
        ("/tasks/0/applies_when", "Task::applies_when (§7.1)"),
        ("/tasks/0/complete_when", "Task::complete_when (C1, §5.1)"),
        ("/tasks/0/abort_when", "Task::abort_when (§8)"),
        ("/tasks/0/combat", "Task::combat (C6, §5.6)"),
        ("/tasks/0/jump_to", "Task::jump_to (§4.1)"),
        ("/tasks/1/loot_filter/0/for_quest", "LootRule::for_quest (§4.1)"),
        ("/tasks/1/ops/1/payload/reward_choice", "Op::TurnIn::reward_choice (§4.1)"),
    ] {
        assert_eq!(
            value.pointer(pointer),
            Some(&Value::Null),
            "ADR 07: {what} must be present as an explicit null at `{pointer}`, not dropped. \
             Dropping it makes \"no value\" indistinguishable from \"field forgotten\", and the \
             root object denies unknown fields, so a re-added key would then fail to load. \
             Full document: {value}"
        );
    }
}

#[test]
fn interact_target_none_is_emitted_as_null_not_dropped() {
    // ADR 07 §7.3.2 / §8: quest 983's ender is `gameobject_involvedrelation` entry 17182, not a
    // creature, which is exactly why the worked example's turn-in task carries no `.target`.
    // `None` here is the resolved, correct answer — a schema that treated it as a missing value
    // would emit a null target and stall the runner.
    let profile = emptied_profile();
    let value = serde_json::to_value(&profile).unwrap();

    let task = value["tasks"][0]
        .as_object()
        .expect("tasks[0] must be an object");
    assert!(
        task.contains_key("interact_target"),
        "ADR 07 §7.3.2: `interact_target` must be present even when None — a gameobject turn-in \
         legitimately has no NPC and the artifact must say so explicitly. Task was: {:?}",
        task
    );
    assert_eq!(
        task["interact_target"],
        Value::Null,
        "ADR 07 §7.3.2: `interact_target: None` must serialize as null"
    );

    let reloaded: RuntimeProfile = serde_json::from_value(value).unwrap();
    assert!(
        reloaded.tasks[0].interact_target.is_none(),
        "ADR 07 §7.3.2: `interact_target: None` did not survive the round trip"
    );
    assert_eq!(reloaded, profile);
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// §7.3.3 — empty is a value, not an absence
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn empty_collections_survive_as_empty_arrays() {
    let profile = emptied_profile();
    let value = serde_json::to_value(&profile).unwrap();

    for (pointer, what) in [
        ("/tags_used", "RuntimeProfile::tags_used (C4, §5.4)"),
        ("/meta/next", "GuideMeta::next (§7.1)"),
        (
            "/defaults/combat/targets",
            "CombatPolicy::targets — `.mob` absent (§5.6)",
        ),
        (
            "/defaults/combat/watch_units",
            "CombatPolicy::watch_units — `.unitscan` absent (§5.6)",
        ),
        ("/tasks/0/deps", "Task::deps — no `#requires` (P1, §7.1)"),
        (
            "/tasks/0/ops",
            "Task::ops — §7.3.3 task 4 is a folded placeholder step with no operations",
        ),
        ("/tasks/0/loot_filter", "Task::loot_filter (§4.1)"),
        ("/tasks/0/serves_quests", "Task::serves_quests (§4.1)"),
        ("/tasks/0/suppress", "Task::suppress (§8)"),
        (
            "/tasks/1/lifetime/payload/channels",
            "Lifetime::Background::channels — §7.3.3 task 6 holds NO channels (§5.3)",
        ),
        (
            "/tasks/1/ops/0/payload/route/points",
            "Route::points (§5.7)",
        ),
        ("/tasks/1/ops/0/payload/route/radii", "Route::radii (§5.7)"),
        (
            "/tasks/1/ops/1/payload/any_of",
            "Op::TurnIn::any_of (§8, the Aldor/Scryer choice point)",
        ),
    ] {
        assert_eq!(
            value.pointer(pointer),
            Some(&json!([])),
            "ADR 07: {what} must serialize as an empty array at `{pointer}`, never be elided. \
             An elided collection is indistinguishable from an unset one, and the root denies \
             unknown fields so it could not be re-added. Full document: {value}"
        );
    }

    let reloaded: RuntimeProfile = serde_json::from_value(value).unwrap();
    assert_eq!(
        reloaded, profile,
        "ADR 07 §7.3.3: a profile whose collections are empty must survive the round trip"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// §7.2 / §6.2.5 — the magic is a guard
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[derive(Debug, PartialEq, Serialize, Deserialize)]
struct MagicHolder {
    #[serde(with = "magic")]
    magic: [u8; 4],
}

#[test]
fn magic_round_trips_as_the_string_sntl() {
    let holder = MagicHolder { magic: MAGIC };
    assert_eq!(
        serde_json::to_value(&holder).unwrap(),
        json!({ "magic": "SNTL" }),
        "ADR 07 §7.2 pins `\"magic\": {{ \"const\": \"SNTL\" }}`"
    );
    let parsed = round_trip(&holder, "ADR 07 §7.2/§6.2.5: container magic");
    assert_eq!(
        parsed.magic, *b"SNTL",
        "ADR 07 §6.2.5: the magic must decode back to the four bytes b\"SNTL\""
    );

    // ... and through the real root field, not just a stand-in holder.
    let profile = maximal_profile();
    let value = serde_json::to_value(&profile).unwrap();
    assert_eq!(value["magic"], json!("SNTL"));
    assert_eq!(
        serde_json::from_value::<RuntimeProfile>(value).unwrap().magic,
        MAGIC
    );
}

#[test]
fn magic_refuses_everything_that_is_not_sntl() {
    // A magic that accepts near-misses is not a guard. ADR 07 §5.4 (C4): refuse, don't degrade.
    let impostors = [
        (json!("SNTX"), "one byte wrong"),
        (json!("SNT"), "truncated to three bytes"),
        (json!("SNTLL"), "one byte too long"),
        (json!(""), "empty string"),
        (json!("sntl"), "lowercase"),
        (json!(1234), "a number rather than a string"),
        (json!([83, 78, 84, 76]), "the raw byte-array form"),
        (json!(null), "null"),
    ];
    for (impostor, why) in impostors {
        let attempt = serde_json::from_value::<MagicHolder>(json!({ "magic": impostor }));
        assert!(
            attempt.is_err(),
            "ADR 07 §7.2/§5.4: the container magic accepted {why} ({impostor}). \
             The magic exists to make a non-Sentinel file fail at the first field; if it accepts \
             anything but \"SNTL\" it is not guarding."
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// §7.2 — digests are lowercase 64-hex, and nothing else
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[derive(Debug, PartialEq, Serialize, Deserialize)]
struct DigestHolder {
    #[serde(with = "hex32")]
    digest: [u8; 32],
}

#[test]
fn digests_round_trip_as_lowercase_hex_with_the_right_bytes() {
    // ADR 07 §7.2: "pattern": "^[0-9a-f]{64}$".
    let text = "00112233445566778899aabbccddeeff".repeat(2);
    assert_eq!(text.len(), 64);

    let parsed: DigestHolder = serde_json::from_value(json!({ "digest": text })).unwrap();
    let mut expected = [0u8; 32];
    for (index, slot) in expected.iter_mut().enumerate() {
        let byte = [
            0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd,
            0xee, 0xff,
        ][index % 16];
        *slot = byte;
    }
    assert_eq!(
        parsed.digest, expected,
        "ADR 07 §7.2: a 64-character lowercase hex digest must decode to the exact 32 bytes it spells"
    );
    assert_eq!(
        serde_json::to_value(&parsed).unwrap(),
        json!({ "digest": text }),
        "ADR 07 §7.2: a digest must re-emit as the same lowercase hex string"
    );
    round_trip(&parsed, "ADR 07 §7.2: 32-byte digest as ^[0-9a-f]{64}$");

    // Both digest-bearing fields of the artifact use this codec.
    let integrity = ContentIntegrity {
        content_hash: [0x5a; 32],
        world_source: "tbcmangos.sqlite".to_owned(),
        world_build: "sha256:0f0f; quest_template=6599".to_owned(),
    };
    let value = serde_json::to_value(&integrity).unwrap();
    assert_eq!(value["content_hash"], json!("5a".repeat(32)));
    round_trip(&integrity, "ADR 07 §5.4.1: ContentIntegrity");
}

#[test]
fn digests_refuse_anything_outside_the_pinned_pattern() {
    let malformed = [
        (json!("ab".repeat(31) + "a"), "63 characters"),
        (json!("ab".repeat(32) + "a"), "65 characters"),
        (json!("AB".repeat(32)), "uppercase hex"),
        (
            json!("00112233445566778899AABBCCDDEEFF".repeat(2)),
            "mixed case hex",
        ),
        (json!("zz".repeat(32)), "non-hex characters"),
        (json!("0x".to_owned() + &"ab".repeat(31)), "an 0x prefix"),
        (json!(vec![0u8; 32]), "a JSON array of 32 numbers"),
        (json!(null), "null"),
    ];
    for (candidate, why) in malformed {
        let attempt = serde_json::from_value::<DigestHolder>(json!({ "digest": candidate }));
        assert!(
            attempt.is_err(),
            "ADR 07 §7.2: the digest codec accepted {why} ({candidate}). The pinned pattern is \
             ^[0-9a-f]{{64}}$ — uppercase in particular must fail, because two spellings of one \
             digest would break the cross-artifact equality check of §5.4.1 (profile vs sidecar \
             index vs .save.json)."
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// C4 (§5.4) — refuse, don't degrade
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn every_struct_in_the_artifact_refuses_unknown_fields() {
    let profile = maximal_profile();

    reject_extra_key(&profile, "extra", "RuntimeProfile (root, §7.2)");
    reject_extra_key(&profile.tasks[0], "extra", "Task (§7.1)");
    reject_extra_key(&profile.integrity, "extra", "ContentIntegrity (§5.4.1)");
    reject_extra_key(&profile.defaults.combat, "extra", "CombatPolicy (§5.6)");
    reject_extra_key(&profile.waypoint_pool[0], "extra", "Point (§5.7)");
    reject_extra_key(&profile.tasks[0].source, "extra", "SourceSpan (§6.6)");
    reject_extra_key(
        &profile.defaults.combat.targets[0],
        "extra",
        "NpcRef (§5.4.1)",
    );

    let route = Route {
        kind: RouteKind::Circuit { close: true },
        mode: TravelMode::Ground,
        points: vec![0, 1, 2],
        radii: vec![60, 60, 60],
    };
    reject_extra_key(&route, "extra", "Route (C7, §5.7)");

    // Also the remaining artifact structs, for completeness.
    reject_extra_key(&profile.archetype, "extra", "Archetype (C2, §5.2)");
    reject_extra_key(&profile.meta, "extra", "GuideMeta (§7.1)");
    reject_extra_key(&profile.defaults, "extra", "ProfileDefaults (§7.1)");
    reject_extra_key(
        &profile.tasks[0].loot_filter[0],
        "extra",
        "LootRule (§4.1)",
    );
    reject_extra_key(
        &ResumeCursor {
            task: 0,
            op_index: 0,
            waypoint: 0,
            loop_iter: 0,
        },
        "extra",
        "ResumeCursor (§5.3)",
    );
}

#[test]
fn prose_comment_keys_are_refused_by_the_artifact() {
    // ADR 07 §7.3.3 annotates its worked example with `_comment` keys. Those keys are prose, not
    // schema, and C4 (§5.4) says an artifact carrying a field this model does not understand must
    // refuse to load. That is precisely why the checked-in fixture had to have them stripped.
    let profile = maximal_profile();
    reject_extra_key(&profile, "_comment", "RuntimeProfile (root, §7.3.3 prose)");
    reject_extra_key(&profile.tasks[0], "_comment", "Task (§7.3.3 prose)");
    reject_extra_key(
        &profile.waypoint_pool[0],
        "_comment",
        "Point (§7.3.3 prose)",
    );
}

#[test]
fn unknown_keys_inside_a_tagged_payload_are_also_refused() {
    // C4 must hold at both levels: beside `type`/`payload`, and inside the variant's own payload.
    let cases = [
        (
            json!({ "type": "QuestInLog", "payload": { "id": 983, "bogus": 1 } }),
            "an unknown key inside a Predicate payload",
        ),
        (
            json!({ "type": "QuestInLog", "payload": { "id": 983 }, "bogus": 1 }),
            "an unknown key beside `type`/`payload` on a Predicate",
        ),
    ];
    for (candidate, why) in cases {
        assert!(
            serde_json::from_value::<Predicate>(candidate.clone()).is_err(),
            "C4 (ADR 07 §5.4): the model accepted {why}: {candidate}"
        );
    }

    let op = json!({
        "type": "Wait",
        "payload": { "secs": 12, "label": "RP", "bogus": true }
    });
    assert!(
        serde_json::from_value::<Op>(op.clone()).is_err(),
        "C4 (ADR 07 §5.4): the model accepted an unknown key inside an Op payload: {op}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// §7.3.2 / §8 — load-bearing edge cases
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn quest_objective_need_zero_is_accepted_and_preserved() {
    // ADR 07 §7.3.2 / §8: quest 984 ("How Big a Threat?") has no `Req*` columns populated at all —
    // it is an exploration objective satisfied by area discovery, not by a count. A model that
    // rejected or defaulted `need: 0` would make that objective unsatisfiable.
    let predicate = Predicate::QuestObjective {
        id: 984,
        index: 1,
        need: 0,
    };
    let value = serde_json::to_value(&predicate).unwrap();
    assert_eq!(
        value,
        json!({ "type": "QuestObjective", "payload": { "id": 984, "index": 1, "need": 0 } }),
        "ADR 07 §7.3.2: `need: 0` must be written out verbatim"
    );
    let parsed: Predicate = serde_json::from_value(value).unwrap();
    assert_eq!(
        parsed, predicate,
        "ADR 07 §8: `need: 0` did not survive the round trip — quest 984's exploration objective \
         would become unsatisfiable"
    );
    round_trip(&predicate, "ADR 07 §7.3.2: QuestObjective { need: 0 }");
}

#[test]
fn task_deps_preserve_authored_order_and_duplicates() {
    // ADR 07 §7.3.3 task 4 prints `"deps": [2, 0]`. Dependency order is the compiler's to choose;
    // the model must not sort, dedupe, or otherwise "tidy" it.
    let mut task = maximal_profile().tasks[3].clone();
    assert_eq!(task.deps, vec![2, 0], "corpus precondition");

    let value = serde_json::to_value(&task).unwrap();
    assert_eq!(
        value["deps"],
        json!([2, 0]),
        "ADR 07 §7.3.3 task 4: `deps` came back sorted. Order is the compiler's, not the model's, \
         to normalise."
    );
    let parsed: Task = serde_json::from_value(value).unwrap();
    assert_eq!(parsed.deps, vec![2, 0]);
    round_trip(&task, "ADR 07 §7.1 (P1): Task::deps order");

    // Duplicates as authored: `#requires` may name the same predecessor twice, and squashing it
    // silently changes what the artifact says.
    task.deps = vec![3, 1, 3, 1];
    let value = serde_json::to_value(&task).unwrap();
    assert_eq!(
        value["deps"],
        json!([3, 1, 3, 1]),
        "ADR 07 §7.1 (P1): duplicate `deps` entries were collapsed; `deps` is a Vec, not a Set"
    );
    assert_eq!(
        serde_json::from_value::<Task>(value).unwrap().deps,
        vec![3, 1, 3, 1]
    );
}

#[test]
fn resume_cursor_round_trips_all_four_levels() {
    // ADR 07 §5.3 / kernel change K8: `op_index` alone is not enough, because one `Op::Travel`
    // carries a whole route. A 15-waypoint circuit preempted by combat must resume at the waypoint
    // it reached, not restart — that is a minutes-long regression per interruption.
    let cursor = ResumeCursor {
        task: 3,
        op_index: 2,
        waypoint: 14,
        loop_iter: 7,
    };
    assert_eq!(
        serde_json::to_value(cursor).unwrap(),
        json!({ "task": 3, "op_index": 2, "waypoint": 14, "loop_iter": 7 }),
        "ADR 07 §5.3: the resume cursor is (task, op_index, waypoint, loop_iter) — all four levels \
         must reach the wire"
    );
    let parsed = round_trip(&cursor, "ADR 07 §5.3 (K8): ResumeCursor");
    assert_eq!(parsed.task, 3);
    assert_eq!(
        parsed.op_index, 2,
        "ADR 07 §5.3: op_index lost across the round trip"
    );
    assert_eq!(
        parsed.waypoint, 14,
        "ADR 07 §5.3: waypoint lost across the round trip — a preempted circuit would restart"
    );
    assert_eq!(
        parsed.loop_iter, 7,
        "ADR 07 §5.3: loop_iter lost across the round trip — a `#loop` task would recount"
    );
}

#[test]
fn an_artifact_that_is_not_understood_is_refused_outright() {
    // C4 (ADR 07 §5.4) is not only about extra keys. Four more ways an artifact can be one this
    // kernel must not interpret, each of which has to fail rather than fill in a plausible value.
    assert!(
        serde_json::from_str::<Predicate>(r#"{"type":"Bogus","payload":{}}"#).is_err(),
        "C4 (ADR 07 §5.4): an unrecognised predicate tag loaded. A newer artifact using a tag this \
         kernel does not implement must refuse, not fall through — falling through is exactly how \
         the externally tagged condition enum failed open in Lua."
    );
    assert!(
        serde_json::from_str::<Channel>(r#""MOVEMENTX""#).is_err(),
        "C4 (ADR 07 §5.4/§7.2): an unrecognised Channel spelling loaded. The channel set is the \
         lease vocabulary of the ControlBroker (§5.3); an unknown channel cannot be arbitrated."
    );
    assert!(
        serde_json::from_str::<SourceSpan>(r#"{"file":"A-11-23.lua","line_start":211}"#).is_err(),
        "ADR 07 §7.2: every field in the root `required` list is required. A missing field must \
         fail, not default."
    );
    assert!(
        serde_json::from_str::<SourceSpan>(
            r#"{"file":"a","line_start":1,"line_start":2,"line_end":3}"#
        )
        .is_err(),
        "C4 (ADR 07 §5.4): a duplicated key loaded and one of the two values won silently. Which \
         one wins is not something an artifact format may leave to chance."
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Known R1 defect — kept failing-but-ignored so the audit phase can rule on it
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── SCOPE ────────────────────────────────────────────────────────────────────────────────────────
// This is a real MODEL defect and it is deliberately still failing. It is out of scope for the ADR 07
// audit (which moved only the ADR text and the fixture, never `src/kernel/*.rs`) and belongs to the
// later deliverable that adds the finite-float guard.
//
// ── TRAP, for whoever implements that guard ───────────────────────────────────────────────────────
// The body below CAN NEVER PASS, not even after the model is fixed, because its two halves assert
// opposite rules:
//
//   * assertion (1) calls `.expect("serialization currently succeeds")` on a `Point` whose
//     `z = Some(f32::INFINITY)` and then asserts the round trip preserved infinity. JSON cannot spell
//     infinity, so there is no value the round trip could preserve. Today the `.expect` succeeds and
//     the `assert_eq!` fails; once a serialize-time guard lands, the `.expect` itself panics.
//   * assertion (2) already states the correct rule — serialization must ERROR on a non-finite float.
//
// So the guard's implementer must REWRITE assertion (1) to
//     assert!(serde_json::to_string(&point).is_err())
// so both halves state the same refuse-don't-degrade rule for `Option<f32>` and bare `f32` alike.
// Do not "fix" this by relaxing assertion (2); the producer, not the consumer, is who must be told.
#[test]
#[ignore = "OUT OF SCOPE for the ADR 07 audit — real model defect, deferred to the finite-float \
            guard deliverable: a non-finite f32 is written as JSON null, so Point::z reloads as None \
            and silently loses its value instead of refusing (C4, ADR 07 §5.4). NOTE: this test body \
            cannot pass even after the guard lands — see the TRAP comment above; assertion (1) must \
            be rewritten to assert serialization ERRORS."]
fn non_finite_floats_must_not_degrade_silently() {
    // JSON cannot spell infinity or NaN, and serde_json's answer is to write `null`. The kernel
    // model has five float fields — `Point::x/y/z`, `Predicate::AtLocation::radius`,
    // `Predicate::CooldownCmp::secs`, `Predicate::ItemStatCmp::value` — and none of them guards
    // against a non-finite value on the way out. Two distinct failures follow.
    //
    // 1. `Option<f32>`: `Some(non-finite)` is written as `null` and read back as `None`. That is a
    //    silent, lossless-looking degradation of exactly the kind C4 (§5.4) forbids — and `Point::z`
    //    is the field §5.7 says the compiler fills from the navmesh, i.e. from a probe that can
    //    plausibly answer with a non-finite value.
    // 2. Bare `f32`: `NaN` is written as `null` and then fails to load ("invalid type: null"). The
    //    refusal is correct, but it happens at the *consumer*. The producer wrote an unloadable
    //    artifact and was told nothing.
    //
    // The fix is not this file's to make, and the model already has the precedent for it: the
    // `magic` codec (§6.2.5) errors on serialization when the in-memory value is wrong rather than
    // emitting an artifact that cannot load. A finite-float check would follow that pattern.
    let point = Point {
        map_id: 1439,
        x: 1.0,
        y: 2.0,
        z: Some(f32::INFINITY),
    };
    let encoded = serde_json::to_string(&point).expect("serialization currently succeeds");
    let reloaded: Point = serde_json::from_str(&encoded).expect("and the result currently loads");
    assert_eq!(
        reloaded, point,
        "C4 (ADR 07 §5.4): `Point::z = Some(non-finite)` was written as {encoded} and came back as \
         `None`. The value was lost and nothing failed."
    );

    let not_a_number = Point {
        map_id: 1439,
        x: f32::NAN,
        y: 2.0,
        z: None,
    };
    assert!(
        serde_json::to_string(&not_a_number).is_err(),
        "C4 (ADR 07 §5.4): serializing a non-finite bare coordinate produced an artifact that \
         cannot be read back. The producer must be told at write time, as the `magic` codec is."
    );
}
