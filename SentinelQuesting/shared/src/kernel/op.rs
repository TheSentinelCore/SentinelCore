//! [`Op`] — the ordered operations inside a [`Task`](crate::kernel::Task), plus navigation
//! ([`Route`], [`Point`]) and behaviour delegation ([`DelegatePayload`]).
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 for the shapes, §5.5 (C5) for delegation,
//! §5.7 (C7) for navigation.
//!
//! Two design rules are visible here and are the point of the module:
//!
//! * **Step-as-container.** A task's `ops` are ordered and heterogeneous — travel, then use an
//!   item, then turn in — instead of one action per step (§7.1, §7.3.3 task 2 and task 7).
//! * **Delegate, don't reimplement** (C5). Eleven commands (4,210 instances) become
//!   [`Op::Delegate`] against a named kernel behaviour rather than a bespoke op each (§5.5).
//!
//! Tagging follows C4 (§5.4): [`Op`], [`RouteKind`], [`GossipPolicy`] and [`DelegatePayload`] are
//! adjacently tagged because they carry payloads and are dispatched on in Lua; the scalar mode
//! vocabularies ([`TravelMode`], [`VendorMode`], …) are bare strings, as §7.3.3 shows
//! (`"mode": "Ground"`).

use serde::{Deserialize, Serialize};

use super::finite;
use super::ids::{ItemId, QuestId, SpellId};

/// A world coordinate in the profile's shared waypoint pool (§5.7, §7.1).
///
/// Both corpus coordinate systems — `zone,x,y[,z]` and the zone-name form — normalise to **world
/// coordinates** offline. The runtime never converts zone percentages to world space: it has no
/// reliable table for it, and Sylvanas zone coordinates are percentage-based with no Z.
///
/// `z` is `Option` because the corpus never supplies it. The compiler fills it from the navmesh
/// where it can and leaves `None` otherwise, letting the engine ground-snap (§5.7).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Point {
    /// Map id. `1439` is Darkshore in §7.3.
    pub map_id: u32,
    /// World X. Refused at write time if non-finite — see [`finite`].
    #[serde(serialize_with = "finite::serialize")]
    #[schemars(with = "f32")]
    pub x: f32,
    /// World Y. Refused at write time if non-finite — see [`finite`].
    #[serde(serialize_with = "finite::serialize")]
    #[schemars(with = "f32")]
    pub y: f32,
    /// World Z, when the compiler could resolve it.
    ///
    /// The slot the [`finite`] guard exists for: `Some(non-finite)` would serialize to `null` and
    /// reload as `None`, losing the value with nothing failing.
    #[serde(serialize_with = "finite::serialize_option")]
    #[schemars(with = "Option<f32>")]
    pub z: Option<f32>,
}

/// A resolved creature reference: entry id plus the name it is expected to have (§5.4.1, §5.8).
///
/// `expect_name` is what makes server-content drift *detectable*. `content_hash` cannot be checked
/// against the server — no API exposes world-database identity — so the runtime instead does a
/// **first-touch probe**: the first time a task interacts with entry *N*, it compares the observed
/// unit name against `expect_name` and fails the task with a named reason on mismatch. A wrong
/// entry id is not recoverable by retrying (§5.4.1).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct NpcRef {
    /// MaNGOS `creature_template.entry`, e.g. `2231` for Pygmy Tide Crawler (§7.3.2).
    pub entry: u32,
    /// Name expected at that entry, for the first-touch probe.
    pub expect_name: String,
    /// Optional index into
    /// [`RuntimeProfile::waypoint_pool`](crate::kernel::RuntimeProfile::waypoint_pool) recording
    /// where the NPC was authored to stand.
    pub pos: Option<u32>,
}

/// How the engine should treat a route's points (C7, §5.7).
///
/// The corpus contains both destinations and baked routes and they are **not** interchangeable, so
/// the artifact carries both and discriminates them here.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum RouteKind {
    /// A single point; the engine paths there freely. The 16,231 three-argument `.goto` lines.
    Destination,
    /// Ordered points the engine may smooth between. A run of `.goto` / `.waypoint` in a non-loop
    /// task.
    Corridor,
    /// Ordered points, cycled — **do not smooth away**. `#loop` (1,661).
    ///
    /// The decisive witness is `A-11-23.lua:215-231`, where the last `.waypoint` is byte-identical
    /// to the first `.goto`: a navmesh asked to path from A to A returns a zero-length path and
    /// cannot know the intent is to walk the loop repeatedly to farm respawns. The route *is* the
    /// objective (§5.7).
    Circuit {
        /// Whether the last point connects back to the first.
        close: bool,
    },
}

/// Which movement medium a route demands (§7.1: `Any | Ground | Air`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum TravelMode {
    /// `.goto` (38,087) / `.waypoint` (593) — the engine picks.
    Any,
    /// `.groundgoto` (114) — forces ground travel where a flying line fails; it exists precisely to
    /// override the engine's preferred line through mountain paths, caves and stairs (§5.7).
    Ground,
    /// `.flygoto` (1) — the airborne counterpart of `.groundgoto`.
    Air,
}

/// A movement instruction: a kind, a medium, and indices into the profile's shared waypoint pool
/// (§7.1).
///
/// Storing indices rather than coordinates is what lets tasks share points. Note that R1 does not
/// build the pool: §2.6 and §8 specify that the *compiler* deduplicates the duplicated coordinate
/// triples on the way in — 4,190 distinct ones across the corpus, measured — and that lowering is
/// out of scope here (see R2).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Route {
    /// Destination, corridor, or circuit.
    pub kind: RouteKind,
    /// Required movement medium.
    pub mode: TravelMode,
    /// Indices into
    /// [`RuntimeProfile::waypoint_pool`](crate::kernel::RuntimeProfile::waypoint_pool), in order.
    pub points: Vec<u32>,
    /// Arrival radius per point, in yards. Parallel to `points`.
    pub radii: Vec<u16>,
}

/// How to handle an NPC's gossip window during [`Op::Interact`] (§7.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum GossipPolicy {
    /// Leave the window alone.
    None,
    /// `.skipgossip` (282) — advance through single-option gossip automatically. A modifier on the
    /// interaction, not an action of its own (§4.1).
    AutoAdvance,
    /// `.gossip <npc>,<index>` (23) — pick an option by its position in the list.
    Index(u8),
    /// `.gossipoption <id>` (7) — pick an option by its option id.
    OptionId(u32),
}

/// A kernel behaviour plugin that [`Op::Delegate`] hands work to, and that
/// [`Task::suppress`](crate::kernel::Task::suppress) can switch off (§5.5, §5.9 K3).
///
/// Five of these — [`Trainer`](Self::Trainer), [`FlightPath`](Self::FlightPath),
/// [`Hearth`](Self::Hearth), [`Bank`](Self::Bank), [`Stable`](Self::Stable) — **do not exist in
/// ADR-000 §3.2** and are listed as required kernel changes (K3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum BehaviorId {
    /// `behavior.vendor` — `.vendor` (385). Needs a `Buy` mode it does not currently have (K4).
    Vendor,
    /// `behavior.trainer` — `.train` 1-argument form (1,250) and `.trainer` (469). New (K3).
    Trainer,
    /// `behavior.flightpath` — `.fly` (741) and `.fp` (199). New (K3).
    FlightPath,
    /// `behavior.hearth` — `.hs` (382) and `.home` (186). New (K3).
    Hearth,
    /// `behavior.bank` — `.bankwithdraw` (53) and `.bankdeposit` (23). New (K3).
    Bank,
    /// `behavior.stable` — `.stable` (42). New (K3).
    Stable,
    /// `behavior.corpse` — exists in ADR-000 §3.2, but `.deathskip` (77) needs the new `intent`
    /// capability (K5). Also the single value `#ignorecorpse` (1) puts in
    /// [`Task::suppress`](crate::kernel::Task::suppress).
    Corpse,
}

/// Whether a vendor visit sells or buys (§5.5, kernel change K4).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum VendorMode {
    /// Bare `.vendor` — sell junk and repair. The maintenance behaviour ADR-000 §3.2 describes.
    Sell,
    /// `.vendor <entry>` — buy from this vendor. 43 of the 385 instances name a vendor to buy from,
    /// which is why `behavior.vendor` needs a new mode (K4).
    Buy,
}

/// Whether a flight-master visit travels or only registers the node (§5.5).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum FlightMode {
    /// `.fly` (741) — taxi travel to `dest_node`.
    Fly,
    /// `.fp` (199) — acquire/discover the flight path without flying.
    Discover,
}

/// Whether a hearth delegation uses the stone or re-binds it (§5.5).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum HearthMode {
    /// `.hs` (382) — always bare; the sibling `.cooldown item,6948` supplies the gate.
    Use,
    /// `.home` (186) — set the hearth at an innkeeper.
    Bind,
}

/// Direction of a bank visit (§5.5).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum BankMode {
    /// `.bankwithdraw` (53) — lists up to 89 item ids.
    Withdraw,
    /// `.bankdeposit` (23).
    Deposit,
}

/// What a stable-master visit is for (§5.5).
///
/// `.stable` (42) is **always bare** in the corpus — no argument distinguishes the direction.
/// §4.1 nonetheless describes it as "Hunter pet stabling, both directions", and §5.5 types the
/// payload with a `mode`, so the two directions are modelled and marked.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum StableMode {
    /// Bare `.stable` (42) — visit the stable master and let the behaviour decide the direction.
    ///
    /// This is the **only** form the corpus produces, so it is the variant R2's lowering must
    /// emit for every `.stable` line. `Store` and `Retrieve` are unreachable from the corpus as
    /// it stands; do not lower to them by inferring intent from surrounding steps.
    Visit,
    /// Stable the active pet.
    // UNVERIFIED: no corpus evidence found. Only §4.1's prose ("both directions") justifies the
    // split; no `.stable` argument encodes a direction.
    Store,
    /// Retrieve a stabled pet.
    // UNVERIFIED: no corpus evidence found. Same basis as `Store`.
    Retrieve,
}

/// Why the corpse behaviour was invoked (§5.5, §8, kernel change K5).
///
/// This is the field that stops the band 90-99 safety net and the profile from fighting each other:
/// recovery that sees [`DeliberateDeath`](Self::DeliberateDeath) resurrects at the *intended*
/// graveyard instead of running back to the corpse.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum CorpseIntent {
    /// The player died unintentionally — ordinary corpse recovery. Named by K5 ("distinguishing
    /// deliberate from accidental death", §5.9).
    Accidental,
    /// `.deathskip` (77) — deliberate death used as traversal.
    DeliberateDeath,
}

/// The typed argument bundle handed to a kernel behaviour by [`Op::Delegate`] (§5.5, §7.1).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum DelegatePayload {
    /// `.vendor` (385) → `behavior.vendor`.
    Vendor {
        /// The vendor.
        npc: NpcRef,
        /// Sell junk or buy a named list.
        mode: VendorMode,
        /// Items to buy, when `mode` is [`VendorMode::Buy`].
        items: Vec<ItemId>,
        /// Copper floor below which the behaviour must not spend.
        gold_floor: Option<u32>,
    },
    /// `.train` 1-argument form (1,250) and `.trainer` (469) → `behavior.trainer`.
    ///
    /// `spell` is `None` for `.trainer`, which is a whole-visit "train your class spells"
    /// delegation rather than a single spell.
    Trainer {
        /// The trainer.
        npc: NpcRef,
        /// The specific spell to train, when the source named one.
        spell: Option<SpellId>,
    },
    /// `.fly` (741) and `.fp` (199) → `behavior.flightpath`.
    FlightPath {
        /// The flight master.
        npc: NpcRef,
        /// Travel or merely discover the node.
        mode: FlightMode,
        /// Destination node name, when the source named one.
        dest_node: Option<String>,
    },
    /// `.hs` (382) and `.home` (186) → `behavior.hearth`.
    ///
    /// `npc` is `None` for `.hs`, which needs no NPC.
    Hearth {
        /// Use the stone or bind it.
        mode: HearthMode,
        /// The innkeeper, for [`HearthMode::Bind`].
        npc: Option<NpcRef>,
    },
    /// `.bankwithdraw` (53) and `.bankdeposit` (23) → `behavior.bank`.
    Bank {
        /// The banker.
        npc: NpcRef,
        /// Direction.
        mode: BankMode,
        /// Items to move.
        items: Vec<ItemId>,
    },
    /// `.stable` (42) → `behavior.stable`.
    Stable {
        /// The stable master.
        npc: NpcRef,
        /// What the visit is for.
        mode: StableMode,
    },
    /// `.deathskip` (77) → `behavior.corpse` with the new `intent` capability (K5).
    Corpse {
        /// Deliberate or accidental.
        intent: CorpseIntent,
        /// Index into
        /// [`RuntimeProfile::waypoint_pool`](crate::kernel::RuntimeProfile::waypoint_pool) naming
        /// the graveyard the profile wants to resurrect at.
        resurrect_at: Option<u32>,
    },
}

/// An item the task should keep while it is active, and the quest it counts toward (§7.1).
///
/// Produced by `.collect` (3,044), whose optional third argument is the owning quest, and by
/// `.addquestitem` (32), which declares an item counting toward a quest the current step is *not*
/// working on so that it is kept while doing something else (§4.1).
///
/// The required *count* is not here: that half of `.collect` lowers to
/// [`Predicate::ItemCount`](crate::kernel::Predicate::ItemCount). This struct is the loot filter
/// only.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LootRule {
    /// The item to keep, e.g. `5385` (Crawler Leg) in §7.3.3 task 0.
    pub item: ItemId,
    /// The quest it counts toward. `None` when `.collect` omitted its third argument.
    pub for_quest: Option<QuestId>,
}

/// One operation inside a task's ordered `ops` list (§7.1).
///
/// Adjacently tagged per C4: the Lua kernel dispatches on `op.type`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum Op {
    /// Move. `.goto` (38,087), `.waypoint` (593), `.groundgoto` (114), `.flygoto` (1).
    Travel {
        /// The route to walk.
        route: Route,
    },
    /// Accept a quest. `.accept` (7,490); `.daily` (35) sets `repeatable`.
    Accept {
        /// The quest.
        quest: QuestId,
        /// `.daily` — a repeatable quest, for which
        /// [`QuestInLog`](crate::kernel::Predicate::QuestInLog) rather than `QuestTurnedIn` is the
        /// reliable gate (§8).
        repeatable: bool,
    },
    /// Hand a quest in. `.turnin` (7,712); `.dailyturnin` (40) sets `repeatable`.
    TurnIn {
        /// The quest to hand in.
        quest: QuestId,
        /// `.turninmultiple` (1) — hand in whichever of these was taken. This is the Aldor/Scryer
        /// allegiance choice point (§8).
        any_of: Vec<QuestId>,
        /// Reward index, from `.turnin`'s second argument. Proven by `A-1-11-Human.lua:155/156`,
        /// which turn in quest 33 with reward 2 vs 1, split by armour class (§4.1).
        reward_choice: Option<u8>,
        /// A negative quest id in the source means an optional turn-in (38 instances).
        optional: bool,
        /// `.dailyturnin`.
        repeatable: bool,
    },
    /// Abandon quests. `.abandon` (142) — a real mutation of the quest log.
    Abandon {
        /// The quests to abandon.
        quests: Vec<QuestId>,
    },
    /// Stop tracking a quest without abandoning it. `#qremove` (2) — used where the route never
    /// turns the quest in. Distinct from [`Op::Abandon`]: no in-game effect (§4.2).
    UntrackQuest {
        /// The quest to stop tracking.
        quest: QuestId,
    },
    /// Interact with an NPC. `.gossip` (23) and `.gossipoption` (7) supply the policy.
    Interact {
        /// The NPC.
        npc: NpcRef,
        /// How to handle the gossip window.
        gossip: GossipPolicy,
    },
    /// Use an item. `.use` (1,678), including quest-starting items.
    UseItem {
        /// The item, e.g. `7586` (Tharnariun's Hope) in §7.3.3 task 2.
        item: ItemId,
    },
    /// Cast a spell. `.cast` (589) and the 181 `.usespell` lines that duplicate a sibling `.cast`.
    /// Also covers "click this object, which casts spell N".
    Cast {
        /// The spell.
        spell: SpellId,
    },
    /// Destroy an item to free bag space. `.destroy` (72).
    DestroyItem {
        /// The item.
        item: ItemId,
    },
    /// Equip an item into a slot. `.equip` (27) — slot first, then item, e.g. `.equip 16,2488`.
    Equip {
        /// Equipment slot, corroborated by sibling `.itemStat` slot numbers (§4.1).
        slot: u8,
        /// The item.
        item: ItemId,
    },
    /// Enter a vehicle. `.vehicle` (2) — kept despite the low count because it cannot be expressed
    /// as `.use` or `.interact` (§8; the Fel Reaver console, quest 10612).
    EnterVehicle,
    /// Wait out a scripted RP/cutscene/spawn delay. `.timer` (200) — real bot behaviour, not
    /// display (§4.1).
    Wait {
        /// Seconds to wait.
        secs: u16,
        /// Human-readable reason, carried for the runner cockpit's blocked-reason display.
        label: String,
    },
    /// Hand the work to a kernel behaviour instead of reimplementing it (C5, §5.5).
    Delegate {
        /// Which behaviour.
        behavior: BehaviorId,
        /// Its typed arguments. The producer is responsible for pairing `behavior` with the
        /// matching payload variant.
        payload: DelegatePayload,
    },
}
