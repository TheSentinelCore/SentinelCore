//! RuntimeOperation — a compiled, resolved operation (ADR `05` Part 2).
//!
//! Mirrors the authoring `Operation` but with typed entry/exit conditions and fully-resolved
//! `RuntimeAction`s. IDs in `actions` are sequential execution indices, not library references.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{action::RuntimeAction, condition::RuntimeCondition};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeOperation {
    pub id: Uuid,
    pub name: String,
    #[serde(default)]
    pub entry_conditions: Vec<RuntimeCondition>,
    #[serde(default)]
    pub exit_conditions: Vec<RuntimeCondition>,
    pub actions: Vec<RuntimeAction>,
}

impl RuntimeOperation {
    pub fn new(id: Uuid, name: impl Into<String>, actions: Vec<RuntimeAction>) -> Self {
        Self {
            id,
            name: name.into(),
            entry_conditions: Vec::new(),
            exit_conditions: Vec::new(),
            actions,
        }
    }
}
