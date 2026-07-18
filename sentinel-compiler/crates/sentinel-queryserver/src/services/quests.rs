//! Quest Service — Volume 4 §7

use anyhow::Result;
use rusqlite::OptionalExtension;
use sentinel_schema::{NpcRole, Waypoint};

use super::helpers::zone_name;
use super::ServiceState;
use crate::error::QueryError;
use crate::models::*;

// ---------------------------------------------------------------------------
// Quest-specific DB helpers (private to this module)
// ---------------------------------------------------------------------------

fn quest_objectives(
    conn: &rusqlite::Connection,
    quest_id: u32,
) -> rusqlite::Result<Vec<QuestObjective>> {
    let mut stmt = conn.prepare(
        "SELECT ObjectiveText1, ObjectiveText2, ObjectiveText3, ObjectiveText4,
                ReqItemId1, ReqItemId2, ReqItemId3, ReqItemId4,
                ReqItemCount1, ReqItemCount2, ReqItemCount3, ReqItemCount4,
                ReqCreatureOrGOId1, ReqCreatureOrGOId2, ReqCreatureOrGOId3, ReqCreatureOrGOId4,
                ReqCreatureOrGOCount1, ReqCreatureOrGOCount2, ReqCreatureOrGOCount3, ReqCreatureOrGOCount4,
                ReqSpellCast1, ReqSpellCast2, ReqSpellCast3, ReqSpellCast4
         FROM quest_template WHERE entry = ?1",
    )?;

    let row = stmt.query_row([quest_id], |row| {
        let texts = [
            row.get::<_, Option<String>>(0)?,
            row.get::<_, Option<String>>(1)?,
            row.get::<_, Option<String>>(2)?,
            row.get::<_, Option<String>>(3)?,
        ];
        let item_ids = [
            row.get::<_, u32>(4)?,
            row.get(5)?,
            row.get(6)?,
            row.get(7)?,
        ];
        let item_counts = [
            row.get::<_, u32>(8)?,
            row.get(9)?,
            row.get(10)?,
            row.get(11)?,
        ];
        let creature_ids = [
            row.get::<_, u32>(12)?,
            row.get(13)?,
            row.get(14)?,
            row.get(15)?,
        ];
        let creature_counts = [
            row.get::<_, u32>(16)?,
            row.get(17)?,
            row.get(18)?,
            row.get(19)?,
        ];
        let spell_ids = [
            row.get::<_, u32>(20)?,
            row.get(21)?,
            row.get(22)?,
            row.get(23)?,
        ];

        let mut objectives = Vec::new();
        for slot in 0..4 {
            if item_ids[slot] != 0 || creature_ids[slot] != 0 || spell_ids[slot] != 0 {
                objectives.push(QuestObjective {
                    slot: (slot + 1) as u32,
                    item_id: item_ids[slot],
                    item_count: item_counts[slot],
                    creature_or_go_id: creature_ids[slot],
                    creature_or_go_count: creature_counts[slot],
                    spell_id: spell_ids[slot],
                    text: texts[slot].clone(),
                });
            }
        }
        Ok(objectives)
    })?;

    Ok(row)
}

fn quest_rewards(
    conn: &rusqlite::Connection,
    quest_id: u32,
) -> rusqlite::Result<Vec<QuestReward>> {
    let mut stmt = conn.prepare(
        "SELECT RewItemId1, RewItemId2, RewItemId3, RewItemId4,
                RewItemCount1, RewItemCount2, RewItemCount3, RewItemCount4,
                RewChoiceItemId1, RewChoiceItemId2, RewChoiceItemId3, RewChoiceItemId4,
                RewChoiceItemId5, RewChoiceItemId6,
                RewChoiceItemCount1, RewChoiceItemCount2, RewChoiceItemCount3, RewChoiceItemCount4,
                RewChoiceItemCount5, RewChoiceItemCount6
         FROM quest_template WHERE entry = ?1",
    )?;

    let rewards = stmt.query_row([quest_id], |row| {
        let reward_ids = [
            row.get::<_, u32>(0)?,
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
        ];
        let reward_counts = [
            row.get::<_, u32>(4)?,
            row.get(5)?,
            row.get(6)?,
            row.get(7)?,
        ];
        let choice_ids = [
            row.get::<_, u32>(8)?,
            row.get(9)?,
            row.get(10)?,
            row.get(11)?,
            row.get(12)?,
            row.get(13)?,
        ];
        let choice_counts = [
            row.get::<_, u32>(14)?,
            row.get(15)?,
            row.get(16)?,
            row.get(17)?,
            row.get(18)?,
            row.get(19)?,
        ];

        let mut results = Vec::new();
        for slot in 0..4 {
            if reward_ids[slot] != 0 {
                results.push(QuestReward {
                    slot: (slot + 1) as u32,
                    item_id: reward_ids[slot],
                    item_count: reward_counts[slot],
                    choice: false,
                });
            }
        }
        for slot in 0..6 {
            if choice_ids[slot] != 0 {
                results.push(QuestReward {
                    slot: (slot + 1) as u32,
                    item_id: choice_ids[slot],
                    item_count: choice_counts[slot],
                    choice: true,
                });
            }
        }
        Ok(results)
    })?;

    Ok(rewards)
}

fn quest_chain(
    conn: &rusqlite::Connection,
    quest_id: u32,
) -> rusqlite::Result<QuestChain> {
    let prev: Option<u32> = conn
        .query_row(
            "SELECT PrevQuestId FROM quest_template WHERE entry = ?1",
            [quest_id],
            |r| r.get(0),
        )
        .optional()?;

    let next: Option<u32> = conn
        .query_row(
            "SELECT NextQuestId FROM quest_template WHERE entry = ?1",
            [quest_id],
            |r| r.get(0),
        )
        .optional()?;

    let next_in_chain: Option<u32> = conn
        .query_row(
            "SELECT NextQuestInChain FROM quest_template WHERE entry = ?1",
            [quest_id],
            |r| r.get(0),
        )
        .optional()?;

    Ok(QuestChain {
        accept: prev.into_iter().collect(),
        quests: vec![quest_id],
        followups: next.into_iter().collect(),
        branches: vec![],
        end: next_in_chain.into_iter().collect(),
    })
}

fn quest_prerequisites(
    conn: &rusqlite::Connection,
    quest_id: u32,
) -> rusqlite::Result<Vec<u32>> {
    let mut stmt = conn.prepare(
        "SELECT entry FROM quest_template WHERE NextQuestId = ?1 OR NextQuestInChain = ?1",
    )?;
    let rows = stmt.query_map([quest_id], |r| r.get(0))?;
    Ok(rows.filter_map(Result::ok).collect())
}

fn quest_followups(conn: &rusqlite::Connection, quest_id: u32) -> rusqlite::Result<Vec<u32>> {
    let mut stmt = conn.prepare("SELECT entry FROM quest_template WHERE PrevQuestId = ?1")?;
    let rows = stmt.query_map([quest_id], |r| r.get(0))?;
    Ok(rows.filter_map(Result::ok).collect())
}

// ---------------------------------------------------------------------------
// QuestService
// ---------------------------------------------------------------------------

#[derive(Clone)]
pub struct QuestService {
    state: ServiceState,
}

impl QuestService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    /// Search quests — GET /api/v1/quests/search
    pub async fn search(
        &self,
        query: Option<String>,
        zone: Option<String>,
        min_level: Option<u32>,
        max_level: Option<u32>,
        faction: Option<String>,
        limit: Option<u32>,
    ) -> Result<Vec<QuestSearchResult>> {
        let cache_key = format!(
            "quest_search:{:?}:{:?}:{:?}:{:?}:{:?}:{:?}",
            query, zone, min_level, max_level, faction, limit
        );

        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let results =
            tokio::task::spawn_blocking(move || -> Result<Vec<QuestSearchResult>> {
                let conn = db.blocking_lock();

                let mut sql = String::from(
                    "SELECT qt.entry, qt.Title, qt.QuestLevel, qt.MinLevel, qt.ZoneOrSort
                     FROM quest_template qt
                     WHERE 1=1",
                );

                let mut params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();

                if let Some(q) = &query {
                    sql.push_str(" AND qt.Title LIKE ?");
                    params.push(Box::new(format!("%{}%", q)));
                }
                if let Some(_z) = &zone {
                    // areatable not available in this DB — filter by ZoneOrSort numeric if possible
                    sql.push_str(" AND qt.ZoneOrSort > 0");
                }
                if let Some(l) = min_level {
                    sql.push_str(" AND qt.MinLevel >= ?");
                    params.push(Box::new(l as i64));
                }
                if let Some(l) = max_level {
                    sql.push_str(" AND qt.MaxLevel <= ?");
                    params.push(Box::new(l as i64));
                }
                if let Some(f) = &faction {
                    sql.push_str(" AND qt.RequiredRaces & ? != 0");
                    let faction_mask = match f.as_str() {
                        "Alliance" => 1101,
                        "Horde" => 690,
                        _ => 0,
                    };
                    params.push(Box::new(faction_mask));
                }

                sql.push_str(" ORDER BY qt.entry LIMIT ?");
                params.push(Box::new(limit.unwrap_or(50) as i64));

                let mut stmt = conn.prepare(&sql)?;
                let rows = stmt.query_map(
                    rusqlite::params_from_iter(params.iter().map(|p| p.as_ref())),
                    |row| {
                        let zone_id: i32 = row.get(4)?;
                        Ok(QuestSearchResult {
                            id: row.get(0)?,
                            title: row.get(1)?,
                            level: row.get(2)?,
                            min_level: row.get(3)?,
                            zone: format!("ZoneID:{}", zone_id),
                            giver: 0,
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

        self.state
            .cache
            .insert(cache_key, serde_json::to_value(&results)?)
            .await;
        Ok(results)
    }

    /// Get quest details — GET /api/v1/quests/{id}
    pub async fn get_details(&self, quest_id: u32) -> Result<QuestDetails> {
        let cache_key = format!("quest_details:{}", quest_id);

        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let details = tokio::task::spawn_blocking(move || -> Result<QuestDetails> {
            let conn = db.blocking_lock();

            let quest_row = conn.query_row(
                "SELECT entry, Title, MinLevel, MaxLevel, QuestLevel, ZoneOrSort,
                        PrevQuestId, NextQuestId, NextQuestInChain, BreadcrumbForQuestId,
                        RequiredClasses, RequiredRaces
                 FROM quest_template WHERE entry = ?1",
                [quest_id],
                |row| {
                    // MaNGOS uses -1 as sentinel for "no value" — read as i32, convert to u32
                    let entry: u32 = row.get(0)?;
                    let title: String = row.get(1)?;
                    let min_level: u32 = row.get(2)?;
                    let max_level: u32 = row.get(3)?;
                    let quest_level: u32 = row.get(4)?;
                    let zone_or_sort: u32 = row.get(5)?;
                    let prev: i32 = row.get(6)?;
                    let next: i32 = row.get(7)?;
                    let next_chain: i32 = row.get(8)?;
                    let breadcrumb: i32 = row.get(9)?;
                    let classes: u32 = row.get(10)?;
                    let races: u32 = row.get(11)?;
                    Ok((
                        entry, title, min_level, max_level, quest_level, zone_or_sort,
                        prev.max(0) as u32, next.max(0) as u32,
                        next_chain.max(0) as u32, breadcrumb.max(0) as u32,
                        classes, races,
                    ))
                },
            )?;

            let objectives = quest_objectives(&conn, quest_id)?;
            let rewards = quest_rewards(&conn, quest_id)?;
            let chain = quest_chain(&conn, quest_id)?;
            let prerequisites = quest_prerequisites(&conn, quest_id)?;
            let followups = quest_followups(&conn, quest_id)?;

            Ok(QuestDetails {
                id: quest_row.0,
                title: quest_row.1,
                min_level: quest_row.2,
                max_level: quest_row.3,
                level: quest_row.4,
                zone: quest_row.5.to_string(),
                giver: quest_row.6,
                turn_in: quest_row.7,
                objectives,
                rewards,
                chain,
                prerequisites,
                followups,
                exclusive_quests: vec![],
                required_items: vec![],
                required_kills: vec![],
            })
        })
        .await??;

        self.state
            .cache
            .insert(cache_key, serde_json::to_value(&details)?)
            .await;
        Ok(details)
    }

    /// Get quest chain — GET /api/v1/quests/{id}/chain
    pub async fn get_quest_chain(&self, quest_id: u32, limit: u32) -> Result<QuestChain> {
        let cache_key = format!("quest_chain:{}:{}", quest_id, limit);
        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let details = self.get_details(quest_id).await?;
        let chain = details.chain;

        self.state
            .cache
            .insert(cache_key, serde_json::to_value(&chain)?)
            .await;
        Ok(chain)
    }

    /// Nearby quests — GET /api/v1/quests/near
    pub async fn get_nearby_quests(
        &self,
        params: crate::api::quests::NearbyQuestsParams,
    ) -> Result<Vec<QuestSearchResult>> {
        let _zone_filter = params.zone;

        let db = self.state.db.clone();
        let results =
            tokio::task::spawn_blocking(move || -> Result<Vec<QuestSearchResult>> {
                let conn = db.blocking_lock();

                let sql = String::from(
                    "SELECT qt.entry, qt.Title, qt.QuestLevel, qt.MinLevel, qt.ZoneOrSort
                     FROM quest_template qt
                     WHERE qt.ZoneOrSort > 0
                     ORDER BY qt.entry
                     LIMIT 50",
                );

                let query_params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();

                let mut stmt = conn.prepare(&sql)?;
                let rows = stmt.query_map(
                    rusqlite::params_from_iter(query_params.iter().map(|p| p.as_ref())),
                    |row| {
                        let zone_id: i32 = row.get(4)?;
                        Ok(QuestSearchResult {
                            id: row.get(0)?,
                            title: row.get(1)?,
                            level: row.get(2)?,
                            min_level: row.get(3)?,
                            zone: format!("ZoneID:{}", zone_id),
                            giver: 0,
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

    /// Get quest NPCs — GET /api/v1/quests/{id}/npcs
    pub async fn get_quest_npcs(
        &self,
        quest_id: u32,
        relation: &str,
        map_id: Option<u32>,
    ) -> Result<Vec<NpcDetails>> {
        let relation = relation.to_owned();

        let db = self.state.db.clone();
        let results = tokio::task::spawn_blocking(move || -> Result<Vec<NpcDetails>> {
            let conn = db.blocking_lock();

            let table = match relation.as_str() {
                "giver" => "creature_questrelation",
                "turnin" => "creature_involvedrelation",
                _ => {
                    return Err(
                        QueryError::InvalidRequest("relation must be giver or turnin".into())
                            .into(),
                    )
                }
            };

            let mut sql = format!(
                "SELECT c.id, ct.Name, c.map, c.position_x, c.position_y, c.position_z
                 FROM {table} r
                 JOIN creature_template ct ON ct.Entry = r.id
                 LEFT JOIN creature c ON c.id = r.id
                 WHERE r.quest = ?1"
            );
            let mut params: Vec<Box<dyn rusqlite::ToSql>> = vec![Box::new(quest_id as i64)];

            if let Some(map) = map_id {
                sql.push_str(" AND c.map = ?2");
                params.push(Box::new(map as i64));
            }

            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(
                rusqlite::params_from_iter(params.iter().map(|p| p.as_ref())),
                |row| {
                    let map = row.get::<_, u32>(2)?;
                    let zone = zone_name(&conn, map)?;
                    let zone_str = zone.clone();
                    Ok(NpcDetails {
                        entry: row.get(0)?,
                        name: row.get(1)?,
                        roles: vec![if relation == "giver" {
                            NpcRole::QuestGiver
                        } else {
                            NpcRole::QuestGiver
                        }],
                        zone,
                        position: Waypoint::new(
                            map,
                            zone_str,
                            row.get(3)?,
                            row.get(4)?,
                            row.get(5)?,
                            5.0,
                        ),
                        faction: String::new(),
                        quest_ids: vec![quest_id],
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
    pub async fn search_quests(
        &self,
        params: crate::api::quests::QuestSearchParams,
        limit: u32,
    ) -> Result<Vec<QuestSearchResult>> {
        self.search(
            params.query,
            params.zone,
            params.min_level,
            params.max_level,
            params.faction,
            Some(limit),
        )
        .await
    }
}
