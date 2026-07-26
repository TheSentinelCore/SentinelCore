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

use std::collections::BTreeMap;

use sentinel_models::platform::EntityKind;
use sentinel_models::runtime::RuntimeWaypoint;
use serde::{Deserialize, Serialize};

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

/// What lowering needs to know about the game database.
pub trait ResolverDb {
    /// Identifies the database content these answers came from. Stamped onto every
    /// [`sentinel_models::platform::ExecutionPlan`]; a plan carrying a different fingerprint is
    /// stale, not wrong.
    fn fingerprint(&self) -> &str;

    /// A canonical spawn point for an entry, or `None` when the entry has none (a vendor that
    /// only exists inside an instance, a deleted entry, a typo'd ref).
    fn spawn(&self, kind: EntityKind, id: u32) -> Option<Spawn>;

    /// The current display name. `EntityRef::label` is a cache that may be years stale (ADR 09a
    /// §1.2), so resolve-time output prefers this.
    fn label(&self, kind: EntityKind, id: u32) -> Option<String>;

    /// The NPC that offers a quest, for intents that did not name one.
    fn quest_giver(&self, quest_id: u32) -> Option<u32>;

    /// The NPC that takes a quest back. Frequently not the giver.
    fn quest_ender(&self, quest_id: u32) -> Option<u32>;
}

/// A fixture database. Public, not `#[cfg(test)]`: W6's simulation and CI regression runs need to
/// resolve a campaign with no sqlite file present, and a second copy of this in a test module
/// would drift from the trait.
///
/// `BTreeMap` throughout so iteration order cannot leak into resolver output.
#[derive(Debug, Clone, Default)]
pub struct InMemoryDb {
    fingerprint: String,
    spawns: BTreeMap<(EntityKind, u32), Spawn>,
    labels: BTreeMap<(EntityKind, u32), String>,
    quest_givers: BTreeMap<u32, u32>,
    quest_enders: BTreeMap<u32, u32>,
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
}

impl ResolverDb for InMemoryDb {
    fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    fn spawn(&self, kind: EntityKind, id: u32) -> Option<Spawn> {
        self.spawns.get(&(kind, id)).copied()
    }

    fn label(&self, kind: EntityKind, id: u32) -> Option<String> {
        self.labels.get(&(kind, id)).cloned()
    }

    fn quest_giver(&self, quest_id: u32) -> Option<u32> {
        self.quest_givers.get(&quest_id).copied()
    }

    fn quest_ender(&self, quest_id: u32) -> Option<u32> {
        self.quest_enders.get(&quest_id).copied()
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
        assert!(db.spawn(EntityKind::Npc, 1).is_none());
        assert!(db.label(EntityKind::Npc, 1).is_none());
        assert!(db.quest_giver(1).is_none());
        assert!(db.quest_ender(1).is_none());
    }
}
