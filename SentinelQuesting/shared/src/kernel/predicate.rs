//! [`Predicate`] — the single condition language of the kernel artifact (contract C1, ADR
//! `07_RUNTIME_PROFILE_SCHEMA` §5.1).
//!
//! All 31 `TRANSFORM`-to-predicate corpus commands (§4.1) lower into one `Predicate` tree. A
//! [`Task`](crate::kernel::Task) has exactly three predicate slots — `applies_when`,
//! `complete_when`, `abort_when` — and all three hold this type, evaluated by one function. There
//! is deliberately no second boolean-valued construct anywhere in this module tree.
//!
//! `Predicate` and [`Cmp`] carry `#[serde(tag = "type", content = "payload")]` per C4 (§5.4).
//! External tagging is the bug this repository has already shipped once: an externally tagged
//! condition enum made every non-unit variant fall through to a fail-open `true` in Lua, so
//! condition gating silently stopped gating.
//!
//! The supporting scalar vocabularies in this module ([`UnitRef`], [`SkillLine`], [`Standing`],
//! [`CooldownKind`], [`AreaKind`], [`ItemStat`]) are **bare strings** on the wire — they are leaves,
//! not sum types with payloads, and §7.3.3 shows leaf vocabulary unwrapped (`"kind": "SubArea"`).

use serde::{Deserialize, Serialize};

use super::finite;
use super::ids::{ItemId, QuestId, SpellId};

/// Comparison operator, added once so the 15 new predicate variants do not each re-invent
/// threshold parsing (§5.1.1).
///
/// The direct corpus justification is that operators are *authored*: `.itemcount 16321,<1`
/// (`A-1-11-Dwarf-Gnome.lua:631`), `.skill cooking,<50,1` (`A-23-30.lua:1008`),
/// `.cooldown item,6948,>2,1`, `.money <0.0480`. RXPGuides re-parses `<` in ~120 handlers (§3.1);
/// this enum is what avoids that.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum Cmp {
    /// Strictly less than.
    Lt,
    /// Less than or equal.
    Le,
    /// Exactly equal.
    Eq,
    /// Greater than or equal. This is the case the removed `HasItem` variant covered (§5.1.1).
    Ge,
    /// Strictly greater than.
    Gt,
}

/// Which unit an aura test reads (§7.1, `Predicate::AuraPresent`).
///
/// `.aura` (174 uses) never names a unit — every instance is one or more spell ids, optionally
/// `-`-prefixed to negate — so the corpus only ever produces [`UnitRef::Player`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum UnitRef {
    /// `.aura <spell>` (§4.1) — the local player. The only unit the corpus tests.
    Player,
    /// The player's current target.
    // UNVERIFIED: no corpus evidence found. No corpus command produces an aura test against a
    // non-player unit; §7.1 nonetheless types the field as a unit reference rather than pinning it
    // to the player, so the second inhabitant is kept and marked.
    Target,
}

/// Profession / secondary skill line named by `.skill` (507 uses, §4.1).
///
/// These ten are the complete set of distinct first arguments in the corpus: `riding`, `cooking`,
/// `skinning`, `mining`, `herbalism`, `tailoring`, `firstaid`, `enchanting`, `lockpicking`,
/// `engineering`. Readable in-client via `core.spell_book.get_profession_info`, which §5.1.2 notes
/// can answer with a safe default indistinguishable from a real zero — hence
/// [`UnknownPolicy`](crate::kernel::UnknownPolicy).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum SkillLine {
    /// `.skill cooking,…`
    Cooking,
    /// `.skill enchanting,…`
    Enchanting,
    /// `.skill engineering,…`
    Engineering,
    /// `.skill firstaid,…`
    FirstAid,
    /// `.skill herbalism,…`
    Herbalism,
    /// `.skill lockpicking,…`
    Lockpicking,
    /// `.skill mining,…`
    Mining,
    /// `.skill riding,…` — the most common form (`.skill riding,225,1`).
    Riding,
    /// `.skill skinning,…`
    Skinning,
    /// `.skill tailoring,…`
    Tailoring,
}

/// Reputation standing band named by `.reputation` (298 uses, §4.1).
///
/// The corpus supplies exactly these six second arguments — `unfriendly`, `neutral`, `friendly`,
/// `honored`, `revered`, `exalted` (case is inconsistent in the source, e.g. `Friendly`, and is
/// normalised at ingest per §5.10). `hated` and `hostile` never appear and are therefore absent.
///
/// Reputation is **not readable** from the Sylvanas API (§5.8), so
/// [`Predicate::ReputationCmp`] evaluates `Unknown` at runtime and is expected to be paired with
/// [`UnknownPolicy::Block`](crate::kernel::UnknownPolicy::Block).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum Standing {
    /// `.reputation <faction>,unfriendly,…`
    Unfriendly,
    /// `.reputation <faction>,neutral,…`
    Neutral,
    /// `.reputation <faction>,friendly,…`
    Friendly,
    /// `.reputation <faction>,honored,…`
    Honored,
    /// `.reputation <faction>,revered,…`
    Revered,
    /// `.reputation <faction>,exalted,…`
    Exalted,
}

/// Which cooldown table [`Predicate::CooldownCmp`] reads (§5.1.1).
///
/// `.cooldown` (549 uses) has exactly two first arguments in the corpus: `item` (the 443+52+3+3
/// hearthstone instances, `.cooldown item,6948,…`) and `spell` (`.cooldown spell,556,…`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum CooldownKind {
    /// `.cooldown item,<item_id>,…` — e.g. the hearthstone, item 6948.
    Item,
    /// `.cooldown spell,<spell_id>,…` — e.g. spell 556, Astral Recall.
    Spell,
}

/// Granularity of an [`Predicate::InArea`] membership test (§5.1.1).
///
/// `InArea` is the largest single predicate addition by use count (4,906) and covers four commands:
/// `.zone` (1,063) and `.zoneskip` (2,032) produce [`AreaKind::Zone`]; `.subzone` (991) and
/// `.subzoneskip` (820) produce [`AreaKind::SubArea`]. Both carry a numeric AreaTable id — zone
/// *names* never reach the artifact (§5.8).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum AreaKind {
    /// `.zone` / `.zoneskip` — a top-level zone.
    Zone,
    /// `.subzone` / `.subzoneskip` — a sub-area within a zone, as in §7.3.3 task 5 (`"area": 442`).
    SubArea,
}

/// Which property of an equipped item [`Predicate::ItemStatCmp`] compares (§5.1.1).
///
/// `.itemStat` (327 uses) is a gear-upgrade gate on the item currently in a slot. The corpus
/// contains exactly two stat tokens: `QUALITY` and `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum ItemStat {
    /// `QUALITY` — e.g. `.itemStat 18,QUALITY,<7`.
    Quality,
    /// `ITEM_MOD_DAMAGE_PER_SECOND_SHORT` — e.g.
    /// `.itemStat 16,ITEM_MOD_DAMAGE_PER_SECOND_SHORT,<25.6`.
    DamagePerSecond,
}

/// The kernel's only condition type (C1, §5.1) — a nestable AST evaluated by one function.
///
/// Exactly 24 variants: the nine ADR-000 §7.2 baseline variants, plus the 15 additions justified
/// one by one in §5.1.1. There is intentionally **no `HasItem`**: §5.1.1 replaces it with
/// [`Predicate::ItemCount`], of which `HasItem` is the `cmp: Ge` case. Keeping both would be a
/// second way to say one thing.
///
/// Evaluation is tri-state, not boolean (`Truth { True, False, Unknown }`, §5.1.2 / kernel change
/// K2), and what happens on `Unknown` is declared per task by
/// [`UnknownPolicy`](crate::kernel::UnknownPolicy).
///
/// Adjacently tagged per C4; `And`, `Or` and `Not` therefore serialize with their children directly
/// under `payload` (`{"type":"And","payload":[…]}`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum Predicate {
    // ─── ADR-000 §7.2 baseline ───────────────────────────────────────────────────────────────
    /// Conjunction. Emitted when one step carries more than one predicate term — several
    /// `.complete` lines, or a `.complete` alongside an `.isOnQuest`
    /// (`compiler/src/kernel/task_graph.rs::fold_and`, which deliberately does *not* wrap a lone
    /// term). §7.3.3's excerpt contains no `And` and its `tags_used` does not list one; an earlier
    /// revision cited its task 4 as the witness, which the `--XXREQ` fold removed (ADR 07 §9 item
    /// 28).
    And(Vec<Predicate>),
    /// Disjunction. `.isOnQuest` accepts any-of lists of up to 11 quest ids (§4.1).
    Or(Vec<Predicate>),
    /// Negation. Produced by `.isNotOnQuest` (28), `.isQuestNotComplete` (1), `.solo` (13) and the
    /// negating `,1` argument of `.subzoneskip` / `.bindlocation` (§4.1).
    Not(Box<Predicate>),
    /// Objectives met but the quest has not been handed in. `.isQuestComplete` (1,389).
    QuestComplete {
        /// The quest.
        id: QuestId,
    },
    /// A single quest objective's progress. `.complete` (7,218) — the step's completion authority.
    QuestObjective {
        /// The quest.
        id: QuestId,
        /// 1-based objective index, as authored (`.complete 983,1`).
        index: u8,
        /// Required count, baked offline from `quest_template.ReqItemCount*` /
        /// `ReqCreatureOrGOCount*` so the runtime never parses a localized progress string (§7.3.2).
        ///
        /// **`0` is legal and load-bearing.** Quest 984 (`How Big a Threat?`) has no `Req*` columns
        /// populated at all — it is an exploration objective satisfied by area discovery, not by a
        /// count (§7.3.2, §8). A positive-count validation here would make it unsatisfiable.
        need: u32,
    },
    /// Proximity to a pooled waypoint. A distance test, unlike [`Predicate::InArea`].
    AtLocation {
        /// Index into [`RuntimeProfile::waypoint_pool`](crate::kernel::RuntimeProfile::waypoint_pool).
        point: u32,
        /// Arrival radius in yards. Refused at write time if non-finite — see
        /// [`finite`](crate::kernel::finite).
        #[serde(serialize_with = "finite::serialize")]
        #[schemars(with = "f32")]
        radius: f32,
    },
    /// Player level floor. `#level` (22) and the 1-argument `.maxlevel` complement (§5.2).
    ///
    /// Deliberately *not* resolved at compile time even though `#level` looks static: player level
    /// changes during play, and caching it is the RXP `applies()` bug (§5.2).
    LevelAtLeast {
        /// Inclusive minimum level.
        level: u8,
    },
    /// An aura is present on a unit. `.aura` (174).
    AuraPresent {
        /// The aura's spell id.
        spell: SpellId,
        /// Which unit to read.
        on: UnitRef,
    },
    /// A named runtime flag. Carried from ADR-000 §7.2; no corpus command produces one, so the
    /// compiler emits it only for kernel-internal bookkeeping.
    Flag {
        /// Flag name.
        key: String,
    },

    // ─── Additions, each justified in §5.1.1 ─────────────────────────────────────────────────
    /// The quest is in the log. `.isOnQuest` (3,139) → `core.quests.is_on_quest`.
    ///
    /// A third distinct quest state: neither complete nor turned in. Also the gate the compiler
    /// emits for repeatables, because `QuestTurnedIn` is unreliable for dailies (§8).
    QuestInLog {
        /// The quest.
        id: QuestId,
    },
    /// The quest has been handed in. `.isQuestTurnedIn` (1,488) →
    /// `core.quests.is_quest_flagged_completed`.
    ///
    /// Without this a resumed run cannot tell "handed in" from "never taken" (§5.1.1).
    QuestTurnedIn {
        /// The quest.
        id: QuestId,
    },
    /// The quest is obtainable: prerequisites, level and reputation satisfied, not already done.
    /// `.isQuestAvailable` (930). Requires compile-time prerequisite resolution from
    /// `quest_template`.
    QuestAvailable {
        /// The quest.
        id: QuestId,
    },
    /// Bag count of an item, with an operator. `.itemcount` (1,666), `.collect` (3,044),
    /// `.bronzetube` (22) — 4,732 uses in total.
    ///
    /// **Supersedes `HasItem`**, which had no operator; the corpus needs `<1` and `>0`.
    ItemCount {
        /// The item.
        id: ItemId,
        /// Comparison operator, as authored.
        cmp: Cmp,
        /// Right-hand side of the comparison.
        count: u32,
    },
    /// Money test in copper. `.money` (259) — `<0.0480` is gold.silver-copper, normalised offline.
    /// Readable via `core.inventory.get_gold`.
    MoneyCmp {
        /// Comparison operator.
        cmp: Cmp,
        /// Right-hand side, in copper.
        copper: u64,
    },
    /// Profession / secondary skill test. `.skill` (507), e.g. `.skill cooking,<50,1`.
    SkillCmp {
        /// Which skill line.
        line: SkillLine,
        /// Comparison operator.
        cmp: Cmp,
        /// Right-hand side, in skill points.
        value: u16,
    },
    /// Reputation test. `.reputation` (298).
    ///
    /// **Not evaluable client-side** (§5.8). It exists so the compiler can emit what it cannot
    /// pre-resolve and the runtime can fail closed with a named reason instead of failing open.
    ReputationCmp {
        /// MaNGOS faction id (the numeric first argument, e.g. `576`).
        faction: u32,
        /// Standing band named by the second argument.
        standing: Standing,
        /// Comparison operator.
        cmp: Cmp,
        /// Signed reputation value within the band.
        value: i32,
    },
    /// Grind-to-XP objective. `.xp` (2,133). Both corpus forms — `4-420` and `>5,1` — fold into a
    /// level plus a signed offset. Readable via `get_xp` / `get_max_xp`.
    XpAtLeast {
        /// Level the offset is measured against.
        level: u8,
        /// Signed XP offset within that level, e.g. `6760` in §7.3.3 task 4.
        xp_offset: i32,
    },
    /// Cooldown remaining test. `.cooldown` (549), e.g. `item,6948,>2,1`. Hearthstone gating
    /// depends on it.
    CooldownCmp {
        /// Which cooldown table to read.
        kind: CooldownKind,
        /// Item or spell id, depending on `kind`.
        id: u32,
        /// Comparison operator.
        cmp: Cmp,
        /// Right-hand side, in seconds. Refused at write time if non-finite — see
        /// [`finite`](crate::kernel::finite).
        #[serde(serialize_with = "finite::serialize")]
        #[schemars(with = "f32")]
        secs: f32,
    },
    /// Zone or sub-area membership — a **set** test, not a distance test. `.zone`, `.subzone`,
    /// `.zoneskip`, `.subzoneskip` (4,906 uses, the largest single addition).
    InArea {
        /// Numeric AreaTable id. §5.1.1 writes this field as `area_id`; §7.1 and the §7.3.3
        /// fixture both use `area`, and §7.1 is authoritative.
        area: u32,
        /// Zone or sub-area granularity.
        kind: AreaKind,
    },
    /// The hearthstone is bound to this area. `.bindlocation` (557); not expressible otherwise.
    HearthBoundTo {
        /// Numeric AreaTable id. Same `area_id` vs `area` naming note as [`Predicate::InArea`].
        area: u32,
    },
    /// Gear-upgrade gate on the item currently equipped in a slot. `.itemStat` (327).
    ///
    /// §4.1 notes this predicate is *stay-active-while-true*, inverted with respect to `.money`.
    ItemStatCmp {
        /// Equipment slot number as authored (`16`, `17`, `18`, `1`, …), corroborated by sibling
        /// `.equip` lines (§4.1).
        slot: u8,
        /// Which stat to read.
        stat: ItemStat,
        /// Comparison operator.
        cmp: Cmp,
        /// Right-hand side. Refused at write time if non-finite — see
        /// [`finite`](crate::kernel::finite).
        #[serde(serialize_with = "finite::serialize")]
        #[schemars(with = "f32")]
        value: f32,
    },
    /// Party-size test. `.group` (190) and, negated, `.solo` (13). Drives both gating and
    /// [`CombatPolicy::expect_group`](crate::kernel::CombatPolicy::expect_group).
    InGroup {
        /// Comparison operator.
        cmp: Cmp,
        /// Right-hand side, in party members.
        size: u8,
    },
    /// The spell is already known. `.train` in its 2-argument condition form (403 uses); distinct
    /// from [`Predicate::AuraPresent`] (§5.1.1).
    SpellKnown {
        /// The spell.
        spell: SpellId,
    },
    /// Player level ceiling. `.maxlevel` (171).
    ///
    /// A dedicated variant because `Not(LevelAtLeast(n))` is off by one (§5.1.1).
    LevelAtMost {
        /// Inclusive maximum level.
        level: u8,
    },
}
