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
use sentinel_resolver::{DbError, DbResult, Diagnostic, ResolverDb, Spawn};
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

/// Every lookup below is `Ok(None)` for "this snapshot has no such row" and `Err` for "this
/// snapshot could not be read". Nothing swallows the second into the first: the `or_log` helper
/// that used to sit here logged a `warn` and returned `None`, which meant a locked or
/// schema-mismatched database reached the author as `resolver.spawn.unknown` — "no spawn point for
/// `npc:823`" — and the operator learned nothing at all unless someone was reading the log.
impl ResolverDb for SqliteResolverDb {
    fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    fn spawn(&self, kind: EntityKind, id: u32) -> DbResult<Option<Spawn>> {
        let table = match kind {
            EntityKind::Npc => SpawnType::Npc,
            EntityKind::Object => SpawnType::Object,
            // Quests, items, spells and maps are not placed in the world. `Ok(None)` is the honest
            // answer — nothing failed — and the resolver turns it into a diagnostic naming the
            // field.
            _ => return Ok(None),
        };
        let spawns = self
            .db
            .spawns(table, id)
            .map_err(|error| DbError::new("spawn", error))?;
        // `Db::spawns` orders by guid, so the canonical spawn is the lowest-guid placement — the
        // same one `GET /spawns/:type/:entry` lists first.
        Ok(spawns.first().map(|first| {
            Spawn::new(first.map, first.position_x, first.position_y, first.position_z)
        }))
    }

    fn label(&self, kind: EntityKind, id: u32) -> DbResult<Option<String>> {
        self.db
            .entity_label(kind, id)
            .map_err(|error| DbError::new("label", error))
    }

    fn quest_giver(&self, quest_id: u32) -> DbResult<Option<u32>> {
        self.db
            .quest_giver(quest_id)
            .map_err(|error| DbError::new("quest_giver", error))
    }

    fn quest_ender(&self, quest_id: u32) -> DbResult<Option<u32>> {
        self.db
            .quest_ender(quest_id)
            .map_err(|error| DbError::new("quest_ender", error))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_db::open;
    use axum::body::Bytes;
    use axum::http::StatusCode;
    use axum::Extension;
    use rusqlite::Connection;
    use std::sync::{Arc, Mutex};

    fn resolver_db() -> SqliteResolverDb {
        SqliteResolverDb::new(open()).expect("the snapshot must yield a fingerprint")
    }

    /// A snapshot whose fingerprint tables all exist — so construction succeeds and resolution
    /// starts — but whose `creature` rows cannot be read back in the shape the queries expect.
    ///
    /// This is the shape of the bug W10 fixes, not a contrived one: an out-of-date or partially
    /// restored snapshot answers `PRAGMA` and `COUNT(*)` happily and fails on the first real read,
    /// which is exactly when the old `or_log` helper turned the failure into "no spawn".
    fn unreadable_db() -> Db {
        let conn = Connection::open_in_memory().expect("an in-memory database always opens");
        conn.execute_batch(
            "CREATE TABLE db_version(version TEXT);
             INSERT INTO db_version(version) VALUES ('test');
             CREATE TABLE creature(unexpected);
             CREATE TABLE creature_template(unexpected);
             CREATE TABLE creature_involvedrelation(unexpected);
             CREATE TABLE creature_questrelation(unexpected);
             CREATE TABLE game_tele(unexpected);
             CREATE TABLE gameobject(unexpected);
             CREATE TABLE gameobject_template(unexpected);
             CREATE TABLE item_template(unexpected);
             CREATE TABLE quest_template(unexpected);
             CREATE TABLE spell_template(unexpected);",
        )
        .expect("the stub schema is valid SQL");
        Db(Arc::new(Mutex::new(conn)))
    }

    /// The defect this work unit exists for, at the seam: an unreadable table must not answer the
    /// same way an entry that is simply never placed in the world does.
    #[test]
    fn a_read_that_failed_is_an_error_not_the_none_an_unspawned_entry_gives() {
        let broken = SqliteResolverDb::new(unreadable_db())
            .expect("the fingerprint tables are all present");
        let error = broken
            .spawn(EntityKind::Npc, 823)
            .expect_err("a query that could not run is not `no such spawn`");
        assert_eq!(error.lookup, "spawn");

        assert_eq!(
            resolver_db().spawn(EntityKind::Npc, 99_999_999),
            Ok(None),
            "an entry with no placement is still an ordinary absence"
        );
    }

    /// `POST /resolve` over a database it cannot read is a server fault, and has to say so. A 200
    /// carrying "no spawn point for `npc:823`" would send the author hunting a data problem that
    /// does not exist while the real one — an unreadable snapshot — goes unreported.
    #[tokio::test]
    async fn a_backend_read_failure_is_a_500_rather_than_a_200_reporting_a_missing_spawn() {
        let campaign = r#"{
          "id": "018f0000-0000-7000-8000-000000000001",
          "name": "Elwynn opener",
          "graphs": [{
            "id": "018f0000-0000-7000-8000-000000000002",
            "name": "Northshire",
            "entry_node": "018f0000-0000-7000-8000-000000000010",
            "nodes": [
              { "id": "018f0000-0000-7000-8000-000000000010",
                "type": "questing.Travel",
                "intent": { "to": { "ref": "npc:823", "label": "Deputy Willem" } } }
            ],
            "edges": []
          }]
        }"#;

        let error = crate::handlers::resolve(
            Extension(unreadable_db()),
            Bytes::from(campaign.to_string()),
        )
        .await
        .expect_err("an unreadable database is not a resolvable campaign");

        assert_eq!(error.0, StatusCode::INTERNAL_SERVER_ERROR);
        let message = error.1 .0["error"]
            .as_str()
            .expect("the server's error shape is `{\"error\": …}`")
            .to_string();
        assert!(
            message.contains("spawn") && !message.contains("no spawn point"),
            "the operator must be told the read failed, not that the npc has no spawn: {message}"
        );
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
            .expect("the snapshot is readable")
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
            .expect("the snapshot is readable")
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
            assert_eq!(
                db.spawn(kind, 1),
                Ok(None),
                "{kind} must not report a spawn, and not reporting one is not a failure"
            );
        }
    }

    #[test]
    fn an_unspawned_entry_is_none_rather_than_the_world_origin() {
        assert_eq!(resolver_db().spawn(EntityKind::Npc, 99_999_999), Ok(None));
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
            assert_eq!(db.label(kind, id), Ok(Some(expected.to_string())));
        }
    }

    #[test]
    fn an_unknown_entry_has_no_label() {
        assert_eq!(resolver_db().label(EntityKind::Npc, 99_999_999), Ok(None));
    }

    #[test]
    fn the_quest_relations_are_read_from_the_two_separate_tables() {
        let db = resolver_db();
        assert_eq!(db.quest_giver(783), Ok(Some(823)), "Deputy Willem offers it");
        assert_eq!(db.quest_ender(783), Ok(Some(197)), "Marshal McBride takes it");
        assert_eq!(db.quest_giver(99_999_999), Ok(None));
        assert_eq!(db.quest_ender(99_999_999), Ok(None));
    }
}
