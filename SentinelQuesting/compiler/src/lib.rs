//! Sentinel Questing — Compiler (Phase 6).
//!
//! Compiles Projects into RuntimeProfiles for Lua execution.

use std::collections::HashMap;
use uuid::Uuid;

mod condition;

use sentinel_models::authoring::{Action, ActionPayload, Diagnostic, Project, Severity};
use sentinel_models::runtime::{
    compute_content_hash, GuardedAction, RuntimeAction, RuntimeOperation, RuntimeProfile, RuntimeAcceptQuest,
    RuntimeFlight, RuntimeHearth, RuntimeKill, RuntimeVendor, RuntimeTrain, RuntimeUseItem,
    RuntimeComment, RuntimeTravel, RuntimeTurnInQuest, RuntimeWaypoint, RuntimeRepair,
    RuntimeLearnFlightPath, RuntimeConditionAction, RuntimeSetVariable, RuntimeEscort,
    RuntimePatrol, RuntimeGrind, RuntimeLoot, RuntimeBank, RuntimeMailbox, RuntimeWait,
    RuntimeCondition, RuntimeInteractNpc,
};

/// Title-Case class names the runtime's `CLASS_ID_TO_NAME` map can produce
/// (`sentinel/modules/questing/runtime_profile.lua`). Anything else in a `class_restriction`
/// tail is an authoring error worth a diagnostic, not a guess.
const KNOWN_CLASSES: &[&str] = &[
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "DeathKnight", "Shaman", "Mage", "Warlock",
    "Druid",
];

/// Lower a RestedXP class-tail (e.g. `"Warrior"`, `"Warrior/Paladin"`, `"!Rogue"`) into a
/// `RuntimeCondition` guard (CL4). Returns `None` — plus a diagnostic — for empty/unknown class
/// tokens; never panics, never guesses.
fn parse_class_guard(
    restriction: &str,
    action_id: Uuid,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<RuntimeCondition> {
    let trimmed = restriction.trim();
    if trimmed.is_empty() {
        return None;
    }
    let (negate, rest) = match trimmed.strip_prefix('!') {
        Some(stripped) => (true, stripped),
        None => (false, trimmed),
    };
    let names: Vec<&str> = rest.split('/').map(|s| s.trim()).collect();

    let unknown = |diagnostics: &mut Vec<Diagnostic>, detail: String| {
        diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: "UNKNOWN_CLASS_RESTRICTION".to_string(),
            message: format!(
                "class restriction '{restriction}' could not be mapped to a guard: {detail}"
            ),
            entity: Some(restriction.to_string()),
            action: Some(action_id.to_string()),
        });
    };

    if names.is_empty() || names.iter().any(|n| n.is_empty()) {
        unknown(diagnostics, "empty class token".to_string());
        return None;
    }
    for name in &names {
        if !KNOWN_CLASSES.contains(name) {
            unknown(diagnostics, format!("unknown class '{name}'"));
            return None;
        }
    }

    let base = if names.len() == 1 {
        RuntimeCondition::ClassIs(names[0].to_string())
    } else {
        RuntimeCondition::Any(names.iter().map(|n| RuntimeCondition::ClassIs(n.to_string())).collect())
    };
    Some(if negate { RuntimeCondition::Not(Box::new(base)) } else { base })
}

/// Compiler errors that prevent profile generation.
#[derive(Debug, Clone, thiserror::Error)]
pub enum CompilerError {
    #[error("NPC reference could not be resolved to an entry")]
    UnresolvedNpc,
    #[error("Quest reference could not be resolved")]
    UnresolvedQuest,
}

/// Non-fatal compile-time findings, kept out of `RuntimeProfile` (clean runtime artifact).
/// `unmapped_conditions` populated here (CL1); PR2b adds `unresolved` (unresolvable
/// `LootObject` references — CL2). Class filtering (CL4, PR5c) lowers `Action.class_restriction`
/// into a per-action `GuardedAction.guard` (`RuntimeCondition`); unknown class tokens surface
/// here as `UNKNOWN_CLASS_RESTRICTION` diagnostics rather than a guessed guard.
#[derive(Debug, Clone, Default)]
pub struct CompileReport {
    pub unmapped_conditions: Vec<Diagnostic>,
    /// Count of references (currently: `LootObject`) that could not be resolved to a
    /// concrete entry. Mirrored as an `UNRESOLVED_OBJECT` diagnostic in `unmapped_conditions`.
    pub unresolved: u32,
}

pub struct Compiler;

impl Compiler {
    /// Compile a Project into a RuntimeProfile plus a report of non-fatal findings.
    pub fn compile(project: &Project) -> Result<(RuntimeProfile, CompileReport), CompilerError> {
        let npc_uuid_to_entry: HashMap<Uuid, u32> = project.npc_library
            .iter()
            .filter_map(|n| n.entry.map(|e| (n.id, e)))
            .collect();
        let object_uuid_to_entry: HashMap<Uuid, u32> = project.object_library
            .iter()
            .map(|o| (o.id, o.entry))
            .collect();

        let mut diagnostics: Vec<Diagnostic> = Vec::new();
        let mut unresolved: u32 = 0;
        let runtime_operations: Vec<RuntimeOperation> = project.operations
            .iter()
            .map(|op| resolve_operation(op, &npc_uuid_to_entry, &object_uuid_to_entry, &mut diagnostics, &mut unresolved))
            .collect::<Result<Vec<_>, _>>()?;

        let mut profile = RuntimeProfile::new(project.metadata.name.clone(), runtime_operations);
        profile.content_hash = compute_content_hash(&profile);
        let report = CompileReport { unmapped_conditions: diagnostics, unresolved };
        Ok((profile, report))
    }
}

fn resolve_operation(
    op: &sentinel_models::authoring::Operation,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
    object_uuid_to_entry: &HashMap<Uuid, u32>,
    diagnostics: &mut Vec<Diagnostic>,
    unresolved: &mut u32,
) -> Result<RuntimeOperation, CompilerError> {
    let runtime_actions: Vec<GuardedAction> = op.actions
        .iter()
        .map(|a| resolve_action(a, npc_uuid_to_entry, object_uuid_to_entry, diagnostics, unresolved))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(RuntimeOperation {
        id: op.id,
        name: op.name.clone(),
        entry_conditions: Vec::new(),
        exit_conditions: Vec::new(),
        actions: runtime_actions,
    })
}

fn resolve_action(
    action: &Action,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
    object_uuid_to_entry: &HashMap<Uuid, u32>,
    diagnostics: &mut Vec<Diagnostic>,
    unresolved: &mut u32,
) -> Result<GuardedAction, CompilerError> {
    let runtime_action = match &action.payload {
        ActionPayload::AcceptQuest(a) => {
            let npc_entry = a.npc.and_then(|u| npc_uuid_to_entry.get(&u).copied())
                .ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::AcceptQuest(RuntimeAcceptQuest {
                quest_id: a.quest,
                npc_entry,
                auto_complete_dialog: a.auto_complete_dialog,
                optional: a.optional,
            })
        }
        ActionPayload::TurnInQuest(t) => {
            let npc_entry = t.npc.and_then(|u| npc_uuid_to_entry.get(&u).copied())
                .ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::TurnInQuest(RuntimeTurnInQuest {
                quest_id: t.quest,
                npc_entry,
                choose_reward: t.choose_reward,
                optional: t.optional,
            })
        }
        ActionPayload::Travel(tr) => {
            // Pass through .goto coordinates from importer as waypoint
            let position = tr.position
                .map(|p| RuntimeWaypoint::new(p.map, p.world_x, p.world_y, p.world_z))
                .unwrap_or_else(|| RuntimeWaypoint::new(0, 0.0, 0.0, 0.0));
            RuntimeAction::Travel(RuntimeTravel {
                destination: tr.destination.clone(),
                position,
                tolerance: tr.tolerance,
                allow_flight: tr.allow_flight,
                timeout: tr.timeout,
            })
        }
        ActionPayload::Vendor(v) => {
            let npc_entry = *npc_uuid_to_entry.get(&v.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Vendor(RuntimeVendor {
                npc_entry,
                sell_grey: v.sell_grey,
                repair: v.repair,
                buy_items: v.buy_items.clone(),
                minimum_free_slots: v.minimum_free_slots,
            })
        }
        ActionPayload::Train(tr) => {
            let npc_entry = *npc_uuid_to_entry.get(&tr.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Train(RuntimeTrain {
                npc_entry,
                trainer_type: tr.trainer_type.clone(),
                minimum_level: tr.minimum_level,
            })
        }
        ActionPayload::Flight(f) => {
            let npc_entry = *npc_uuid_to_entry.get(&f.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Flight(RuntimeFlight {
                npc_entry,
                destination: f.destination.clone(),
            })
        }
        ActionPayload::Hearth(h) => {
            RuntimeAction::Hearth(RuntimeHearth {
                innkeeper_entry: h.innkeeper.and_then(|u| npc_uuid_to_entry.get(&u).copied()),
                destination: h.destination.clone(),
            })
        }
        ActionPayload::Kill(k) => {
            RuntimeAction::Kill(RuntimeKill {
                creature_entries: k.creature_entries.clone(),
                quantity: k.quantity,
                loot: k.loot,
                ignore_elites: k.ignore_elites,
            })
        }
        ActionPayload::UseItem(u) => {
            RuntimeAction::UseItem(RuntimeUseItem {
                item: u.item,
                target_entry: u.target.and_then(|e| npc_uuid_to_entry.get(&e).copied()),
            })
        }
        ActionPayload::Comment(c) => {
            RuntimeAction::Comment(RuntimeComment {
                text: c.text.clone(),
            })
        }
        // Additional action types (Wave 3 completions)
        ActionPayload::Repair(r) => {
            let npc_entry = *npc_uuid_to_entry.get(&r.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Repair(RuntimeRepair { npc_entry })
        }
        ActionPayload::LearnFlightPath(fp) => {
            let npc_entry = *npc_uuid_to_entry.get(&fp.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::LearnFlightPath(RuntimeLearnFlightPath { npc_entry })
        }
        ActionPayload::Condition(cond) => {
            // §23 DSL -> typed RuntimeCondition; unmappable: diagnostic first, THEN fail open to
            // AlwaysTrue (design Decision 7) — never silently substituted.
            let condition = condition::parse_condition(&cond.expression).unwrap_or_else(|err| {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNMAPPED_CONDITION".to_string(),
                    message: format!(
                        "condition expression '{}' could not be mapped to a RuntimeCondition: {err}",
                        cond.expression
                    ),
                    entity: Some(cond.expression.clone()),
                    action: Some(action.id.to_string()),
                });
                RuntimeCondition::AlwaysTrue
            });
            RuntimeAction::Condition(RuntimeConditionAction { condition, role: cond.role })
        }
        ActionPayload::SetVariable(sv) => {
            RuntimeAction::SetVariable(RuntimeSetVariable {
                name: sv.name.clone(),
                value: sv.value.clone(),
            })
        }
        ActionPayload::Escort(e) => {
            let npc_entry = *npc_uuid_to_entry.get(&e.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Escort(RuntimeEscort {
                npc_entry,
                area: e.area,
                timeout: e.timeout,
            })
        }
        ActionPayload::Patrol(p) => {
            RuntimeAction::Patrol(RuntimePatrol {
                area: p.area,
                waypoints: p.waypoints.iter()
                    .map(|w| RuntimeWaypoint::new(w.map, w.world_x, w.world_y, w.world_z))
                    .collect(),
            })
        }
        ActionPayload::GrindArea(g) => {
            RuntimeAction::Grind(RuntimeGrind {
                polygon: g.polygon,
                targets: g.targets.clone(),
                loot: g.loot,
                timeout: g.timeout,
                minimum_kills: g.minimum_kills,
                maximum_kills: g.maximum_kills,
                stop_condition: g.stop_condition.clone(),
            })
        }
        ActionPayload::LootObject(l) => {
            // CL2: resolve the authoring object UUID to its concrete entry via the project's
            // object library (mirrors the NPC-resolution path). Unresolvable -> diagnostic +
            // `unresolved` tally, never a silent `0` masquerading as a valid entry.
            let object_entry = object_uuid_to_entry.get(&l.object).copied().unwrap_or_else(|| {
                *unresolved += 1;
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNRESOLVED_OBJECT".to_string(),
                    message: format!(
                        "loot object reference '{}' could not be resolved to an entry",
                        l.object
                    ),
                    entity: Some(l.object.to_string()),
                    action: Some(action.id.to_string()),
                });
                0
            });
            RuntimeAction::Loot(RuntimeLoot {
                object_entry,
                count: l.count,
            })
        }
        ActionPayload::Bank(b) => {
            let npc_entry = *npc_uuid_to_entry.get(&b.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Bank(RuntimeBank { npc_entry })
        }
        ActionPayload::Mailbox(m) => {
            let npc_entry = *npc_uuid_to_entry.get(&m.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::Mailbox(RuntimeMailbox { npc_entry })
        }
        ActionPayload::InteractNPC(i) => {
            let npc_entry = *npc_uuid_to_entry.get(&i.npc).ok_or(CompilerError::UnresolvedNpc)?;
            RuntimeAction::InteractNpc(RuntimeInteractNpc {
                npc_entry,
                gossip: i.gossip.clone(),
            })
        }
        ActionPayload::Wait(w) => {
            RuntimeAction::Wait(RuntimeWait { duration: w.duration })
        }
        ActionPayload::SetHearth(sh) => {
            RuntimeAction::Hearth(RuntimeHearth {
                innkeeper_entry: sh.npc.and_then(|u| npc_uuid_to_entry.get(&u).copied()),
                destination: None,
            })
        }
    };

    // CL4: lower the authoring class-tail into a per-action guard. `None`/empty -> no guard,
    // unchanged behavior; unknown tokens -> diagnostic + no guard (fail open, never a guess).
    let guard = action.class_restriction
        .as_deref()
        .and_then(|r| parse_class_guard(r, action.id, diagnostics));

    Ok(GuardedAction { action: runtime_action, guard })
}