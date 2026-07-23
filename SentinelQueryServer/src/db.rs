use rusqlite::Connection;
use sentinel_query_types::*;
use std::sync::{Arc, Mutex};

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
}