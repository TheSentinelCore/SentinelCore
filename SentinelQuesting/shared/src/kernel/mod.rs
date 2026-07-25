//! The **kernel artifact** model — ADR `07_RUNTIME_PROFILE_SCHEMA`.
//!
//! This is the compile-before-execute artifact described by ADR 07, *"RestedXP ingest to
//! kernel-executable artifact"*, and executed by the kernel of ADR 08. It is a **second, separate**
//! model that coexists with [`crate::runtime`]: that module is the older, still-live ADR-05 model
//! consumed today by `sentinel-compiler` and the Lua runtime, and it has its own type also called
//! `RuntimeProfile`. Neither model is derived from the other here.
//!
//! # What the model guarantees
//!
//! * **One condition language** (C1, §5.1). [`Predicate`] is the only boolean-valued construct in
//!   this module tree. Its evaluation is tri-state, and what happens on `Unknown` is declared per
//!   task by [`UnknownPolicy`] (§5.1.2).
//! * **Static gates are gone** (C2, §5.2). Class, race and faction survive only in
//!   [`Archetype`] as provenance, because the Sylvanas API cannot answer "am I Alliance?".
//! * **Concurrency is channels and bands** (C3, §5.3). [`Lifetime`] and [`CompletionSource`] are
//!   independent fields, and [`ResumeCursor`] pins resume granularity to
//!   `(task, op_index, waypoint, loop_iter)`.
//! * **Fail-closed** (C4, §5.4). Every struct here is `#[serde(deny_unknown_fields)]` and every
//!   enum the kernel dispatches on is adjacently tagged.
//! * **Delegate, don't reimplement** (C5, §5.5) via [`Op::Delegate`] and [`DelegatePayload`].
//! * **Combat is a policy** (C6, §5.6) — [`CombatPolicy`], profile default plus per-task override.
//! * **The engine owns pathfinding** (C7, §5.7) — [`RouteKind`] discriminates a destination from a
//!   baked circuit.
//!
//! # Wire shape
//!
//! Two rules, and they are not interchangeable:
//!
//! 1. **Enums the kernel dispatches on are adjacently tagged**, `#[serde(tag = "type", content =
//!    "payload")]`: [`Lifetime`], [`CompletionSource`], [`UnknownPolicy`], [`Op`], [`RouteKind`],
//!    [`GossipPolicy`], [`DelegatePayload`], [`CombatStance`], [`GroupExpectation`], [`Cmp`],
//!    [`Predicate`]. The rule is **role, not arity** — [`CombatStance`], [`GroupExpectation`] and
//!    [`Cmp`] carry no payload on any variant and are tagged anyway, because a reader dispatches on
//!    them and a bare string would leave nowhere to add a payload later without a wire break.
//!    This is C4, and it is not theoretical: this repository shipped an
//!    *externally* tagged condition enum, and every non-unit condition consequently fell through to
//!    a fail-open `true` in Lua, so condition gating silently stopped gating.
//! 2. **Scalar vocabulary serializes as a bare string**: [`Class`], [`Race`], [`Faction`],
//!    [`Expansion`], [`Allegiance`], [`ProfileMode`], [`Channel`], [`TravelMode`], [`AreaKind`],
//!    [`UnitRef`], [`SkillLine`], [`Standing`], [`CooldownKind`], [`ItemStat`], [`BehaviorId`],
//!    [`VendorMode`], [`FlightMode`], [`HearthMode`], [`BankMode`], [`StableMode`],
//!    [`CorpseIntent`]. §7.3.3 forces this: it contains `"class": "Hunter"`, `"expansion": "Tbc"`,
//!    `"mode": "Ground"`, `"kind": "SubArea"`, `"channels": ["MOVEMENT"]`. [`Channel`] alone is
//!    SCREAMING_SNAKE, per §7.2.
//!
//! ## Unit variants: emitted absent, accepted either way
//!
//! Serde's canonical adjacent tagging **omits** the content field for a unit variant, so this model
//! emits `{"type": "Exclusive"}`. §7.3.3 originally printed `{"type": "Exclusive", "payload": null}`
//! instead; the R1 model audit ruled serde's form authoritative (§9 item 23) and rewrote §7.3.3 and
//! the worked-example fixture to match, rather than adding eleven hand-written `Serialize` impls to
//! reproduce a `null` that §7.2's `$defs` never required. The ADR moved; the model did not.
//!
//! Both spellings are still **accepted** on the way in, because artifacts compiled against the
//! pre-audit text carry the explicit `null` and must keep loading. Nothing is lost either way:
//! §7.2 requires only `["type"]`, and in Lua an absent key and a `null` key are both `nil`. The
//! `unit_variants_omit_payload_and_accept_null` test below pins both halves so the asymmetry cannot
//! drift into a surprise.
//!
//! # Scope
//!
//! This module is the **model only**: types, their wire shape, and the tests that pin both. It
//! deliberately contains no lowering from [`crate::authoring`], no offset-indexed container, no
//! digest computation, and no loader. Those are separate work.

pub mod ids;
pub mod op;
pub mod predicate;
pub mod profile;
pub mod task;

pub use ids::{hex32, magic, ItemId, QuestId, SpellId, TaskId, MAGIC, MAGIC_STR};
pub use op::{
    BankMode, BehaviorId, CorpseIntent, DelegatePayload, FlightMode, GossipPolicy, HearthMode,
    LootRule, NpcRef, Op, Point, Route, RouteKind, StableMode, TravelMode, VendorMode,
};
pub use predicate::{AreaKind, Cmp, CooldownKind, ItemStat, Predicate, SkillLine, Standing, UnitRef};
pub use profile::{
    Allegiance, Archetype, Class, CombatPolicy, CombatStance, ContentIntegrity, Expansion, Faction,
    GroupExpectation, GuideMeta, ProfileDefaults, ProfileMode, Race, RuntimeProfile,
    SCHEMA_VERSION,
};
pub use task::{
    Channel, CompletionSource, Lifetime, ResumeCursor, SourceSpan, Task, UnknownPolicy,
};

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// C4: enums the kernel dispatches on must be adjacently tagged. An externally tagged
    /// `{"QuestInLog": {"id": 983}}` is the shape that made gating fail open in Lua.
    #[test]
    fn predicates_are_adjacently_tagged() {
        let predicate = Predicate::QuestInLog { id: 983 };
        assert_eq!(
            serde_json::to_value(&predicate).unwrap(),
            json!({ "type": "QuestInLog", "payload": { "id": 983 } })
        );

        let nested = Predicate::And(vec![
            Predicate::QuestObjective {
                id: 2118,
                index: 1,
                need: 1,
            },
            Predicate::Not(Box::new(Predicate::QuestTurnedIn { id: 983 })),
        ]);
        assert_eq!(
            serde_json::to_value(&nested).unwrap(),
            json!({
                "type": "And",
                "payload": [
                    { "type": "QuestObjective", "payload": { "id": 2118, "index": 1, "need": 1 } },
                    { "type": "Not", "payload": { "type": "QuestTurnedIn", "payload": { "id": 983 } } }
                ]
            })
        );
    }

    /// Serde omits `payload` for unit variants. §7.3.3 used to print it as an explicit `null`; the
    /// audit moved the ADR to serde's form (§9 item 23), but artifacts written against the old text
    /// still carry it, so both must load. The emitted form is pinned so the choice stays visible
    /// rather than accidental.
    #[test]
    fn unit_variants_omit_payload_and_accept_null() {
        assert_eq!(
            serde_json::to_value(Lifetime::Exclusive).unwrap(),
            json!({ "type": "Exclusive" })
        );
        let from_null: Lifetime =
            serde_json::from_value(json!({ "type": "Exclusive", "payload": null })).unwrap();
        assert_eq!(from_null, Lifetime::Exclusive);
        let from_absent: Lifetime = serde_json::from_value(json!({ "type": "Exclusive" })).unwrap();
        assert_eq!(from_absent, Lifetime::Exclusive);

        let stance: CombatStance =
            serde_json::from_value(json!({ "type": "Aggressive", "payload": null })).unwrap();
        assert_eq!(stance, CombatStance::Aggressive);
    }

    /// Newtype variants put the value directly under `payload`: §7.3.3 task 6 has
    /// `"completion": { "type": "LinkedTo", "payload": 7 }`.
    #[test]
    fn newtype_variants_carry_a_bare_payload() {
        assert_eq!(
            serde_json::to_value(CompletionSource::LinkedTo(7)).unwrap(),
            json!({ "type": "LinkedTo", "payload": 7 })
        );
        assert_eq!(
            serde_json::to_value(GossipPolicy::Index(0)).unwrap(),
            json!({ "type": "Index", "payload": 0 })
        );
    }

    /// Scalar vocabulary must stay unwrapped, or §7.3.3 stops parsing.
    #[test]
    fn scalar_vocabulary_serializes_as_bare_strings() {
        assert_eq!(serde_json::to_value(Class::Hunter).unwrap(), json!("Hunter"));
        assert_eq!(serde_json::to_value(Race::NightElf).unwrap(), json!("NightElf"));
        assert_eq!(serde_json::to_value(Faction::Alliance).unwrap(), json!("Alliance"));
        assert_eq!(serde_json::to_value(Expansion::Tbc).unwrap(), json!("Tbc"));
        assert_eq!(
            serde_json::to_value(ProfileMode::SpeedRoute).unwrap(),
            json!("SpeedRoute")
        );
        assert_eq!(serde_json::to_value(TravelMode::Ground).unwrap(), json!("Ground"));
        assert_eq!(serde_json::to_value(AreaKind::SubArea).unwrap(), json!("SubArea"));
        assert_eq!(serde_json::to_value(BehaviorId::FlightPath).unwrap(), json!("FlightPath"));
    }

    /// §7.2 spells the channels SCREAMING_SNAKE.
    #[test]
    fn channels_are_screaming_snake_case() {
        assert_eq!(
            serde_json::to_value(vec![Channel::Movement, Channel::Interaction]).unwrap(),
            json!(["MOVEMENT", "INTERACTION"])
        );
        let round_trip: Channel = serde_json::from_value(json!("TARGETING")).unwrap();
        assert_eq!(round_trip, Channel::Targeting);
    }

    /// C4 refuse-don't-degrade, at both levels: an unknown key inside a variant payload and an
    /// unknown key beside `type`/`payload`.
    #[test]
    fn unknown_fields_are_refused() {
        assert!(serde_json::from_value::<Predicate>(
            json!({ "type": "QuestInLog", "payload": { "id": 983, "bogus": 1 } })
        )
        .is_err());
        assert!(serde_json::from_value::<Predicate>(
            json!({ "type": "QuestInLog", "payload": { "id": 983 }, "bogus": 1 })
        )
        .is_err());
        assert!(serde_json::from_value::<SourceSpan>(
            json!({ "file": "A-11-23.lua", "line_start": 211, "line_end": 237, "bogus": 1 })
        )
        .is_err());
    }

    /// The magic is a string on the wire and only `"SNTL"` loads.
    #[test]
    fn magic_is_a_string_and_rejects_impostors() {
        #[derive(serde::Serialize, serde::Deserialize, Debug, PartialEq)]
        struct Holder {
            #[serde(with = "magic")]
            magic: [u8; 4],
        }
        assert_eq!(
            serde_json::to_value(Holder { magic: MAGIC }).unwrap(),
            json!({ "magic": "SNTL" })
        );
        assert!(serde_json::from_value::<Holder>(json!({ "magic": "SNTL" })).is_ok());
        assert!(serde_json::from_value::<Holder>(json!({ "magic": "LTNS" })).is_err());
        assert!(serde_json::from_value::<Holder>(json!({ "magic": "SNTLX" })).is_err());
    }

    /// Digests are lowercase 64-character hex on the wire, and nothing else loads.
    #[test]
    fn content_integrity_hash_is_lowercase_hex() {
        let integrity = ContentIntegrity {
            content_hash: [0xab; 32],
            world_source: "tbcmangos.sqlite".to_owned(),
            world_build: "sha256:deadbeef; quest_template=6599".to_owned(),
        };
        let value = serde_json::to_value(&integrity).unwrap();
        assert_eq!(value["content_hash"], json!("ab".repeat(32)));
        assert_eq!(
            serde_json::from_value::<ContentIntegrity>(value).unwrap(),
            integrity
        );

        for bad in ["AB".repeat(32), "ab".repeat(31), "zz".repeat(32)] {
            assert!(
                serde_json::from_value::<ContentIntegrity>(json!({
                    "content_hash": bad,
                    "world_source": "tbcmangos.sqlite",
                    "world_build": "x"
                }))
                .is_err(),
                "expected refusal"
            );
        }
    }

    /// §7.3.2 / §8: quest 984 is an exploration objective with no `Req*` columns, so `need == 0`
    /// must survive a round trip untouched.
    #[test]
    fn quest_objective_need_may_be_zero() {
        let predicate = Predicate::QuestObjective {
            id: 984,
            index: 1,
            need: 0,
        };
        let value = serde_json::to_value(&predicate).unwrap();
        assert_eq!(value["payload"]["need"], json!(0));
        assert_eq!(
            serde_json::from_value::<Predicate>(value).unwrap(),
            predicate
        );
    }

    /// P1: the dependency edge is plural. §7.3.3 task 4 carries `"deps": [2, 0]`.
    #[test]
    fn task_deps_are_plural() {
        let task = Task {
            id: 4,
            deps: vec![2, 0],
            blocking: false,
            lifetime: Lifetime::Exclusive,
            completion: CompletionSource::OwnPredicate,
            applies_when: None,
            complete_when: Some(Predicate::And(vec![
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
            ])),
            abort_when: None,
            unknown_policy: UnknownPolicy::Block,
            ops: Vec::new(),
            interact_target: None,
            combat: None,
            loot_filter: Vec::new(),
            serves_quests: vec![2118, 983],
            suppress: Vec::new(),
            jump_to: None,
            source: SourceSpan {
                file: "A-11-23.lua".to_owned(),
                line_start: 265,
                line_end: 268,
            },
        };
        let value = serde_json::to_value(&task).unwrap();
        assert_eq!(value["deps"], json!([2, 0]));
        assert_eq!(value["interact_target"], json!(null));
        assert_eq!(serde_json::from_value::<Task>(value).unwrap(), task);
    }
}
