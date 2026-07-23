//! Project builder — lowers [`ParsedGuide`](crate::ParsedGuide) into a
//! `sentinel_models::Project` while resolving NPCs/quests via [`QueryClient`].
//!
//! Unresolved entities become diagnostics (ADR `03` §18) rather than hard errors.

use std::collections::HashMap;
use uuid::Uuid;

use sentinel_models::authoring::{
    Action, ActionPayload, AcceptQuestAction, CommentAction, ConditionAction, ConditionRole,
    Faction, FlightAction, HearthAction, ImportMetadata, KillTargetAction, LearnFlightPathAction,
    NpcRole, NPCReference, Operation, Position, Project, QuestReference, Severity, TrainerAction,
    TravelAction, TurnInQuestAction, UseItemAction, VendorAction, Diagnostic,
};
use sentinel_queryclient::{
    NpcDetail, ObjectiveKind, QuestDetail, QueryClient, QueryClientError, WorldPos,
};

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
        p.x,
        p.y,
        p.z,
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
            // CRITICAL fix (post-PR3-review): a Transport/Server/Decode error means the query
            // itself failed (server down, timeout, bad response) — NOT that the entity is
            // genuinely absent. Before this fix these `?`-propagated out of `build`, aborting
            // the whole guide block; with `HttpQueryClient` as the default (PR3) this is
            // reachable whenever `SentinelQueryServer` is unreachable, regressing offline
            // import. Degrade the same way as NotFound (unresolved, inert fallback) but with a
            // distinct diagnostic code so an operator can tell "server down" apart from
            // "entity genuinely absent".
            Err(e) => {
                self.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "QUERY_UNREACHABLE".to_string(),
                    message: format!("NPC entry {entry} lookup failed: {e}"),
                    entity: Some(entry.to_string()),
                    action: None,
                });
                Ok(None)
            }
        }
    }

    async fn resolve_npc_by_name(&mut self, name: &str) -> Result<Option<Uuid>, QueryClientError> {
        let results = match self.client.search_npcs(name).await {
            Ok(r) => r,
            Err(e) => {
                // See `resolve_npc_by_entry`: a transport-level failure degrades to a
                // diagnostic instead of aborting the block.
                self.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "QUERY_UNREACHABLE".to_string(),
                    message: format!("NPC search '{name}' failed: {e}"),
                    entity: Some(name.to_string()),
                    action: None,
                });
                return Ok(None);
            }
        };
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

    /// Resolve a creature NAME to concrete entry ids for a `Kill` target.
    ///
    /// `.mob` is overwhelmingly name-based (6,585 corpus uses, e.g. `.mob Young Wolf`), but the
    /// lowering previously kept only numeric args — so every named `.mob` produced an EMPTY
    /// `creature_entries` list and a Kill the runtime could never satisfy. Exact (case-insensitive)
    /// name matches are preferred; a search that only returns partial matches keeps them, because
    /// RestedXP frequently names a family ("Young Wolf") that maps to several spawn entries.
    /// Unresolvable names emit a diagnostic and contribute nothing — never a silent empty list.
    async fn resolve_creature_entries_by_name(
        &mut self,
        name: &str,
    ) -> Result<Vec<u32>, QueryClientError> {
        let results = match self.client.search_npcs(name).await {
            Ok(r) => r,
            Err(e) => {
                self.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "QUERY_UNREACHABLE".to_string(),
                    message: format!("creature search '{name}' failed: {e}"),
                    entity: Some(name.to_string()),
                    action: None,
                });
                return Ok(Vec::new());
            }
        };

        let exact: Vec<u32> = results
            .iter()
            .filter(|s| s.name.eq_ignore_ascii_case(name))
            .map(|s| s.entry)
            .collect();
        let entries = if exact.is_empty() {
            results.iter().map(|s| s.entry).collect::<Vec<u32>>()
        } else {
            exact
        };

        if entries.is_empty() {
            self.diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "UNRESOLVED_MOB".to_string(),
                message: format!("creature '{name}' not found; Kill target left unresolved"),
                entity: Some(name.to_string()),
                action: None,
            });
        }
        Ok(entries)
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
            // CRITICAL fix (post-PR3-review): see `resolve_npc_by_entry` — a transport-level
            // failure degrades to a diagnostic instead of `?`-propagating and aborting the block.
            Err(e) => {
                self.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "QUERY_UNREACHABLE".to_string(),
                    message: format!("Quest {id} lookup failed: {e}"),
                    entity: Some(id.to_string()),
                    action: None,
                });
                Ok(None)
            }
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

/// A zone's UI map identity plus the linear bounds needed to turn RestedXP's zone-relative
/// percentages into world coordinates.
///
/// `continent` is what lands in [`Position::map`] — the id the navmesh/server uses (Eastern
/// Kingdoms 0, Kalimdor 1, Outland 530). The four bounds come from the client's own
/// `core.game_ui.get_world_pos_from_map_pos`, sampled at the (0,0) and (1,1) corners of each zone
/// map, so the table is measured rather than remembered.
///
/// Axis convention (verified against the live client and the world DB): world **X** interpolates
/// along the map's **y** axis, world **Y** along the map's **x** axis.
#[derive(Debug, Clone, Copy)]
struct ZoneMap {
    continent: u32,
    /// world X at map y = 0
    top: f32,
    /// world Y at map x = 0
    left: f32,
    /// world X at map y = 1
    bottom: f32,
    /// world Y at map x = 1
    right: f32,
}

impl ZoneMap {
    /// Convert zone-relative percentages (0..100) to world X/Y.
    fn to_world(&self, pct_x: f32, pct_y: f32) -> (f32, f32) {
        let mx = pct_x / 100.0;
        let my = pct_y / 100.0;
        (
            self.top + my * (self.bottom - self.top),
            self.left + mx * (self.right - self.left),
        )
    }
}

/// Zone table: `(ui_map_id, aliases, bounds)`.
///
/// Bounds were sampled from a live client; each entry is verified against a known DB spawn (e.g.
/// Elwynn `48.923,41.606` resolves to Marshal McBride at `(-8902.6, -162.6)`, within 0.1 yd).
/// Zones absent from this table cannot be converted and produce a diagnostic rather than a
/// bogus position — a percentage must never survive compilation (ADR 06 invariant 3).
const ZONE_TABLE: &[(u32, &[&str], ZoneMap)] = &[
    (1429, &["Elwynn Forest"],
     ZoneMap { continent: 0, top: -7939.583, left: 1535.4166, bottom: -10254.166, right: -1935.4166 }),
    (1426, &["Dun Morogh"],
     ZoneMap { continent: 0, top: -3877.083, left: 1802.0833, bottom: -7160.4165, right: -3122.9165 }),
    (1432, &["Loch Modan"],
     ZoneMap { continent: 0, top: -4487.5, left: -1993.7499, bottom: -6327.083, right: -4752.083 }),
    (1455, &["Ironforge"],
     ZoneMap { continent: 0, top: -4569.2412, left: -713.5914, bottom: -5096.8457, right: -1504.2164 }),
    (1453, &["Stormwind City", "Stormwind", "StormwindClassic"],
     ZoneMap { continent: 0, top: -8278.8506, left: 1380.9714, bottom: -9175.205, right: 36.7006 }),
    (1437, &["Wetlands"],
     ZoneMap { continent: 0, top: -2147.9165, left: -389.5833, bottom: -4904.1665, right: -4525.0 }),
    (1436, &["Westfall"],
     ZoneMap { continent: 0, top: -9400.0, left: 3016.6665, bottom: -11733.333, right: -483.3333 }),
    (1433, &["Redridge Mountains"],
     ZoneMap { continent: 0, top: -8575.0, left: -1570.8333, bottom: -10022.916, right: -3741.6665 }),
    (1439, &["Darkshore"],
     ZoneMap { continent: 1, top: 8333.333, left: 2941.6665, bottom: 3966.6665, right: -3608.3333 }),
];

/// Does this action have any chance of progressing a quest objective?
fn is_satisfying_action(action: &Action) -> bool {
    matches!(
        action.payload,
        ActionPayload::Kill(_)
            | ActionPayload::UseItem(_)
            | ActionPayload::InteractNPC(_)
            | ActionPayload::LootObject(_)
            | ActionPayload::GrindArea(_)
    )
}

/// Pull `(quest, objective_index)` out of a `.complete`-derived gate expression.
///
/// Only the bare `Objective(q,i)` form is handled; compound expressions are left alone rather than
/// guessed at.
fn parse_objective_expr(expression: &str) -> Option<(u32, u32)> {
    let inner = expression.trim().strip_prefix("Objective(")?.strip_suffix(')')?;
    let (q, i) = inner.split_once(',')?;
    Some((q.trim().parse().ok()?, i.trim().parse().ok()?))
}

/// Pull `(item, count)` out of a `.collect`/`.itemcount`-derived gate expression.
///
/// Bare `ItemCount(item,n)` only. A negated `NOT ItemCount(...)` is deliberately NOT matched: it
/// asserts the player has FEWER than n, so synthesising a Kill to gather more would drive the run
/// away from the gate rather than toward it.
fn parse_item_count_expr(expression: &str) -> Option<(u32, u32)> {
    let inner = expression.trim().strip_prefix("ItemCount(")?.strip_suffix(')')?;
    let (item, count) = inner.split_once(',')?;
    Some((item.trim().parse().ok()?, count.trim().parse().ok()?))
}

/// Level-1 enrichment (ADR 06 §5) enforcing invariant 1 (satisfiability).
///
/// A guide step that reads `.goto <coords>` + `.complete 7,1` means *"walk here, then you'll kill
/// the kobolds"* — the human sees them and acts. Transcribed literally the bot travels and then
/// waits forever; that shape occurred 185 times in the Elwynn profile. Where a Completion gate has
/// no action before it that could ever satisfy it, synthesise one from the quest's structured
/// objectives.
///
/// Gaps only: a step that already kills keeps exactly what the guide specified.
async fn enrich_unsatisfiable_gates(
    state: &mut MapperState<'_>,
    step_index: usize,
    actions: &mut Vec<Action>,
) -> Result<(), QueryClientError> {
    /// What a gate needs satisfying: a quest objective slot, or a raw item count.
    enum Gate {
        Objective { quest: u32, index: u32 },
        Item { item: u32, count: u32 },
    }

    let mut gates: Vec<(usize, Gate)> = Vec::new();
    for (i, a) in actions.iter().enumerate() {
        if let ActionPayload::Condition(c) = &a.payload {
            if c.role == ConditionRole::Completion {
                if let Some((quest, index)) = parse_objective_expr(&c.expression) {
                    gates.push((i, Gate::Objective { quest, index }));
                } else if let Some((item, count)) = parse_item_count_expr(&c.expression) {
                    gates.push((i, Gate::Item { item, count }));
                }
            }
        }
    }

    // Insert back-to-front so earlier gate indices stay valid.
    for (gate_at, gate) in gates.into_iter().rev() {
        if actions[..gate_at].iter().any(is_satisfying_action) {
            continue; // the guide already said how
        }

        // A raw `.collect item,n` names no quest, so the requirement comes from the item's own
        // loot sources rather than a quest row.
        let (quest_id, obj_index) = match gate {
            Gate::Objective { quest, index } => (quest, index),
            Gate::Item { item, count } => {
                let sources = state.client.get_item_sources(item).await.unwrap_or_default();
                if sources.is_empty() {
                    state.diagnostics.push(Diagnostic {
                        severity: Severity::Warning,
                        code: "UNSATISFIABLE_GATE".to_string(),
                        message: format!(
                            "item {item} has no loot source; the collect gate was left \
                             unsatisfiable (script-driven — ADR 06 Level 2/3)"
                        ),
                        entity: Some(format!("item:{item}")),
                        action: None,
                    });
                    continue;
                }
                state.diagnostics.push(Diagnostic {
                    severity: Severity::Info,
                    code: "GATE_ENRICHED".to_string(),
                    message: format!("synthesised a Kill for collect gate on item {item}"),
                    entity: Some(format!("step:{step_index}")),
                    action: None,
                });
                actions.insert(
                    gate_at,
                    Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        class_restriction: None,
                        note: None,
                        payload: ActionPayload::Kill(KillTargetAction {
                            // Drop chance means `count` kills will not yield `count` items; see the
                            // overshoot rationale below.
                            creature_entries: sources,
                            quantity: Some(count.saturating_mul(5).max(1)),
                            loot: true,
                            ignore_elites: false,
                        }),
                    },
                );
                continue;
            }
        };
        let detail = match state.client.get_quest(quest_id).await {
            Ok(d) => d,
            Err(_) => continue, // transport/not-found already diagnosed elsewhere
        };
        let Some(obj) = detail
            .structured_objectives
            .iter()
            .find(|o| o.index as u32 == obj_index)
        else {
            state.diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "UNSATISFIABLE_GATE".to_string(),
                message: format!(
                    "quest {quest_id} objective {obj_index} has no derivable requirement; the gate \
                     was left unsatisfiable (script-driven objective — ADR 06 Level 2/3)"
                ),
                entity: Some(format!("quest:{quest_id}")),
                action: None,
            });
            continue;
        };

        let payload = match obj.kind {
            ObjectiveKind::KillCreature => Some(ActionPayload::Kill(KillTargetAction {
                creature_entries: vec![obj.target_entry],
                quantity: Some(obj.required),
                loot: true,
                ignore_elites: false,
            })),
            ObjectiveKind::CollectItem if !obj.sources.is_empty() => {
                // The item drops at a chance, so `required` kills will not reliably yield
                // `required` items. Overshoot deliberately: the gate after this action is the real
                // stop condition, but in a linear profile an earlier action never re-runs once it
                // succeeds, so undershooting strands the gate forever. The objective graph removes
                // this heuristic by re-deriving executable work every tick.
                Some(ActionPayload::Kill(KillTargetAction {
                    creature_entries: obj.sources.clone(),
                    quantity: Some(obj.required.saturating_mul(5).max(1)),
                    loot: true,
                    ignore_elites: false,
                }))
            }
            _ => {
                state.diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNSATISFIABLE_GATE".to_string(),
                    message: format!(
                        "quest {quest_id} objective {obj_index} ({:?}) has no synthesisable action \
                         (no loot source, or an object interaction needing a library reference)",
                        obj.kind
                    ),
                    entity: Some(format!("quest:{quest_id}")),
                    action: None,
                });
                None
            }
        };

        if let Some(payload) = payload {
            state.diagnostics.push(Diagnostic {
                severity: Severity::Info,
                code: "GATE_ENRICHED".to_string(),
                message: format!(
                    "synthesised a satisfying action for quest {quest_id} objective {obj_index}"
                ),
                entity: Some(format!("step:{step_index}")),
                action: None,
            });
            actions.insert(
                gate_at,
                Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    class_restriction: None,
                    note: None,
                    payload,
                },
            );
        }
    }
    Ok(())
}

/// Class names the compiler's `parse_class_guard` can lower (kept in sync with its KNOWN_CLASSES).
const CLASS_TOKENS: &[&str] = &[
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "DeathKnight", "Shaman", "Mage", "Warlock",
    "Druid",
];

/// Is this step-condition token a class name (optionally `!`-negated)?
///
/// Step headers carry a mix of classes (`<< Warlock`) and races (`<< !Human`); only the former can
/// currently be gated, so this keeps race tokens from being lowered into a class guard.
fn is_known_class_token(token: &str) -> bool {
    let name = token.trim().trim_start_matches('!').trim();
    CLASS_TOKENS.iter().any(|c| c.eq_ignore_ascii_case(name))
}

/// Look up a zone by name or by a bare UI map id (guides use both forms, e.g.
/// `.goto Elwynn Forest,…` and `.goto 1429,…`).
fn zone_map_for(zone: &str) -> Option<ZoneMap> {
    if let Ok(ui_map_id) = zone.trim().parse::<u32>() {
        return ZONE_TABLE.iter().find(|(id, _, _)| *id == ui_map_id).map(|(_, _, m)| *m);
    }
    ZONE_TABLE
        .iter()
        .find(|(_, names, _)| names.iter().any(|n| n.eq_ignore_ascii_case(zone.trim())))
        .map(|(_, _, m)| *m)
}

/// Build a `.goto` [`Position`] from its comma-split args (`[dest, x, y, z?]`, IF1). Trailing
/// `--` dev comments are already stripped at lex time (`lexer.rs::strip_inline_dev_comment`).
/// Returns `None` when no numeric x/y pair is present (zone-only goto) — the destination
/// name alone is preserved with no error, per the "zone name only" scenario.
///
/// Pushes an `UNMAPPED_GOTO_ZONE` diagnostic (rather than silently defaulting to map 0) when the
/// zone name is not a bare map id and is absent from [`zone_to_map_id`]'s static table.
fn build_travel_position(state: &mut MapperState, step: &Step, args: &[String]) -> Option<Position> {
    let pct_x = args.get(1)?.parse::<f32>().ok()?;
    let pct_y = args.get(2)?.parse::<f32>().ok()?;
    let z = args.get(3).and_then(|s| s.parse::<f32>().ok()).unwrap_or(0.0);
    let zone = args.first()?;

    // A zone we cannot convert yields NO position rather than a bogus one: emitting the raw
    // percentages produced 522 Travel actions aimed at meaningless coordinates, which is why the
    // bot travelled nowhere. ADR 06 invariant 3 — a percentage must never survive compilation.
    let Some(zone_map) = zone_map_for(zone) else {
        state.diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: "UNMAPPED_GOTO_ZONE".to_string(),
            message: format!(
                "Zone '{zone}' is not in the zone table; cannot convert {pct_x},{pct_y} to world \
                 coordinates, so no travel position was emitted"
            ),
            entity: Some(format!("step:{}", step.index)),
            action: None,
        });
        return None;
    };

    let (world_x, world_y) = zone_map.to_world(pct_x, pct_y);
    Some(Position::new(zone_map.continent, world_x, world_y, z))
}

/// Encode a `.collect`/`.itemcount` count argument as a §23 DSL fragment. The grammar only
/// provides an "at least" primitive (`ItemCountAtLeast`, DSL `ItemCount(item,n)`). `>=` and `<`
/// map directly onto that primitive (`ItemCount`/`NOT ItemCount`); `>` and `<=` need arithmetic
/// (`checked_add(1)`) to shift their boundary onto the same "at least" primitive — no new syntax
/// is invented; PR2a's parser only ever needs to recognize `ItemCount`/`NOT`.
/// Tolerates whitespace between the operator and the digits (e.g. `< 5`).
/// Returns `None` on unparseable input (caller falls back to a diagnostic).
fn item_count_dsl(item: u32, raw: &str) -> Option<String> {
    let (op, digits) = if let Some(rest) = raw.strip_prefix(">=") {
        (">=", rest)
    } else if let Some(rest) = raw.strip_prefix("<=") {
        ("<=", rest)
    } else if let Some(rest) = raw.strip_prefix('>') {
        (">", rest)
    } else if let Some(rest) = raw.strip_prefix('<') {
        ("<", rest)
    } else {
        (">=", raw)
    };
    let n = digits.trim().parse::<u32>().ok()?;
    match op {
        ">=" => Some(format!("ItemCount({item},{n})")),
        // Guard against overflow instead of panicking (debug builds trap on `+1` at u32::MAX).
        ">" => Some(format!("ItemCount({item},{})", n.checked_add(1)?)),
        "<=" => Some(format!("NOT ItemCount({item},{})", n.checked_add(1)?)),
        "<" => Some(format!("NOT ItemCount({item},{n})")),
        _ => unreachable!(),
    }
}

/// The seven gating/completion command names lowered to typed §23 DSL conditions (IF2) — single
/// source of truth shared between `build_step_actions`'s command routing and
/// `gating_condition_dsl`'s dispatch (previously duplicated as two separate literal lists).
const GATING_COMMANDS: [&str; 7] = [
    "complete", "collect", "itemcount", "isOnQuest",
    "isQuestComplete", "isQuestTurnedIn", "isQuestAvailable",
];

/// Build the `02_DATA_MODEL.md §23` DSL expression for a gating/completion command per the
/// design's command -> DSL mapping table (IF2). Returns `None` on unparseable arguments so the
/// caller can fall back to a diagnostic-carrying inert action. Trailing `--` dev comments are
/// already stripped at lex time (`lexer.rs::strip_inline_dev_comment`).
fn gating_condition_dsl(cmd_name: &str, args: &[String]) -> Option<String> {
    if !GATING_COMMANDS.contains(&cmd_name) {
        return None;
    }
    let arg = |i: usize| args.get(i).map(|s| s.as_str());
    match cmd_name {
        "complete" => {
            let quest = arg(0)?.parse::<u32>().ok()?;
            let idx = arg(1)?.parse::<u32>().ok()?;
            Some(format!("Objective({quest},{idx})"))
        }
        "collect" | "itemcount" => {
            let item = arg(0)?.parse::<u32>().ok()?;
            // Count arg is optional (implicit "at least 1") and may carry a RestedXP
            // comparison prefix (`<`, `>`, `<=`, `>=`); bare numbers mean "at least N".
            let raw_count = arg(1).unwrap_or("1");
            item_count_dsl(item, raw_count)
        }
        "isOnQuest" => quest_ids_dsl(args, |q| format!("QuestAccepted({q})")),
        "isQuestComplete" => quest_ids_dsl(args, |q| format!("QuestCompleted({q})")),
        "isQuestTurnedIn" => quest_ids_dsl(args, |q| format!("QuestRewarded({q})")),
        "isQuestAvailable" => quest_ids_dsl(args, |q| format!("NOT QuestRewarded({q})")),
        _ => unreachable!("cmd_name checked against GATING_COMMANDS above"),
    }
}

/// The role a gating command's condition plays in step progression (PR5a). `complete`/
/// `collect`/`itemcount` are wait-until-true completion gates; the `isX` family only decides
/// whether the step applies at all. See [`ConditionRole`].
fn condition_role_for(cmd_name: &str) -> ConditionRole {
    match cmd_name {
        "complete" | "collect" | "itemcount" => ConditionRole::Completion,
        "isOnQuest" | "isQuestComplete" | "isQuestTurnedIn" | "isQuestAvailable" => {
            ConditionRole::Applicability
        }
        _ => unreachable!("cmd_name checked against GATING_COMMANDS by the caller"),
    }
}

/// Spell IDs from a `.train`/`.trainer` arg list. RestedXP writes `.train <spell_id>` or
/// `.train <spell_id>,<rank>` — measured across The Burning Crusade.lua, every one of the 1,383
/// `.train` lines has exactly one or two comma-separated fields, never more. Only the first field
/// is a spell ID; a trailing rank is a qualifier, not a second spell, so taking every arg would
/// invent a bogus "spell 1". Unparseable/empty args yield an empty list rather than a guess.
fn train_spell_ids(args: &[String]) -> Vec<u32> {
    args.first()
        .and_then(|a| a.trim().parse::<u32>().ok())
        .into_iter()
        .collect()
}

/// Parse every comma-separated arg as a quest ID, lowering through `predicate` into a §23
/// infix-`||` chain: RestedXP quest gates commonly list several IDs read as "any of these"
/// (round-3 finding); one ID yields the unchanged single string. `||` is the grammar's OR form
/// (design: `||` -> `Any`); PR2a's parser consumes it, and fail-open covers residual ambiguity.
/// `None` if the list is empty or any ID fails to parse.
fn quest_ids_dsl(args: &[String], predicate: impl Fn(u32) -> String) -> Option<String> {
    let ids: Vec<u32> = args.iter()
        .map(|a| a.parse::<u32>().ok())
        .collect::<Option<_>>()?;
    if ids.is_empty() {
        return None;
    }
    Some(ids.into_iter().map(predicate).collect::<Vec<_>>().join(" || "))
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

/// Never-drop fallback (IF7): wrap a non-leveling-core command as a typed inert `Comment`,
/// always carrying a diagnostic naming the command and its raw args — never a bare `Comment`.
/// `note_as_text`: WARNING fix — restores the two pre-existing per-arm shapes exactly.
/// `false` (named arms: waypoint/skill/equip): `text` is always the `.command args` template,
/// `note` carries `cmd.note` separately. `true` (catch-all `_` only): `text` is the note when
/// present (else the template), and `note` stays `None`.
fn inert_preserved_action(
    state: &mut MapperState,
    step_index: usize,
    cmd: &crate::Command,
    note_as_text: bool,
) -> Action {
    let action_id = Uuid::new_v4();
    let template = || format!(".{} {}", cmd.name, cmd.args.join(","));
    let (text, note) = if note_as_text {
        (cmd.note.clone().unwrap_or_else(template), None)
    } else {
        (template(), cmd.note.clone())
    };
    state.diagnostics.push(Diagnostic {
        severity: Severity::Info,
        code: "COMMAND_PRESERVED_INERT".to_string(),
        message: format!(
            "Command '.{}' is outside leveling-core semantic lowering; preserved as an inert action (args: {:?})",
            cmd.name, cmd.args
        ),
        entity: Some(format!("step:{step_index}")),
        action: Some(action_id.to_string()),
    });
    Action {
        id: action_id,
        enabled: true,
        condition: None,
        class_restriction: None,
        note,
        payload: ActionPayload::Comment(CommentAction { text }),
    }
}

/// Build actions from a step's commands, mutating `state` to resolve entities.
async fn build_step_actions(
    state: &mut MapperState<'_>,
    step: &Step,
) -> Result<Vec<Action>, QueryClientError> {
    let mut actions = Vec::new();
    let mut last_target: Option<Uuid> = None;

    for cmd in &step.commands {
        // IF3: apply the command line's `<< Class` suffix (if any) to whichever action(s) this
        // command produces below, rather than threading it through every match arm individually.
        let actions_before = actions.len();
        match cmd.name.as_str() {
            "target" => {
                last_target = resolve_npc_with_hints(state, step, cmd.args.first()).await?;
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
                                    class_restriction: None,
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
                                    class_restriction: None,
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
                                    class_restriction: None,
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
                                    class_restriction: None,
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
                let position = build_travel_position(state, step, &cmd.args);
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    class_restriction: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Travel(TravelAction {
                        destination: dest,
                        position,
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
                        class_restriction: None,
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
                        class_restriction: None,
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
                        class_restriction: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Train(TrainerAction {
                            npc,
                            spells: train_spell_ids(&cmd.args),
                            trainer_type: None,
                            minimum_level: None,
                        }),
                    });
                } else {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        class_restriction: None,
                        note: None,
                        payload: ActionPayload::Comment(CommentAction {
                            text: format!(".train {}", cmd.args.join(",")),
                        }),
                    });
                }
            }
            "fly" => {
                let dest = cmd.args.first().cloned()
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
                        class_restriction: None,
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
                        class_restriction: None,
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
                    class_restriction: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Hearth(HearthAction {
                        innkeeper: None,
                        destination: None,
                    }),
                });
            }
            "mob" => {
                // .mob <entry> or .mob <name> - kill target. Names dominate the corpus, so they
                // must resolve to entries here; keeping only numerics made every named .mob an
                // unsatisfiable Kill (measured 53 of 53 empty in the Elwynn profile).
                let mut entries: Vec<u32> = Vec::new();
                for arg in &cmd.args {
                    let raw = arg.trim();
                    if raw.is_empty() {
                        continue;
                    }
                    if let Ok(entry) = raw.parse::<u32>() {
                        entries.push(entry);
                    } else {
                        // `.target +Name` style prefixes also appear on mob names.
                        let name = raw.trim_start_matches('+').trim();
                        let resolved = state.resolve_creature_entries_by_name(name).await?;
                        entries.extend(resolved);
                    }
                }
                entries.dedup();
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    class_restriction: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Kill(KillTargetAction {
                        creature_entries: entries,
                        quantity: None,
                        loot: true,
                        ignore_elites: false,
                    }),
                });
            }
            name if GATING_COMMANDS.contains(&name) => {
                // Gating/completion command (IF2): lower to a typed §23 DSL condition per
                // the design's mapping table. Malformed args fall back to a diagnostic-carrying
                // inert Comment — never a bare Comment with no diagnostic.
                match gating_condition_dsl(cmd.name.as_str(), &cmd.args) {
                    Some(expression) => {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            class_restriction: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Condition(ConditionAction {
                                expression,
                                role: condition_role_for(cmd.name.as_str()),
                            }),
                        });
                    }
                    None => {
                        let action_id = Uuid::new_v4();
                        state.diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "MALFORMED_GATING_ARGS".to_string(),
                            message: format!(
                                "Gating command '.{}' has unparseable arguments: {:?}",
                                cmd.name, cmd.args
                            ),
                            entity: Some(format!("step:{}", step.index)),
                            action: Some(action_id.to_string()),
                        });
                        actions.push(Action {
                            id: action_id,
                            enabled: true,
                            condition: None,
                            class_restriction: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Comment(CommentAction {
                                text: format!(".{} {}", cmd.name, cmd.args.join(",")),
                            }),
                        });
                    }
                }
            }
            "item" => {
                // .item <item_id> - related to item usage
                if let Some(id_str) = cmd.args.first() {
                    if let Ok(item_id) = id_str.parse::<u32>() {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            class_restriction: None,
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
                            class_restriction: None,
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
                // .waypoint <x>, <y> - waypoint in current zone (IF7: never-drop inert preserve)
                actions.push(inert_preserved_action(state, step.index, cmd, false));
            }
            "trainer" => {
                // .trainer - alias for train, uses last_target
                if let Some(npc) = last_target {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        class_restriction: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Train(TrainerAction {
                            npc,
                            spells: train_spell_ids(&cmd.args),
                            trainer_type: None,
                            minimum_level: None,
                        }),
                    });
                }
            }
            "skill" => {
                // .skill <skill_id> <level> - train skill (IF7: never-drop inert preserve)
                actions.push(inert_preserved_action(state, step.index, cmd, false));
            }
            "abandon" => {
                // .abandon <quest_id> - abandon quest. Missing/unparseable id (IF7 never-drop):
                // fall back to a diagnostic-carrying inert Comment, never a silent drop.
                match cmd.args.first().and_then(|id_str| id_str.parse::<u32>().ok()) {
                    Some(id) => {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            class_restriction: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Comment(CommentAction {
                                text: format!(".abandon {}", id),
                            }),
                        });
                    }
                    None => {
                        let action_id = Uuid::new_v4();
                        state.diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "MALFORMED_ABANDON_ARGS".to_string(),
                            message: format!(
                                "Command '.abandon' has unparseable arguments: {:?}",
                                cmd.args
                            ),
                            entity: Some(format!("step:{}", step.index)),
                            action: Some(action_id.to_string()),
                        });
                        actions.push(Action {
                            id: action_id,
                            enabled: true,
                            condition: None,
                            class_restriction: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Comment(CommentAction {
                                text: format!(".abandon {}", cmd.args.join(",")),
                            }),
                        });
                    }
                }
            }
            "fp" => {
                // .fp - flight point (learn). Corpus measurement of The Burning Crusade.lua showed
                // `.fp` was 135 of the 514 unresolved commands because it only consulted a
                // preceding `.target`. Fall back to the step's |cRXP_FRIENDLY_...|r name hints,
                // exactly as `.vendor` and `.train` already do.
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
                        class_restriction: None,
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
                        class_restriction: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Comment(CommentAction {
                            text: ".fp (unresolved NPC)".to_string(),
                        }),
                    });
                }
            }
            "equip" => {
                // .equip <item_id> - equip item (IF7: never-drop inert preserve, not a bare Comment)
                actions.push(inert_preserved_action(state, step.index, cmd, false));
            }
            _ => {
                // Unrecognized command (IF7): never-drop inert preserve, never a bare Comment.
                actions.push(inert_preserved_action(state, step.index, cmd, true));
            }
        }

        // IF3: stamp the command's class suffix onto every action this command just produced.
        if cmd.class_restriction.is_some() {
            for action in &mut actions[actions_before..] {
                action.class_restriction = cmd.class_restriction.clone();
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
            op.sticky = step.directives.iter().any(|d| d.name.eq_ignore_ascii_case("sticky"));
            op.looping = step.directives.iter().any(|d| d.name.eq_ignore_ascii_case("loop"));
            // IF5: surface every tolerated directive typo as an info diagnostic.
            for d in &step.directives {
                if let Some(original) = &d.original {
                    state.diagnostics.push(Diagnostic {
                        severity: Severity::Info,
                        code: "DIRECTIVE_TYPO_TOLERATED".to_string(),
                        message: format!(
                            "Directive '#{original}' tolerated as canonical '#{}'", d.name
                        ),
                        entity: Some(format!("step:{}", step.index)),
                        action: None,
                    });
                }
            }
            op.actions = build_step_actions(&mut state, step).await?;

            // Level-1 enrichment before class stamping, so a synthesised action inherits the
            // step's class restriction like any other.
            enrich_unsatisfiable_gates(&mut state, step.index, &mut op.actions).await?;

            // Step-level class gating (`step << Warlock`, `step << Priest/Mage/Warlock`).
            // IF3 already stamps COMMAND-level suffixes (`.turnin 33,2 << Rogue`), but a step
            // header restriction reached only `op.conditions`, which the compiler drops — so a
            // Paladin happily ran the Warlock opening. Stamp it onto every action in the step that
            // has no class suffix of its own; the command-level suffix is more specific and wins.
            //
            // Only CLASS tokens are propagated. `step << !Human` is a RACE restriction, and
            // RaceIs compares against a numeric race id the runtime does not yet map, so emitting
            // it would gate on a comparison that cannot match. Unknown tokens are left to
            // parse_class_guard, which diagnoses and fails open (runs the step) — the safe
            // direction, since doing an extra step costs time while skipping a needed one breaks
            // the route.
            if !step.conditions.is_empty()
                && step.conditions.iter().all(|c| is_known_class_token(c))
            {
                let restriction = step.conditions.join("/");
                for action in op.actions.iter_mut() {
                    if action.class_restriction.is_none() {
                        action.class_restriction = Some(restriction.clone());
                    }
                }
            }

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