//! Sentinel Questing — Compiler (Phase 6).
//!
//! Compiles Projects into RuntimeProfiles for Lua execution.

use std::collections::HashMap;
use uuid::Uuid;

use sentinel_models::authoring::{Action, ActionPayload, Project};
use sentinel_models::runtime::{
    compute_content_hash, RuntimeAction, RuntimeOperation, RuntimeProfile, RuntimeAcceptQuest,
    RuntimeFlight, RuntimeHearth, RuntimeKill, RuntimeVendor, RuntimeTrain, RuntimeUseItem,
    RuntimeComment, RuntimeTravel, RuntimeTurnInQuest, RuntimeWaypoint, RuntimeRepair,
    RuntimeLearnFlightPath, RuntimeConditionAction, RuntimeSetVariable, RuntimeEscort,
    RuntimePatrol, RuntimeGrind, RuntimeLoot, RuntimeBank, RuntimeMailbox, RuntimeWait,
    RuntimeCondition, RuntimeInteractNpc,
};

/// Compiler errors that prevent profile generation.
#[derive(Debug, Clone, thiserror::Error)]
pub enum CompilerError {
    #[error("NPC reference could not be resolved to an entry")]
    UnresolvedNpc,
    #[error("Quest reference could not be resolved")]
    UnresolvedQuest,
}

pub struct Compiler;

impl Compiler {
    /// Compile a Project into a RuntimeProfile.
    pub fn compile(project: &Project) -> Result<RuntimeProfile, CompilerError> {
        let npc_uuid_to_entry: HashMap<Uuid, u32> = project.npc_library
            .iter()
            .filter_map(|n| n.entry.map(|e| (n.id, e)))
            .collect();

        let runtime_operations: Vec<RuntimeOperation> = project.operations
            .iter()
            .map(|op| resolve_operation(op, &npc_uuid_to_entry))
            .collect::<Result<Vec<_>, _>>()?;

        let mut profile = RuntimeProfile::new(project.metadata.name.clone(), runtime_operations);
        profile.content_hash = compute_content_hash(&profile);
        Ok(profile)
    }
}

fn resolve_operation(
    op: &sentinel_models::authoring::Operation,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
) -> Result<RuntimeOperation, CompilerError> {
    let runtime_actions: Vec<RuntimeAction> = op.actions
        .iter()
        .map(|a| resolve_action(a, npc_uuid_to_entry))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(RuntimeOperation::new(op.id, op.name.clone(), runtime_actions))
}

fn resolve_action(
    action: &Action,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
) -> Result<RuntimeAction, CompilerError> {
    Ok(match &action.payload {
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
        ActionPayload::Condition(_cond) => {
            // Parse condition expression - simplified for now
            RuntimeAction::Condition(RuntimeConditionAction {
                condition: RuntimeCondition::AlwaysTrue,
            })
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
            RuntimeAction::Loot(RuntimeLoot {
                object_entry: 0, // Would need object resolution via QueryServer
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
    })
}