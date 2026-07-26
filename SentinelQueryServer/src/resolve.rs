//! The `sentinel-resolver` seam: a [`ResolverDb`] backed by the live tbcmangos snapshot.
//!
//! Resolution itself lives in the crate, not here (ADR 09 §5) — HTTP is one transport among
//! several, and none of the lowering rules may leak into this file. What the crate deliberately
//! does *not* do is open a connection, so satisfying its narrow trait from sqlite is the whole job
//! of this module.
//!
//! Two properties are load-bearing:
//!
//! * **Determinism.** Every answer below is either a single-row lookup or an ordered pick. An entry
//!   like npc 823 has many spawns; returning "whichever row came back first" would make the plan
//!   depend on query-planner mood and break the crate's byte-identity guarantee.
//! * **Reuse.** Spawns come from [`Db::spawns`], the same query `GET /spawns/:type/:entry` serves.
//!   A second copy of that query could drift, and the height it returns is the fix for 100% of
//!   38,726 imported Travel positions carrying `world_z = 0`.

use sentinel_models::platform::{EntityKind, ExecutionPlan};
use sentinel_resolver::{Diagnostic, ResolverDb, Spawn};
use serde::{Deserialize, Serialize};

use crate::db::Db;
use crate::search::SpawnType;

/// `POST /resolve`'s body. Diagnostics travel *with* a plan rather than instead of one: a campaign
/// with unresolvable references still resolves, and the IDE needs both halves to draw squiggles
/// over a route it can already run.
#[derive(Debug, Serialize, Deserialize)]
pub struct ResolveResponse {
    pub plan: ExecutionPlan,
    pub diagnostics: Vec<Diagnostic>,
}

pub struct SqliteResolverDb {
    db: Db,
    fingerprint: String,
}

impl SqliteResolverDb {
    /// Computes the fingerprint once, up front. Reading it per lookup would let a concurrent
    /// snapshot swap stamp a plan with a fingerprint that half its operations were not resolved
    /// against.
    pub fn new(db: Db) -> Result<Self, String> {
        let fingerprint = db.fingerprint()?;
        Ok(Self { db, fingerprint })
    }
}

/// The trait returns `Option`, so a sqlite failure would otherwise be indistinguishable from "no
/// such entry" — the resolver would report a missing spawn and the operator would never learn the
/// database was unreadable.
fn or_log<T>(what: &str, result: Result<Option<T>, String>) -> Option<T> {
    match result {
        Ok(value) => value,
        Err(error) => {
            tracing::warn!("resolver db lookup failed ({what}): {error}");
            None
        }
    }
}

impl ResolverDb for SqliteResolverDb {
    fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    fn spawn(&self, kind: EntityKind, id: u32) -> Option<Spawn> {
        let table = match kind {
            EntityKind::Npc => SpawnType::Npc,
            EntityKind::Object => SpawnType::Object,
            // Quests, items, spells and maps are not placed in the world. `None` is the honest
            // answer; the resolver turns it into a diagnostic naming the field.
            _ => return None,
        };
        let spawns = or_log("spawn", self.db.spawns(table, id).map(Some))?;
        // `Db::spawns` orders by guid, so the canonical spawn is the lowest-guid placement — the
        // same one `GET /spawns/:type/:entry` lists first.
        let first = spawns.first()?;
        Some(Spawn::new(
            first.map,
            first.position_x,
            first.position_y,
            first.position_z,
        ))
    }

    fn label(&self, kind: EntityKind, id: u32) -> Option<String> {
        or_log("label", self.db.entity_label(kind, id))
    }

    fn quest_giver(&self, quest_id: u32) -> Option<u32> {
        or_log("quest_giver", self.db.quest_giver(quest_id))
    }

    fn quest_ender(&self, quest_id: u32) -> Option<u32> {
        or_log("quest_ender", self.db.quest_ender(quest_id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_db::open;

    fn resolver_db() -> SqliteResolverDb {
        SqliteResolverDb::new(open()).expect("the snapshot must yield a fingerprint")
    }

    #[test]
    fn the_fingerprint_is_the_same_for_two_connections_to_one_snapshot() {
        // Callers detect staleness by comparing this string. A fingerprint that changed per
        // connection would report every plan as stale and make re-resolution unfalsifiable.
        let first = resolver_db();
        let second = resolver_db();
        assert_eq!(first.fingerprint(), second.fingerprint());
        assert!(
            first.fingerprint().starts_with("tbcmangos@"),
            "fingerprint was {}",
            first.fingerprint()
        );
    }

    #[test]
    fn an_npc_spawn_carries_its_real_ground_height() {
        let spawn = resolver_db()
            .spawn(EntityKind::Npc, 823)
            .expect("Deputy Willem is spawned");
        assert_eq!(spawn.map, 0);
        assert!((spawn.z - 83.4466).abs() < 0.01, "z was {}", spawn.z);
    }

    #[test]
    fn an_object_spawn_comes_from_the_gameobject_table() {
        // Silverleaf's lowest-guid placement is on map 1, not map 0 — picking a different spawn
        // would move the route to another continent, which is why the pick has to be ordered.
        let spawn = resolver_db()
            .spawn(EntityKind::Object, 1617)
            .expect("Silverleaf is placed");
        assert_eq!(spawn.map, 1);
        assert!((spawn.z - 28.7988).abs() < 0.01, "z was {}", spawn.z);
    }

    #[test]
    fn a_kind_that_is_never_placed_in_the_world_has_no_spawn() {
        let db = resolver_db();
        for kind in [
            EntityKind::Quest,
            EntityKind::Item,
            EntityKind::Spell,
            EntityKind::Map,
            EntityKind::Area,
        ] {
            assert!(db.spawn(kind, 1).is_none(), "{kind} must not report a spawn");
        }
    }

    #[test]
    fn an_unspawned_entry_is_none_rather_than_the_world_origin() {
        assert!(resolver_db().spawn(EntityKind::Npc, 99_999_999).is_none());
    }

    #[test]
    fn labels_come_from_the_snapshot_for_every_kind_that_has_a_name() {
        let db = resolver_db();
        for (kind, id, expected) in [
            (EntityKind::Npc, 823, "Deputy Willem"),
            (EntityKind::Quest, 783, "A Threat Within"),
            (EntityKind::Object, 1617, "Silverleaf"),
            (EntityKind::Spell, 8690, "Hearthstone"),
            (EntityKind::Area, 1, "RuinsOfAndorhal"),
        ] {
            assert_eq!(db.label(kind, id).as_deref(), Some(expected));
        }
    }

    #[test]
    fn an_unknown_entry_has_no_label() {
        assert!(resolver_db().label(EntityKind::Npc, 99_999_999).is_none());
    }

    #[test]
    fn the_quest_relations_are_read_from_the_two_separate_tables() {
        let db = resolver_db();
        assert_eq!(db.quest_giver(783), Some(823), "Deputy Willem offers it");
        assert_eq!(db.quest_ender(783), Some(197), "Marshal McBride takes it");
        assert!(db.quest_giver(99_999_999).is_none());
        assert!(db.quest_ender(99_999_999).is_none());
    }
}
