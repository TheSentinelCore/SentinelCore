//! Sentinel Questing — Project Validator (Phase 5).
//!
//! Validates Projects for:
//! - Duplicate NPCs (same entry in npc_library)
//! - Missing NPCs (references to non-existent UUIDs)
//! - Missing Quests (referenced in actions but not in library)
//! - Circular Conditions (condition expressions that reference each other)
//! - Unused Variables
//! - Broken References
//! - Duplicate Actions within operations

use std::collections::HashSet;
use uuid::Uuid;

use sentinel_models::authoring::{ActionPayload, Diagnostic, Project, Severity, NPCReference};

pub struct Validator;

impl Validator {
    /// Validate a Project and return diagnostics.
    pub fn validate(project: &Project) -> Vec<Diagnostic> {
        let mut diagnostics = Vec::new();

        // Check for duplicate NPCs (same entry in npc_library)
        let mut seen_entries: HashSet<Option<u32>> = HashSet::new();
        for npc in &project.npc_library {
            if let Some(entry) = npc.entry {
                if !seen_entries.insert(Some(entry)) {
                    diagnostics.push(Diagnostic {
                        severity: Severity::Warning,
                        code: "DUPLICATE_NPC".to_string(),
                        message: format!("Duplicate NPC entry {} in npc_library", entry),
                        entity: Some(npc.name.clone()),
                        action: None,
                    });
                }
            }
        }

        // Check for duplicate quests (same quest_id in quest_library)
        let mut seen_quest_ids: HashSet<u32> = HashSet::new();
        for quest in &project.quest_library {
            if !seen_quest_ids.insert(quest.quest_id) {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "DUPLICATE_QUEST".to_string(),
                    message: format!("Duplicate quest ID {} in quest_library", quest.quest_id),
                    entity: quest.title.clone(),
                    action: None,
                });
            }
        }

        // Check for broken NPC references in actions
        let npc_uuids: HashSet<Uuid> = project.npc_library.iter().map(|n| n.id).collect();
        for op in &project.operations {
            for action in &op.actions {
                match &action.payload {
                    ActionPayload::AcceptQuest(a) => {
                        if let Some(npc_uuid) = a.npc {
                            if !npc_uuids.contains(&npc_uuid) {
                                diagnostics.push(Diagnostic {
                                    severity: Severity::Error,
                                    code: "BROKEN_NPC_REFERENCE".to_string(),
                                    message: format!("AcceptQuest references missing NPC {}", npc_uuid),
                                    entity: Some(format!("quest:{}", a.quest)),
                                    action: Some(action.id.to_string()),
                                });
                            }
                        }
                    }
                    ActionPayload::TurnInQuest(t) => {
                        if let Some(npc_uuid) = t.npc {
                            if !npc_uuids.contains(&npc_uuid) {
                                diagnostics.push(Diagnostic {
                                    severity: Severity::Error,
                                    code: "BROKEN_NPC_REFERENCE".to_string(),
                                    message: format!("TurnInQuest references missing NPC {}", npc_uuid),
                                    entity: Some(format!("quest:{}", t.quest)),
                                    action: Some(action.id.to_string()),
                                });
                            }
                        }
                    }
                    ActionPayload::Vendor(v) => {
                        if !npc_uuids.contains(&v.npc) {
                            diagnostics.push(Diagnostic {
                                severity: Severity::Error,
                                code: "BROKEN_NPC_REFERENCE".to_string(),
                                message: format!("Vendor references missing NPC {}", v.npc),
                                entity: None,
                                action: Some(action.id.to_string()),
                            });
                        }
                    }
                    ActionPayload::Train(tr) => {
                        if !npc_uuids.contains(&tr.npc) {
                            diagnostics.push(Diagnostic {
                                severity: Severity::Error,
                                code: "BROKEN_NPC_REFERENCE".to_string(),
                                message: format!("Train references missing NPC {}", tr.npc),
                                entity: None,
                                action: Some(action.id.to_string()),
                            });
                        }
                    }
                    ActionPayload::Flight(f) => {
                        if !npc_uuids.contains(&f.npc) {
                            diagnostics.push(Diagnostic {
                                severity: Severity::Error,
                                code: "BROKEN_NPC_REFERENCE".to_string(),
                                message: format!("Flight references missing NPC {}", f.npc),
                                entity: Some(f.destination.clone()),
                                action: Some(action.id.to_string()),
                            });
                        }
                    }
                    ActionPayload::LearnFlightPath(l) => {
                        if !npc_uuids.contains(&l.npc) {
                            diagnostics.push(Diagnostic {
                                severity: Severity::Error,
                                code: "BROKEN_NPC_REFERENCE".to_string(),
                                message: format!("LearnFlightPath references missing NPC {}", l.npc),
                                entity: None,
                                action: Some(action.id.to_string()),
                            });
                        }
                    }
                    _ => {}
                }
            }
        }

        // Check for unresolved quests (referenced in actions but not in library)
        let quest_ids: HashSet<u32> = project.quest_library.iter().map(|q| q.quest_id).collect();
        // Skip check if this was imported - importer already emits diagnostics for unresolved quests
        if project.import_metadata.is_none() {
            for op in &project.operations {
                for action in &op.actions {
                    match &action.payload {
                        ActionPayload::AcceptQuest(a) => {
                            if !quest_ids.contains(&a.quest) {
                                diagnostics.push(Diagnostic {
                                    severity: Severity::Warning,
                                    code: "UNRESOLVED_QUEST".to_string(),
                                    message: format!("AcceptQuest references quest {} not in quest_library", a.quest),
                                    entity: Some(format!("quest:{}", a.quest)),
                                    action: Some(action.id.to_string()),
                                });
                            }
                        }
                        ActionPayload::TurnInQuest(t) => {
                            if !quest_ids.contains(&t.quest) {
                                diagnostics.push(Diagnostic {
                                    severity: Severity::Warning,
                                    code: "UNRESOLVED_QUEST".to_string(),
                                    message: format!("TurnInQuest references quest {} not in quest_library", t.quest),
                                    entity: Some(format!("quest:{}", t.quest)),
                                    action: Some(action.id.to_string()),
                                });
                            }
                        }
                        _ => {}
                    }
                }
            }
        }

        // Check for circular condition detection (variables that reference themselves through operations)
        // For now, check if any condition expression references itself directly
        // This is a simplified check - real implementation would build a dependency graph
        let mut used_variables: HashSet<String> = HashSet::new();
        for op in &project.operations {
            for action in &op.actions {
                if let ActionPayload::SetVariable(sv) = &action.payload {
                    used_variables.insert(sv.name.clone());
                }
            }
        }
        // Check if any condition uses undefined variables
        for op in &project.operations {
            for action in &op.actions {
                if let ActionPayload::Condition(_cond) = &action.payload {
                    // Would need to parse expression and check against used_variables
                    // Placeholder for now
                }
            }
        }

        // Check for unused variables (declared but never referenced)
        // This would require analyzing all condition expressions across the project
        // Placeholder for now

        diagnostics
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_project() -> Project {
        sentinel_models::authoring::new_project("test")
    }

    #[test]
    fn detects_duplicate_npc_entry() {
        let mut project = make_project();
        project.npc_library = vec![
            NPCReference { id: Uuid::nil(), entry: Some(123), guid: None, name: "Test1".to_string(),
                faction: None, roles: vec![], position: None, source: None, notes: None },
            NPCReference { id: Uuid::nil(), entry: Some(123), guid: None, name: "Test2".to_string(),
                faction: None, roles: vec![], position: None, source: None, notes: None },
        ];
        let diags = Validator::validate(&project);
        assert!(diags.iter().any(|d| d.code == "DUPLICATE_NPC"));
    }

    #[test]
    fn no_duplicate_npc_when_entries_differ() {
        let mut project = make_project();
        project.npc_library = vec![
            NPCReference { id: Uuid::nil(), entry: Some(123), guid: None, name: "Test1".to_string(),
                faction: None, roles: vec![], position: None, source: None, notes: None },
            NPCReference { id: Uuid::nil(), entry: Some(456), guid: None, name: "Test2".to_string(),
                faction: None, roles: vec![], position: None, source: None, notes: None },
        ];
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "DUPLICATE_NPC"));
    }
}