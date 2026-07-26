//! Sentinel Questing — Project Validator (Phase 5).
//!
//! Validates Projects for:
//! - Duplicate NPC entries
//! - Duplicate quest entries
//! - Missing NPC references (broken UUIDs in actions)
//! - Unresolved quest references
//! - Circular condition dependencies
//! - Unused variables
//! - Missing/incomplete coordinates
//! - Quest chain consistency
//! - Invalid operation order (prerequisite ordering)
//! - Unused assets (NPCs and quests never referenced by any operation)
//! - Broken references

use std::collections::{HashMap, HashSet};

use sentinel_models::authoring::{
    ActionPayload, Diagnostic, Position, Project, QuestReference, Severity,
};

pub struct Validator;

impl Validator {
    /// Validate a Project and return diagnostics.
    pub fn validate(project: &Project) -> Vec<Diagnostic> {
        let mut diagnostics = Vec::new();

        Self::check_duplicate_npcs(project, &mut diagnostics);
        Self::check_duplicate_quests(project, &mut diagnostics);
        Self::check_broken_npc_references(project, &mut diagnostics);
        Self::check_unresolved_quests(project, &mut diagnostics);
        Self::check_circular_conditions(project, &mut diagnostics);
        Self::check_unused_variables(project, &mut diagnostics);
        Self::check_missing_coordinates(project, &mut diagnostics);
        Self::check_quest_chain_consistency(project, &mut diagnostics);
        Self::check_invalid_operation_order(project, &mut diagnostics);
        Self::check_unused_assets(project, &mut diagnostics);

        diagnostics
    }

    // ==================================================================
    // Duplicate NPCs
    // ==================================================================

    fn check_duplicate_npcs(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
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
    }

    // ==================================================================
    // Duplicate quests
    // ==================================================================

    fn check_duplicate_quests(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
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
    }

    // ==================================================================
    // Broken NPC references
    // ==================================================================

    fn check_broken_npc_references(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        let npc_uuids: HashSet<uuid::Uuid> = project.npc_library.iter().map(|n| n.id).collect();
        for op in &project.operations {
            for action in &op.actions {
                Self::check_single_npc_ref(&action.payload, &npc_uuids, action.id, diagnostics);
            }
        }
    }

    fn check_single_npc_ref(
        payload: &ActionPayload,
        npc_uuids: &HashSet<uuid::Uuid>,
        action_id: uuid::Uuid,
        diagnostics: &mut Vec<Diagnostic>,
    ) {
        let npc_uuid = match payload {
            ActionPayload::Vendor(v) => Some(v.npc),
            ActionPayload::Train(tr) => Some(tr.npc),
            ActionPayload::Flight(f) => Some(f.npc),
            ActionPayload::LearnFlightPath(l) => Some(l.npc),
            ActionPayload::InteractNPC(i) => Some(i.npc),
            ActionPayload::AcceptQuest(a) => a.npc,
            ActionPayload::TurnInQuest(t) => t.npc,
            ActionPayload::Repair(r) => Some(r.npc),
            ActionPayload::Mailbox(m) => Some(m.npc),
            ActionPayload::Bank(b) => Some(b.npc),
            _ => return,
        };

        if let Some(npc_id) = npc_uuid {
            if !npc_uuids.contains(&npc_id) {
                let code = match payload {
                    ActionPayload::Vendor(_) => "Vendor",
                    ActionPayload::Train(_) => "Train",
                    ActionPayload::Flight(_) => "Flight",
                    ActionPayload::LearnFlightPath(_) => "LearnFlightPath",
                    ActionPayload::InteractNPC(_) => "InteractNPC",
                    ActionPayload::AcceptQuest(_) => "AcceptQuest",
                    ActionPayload::TurnInQuest(_) => "TurnInQuest",
                    ActionPayload::Repair(_) => "Repair",
                    ActionPayload::Mailbox(_) => "Mailbox",
                    ActionPayload::Bank(_) => "Bank",
                    _ => "Unknown",
                };

                let entity = match payload {
                    ActionPayload::AcceptQuest(a) => Some(format!("quest:{}", a.quest)),
                    ActionPayload::TurnInQuest(t) => Some(format!("quest:{}", t.quest)),
                    ActionPayload::Flight(f) => Some(f.destination.clone()),
                    _ => None,
                };

                diagnostics.push(Diagnostic {
                    severity: Severity::Error,
                    code: "BROKEN_NPC_REFERENCE".to_string(),
                    message: format!("{} references missing NPC {}", code, npc_id),
                    entity,
                    action: Some(action_id.to_string()),
                });
            }
        }
    }

    // ==================================================================
    // Unresolved quests
    // ==================================================================

    fn check_unresolved_quests(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        if project.import_metadata.is_some() {
            return;
        }

        let quest_ids: HashSet<u32> = project.quest_library.iter().map(|q| q.quest_id).collect();
        for op in &project.operations {
            for action in &op.actions {
                match &action.payload {
                    ActionPayload::AcceptQuest(a) if !quest_ids.contains(&a.quest) => {
                        diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "UNRESOLVED_QUEST".to_string(),
                            message: format!(
                                "AcceptQuest references quest {} not in quest_library",
                                a.quest
                            ),
                            entity: Some(format!("quest:{}", a.quest)),
                            action: Some(action.id.to_string()),
                        });
                    }
                    ActionPayload::TurnInQuest(t) if !quest_ids.contains(&t.quest) => {
                        diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "UNRESOLVED_QUEST".to_string(),
                            message: format!(
                                "TurnInQuest references quest {} not in quest_library",
                                t.quest
                            ),
                            entity: Some(format!("quest:{}", t.quest)),
                            action: Some(action.id.to_string()),
                        });
                    }
                    _ => {}
                }
            }
        }
    }

    // ==================================================================
    // Circular condition detection (W7.1)
    // ==================================================================
    //
    // Operations execute sequentially top-to-bottom. An operation's
    // condition can only reference variables written by EARLIER operations.
    // If operation i reads variable X in its condition, but X is only
    // written by operations at index >= i, then the condition can never
    // be satisfied — that's a circular/unreachable condition.
    //
    // Algorithm:
    //   1. For each operation, collect READ variables (from its conditions)
    //      and WRITE variables (from SetVariable actions).
    //   2. For each operation i, check each variable it reads.
    //   3. If ALL writes of that variable happen at index >= i (the var
    //      hasn't been set yet when op i runs), flag it.

    fn check_circular_conditions(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        let var_names: Vec<&str> = project.variables.iter().map(|v| v.name.as_str()).collect();
        if var_names.is_empty() {
            return;
        }

        // Collect condition expressions (operation-level + ConditionAction actions).
        let op_conditions: Vec<Vec<String>> = project
            .operations
            .iter()
            .map(|op| {
                let mut conds = op.conditions.clone();
                for action in &op.actions {
                    if let ActionPayload::Condition(c) = &action.payload {
                        conds.push(c.expression.clone());
                    }
                }
                conds
            })
            .collect();

        // Which variables does each operation READ (in its conditions)?
        let op_reads: Vec<HashSet<String>> = op_conditions
            .iter()
            .map(|conds| {
                let mut read_vars = HashSet::new();
                for expr in conds {
                    for var_name in &var_names {
                        if expr.contains(var_name) {
                            read_vars.insert(var_name.to_string());
                        }
                    }
                }
                read_vars
            })
            .collect();

        // Which variables does each operation WRITE?
        let op_writes: Vec<HashSet<String>> = project
            .operations
            .iter()
            .map(|op| {
                let mut write_vars = HashSet::new();
                for action in &op.actions {
                    if let ActionPayload::SetVariable(sv) = &action.payload {
                        write_vars.insert(sv.name.clone());
                    }
                }
                write_vars
            })
            .collect();

        // For each variable, find the earliest operation index that writes it.
        let mut var_earliest_write: std::collections::HashMap<&str, usize> =
            std::collections::HashMap::new();
        for (i, writes) in op_writes.iter().enumerate() {
            for var_name in writes {
                var_earliest_write
                    .entry(var_name.as_str())
                    .or_insert(i);
            }
        }

        // For each operation, check if any variable in its condition is
        // only written by STRICTLY LATER operations.  A self-reference
        // (read-in-condition + write-in-action within the same op) is a
        // normal counter/tracking pattern — not flagged.
        for (i, reads) in op_reads.iter().enumerate() {
            for var_name in reads {
                let earliest_write = var_earliest_write.get(var_name.as_str());
                if let Some(&write_idx) = earliest_write {
                    if write_idx > i {
                        // Variable is only written by operations AFTER this one.
                        // At runtime, the condition will be evaluated before
                        // any writes happen — this condition can never be met.
                        let writers: Vec<String> = op_writes
                            .iter()
                            .enumerate()
                            .filter(|(_, w)| w.contains(var_name))
                            .map(|(idx, _)| format!("#{}: {}", idx + 1, project.operations[idx].name))
                            .collect();

                        diagnostics.push(Diagnostic {
                            severity: Severity::Error,
                            code: "CIRCULAR_CONDITION".to_string(),
                            message: format!(
                                "Operation #{}: '{}' reads variable '{}' which is only written by {} — condition can never be satisfied",
                                i + 1,
                                project.operations[i].name,
                                var_name,
                                writers.join(", "),
                            ),
                            entity: Some(format!("op:{}", project.operations[i].name)),
                            action: None,
                        });
                    }
                }
            }
        }
    }

    // ==================================================================
    // Unused variable detection (W7.2)
    // ==================================================================
    //
    // Reports:
    //   - Warning: Variable declared but never referenced in any
    //     operation condition or action condition expression.
    //   - Warning: Variable written via SetVariable but never declared
    //     in project.variables.
    //   - Info: Variable declared + written via SetVariable but never
    //     read in any condition expression.

    fn check_unused_variables(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        // Collect all condition expressions (op-level + ConditionAction).
        let all_condition_exprs: Vec<&str> = project
            .operations
            .iter()
            .flat_map(|op| {
                let exprs: Vec<&str> = op.conditions.iter().map(|s| s.as_str()).collect();
                exprs
            })
            .chain(
                project
                    .operations
                    .iter()
                    .flat_map(|op| {
                        op.actions
                            .iter()
                            .filter_map(|a| match &a.payload {
                                ActionPayload::Condition(c) => Some(c.expression.as_str()),
                                _ => None,
                            })
                    }),
            )
            .collect();

        // Collect all variables written via SetVariable.
        let set_variable_names: HashSet<&str> = project
            .operations
            .iter()
            .flat_map(|op| {
                op.actions
                    .iter()
                    .filter_map(|a| match &a.payload {
                        ActionPayload::SetVariable(sv) => Some(sv.name.as_str()),
                        _ => None,
                    })
            })
            .collect();

        // Collect all declared variable names.
        let declared_names: HashSet<&str> =
            project.variables.iter().map(|v| v.name.as_str()).collect();

        // Find which declared variables are referenced in any condition.
        let mut referenced_in_conditions: HashSet<&str> = HashSet::new();
        for var_name in &declared_names {
            for expr in &all_condition_exprs {
                if expr.contains(var_name) {
                    referenced_in_conditions.insert(*var_name);
                }
            }
        }

        // Check for undeclared variables used in SetVariable
        for op in &project.operations {
            for action in &op.actions {
                if let ActionPayload::SetVariable(sv) = &action.payload {
                    if !declared_names.contains(sv.name.as_str()) {
                        diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "UNDECLARED_VARIABLE".to_string(),
                            message: format!(
                                "SetVariable writes to '{}' which is not declared in project.variables",
                                sv.name
                            ),
                            entity: Some(format!("op:{}", op.name)),
                            action: Some(action.id.to_string()),
                        });
                    }
                }
            }
        }

        // Check declared variables.
        for var_name in &declared_names {
            let referenced = referenced_in_conditions.contains(var_name);
            let written = set_variable_names.contains(var_name);

            if !referenced && !written {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNUSED_VARIABLE".to_string(),
                    message: format!(
                        "Variable '{}' is declared but never set or read in any condition",
                        var_name
                    ),
                    entity: None,
                    action: None,
                });
            } else if written && !referenced {
                diagnostics.push(Diagnostic {
                    severity: Severity::Info,
                    code: "VARIABLE_WRITTEN_BUT_UNREAD".to_string(),
                    message: format!(
                        "Variable '{}' is written via SetVariable but never checked in a condition",
                        var_name
                    ),
                    entity: None,
                    action: None,
                });
            }
        }
    }
}

impl Validator {
    // ==================================================================
    // Missing coordinates
    // ==================================================================

    fn check_missing_coordinates(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        // Check NPC positions in the library.
        for npc in &project.npc_library {
            if Self::is_position_missing(&npc.position) {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "MISSING_COORDS".to_string(),
                    message: format!(
                        "NPC '{}' has missing or zeroed coordinates (map:{}, x:{}, y:{}, z:{})",
                        npc.name,
                        npc.position.map_or(0, |p| p.map),
                        npc.position.map_or(0.0, |p| p.world_x),
                        npc.position.map_or(0.0, |p| p.world_y),
                        npc.position.map_or(0.0, |p| p.world_z),
                    ),
                    entity: Some(npc.name.clone()),
                    action: None,
                });
            }
        }

        // Check action positions.
        for op in &project.operations {
            for action in &op.actions {
                Self::check_action_position(&action.payload, &op.name, action.id, diagnostics);
            }
        }
    }

    fn is_position_missing(pos: &Option<Position>) -> bool {
        match pos {
            None => true,
            Some(p) => {
                // Zeroed-out coordinates are suspicious — they usually mean
                // the position was never filled in properly.
                p.world_x == 0.0 && p.world_y == 0.0 && p.world_z == 0.0
            }
        }
    }

    fn check_action_position(
        payload: &ActionPayload,
        op_name: &str,
        action_id: uuid::Uuid,
        diagnostics: &mut Vec<Diagnostic>,
    ) {
        let position = match payload {
            ActionPayload::Travel(t) => &t.position,
            _ => return,
        };

        if Self::is_position_missing(position) {
            diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "MISSING_COORDS".to_string(),
                message: format!(
                    "Travel action in operation '{}' has missing or zeroed coordinates",
                    op_name,
                ),
                entity: Some(format!("op:{}", op_name)),
                action: Some(action_id.to_string()),
            });
        }
    }

    // ==================================================================
    // Quest chain consistency
    // ==================================================================
    //
    // Detects TurnInQuest actions for quests that were never picked up
    // (no AcceptQuest) in any prior operation.

    fn check_quest_chain_consistency(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        // Collect all quest IDs accepted across all operations (in order).
        let mut accepted_quests: HashSet<u32> = HashSet::new();
        // Track first-encounter order for meaningful messages.
        let mut accept_order: Vec<u32> = Vec::new();

        for op in &project.operations {
            for action in &op.actions {
                if let ActionPayload::AcceptQuest(a) = &action.payload {
                    if accepted_quests.insert(a.quest) {
                        accept_order.push(a.quest);
                    }
                }
            }
        }

        // Now check each TurnInQuest.
        for op in &project.operations {
            for action in &op.actions {
                if let ActionPayload::TurnInQuest(t) = &action.payload {
                    if !accepted_quests.contains(&t.quest) {
                        diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "QUEST_CHAIN_INCONSISTENCY".to_string(),
                            message: format!(
                                "TurnInQuest for quest {} in operation '{}' — \
                                 quest was never picked up (no AcceptQuest) in any operation",
                                t.quest, op.name,
                            ),
                            entity: Some(format!("op:{}", op.name)),
                            action: Some(action.id.to_string()),
                        });
                    }
                }
            }
        }
    }

    // ==================================================================
    // Invalid operation order (prerequisite ordering)
    // ==================================================================
    //
    // Detects when an operation accepts a quest Q, but Q has
    // prerequisites that are only accepted in operations after it.

    fn check_invalid_operation_order(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        // Build a map: quest_id -> quest metadata (for prerequisites).
        let quest_map: HashMap<u32, &QuestReference> = project
            .quest_library
            .iter()
            .map(|q| (q.quest_id, q))
            .collect();

        // Collect AcceptQuest events in order: (operation_index, quest_id).
        let mut accept_events: Vec<(usize, u32)> = Vec::new();
        for (op_idx, op) in project.operations.iter().enumerate() {
            for action in &op.actions {
                if let ActionPayload::AcceptQuest(a) = &action.payload {
                    accept_events.push((op_idx, a.quest));
                }
            }
        }

        // For each AcceptQuest, check if its prerequisites come AFTER it.
        for &(op_idx, quest_id) in &accept_events {
            let prereqs: &[u32] = quest_map
                .get(&quest_id)
                .map(|q| q.prerequisites.as_slice())
                .unwrap_or(&[]);

            if prereqs.is_empty() {
                continue;
            }

            for &prereq_id in prereqs {
                // Find the operation index where the prerequisite is accepted.
                let prereq_op_idx = accept_events
                    .iter()
                    .find(|&&(_, qid)| qid == prereq_id)
                    .map(|&(idx, _)| idx);

                if let Some(prereq_idx) = prereq_op_idx {
                    if prereq_idx > op_idx {
                        diagnostics.push(Diagnostic {
                            severity: Severity::Error,
                            code: "INVALID_OPERATION_ORDER".to_string(),
                            message: format!(
                                "Operation #{} accepts quest {} (prerequisite: {}) \
                                 but prerequisite quest {} is accepted later in operation #{}",
                                op_idx + 1,
                                quest_id,
                                prereq_id,
                                prereq_id,
                                prereq_idx + 1,
                            ),
                            entity: Some(format!(
                                "op:{}",
                                project.operations[op_idx].name
                            )),
                            action: None,
                        });
                    }
                }
            }
        }
    }

    // ==================================================================
    // Unused asset detection
    // ==================================================================
    //
    // Info-level diagnostics for NPCs and quests in the library that are
    // never referenced by any operation.

    fn check_unused_assets(project: &Project, diagnostics: &mut Vec<Diagnostic>) {
        // Collect all NPC UUIDs referenced by operations.
        let mut referenced_npcs: HashSet<uuid::Uuid> = HashSet::new();
        // Collect all quest IDs referenced by operations.
        let mut referenced_quests: HashSet<u32> = HashSet::new();

        for op in &project.operations {
            for action in &op.actions {
                Self::collect_references(&action.payload, &mut referenced_npcs, &mut referenced_quests);
            }
        }

        // Check unused NPCs.
        for npc in &project.npc_library {
            if !referenced_npcs.contains(&npc.id) {
                diagnostics.push(Diagnostic {
                    severity: Severity::Info,
                    code: "UNUSED_ASSET".to_string(),
                    message: format!(
                        "NPC '{}' ({}) in npc_library is never referenced by any operation",
                        npc.name, npc.id,
                    ),
                    entity: Some(npc.name.clone()),
                    action: None,
                });
            }
        }

        // Check unused quests.
        for quest in &project.quest_library {
            if !referenced_quests.contains(&quest.quest_id) {
                diagnostics.push(Diagnostic {
                    severity: Severity::Info,
                    code: "UNUSED_ASSET".to_string(),
                    message: format!(
                        "Quest {} ('{}') in quest_library is never referenced by any operation",
                        quest.quest_id,
                        quest.title.as_deref().unwrap_or("untitled"),
                    ),
                    entity: Some(quest.title.clone().unwrap_or_default()),
                    action: None,
                });
            }
        }
    }

    fn collect_references(
        payload: &ActionPayload,
        npcs: &mut HashSet<uuid::Uuid>,
        quests: &mut HashSet<u32>,
    ) {
        match payload {
            ActionPayload::Vendor(v) => {
                npcs.insert(v.npc);
            }
            ActionPayload::Train(tr) => {
                npcs.insert(tr.npc);
            }
            ActionPayload::Flight(f) => {
                npcs.insert(f.npc);
            }
            ActionPayload::LearnFlightPath(l) => {
                npcs.insert(l.npc);
            }
            ActionPayload::InteractNPC(i) => {
                npcs.insert(i.npc);
            }
            ActionPayload::AcceptQuest(a) => {
                if let Some(npc_id) = a.npc {
                    npcs.insert(npc_id);
                }
                quests.insert(a.quest);
            }
            ActionPayload::TurnInQuest(t) => {
                if let Some(npc_id) = t.npc {
                    npcs.insert(npc_id);
                }
                quests.insert(t.quest);
            }
            ActionPayload::Repair(r) => {
                npcs.insert(r.npc);
            }
            ActionPayload::Mailbox(m) => {
                npcs.insert(m.npc);
            }
            ActionPayload::Bank(b) => {
                npcs.insert(b.npc);
            }
            ActionPayload::Escort(e) => {
                npcs.insert(e.npc);
            }
            ActionPayload::SetHearth(sh) => {
                if let Some(npc_id) = sh.npc {
                    npcs.insert(npc_id);
                }
            }
            ActionPayload::Hearth(h) => {
                if let Some(npc_id) = h.innkeeper {
                    npcs.insert(npc_id);
                }
            }
            _ => {}
        }
    }
}

// ======================================================================
// Tests
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_models::authoring::{
        self, AcceptQuestAction, Action, NPCReference, Position, QuestReference, SetVariableAction,
        TravelAction, TurnInQuestAction, Variable, VariableType, VariableValue, VendorAction,
    };

    fn make_project() -> Project {
        authoring::new_project("test")
    }

    fn make_action(id_hex: &str, payload: ActionPayload) -> Action {
        let hex: String = id_hex
            .chars()
            .chain(std::iter::repeat('0'))
            .take(32)
            .collect();
        Action {
            id: uuid::Uuid::parse_str(&hex).unwrap_or(uuid::Uuid::nil()),
            enabled: true,
            payload,
            condition: None,
            class_restriction: None,
            gate: None,
            note: None,
        }
    }

    // ==============================================================
    // Duplicate NPC tests
    // ==============================================================

    #[test]
    fn detects_duplicate_npc_entry() {
        let mut project = make_project();
        let npc_template = |name: &str, entry: Option<u32>| -> NPCReference {
            NPCReference {
                id: uuid::Uuid::nil(),
                entry,
                guid: None,
                name: name.to_string(),
                faction: None,
                roles: vec![],
                position: None,
                source: None,
                notes: None,
            }
        };
        project.npc_library = vec![
            npc_template("Test1", Some(123)),
            npc_template("Test2", Some(123)),
        ];
        let diags = Validator::validate(&project);
        assert!(diags.iter().any(|d| d.code == "DUPLICATE_NPC"));
    }

    #[test]
    fn no_duplicate_npc_when_entries_differ() {
        let mut project = make_project();
        let npc_template = |name: &str, entry: Option<u32>| -> NPCReference {
            NPCReference {
                id: uuid::Uuid::nil(),
                entry,
                guid: None,
                name: name.to_string(),
                faction: None,
                roles: vec![],
                position: None,
                source: None,
                notes: None,
            }
        };
        project.npc_library = vec![
            npc_template("Test1", Some(123)),
            npc_template("Test2", Some(456)),
        ];
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "DUPLICATE_NPC"));
    }

    // ==============================================================
    // Circular condition tests (W7.1)
    // ==============================================================

    #[test]
    fn no_circular_without_variables() {
        let project = make_project();
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "CIRCULAR_CONDITION"));
    }

    #[test]
    fn no_circular_forward_dependency() {
        let mut project = make_project();
        project
            .variables
            .push(Variable::new("counter", VariableType::Int, VariableValue::Int(0)));
        // op1: writes counter
        // op2: reads counter (written by earlier op1 — fine)
        project.operations = vec![
            authoring::Operation {
                id: uuid::Uuid::nil(),
                name: "op1".to_string(),
                description: None,
                minimum_level: None,
                maximum_level: None,
                enabled: true,
                conditions: vec![],
                sticky: false,
                looping: false,
                labels: vec![],
                requires: vec![],
                complete_with: vec![],
                optional: None,
                gate: None,
                directives: vec![],
                placeholder: false,
                source_line_start: None,
                source_line_end: None,
                actions: vec![make_action(
                    "00000000000000000000000000000001",
                    ActionPayload::SetVariable(SetVariableAction {
                        name: "counter".to_string(),
                        value: VariableValue::Int(1),
                    }),
                )],
                notes: None,
            },
            authoring::Operation {
                id: uuid::Uuid::nil(),
                name: "op2".to_string(),
                description: None,
                minimum_level: None,
                maximum_level: None,
                enabled: true,
                conditions: vec!["counter > 0".to_string()],
                sticky: false,
                looping: false,
                labels: vec![],
                requires: vec![],
                complete_with: vec![],
                optional: None,
                gate: None,
                directives: vec![],
                placeholder: false,
                source_line_start: None,
                source_line_end: None,
                actions: vec![],
                notes: None,
            },
        ];
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "CIRCULAR_CONDITION"));
    }

    #[test]
    fn no_circular_self_ref_is_not_flagged() {
        let mut project = make_project();
        project
            .variables
            .push(Variable::new("counter", VariableType::Int, VariableValue::Int(0)));
        // op1 reads "counter" in condition and also writes it via SetVariable.
        // This is a normal counter pattern — not a cycle.
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec!["counter > 0".to_string()],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "00000000000000000000000000000001",
                ActionPayload::SetVariable(SetVariableAction {
                    name: "counter".to_string(),
                    value: VariableValue::Int(1),
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            !diags.iter().any(|d| d.code == "CIRCULAR_CONDITION"),
            "Self-referencing condition should not be flagged (normal counter pattern)"
        );
    }

    #[test]
    fn detects_circular_backward_dependency() {
        let mut project = make_project();
        project.variables = vec![
            Variable::new("var_a", VariableType::Int, VariableValue::Int(0)),
            Variable::new("var_b", VariableType::Int, VariableValue::Int(0)),
        ];
        // op1: condition reads var_a, writes var_b
        // op2: condition reads var_b, writes var_a
        project.operations = vec![
            authoring::Operation {
                id: uuid::Uuid::nil(),
                name: "op1".to_string(),
                description: None,
                minimum_level: None,
                maximum_level: None,
                enabled: true,
                conditions: vec!["var_a > 0".to_string()],
                sticky: false,
                looping: false,
                labels: vec![],
                requires: vec![],
                complete_with: vec![],
                optional: None,
                gate: None,
                directives: vec![],
                placeholder: false,
                source_line_start: None,
                source_line_end: None,
                actions: vec![make_action(
                    "10000000000000000000000000000001",
                    ActionPayload::SetVariable(SetVariableAction {
                        name: "var_b".to_string(),
                        value: VariableValue::Int(1),
                    }),
                )],
                notes: None,
            },
            authoring::Operation {
                id: uuid::Uuid::nil(),
                name: "op2".to_string(),
                description: None,
                minimum_level: None,
                maximum_level: None,
                enabled: true,
                conditions: vec!["var_b > 5".to_string()],
                sticky: false,
                looping: false,
                labels: vec![],
                requires: vec![],
                complete_with: vec![],
                optional: None,
                gate: None,
                directives: vec![],
                placeholder: false,
                source_line_start: None,
                source_line_end: None,
                actions: vec![make_action(
                    "20000000000000000000000000000001",
                    ActionPayload::SetVariable(SetVariableAction {
                        name: "var_a".to_string(),
                        value: VariableValue::Int(2),
                    }),
                )],
                notes: None,
            },
        ];
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "CIRCULAR_CONDITION"),
            "Expected CIRCULAR_CONDITION diagnostic, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_circular_for_independent_vars() {
        let mut project = make_project();
        project.variables = vec![
            Variable::new("counter1", VariableType::Int, VariableValue::Int(0)),
            Variable::new("counter2", VariableType::Int, VariableValue::Int(0)),
        ];
        project.operations = vec![
            authoring::Operation {
                id: uuid::Uuid::nil(),
                name: "op1".to_string(),
                description: None,
                minimum_level: None,
                maximum_level: None,
                enabled: true,
                conditions: vec!["counter1 < 3".to_string()],
                sticky: false,
                looping: false,
                labels: vec![],
                requires: vec![],
                complete_with: vec![],
                optional: None,
                gate: None,
                directives: vec![],
                placeholder: false,
                source_line_start: None,
                source_line_end: None,
                actions: vec![make_action(
                    "10000000000000000000000000000001",
                    ActionPayload::SetVariable(SetVariableAction {
                        name: "counter1".to_string(),
                        value: VariableValue::Int(1),
                    }),
                )],
                notes: None,
            },
            authoring::Operation {
                id: uuid::Uuid::nil(),
                name: "op2".to_string(),
                description: None,
                minimum_level: None,
                maximum_level: None,
                enabled: true,
                conditions: vec!["counter2 == 0".to_string()],
                sticky: false,
                looping: false,
                labels: vec![],
                requires: vec![],
                complete_with: vec![],
                optional: None,
                gate: None,
                directives: vec![],
                placeholder: false,
                source_line_start: None,
                source_line_end: None,
                actions: vec![make_action(
                    "20000000000000000000000000000001",
                    ActionPayload::SetVariable(SetVariableAction {
                        name: "counter2".to_string(),
                        value: VariableValue::Int(1),
                    }),
                )],
                notes: None,
            },
        ];
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "CIRCULAR_CONDITION"));
    }

    // ==============================================================
    // Unused variable tests (W7.2)
    // ==============================================================

    #[test]
    fn detects_unused_variable() {
        let mut project = make_project();
        project.variables.push(Variable::new(
            "never_used",
            VariableType::Bool,
            VariableValue::Bool(false),
        ));
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "UNUSED_VARIABLE"),
            "Expected UNUSED_VARIABLE diagnostic, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_unused_when_read_in_condition() {
        let mut project = make_project();
        project
            .variables
            .push(Variable::new("my_var", VariableType::Int, VariableValue::Int(0)));
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec!["my_var > 0".to_string()],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "UNUSED_VARIABLE"));
    }

    #[test]
    fn written_but_unread_is_info() {
        let mut project = make_project();
        project
            .variables
            .push(Variable::new("my_var", VariableType::Int, VariableValue::Int(0)));
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::SetVariable(SetVariableAction {
                    name: "my_var".to_string(),
                    value: VariableValue::Int(42),
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "UNUSED_VARIABLE"));
        assert!(
            diags.iter().any(|d| d.code == "VARIABLE_WRITTEN_BUT_UNREAD"),
            "Expected VARIABLE_WRITTEN_BUT_UNREAD, got: {:?}",
            diags
        );
    }

    #[test]
    fn detects_undeclared_variable() {
        let mut project = make_project();
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::SetVariable(SetVariableAction {
                    name: "undeclared_var".to_string(),
                    value: VariableValue::Int(99),
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "UNDECLARED_VARIABLE"),
            "Expected UNDECLARED_VARIABLE, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_unused_diagnostics_for_normal_use() {
        let mut project = make_project();
        project
            .variables
            .push(Variable::new("counter", VariableType::Int, VariableValue::Int(0)));
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec!["counter < 5".to_string()],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::SetVariable(SetVariableAction {
                    name: "counter".to_string(),
                    value: VariableValue::Int(1),
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| {
            let c = d.code.as_str();
            c == "UNUSED_VARIABLE"
                || c == "UNDECLARED_VARIABLE"
                || c == "VARIABLE_WRITTEN_BUT_UNREAD"
        }));
    }

    // ==============================================================
    // Missing coordinates tests
    // ==============================================================

    #[test]
    fn detects_missing_npc_position() {
        let mut project = make_project();
        project.npc_library.push(NPCReference {
            id: uuid::Uuid::nil(),
            entry: Some(100),
            guid: None,
            name: "TestNPC".to_string(),
            faction: None,
            roles: vec![],
            position: None,
            source: None,
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "MISSING_COORDS"),
            "Expected MISSING_COORDS for NPC with no position, got: {:?}",
            diags
        );
    }

    #[test]
    fn detects_zeroed_npc_position() {
        let mut project = make_project();
        project.npc_library.push(NPCReference {
            id: uuid::Uuid::nil(),
            entry: Some(100),
            guid: None,
            name: "TestNPC".to_string(),
            faction: None,
            roles: vec![],
            position: Some(Position::new(0, 0.0, 0.0, 0.0)),
            source: None,
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "MISSING_COORDS"),
            "Expected MISSING_COORDS for NPC with zeroed position, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_missing_coords_for_valid_position() {
        let mut project = make_project();
        project.npc_library.push(NPCReference {
            id: uuid::Uuid::nil(),
            entry: Some(100),
            guid: None,
            name: "TestNPC".to_string(),
            faction: None,
            roles: vec![],
            position: Some(Position::new(1, -8345.0, 610.0, 94.0)),
            source: None,
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "MISSING_COORDS"));
    }

    #[test]
    fn detects_missing_travel_position() {
        let mut project = make_project();
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::Travel(TravelAction {
                    destination: "Somewhere".to_string(),
                    position: None,
                    tolerance: 5.0,
                    authored_radius: None,
                    mount: None,
                    allow_flight: false,
                    timeout: None,
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "MISSING_COORDS"),
            "Expected MISSING_COORDS for Travel with no position, got: {:?}",
            diags
        );
    }

    // ==============================================================
    // Quest chain consistency tests
    // ==============================================================

    #[test]
    fn detects_turnin_without_accept() {
        let mut project = make_project();
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: 42,
                    npc: None,
                    choose_reward: None,
                    optional: false,
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "QUEST_CHAIN_INCONSISTENCY"),
            "Expected QUEST_CHAIN_INCONSISTENCY, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_chain_inconsistency_when_accept_exists() {
        let mut project = make_project();
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::AcceptQuest(AcceptQuestAction {
                    quest: 42,
                    npc: None,
                    auto_complete_dialog: false,
                    optional: false,
                }),
            )],
            notes: None,
        });
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op2".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "20000000000000000000000000000001",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: 42,
                    npc: None,
                    choose_reward: None,
                    optional: false,
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "QUEST_CHAIN_INCONSISTENCY"));
    }

    // ==============================================================
    // Invalid operation order tests
    // ==============================================================

    #[test]
    fn detects_prerequisite_accepted_later() {
        let mut project = make_project();
        // Quest 200 has prerequisite 100.
        project.quest_library.push(QuestReference {
            id: uuid::Uuid::nil(),
            quest_id: 200,
            title: Some("Quest B".to_string()),
            level: None,
            minimum_level: None,
            suggested_group: None,
            giver_npc: None,
            finisher_npc: None,
            chain: None,
            prerequisites: vec![100],
            exclusive_with: vec![],
            repeatable: false,
            source: None,
        });
        project.quest_library.push(QuestReference {
            id: uuid::Uuid::nil(),
            quest_id: 100,
            title: Some("Quest A".to_string()),
            level: None,
            minimum_level: None,
            suggested_group: None,
            giver_npc: None,
            finisher_npc: None,
            chain: None,
            prerequisites: vec![],
            exclusive_with: vec![],
            repeatable: false,
            source: None,
        });
        // Accept quest 200 BEFORE quest 100 — wrong order.
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::AcceptQuest(AcceptQuestAction {
                    quest: 200,
                    npc: None,
                    auto_complete_dialog: false,
                    optional: false,
                }),
            )],
            notes: None,
        });
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op2".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "20000000000000000000000000000001",
                ActionPayload::AcceptQuest(AcceptQuestAction {
                    quest: 100,
                    npc: None,
                    auto_complete_dialog: false,
                    optional: false,
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "INVALID_OPERATION_ORDER"),
            "Expected INVALID_OPERATION_ORDER, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_order_issue_when_prerequisite_comes_first() {
        let mut project = make_project();
        project.quest_library.push(QuestReference {
            id: uuid::Uuid::nil(),
            quest_id: 200,
            title: Some("Quest B".to_string()),
            level: None,
            minimum_level: None,
            suggested_group: None,
            giver_npc: None,
            finisher_npc: None,
            chain: None,
            prerequisites: vec![100],
            exclusive_with: vec![],
            repeatable: false,
            source: None,
        });
        // Accept quest 100 BEFORE quest 200 — correct order.
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::AcceptQuest(AcceptQuestAction {
                    quest: 100,
                    npc: None,
                    auto_complete_dialog: false,
                    optional: false,
                }),
            )],
            notes: None,
        });
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op2".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "20000000000000000000000000000001",
                ActionPayload::AcceptQuest(AcceptQuestAction {
                    quest: 200,
                    npc: None,
                    auto_complete_dialog: false,
                    optional: false,
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "INVALID_OPERATION_ORDER"));
    }

    // ==============================================================
    // Unused asset tests
    // ==============================================================

    #[test]
    fn detects_unused_npc() {
        let mut project = make_project();
        project.npc_library.push(NPCReference {
            id: uuid::Uuid::nil(),
            entry: Some(100),
            guid: None,
            name: "UnusedNPC".to_string(),
            faction: None,
            roles: vec![],
            position: None,
            source: None,
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(
            diags.iter().any(|d| d.code == "UNUSED_ASSET"),
            "Expected UNUSED_ASSET for unused NPC, got: {:?}",
            diags
        );
    }

    #[test]
    fn no_unused_asset_for_referenced_npc() {
        let mut project = make_project();
        let npc_id = uuid::Uuid::nil();
        project.npc_library.push(NPCReference {
            id: npc_id,
            entry: Some(100),
            guid: None,
            name: "UsedNPC".to_string(),
            faction: None,
            roles: vec![],
            position: None,
            source: None,
            notes: None,
        });
        project.operations.push(authoring::Operation {
            id: uuid::Uuid::nil(),
            name: "op1".to_string(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: vec![],
            sticky: false,
            looping: false,
            labels: vec![],
            requires: vec![],
            complete_with: vec![],
            optional: None,
            gate: None,
            directives: vec![],
            placeholder: false,
            source_line_start: None,
            source_line_end: None,
            actions: vec![make_action(
                "10000000000000000000000000000001",
                ActionPayload::Vendor(VendorAction {
                    npc: npc_id,
                    sell_grey: false,
                    repair: false,
                    buy_items: vec![],
                    minimum_free_slots: None,
                }),
            )],
            notes: None,
        });
        let diags = Validator::validate(&project);
        assert!(!diags.iter().any(|d| d.code == "UNUSED_ASSET"));
    }
}
