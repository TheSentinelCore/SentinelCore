//! Command-pattern undo/redo history for the questing editor.
//!
//! Each editor mutation is wrapped in an `EditorCommand` that stores enough
//! information to reverse itself. `CommandHistory` manages the undo/redo stacks
//! and enforces the history depth limit.

use sentinel_models::authoring::{Action, Operation, Project};

// ---------------------------------------------------------------------------
// Trait
// ---------------------------------------------------------------------------

/// A single reversible mutation on a `Project`.
pub trait EditorCommand: Send + Sync {
    /// Apply the forward mutation.
    fn apply(&self, project: &mut Project) -> Result<(), String>;

    /// Return a command that reverses this one.
    fn inverse(&self) -> Box<dyn EditorCommand>;

    /// Human-readable label, e.g. "Add Operation 'Kill Wolves'".
    fn description(&self) -> String;
}

// ---------------------------------------------------------------------------
// Operation-level commands
// ---------------------------------------------------------------------------

pub struct AddOperation {
    pub index: usize,
    pub operation: Operation,
}

impl EditorCommand for AddOperation {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        let idx = self.index;
        if idx > project.operations.len() {
            return Err(format!(
                "Cannot add operation at index {} (len = {})",
                idx,
                project.operations.len()
            ));
        }
        project.operations.insert(idx, self.operation.clone());
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        Box::new(RemoveOperation {
            index: self.index,
            operation: self.operation.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Add Operation '{}'", self.operation.name)
    }
}

pub struct RemoveOperation {
    pub index: usize,
    pub operation: Operation,
}

impl EditorCommand for RemoveOperation {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        if self.index >= project.operations.len() {
            return Err(format!(
                "Cannot remove operation at index {} (len = {})",
                self.index,
                project.operations.len()
            ));
        }
        project.operations.remove(self.index);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        Box::new(AddOperation {
            index: self.index,
            operation: self.operation.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Remove Operation '{}'", self.operation.name)
    }
}

pub struct ModifyOperation {
    pub index: usize,
    pub old_op: Operation,
    pub new_op: Operation,
}

impl EditorCommand for ModifyOperation {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        if self.index >= project.operations.len() {
            return Err(format!(
                "Cannot modify operation at index {} (len = {})",
                self.index,
                project.operations.len()
            ));
        }
        project.operations[self.index] = self.new_op.clone();
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        Box::new(ModifyOperation {
            index: self.index,
            old_op: self.new_op.clone(),
            new_op: self.old_op.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Modify Operation '{}'", self.new_op.name)
    }
}

pub struct MoveOperation {
    pub from: usize,
    pub to: usize,
}

impl EditorCommand for MoveOperation {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        let len = project.operations.len();
        if self.from >= len || self.to >= len {
            return Err(format!(
                "Cannot move operation from {} to {} (len = {})",
                self.from, self.to, len
            ));
        }
        let op = project.operations.remove(self.from);
        project.operations.insert(self.to, op);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        // Reverse: swap from and to
        Box::new(MoveOperation {
            from: self.to,
            to: self.from,
        })
    }

    fn description(&self) -> String {
        format!("Move Operation {} → {}", self.from, self.to)
    }
}

// ---------------------------------------------------------------------------
// Action-level commands
// ---------------------------------------------------------------------------

pub struct AddAction {
    pub op_index: usize,
    pub action: Action,
}

impl EditorCommand for AddAction {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        if self.op_index >= project.operations.len() {
            return Err(format!(
                "Cannot add action: operation index {} out of range (len = {})",
                self.op_index,
                project.operations.len()
            ));
        }
        project.operations[self.op_index].actions.push(self.action.clone());
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        let action_idx = usize::MAX; // actual index resolved at undo time via RemoveAction
        Box::new(RemoveAction {
            op_index: self.op_index,
            index: action_idx,
            action: self.action.clone(),
        })
    }

    fn description(&self) -> String {
        format!(
            "Add Action to Operation {}",
            self.op_index
        )
    }
}

pub struct RemoveAction {
    pub op_index: usize,
    pub index: usize,
    pub action: Action,
}

impl EditorCommand for RemoveAction {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        if self.op_index >= project.operations.len() {
            return Err(format!(
                "Cannot remove action: operation index {} out of range (len = {})",
                self.op_index,
                project.operations.len()
            ));
        }
        let actions = &mut project.operations[self.op_index].actions;
        let idx = if self.index == usize::MAX {
            actions.len().saturating_sub(1)
        } else {
            self.index
        };
        if idx >= actions.len() {
            return Err(format!(
                "Cannot remove action at index {} (len = {})",
                idx,
                actions.len()
            ));
        }
        actions.remove(idx);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        Box::new(AddAction {
            op_index: self.op_index,
            action: self.action.clone(),
        })
    }

    fn description(&self) -> String {
        format!(
            "Remove Action from Operation {}",
            self.op_index
        )
    }
}

pub struct ModifyAction {
    pub op_index: usize,
    pub action_index: usize,
    pub old_action: Action,
    pub new_action: Action,
}

impl EditorCommand for ModifyAction {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        if self.op_index >= project.operations.len() {
            return Err(format!(
                "Cannot modify action: operation index {} out of range",
                self.op_index
            ));
        }
        let actions = &mut project.operations[self.op_index].actions;
        if self.action_index >= actions.len() {
            return Err(format!(
                "Cannot modify action at index {} (len = {})",
                self.action_index,
                actions.len()
            ));
        }
        actions[self.action_index] = self.new_action.clone();
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        Box::new(ModifyAction {
            op_index: self.op_index,
            action_index: self.action_index,
            old_action: self.new_action.clone(),
            new_action: self.old_action.clone(),
        })
    }

    fn description(&self) -> String {
        format!(
            "Modify Action {} in Operation {}",
            self.action_index, self.op_index
        )
    }
}

// ---------------------------------------------------------------------------
// Metadata commands
// ---------------------------------------------------------------------------

pub struct ModifyProjectMeta {
    pub old_name: String,
    pub new_name: String,
}

impl EditorCommand for ModifyProjectMeta {
    fn apply(&self, project: &mut Project) -> Result<(), String> {
        project.metadata.name = self.new_name.clone();
        Ok(())
    }

    fn inverse(&self) -> Box<dyn EditorCommand> {
        Box::new(ModifyProjectMeta {
            old_name: self.new_name.clone(),
            new_name: self.old_name.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Rename project '{}' → '{}'", self.old_name, self.new_name)
    }
}

// ---------------------------------------------------------------------------
// Command History
// ---------------------------------------------------------------------------

pub struct CommandHistory {
    undo_stack: Vec<Box<dyn EditorCommand>>,
    redo_stack: Vec<Box<dyn EditorCommand>>,
    max_history: usize,
}

impl Clone for CommandHistory {
    fn clone(&self) -> Self {
        // Cannot clone Box<dyn EditorCommand>, so create an empty history.
        // The clone is only used for AppState which is shared via Arc<RwLock<>>,
        // so this shouldn't be called in practice.
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history: self.max_history,
        }
    }
}

impl Default for CommandHistory {
    fn default() -> Self {
        Self::new()
    }
}

impl CommandHistory {
    pub fn new() -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history: 50,
        }
    }

    pub fn with_max(max_history: usize) -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history,
        }
    }

    /// Execute a command: apply it, push to undo stack, clear redo stack.
    pub fn execute(&mut self, cmd: Box<dyn EditorCommand>, project: &mut Project) -> Result<(), String> {
        cmd.apply(project)?;
        self.undo_stack.push(cmd);
        self.redo_stack.clear();

        // Enforce max_history limit (0 = unlimited)
        if self.max_history > 0 && self.undo_stack.len() > self.max_history {
            self.undo_stack.remove(0);
        }

        Ok(())
    }

    /// Undo the most recent command.
    pub fn undo(&mut self, project: &mut Project) -> Result<String, String> {
        let cmd = self.undo_stack.pop().ok_or_else(|| "Nothing to undo".to_string())?;
        let desc = cmd.description();
        let inverse = cmd.inverse();
        inverse.apply(project)?;
        self.redo_stack.push(cmd);
        Ok(desc)
    }

    /// Redo the most recently undone command.
    pub fn redo(&mut self, project: &mut Project) -> Result<String, String> {
        let cmd = self.redo_stack.pop().ok_or_else(|| "Nothing to redo".to_string())?;
        let desc = cmd.description();
        cmd.apply(project)?;
        self.undo_stack.push(cmd);
        Ok(desc)
    }

    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    pub fn undo_description(&self) -> Option<String> {
        self.undo_stack.last().map(|cmd| cmd.description())
    }

    pub fn redo_description(&self) -> Option<String> {
        self.redo_stack.last().map(|cmd| cmd.description())
    }

    pub fn clear(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_models::authoring::new_project;

    fn make_op(name: &str) -> Operation {
        Operation::new(name)
    }

    fn make_action() -> Action {
        Action {
            id: uuid::Uuid::new_v4(),
            enabled: true,
            condition: None,
            class_restriction: None,
            gate: None,
            note: None,
            payload: sentinel_models::authoring::ActionPayload::Comment(
                sentinel_models::authoring::CommentAction {
                    text: "test".to_string(),
                },
            ),
        }
    }

    /// Helper: assert that a project has exactly the given operation names, in order.
    fn assert_op_names(project: &Project, expected: &[&str]) {
        let names: Vec<&str> = project.operations.iter().map(|o| o.name.as_str()).collect();
        assert_eq!(names, expected);
    }

    // ---- Add / Undo / Redo cycle ---------------------------------------

    #[test]
    fn add_operation_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        let op = make_op("FirstOp");
        history
            .execute(
                Box::new(AddOperation {
                    index: 0,
                    operation: op,
                }),
                &mut project,
            )
            .unwrap();
        assert_op_names(&project, &["FirstOp"]);
        assert!(history.can_undo());
        assert!(!history.can_redo());

        // Undo
        let desc = history.undo(&mut project).unwrap();
        assert!(desc.contains("FirstOp"));
        assert_op_names(&project, &[]);
        assert!(!history.can_undo());
        assert!(history.can_redo());

        // Redo
        let desc = history.redo(&mut project).unwrap();
        assert!(desc.contains("FirstOp"));
        assert_op_names(&project, &["FirstOp"]);
        assert!(history.can_undo());
        assert!(!history.can_redo());
    }

    #[test]
    fn add_two_operations_undo_both() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation {
                    index: 0,
                    operation: make_op("A"),
                }),
                &mut project,
            )
            .unwrap();
        history
            .execute(
                Box::new(AddOperation {
                    index: 1,
                    operation: make_op("B"),
                }),
                &mut project,
            )
            .unwrap();
        assert_op_names(&project, &["A", "B"]);

        history.undo(&mut project).unwrap();
        assert_op_names(&project, &["A"]);

        history.undo(&mut project).unwrap();
        assert_op_names(&project, &[]);
        assert!(!history.can_undo());
    }

    #[test]
    fn remove_operation_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        // Add two ops
        let op_a = make_op("A");
        let op_b = make_op("B");
        history
            .execute(Box::new(AddOperation { index: 0, operation: op_a }), &mut project)
            .unwrap();
        history
            .execute(Box::new(AddOperation { index: 1, operation: op_b }), &mut project)
            .unwrap();

        // Remove the first
        let removed = project.operations[0].clone();
        history
            .execute(
                Box::new(RemoveOperation {
                    index: 0,
                    operation: removed,
                }),
                &mut project,
            )
            .unwrap();
        assert_op_names(&project, &["B"]);

        // Undo remove
        history.undo(&mut project).unwrap();
        assert_op_names(&project, &["A", "B"]);

        // Redo remove
        history.redo(&mut project).unwrap();
        assert_op_names(&project, &["B"]);
    }

    #[test]
    fn modify_operation_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        let original = make_op("Original");
        history
            .execute(
                Box::new(AddOperation {
                    index: 0,
                    operation: original,
                }),
                &mut project,
            )
            .unwrap();

        // Modify
        let old = project.operations[0].clone();
        let mut new = old.clone();
        new.name = "Modified".to_string();

        history
            .execute(
                Box::new(ModifyOperation {
                    index: 0,
                    old_op: old,
                    new_op: new,
                }),
                &mut project,
            )
            .unwrap();
        assert_op_names(&project, &["Modified"]);

        // Undo modify
        history.undo(&mut project).unwrap();
        assert_op_names(&project, &["Original"]);

        // Redo modify
        history.redo(&mut project).unwrap();
        assert_op_names(&project, &["Modified"]);
    }

    #[test]
    fn move_operation_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("A") }),
                &mut project,
            )
            .unwrap();
        history
            .execute(
                Box::new(AddOperation { index: 1, operation: make_op("B") }),
                &mut project,
            )
            .unwrap();
        history
            .execute(
                Box::new(AddOperation { index: 2, operation: make_op("C") }),
                &mut project,
            )
            .unwrap();
        assert_op_names(&project, &["A", "B", "C"]);

        // Move B from index 1 → 0
        history
            .execute(Box::new(MoveOperation { from: 1, to: 0 }), &mut project)
            .unwrap();
        assert_op_names(&project, &["B", "A", "C"]);

        // Undo
        history.undo(&mut project).unwrap();
        assert_op_names(&project, &["A", "B", "C"]);

        // Redo
        history.redo(&mut project).unwrap();
        assert_op_names(&project, &["B", "A", "C"]);
    }

    #[test]
    fn new_command_clears_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("A") }),
                &mut project,
            )
            .unwrap();
        history.undo(&mut project).unwrap();
        assert!(history.can_redo());

        // New command after undo should clear redo
        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("B") }),
                &mut project,
            )
            .unwrap();
        assert!(!history.can_redo());
        assert_op_names(&project, &["B"]);
    }

    #[test]
    fn max_history_limit() {
        let mut project = new_project("test");
        let mut history = CommandHistory::with_max(3);

        for i in 0..5 {
            history
                .execute(
                    Box::new(AddOperation {
                        index: project.operations.len(),
                        operation: make_op(&format!("Op{}", i)),
                    }),
                    &mut project,
                )
                .unwrap();
        }

        // Only the last 3 should be in undo stack
        assert_eq!(history.undo_stack.len(), 3);

        // Undo all 3 should work, 4th should fail
        assert!(history.undo(&mut project).is_ok());
        assert!(history.undo(&mut project).is_ok());
        assert!(history.undo(&mut project).is_ok());
        assert!(history.undo(&mut project).is_err());
    }

    #[test]
    fn unlimited_history() {
        let mut project = new_project("test");
        let mut history = CommandHistory::with_max(0);

        for i in 0..100 {
            history
                .execute(
                    Box::new(AddOperation {
                        index: project.operations.len(),
                        operation: make_op(&format!("Op{}", i)),
                    }),
                    &mut project,
                )
                .unwrap();
        }

        assert_eq!(history.undo_stack.len(), 100);

        // Undo 50
        for _ in 0..50 {
            history.undo(&mut project).unwrap();
        }
        // Should have 50 in undo, 50 in redo
        assert_eq!(history.undo_stack.len(), 50);
        assert_eq!(history.redo_stack.len(), 50);
    }

    // ---- Action commands -----------------------------------------------

    #[test]
    fn add_action_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("Op") }),
                &mut project,
            )
            .unwrap();

        let action = make_action();
        history
            .execute(Box::new(AddAction { op_index: 0, action }), &mut project)
            .unwrap();
        assert_eq!(project.operations[0].actions.len(), 1);

        // Undo
        history.undo(&mut project).unwrap();
        assert_eq!(project.operations[0].actions.len(), 0);

        // Redo
        history.redo(&mut project).unwrap();
        assert_eq!(project.operations[0].actions.len(), 1);
    }

    #[test]
    fn remove_action_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("Op") }),
                &mut project,
            )
            .unwrap();

        let action = make_action();
        history
            .execute(Box::new(AddAction { op_index: 0, action }), &mut project)
            .unwrap();

        let removed = project.operations[0].actions[0].clone();
        history
            .execute(
                Box::new(RemoveAction {
                    op_index: 0,
                    index: usize::MAX,
                    action: removed,
                }),
                &mut project,
            )
            .unwrap();
        assert_eq!(project.operations[0].actions.len(), 0);

        history.undo(&mut project).unwrap();
        assert_eq!(project.operations[0].actions.len(), 1);

        history.redo(&mut project).unwrap();
        assert_eq!(project.operations[0].actions.len(), 0);
    }

    #[test]
    fn modify_action_undo_redo() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("Op") }),
                &mut project,
            )
            .unwrap();

        let action = make_action();
        history
            .execute(Box::new(AddAction { op_index: 0, action }), &mut project)
            .unwrap();

        let old = project.operations[0].actions[0].clone();
        let mut new_action = old.clone();
        new_action.enabled = false;

        history
            .execute(
                Box::new(ModifyAction {
                    op_index: 0,
                    action_index: 0,
                    old_action: old,
                    new_action,
                }),
                &mut project,
            )
            .unwrap();
        assert!(!project.operations[0].actions[0].enabled);

        history.undo(&mut project).unwrap();
        assert!(project.operations[0].actions[0].enabled);

        history.redo(&mut project).unwrap();
        assert!(!project.operations[0].actions[0].enabled);
    }

    #[test]
    fn can_undo_redo_descriptions() {
        let mut history = CommandHistory::new();
        assert!(!history.can_undo());
        assert!(!history.can_redo());
        assert!(history.undo_description().is_none());
        assert!(history.redo_description().is_none());

        let mut project = new_project("test");
        let op = make_op("TestOp");
        history
            .execute(Box::new(AddOperation { index: 0, operation: op }), &mut project)
            .unwrap();

        assert!(history.can_undo());
        let desc = history.undo_description().unwrap();
        assert!(desc.contains("TestOp"));

        history.undo(&mut project).unwrap();
        assert!(!history.can_undo());
        assert!(history.can_redo());
        let desc = history.redo_description().unwrap();
        assert!(desc.contains("TestOp"));
    }

    #[test]
    fn clear_history() {
        let mut project = new_project("test");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("A") }),
                &mut project,
            )
            .unwrap();
        history
            .execute(
                Box::new(AddOperation { index: 0, operation: make_op("B") }),
                &mut project,
            )
            .unwrap();
        assert!(history.can_undo());

        history.clear();
        assert!(!history.can_undo());
        assert!(!history.can_redo());
    }

    #[test]
    fn modify_project_meta_undo_redo() {
        let mut project = new_project("original");
        let mut history = CommandHistory::new();

        history
            .execute(
                Box::new(ModifyProjectMeta {
                    old_name: "original".to_string(),
                    new_name: "renamed".to_string(),
                }),
                &mut project,
            )
            .unwrap();
        assert_eq!(project.metadata.name, "renamed");

        history.undo(&mut project).unwrap();
        assert_eq!(project.metadata.name, "original");

        history.redo(&mut project).unwrap();
        assert_eq!(project.metadata.name, "renamed");
    }
}
