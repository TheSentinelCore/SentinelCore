//! Project builder — lowers [`ParsedGuide`](crate::ParsedGuide) into a
//! `sentinel_models::Project` while resolving NPCs/quests via [`QueryClient`].
//!
//! Unresolved entities become diagnostics (ADR `03` §18) rather than hard errors.

use std::collections::{BTreeMap, HashMap};
use uuid::Uuid;

use sentinel_models::authoring::{
    Action, ActionPayload, AcceptQuestAction, CommentAction, CompleteWithTarget, ConditionAction,
    ConditionRole, Faction, FlightAction, Gated, GuideDirective, GuideGate, HearthAction,
    ImportMetadata, KillTargetAction, LearnFlightPathAction, NpcRole, NPCReference, Operation,
    Position, Project, QuestReference, Severity, TrainerAction, TravelAction, TurnInQuestAction,
    UseItemAction, VendorAction, Diagnostic,
};
use sentinel_models::zone::zone_map_for;
use sentinel_queryclient::{
    NpcDetail, ObjectiveKind, QuestDetail, QueryClient, QueryClientError, WorldPos,
};

use crate::{split_directive_gate, Directive, LabelDef, ParsedGuide, Step};

/// Directives with a typed carrier on [`Operation`]. Everything else is passed through verbatim
/// in `Operation::directives` so no step-body directive is silently dropped a second time.
const TYPED_DIRECTIVES: &[&str] =
    &["label", "requires", "completewith", "optional", "sticky", "loop"];

/// Does this step gate carry the `skip` disable sentinel?
///
/// `skip` (139 occurrences, every one of them on a `step` marker) is never negated, never appears
/// in a `/`-list, and never occurs outside a step tail. It is ABSORBING: `step << Warrior skip` is
/// a step the author turned off, not a Warrior-only step, and reading `Warrior` as the audience
/// would resurrect it.
fn gate_disables(gate: &str) -> bool {
    gate.split(|c: char| c == '/' || c.is_whitespace())
        .any(|t| !t.starts_with('!') && t.eq_ignore_ascii_case("skip"))
}

/// Split a directive's value into `(value, gate)` as a `Gated<String>` entry.
fn gated_value(d: &Directive) -> (String, Option<GuideGate>) {
    let (value, gate) = split_directive_gate(d.value.as_deref().unwrap_or_default());
    (value, gate.map(GuideGate))
}

fn directives_named<'a>(step: &'a Step, name: &'a str) -> impl Iterator<Item = &'a Directive> {
    step.directives.iter().filter(move |d| d.name.eq_ignore_ascii_case(name))
}

/// `#label NAME [<< gate]` entries, in source order.
fn step_labels(step: &Step) -> Vec<Gated<String>> {
    directives_named(step, "label")
        .filter_map(|d| {
            let (value, gate) = gated_value(d);
            (!value.is_empty()).then(|| Gated { value, gate, line: d.line })
        })
        .collect()
}

/// `#requires LABEL [<< gate]` entries, in source order, each keeping its OWN gate.
fn step_requires(step: &Step) -> Vec<Gated<String>> {
    directives_named(step, "requires")
        .filter_map(|d| {
            let (value, gate) = gated_value(d);
            (!value.is_empty()).then(|| Gated { value, gate, line: d.line })
        })
        .collect()
}

/// `#completewith TARGET [<< gate]` entries. The gate is stripped BEFORE the `next` comparison,
/// or the 10 corpus lines spelling `#completewith next << <gate>` are misfiled as label refs.
fn step_complete_with(step: &Step) -> Vec<Gated<CompleteWithTarget>> {
    directives_named(step, "completewith")
        .filter_map(|d| {
            let (name, gate) = gated_value(d);
            if name.is_empty() {
                return None;
            }
            let value = if name.eq_ignore_ascii_case("next") {
                CompleteWithTarget::Next
            } else {
                CompleteWithTarget::Label(name)
            };
            Some(Gated { value, gate, line: d.line })
        })
        .collect()
}

/// `#optional [<< gate]` entries, in source order. A value of `Some("")` (two corpus lines are
/// written with a trailing space) is bare, not an empty gate.
///
/// Returns all of them: [`Operation::optional`] holds one, so the caller keeps the first and
/// DIAGNOSES the rest. One corpus step stacks two (`The Burning Crusade.lua:91519`/`:91527`), both
/// bare, so nothing observable is lost today — but `#optional << Horde` plus `#optional << !Horde`
/// would collapse to the first silently and wrongly.
fn step_optionals(step: &Step) -> Vec<Gated<()>> {
    directives_named(step, "optional")
        .map(|d| {
            let (_, gate) = gated_value(d);
            Gated { value: (), gate, line: d.line }
        })
        .collect()
}

/// Every step-body directive without a typed carrier, verbatim (`#xprate`, `#phase`, `#aldor`, …).
fn step_passthrough_directives(step: &Step) -> Vec<GuideDirective> {
    step.directives
        .iter()
        .filter(|d| !TYPED_DIRECTIVES.iter().any(|t| d.name.eq_ignore_ascii_case(t)))
        .map(|d| {
            let (value, gate) = gated_value(d);
            GuideDirective {
                name: d.name.clone(),
                value: (!value.is_empty()).then_some(value),
                gate,
                line: d.line,
            }
        })
        .collect()
}

/// Is this a *requirement placeholder* — an invisible step that exists only to park an extra
/// `#requires`, because RestedXP has no multi-requires syntax?
///
/// Structural predicate: after discarding `--` comment lines, the step body holds no command and
/// no instruction text — only directives — and it carries at least one `#requires`. The
/// `--XXREQ Placeholder …` note the guide author sometimes leaves marks only 6 of the 49
/// occurrences, so it must NOT be the detector; `#optional` is present on only 12, so it must not
/// be part of the predicate either.
fn is_placeholder_step(step: &Step) -> bool {
    step.commands.is_empty()
        && step.text.iter().all(|t| t.trim_start().starts_with("--"))
        && step.directives.iter().any(|d| d.name.eq_ignore_ascii_case("requires"))
}

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
            // The guide already said HOW, but `.mob <name>` says nothing about HOW MANY, and the
            // runtime defaults an absent quantity to 1. A step reading `.mob Young Wolf` +
            // `.complete 33,1` would kill exactly one wolf and then wait forever on a gate needing
            // eight. Bound the existing kill from the gate's own requirement.
            let needed = match gate {
                Gate::Objective { quest, index } => match state.client.get_quest(quest).await {
                    Ok(d) => d
                        .structured_objectives
                        .iter()
                        .find(|o| o.index as u32 == index)
                        .map(|o| match o.kind {
                            // Drop chance: see the overshoot rationale below.
                            ObjectiveKind::CollectItem => o.required.saturating_mul(5).max(1),
                            _ => o.required,
                        }),
                    Err(_) => None,
                },
                Gate::Item { count, .. } => Some(count.saturating_mul(5).max(1)),
            };
            if let Some(needed) = needed {
                for a in actions[..gate_at].iter_mut() {
                    if let ActionPayload::Kill(k) = &mut a.payload {
                        if k.quantity.is_none() {
                            k.quantity = Some(needed);
                        }
                    }
                }
            }
            continue;
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
                        gate: None,
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
                    gate: None,
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
    // RestedXP `.goto zone,x,y[,radius][,flags]` NEVER carries a height — the optional
    // third numeric is a reach RADIUS (`.goto 1429,47.601,36.720,45,0` = 45yd radius for
    // the Echo Ridge sweep). Baking it as Z buried those waypoints ~35yd inside the
    // terrain, the navmesh found no polygon, and travel wedged in awaiting_path forever
    // (live-caught). Z is always 0 here; the runtime resolves ground height on arrival.
    let z = 0.0;
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

/// Lower a `.xp` argument list to a §23 `LevelAtLeast(N)` expression, or `None` for the
/// out-of-scope variants. Corpus shapes (whole `restedxp guides` tree): `<N,1` (1416) and
/// `>N,1` (603) are RestedXP *skip-step* variants with different semantics — left inert.
/// `N` (50) and `N+M` (30, level N plus M experience points) are wait-until-level gates;
/// the sub-level `+M` XP refinement is deliberately dropped (out of scope) and `N+M` gates
/// on level N alone. Anything else (`N-M` countdown forms etc.) stays inert.
fn xp_level_dsl(args: &[String]) -> Option<String> {
    // The lexer comma-splits args; a comparison/skip form (`<50,1`) or any extra arg
    // means "not a plain level gate".
    if args.len() != 1 {
        return None;
    }
    let raw = args[0].trim();
    // `N` or `N+M` — take the level part; reject `N-M`, `<N`, `>N`, `N.N`, `N>>` etc.
    let level_part = raw.split('+').next()?;
    let level = level_part.parse::<u8>().ok()?;
    if let Some(xp_part) = raw.strip_prefix(level_part) {
        if !xp_part.is_empty() {
            // Must be exactly `+<digits>` to count as the N+M form.
            let digits = xp_part.strip_prefix('+')?;
            if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
        }
    }
    Some(format!("LevelAtLeast({level})"))
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
        gate: None,
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
                                    gate: None,
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
                                    gate: None,
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
                        // `.turnin 33,2` — the second comma-arg is the guide's reward
                        // choice (1-based slot). Dropping it left choice-reward turn-ins
                        // stalled on the reward frame at runtime (live-caught on quest 33).
                        let choose_reward = cmd.args.get(1).and_then(|a| a.parse::<u32>().ok());
                        match state.resolve_quest(id).await? {
                            Some((_, _, finisher)) => {
                                let npc = finisher.or(last_target);
                                actions.push(Action {
                                    id: Uuid::new_v4(),
                                    enabled: true,
                                    condition: None,
                                    class_restriction: None,
                                    gate: None,
                                    note: cmd.note.clone(),
                                    payload: ActionPayload::TurnInQuest(TurnInQuestAction {
                                        quest: id,
                                        npc,
                                        choose_reward,
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
                                    gate: None,
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
            // `.waypoint` shares `.goto`'s grammar and its meaning. ADR 07 §7.1 lists both as
            // sources of `Op::Travel` (38,087 and 593), and §5.7's decisive witness for baked
            // routes — the closed patrol circuit at `A-11-23.lua:215-231` — is three `.goto` lines
            // followed by fourteen `.waypoint` lines. Preserving `.waypoint` as an inert comment
            // deleted 14 of that circuit's 17 points before any compiler could see them.
            "goto" | "waypoint" => {
                let dest = cmd.args.first()
                    .map(|a| if a.parse::<u32>().is_ok() { format!("Map {}", a) } else { a.clone() })
                    .unwrap_or_else(|| "Unknown".to_string());
                let position = build_travel_position(state, step, &cmd.args);
                // The optional radius arg (`.goto zone,x,y,45,0`) is the guide's reach
                // tolerance in yards; keep the 5yd default when absent or zero, and clamp
                // so a typo can never make "arrived" meaninglessly wide.
                let authored = cmd.args.get(3).and_then(|s| s.parse::<f32>().ok());
                let tolerance = authored
                    .filter(|r| *r > 0.0)
                    .map(|r| r.clamp(5.0, 60.0))
                    .unwrap_or(5.0);
                // …and the *authored* number beside it, because the clamp above is an execution
                // policy that cannot be undone: `5` may mean "authored 5", "authored 0" or
                // "authored nothing", and §7.3.3's `radii` needs to tell them apart.
                let authored_radius = authored
                    .filter(|r| r.is_finite() && *r >= 0.0 && *r <= f32::from(u16::MAX))
                    .map(|r| r.round() as u16);
                actions.push(Action {
                    id: Uuid::new_v4(),
                    enabled: true,
                    condition: None,
                    class_restriction: None,
                    gate: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Travel(TravelAction {
                        destination: dest,
                        position,
                        tolerance,
                        authored_radius,
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
                        gate: None,
                        note: cmd.note.clone(),
                        payload: ActionPayload::Vendor(VendorAction {
                            npc,
                            // A `.vendor` stop in a leveling guide means "offload junk and
                            // fix gear" — false defaults sent the bot to Goldshire's vendor
                            // to sell nothing (live-caught).
                            sell_grey: true,
                            repair: true,
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
                        gate: None,
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
                        gate: None,
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
                        gate: None,
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
                        gate: None,
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
                        gate: None,
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
                    gate: None,
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
                    gate: None,
                    note: cmd.note.clone(),
                    payload: ActionPayload::Kill(KillTargetAction {
                        creature_entries: entries,
                        quantity: None,
                        loot: true,
                        ignore_elites: false,
                    }),
                });
            }
            "xp" => {
                // `.xp N` / `.xp N+M`: wait-until-level Completion gate (LevelAtLeast) so the
                // runtime holds — and grinds — instead of running ahead under-leveled. The
                // skip-step variants (`<N,1` / `>N,1`) keep the IF7 never-drop inert path,
                // diagnostic included, until their skip semantics are lowered deliberately.
                match xp_level_dsl(&cmd.args) {
                    Some(expression) => {
                        actions.push(Action {
                            id: Uuid::new_v4(),
                            enabled: true,
                            condition: None,
                            class_restriction: None,
                            gate: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::Condition(ConditionAction {
                                expression,
                                role: ConditionRole::Completion,
                            }),
                        });
                    }
                    None => {
                        actions.push(inert_preserved_action(state, step.index, cmd, true));
                    }
                }
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
                            gate: None,
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
                            gate: None,
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
                            gate: None,
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
                            gate: None,
                            note: cmd.note.clone(),
                            payload: ActionPayload::UseItem(UseItemAction {
                                item: item_id,
                                target: None,
                            }),
                        });
                    }
                }
            }
            "trainer" => {
                // .trainer - alias for train, uses last_target
                if let Some(npc) = last_target {
                    actions.push(Action {
                        id: Uuid::new_v4(),
                        enabled: true,
                        condition: None,
                        class_restriction: None,
                        gate: None,
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
                            gate: None,
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
                            gate: None,
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
                        gate: None,
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
                        gate: None,
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
        // `class_restriction` keeps its existing (class-only) consumers; `gate` carries the same
        // tail typed as a full gate expression, so race/faction/era tails survive with it.
        if cmd.class_restriction.is_some() {
            for action in &mut actions[actions_before..] {
                action.class_restriction = cmd.class_restriction.clone();
                action.gate = cmd.class_restriction.clone().map(GuideGate);
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

        // Fold each maximal run of requirement placeholders into the step that follows it: the
        // placeholder emits no task, but its parked `#requires` (and its `#label`, which would
        // otherwise dangle) move onto the absorbing step. A trailing run with nothing left to
        // absorb it is emitted as-is rather than dropped, flagged `placeholder = true`.
        let mut planned: Vec<(&Step, Vec<&Step>)> = Vec::new();
        let mut parked: Vec<&Step> = Vec::new();
        for step in &guide.steps {
            if is_placeholder_step(step) {
                parked.push(step);
            } else {
                planned.push((step, std::mem::take(&mut parked)));
            }
        }
        for step in parked {
            planned.push((step, Vec::new()));
        }

        // Build operations from steps.
        let mut operations = Vec::new();
        for (step, absorbed) in planned {
            let name = operation_name(step);
            let mut op = Operation::new(name);
            op.conditions = step.conditions.clone();
            op.gate = step.gate.clone().map(GuideGate);
            // `<< skip` is a disable sentinel, not an audience: 139 corpus steps the author turned
            // off compiled into live, executing tasks before this.
            op.enabled = !step.gate.as_deref().is_some_and(gate_disables);
            op.sticky = step.directives.iter().any(|d| d.name.eq_ignore_ascii_case("sticky"));
            op.looping = step.directives.iter().any(|d| d.name.eq_ignore_ascii_case("loop"));
            op.placeholder = is_placeholder_step(step);
            // Provenance spans the step marker through the last line that belongs to the step, and
            // a folded placeholder is *part of* the operation it was absorbed into — its parked
            // `#requires` is now this operation's edge, so a reader who follows the span back must
            // land on the lines that produced it. `line_end.max(line)` guards a `Step` that
            // predates `Step::line_end` and deserialised it as zero.
            let span_of = |s: &Step| (s.line as u32, s.line_end.max(s.line) as u32);
            let (mut line_start, mut line_end) = span_of(step);
            for parked_step in &absorbed {
                let (parked_start, parked_end) = span_of(parked_step);
                line_start = line_start.min(parked_start);
                line_end = line_end.max(parked_end);
            }
            op.source_line_start = Some(line_start);
            op.source_line_end = Some(line_end);
            // Absorbed placeholders contribute their parked entries first, in source order.
            // Everything the placeholder carried moves across, not just `#label`/`#requires`: it
            // emits no operation of its own, so a directive left behind here is destroyed. 22
            // `#optional` and 2 `#xprate` (`A-11-23.lua:732`, `:737`) were being dropped, and
            // `#xprate` decides whether the step belongs to the route at all.
            let mut optionals: Vec<Gated<()>> = Vec::new();
            for parked_step in &absorbed {
                op.labels.extend(step_labels(parked_step));
                op.requires.extend(step_requires(parked_step));
                op.complete_with.extend(step_complete_with(parked_step));
                op.directives.extend(step_passthrough_directives(parked_step));
                optionals.extend(step_optionals(parked_step));
            }
            op.labels.extend(step_labels(step));
            op.requires.extend(step_requires(step));
            op.complete_with.extend(step_complete_with(step));
            op.directives.extend(step_passthrough_directives(step));
            optionals.extend(step_optionals(step));
            // `Operation::optional` holds one entry; dropping the rest is an acceptable rule,
            // dropping them in silence is not.
            let mut optionals = optionals.into_iter();
            op.optional = optionals.next();
            if let Some(kept) = &op.optional {
                for discarded in optionals {
                    state.diagnostics.push(Diagnostic {
                        severity: Severity::Info,
                        code: "DUPLICATE_OPTIONAL_DISCARDED".to_string(),
                        message: format!(
                            "a second `#optional` (line {}) on this step is discarded; the first \
                             (line {}) is the one that applies",
                            discarded.line, kept.line
                        ),
                        entity: Some(format!("step:{}", step.index)),
                        action: None,
                    });
                }
            }
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

        // Task-graph diagnostics. `LabelGraph` was computed by `parse_guide` and attached to
        // nothing, so a dangling `#completewith`/`#requires` produced no project diagnostic at
        // all. Standing ruling: unresolved is ERROR severity, the ordering intent is dropped, the
        // step SURVIVES and the guide still compiles — every globally-unresolvable step in the
        // corpus carries its own completion predicate as the fallback.
        // A `#label` name defined more than once is only a problem when NOTHING tells the
        // definitions apart. The importer cannot rank gated definitions — that needs a resolved
        // archetype, which is C2's — so it keeps them all (`LabelGraph::definitions` is a multimap)
        // and reports only the genuinely undecidable groups.
        //
        // The EFFECTIVE gate is the pair (`#label` line's own tail, gate on the step carrying it).
        // Of the corpus's duplicate-name groups, 21 are disambiguated purely by complementary
        // `step` markers with byte-identical, tail-less `#label` lines (`Prowlers`,
        // `A-1-11-Human.lua:1273` `step << Paladin` / `:1280` `step << !Paladin`). Reading the
        // directive's gate alone reports all 21 as duplicates and trains operators to ignore
        // the code.
        //
        // Two definitions are undecidable when their effective gates are EQUAL — not merely when
        // both are absent. Testing only for absence has a false negative that is exactly as
        // undecidable as the case it does catch: `DruidTraining11`
        // (`The Burning Crusade.lua:71199`/`:72214`) and `chillwindEnd` (`:92465`/`:93213`) each
        // have two definitions gated identically, and no archetype can ever tell them apart.
        // Grouping by the gate pair subsumes the all-ungated case rather than special-casing it.
        let mut ambiguous: Vec<(&str, Vec<&LabelDef>)> = Vec::new();
        for (name, defs) in &guide.labels.definitions {
            if defs.len() < 2 {
                continue;
            }
            let mut by_gate: BTreeMap<(Option<&str>, Option<&str>), Vec<&LabelDef>> =
                BTreeMap::new();
            for def in defs {
                let step_gate = guide
                    .steps
                    .get(def.step)
                    .and_then(|s| s.gate.as_deref());
                by_gate
                    .entry((def.gate.as_deref(), step_gate))
                    .or_default()
                    .push(def);
            }
            for undecidable in by_gate.into_values() {
                if undecidable.len() >= 2 {
                    ambiguous.push((name.as_str(), undecidable));
                }
            }
        }
        // `HashMap` iteration order is unspecified; report in source order so the diagnostic list
        // is reproducible.
        ambiguous.sort_by_key(|(name, defs)| (defs[0].line, *name));
        for (name, defs) in ambiguous {
            let lines: Vec<String> = defs.iter().map(|d| d.line.to_string()).collect();
            // Name the shared gate when there is one. These groups are undecidable because their
            // effective gates are IDENTICAL, which includes but is not limited to all being absent
            // — saying "no gate on any of them" would be a lie for `DruidTraining11` (both
            // `<< Druid`) and `chillwindEnd` (both `<< Alliance`).
            let step_gate = guide.steps.get(defs[0].step).and_then(|s| s.gate.as_deref());
            let shared = match (defs[0].gate.as_deref(), step_gate) {
                (None, None) => "no gate on any of them".to_string(),
                (label_gate, marker_gate) => {
                    let mut parts = Vec::new();
                    if let Some(g) = label_gate {
                        parts.push(format!("`#label … << {g}`"));
                    }
                    if let Some(g) = marker_gate {
                        parts.push(format!("`step << {g}`"));
                    }
                    format!("the same gate on all of them ({})", parts.join(" under "))
                }
            };
            state.diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "DUPLICATE_LABEL".to_string(),
                message: format!(
                    "`#label {name}` is defined {} times in this guide with {shared} (lines {}); \
                     a `#completewith`/`#requires` naming it cannot be bound to one of them by \
                     any rule",
                    defs.len(),
                    lines.join(", ")
                ),
                entity: Some(format!("step:{}", defs[0].step)),
                action: None,
            });
        }

        for r in &guide.labels.unresolved {
            state.diagnostics.push(Diagnostic {
                severity: Severity::Error,
                code: "UNRESOLVED_COMPLETEWITH".to_string(),
                message: format!(
                    "`#completewith {}` (line {}) names no `#label` in this guide; the step keeps \
                     its own completion predicate",
                    r.label, r.line
                ),
                entity: Some(format!("step:{}", r.from_step)),
                action: None,
            });
        }
        for r in &guide.labels.unresolved_requires {
            state.diagnostics.push(Diagnostic {
                severity: Severity::Error,
                code: "UNRESOLVED_REQUIRES".to_string(),
                message: format!(
                    "`#requires {}` (line {}) names no `#label` in this guide; the edge is \
                     dropped and the step is retained",
                    r.label, r.line
                ),
                entity: Some(format!("step:{}", r.from_step)),
                action: None,
            });
        }

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