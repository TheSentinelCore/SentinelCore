use std::sync::Arc;

use rusqlite::{params_from_iter, types::Value};

use crate::error::AppError;
use crate::models::{PagedResponse, UtilityEntity};
use crate::storage::query::{
    decode_list_cursor, decode_nearby_cursor, encode_list_cursor, encode_nearby_cursor,
    map_faction_team,
};
use crate::storage::SqliteStore;
use crate::validation::NPC_FLAG_FLIGHT_MASTER;

const ENDPOINT_FLIGHT_LIST: &str = "flight_masters_list";
const ENDPOINT_FLIGHT_NEARBY: &str = "flight_masters_nearby";

#[derive(Debug, Clone)]
pub struct UtilityListQuery {
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
}

#[derive(Debug, Clone)]
pub struct UtilityNearbyQuery {
    pub x: f64,
    pub y: f64,
    pub radius: f64,
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
}

#[derive(Clone)]
pub struct FlightMasterRepository {
    store: Arc<SqliteStore>,
}

impl FlightMasterRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn list_flight_masters(
        &self,
        map_id: i64,
        query: &UtilityListQuery,
    ) -> Result<PagedResponse<UtilityEntity>, AppError> {
        list_utility_entities(
            &self.store,
            map_id,
            query,
            NPC_FLAG_FLIGHT_MASTER,
            ENDPOINT_FLIGHT_LIST,
        )
    }

    pub fn nearby_flight_masters(
        &self,
        map_id: i64,
        query: &UtilityNearbyQuery,
    ) -> Result<PagedResponse<UtilityEntity>, AppError> {
        nearby_utility_entities(
            &self.store,
            map_id,
            query,
            NPC_FLAG_FLIGHT_MASTER,
            ENDPOINT_FLIGHT_NEARBY,
        )
    }
}

pub(crate) fn list_utility_entities(
    store: &SqliteStore,
    map_id: i64,
    query: &UtilityListQuery,
    required_flag: i64,
    endpoint: &str,
) -> Result<PagedResponse<UtilityEntity>, AppError> {
    let conn = store.open_read_only()?;

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
            ct.Faction,
            fs.Team
        FROM creature c
        JOIN creature_template ct ON ct.Entry = c.id
        LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
        WHERE c.map = ?
          AND ((ct.NpcFlags & ?) != 0)
        ",
    );

    let mut bind: Vec<Value> = vec![map_id.into(), required_flag.into()];

    if let Some(raw_cursor) = &query.cursor {
        let (entry, guid) = decode_list_cursor(endpoint, &query.dataset_version, raw_cursor)?;
        sql.push_str(" AND (c.id > ? OR (c.id = ? AND c.guid > ?))");
        bind.push(entry.into());
        bind.push(entry.into());
        bind.push(guid.into());
    }

    sql.push_str(" ORDER BY c.id ASC, c.guid ASC LIMIT ?");
    bind.push((query.limit as i64 + 1).into());

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(bind.iter()), |row| {
        Ok(UtilityEntity {
            guid: row.get(0)?,
            entry: row.get(1)?,
            name: row.get(2)?,
            map_id: row.get(3)?,
            x: row.get(4)?,
            y: row.get(5)?,
            z: row.get(6)?,
            distance: None,
            faction_id: row.get(7)?,
            faction_team: map_faction_team(row.get::<_, Option<i64>>(8)?),
        })
    })?;

    let mut items: Vec<UtilityEntity> = rows.collect::<Result<_, _>>()?;

    let next_cursor = if items.len() > query.limit as usize {
        let last = items.pop().expect("len > limit guarantees trailing row");
        Some(encode_list_cursor(
            endpoint,
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

pub(crate) fn nearby_utility_entities(
    store: &SqliteStore,
    map_id: i64,
    query: &UtilityNearbyQuery,
    required_flag: i64,
    endpoint: &str,
) -> Result<PagedResponse<UtilityEntity>, AppError> {
    let conn = store.open_read_only()?;

    let min_x = query.x - query.radius;
    let max_x = query.x + query.radius;
    let min_y = query.y - query.radius;
    let max_y = query.y + query.radius;
    let radius_sq = query.radius * query.radius;

    let sql = "
        SELECT
            c.guid,
            c.id,
            ct.Name,
            c.map,
            CAST(c.position_x AS REAL),
            CAST(c.position_y AS REAL),
            CAST(c.position_z AS REAL),
            ct.Faction,
            fs.Team
        FROM creature c
        JOIN creature_template ct ON ct.Entry = c.id
        LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
        WHERE c.map = ?
          AND c.position_x BETWEEN ? AND ?
          AND c.position_y BETWEEN ? AND ?
          AND ((ct.NpcFlags & ?) != 0)
        ORDER BY c.guid ASC
    ";

    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(
        params_from_iter([
            Value::from(map_id),
            Value::from(min_x),
            Value::from(max_x),
            Value::from(min_y),
            Value::from(max_y),
            Value::from(required_flag),
        ]),
        |row| {
            let x: f64 = row.get(4)?;
            let y: f64 = row.get(5)?;
            let dist_sq = ((x - query.x) * (x - query.x)) + ((y - query.y) * (y - query.y));
            Ok((
                dist_sq,
                UtilityEntity {
                    guid: row.get(0)?,
                    entry: row.get(1)?,
                    name: row.get(2)?,
                    map_id: row.get(3)?,
                    x,
                    y,
                    z: row.get(6)?,
                    distance: Some(dist_sq.sqrt()),
                    faction_id: row.get(7)?,
                    faction_team: map_faction_team(row.get::<_, Option<i64>>(8)?),
                },
            ))
        },
    )?;

    let mut candidates: Vec<(f64, UtilityEntity)> = rows
        .filter_map(|row| row.ok())
        .filter(|(distance_sq, _)| *distance_sq <= radius_sq)
        .collect();

    candidates.sort_by(|(a_dist, a_entity), (b_dist, b_entity)| {
        a_dist
            .partial_cmp(b_dist)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a_entity.guid.cmp(&b_entity.guid))
    });

    if let Some(raw_cursor) = &query.cursor {
        let (cursor_distance_sq, cursor_guid) =
            decode_nearby_cursor(endpoint, &query.dataset_version, raw_cursor)?;
        candidates.retain(|(distance_sq, entity)| {
            *distance_sq > cursor_distance_sq
                || (*distance_sq == cursor_distance_sq && entity.guid > cursor_guid)
        });
    }

    let next_cursor = if candidates.len() > query.limit as usize {
        let (dist_sq, entity) = candidates
            .drain(query.limit as usize..)
            .next()
            .expect("len > limit guarantees trailing row");
        Some(encode_nearby_cursor(
            endpoint,
            &query.dataset_version,
            dist_sq,
            entity.guid,
        )?)
    } else {
        None
    };

    let items: Vec<UtilityEntity> = candidates
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
