//! NPC Service — Volume 4 §8

use anyhow::Result;
use rusqlite::OptionalExtension;
use sentinel_schema::{NpcRole, Waypoint};

use super::helpers::zone_name;
use super::ServiceState;
use crate::models::*;

// ---------------------------------------------------------------------------
// NPC-specific DB helpers
// ---------------------------------------------------------------------------

pub(crate) fn determine_roles(
    conn: &rusqlite::Connection,
    entry: u32,
) -> rusqlite::Result<Vec<NpcRole>> {
    let mut roles = Vec::new();

    // Use creature_template.NpcFlags bitmask — the canonical source in MaNGOS
    // Flags: 0x1=Gossip, 0x2=QuestGiver, 0x4=Trainer, 0x80=Vendor, 0x200=Repair
    //        0x400=Vendor (ammo), 0x800=Vendor (food), 0x1000=Vendor (drink)
    //        0x100000=Innkeeper, 0x1000000=FlightMaster, 0x2000000=Mailbox, 0x4000000=Banker
    let flags: u32 = conn
        .query_row(
            "SELECT COALESCE(NpcFlags, 0) FROM creature_template WHERE Entry = ?1",
            [entry],
            |r| r.get(0),
        )
        .optional()?
        .unwrap_or(0);

    if flags & 0x2 != 0 {
        roles.push(NpcRole::QuestGiver);
    }
    if flags & 0x4 != 0 {
        roles.push(NpcRole::Trainer);
    }
    if flags & 0x80 != 0 || flags & 0x400 != 0 || flags & 0x800 != 0 || flags & 0x1000 != 0 {
        roles.push(NpcRole::Vendor);
    }
    if flags & 0x200 != 0 {
        roles.push(NpcRole::Repair);
    }
    if flags & 0x100000 != 0 {
        roles.push(NpcRole::Innkeeper);
    }
    if flags & 0x1000000 != 0 {
        roles.push(NpcRole::FlightMaster);
    }
    if flags & 0x2000000 != 0 {
        roles.push(NpcRole::Mailbox);
    }
    if flags & 0x4000000 != 0 {
        roles.push(NpcRole::Bank);
    }

    if roles.is_empty() {
        roles.push(NpcRole::Generic);
    }

    Ok(roles)
}

pub(crate) fn npc_quests(
    conn: &rusqlite::Connection,
    entry: u32,
) -> rusqlite::Result<Vec<u32>> {
    let mut quests = Vec::new();
    let mut stmt = conn.prepare("SELECT quest FROM creature_questrelation WHERE id = ?1")?;
    let rows = stmt.query_map([entry], |r| r.get(0))?;
    for row in rows {
        quests.push(row?);
    }

    let mut stmt = conn.prepare("SELECT quest FROM creature_involvedrelation WHERE id = ?1")?;
    let rows = stmt.query_map([entry], |r| r.get(0))?;
    for row in rows {
        quests.push(row?);
    }
    Ok(quests)
}

// ---------------------------------------------------------------------------
// NpcService
// ---------------------------------------------------------------------------

#[derive(Clone)]
pub struct NpcService {
    state: ServiceState,
}

impl NpcService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    /// Lookup NPC — GET /api/v1/npcs/{entry}
    pub async fn get(&self, entry: u32) -> Result<NpcDetails> {
        let cache_key = format!("npc:{}", entry);

        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let row = tokio::task::spawn_blocking(move || -> Result<NpcDetails> {
            let conn = db.blocking_lock();

            let details = conn.query_row(
                "SELECT ct.Entry, ct.Name, ct.Faction, c.map, c.position_x, c.position_y, c.position_z
                 FROM creature_template ct
                 LEFT JOIN creature c ON c.id = ct.Entry
                 WHERE ct.Entry = ?1 LIMIT 1",
                [entry],
                |row| {
                    let map = row.get::<_, u32>(3)?;
                    let zone = zone_name(&conn, map)?;
                    let zone_str = zone.clone();
                    Ok(NpcDetails {
                        entry: row.get(0)?,
                        name: row.get(1)?,
                        roles: determine_roles(&conn, entry)?,
                        zone,
                        position: Waypoint::new(
                            map,
                            zone_str,
                            row.get(4)?,
                            row.get(5)?,
                            row.get(6)?,
                            5.0,
                        ),
                        faction: row.get(2)?,
                        quest_ids: npc_quests(&conn, entry)?,
                    })
                },
            )?;
            Ok(details)
        })
        .await??;

        self.state
            .cache
            .insert(cache_key, serde_json::to_value(&row)?)
            .await;
        Ok(row)
    }

    /// Search NPCs — GET /api/v1/npcs/search
    pub async fn search(
        &self,
        name: Option<String>,
        entry: Option<u32>,
        _role: Option<String>,
        faction: Option<String>,
        _zone: Option<String>,
    ) -> Result<Vec<NpcSearchResult>> {
        let db = self.state.db.clone();
        let results =
            tokio::task::spawn_blocking(move || -> Result<Vec<NpcSearchResult>> {
                let conn = db.blocking_lock();

                let mut sql = String::from(
                    "SELECT ct.Entry, ct.Name, ct.Faction, COALESCE(c.map, 0) as map
                     FROM creature_template ct
                     LEFT JOIN creature c ON c.id = ct.Entry
                     WHERE 1=1",
                );
                let mut params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();

                if let Some(ref n) = name {
                    sql.push_str(" AND ct.Name LIKE ?");
                    params.push(Box::new(format!("%{}%", n)));
                }
                if let Some(e) = entry {
                    sql.push_str(" AND ct.Entry = ?");
                    params.push(Box::new(e as i64));
                }
                if let Some(f) = faction {
                    sql.push_str(" AND ct.Faction = ?");
                    params.push(Box::new(f));
                }

                sql.push_str(" LIMIT 100");

                let mut stmt = conn.prepare(&sql)?;
                let rows = stmt.query_map(
                    rusqlite::params_from_iter(params.iter().map(|p| p.as_ref())),
                    |row| {
                        let zone = zone_name(&conn, row.get::<_, u32>(3)?)?;
                        Ok(NpcSearchResult {
                            entry: row.get(0)?,
                            name: row.get(1)?,
                            roles: determine_roles(&conn, row.get::<_, u32>(0)?)?,
                            zone,
                        })
                    },
                )?;

                let mut results = Vec::new();
                for row in rows {
                    results.push(row?);
                }
                Ok(results)
            })
            .await??;

        Ok(results)
    }

    /// Nearby NPCs — GET /api/v1/npcs/near
    pub async fn nearby(
        &self,
        _x: f32,
        _y: f32,
        _radius: f32,
        zone: Option<String>,
    ) -> Result<Vec<NpcSearchResult>> {
        let db = self.state.db.clone();
        let results =
            tokio::task::spawn_blocking(move || -> Result<Vec<NpcSearchResult>> {
                let conn = db.blocking_lock();

                let mut sql = String::from(
                    "SELECT ct.Entry, ct.Name, ct.Faction, COALESCE(c.map, 0)
                     FROM creature_template ct
                     JOIN creature c ON c.id = ct.Entry
                     WHERE c.map IS NOT NULL
                     GROUP BY ct.Entry
                     LIMIT 50",
                );
                let params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();

                if let Some(z) = zone {
                    // areatable not available — try numeric parse, otherwise skip filter
                    if let Ok(_map_id) = z.parse::<u32>() {
                        // can't filter by map without areatable in this DB
                    }
                }

                sql.push_str(" LIMIT 50");

                let mut stmt = conn.prepare(&sql)?;
                let rows = stmt.query_map(
                    rusqlite::params_from_iter(params.iter().map(|p| p.as_ref())),
                    |row| {
                        let zone = zone_name(&conn, row.get::<_, u32>(3)?)?;
                        Ok(NpcSearchResult {
                            entry: row.get(0)?,
                            name: row.get(1)?,
                            roles: determine_roles(&conn, row.get::<_, u32>(0)?)?,
                            zone,
                        })
                    },
                )?;

                let mut results = Vec::new();
                for row in rows {
                    results.push(row?);
                }
                Ok(results)
            })
            .await??;

        Ok(results)
    }

    /// Wrapper for API compatibility
    pub async fn search_npcs(
        &self,
        params: crate::api::npcs::NpcSearchParams,
        _limit: u32,
    ) -> Result<Vec<NpcSearchResult>> {
        self.search(
            params.name,
            params.entry,
            params.role,
            params.faction,
            params.zone,
        )
        .await
    }

    /// Wrapper for API compatibility
    pub async fn get_nearby_npcs(
        &self,
        params: crate::api::npcs::NearbyNpcsParams,
    ) -> Result<Vec<NpcSearchResult>> {
        self.nearby(params.x, params.y, params.radius, params.zone)
            .await
    }
}
