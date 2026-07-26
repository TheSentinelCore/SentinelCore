//! The `02_DATA_MODEL.md` §23 condition DSL → [`Predicate`] (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.1).
//!
//! The parser is [`crate::condition`]'s, unchanged and unforked: this module supplies only a
//! [`ConditionSink`] — the leaf mapping and the three combinators. That is what keeps
//! `MAX_CONDITION_DEPTH` and `MAX_CONDITION_TOKENS`, which close a network-reachable
//! stack-overflow DoS on the editor's `/compile` endpoint, in one place for both target models.

use sentinel_models::kernel::{AreaKind, Cmp, Predicate, QuestId};

use crate::condition::{as_i32, as_u32, as_u8, parse_with, ConditionParseError, ConditionSink};

use super::LoweringError;

/// Supplies the offline-baked facts a predicate needs but the DSL does not carry.
///
/// `Objective(983,1)` names a quest and a 1-based objective index and *nothing else*. The required
/// count is baked from `quest_template.ReqItemCount*` / `ReqCreatureOrGOCount*` so the runtime never
/// parses a localized progress string (§7.3.2) — and `&Project` does not carry those columns, which
/// is why the lowering takes an injected provider rather than reading them itself.
pub trait QuestMeta {
    /// Required count for one objective.
    ///
    /// `Some(0)` and `None` are **different answers and must stay different**. `Some(0)` is "this
    /// objective needs no count" — quest 984 (`How Big a Threat?`) has no `Req*` columns at all and
    /// is satisfied by area discovery — and §7.3.2 calls that legal and load-bearing. `None` is "the
    /// world database could not answer", which is [`LoweringError::UnknownObjective`]. Collapsing
    /// the second into the first manufactures an exploration objective from a lookup failure, and
    /// the resulting task completes the instant it is evaluated.
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32>;

    /// The item one objective requires, when its requirement *is* an item.
    ///
    /// `quest_template.ReqItemId<index>`, and `None` when that column is zero — the objective is a
    /// creature, a gameobject or an exploration. Quest 983 objective 1 is `ReqItemId1 = 5385`
    /// (Crawler Leg), which §7.3.2 verified and the guide author's own comment corroborates
    /// (`A-11-23.lua:234`, `--Crawler Leg (6)`); quest 2118 objective 1 is a creature and answers
    /// `None`.
    ///
    /// **`None` here does not have to carry the "could not answer" meaning that
    /// [`objective_need`](Self::objective_need)'s does**, and deliberately does not. This is only
    /// ever consulted for a `(quest, index)` pair that `objective_need` has *already* answered for
    /// — the lowering asks in that order, and a provider that could not answer has already failed
    /// the compile with [`LoweringError::UnknownObjective`]. So by the time this is called, the
    /// world database is known to know about the objective, and the only fact left to report is
    /// whether its requirement is an item.
    ///
    /// Feeds [`Task::loot_filter`](sentinel_models::kernel::Task::loot_filter): a task working an
    /// item objective has to keep the item or the objective can never advance (§7.3.3 task 0).
    fn objective_item(&self, quest: QuestId, index: u8) -> Option<u32>;
}

/// Lower a §23 condition expression into a [`Predicate`].
///
/// Unlike the ADR-05 path, which records an `UNMAPPED_CONDITION` diagnostic and substitutes
/// `RuntimeCondition::AlwaysTrue`, this **fails**. The kernel's 24 `Predicate` variants contain no
/// always-true by design, and the two alternatives to failing are both fail-open: substituting a
/// permissive predicate, or omitting the leaf — which leaves a well-formed-looking tree gating on
/// less than the author wrote.
pub fn lower_predicate(expression: &str, meta: &dyn QuestMeta) -> Result<Predicate, LoweringError> {
    match parse_with(expression, &KernelSink { meta }) {
        Ok(predicate) => Ok(predicate),
        Err(LeafError::Objective { quest, index }) => {
            Err(LoweringError::UnknownObjective { quest, index })
        }
        Err(LeafError::Parse(err)) => Err(LoweringError::UnmappablePredicate {
            expression: expression.to_owned(),
            reason: err.to_string(),
        }),
    }
}

/// Sink-local error. The parser reports [`ConditionParseError`]; the leaf mapping additionally has
/// a *structured* failure — an objective the provider could not answer — that would be lost if it
/// were flattened into a string on the way out.
enum LeafError {
    Parse(ConditionParseError),
    Objective { quest: QuestId, index: u8 },
}

impl From<ConditionParseError> for LeafError {
    fn from(err: ConditionParseError) -> Self {
        LeafError::Parse(err)
    }
}

struct KernelSink<'a> {
    meta: &'a dyn QuestMeta,
}

impl ConditionSink for KernelSink<'_> {
    type Output = Predicate;
    type Error = LeafError;

    fn any(&self, terms: Vec<Predicate>) -> Predicate {
        Predicate::Or(terms)
    }

    fn all(&self, terms: Vec<Predicate>) -> Predicate {
        Predicate::And(terms)
    }

    /// `NOT ItemCount(item,n)` folds into the operator instead of wrapping it.
    ///
    /// The §23 DSL has only an at-least primitive, so `item_count_dsl` encodes `.itemcount 16321,<1`
    /// as `NOT ItemCount(16321,1)`. The kernel has [`Cmp`], and `NOT (count >= n)` *is* `count < n`,
    /// exactly. Emitting `Not(ItemCount { cmp: Ge, .. })` would be a second way to spell one thing,
    /// which §5.1.1 is explicit about avoiding — it is the reason `HasItem` was removed.
    ///
    /// Only `Ge` folds, because only `Ge` can appear: a leaf `ItemCount` is always the at-least
    /// primitive. Anything else negates by wrapping.
    fn not(&self, inner: Predicate) -> Predicate {
        match inner {
            Predicate::ItemCount { id, cmp: Cmp::Ge, count } => {
                Predicate::ItemCount { id, cmp: Cmp::Lt, count }
            }
            other => Predicate::Not(Box::new(other)),
        }
    }

    fn leaf(&self, name: &str, args: &[i64]) -> Result<Predicate, LeafError> {
        Ok(match (name, args) {
            // The three quest states are distinct and all three are needed: a resumed run cannot
            // tell "handed in" from "never taken" without QuestTurnedIn, nor "objectives met" from
            // "still working" without QuestComplete (§5.1.1).
            ("QuestAccepted", [id]) => Predicate::QuestInLog { id: as_u32(*id, "quest id")? },
            ("QuestCompleted", [id]) => Predicate::QuestComplete { id: as_u32(*id, "quest id")? },
            ("QuestRewarded", [id]) => Predicate::QuestTurnedIn { id: as_u32(*id, "quest id")? },
            // §5.2 keeps the level gate a *runtime* predicate even though `#level` looks static:
            // player level changes during play, and caching it is the RXP `applies()` bug.
            ("LevelAtLeast", [level]) => {
                Predicate::LevelAtLeast { level: as_u8(*level, "level")? }
            }
            // `.xp <level>±<offset>` — one statement, `total_xp >= start_of_level(level) + offset`,
            // and the sign is the author's. `A-11-23.lua:271` writes `+6760` of level 10's 7,600 and
            // `A-1-11-Draenei.lua:141` writes `-420` of level 4's 1,400; §5.1.1 types the field
            // `i32` for exactly that pair. The importer used to split on `+` and keep only the
            // level, which is why this arm exists at all — a `LevelAtLeast` here silently discards
            // 89% of a level's grind.
            //
            // The offset-free `.xp N` is this predicate with `xp_offset: 0`, and it deliberately
            // still arrives as `LevelAtLeast(N)`: see `project_builder::xp_gate_dsl`.
            ("XpAtLeast", [level, offset]) => Predicate::XpAtLeast {
                level: as_u8(*level, "level")?,
                xp_offset: as_i32(*offset, "xp offset")?,
            },
            // `.subzone <area>` — a set test on an **AreaTable id**, never a UiMapID.
            //
            // The two numeric spaces overlap (`AreaTable` 1443 is `The Slag Pit` in Searing Gorge;
            // `ZONE_TABLE` 1443 is the Desolace UiMapID on another continent), so resolving this
            // payload through `sentinel_models::zone::zone_map_for` yields a plausible answer in the
            // wrong place instead of an error. Nothing on this path may consult that table —
            // `kernel_authored_predicates.rs::a_subzone_id_that_is_also_a_ui_map_id_is_not_translated`
            // pins it.
            //
            // `AreaKind` records **which command was authored**, not `AreaTable`'s parent column:
            // 135 of the 991 `.subzone` uses name an area whose parent is 0 (instance entrances such
            // as `.subzone 209`, Shadowfang Keep), so a parent-derived kind would disagree with the
            // author on every one of them. There is no `InZone` arm because no corpus `.zone` line
            // supplies an AreaTable id to put in one — see the test module below.
            ("InSubArea", [area]) => Predicate::InArea {
                area: as_u32(*area, "area id")?,
                kind: AreaKind::SubArea,
            },
            ("ItemCount", [item, n]) => Predicate::ItemCount {
                id: as_u32(*item, "item id")?,
                cmp: Cmp::Ge,
                count: as_u32(*n, "count")?,
            },
            // There is deliberately no `HasItem` arm. §5.1.1 removed the variant from the kernel
            // model as the `cmp: Ge, count: 1` case of `ItemCount`, and the ADR-05 sink has no arm
            // for the name either, so accepting it here would make this sink strictly more
            // permissive than the one it shares a parser with — for an input nothing produces. See
            // `tests::has_item_is_refused_by_both_sinks` for the three greps that establish that.
            ("Objective", [quest, index]) => {
                let quest = as_u32(*quest, "quest id")?;
                let index = as_u8(*index, "objective index")?;
                let need = self
                    .meta
                    .objective_need(quest, index)
                    .ok_or(LeafError::Objective { quest, index })?;
                Predicate::QuestObjective { id: quest, index, need }
            }
            (other, _) => {
                return Err(LeafError::Parse(ConditionParseError(format!(
                    "unknown predicate '{other}' with {} argument(s)",
                    args.len()
                ))))
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::{lower_predicate, QuestMeta};
    use crate::condition::parse_condition;
    use crate::kernel::LoweringError;
    use sentinel_models::kernel::QuestId;

    struct NoMeta;

    impl QuestMeta for NoMeta {
        fn objective_need(&self, _quest: QuestId, _index: u8) -> Option<u32> {
            None
        }

        /// Never reached: `objective_need` refuses first, and the lowering asks in that order.
        fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
            None
        }
    }

    /// The two sinks share one parser, so they must share one accepted-leaf vocabulary. `HasItem` is
    /// the only name that could have differed, and it does not.
    ///
    /// It is **not reachable input**. Three greps, each of which refutes the claim that it is:
    ///
    /// 1. `rg HasItem compiler/src/condition.rs` → nothing. [`RuntimeConditionSink::leaf`] has no
    ///    `HasItem` arm, so the ADR-05 parser refuses the name as an unknown predicate — the editor's
    ///    `/compile` reaches a sink only through `parse_condition`, from the
    ///    `ActionPayload::Condition` arm of [`crate::Compiler::compile`].
    /// 2. `rg 'HasItem' importer/src/` → nothing. No DSL emitter produces the string.
    /// 3. `rg 'RuntimeCondition::HasItem'` → nothing.
    ///    [`sentinel_models::runtime::RuntimeCondition::HasItem`] is declared and never constructed.
    ///
    /// So a `HasItem` arm here would accept a leaf the ADR-05 sink rejects, for an input nothing can
    /// produce — and §5.1.1 removed the variant from the kernel model outright
    /// (`shared/tests/kernel_wire_shape.rs::…has_item…` refuses the tag at load). Both sinks refuse
    /// it; that symmetry is what this pins.
    #[test]
    fn has_item_is_refused_by_both_sinks() {
        let kernel = lower_predicate("HasItem(5385)", &NoMeta);
        assert!(
            matches!(kernel, Err(LoweringError::UnmappablePredicate { .. })),
            "the kernel sink must refuse `HasItem`, exactly as the ADR-05 sink does. got: {kernel:?}"
        );

        let adr_05 = parse_condition("HasItem(5385)");
        assert!(
            adr_05.is_err(),
            "`RuntimeConditionSink::leaf` has no `HasItem` arm; if this ever passes the asymmetry \
             moved rather than closed. got: {adr_05:?}"
        );

        // The sanctioned spelling, on both sides: §5.1.1 replaced `HasItem` with the `cmp: Ge,
        // count: 1` case of `ItemCount`, and that one both sinks accept.
        assert!(
            lower_predicate("ItemCount(5385,1)", &NoMeta).is_ok(),
            "`ItemCount(item,1)` is the sanctioned replacement and must still lower"
        );
        assert!(parse_condition("ItemCount(5385,1)").is_ok());
    }

    /// The two sinks must both accept `XpAtLeast`, and for opposite reasons.
    ///
    /// The kernel sink accepts it because that is where the offset lands. The ADR-05 sink accepts it
    /// because refusing it would make `Compiler::compile` record `UNMAPPED_CONDITION` and fail open
    /// to `AlwaysTrue` on 56 corpus lines — an always-true *completion* gate, i.e. a grind step that
    /// finishes before it starts. It maps to `LevelAtLeast`, which is exactly what those lines
    /// already produced on that path, and `condition.rs`'s arm says so at length.
    #[test]
    fn xp_at_least_is_accepted_by_both_sinks_and_only_one_keeps_the_offset() {
        assert_eq!(
            lower_predicate("XpAtLeast(10,6760)", &NoMeta).unwrap(),
            sentinel_models::kernel::Predicate::XpAtLeast { level: 10, xp_offset: 6760 }
        );
        assert_eq!(
            lower_predicate("XpAtLeast(4,-420)", &NoMeta).unwrap(),
            sentinel_models::kernel::Predicate::XpAtLeast { level: 4, xp_offset: -420 },
            "the sign must survive tokenisation; `-` is a literal sign in this grammar"
        );
        assert!(
            parse_condition("XpAtLeast(10,6760)").is_ok(),
            "the ADR-05 sink must map it rather than fail open on a completion gate"
        );
    }

    /// A negative may only appear where a signed field takes it.
    ///
    /// Widening the parser's arguments to `i64` is what let `-420` through, and the risk of that
    /// change is that every other leaf silently gained a meaning for negatives. `as_u32` / `as_u8`
    /// are what stop it, and this is the test that they are actually in the path.
    #[test]
    fn a_negative_argument_is_refused_everywhere_it_cannot_be_held() {
        for expression in ["QuestAccepted(-1)", "LevelAtLeast(-3)", "ItemCount(-5385,1)"] {
            assert!(
                lower_predicate(expression, &NoMeta).is_err(),
                "`{expression}` must not lower: none of those fields is signed"
            );
            assert!(parse_condition(expression).is_err(), "`{expression}`, ADR-05 sink");
        }
    }

    /// There is no `InZone` arm, and its absence is a measurement rather than an oversight.
    ///
    /// `AreaKind::Zone` is a real vocabulary member and `.zone` is the command that means it — but
    /// over the whole corpus, 1,037 of 1,063 `.zone` uses name the zone in words
    /// (`.zone Redridge Mountains`), and 25 of the remaining 26 carry a UiMapID that `AreaTable.dbc`
    /// does not contain (`.zone 1415` is `Azeroth`/`Eastern Kingdoms`). The 26th is `.zone 721,2`,
    /// the two-argument form whose second field the corpus never explains. So there is no `.zone`
    /// line anywhere that hands the compiler a bare AreaTable id, and an `InZone` arm would exist
    /// only to be fed the wrong id space — the failure mode `InSubArea`'s own doc comment describes.
    ///
    /// This mirrors `has_item_is_refused_by_both_sinks`: a sink arm for an input nothing produces is
    /// how the two sinks drift apart.
    #[test]
    fn in_zone_is_refused_by_both_sinks() {
        assert!(
            matches!(
                lower_predicate("InZone(1415)", &NoMeta),
                Err(LoweringError::UnmappablePredicate { .. })
            ),
            "nothing emits `InZone`; adding an arm needs a `.zone` line that supplies an AreaTable \
             id, and the corpus has none"
        );
        assert!(parse_condition("InZone(1415)").is_err());
    }
}
