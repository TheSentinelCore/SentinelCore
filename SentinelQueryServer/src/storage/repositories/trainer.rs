use std::sync::Arc;

use rusqlite::{params, params_from_iter, types::Value};

use crate::error::AppError;
use crate::models::{PagedResponse, TrainerDetail, TrainerEntity, TrainerSpell};
use crate::storage::query::{
    decode_list_cursor, decode_nearby_cursor, encode_list_cursor, encode_nearby_cursor,
    map_faction_team,
};
use crate::storage::SqliteStore;
use crate::validation::TRAINER_MASK;

const ENDPOINT_TRAINERS_LIST: &str = "trainers_list";
const ENDPOINT_TRAINERS_NEARBY: &str = "trainers_nearby";

#[derive(Debug, Clone)]
pub struct TrainerListQuery {
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
    pub trainer_type: Option<String>,
    pub class_id: Option<i64>,
    pub profession_id: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct TrainerNearbyQuery {
    pub x: f64,
    pub y: f64,
    pub radius: f64,
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
    pub trainer_type: Option<String>,
    pub class_id: Option<i64>,
    pub profession_id: Option<i64>,
}

#[derive(Clone)]
pub struct TrainerRepository {
    store: Arc<SqliteStore>,
}

impl TrainerRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn list_trainers(
        &self,
        map_id: i64,
        query: &TrainerListQuery,
    ) -> Result<PagedResponse<TrainerEntity>, AppError> {
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
                ct.TrainerType,
                ct.TrainerClass,
                ct.TrainerRace,
                ct.TrainerSpell,
                ct.TrainerTemplateId,
                ct.NpcFlags,
                ct.Faction,
                fs.Team,
                (
                    SELECT COUNT(*) FROM npc_trainer nt
                    WHERE nt.entry = c.id
                ) + (
                    SELECT COUNT(*) FROM npc_trainer_template ntt
                    WHERE ntt.entry = ct.TrainerTemplateId
                ) AS trainer_spell_count
            FROM creature c
            JOIN creature_template ct ON ct.Entry = c.id
            LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
            WHERE c.map = ?
              AND (
                    (ct.NpcFlags & ?) != 0
                    OR EXISTS(SELECT 1 FROM npc_trainer nt2 WHERE nt2.entry = c.id)
                    OR (ct.TrainerTemplateId > 0 AND EXISTS(SELECT 1 FROM npc_trainer_template ntt2 WHERE ntt2.entry = ct.TrainerTemplateId))
                  )
            ",
        );

        let mut bind: Vec<Value> = vec![map_id.into(), TRAINER_MASK.into()];
        append_trainer_filters(&mut sql, &mut bind, query);

        if let Some(raw_cursor) = &query.cursor {
            let (entry, guid) =
                decode_list_cursor(ENDPOINT_TRAINERS_LIST, &query.dataset_version, raw_cursor)?;
            sql.push_str(" AND (c.id > ? OR (c.id = ? AND c.guid > ?))");
            bind.push(entry.into());
            bind.push(entry.into());
            bind.push(guid.into());
        }

        sql.push_str(" ORDER BY c.id ASC, c.guid ASC LIMIT ?");
        bind.push((query.limit as i64 + 1).into());

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(bind.iter()), |row| {
            Ok(row_to_trainer_entity(row, None))
        })?;

        let mut items: Vec<TrainerEntity> = rows.collect::<Result<_, _>>()?;

        let next_cursor = if items.len() > query.limit as usize {
            let last = items.pop().expect("len > limit guarantees trailing row");
            Some(encode_list_cursor(
                ENDPOINT_TRAINERS_LIST,
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

    pub fn nearby_trainers(
        &self,
        map_id: i64,
        query: &TrainerNearbyQuery,
    ) -> Result<PagedResponse<TrainerEntity>, AppError> {
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
                ct.TrainerType,
                ct.TrainerClass,
                ct.TrainerRace,
                ct.TrainerSpell,
                ct.TrainerTemplateId,
                ct.NpcFlags,
                ct.Faction,
                fs.Team,
                (
                    SELECT COUNT(*) FROM npc_trainer nt
                    WHERE nt.entry = c.id
                ) + (
                    SELECT COUNT(*) FROM npc_trainer_template ntt
                    WHERE ntt.entry = ct.TrainerTemplateId
                ) AS trainer_spell_count
            FROM creature c
            JOIN creature_template ct ON ct.Entry = c.id
            LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
            WHERE c.map = ?
              AND c.position_x BETWEEN ? AND ?
              AND c.position_y BETWEEN ? AND ?
              AND (
                    (ct.NpcFlags & ?) != 0
                    OR EXISTS(SELECT 1 FROM npc_trainer nt2 WHERE nt2.entry = c.id)
                    OR (ct.TrainerTemplateId > 0 AND EXISTS(SELECT 1 FROM npc_trainer_template ntt2 WHERE ntt2.entry = ct.TrainerTemplateId))
                  )
            ",
        );

        let mut bind: Vec<Value> = vec![
            map_id.into(),
            min_x.into(),
            max_x.into(),
            min_y.into(),
            max_y.into(),
            TRAINER_MASK.into(),
        ];

        append_trainer_filters(
            &mut sql,
            &mut bind,
            &TrainerListQuery {
                limit: query.limit,
                cursor: query.cursor.clone(),
                dataset_version: query.dataset_version.clone(),
                trainer_type: query.trainer_type.clone(),
                class_id: query.class_id,
                profession_id: query.profession_id,
            },
        );

        sql.push_str(" ORDER BY c.guid ASC");

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(bind.iter()), |row| {
            let x: f64 = row.get(4)?;
            let y: f64 = row.get(5)?;
            let dist_sq = ((x - query.x) * (x - query.x)) + ((y - query.y) * (y - query.y));
            Ok((dist_sq, row_to_trainer_entity(row, Some(dist_sq.sqrt()))))
        })?;

        let mut candidates: Vec<(f64, TrainerEntity)> = rows
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
                decode_nearby_cursor(ENDPOINT_TRAINERS_NEARBY, &query.dataset_version, raw_cursor)?;
            candidates.retain(|(dist_sq, entity)| {
                *dist_sq > cursor_distance_sq
                    || (*dist_sq == cursor_distance_sq && entity.guid > cursor_guid)
            });
        }

        let next_cursor = if candidates.len() > query.limit as usize {
            let (dist_sq, entity) = candidates
                .drain(query.limit as usize..)
                .next()
                .expect("len > limit guarantees trailing row");
            Some(encode_nearby_cursor(
                ENDPOINT_TRAINERS_NEARBY,
                &query.dataset_version,
                dist_sq,
                entity.guid,
            )?)
        } else {
            None
        };

        let items: Vec<TrainerEntity> = candidates
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

    pub fn trainer_detail(&self, entry: i64) -> Result<TrainerDetail, AppError> {
        let conn = self.store.open_read_only()?;

        conn.query_row(
            "
            SELECT
                ct.Entry,
                ct.Name,
                ct.NpcFlags,
                ct.TrainerType,
                ct.TrainerClass,
                ct.TrainerRace,
                ct.Faction,
                fs.Team,
                (
                    SELECT COUNT(*) FROM npc_trainer nt
                    WHERE nt.entry = ct.Entry
                ) + (
                    SELECT COUNT(*) FROM npc_trainer_template ntt
                    WHERE ntt.entry = ct.TrainerTemplateId
                ) AS trainer_spell_count
            FROM creature_template ct
            LEFT JOIN faction_store fs ON fs.Entry = ct.Faction
            WHERE ct.Entry = ?1
              AND (
                    (ct.NpcFlags & ?2) != 0
                    OR EXISTS(SELECT 1 FROM npc_trainer nt2 WHERE nt2.entry = ct.Entry)
                    OR (ct.TrainerTemplateId > 0 AND EXISTS(SELECT 1 FROM npc_trainer_template ntt2 WHERE ntt2.entry = ct.TrainerTemplateId))
                  )
            LIMIT 1
            ",
            params![entry, TRAINER_MASK],
            |row| {
                let trainer_type = classify_trainer_type(
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(0)?,
                );

                Ok(TrainerDetail {
                    entry: row.get(0)?,
                    name: row.get(1)?,
                    npc_flags: row.get(2)?,
                    trainer_type,
                    trainer_class: row.get(4)?,
                    trainer_race: row.get(5)?,
                    trainer_spell_count: row.get(8)?,
                    faction_id: row.get(6)?,
                    faction_team: map_faction_team(row.get::<_, Option<i64>>(7)?),
                })
            },
        )
        .map_err(|_| AppError::entity_not_found("trainer", entry))
    }

    pub fn trainer_spells(&self, entry: i64) -> Result<Vec<TrainerSpell>, AppError> {
        let conn = self.store.open_read_only()?;

        let trainer_template_id: i64 = conn
            .query_row(
                "SELECT TrainerTemplateId FROM creature_template WHERE Entry = ?1 LIMIT 1",
                [entry],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let mut stmt = conn.prepare(
            "
            SELECT
                spell,
                spellcost,
                reqskill,
                reqskillvalue,
                reqlevel,
                ReqAbility1,
                ReqAbility2,
                ReqAbility3,
                source
            FROM (
                SELECT
                    spell,
                    spellcost,
                    reqskill,
                    reqskillvalue,
                    reqlevel,
                    ReqAbility1,
                    ReqAbility2,
                    ReqAbility3,
                    'npc_trainer' AS source
                FROM npc_trainer
                WHERE entry = ?1

                UNION ALL

                SELECT
                    spell,
                    spellcost,
                    reqskill,
                    reqskillvalue,
                    reqlevel,
                    ReqAbility1,
                    ReqAbility2,
                    ReqAbility3,
                    'npc_trainer_template' AS source
                FROM npc_trainer_template
                WHERE entry = ?2
            )
            ORDER BY spell ASC, reqlevel ASC, source ASC
            ",
        )?;

        let rows = stmt.query_map(params![entry, trainer_template_id], |row| {
            Ok(TrainerSpell {
                spell: row.get(0)?,
                spell_cost: row.get(1)?,
                req_skill: row.get(2)?,
                req_skill_value: row.get(3)?,
                req_level: row.get(4)?,
                req_ability_1: row.get(5)?,
                req_ability_2: row.get(6)?,
                req_ability_3: row.get(7)?,
                source: row.get(8)?,
            })
        })?;

        Ok(rows.collect::<Result<_, _>>()?)
    }
}

fn append_trainer_filters(sql: &mut String, bind: &mut Vec<Value>, query: &TrainerListQuery) {
    match query.trainer_type.as_deref() {
        Some("class") => sql.push_str(" AND ct.TrainerClass > 0"),
        Some("profession") => sql.push_str(" AND ct.TrainerType > 0"),
        Some("any") | None => {}
        Some(_) => {}
    }

    if let Some(class_id) = query.class_id {
        sql.push_str(" AND ct.TrainerClass = ?");
        bind.push(class_id.into());
    }

    if let Some(profession_id) = query.profession_id {
        sql.push_str(" AND ct.TrainerSpell = ?");
        bind.push(profession_id.into());
    }
}

fn classify_trainer_type(trainer_type: i64, trainer_class: i64, _entry: i64) -> String {
    if trainer_class > 0 {
        "class".to_string()
    } else if trainer_type > 0 {
        "profession".to_string()
    } else {
        "any".to_string()
    }
}

fn row_to_trainer_entity(row: &rusqlite::Row<'_>, distance: Option<f64>) -> TrainerEntity {
    let trainer_type = classify_trainer_type(
        row.get::<_, i64>(7).unwrap_or_default(),
        row.get::<_, i64>(8).unwrap_or_default(),
        row.get::<_, i64>(1).unwrap_or_default(),
    );

    TrainerEntity {
        guid: row.get(0).unwrap_or_default(),
        entry: row.get(1).unwrap_or_default(),
        name: row.get(2).unwrap_or_default(),
        map_id: row.get(3).unwrap_or_default(),
        x: row.get(4).unwrap_or_default(),
        y: row.get(5).unwrap_or_default(),
        z: row.get(6).unwrap_or_default(),
        distance,
        trainer_type,
        trainer_class: row.get(8).unwrap_or_default(),
        trainer_race: row.get(9).unwrap_or_default(),
        trainer_spell_count: row.get(15).unwrap_or_default(),
        faction_id: row.get(13).unwrap_or_default(),
        faction_team: map_faction_team(row.get::<_, Option<i64>>(14).unwrap_or(None)),
    }
}
