//! Quest library — referenced by ID (ADR `02_DATA_MODEL` §9, ADR-202).
//!
//! Objectives intentionally live on actions, not here (ADR `02_DATA_MODEL` §9 note).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestReference {
    pub id: Uuid,
    pub quest_id: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub level: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_level: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub suggested_group: Option<u8>,
    /// [`Uuid`] of the giver NPC in `npc_library`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub giver_npc: Option<Uuid>,
    /// [`Uuid`] of the finisher NPC in `npc_library`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub finisher_npc: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chain: Option<String>,
    #[serde(default)]
    pub prerequisites: Vec<u32>,
    #[serde(default)]
    pub exclusive_with: Vec<u32>,
    #[serde(default)]
    pub repeatable: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

impl QuestReference {
    pub fn new(quest_id: u32) -> Self {
        Self {
            id: Uuid::new_v4(),
            quest_id,
            title: None,
            level: None,
            minimum_level: None,
            suggested_group: None,
            giver_npc: None,
            finisher_npc: None,
            chain: None,
            prerequisites: Vec::new(),
            exclusive_with: Vec::new(),
            repeatable: false,
            source: None,
        }
    }
}
