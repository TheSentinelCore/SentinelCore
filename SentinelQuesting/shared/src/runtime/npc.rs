//! Resolved NPC embedded directly in the runtime profile (no library reference).

use serde::{Deserialize, Serialize};

use crate::authoring::Position;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeNpc {
    pub entry: u32,
    pub name: String,
    pub position: Position,
    #[serde(default)]
    pub roles: Vec<String>,
}

impl RuntimeNpc {
    pub fn new(entry: u32, name: impl Into<String>, position: Position) -> Self {
        Self {
            entry,
            name: name.into(),
            position,
            roles: Vec::new(),
        }
    }
}
