//! Operations — the primary authoring unit (ADR `02_DATA_MODEL` §11, ADR-007).
//!
//! Operations mirror how humans think about leveling ("Northshire", "Goldshire") rather than
//! individual guide steps. Each operation owns an ordered list of [`Action`]s.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::action::Action;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Operation {
    pub id: Uuid,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_level: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maximum_level: Option<u8>,
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Gate expressions evaluated before the operation is entered.
    #[serde(default)]
    pub conditions: Vec<String>,
    /// `#sticky` directive (IF4): the operation should be revisited rather than treated as
    /// one-shot.
    #[serde(default)]
    pub sticky: bool,
    /// `#loop` directive (IF4): the operation should repeat rather than advance linearly.
    #[serde(default)]
    pub looping: bool,
    pub actions: Vec<Action>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

fn default_true() -> bool {
    true
}

impl Operation {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            description: None,
            minimum_level: None,
            maximum_level: None,
            enabled: true,
            conditions: Vec::new(),
            sticky: false,
            looping: false,
            actions: Vec::new(),
            notes: None,
        }
    }
}
