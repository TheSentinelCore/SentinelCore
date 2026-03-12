use std::sync::Arc;

use rusqlite::{params_from_iter, types::Value};

use crate::error::AppError;
use crate::models::{PagedResponse, VendorEntity};
use crate::storage::query::{
    decode_list_cursor, decode_nearby_cursor, encode_list_cursor, encode_nearby_cursor,
    map_faction_team,
};
use crate::storage::SqliteStore;
use crate::validation::{can_repair, can_sell, NPC_FLAG_REPAIR, VENDOR_MASK};

const ENDPOINT_VENDORS_LIST: &str = "vendors_list";
const ENDPOINT_VENDORS_NEARBY: &str = "vendors_nearby";

#[derive(Debug, Clone)]
pub struct VendorListQuery {
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
    pub require_sell: bool,
    pub require_repair: bool,
    pub faction: Option<String>,
}

#[derive(Debug, Clone)]
pub struct VendorNearbyQuery {
    pub x: f64,
    pub y: f64,
    pub radius: f64,
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
    pub require_sell: bool,
    pub require_repair: bool,
    pub faction: Option<String>,
}

#[derive(Clone)]
pub struct VendorRepository {
    store: Arc<SqliteStore>,
}

impl VendorRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn list_vendors(
        &self,
        map_id: i64,
        query: &VendorListQuery,
    ) -> Result<PagedResponse<VendorEntity>, AppError> {
        let conn = self.store.open_read_only()?;

        let mut sql = String::from(
            "
            SELECT
                c.guid,
                c.id,
                ct.Name,
                c.map,
                CAST(c.position_x AS REAL),
                CAST(c.position_y AS REAL),
                CAST(c.position_z AS REAL),
                ct.NpcFlags,
                ct.Faction,
                fs.Team,
                (
                    SELECT COUNT(*) FROM npc_vendor nv
                    WHERE nv.entry = c.id
                ) AS vendor_item_count
            FROM creature c
            JOIN creature_template ct ON ct.Entry = c.id
            LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
            WHERE c.map = ?
              AND (((ct.NpcFlags & ?) != 0) OR EXISTS(SELECT 1 FROM npc_vendor nv2 WHERE nv2.entry = c.id))
            ",
        );

        let mut bind: Vec<Value> = vec![map_id.into(), VENDOR_MASK.into()];

        if query.require_sell {
            sql.push_str(
                " AND (((ct.NpcFlags & ?) != 0) OR EXISTS(SELECT 1 FROM npc_vendor nv3 WHERE nv3.entry = c.id))",
            );
            bind.push(VENDOR_MASK.into());
        }

        if query.require_repair {
            sql.push_str(" AND ((ct.NpcFlags & ?) != 0)");
            bind.push(NPC_FLAG_REPAIR.into());
        }

        append_faction_filter(&mut sql, &mut bind, &query.faction);

        if let Some(raw_cursor) = &query.cursor {
            let (entry, guid) =
                decode_list_cursor(ENDPOINT_VENDORS_LIST, &query.dataset_version, raw_cursor)?;
            sql.push_str(" AND (c.id > ? OR (c.id = ? AND c.guid > ?))");
            bind.push(entry.into());
            bind.push(entry.into());
            bind.push(guid.into());
        }

        sql.push_str(" ORDER BY c.id ASC, c.guid ASC LIMIT ?");
        bind.push((query.limit as i64 + 1).into());

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(bind.iter()), |row| {
            let npc_flags = row.get::<_, i64>(7)?;
            let faction_team = map_faction_team(row.get::<_, Option<i64>>(9)?);

            Ok(VendorEntity {
                guid: row.get(0)?,
                entry: row.get(1)?,
                name: row.get(2)?,
                map_id: row.get(3)?,
                x: row.get(4)?,
                y: row.get(5)?,
                z: row.get(6)?,
                distance: None,
                npc_flags,
                can_sell: can_sell(npc_flags),
                can_repair: can_repair(npc_flags),
                vendor_item_count: row.get(10)?,
                faction_id: row.get(8)?,
                faction_team,
            })
        })?;

        let mut items: Vec<VendorEntity> = rows.collect::<Result<_, _>>()?;
        let next_cursor = if items.len() > query.limit as usize {
            let last = items.pop().expect("len > limit guarantees a trailing row");
            Some(encode_list_cursor(
                ENDPOINT_VENDORS_LIST,
                &query.dataset_version,
                last.entry,
                last.guid,
            )?)
        } else {
            None
        };

        Ok(PagedResponse {
            count: items.len(),
            items,
            next_cursor,
        })
    }

    pub fn nearby_vendors(
        &self,
        map_id: i64,
        query: &VendorNearbyQuery,
    ) -> Result<PagedResponse<VendorEntity>, AppError> {
        let conn = self.store.open_read_only()?;
        let min_x = query.x - query.radius;
        let max_x = query.x + query.radius;
        let min_y = query.y - query.radius;
        let max_y = query.y + query.radius;
        let radius_sq = query.radius * query.radius;

        let mut sql = String::from(
            "
            SELECT
                c.guid,
                c.id,
                ct.Name,
                c.map,
                CAST(c.position_x AS REAL),
                CAST(c.position_y AS REAL),
                CAST(c.position_z AS REAL),
                ct.NpcFlags,
                ct.Faction,
                fs.Team,
                (
                    SELECT COUNT(*) FROM npc_vendor nv
                    WHERE nv.entry = c.id
                ) AS vendor_item_count
            FROM creature c
            JOIN creature_template ct ON ct.Entry = c.id
            LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
            WHERE c.map = ?
              AND c.position_x BETWEEN ? AND ?
              AND c.position_y BETWEEN ? AND ?
              AND (((ct.NpcFlags & ?) != 0) OR EXISTS(SELECT 1 FROM npc_vendor nv2 WHERE nv2.entry = c.id))
            ",
        );

        let mut bind: Vec<Value> = vec![
            map_id.into(),
            min_x.into(),
            max_x.into(),
            min_y.into(),
            max_y.into(),
            VENDOR_MASK.into(),
        ];

        if query.require_sell {
            sql.push_str(
                " AND (((ct.NpcFlags & ?) != 0) OR EXISTS(SELECT 1 FROM npc_vendor nv3 WHERE nv3.entry = c.id))",
            );
            bind.push(VENDOR_MASK.into());
        }

        if query.require_repair {
            sql.push_str(" AND ((ct.NpcFlags & ?) != 0)");
            bind.push(NPC_FLAG_REPAIR.into());
        }

        append_faction_filter(&mut sql, &mut bind, &query.faction);
        sql.push_str(" ORDER BY c.guid ASC");

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(bind.iter()), |row| {
            let x: f64 = row.get(4)?;
            let y: f64 = row.get(5)?;
            let dist_sq = ((x - query.x) * (x - query.x)) + ((y - query.y) * (y - query.y));

            let npc_flags = row.get::<_, i64>(7)?;
            let faction_team = map_faction_team(row.get::<_, Option<i64>>(9)?);

            Ok((
                dist_sq,
                VendorEntity {
                    guid: row.get(0)?,
                    entry: row.get(1)?,
                    name: row.get(2)?,
                    map_id: row.get(3)?,
                    x,
                    y,
                    z: row.get(6)?,
                    distance: Some(dist_sq.sqrt()),
                    npc_flags,
                    can_sell: can_sell(npc_flags),
                    can_repair: can_repair(npc_flags),
                    vendor_item_count: row.get(10)?,
                    faction_id: row.get(8)?,
                    faction_team,
                },
            ))
        })?;

        let mut candidates: Vec<(f64, VendorEntity)> = rows
            .filter_map(|row| row.ok())
            .filter(|(dist_sq, _)| *dist_sq <= radius_sq)
            .collect();

        candidates.sort_by(|(a_dist, a_entity), (b_dist, b_entity)| {
            a_dist
                .partial_cmp(b_dist)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a_entity.guid.cmp(&b_entity.guid))
        });

        if let Some(raw_cursor) = &query.cursor {
            let (cursor_distance_sq, cursor_guid) =
                decode_nearby_cursor(ENDPOINT_VENDORS_NEARBY, &query.dataset_version, raw_cursor)?;
            candidates.retain(|(dist_sq, entity)| {
                *dist_sq > cursor_distance_sq
                    || (*dist_sq == cursor_distance_sq && entity.guid > cursor_guid)
            });
        }

        let mut candidates = candidates;
        let next_cursor = if candidates.len() > query.limit as usize {
            let (dist_sq, entity) = candidates
                .drain(query.limit as usize..)
                .next()
                .expect("len > limit guarantees trailing row");
            Some(encode_nearby_cursor(
                ENDPOINT_VENDORS_NEARBY,
                &query.dataset_version,
                dist_sq,
                entity.guid,
            )?)
        } else {
            None
        };

        let items: Vec<VendorEntity> = candidates
            .into_iter()
            .take(query.limit as usize)
            .map(|(_, entity)| entity)
            .collect();

        Ok(PagedResponse {
            count: items.len(),
            items,
            next_cursor,
        })
    }
}

fn append_faction_filter(sql: &mut String, _bind: &mut Vec<Value>, faction: &Option<String>) {
    match faction.as_deref() {
        Some("alliance") => sql.push_str(" AND fs.Team = 469"),
        Some("horde") => sql.push_str(" AND fs.Team = 67"),
        Some("neutral") => sql.push_str(" AND COALESCE(fs.Team, 0) NOT IN (67, 469)"),
        _ => {}
    }
}
