//! Object (GameObject) library (ADR `02_DATA_MODEL` §10, ADR-202).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::position::Position;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GameObjectReference {
    pub id: Uuid,
    pub entry: u32,
    pub name: String,
    pub position: Position,
    /// Free-form type tag, e.g. `"Chest"`, `"Mailbox"`, `"MiningNode"`, `"QuestObject"`.
    pub type_: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

impl GameObjectReference {
    pub fn new(
        entry: u32,
        name: impl Into<String>,
        position: Position,
        type_: impl Into<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            entry,
            name: name.into(),
            position,
            type_: type_.into(),
            source: None,
        }
    }
}
