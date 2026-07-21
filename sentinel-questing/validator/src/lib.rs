//! Sentinel Questing — Project Validator (Phase 5).
//!
//! Validates Projects for:
//! - Duplicate NPC entries
//! - Duplicate quest entries
//! - Missing NPC references (broken UUIDs in actions)
//! - Unresolved quest references
//! - Circular condition dependencies
//! - Unused variables
//! - Broken references

use std::collections::HashSet;

use sentinel_models::authoring::{ActionPayload, Diagnostic, Project, Severity};

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

// ======================================================================
// Tests
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_models::authoring::{
        self, Action, NPCReference, SetVariableAction, Variable, VariableType, VariableValue,
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
}
