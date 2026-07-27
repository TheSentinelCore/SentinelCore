use rusqlite::Connection;
use sentinel_models::platform::EntityKind;
use sentinel_query_types::*;
use std::sync::{Arc, Mutex};

use crate::search::{escape_like, SearchHit, SearchKind, SpawnPoint, SpawnType, MAX_SEARCH_LIMIT};

#[derive(Clone)]
pub struct Db(pub Arc<Mutex<Connection>>);

impl Db {
    pub fn new(path: &str) -> Self {
        let conn = Connection::open_with_flags(
            path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )
        .expect("failed to open tbcmangos.sqlite");
        Self(Arc::new(Mutex::new(conn)))
    }

    // Helper to execute a query and map to Vec<T>
    fn query_map<T, F>(&self, sql: &str, params: impl rusqlite::Params, f: F) -> Result<Vec<T>, String>
    where
        F: FnMut(&rusqlite::Row<'_>) -> Result<T, rusqlite::Error>,
    {
        let db = self.0.lock().unwrap();
        let mut stmt = db.prepare(sql).map_err(|e| e.to_string())?;
        let mut rows = stmt.query_map(params, f).map_err(|e| e.to_string())?;
        let mut result = Vec::new();
        while let Some(row) = rows.next() {
            result.push(row.map_err(|e| e.to_string())?);
        }
        Ok(result)
    }

    pub fn get_quest(&self, id: u32) -> Result<Option<QuestDetail>, String> {
        // Get basic quest info
        let quest_opt = self.query_map::<_, _>(
            "SELECT entry, Title, QuestLevel, MinLevel, PrevQuestId, NextQuestId, NextQuestInChain, ExclusiveGroup \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, i64>(7)?,
                ))
            }
        )?;

        let Some((entry, title_opt, quest_level, min_level, prev_quest_id, next_quest_id, next_quest_in_chain, _exclusive_group)) = quest_opt.first().cloned() else {
            return Ok(None);
        };
        let title = title_opt.unwrap_or_default();

        // Get giver (first creature_questrelation)
        let giver_opt = self.query_map::<_, _>(
            "SELECT id FROM creature_questrelation WHERE quest = ?1 LIMIT 1",
            [id],
            |row| row.get::<_, i64>(0)
        )?;
        let giver_entry = giver_opt.first().map(|x| *x as u32);

// Get finisher (first creature_involvedrelation)
        let finisher_opt = self.query_map::<_, _>(
            "SELECT id FROM creature_involvedrelation WHERE quest = ?1 LIMIT 1",
            [id],
            |row| row.get::<_, i64>(0)
        )?;
        let finisher_entry = finisher_opt.first().map(|x| *x as u32);

        // Collect objectives from ReqCreatureOrGOId1..4 that are >0
        let mut objectives = Vec::new();
        let obj_res = self.query_map::<_, _>(
            "SELECT ReqCreatureOrGOId1, ReqCreatureOrGOId2, ReqCreatureOrGOId3, ReqCreatureOrGOId4 \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            }
        )?;
        if let Some((c1, c2, c3, c4)) = obj_res.first().cloned() {
            for &c in &[c1, c2, c3, c4] {
                if c > 0 {
                    objectives.push(format!("Objective {}", c));
                }
            }
        }

        // Structured objectives (ADR 06 Level-1 enrichment): what each slot actually requires, so
        // the compiler can synthesise a satisfying action rather than emit an unreachable gate.
        let mut structured_objectives = Vec::new();

        // Creature/GO kill-or-interact slots. A NEGATIVE ReqCreatureOrGOId is a gameobject entry.
        let creature_rows = self.query_map::<_, _>(
            "SELECT ReqCreatureOrGOId1, ReqCreatureOrGOCount1, ReqCreatureOrGOId2, ReqCreatureOrGOCount2, \
                    ReqCreatureOrGOId3, ReqCreatureOrGOCount3, ReqCreatureOrGOId4, ReqCreatureOrGOCount4 \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok([
                    (row.get::<_, i64>(0)?, row.get::<_, i64>(1)?),
                    (row.get::<_, i64>(2)?, row.get::<_, i64>(3)?),
                    (row.get::<_, i64>(4)?, row.get::<_, i64>(5)?),
                    (row.get::<_, i64>(6)?, row.get::<_, i64>(7)?),
                ])
            },
        )?;
        if let Some(slots) = creature_rows.first() {
            for (i, &(target, count)) in slots.iter().enumerate() {
                if target == 0 || count <= 0 {
                    continue;
                }
                let (kind, entry) = if target > 0 {
                    (ObjectiveKind::KillCreature, target as u32)
                } else {
                    (ObjectiveKind::InteractObject, (-target) as u32)
                };
                structured_objectives.push(QuestObjective {
                    index: (i + 1) as u8,
                    kind,
                    target_entry: entry,
                    required: count as u32,
                    sources: Vec::new(),
                });
            }
        }

        // Item slots, plus the creatures whose loot table yields each item.
        let item_rows = self.query_map::<_, _>(
            "SELECT ReqItemId1, ReqItemCount1, ReqItemId2, ReqItemCount2, \
                    ReqItemId3, ReqItemCount3, ReqItemId4, ReqItemCount4 \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok([
                    (row.get::<_, i64>(0)?, row.get::<_, i64>(1)?),
                    (row.get::<_, i64>(2)?, row.get::<_, i64>(3)?),
                    (row.get::<_, i64>(4)?, row.get::<_, i64>(5)?),
                    (row.get::<_, i64>(6)?, row.get::<_, i64>(7)?),
                ])
            },
        )?;
        if let Some(slots) = item_rows.first() {
            for (i, &(item, count)) in slots.iter().enumerate() {
                if item <= 0 || count <= 0 {
                    continue;
                }
                let sources = self
                    .query_map::<_, _>(
                        "SELECT entry FROM creature_loot_template WHERE item = ?1",
                        [item],
                        |row| row.get::<_, i64>(0),
                    )
                    .unwrap_or_default()
                    .into_iter()
                    .map(|e| e as u32)
                    .collect::<Vec<u32>>();
                structured_objectives.push(QuestObjective {
                    index: (i + 1) as u8,
                    kind: ObjectiveKind::CollectItem,
                    target_entry: item as u32,
                    required: count as u32,
                    sources,
                });
            }
        }

        Ok(Some(QuestDetail {
            id: entry as u32,
            title,
            level: quest_level as u8,
            min_level: min_level as u8,
            required_quests: if prev_quest_id > 0 {
                vec![prev_quest_id as u32]
            } else {
                Vec::new()
            },
            next_quests: [next_quest_id, next_quest_in_chain]
                .into_iter()
                .filter(|&x| x > 0)
                .map(|x| x as u32)
                .collect(),
            giver_entry,
            finisher_entry,
            objectives,
            structured_objectives,
        }))
    }

    /// Chain information for a quest: prerequisites, follow-ups, chain depth, and branches.
    ///
    /// Prerequisites are quests with PrevQuestId pointing to this quest (reversed link).
    /// Follow-ups are the quest's NextQuestId and NextQuestInChain.
    /// Branches are other quests sharing the same ExclusiveGroup.
    /// Chain depth is computed by following PrevQuestId links backwards.
    pub fn get_quest_chain(&self, id: u32) -> Result<Option<QuestChain>, String> {
        // First, get the quest's own data
        let quest_opt = self.query_map::<_, _>(
            "SELECT entry, Title, PrevQuestId, NextQuestId, NextQuestInChain, ExclusiveGroup \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            }
        )?;

        let Some((entry, title_opt, prev_quest_id, next_quest_id, next_quest_in_chain, exclusive_group)) = quest_opt.first().cloned() else {
            return Ok(None);
        };
        let title = title_opt.unwrap_or_default();

        // Helper: resolve a quest ID to a QuestChainLink
        let resolve_link = |qid: i64| -> Option<QuestChainLink> {
            if qid <= 0 { return None; }
            let rows = self.query_map::<_, _>(
                "SELECT Title, ExclusiveGroup FROM quest_template WHERE entry = ?1",
                [qid],
                |row| Ok((
                    row.get::<_, Option<String>>(0)?.unwrap_or_default(),
                    row.get::<_, i64>(1)?,
                ))
            ).ok()?;
            rows.first().map(|(t, eg)| QuestChainLink {
                quest_id: qid as u32,
                title: t.clone(),
                exclusive_group: *eg as i32,
            })
        };

        // Prerequisites: quests that must be completed before this one.
        // Standard MaNGOS interpretation — PrevQuestId on THIS quest = a prerequisite to do first.
        let mut prerequisites: Vec<QuestChainLink> = Vec::new();
        if prev_quest_id > 0 {
            if let Some(link) = resolve_link(prev_quest_id) {
                prerequisites.push(link);
            }
        }

        // Also check if other quests list this quest as their follow-up (alternative prereq view).
        let prereq_from_others: Vec<QuestChainLink> = self.query_map::<_, _>(
            "SELECT entry, Title, ExclusiveGroup FROM quest_template WHERE NextQuestId = ?1 AND entry != ?2",
            [id as i64, prev_quest_id],
            |row| {
                Ok(QuestChainLink {
                    quest_id: row.get::<_, i64>(0)? as u32,
                    title: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    exclusive_group: row.get::<_, i64>(2)? as i32,
                })
            }
        )?;
        for link in prereq_from_others {
            if !prerequisites.iter().any(|p| p.quest_id == link.quest_id) {
                prerequisites.push(link);
            }
        }

        // Follow-ups: this quest's NextQuestId and NextQuestInChain
        let mut follow_ups: Vec<QuestChainLink> = Vec::new();
        for qid in [next_quest_id, next_quest_in_chain] {
            if let Some(link) = resolve_link(qid) {
                if !follow_ups.iter().any(|f| f.quest_id == link.quest_id) {
                    follow_ups.push(link);
                }
            }
        }

        // Branches: other quests sharing the same ExclusiveGroup (> 0 means exclusive group)
        let mut branches: Vec<QuestChainLink> = Vec::new();
        if exclusive_group > 0 {
            branches = self.query_map::<_, _>(
                "SELECT entry, Title, ExclusiveGroup FROM quest_template \
                 WHERE ExclusiveGroup = ?1 AND entry != ?2",
                [exclusive_group, id as i64],
                |row| {
                    Ok(QuestChainLink {
                        quest_id: row.get::<_, i64>(0)? as u32,
                        title: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                        exclusive_group: row.get::<_, i64>(2)? as i32,
                    })
                }
            )?;
        }

        // Chain depth: follow PrevQuestId links backwards from this quest to the root
        let chain_depth = self.compute_chain_depth(prev_quest_id);

        Ok(Some(QuestChain {
            quest_id: entry as u32,
            title,
            prerequisites,
            follow_ups,
            chain_depth,
            branches,
        }))
    }

    /// Recursively follow PrevQuestId to compute depth of the chain containing this quest.
    /// Starts from the prerequisite (prev_quest_id) and counts each step back to root.
    fn compute_chain_depth(&self, mut prev_quest_id: i64) -> u32 {
        if prev_quest_id <= 0 {
            return 1; // Just this quest itself
        }
        let mut depth: u32 = 1; // Count this quest
        let db = self.0.lock().unwrap();
        // Limit iterations to prevent infinite loops on bad data
        for _ in 0..100 {
            depth += 1;
            let next_prev: Option<i64> = db
                .query_row(
                    "SELECT PrevQuestId FROM quest_template WHERE entry = ?1",
                    [prev_quest_id],
                    |row| row.get(0),
                )
                .ok()
                .flatten();
            match next_prev {
                Some(id) if id > 0 => {
                    prev_quest_id = id;
                }
                _ => break,
            }
        }
        depth
    }

    /// Objects for a quest: parsed creature/GO/item requirements with names and sources.
    ///
    /// Returns parsed objectives from ReqCreatureOrGOId[1-4] and ReqItemId[1-4] fields,
    /// cross-referenced with names and creature loot sources.
    pub fn get_quest_objectives(&self, id: u32) -> Result<Option<QuestObjectivesResponse>, String> {
        // Get quest title and composite objective text
        let quest_opt = self.query_map::<_, _>(
            "SELECT entry, Title, Objectives \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, Option<String>>(2)?,
                ))
            }
        )?;

        let Some((entry, title_opt, obj_text_opt)) = quest_opt.first().cloned() else {
            return Ok(None);
        };
        let _title = title_opt.unwrap_or_default();
        let quest_id = entry as u32;

        // Resolve creature name from entry
        let creature_name = |creature_entry: u32| -> String {
            self.query_map::<_, _>(
                "SELECT Name FROM creature_template WHERE Entry = ?1",
                [creature_entry as i64],
                |row| row.get::<_, Option<String>>(0),
            )
            .ok()
            .and_then(|v| v.into_iter().flatten().next())
            .unwrap_or_else(|| format!("Creature {}", creature_entry))
        };

        // Resolve item name from entry
        let item_name = |item_entry: u32| -> String {
            self.query_map::<_, _>(
                "SELECT name FROM item_template WHERE entry = ?1",
                [item_entry as i64],
                |row| row.get::<_, Option<String>>(0),
            )
            .ok()
            .and_then(|v| v.into_iter().flatten().next())
            .unwrap_or_else(|| format!("Item {}", item_entry))
        };

        // Resolve gameobject name
        let go_name = |go_entry: u32| -> String {
            self.query_map::<_, _>(
                "SELECT name FROM gameobject_template WHERE entry = ?1",
                [go_entry as i64],
                |row| row.get::<_, Option<String>>(0),
            )
            .ok()
            .and_then(|v| v.into_iter().flatten().next())
            .unwrap_or_else(|| format!("Object {}", go_entry))
        };

        let mut objectives: Vec<ObjectiveResponseItem> = Vec::new();
        let mut text_parts: Vec<String> = Vec::new();

        // Creature/GO objectives from ReqCreatureOrGOId[1-4]
        let cro_rows = self.query_map::<_, _>(
            "SELECT ReqCreatureOrGOId1, ReqCreatureOrGOCount1, \
                    ReqCreatureOrGOId2, ReqCreatureOrGOCount2, \
                    ReqCreatureOrGOId3, ReqCreatureOrGOCount3, \
                    ReqCreatureOrGOId4, ReqCreatureOrGOCount4 \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok([
                    (row.get::<_, i64>(0)?, row.get::<_, i64>(1)?),
                    (row.get::<_, i64>(2)?, row.get::<_, i64>(3)?),
                    (row.get::<_, i64>(4)?, row.get::<_, i64>(5)?),
                    (row.get::<_, i64>(6)?, row.get::<_, i64>(7)?),
                ])
            }
        )?;

        if let Some(slots) = cro_rows.first() {
            for (i, &(target, count)) in slots.iter().enumerate() {
                if target == 0 { continue; }
                if count <= 0 { continue; }

                let (kind, entry) = if target > 0 {
                    ("kill".to_string(), target as u32)
                } else {
                    ("interact".to_string(), (-target) as u32)
                };
                let name = if target > 0 { creature_name(entry) } else { go_name(entry) };
                let kind_label = if target > 0 { "Kill" } else { "Interact with" };

                objectives.push(ObjectiveResponseItem {
                    index: (i + 1) as u8,
                    kind: kind.clone(),
                    entry,
                    name: name.clone(),
                    count: count as u32,
                    source_creatures: Vec::new(),
                });

                let count_label = if count > 1 { format!("{} ", count) } else { String::new() };
                text_parts.push(format!("{kind_label} {count_label}{name}"));
            }
        }

        // Item objectives from ReqItemId[1-4]
        let item_rows = self.query_map::<_, _>(
            "SELECT ReqItemId1, ReqItemCount1, ReqItemId2, ReqItemCount2, \
                    ReqItemId3, ReqItemCount3, ReqItemId4, ReqItemCount4 \
             FROM quest_template WHERE entry = ?1",
            [id],
            |row| {
                Ok([
                    (row.get::<_, i64>(0)?, row.get::<_, i64>(1)?),
                    (row.get::<_, i64>(2)?, row.get::<_, i64>(3)?),
                    (row.get::<_, i64>(4)?, row.get::<_, i64>(5)?),
                    (row.get::<_, i64>(6)?, row.get::<_, i64>(7)?),
                ])
            }
        )?;

        if let Some(slots) = item_rows.first() {
            // Compute starting index for item slots (after creature/GO slots)
            let base_index = objectives.len() as u8;
            for (i, &(item, count)) in slots.iter().enumerate() {
                if item <= 0 || count <= 0 { continue; }

                let name = item_name(item as u32);
                let sources = self
                    .query_map::<_, _>(
                        "SELECT entry FROM creature_loot_template WHERE item = ?1",
                        [item],
                        |row| row.get::<_, i64>(0),
                    )
                    .unwrap_or_default()
                    .into_iter()
                    .map(|e| e as u32)
                    .collect::<Vec<u32>>();

                objectives.push(ObjectiveResponseItem {
                    index: base_index + (i as u8) + 1,
                    kind: "collect".to_string(),
                    entry: item as u32,
                    name: name.clone(),
                    count: count as u32,
                    source_creatures: sources,
                });

                let count_label = if count > 1 { format!("{} ", count) } else { String::new() };
                text_parts.push(format!("Collect {count_label}{name}"));
            }
        }

        let objective_text = if !text_parts.is_empty() {
            text_parts.join(", ")
        } else {
            obj_text_opt.unwrap_or_default()
        };

        Ok(Some(QuestObjectivesResponse {
            quest_id,
            objectives,
            objective_text,
        }))
    }

    /// Creature entries whose loot table yields `item`.
    ///
    /// Level-1 enrichment turns a bare `.collect item,n` gate into a Kill on these creatures. An
    /// empty result means the item has no loot row (script-driven) — data, not an error.
    pub fn get_item_sources(&self, item: u32) -> Result<Vec<u32>, String> {
        Ok(self
            .query_map::<_, _>(
                "SELECT DISTINCT entry FROM creature_loot_template WHERE item = ?1",
                [item],
                |row| row.get::<_, i64>(0),
            )?
            .into_iter()
            .map(|e| e as u32)
            .collect())
    }

    pub fn search_quests(&self, query: &str) -> Result<Vec<QuestSummary>, String> {
        let db = self.0.lock().unwrap();
        let like = format!("%{}%", query);
        let mut stmt = db.prepare(
            "SELECT entry, Title, QuestLevel, MinLevel FROM quest_template WHERE Title LIKE ?1"
        )
        .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([like], |row| {
                Ok(QuestSummary {
                    id: row.get::<_, i64>(0)? as u32,
                    title: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    level: row.get::<_, i64>(2)? as u8,
                    min_level: row.get::<_, i64>(3)? as u8,
                })
            })
            .map_err(|e| e.to_string())?;
        let mut res = Vec::new();
        for row in rows {
            res.push(row.map_err(|e| e.to_string())?);
        }
        Ok(res)
    }

    pub fn get_npc(&self, entry: u32) -> Result<Option<NpcDetail>, String> {
        let db = self.0.lock().unwrap();
        let mut stmt = db.prepare(
            "SELECT ct.Entry, ct.Name, ct.Faction, ct.NpcFlags, c.position_x, c.position_y, c.position_z, c.map \
             FROM creature_template ct \
             LEFT JOIN creature c ON c.id = ct.Entry \
             WHERE ct.Entry = ?1"
        )
        .map_err(|e| e.to_string())?;
        let mut rows = stmt.query_map([entry], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, Option<f64>>(4)?,
                row.get::<_, Option<f64>>(5)?,
                row.get::<_, Option<f64>>(6)?,
                row.get::<_, Option<i64>>(7)?,
            ))
        })
        .map_err(|e| e.to_string())?;

        let Some(row) = rows.next().transpose().map_err(|e| e.to_string())? else {
            return Ok(None);
        };
        let (
            entry_val,
            name_opt,
            faction,
            npc_flags,
            pos_x,
            pos_y,
            pos_z,
            map_val,
        ) = row;
        let name = name_opt.unwrap_or_default();
        let map = map_val.unwrap_or(0) as u32;
        let pos_x = pos_x.unwrap_or(0.0);
        let pos_y = pos_y.unwrap_or(0.0);
        let pos_z = pos_z.unwrap_or(0.0);

        // Compute roles from NpcFlags
        let mut roles = Vec::new();
        let flags = npc_flags;
        if flags & 2 != 0 {
            roles.push("QuestGiver".to_string());
        }
        if flags & 128 != 0 {
            roles.push("Vendor".to_string());
        }
        if flags & 16 != 0 {
            roles.push("Trainer".to_string());
        }
        if flags & 4096 != 0 {
            roles.push("Repairer".to_string());
        }
        if flags & 64 != 0 {
            roles.push("Innkeeper".to_string());
        }
        if flags & 8192 != 0 {
            roles.push("FlightMaster".to_string());
        }
        if flags & 131072 != 0 {
            roles.push("Banker".to_string());
        }
        if flags & 262144 != 0 {
            roles.push("Auctioneer".to_string());
        }
        // Note: Mailbox flag is typically not in NpcFlags; it's often a separate gameobject type

        Ok(Some(NpcDetail {
            entry: entry_val as u32,
            name,
            faction: faction.to_string(),
            positions: vec![WorldPos {
                map,
                x: pos_x as f32,
                y: pos_y as f32,
                z: pos_z as f32,
            }],
            roles,
        }))
    }

    pub fn search_npcs(&self, query: &str) -> Result<Vec<NpcSummary>, String> {
        let db = self.0.lock().unwrap();
        let like = format!("%{}%", query);
        let mut stmt = db.prepare(
            "SELECT Entry, Name, Faction FROM creature_template WHERE Name LIKE ?1"
        )
        .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([like], |row| {
                Ok(NpcSummary {
                    entry: row.get::<_, i64>(0)? as u32,
                    name: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    faction: row.get::<_, i64>(2)?.to_string(),
                })
            })
            .map_err(|e| e.to_string())?;
        let mut res = Vec::new();
        for row in rows {
            res.push(row.map_err(|e| e.to_string())?);
        }
        Ok(res)
    }

    pub fn get_vendor(&self, entry: u32) -> Result<Option<VendorInfo>, String> {
        let db = self.0.lock().unwrap();
        let name_opt = db
            .prepare("SELECT Name FROM creature_template WHERE Entry = ?1")
            .map_err(|e| e.to_string())?
            .query_row([entry], |row| row.get::<_, Option<String>>(0))
            .map_err(|e| e.to_string())?;
        let name = name_opt.unwrap_or_default();

        let mut stmt = db
            .prepare("SELECT item FROM npc_vendor WHERE entry = ?1")
            .map_err(|e| e.to_string())?;
        let mut items = Vec::new();
        let mut iter = stmt.query_map([entry], |row| row.get::<_, i64>(0)).map_err(|e| e.to_string())?;
        while let Some(item) = iter.next() {
            items.push(item.map_err(|e| e.to_string())? as u32);
        }

        // Check repairs flag from NpcFlags
        let mut repairs_stmt = db
            .prepare("SELECT NpcFlags FROM creature_template WHERE Entry = ?1")
            .map_err(|e| e.to_string())?;
        let repairs = repairs_stmt
            .query_row([entry], |row| {
                let flags: i64 = row.get(0)?;
                Ok(flags & 4096 != 0)
            })
            .map_err(|e| e.to_string())?;

        Ok(Some(VendorInfo {
            entry,
            name,
            sells: items,
            repairs,
        }))
    }

    pub fn get_trainer(&self, entry: u32) -> Result<Option<TrainerInfo>, String> {
        let db = self.0.lock().unwrap();
        let name_opt = db
            .prepare("SELECT Name FROM creature_template WHERE Entry = ?1")
            .map_err(|e| e.to_string())?
            .query_row([entry], |row| row.get::<_, Option<String>>(0))
            .map_err(|e| e.to_string())?;
        let name = name_opt.unwrap_or_default();

        let mut stmt = db
            .prepare("SELECT spell FROM npc_trainer WHERE entry = ?1")
            .map_err(|e| e.to_string())?;
        let mut spells: Vec<String> = Vec::new();
        let mut iter = stmt.query_map([entry], |row| row.get::<_, i64>(0)).map_err(|e| e.to_string())?;
        while let Some(spell) = iter.next() {
            spells.push((spell.map_err(|e| e.to_string())? as u32).to_string());
        }

        Ok(Some(TrainerInfo {
            entry,
            name,
            trains: spells,
        }))
    }

    pub fn get_item(&self, entry: u32) -> Result<Option<ItemInfo>, String> {
        let db = self.0.lock().unwrap();
        let mut stmt = db.prepare(
            "SELECT entry, name, Quality, SellPrice FROM item_template WHERE entry = ?1"
        )
        .map_err(|e| e.to_string())?;
        let mut rows = stmt.query_map([entry], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, Option<i64>>(2)?,
                row.get::<_, Option<i64>>(3)?,
            ))
        })
        .map_err(|e| e.to_string())?;

        let Some(row) = rows.next().transpose().map_err(|e| e.to_string())? else {
            return Ok(None);
        };
        let (entry_val, name_opt, quality_opt, sell_price_opt) = row;
        Ok(Some(ItemInfo {
            entry: entry_val as u32,
            name: name_opt.unwrap_or_default(),
            quality: quality_opt.unwrap_or(0) as i32,
            sell_price: sell_price_opt.unwrap_or(0).max(0) as u32,
        }))
    }

    pub fn get_object(&self, entry: u32) -> Result<Option<ObjectInfo>, String> {
        let db = self.0.lock().unwrap();
        let mut stmt = db.prepare(
            "SELECT gt.entry, gt.name, gt.type, g.position_x, g.position_y, g.position_z, g.map \
             FROM gameobject_template gt \
             JOIN gameobject g ON g.id = gt.entry \
             WHERE gt.entry = ?1"
        )
        .map_err(|e| e.to_string())?;
        let mut rows = stmt.query_map([entry], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, i32>(2)?,
                row.get::<_, Option<f64>>(3)?,
                row.get::<_, Option<f64>>(4)?,
                row.get::<_, Option<f64>>(5)?,
                row.get::<_, Option<i64>>(6)?,
            ))
        })
        .map_err(|e| e.to_string())?;

        let Some(row) = rows.next().transpose().map_err(|e| e.to_string())? else {
            return Ok(None);
        };
        let (entry_val, name_opt, type_val, pos_x, pos_y, pos_z, map_val) = row;
        let name = name_opt.unwrap_or_default();
        let kind = type_val.to_string();
        let pos_x = pos_x.unwrap_or(0.0);
        let pos_y = pos_y.unwrap_or(0.0);
        let pos_z = pos_z.unwrap_or(0.0);
        let map = map_val.unwrap_or(0) as u32;

        Ok(Some(ObjectInfo {
            entry: entry_val as u32,
            name,
            kind,
            position: WorldPos {
                map,
                x: pos_x as f32,
                y: pos_y as f32,
                z: pos_z as f32,
            },
        }))
    }

    pub fn creatures_polygon(&self, creature_entry: u32) -> Result<Option<CreaturePolygon>, String> {
        let db = self.0.lock().unwrap();
        let mut stmt = db.prepare(
            "SELECT position_x, position_y, position_z, map FROM creature WHERE id = ?1"
        )
        .map_err(|e| e.to_string())?;
        let rows = stmt.query_map([creature_entry], |row| {
            Ok(WorldPos {
                map: row.get::<_, i64>(3)? as u32,
                x: row.get::<_, f64>(0)? as f32,
                y: row.get::<_, f64>(1)? as f32,
                z: row.get::<_, f64>(2)? as f32,
            })
        })
        .map_err(|e| e.to_string())?;
        
        let mut polygon = Vec::new();
        for row in rows {
            polygon.push(row.map_err(|e| e.to_string())?);
        }
        
        if polygon.is_empty() {
            Ok(None)
        } else {
            Ok(Some(CreaturePolygon {
                creature_entry,
                polygon,
            }))
        }
    }

    pub fn validate(&self, req: ValidateRequest) -> Result<ValidateResponse, String> {
        let mut diagnostics = Vec::new();
        
        for reference in &req.references {
            let parts: Vec<&str> = reference.split(':').collect();
            if parts.len() != 2 {
                diagnostics.push(ValidationDiagnostic {
                    severity: "Error".to_string(),
                    code: "INVALID_REFERENCE".to_string(),
                    message: format!("Invalid reference format: {}", reference),
                });
                continue;
            }
            
            let (r#type, id_str) = (parts[0], parts[1]);
            let id: i64 = match id_str.parse() {
                Ok(id) => id,
                Err(_) => {
                    diagnostics.push(ValidationDiagnostic {
                        severity: "Error".to_string(),
                        code: "INVALID_ID".to_string(),
                        message: format!("Invalid ID in reference: {}", reference),
                    });
                    continue;
                }
            };
            
            match r#type {
                "npc" => {
let exists = self.query_map::<bool, _>(
            "SELECT COUNT(*) > 0 FROM creature_template WHERE Entry = ?1",
            [id],
            |row| Ok(row.get::<_, i64>(0)? > 0)
        )?;
                    if !exists.first().copied().unwrap_or(false) {
                        diagnostics.push(ValidationDiagnostic {
                            severity: "Error".to_string(),
                            code: "NPC_NOT_FOUND".to_string(),
                            message: format!("NPC with entry {} not found", id),
                        });
                    }
                }
                "quest" => {
let exists = self.query_map::<bool, _>(
            "SELECT COUNT(*) > 0 FROM quest_template WHERE entry = ?1",
            [id],
            |row| Ok(row.get::<_, i64>(0)? > 0)
        )?;
                    if !exists.first().copied().unwrap_or(false) {
                        diagnostics.push(ValidationDiagnostic {
                            severity: "Error".to_string(),
                            code: "QUEST_NOT_FOUND".to_string(),
                            message: format!("Quest with id {} not found", id),
                        });
                    }
                }
                "object" => {
let exists = self.query_map::<bool, _>(
            "SELECT COUNT(*) > 0 FROM gameobject_template WHERE entry = ?1",
            [id],
            |row| Ok(row.get::<_, i64>(0)? > 0)
        )?;
                    if !exists.first().copied().unwrap_or(false) {
                        diagnostics.push(ValidationDiagnostic {
                            severity: "Error".to_string(),
                            code: "OBJECT_NOT_FOUND".to_string(),
                            message: format!("Object with entry {} not found", id),
                        });
                    }
                }
                _ => {
                    diagnostics.push(ValidationDiagnostic {
                        severity: "Error".to_string(),
                        code: "UNKNOWN_REFERENCE_TYPE".to_string(),
                        message: format!("Unknown reference type: {}", r#type),
                    });
                }
            }
        }
        
        Ok(ValidateResponse { diagnostics })
    }

    pub fn travel_estimate(&self, req: TravelEstimateRequest) -> Result<TravelEstimateResponse, String> {
        // Simple Euclidean distance divided by assumed speed (7 yd/s for running)
        let dx = req.from.x - req.to.x;
        let dy = req.from.y - req.to.y;
        let dz = req.from.z - req.to.z;
        let distance = (dx*dx + dy*dy + dz*dz).sqrt();
        let speed = 7.0; // yards per second (approximate running speed in WoW)
        let seconds = (distance / speed).ceil() as u64;

        Ok(TravelEstimateResponse { seconds })
    }

    /// Federated fuzzy search across npc / quest / item / object / area, ranked exact > prefix >
    /// substring. Backs the IDE's Smart Search, where one term is expected to surface every kind
    /// of entity at once.
    ///
    /// Each per-kind query carries its own `LIMIT`, so the cost is bounded before the merge —
    /// a caller cannot reach an unbounded LIKE sweep of 109k creatures from the query string.
    pub fn federated_search(&self, term: &str, limit: usize) -> Result<Vec<SearchHit>, String> {
        let limit = limit.clamp(1, MAX_SEARCH_LIMIT);
        let term = term.trim();
        if term.is_empty() {
            return Ok(Vec::new());
        }
        let escaped = escape_like(term);
        let prefix = format!("{escaped}%");
        let anywhere = format!("%{escaped}%");
        let per_kind = limit as i64;

        let mut hits = Vec::new();

        // The rank arithmetic is identical for every kind: 3 exact, 2 prefix, 1 substring. It is
        // computed in SQL so the per-kind LIMIT keeps the best candidates rather than an arbitrary
        // table-order slice.
        hits.extend(self.query_map::<SearchHit, _>(
            "SELECT t.Entry, t.Name, t.SubName, t.MinLevel, t.MaxLevel, t.rank, \
                    (SELECT c.map FROM creature c WHERE c.id = t.Entry LIMIT 1) \
             FROM ( \
               SELECT Entry, Name, SubName, MinLevel, MaxLevel, \
                      CASE WHEN lower(Name) = lower(?1) THEN 3 \
                           WHEN Name LIKE ?2 ESCAPE '\\' THEN 2 \
                           ELSE 1 END AS rank \
               FROM creature_template \
               WHERE Name LIKE ?3 ESCAPE '\\' \
               ORDER BY rank DESC, length(Name) ASC, Entry ASC LIMIT ?4 \
             ) t",
            rusqlite::params![term, prefix, anywhere, per_kind],
            |row| {
                let sub: Option<String> = row.get(2)?;
                let min: i64 = row.get(3)?;
                let max: i64 = row.get(4)?;
                let map: Option<i64> = row.get(6)?;
                Ok(SearchHit {
                    kind: SearchKind::Npc,
                    id: row.get::<_, i64>(0)? as u32,
                    name: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    context: npc_context(sub.as_deref(), min, max, map),
                    score: row.get::<_, i64>(5)? as u8,
                })
            },
        )?);

        hits.extend(self.query_map::<SearchHit, _>(
            "SELECT entry, Title, QuestLevel, MinLevel, \
                    CASE WHEN lower(Title) = lower(?1) THEN 3 \
                         WHEN Title LIKE ?2 ESCAPE '\\' THEN 2 \
                         ELSE 1 END AS rank \
             FROM quest_template \
             WHERE Title LIKE ?3 ESCAPE '\\' \
             ORDER BY rank DESC, length(Title) ASC, entry ASC LIMIT ?4",
            rusqlite::params![term, prefix, anywhere, per_kind],
            |row| {
                Ok(SearchHit {
                    kind: SearchKind::Quest,
                    id: row.get::<_, i64>(0)? as u32,
                    name: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    context: format!(
                        "Quest level {} - min level {}",
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?
                    ),
                    score: row.get::<_, i64>(4)? as u8,
                })
            },
        )?);

        hits.extend(self.query_map::<SearchHit, _>(
            "SELECT entry, name, ItemLevel, Quality, \
                    CASE WHEN lower(name) = lower(?1) THEN 3 \
                         WHEN name LIKE ?2 ESCAPE '\\' THEN 2 \
                         ELSE 1 END AS rank \
             FROM item_template \
             WHERE name LIKE ?3 ESCAPE '\\' \
             ORDER BY rank DESC, length(name) ASC, entry ASC LIMIT ?4",
            rusqlite::params![term, prefix, anywhere, per_kind],
            |row| {
                Ok(SearchHit {
                    kind: SearchKind::Item,
                    id: row.get::<_, i64>(0)? as u32,
                    name: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    context: format!(
                        "Item level {} - quality {}",
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?
                    ),
                    score: row.get::<_, i64>(4)? as u8,
                })
            },
        )?);

        hits.extend(self.query_map::<SearchHit, _>(
            "SELECT t.entry, t.name, t.type, t.rank, \
                    (SELECT g.map FROM gameobject g WHERE g.id = t.entry LIMIT 1) \
             FROM ( \
               SELECT entry, name, type, \
                      CASE WHEN lower(name) = lower(?1) THEN 3 \
                           WHEN name LIKE ?2 ESCAPE '\\' THEN 2 \
                           ELSE 1 END AS rank \
               FROM gameobject_template \
               WHERE name LIKE ?3 ESCAPE '\\' \
               ORDER BY rank DESC, length(name) ASC, entry ASC LIMIT ?4 \
             ) t",
            rusqlite::params![term, prefix, anywhere, per_kind],
            |row| {
                let map: Option<i64> = row.get(4)?;
                Ok(SearchHit {
                    kind: SearchKind::Object,
                    id: row.get::<_, i64>(0)? as u32,
                    name: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    context: match map {
                        Some(map) => format!("Object type {} - map {}", row.get::<_, i64>(2)?, map),
                        None => format!("Object type {} - not spawned", row.get::<_, i64>(2)?),
                    },
                    score: row.get::<_, i64>(3)? as u8,
                })
            },
        )?);

        // `game_tele` is the area source rather than `points_of_interest`: POI rows carry only x/y
        // with no map and no z, so an "area" hit from them could not be navigated to — the same
        // missing-ground-height failure this phase exists to fix.
        hits.extend(self.query_map::<SearchHit, _>(
            "SELECT id, name, map, \
                    CASE WHEN lower(name) = lower(?1) THEN 3 \
                         WHEN name LIKE ?2 ESCAPE '\\' THEN 2 \
                         ELSE 1 END AS rank \
             FROM game_tele \
             WHERE name LIKE ?3 ESCAPE '\\' \
             ORDER BY rank DESC, length(name) ASC, id ASC LIMIT ?4",
            rusqlite::params![term, prefix, anywhere, per_kind],
            |row| {
                Ok(SearchHit {
                    kind: SearchKind::Area,
                    id: row.get::<_, i64>(0)? as u32,
                    name: row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    context: format!("Map {}", row.get::<_, i64>(2)?),
                    score: row.get::<_, i64>(3)? as u8,
                })
            },
        )?);

        Ok(interleave_by_kind(hits, limit))
    }

    /// Spawn points for one entry. An entry that exists but is never placed in the world returns
    /// an empty vector — absence of a spawn is data, not an error.
    pub fn spawns(&self, kind: SpawnType, entry: u32) -> Result<Vec<SpawnPoint>, String> {
        let (table, _) = kind.tables();
        // The table name comes from the SpawnType enum, never from caller text.
        let sql = format!(
            "SELECT guid, map, position_x, position_y, position_z, orientation \
             FROM {table} WHERE id = ?1 ORDER BY guid ASC"
        );
        self.query_map::<SpawnPoint, _>(&sql, [entry], |row| {
            Ok(SpawnPoint {
                guid: row.get::<_, i64>(0)? as u32,
                map: row.get::<_, i64>(1)? as u32,
                position_x: row.get::<_, f64>(2)? as f32,
                position_y: row.get::<_, f64>(3)? as f32,
                position_z: row.get::<_, f64>(4)? as f32,
                orientation: row.get::<_, f64>(5)? as f32,
            })
        })
    }

    /// The current display name for an entity reference, or `None` when the snapshot has no row
    /// for it. `spell` and `map` have no name to give here — `spell_template` carries one but
    /// `EntityKind::Map` has no template table at all — so those return `Ok(None)` rather than an
    /// error, which is what "the database does not know this" means to the resolver.
    pub fn entity_label(&self, kind: EntityKind, id: u32) -> Result<Option<String>, String> {
        let sql = match kind {
            EntityKind::Npc => "SELECT Name FROM creature_template WHERE Entry = ?1",
            EntityKind::Quest => "SELECT Title FROM quest_template WHERE entry = ?1",
            EntityKind::Item => "SELECT name FROM item_template WHERE entry = ?1",
            EntityKind::Object => "SELECT name FROM gameobject_template WHERE entry = ?1",
            EntityKind::Area => "SELECT name FROM game_tele WHERE id = ?1",
            EntityKind::Spell => "SELECT SpellName FROM spell_template WHERE Id = ?1",
            EntityKind::Map => return Ok(None),
        };
        let names = self.query_map::<Option<String>, _>(sql, [id], |row| row.get(0))?;
        Ok(names.into_iter().flatten().next())
    }

    /// The npc that offers a quest. `ORDER BY id` is not decoration: a quest offered by several
    /// npcs would otherwise resolve to whichever row the planner returned first, and the resolver's
    /// byte-identity guarantee would depend on that.
    pub fn quest_giver(&self, quest_id: u32) -> Result<Option<u32>, String> {
        self.first_related_npc("creature_questrelation", quest_id)
    }

    /// The npc that takes a quest back. Frequently not the giver.
    pub fn quest_ender(&self, quest_id: u32) -> Result<Option<u32>, String> {
        self.first_related_npc("creature_involvedrelation", quest_id)
    }

    fn first_related_npc(&self, table: &'static str, quest_id: u32) -> Result<Option<u32>, String> {
        // The table name is a literal from the two callers above, never caller text.
        let sql = format!("SELECT id FROM {table} WHERE quest = ?1 ORDER BY id ASC LIMIT 1");
        let ids = self.query_map::<i64, _>(&sql, [quest_id], |row| row.get(0))?;
        Ok(ids.first().map(|id| *id as u32))
    }

    /// A deterministic identity for this snapshot's content, stamped onto every plan so a caller
    /// can tell a stale plan from a wrong one (ADR 09a §1.4).
    ///
    /// Derived from the schema cookie, the file's page count, the shipped `db_version` string, and
    /// the row counts of exactly the tables resolution reads. Cheap (header reads plus counted
    /// index scans, ~25 ms) and, unlike a file mtime or a hash of 300 MB, both stable across copies
    /// of the same snapshot and sensitive to the rows that actually change a plan.
    pub fn fingerprint(&self) -> Result<String, String> {
        let db = self.0.lock().unwrap();
        let mut material = String::new();

        for pragma in ["schema_version", "page_count"] {
            let value: i64 = db
                .query_row(&format!("PRAGMA {pragma}"), [], |row| row.get(0))
                .map_err(|e| e.to_string())?;
            material.push_str(&format!("{pragma}={value};"));
        }

        // MIN rather than LIMIT 1: an aggregate over an unordered table is the same value every
        // time, a row is not.
        let version: String = db
            .query_row("SELECT COALESCE(MIN(version), '') FROM db_version", [], |row| row.get(0))
            .map_err(|e| e.to_string())?;
        material.push_str(&format!("db_version={version};"));

        for table in FINGERPRINTED_TABLES {
            let count: i64 = db
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| row.get(0))
                .map_err(|e| e.to_string())?;
            material.push_str(&format!("{table}={count};"));
        }

        // The same polynomial `sentinel_models::platform::compute_content_hash` uses. Not
        // `DefaultHasher`: its output is explicitly not guaranteed stable across Rust releases, so
        // a toolchain upgrade would silently invalidate every stored plan's fingerprint.
        let mut hash: u64 = 0;
        for byte in material.bytes() {
            hash = hash.wrapping_mul(31).wrapping_add(byte as u64);
        }
        Ok(format!("tbcmangos@{hash:016x}"))
    }
}

/// Exactly the tables `SqliteResolverDb` reads. A row added anywhere else cannot change a plan, so
/// counting it would only invalidate fingerprints for no reason.
const FINGERPRINTED_TABLES: &[&str] = &[
    "creature",
    "creature_template",
    "creature_involvedrelation",
    "creature_questrelation",
    "game_tele",
    "gameobject",
    "gameobject_template",
    "item_template",
    "quest_template",
    "spell_template",
];

/// `creature_zone` is empty in this snapshot, so there is no zone name to show; the level band
/// plus the spawn map is the best disambiguator available.
fn npc_context(subname: Option<&str>, min_level: i64, max_level: i64, map: Option<i64>) -> String {
    let level = if min_level == max_level {
        format!("Level {min_level}")
    } else {
        format!("Level {min_level}-{max_level}")
    };
    let mut parts = Vec::new();
    if let Some(sub) = subname.map(str::trim).filter(|s| !s.is_empty()) {
        parts.push(format!("<{sub}>"));
    }
    parts.push(level);
    match map {
        Some(map) => parts.push(format!("map {map}")),
        None => parts.push("not spawned".to_string()),
    }
    parts.join(" - ")
}

/// Merge the per-kind hits into one page: every score tier is exhausted before the next, but
/// within a tier the kinds take turns.
///
/// Straight ordering by match quality starves the smaller tables — "wolf" matches 109 items and
/// only 9 quests, so a purely quality-ordered page is all items and the author never sees the
/// quest they were looking for. Turn-taking keeps exact above prefix above substring while still
/// showing every kind on the first page, which is what Smart Search is for.
fn interleave_by_kind(hits: Vec<SearchHit>, limit: usize) -> Vec<SearchHit> {
    // Shorter names first within a kind: "Fang" beats "Fanged Screecher" for the term "Fang".
    // The id breaks the remaining ties so the page is stable across runs.
    let mut buckets: Vec<Vec<SearchHit>> = vec![Vec::new(); SCORE_TIERS * KINDS];
    for hit in hits {
        let tier = SCORE_TIERS - usize::from(hit.score.clamp(1, SCORE_TIERS as u8));
        buckets[tier * KINDS + kind_order(hit.kind) as usize].push(hit);
    }
    for bucket in buckets.iter_mut() {
        bucket.sort_by(|a, b| {
            a.name
                .chars()
                .count()
                .cmp(&b.name.chars().count())
                .then_with(|| a.id.cmp(&b.id))
        });
    }

    let mut page = Vec::with_capacity(limit);
    for tier in 0..SCORE_TIERS {
        let mut cursors = [0usize; KINDS];
        loop {
            let mut emitted = false;
            for kind in 0..KINDS {
                if page.len() == limit {
                    return page;
                }
                let bucket = &buckets[tier * KINDS + kind];
                if let Some(hit) = bucket.get(cursors[kind]) {
                    page.push(hit.clone());
                    cursors[kind] += 1;
                    emitted = true;
                }
            }
            if !emitted {
                break;
            }
        }
    }
    page
}

/// Exact, prefix, substring.
const SCORE_TIERS: usize = 3;
const KINDS: usize = 5;

fn kind_order(kind: SearchKind) -> u8 {
    match kind {
        SearchKind::Npc => 0,
        SearchKind::Quest => 1,
        SearchKind::Item => 2,
        SearchKind::Object => 3,
        SearchKind::Area => 4,
    }
}

#[cfg(test)]
pub(crate) mod test_db {
    use super::Db;

    /// The tests query the real `tbcmangos.sqlite`; the ground-height regression they guard cannot
    /// be reproduced against a synthetic fixture, because the whole point is that mangos carries
    /// heights the guide text never did.
    pub fn open() -> Db {
        let path = std::env::var("SENTINEL_DB").unwrap_or_else(|_| "../tbcmangos.sqlite".to_string());
        assert!(
            std::path::Path::new(&path).exists(),
            "tbcmangos.sqlite not found at {path}; set SENTINEL_DB to point at it"
        );
        Db::new(&path)
    }
}

#[cfg(test)]
mod tests {
    use super::test_db::open;
    use crate::search::{SearchKind, SpawnType, DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT};
    use std::collections::HashSet;

    // "Fang" is the one term in this snapshot that hits every federated table: an NPC named
    // exactly `Fang` (14892) plus quests, items, objects and two flight-point areas containing it.
    const FEDERATED_TERM: &str = "Fang";

    #[test]
    fn federated_search_spans_several_kinds() {
        let db = open();
        let hits = db.federated_search(FEDERATED_TERM, 60).unwrap();
        let kinds: HashSet<SearchKind> = hits.iter().map(|h| h.kind).collect();
        assert!(
            kinds.len() >= 3,
            "expected at least 3 kinds for {FEDERATED_TERM}, got {kinds:?}"
        );
        assert!(hits.iter().all(|h| !h.name.is_empty()));
        assert!(hits.iter().all(|h| !h.context.is_empty()));
    }

    #[test]
    fn federated_search_ranks_exact_match_first() {
        let db = open();
        let hits = db.federated_search(FEDERATED_TERM, 60).unwrap();
        let first = hits.first().expect("expected hits");
        assert_eq!(first.kind, SearchKind::Npc);
        assert_eq!(first.id, 14892);
        assert_eq!(first.name, "Fang");
    }

    #[test]
    fn federated_search_does_not_let_one_kind_starve_the_page() {
        // The motivating case from the plan: the author types "wolf" and expects NPCs, quests and
        // items together. Items alone match 109 rows, so a page ordered purely by match quality
        // fills with items and the quests never surface.
        let db = open();
        let hits = db.federated_search("wolf", DEFAULT_SEARCH_LIMIT).unwrap();
        let kinds: HashSet<SearchKind> = hits.iter().map(|h| h.kind).collect();
        for expected in [SearchKind::Npc, SearchKind::Quest, SearchKind::Item] {
            assert!(
                kinds.contains(&expected),
                "no {expected:?} on the first page for 'wolf': {kinds:?}"
            );
        }
        // Objects are absent on purpose: all six "wolf" gameobjects are substring matches
        // ("Frostwolf Banner"), and match quality still outranks turn-taking.
        assert!(hits.iter().take(3).all(|h| h.score >= 2));
    }

    #[test]
    fn federated_search_honours_the_limit() {
        let db = open();
        let hits = db.federated_search(FEDERATED_TERM, 5).unwrap();
        assert_eq!(hits.len(), 5);
    }

    #[test]
    fn federated_search_treats_wildcards_as_literals() {
        // An unescaped `%` would turn the LIKE into a full scan of 109k creatures plus every other
        // searched table — the query-string-reachable sweep this endpoint must not expose. The
        // snapshot does hold names with a literal `%` (the "10% Test Speed Boots" item family),
        // so the property is "only literal matches", not "no matches".
        let db = open();
        let hits = db.federated_search("%", MAX_SEARCH_LIMIT).unwrap();
        assert!(
            hits.iter().all(|h| h.name.contains('%')),
            "bare '%' matched names without one: {:?}",
            hits.iter().map(|h| &h.name).collect::<Vec<_>>()
        );
        assert!(hits.len() < MAX_SEARCH_LIMIT, "a bare '%' should not fill the page");

        let underscore = db.federated_search("_", MAX_SEARCH_LIMIT).unwrap();
        assert!(underscore.iter().all(|h| h.name.contains('_')));
    }

    #[test]
    fn npc_spawns_carry_real_ground_height() {
        // Deputy Willem. The regression this endpoint exists to kill wrote world_z = 0 for all
        // 38,726 imported Travel positions; `creature.position_z` is the real height.
        let db = open();
        let spawns = db.spawns(SpawnType::Npc, 823).unwrap();
        let first = spawns.first().expect("Deputy Willem has a spawn");
        assert_eq!(first.map, 0);
        assert!((first.position_x - -8933.54).abs() < 1.0, "x = {}", first.position_x);
        assert!((first.position_y - -136.52).abs() < 1.0, "y = {}", first.position_y);
        assert_ne!(first.position_z, 0.0);
        assert!((first.position_z - 83.45).abs() < 1.0, "z = {}", first.position_z);
    }

    #[test]
    fn object_spawns_carry_real_ground_height() {
        let db = open();
        let spawns = db.spawns(SpawnType::Object, 1731).unwrap();
        assert!(spawns.len() > 1, "Copper Vein has many spawns");
        assert!(spawns.iter().any(|s| s.position_z != 0.0));
    }

    #[test]
    fn spawns_of_an_unknown_entry_are_empty_not_an_error() {
        let db = open();
        assert!(db.spawns(SpawnType::Npc, 99_999_999).unwrap().is_empty());
        assert!(db.spawns(SpawnType::Object, 99_999_999).unwrap().is_empty());
    }
}