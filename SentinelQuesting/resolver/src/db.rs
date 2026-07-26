//! The database seam.
//!
//! Deliberately narrow: only what lowering actually needs. The crate is a pure library (ADR 09 §5)
//! and must stay testable with no sqlite file and no QueryServer process, so nothing here opens a
//! connection or issues a request — an implementation does that, behind the trait. QueryServer
//! wraps the crate in W6; the crate never wraps QueryServer.
//!
//! Every method must be **deterministic**. An entry like npc 823 has many spawns in `creature`;
//! an implementation that returned "whichever row came back first" would make the resolver's
//! byte-identity guarantee depend on query planner mood. Picking a canonical spawn is the
//! implementation's job, not the caller's.

use std::collections::{BTreeMap, BTreeSet};

use sentinel_models::platform::EntityKind;
use sentinel_models::runtime::RuntimeWaypoint;
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// A world position for an entry, with a **real** `z`.
///
/// The reason this exists at all: guide text never carried height, so 100% of 38,726 imported
/// Travel positions landed at `world_z = 0` (ADR 09a §2 W3). Ground height comes from
/// `creature.position_z` / `gameobject.position_z`, and it comes in through here.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Spawn {
    pub map: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Spawn {
    pub fn new(map: u32, x: f32, y: f32, z: f32) -> Self {
        Self { map, x, y, z }
    }

    pub fn waypoint(&self) -> RuntimeWaypoint {
        RuntimeWaypoint::new(self.map, self.x, self.y, self.z)
    }
}

/// A lookup the backend could not perform.
///
/// Distinct from `Ok(None)`, and the distinction is the point. `Ok(None)` says the game has no such
/// thing, which the resolver turns into a diagnostic an author can act on; `Err` says the backend
/// could not answer, which no author can fix. Collapsing the two — as `Option` forced every
/// implementation to — made a locked or corrupt snapshot surface to the author as "this NPC has no
/// spawn", sending them hunting a data problem that did not exist.
///
/// Owned by this crate rather than by a backend, so routing on it costs a caller no dependency on
/// sqlite, HTTP, or whatever produced the failure.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
#[error("`{lookup}` lookup failed: {detail}")]
pub struct DbError {
    /// Which trait method failed. `&'static str` so it is backend-independent and safe to match on;
    /// backend wording lives in `detail` and may be reworded freely.
    pub lookup: &'static str,
    /// The backend's own explanation. Free-form on purpose — it never reaches an
    /// [`sentinel_models::platform::ExecutionPlan`], because a failed lookup produces no plan at
    /// all, so an OS-formatted message here cannot leak into byte-identical output.
    pub detail: String,
}

impl DbError {
    pub fn new(lookup: &'static str, detail: impl Into<String>) -> Self {
        Self {
            lookup,
            detail: detail.into(),
        }
    }
}

/// `Ok(None)` is absence, `Err` is failure. Every lookup below is spelled this way so a backend
/// physically cannot report the second as the first.
pub type DbResult<T> = Result<T, DbError>;

/// What lowering needs to know about the game database.
pub trait ResolverDb {
    /// Identifies the database content these answers came from. Stamped onto every
    /// [`sentinel_models::platform::ExecutionPlan`]; a plan carrying a different fingerprint is
    /// stale, not wrong.
    ///
    /// Infallible on purpose: an implementation computes this once, up front, so a snapshot swap
    /// cannot stamp a plan with a fingerprint half its operations were not resolved against.
    fn fingerprint(&self) -> &str;

    /// A canonical spawn point for an entry, `Ok(None)` when the entry has none (a vendor that only
    /// exists inside an instance, a deleted entry, a typo'd ref), `Err` when the placement tables
    /// could not be read.
    fn spawn(&self, kind: EntityKind, id: u32) -> DbResult<Option<Spawn>>;

    /// The current display name. `EntityRef::label` is a cache that may be years stale (ADR 09a
    /// §1.2), so resolve-time output prefers this.
    fn label(&self, kind: EntityKind, id: u32) -> DbResult<Option<String>>;

    /// The NPC that offers a quest, for intents that did not name one.
    fn quest_giver(&self, quest_id: u32) -> DbResult<Option<u32>>;

    /// The NPC that takes a quest back. Frequently not the giver.
    fn quest_ender(&self, quest_id: u32) -> DbResult<Option<u32>>;
}

/// A fixture database. Public, not `#[cfg(test)]`: W6's simulation and CI regression runs need to
/// resolve a campaign with no sqlite file present, and a second copy of this in a test module
/// would drift from the trait.
///
/// `BTreeMap` throughout so iteration order cannot leak into resolver output.
///
/// It also simulates a *failing* backend. Failure is now a distinct behaviour with its own
/// contract, and the crate must stay offline-testable, so there has to be a way to reach the error
/// path without a sqlite file to corrupt.
#[derive(Debug, Clone, Default)]
pub struct InMemoryDb {
    fingerprint: String,
    spawns: BTreeMap<(EntityKind, u32), Spawn>,
    labels: BTreeMap<(EntityKind, u32), String>,
    quest_givers: BTreeMap<u32, u32>,
    quest_enders: BTreeMap<u32, u32>,
    /// Every lookup fails — an unreadable file, a lock held by another writer.
    unreadable: Option<String>,
    /// Only names fail. Separated from `unreadable` because a name is the one answer with a
    /// plausible-looking fallback, so swallowing its failure is the easiest mistake to make.
    unreadable_labels: Option<String>,
    /// Entry-scoped failure — a corrupt page, one unreadable row. `BTreeSet` for the same reason
    /// every map here is a `BTreeMap`.
    failing_entries: BTreeSet<(EntityKind, u32)>,
    failing_quests: BTreeSet<u32>,
}

impl InMemoryDb {
    pub fn new(fingerprint: impl Into<String>) -> Self {
        Self {
            fingerprint: fingerprint.into(),
            ..Default::default()
        }
    }

    pub fn with_spawn(mut self, kind: EntityKind, id: u32, spawn: Spawn) -> Self {
        self.spawns.insert((kind, id), spawn);
        self
    }

    pub fn with_label(mut self, kind: EntityKind, id: u32, label: impl Into<String>) -> Self {
        self.labels.insert((kind, id), label.into());
        self
    }

    pub fn with_quest_giver(mut self, quest_id: u32, npc_entry: u32) -> Self {
        self.quest_givers.insert(quest_id, npc_entry);
        self
    }

    pub fn with_quest_ender(mut self, quest_id: u32, npc_entry: u32) -> Self {
        self.quest_enders.insert(quest_id, npc_entry);
        self
    }

    /// Every lookup now fails, whatever this database was seeded with.
    pub fn failing(mut self, detail: impl Into<String>) -> Self {
        self.unreadable = Some(detail.into());
        self
    }

    /// Only [`ResolverDb::label`] fails.
    pub fn failing_labels(mut self, detail: impl Into<String>) -> Self {
        self.unreadable_labels = Some(detail.into());
        self
    }

    /// Spawn and label lookups for one entry fail; the rest of the database still answers. This is
    /// the case that proves failure is not degraded into a partial plan.
    pub fn with_failing_entry(mut self, kind: EntityKind, id: u32) -> Self {
        self.failing_entries.insert((kind, id));
        self
    }

    /// Both quest relations for one quest fail.
    pub fn with_failing_quest(mut self, quest_id: u32) -> Self {
        self.failing_quests.insert(quest_id);
        self
    }

    fn entry_failure(&self, lookup: &'static str, kind: EntityKind, id: u32) -> Option<DbError> {
        if let Some(detail) = &self.unreadable {
            return Some(DbError::new(lookup, detail.clone()));
        }
        if self.failing_entries.contains(&(kind, id)) {
            return Some(DbError::new(lookup, format!("row for `{kind}:{id}` is unreadable")));
        }
        None
    }

    fn quest_failure(&self, lookup: &'static str, quest_id: u32) -> Option<DbError> {
        if let Some(detail) = &self.unreadable {
            return Some(DbError::new(lookup, detail.clone()));
        }
        if self.failing_quests.contains(&quest_id) {
            return Some(DbError::new(
                lookup,
                format!("relation rows for quest {quest_id} are unreadable"),
            ));
        }
        None
    }
}

impl ResolverDb for InMemoryDb {
    fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    fn spawn(&self, kind: EntityKind, id: u32) -> DbResult<Option<Spawn>> {
        match self.entry_failure("spawn", kind, id) {
            Some(error) => Err(error),
            None => Ok(self.spawns.get(&(kind, id)).copied()),
        }
    }

    fn label(&self, kind: EntityKind, id: u32) -> DbResult<Option<String>> {
        if let Some(detail) = &self.unreadable_labels {
            return Err(DbError::new("label", detail.clone()));
        }
        match self.entry_failure("label", kind, id) {
            Some(error) => Err(error),
            None => Ok(self.labels.get(&(kind, id)).cloned()),
        }
    }

    fn quest_giver(&self, quest_id: u32) -> DbResult<Option<u32>> {
        match self.quest_failure("quest_giver", quest_id) {
            Some(error) => Err(error),
            None => Ok(self.quest_givers.get(&quest_id).copied()),
        }
    }

    fn quest_ender(&self, quest_id: u32) -> DbResult<Option<u32>> {
        match self.quest_failure("quest_ender", quest_id) {
            Some(error) => Err(error),
            None => Ok(self.quest_enders.get(&quest_id).copied()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_spawn_becomes_a_waypoint_with_its_height_intact() {
        let waypoint = Spawn::new(0, -8933.5, -136.5, 83.25).waypoint();
        assert_eq!(waypoint.map, 0);
        assert_eq!(waypoint.world_z, 83.25, "z must survive; z = 0 is the bug");
    }

    #[test]
    fn an_unknown_entry_returns_none_rather_than_a_default_position() {
        let db = InMemoryDb::new("test@0");
        assert_eq!(db.spawn(EntityKind::Npc, 1), Ok(None));
        assert_eq!(db.label(EntityKind::Npc, 1), Ok(None));
        assert_eq!(db.quest_giver(1), Ok(None));
        assert_eq!(db.quest_ender(1), Ok(None));
    }

    /// The whole point of W10: an entry the database has never heard of and an entry it cannot read
    /// must not produce the same value. `Ok(None)` above, `Err` here.
    #[test]
    fn an_unreadable_backend_is_an_error_not_the_same_none_an_unknown_entry_gives() {
        let db = InMemoryDb::new("test@0").failing("database is locked");
        assert_eq!(
            db.spawn(EntityKind::Npc, 1),
            Err(DbError::new("spawn", "database is locked"))
        );
        assert_eq!(db.label(EntityKind::Npc, 1).unwrap_err().lookup, "label");
        assert_eq!(db.quest_giver(1).unwrap_err().lookup, "quest_giver");
        assert_eq!(db.quest_ender(1).unwrap_err().lookup, "quest_ender");
    }

    #[test]
    fn a_failing_entry_leaves_the_rest_of_the_database_answering() {
        let db = InMemoryDb::new("test@0")
            .with_spawn(EntityKind::Npc, 1, Spawn::new(0, 1.0, 2.0, 3.0))
            .with_spawn(EntityKind::Npc, 2, Spawn::new(0, 4.0, 5.0, 6.0))
            .with_failing_entry(EntityKind::Npc, 1);
        assert!(db.spawn(EntityKind::Npc, 1).is_err());
        assert_eq!(
            db.spawn(EntityKind::Npc, 2),
            Ok(Some(Spawn::new(0, 4.0, 5.0, 6.0)))
        );
    }
}
