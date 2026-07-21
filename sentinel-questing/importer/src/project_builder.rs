//! Project builder — lowers [`ParsedGuide`](crate::ParsedGuide) into a
//! `sentinel_models::Project` while resolving NPCs/quests via [`QueryClient`].
//!
//! Unresolved entities become diagnostics (ADR `03` §18) rather than hard errors.

use std::collections::HashMap;
use uuid::Uuid;

use sentinel_models::authoring::{
    Action, ActionPayload, AcceptQuestAction, CommentAction, Faction, FlightAction, HearthAction,
    ImportMetadata, KillTargetAction, LearnFlightPathAction, NpcRole, NPCReference, Operation,
    Position, Project, QuestReference, Severity, TrainerAction, TravelAction, TurnInQuestAction,
    UseItemAction, VendorAction, Diagnostic,
};
use sentinel_queryclient::{NpcDetail, QuestDetail, QueryClient, QueryClientError, WorldPos};

use crate::{ParsedGuide, Step};

/// Helper to convert a role string from QueryServer to [`NpcRole`]. Unknown strings are ignored.
fn role_from_str(s: &str) -> Option<NpcRole> {
    match s {
        "QuestGiver" => Some(NpcRole::QuestGiver),
        "Vendor" => Some(NpcRole::Vendor),
        "Trainer" => Some(NpcRole::Trainer),
        "Repair" => Some(NpcRole::Repair),
        "FlightMaster" => Some(NpcRole::FlightMaster),
        "Innkeeper" => Some(NpcRole::Innkeeper),
        "Mailbox" => Some(NpcRole::Mailbox),
        "Banker" => Some(NpcRole::Banker),
        "Auctioneer" => Some(NpcRole::Auctioneer),
        "Generic" => Some(NpcRole::Generic),
        _ => None,
    }
}

/// Convert QueryServer [`WorldPos`] (f64) to authoring [`Position`] (f32).
fn worldpos_to_position(p: &WorldPos) -> Position {
    Position::new(
        p.map,
        p.x as f32,
        p.y as f32,
        p.z as f32,
    )
}

/// Mutable state during project building, accumulating resolved entities and diagnostics.
struct MapperState<'a> {
    client: &'a dyn QueryClient,
    /// entry -> uuid for NPC references.
    npc_by_entry: HashMap<u32, Uuid>,
    /// npc_library in insertion order.
    npcs: Vec<NPCReference>,
    /// quest_id -> uuid
    quest_by_id: HashMap<u32, Uuid>,
    /// quest_library in insertion order.
    quests: Vec<QuestReference>,
    diagnostics: Vec<Diagnostic>,
}

impl<'a> MapperState<'a> {
    fn new(client: &'a dyn QueryClient) -> Self {
        Self {
            client,
            npc_by_entry: HashMap::new(),
            npcs: Vec::new(),
            quest_by_id: HashMap::new(),
            quests: Vec::new(),
            diagnostics: Vec::new(),
        }
    }

    async fn resolve_npc_by_entry(&mut self, entry: u32) -> Result<Option<Uuid>, QueryClientError> {
        // Already resolved.
        if let Some(uuid) = self.npc_by_entry.get(&entry) {
            return Ok(Some(*uuid));
        }

        match self.client.get_npc(entry).await {
            Ok(detail) => {
                let uuid = Uuid::new_v4();
                let npc = Self::npc_from_detail(uuid, detail);
                self.npcs.push(npc);
                self.npc_by_entry.insert(entry, uuid);
                Ok(Some(uuid))
            }
            Err(QueryClientError::NotFound(_)) => {
                self.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNRESOLVED_NPC".to_string(),
                    message: format!("NPC entry {entry} not found in world database"),
                    entity: Some(entry.to_string()),
                    action: None,
                });
                Ok(None)
            }
            Err(e) => Err(e),
        }
    }

    async fn resolve_npc_by_name(&mut self, name: &str) -> Result<Option<Uuid>, QueryClientError> {
        let results = self.client.search_npcs(name).await?;
        let Some(summary) = results.first() else {
            self.diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "UNRESOLVED_NPC".to_string(),
                message: format!("NPC '{name}' not found in world database"),
                entity: Some(name.to_string()),
                action: None,
            });
            return Ok(None);
        };
        self.resolve_npc_by_entry(summary.entry).await
    }

    async fn resolve_quest(
        &mut self,
        id: u32,
    ) -> Result<Option<(Uuid, Option<Uuid>, Option<Uuid>)>, QueryClientError> {
        // Already resolved: retrieve the stored quest and its npc refs.
        if let Some(&quest_uuid) = self.quest_by_id.get(&id) {
            // Find the quest in the vector to get giver/finisher
            let quest = self.quests.iter().find(|q| q.quest_id == id).unwrap();
            return Ok(Some((quest_uuid, quest.giver_npc, quest.finisher_npc)));
        }

        match self.client.get_quest(id).await {
            Ok(detail) => {
                let quest_uuid = Uuid::new_v4();
                let giver_uuid = match detail.giver_entry {
                    Some(e) => self.resolve_npc_by_entry(e).await.ok().flatten(),
                    None => None,
                };
                let finisher_uuid = match detail.finisher_entry {
                    Some(e) => self.resolve_npc_by_entry(e).await.ok().flatten(),
                    None => None,
                };
                let q = Self::quest_from_detail(quest_uuid, detail, giver_uuid, finisher_uuid);
                self.quests.push(q.clone());
                self.quest_by_id.insert(id, quest_uuid);
                Ok(Some((quest_uuid, giver_uuid, finisher_uuid)))
            }
            Err(QueryClientError::NotFound(_)) => {
                self.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNRESOLVED_QUEST".to_string(),
                    message: format!("Quest {id} not found in world database"),
                    entity: Some(id.to_string()),
                    action: None,
                });
                Ok(None)
            }
            Err(e) => Err(e),
        }
    }

    fn npc_from_detail(uuid: Uuid, detail: NpcDetail) -> NPCReference {
        let roles: Vec<NpcRole> = detail.roles.iter().filter_map(|r| role_from_str(r)).collect();
        let position = detail.positions.first().map(worldpos_to_position);
        NPCReference {
            id: uuid,
            entry: Some(detail.entry),
            guid: None,
            name: detail.name,
            faction: None, // QueryServer returns numeric faction; authoring expects enum
            roles,
            position,
            source: Some("QueryServer".to_string()),
            notes: None,
        }
    }

    fn quest_from_detail(
        uuid: Uuid,
        detail: QuestDetail,
        giver_uuid: Option<Uuid>,
        finisher_uuid: Option<Uuid>,
    ) -> QuestReference {
        let chain = if detail.next_quests.is_empty() {
            None
        } else {
            Some(detail.next_quests.iter().map(|q| q.to_string()).collect::<Vec<_>>().join(","))
        };
        QuestReference {
            id: uuid,
            quest_id: detail.id,
            title: Some(detail.title),
            level: Some(detail.level),
            minimum_level: Some(detail.min_level),
            suggested_group: None,
            giver_npc: giver_uuid,
            finisher_npc: finisher_uuid,
            chain,
            prerequisites: detail.required_quests,
            exclusive_with: vec![],
            repeatable: false,
            source: Some("QueryServer".to_string()),
        }
    }
}

/// Derives the operation name from a step.
/// Priority: `#label` value, then first `.goto` zone name, then `Step {index}`.
fn operation_name(step: &Step) -> String {
    // Label takes precedence.
    if let Some(label) = step.directives.iter().find(|d| d.name == "label").and_then(|d| d.value.as_ref()) {
        return format!("label:{}", label);
    }
    // Otherwise use the goto zone if present.
    for cmd in &step.commands {
        if cmd.name == "goto" {
            if let Some(first) = cmd.args.first() {
                // If first arg is not a number, treat it as zone name.
                let zone = if first.parse::<u32>().is_ok() {
                    // Map ID: use next arg or fallback.
                    first.clone()
                } else {
                    first.clone()
                };
                return zone;
            }
        }
    }
    format!("Step {}", step.index)
}

/// Resolve NPC from explicit target or name hints (Wave 3).
/// Tries explicit target first, then falls back to step's extracted NPC name hints.
async fn resolve_npc_with_hints(
    state: &mut MapperState<'_>,
    step: &Step,
    explicit_name: Option<&String>,
) -> Result<Option<Uuid>, QueryClientError> {
    if let Some(name) = explicit_name {
        return state.resolve_npc_by_name(name).await;
    }
    // Fallback: try name hints from step notes
    for hint in &step.npc_name_hints {
        if let Some(uuid) = state.resolve_npc_by_name(hint).await? {
            return Ok(Some(uuid));
        }
    }
    Ok(None)
}

/// Build actions from a step's commands, mutating `state` to resolve entities.
async fn build_step_actions(
    state: &mut MapperState<'_>,
    step: &Step,
) -> Result<Vec<Action>, QueryClientError> {
    let mut actions = Vec::new();
    let mut last_target: Option<Uuid> = None;

    for cmd in &step.commands {
        match cmd.name.as_str() {
            "target" => {
                last_target = resolve_npc_with_hints(state, step, cmd.args.first().map(|s| s)).await?;
            }
            "accept" => {
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(id) = id_str.parse::<u32>() {
                        match state.resolve_quest(id).await? {
                            Some((_, giver, _)) => {
                                let npc = giver.or(last_target);
                                actions.push(Action {
                                    id: Uuid::new_v4(),
                                    enabled: true,
                                    condition: None,
                                    note: cmd.note.clone(),
                                    payload: ActionPayload::AcceptQuest(AcceptQuestAction {
                                        quest: id,
                                        npc,
                                        auto_complete_dialog: false,
                                        optional: step.directives.iter().any(|d| d.name == "optional"),
                                    }),
                                });
                            }
                            None => {
                                // Unresolved quest: emit a comment preserving intent.
                                actions.push(Action {
                                    id: Uuid::new_v4(),
                                    enabled: true,
                                    condition: None,
                                    note: cmd.note.clone(),
                                    payload: ActionPayload::Comment(CommentAction {
                                        text: format!(".accept {}", id),
                                    }),
                                });
                            }
                        }
                    }
                }
            }
            "turnin" => {
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(id) = id_str.parse::<u32>() {
                        match state.resolve_quest(id).await? {
                            Some((_, _, finisher)) => {
                                let npc = finisher.or(last_target);
                                actions.push(Action {
                                    id: Uuid::new_v4(),
                                    enabled: true,
                                    condition: None,
                                    note: cmd.note.clone(),
                                    payload: ActionPayload::TurnInQuest(TurnInQuestAction {
                                        quest: id,
                                        npc,
                                        choose_reward: None,
                                        optional: step.directives.iter().any(|d| d.name == "optional"),
                                    }),
                                });
                            }
                            None => {
                                actions.push(Action {
                                    id: Uuid::new_v4(),
                                    enabled: true,
                                    condition: None,
                                    note: cmd.note.clone(),
                                    payload: ActionPayload::Comment(CommentAction {
                                        text: format!(".turnin {}", id),
                                    }),
                                });
                            }
                        }
                    }
                }
            }
            "goto" => {
                let dest = cmd.args.first()
                    .map(|a| if a.parse::<u32>().is_ok() { format!("Map {}", a) } else { a.clone() })
                    .unwrap_or_else(|| "Unknown".to_string());
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Travel(TravelAction {
                        destination: dest,
                        position: None,
                        tolerance: 5.0,
                        mount: None,
                        allow_flight: false,
                        timeout: None,
                    }),
                });
            }
            "vendor" => {
                let npc = if let Some(npc) = last_target {
                    Some(npc)
                } else {
                    resolve_npc_with_hints(state, step, None).await?
                };
                if let Some(npc) = npc {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Vendor(VendorAction {
                            npc,
                            sell_grey: false,
                            repair: false,
                            buy_items: vec![],
                            minimum_free_slots: None,
                        }),
                    });
                } else {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: None,
                        payload: ActionPayload::Comment(CommentAction {
                            text: ".vendor (unresolved NPC)".to_string(),
                        }),
                    });
                }
            }
            "train" => {
                let npc = if let Some(npc) = last_target {
                    Some(npc)
                } else {
                    resolve_npc_with_hints(state, step, None).await?
                };
                if let Some(npc) = npc {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Train(TrainerAction {
                            npc,
                            trainer_type: None,
                            minimum_level: None,
                        }),
                    });
                } else {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: None,
                        payload: ActionPayload::Comment(CommentAction {
                            text: format!(".train {}", cmd.args.join(",")),
                        }),
                    });
                }
            }
            "fly" => {
                let dest = cmd.args.first()
                    .map(|s| s.clone())
                    .unwrap_or_else(|| "Unknown".to_string());
                let npc = if let Some(npc) = last_target {
                    Some(npc)
                } else {
                    resolve_npc_with_hints(state, step, None).await?
                };
                if let Some(npc) = npc {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Flight(FlightAction {
                            npc,
                            destination: dest,
                        }),
                    });
                } else {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Comment(CommentAction {
                            text: format!(".fly {}", dest),
                        }),
                    });
                }
            }
            "hs" => {
                // Hearthstone use.
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Hearth(HearthAction {
                        innkeeper: None,
                        destination: None,
                    }),
                });
            }
            "mob" => {
                // .mob <entry> or .mob <name> - kill target
                let entries: Vec<u32> = cmd.args.iter()
                    .filter_map(|a| a.parse::<u32>().ok())
                    .collect();
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Kill(KillTargetAction {
                        creature_entries: entries,
                        quantity: None,
                        loot: true,
                        ignore_elites: false,
                    }),
                });
            }
            "collect" => {
                // .collect <item_id> - loot object for items (preserved as comment for now)
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Comment(CommentAction {
                        text: format!(".collect {}", cmd.args.join(",")),
                    }),
                });
            }
            "item" => {
                // .item <item_id> - related to item usage
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(item_id) = id_str.parse::<u32>() {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::UseItem(UseItemAction {
                                item: item_id,
                                target: None,
                            }),
                        });
                    }
                }
            }
            "use" => {
                // .use <item_id> - use an item
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(item_id) = id_str.parse::<u32>() {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::UseItem(UseItemAction {
                                item: item_id,
                                target: None,
                            }),
                        });
                    }
                }
            }
            "waypoint" => {
                // .waypoint <x>, <y> - waypoint in current zone (preserved as comment)
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Comment(CommentAction {
                        text: format!(".waypoint {}", cmd.args.join(",")),
                    }),
                });
            }
            "trainer" => {
                // .trainer - alias for train, uses last_target
                if let Some(npc) = last_target {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Train(TrainerAction {
                            npc,
                            trainer_type: None,
                            minimum_level: None,
                        }),
                    });
                }
            }
            "complete" => {
                // .complete <quest_id> - mark quest complete without turnin NPC
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(id) = id_str.parse::<u32>() {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Comment(CommentAction {
                                text: format!(".complete {}", id),
                            }),
                        });
                    }
                }
            }
            "skill" => {
                // .skill <skill_id> <level> - train skill
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Comment(CommentAction {
                        text: format!(".skill {}", cmd.args.join(",")),
                    }),
                });
            }
            "abandon" => {
                // .abandon <quest_id> - abandon quest
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(id) = id_str.parse::<u32>() {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Comment(CommentAction {
                                text: format!(".abandon {}", id),
                            }),
                        });
                    }
                }
            }
            "fp" => {
                // .fp - flight point (learn)
                if let Some(npc) = last_target {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::LearnFlightPath(LearnFlightPathAction {
                            npc,
                        }),
                    });
                } else {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Comment(CommentAction {
                            text: ".fp (unresolved NPC)".to_string(),
                        }),
                    });
                }
            }
            "equip" => {
                // .equip <item_id> - equip item (not an authoring action; preserved as comment)
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Comment(CommentAction {
                        text: format!(".equip {}", cmd.args.join(",")),
                    }),
                });
            }
            _ => {
                // Unrecognized command → preserve as comment.
                let text = if let Some(note) = &cmd.note {
                    note.clone()
                } else {
                    format!(".{} {}", cmd.name, cmd.args.join(","))
                };
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    note: None,
                    payload: ActionPayload::Comment(CommentAction { text }),
                });
            }
        }
    }

    Ok(actions)
}

pub struct ProjectBuilder;

impl ProjectBuilder {
    /// Convert a parsed guide into a Project, resolving entities through the QueryClient.
    ///
    /// Unresolved NPCs/quests are recorded as warnings in the Project's diagnostics.
    pub async fn build(
        guide: &ParsedGuide,
        source_file: &str,
        client: &dyn QueryClient,
    ) -> Result<Project, QueryClientError> {
        let mut state = MapperState::new(client);

        let guide_name = guide.headers.iter()
            .find(|h| h.key == "name")
            .map(|h| h.value.clone())
            .unwrap_or_else(|| "Imported Guide".to_string());

        let mut project = sentinel_models::authoring::new_project(guide_name.clone());

        // Faction header: `<< Alliance` or `<< Horde`.
        if let Some(fh) = guide.headers.iter().find(|h| h.key == "faction") {
            if fh.value.eq_ignore_ascii_case("Alliance") {
                project.metadata.faction = Some(Faction::Alliance);
            } else if fh.value.eq_ignore_ascii_case("Horde") {
                project.metadata.faction = Some(Faction::Horde);
            }
        }

        // Build operations from steps.
        let mut operations = Vec::new();
        for step in &guide.steps {
            let name = operation_name(step);
            let mut op = Operation::new(name);
            op.conditions = step.conditions.clone();
            op.actions = build_step_actions(&mut state, step).await?;
            operations.push(op);
        }
        project.operations = operations;

        // Libraries.
        project.npc_library = state.npcs;
        project.quest_library = state.quests;

        // Diagnostics.
        project.diagnostics = state.diagnostics;

        // Import metadata.
        let guide_version = guide.headers.iter()
            .find(|h| h.key == "version")
            .map(|h| h.value.clone())
            .unwrap_or_default();
        project.import_metadata = Some(ImportMetadata {
            importer: "sentinel-importer".to_string(),
            imported_at: chrono::Utc::now().to_rfc3339(),
            source_file: source_file.to_string(),
            checksum: String::new(),
            guide_version,
        });

        Ok(project)
    }
}