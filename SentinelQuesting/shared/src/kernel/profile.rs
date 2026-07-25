//! [`RuntimeProfile`] — the kernel artifact root, its provenance header, and the combat policy.
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 for the shapes, §5.2 (C2) for [`Archetype`], §5.4 (C4) for
//! [`ContentIntegrity`], §5.6 (C6) for [`CombatPolicy`], §6.5 for the three version axes.
//!
//! Because C2 resolves every static gate away at compile time, class / race / faction appear in the
//! artifact **only here in the header**, as provenance describing which archetype it was compiled
//! for — never as a runtime test (§5.8). The runtime could not evaluate them anyway: player faction
//! is not readable from the Sylvanas API and there is no documented race enum.

use serde::{Deserialize, Serialize};

use super::ids::{hex32, magic};
use super::op::{NpcRef, Point};
use super::task::{Task, UnknownPolicy};

/// Re-exported from the authoring model: the wire spellings are already the ones §7.3.3 needs
/// (`"class": "Hunter"`, `"race": "NightElf"`, `"faction": "Alliance"`), so the kernel reuses that
/// vocabulary instead of defining a second one for the same concept.
pub use crate::authoring::{Class, Faction, Race};

/// Schema version currently emitted, from §7.3.3 (`"schema_version": 1`).
///
/// One of the three independent version axes of §6.5. A mismatch on this axis, or on
/// [`RuntimeProfile::schema_hash`], means the kernel cannot interpret the bytes ⇒ **refuse**.
pub const SCHEMA_VERSION: u16 = 1;

/// Client expansion the guide was authored for (§5.2, §4.2).
///
/// All 277 `RegisterGuide` blocks in the corpus carry `#tbc`; `#wotlk` (129) and `#classic` (125)
/// appear as filters within them. Resolved at compile time.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum Expansion {
    /// `#classic`
    Classic,
    /// `#tbc` — the value in §7.3.3.
    Tbc,
    /// `#wotlk`
    Wotlk,
}

/// Shattrath allegiance branch (§5.2, §4.2).
///
/// Compile-time only: the choice is irreversible in-game, so a runtime branch would be dead weight.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum Allegiance {
    /// `#aldor` (239).
    Aldor,
    /// `#scryer` (209).
    Scryer,
}

/// Which flavour of route the artifact was compiled for (§7.1: "`#questguide`, `.dungeon` variant").
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
pub enum ProfileMode {
    /// The pure speed route — the absence of `#questguide`. The value in §7.3.3.
    SpeedRoute,
    /// `#questguide` (228) — do-the-quests mode rather than the speed route (§4.2).
    QuestGuide,
    /// `.dungeon` (1,351) — resolved at compile time into a separate archetype variant rather than a
    /// runtime branch (§5.6, §8).
    Dungeon,
}

/// BLAKE3-and-provenance block that closes the content-integrity gap `schema_hash` leaves open
/// (§5.4.1, kernel change K6).
///
/// `schema_hash` guards the *tag set*; nothing guarded the *resolved ids*, and this project resolves
/// a lot of them out of a 298 MB `tbcmangos.sqlite`. If that snapshot drifts from what the server
/// runs, the compiler emits a syntactically perfect profile that walks to the wrong NPC forever.
///
/// The honest limit: the kernel **cannot** compute the server's content hash — no documented API
/// exposes world-database identity — so `content_hash` is not a server-truth check. It is
/// (1) a coherence check across artifacts (profile, sidecar index and `.save.json` must agree, or
/// **refuse**, because a save resumed against a differently-resolved profile steps to the wrong task
/// index) and (2) a provenance record. Server-truth verification is
/// [`NpcRef::expect_name`](crate::kernel::NpcRef::expect_name) plus the first-touch probe.
///
/// Computing the digest is not R1's concern; this type only carries it.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ContentIntegrity {
    /// BLAKE3 over every resolved `(kind, entry_id, expect_name)` triple, sorted.
    ///
    /// On the wire: a 64-character lowercase hex string, `^[0-9a-f]{64}$` (§7.2).
    #[serde(with = "hex32")]
    #[schemars(with = "String")]
    pub content_hash: [u8; 32],
    /// Which world database the ids were resolved from, e.g. `"tbcmangos.sqlite"`.
    pub world_source: String,
    /// Snapshot identity: file digest plus the row counts of the tables consulted, e.g.
    /// `"sha256:…; quest_template=6599 creature_template=18799 gameobject_template=14216"`.
    pub world_build: String,
}

/// The concrete character the artifact was resolved for (C2, §5.2).
///
/// Every `<<` expression, `#aldor`/`#scryer`, `#hardcore`/`#softcore`, `#ah`/`#ssf`,
/// `#flyable`/`#noflyable`, `#phase`, `#tbc`/`#wotlk`/`#classic` and `.dungeon` is evaluated against
/// this at compile time, and only the surviving tasks and ops are emitted. Static gates must not
/// reach the runtime.
///
/// **This is forced, not an optimisation.** Player faction is not readable from the Sylvanas API —
/// `game_object:get_faction_id()` returns a unit faction template, and the only faction-side call
/// works in arena/battleground context only — and there is no race enum and no `race_id_to_name`
/// table anywhere in the API docs. A residual-gate design would require the runtime to answer "am I
/// Alliance?" and it cannot (§5.2).
///
/// `Hash` is absent, unlike the rest of this module's all-`Eq` types: the reused authoring
/// [`Class`] / [`Race`] / [`Faction`] enums do not derive it, and `crate::authoring` is not modified
/// by this model. Key a profile cache on the serialized archetype instead.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Archetype {
    /// Player class. Reused from the authoring vocabulary; `JsonSchema` is described as a string
    /// because that is the wire type and `crate::authoring` is an ADR-02 module this model does not
    /// modify.
    #[schemars(with = "String")]
    pub class: Class,
    /// Player race. Same reuse note as `class`.
    #[schemars(with = "String")]
    pub race: Race,
    /// Player faction. Same reuse note as `class`.
    #[schemars(with = "String")]
    pub faction: Faction,
    /// Client expansion, from `#tbc` / `#wotlk` / `#classic`.
    pub expansion: Expansion,
    /// `#aldor` / `#scryer`.
    pub allegiance: Option<Allegiance>,
    /// `#hardcore` (59) / `#softcore` (91).
    pub hardcore: bool,
    /// `#ssf` (58) / `#ah` (178) — self-found versus auction-house-permitted.
    pub self_found: bool,
    /// `#flyable` (3) / `#noflyable` (14).
    pub can_fly: bool,
    /// `#phase` (174) — server content-release phase.
    pub content_phase: Option<u8>,
    /// Speed route, quest guide, or dungeon variant.
    pub mode: ProfileMode,
}

/// Guide-pack identity and chaining (§7.1, §4.2).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GuideMeta {
    /// `#name` (278) — unique within `group`, and the target `#next` / `#include` resolve against.
    pub name: String,
    /// `#group` (277) — catalogue bucket and the namespace in which `name` is unique.
    pub group: String,
    /// `#subgroup` (272) — level band or themed section.
    pub subgroup: Option<String>,
    /// `#version` (265) — the upstream guide-pack revision.
    ///
    /// The third version axis of §6.5, and the only one whose mismatch is a **warning**: a newer
    /// guide pack is not an error, it is a reason to recompile.
    pub source_version: u32,
    /// `#next` (156) — profile chaining. `;`-separated alternatives in the source become entries
    /// here.
    pub next: Vec<String>,
}

/// How aggressively combat may act, and against what (C6, §5.6).
///
/// Scope decision: a profile-level default with a per-task override. `.mob` (7,456) is per-step and
/// names a step-specific whitelist, so policy cannot be profile-only; but 16,438 of 23,894 tasks
/// carry no combat token at all, so per-task-only would mean emitting a redundant policy on
/// two-thirds of tasks.
///
/// §7.1 types `targets` and `watch_units` as `Vec<CreatureEntry>`; §5.8 defines that concept as an
/// entry id **plus** `expect_name`, which is exactly [`NpcRef`], and §7.3.3 serializes them as
/// `{entry, expect_name, pos}` objects. [`NpcRef`] is therefore the faithful type.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CombatPolicy {
    /// How much initiative combat may take.
    pub stance: CombatStance,
    /// `.mob` (7,456) — the kill whitelist.
    pub targets: Vec<NpcRef>,
    /// `.unitscan` (735) — roamers and rares to notice. Feeds targeting, not a standalone action.
    pub watch_units: Vec<NpcRef>,
    /// Leash distance in yards; derived from the route radius on grind circuits (§5.6).
    pub leash_yards: u16,
    /// Whether combat may take on additional pulls.
    pub allow_adds: bool,
    /// Party expectation, from `.solo` (13), `.group [n]` (190) and `.dungeon` (1,351).
    pub expect_group: GroupExpectation,
}

/// How much initiative the combat service may take (§5.6, §7.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum CombatStance {
    /// Do not fight. Declared by §7.1; §5.6's corpus mapping table assigns no signal to it, so no
    /// corpus command currently produces this stance.
    Avoid,
    /// Fight back only. The profile-level default for the 16,438 tasks with no combat token.
    Defensive,
    /// Kill only what blocks the objective and refuse adds. `.mob` present (7,456).
    Objective,
    /// Pull proactively. `#loop` + `.mob` + `.complete` (1,661) — a grind circuit *wants* pulls
    /// (§7.3.3 task 0, task 5).
    Aggressive,
}

/// Expected party composition (§5.6, §7.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "type", content = "payload", deny_unknown_fields)]
pub enum GroupExpectation {
    /// `.solo` (13).
    Solo,
    /// `.group [n]` (190).
    Party {
        /// Expected party size.
        size: u8,
    },
    /// `.dungeon` (1,351) — resolved at compile time into a separate archetype variant; this sets
    /// the combat policy for it (§8).
    Dungeon,
}

/// Profile-level fallbacks a task may override (§7.1).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProfileDefaults {
    /// Default combat policy (C6). Used wherever [`Task::combat`](crate::kernel::Task::combat) is
    /// `None`.
    pub combat: CombatPolicy,
    /// Default tri-state policy (C1). Used wherever a task does not override it.
    pub unknown_policy: UnknownPolicy,
}

/// The kernel-executable artifact: a fully resolved, fail-closed, offline-compiled guide (§7.1).
///
/// Every field is required (§7.2's root `required` list is exhaustive) and the struct denies unknown
/// fields, per C4: an artifact carrying a field this model does not understand must **refuse to
/// load**, not silently degrade. That is also why the artifact cannot carry the `_comment` keys
/// §7.3.3 uses for prose.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RuntimeProfile {
    /// Container magic, `b"SNTL"`. On the wire, the string `"SNTL"` (§7.2, §6.2.5).
    #[serde(with = "magic")]
    #[schemars(with = "String")]
    pub magic: [u8; 4],
    /// Struct-shape version; see [`SCHEMA_VERSION`]. Mismatch ⇒ refuse (§6.5).
    pub schema_version: u16,
    /// BLAKE3 over the full tag set (C4, §5.4). Wire form: `^[0-9a-f]{64}$`.
    ///
    /// Guards the *tags*, not the resolved content — that is [`ContentIntegrity`]'s job.
    #[serde(with = "hex32")]
    #[schemars(with = "String")]
    pub schema_hash: [u8; 32],
    /// Every op and predicate tag referenced by this artifact (C4, §5.4). By emission time every
    /// token is canonical and only registered tags appear here, so the fail-closed loader has
    /// nothing to forgive (§5.10).
    pub tags_used: Vec<String>,
    /// Resolved-id integrity and world-snapshot provenance.
    pub integrity: ContentIntegrity,
    /// What character this artifact was resolved for (C2).
    pub archetype: Archetype,
    /// Guide-pack identity and chaining.
    pub meta: GuideMeta,
    /// Profile-level fallbacks.
    pub defaults: ProfileDefaults,
    /// The shared coordinate pool every [`Route`](crate::kernel::Route) indexes into.
    ///
    /// The pool is **interned**: it holds each distinct `(map_id, x, y, z)` exactly once. §7.1
    /// annotates it "deduplicated; routes index into this" and §6.4 says it "deduplicates shared
    /// points across tasks". A route that visits a point twice repeats the **index**, so the same
    /// entry may be referenced any number of times — a closed `Circuit` always does. Interning is a
    /// *pool* operation only: it never changes a route's length. (The separate route-level collapse
    /// §2.6 and §8 call for — a source step emitting the same coordinate twice — is a later
    /// deliverable; see ADR 07 §9 item 26.)
    ///
    /// The *type* cannot enforce that (`Vec<Point>` will hold anything a producer puts in it);
    /// producing an interned pool is the compiler's job. §7.3.3's worked example is interned, and
    /// `kernel_fixture::no_two_waypoint_pool_entries_hold_the_same_coordinate` pins it.
    pub waypoint_pool: Vec<Point>,
    /// Ordered tasks. The index **is** the [`TaskId`](crate::kernel::TaskId).
    pub tasks: Vec<Task>,
}
