//! Resolved quest embedded directly in the runtime profile.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeQuest {
    pub id: u32,
    pub title: String,
}

impl RuntimeQuest {
    pub fn new(id: u32, title: impl Into<String>) -> Self {
        Self {
            id,
            title: title.into(),
        }
    }
}
