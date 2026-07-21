//! RuntimeProfile — the top-level compiled, deterministic execution artifact (ADR `05` Part 2).
//!
//! Compact JSON. Contains everything the Lua runtime needs: resolved NPCs, quests, areas,
//! variables, and the ordered operations of runtime actions. No unresolved references, no
//! editor/compiler metadata, no diagnostics.

use serde::{Deserialize, Serialize};

use super::{
    area::RuntimeArea, npc::RuntimeNpc, operation::RuntimeOperation, quest::RuntimeQuest,
    variable::RuntimeVariable,
};
use crate::authoring::Faction;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeProfile {
    pub schema_version: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    /// Game version, e.g. `"2.4.3"`.
    #[serde(default = "default_game_version")]
    pub game: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub faction: Option<Faction>,
    pub operations: Vec<RuntimeOperation>,
    #[serde(default)]
    pub variables: Vec<RuntimeVariable>,
    #[serde(default)]
    pub areas: Vec<RuntimeArea>,
    #[serde(default)]
    pub npcs: Vec<RuntimeNpc>,
    #[serde(default)]
    pub quests: Vec<RuntimeQuest>,
    /// Content fingerprint — deterministic hash of operations for save/load matching.
    /// Computed during compilation. Lua runtime uses this to verify save file compatibility.
    #[serde(default)]
    pub content_hash: String,
}

fn default_game_version() -> String {
    "2.4.3".to_string()
}

impl RuntimeProfile {
    pub fn new(name: impl Into<String>, operations: Vec<RuntimeOperation>) -> Self {
        Self {
            schema_version: "1.0.0".to_string(),
            name: name.into(),
            description: String::new(),
            game: default_game_version(),
            faction: None,
            operations,
            variables: Vec::new(),
            areas: Vec::new(),
            npcs: Vec::new(),
            quests: Vec::new(),
            content_hash: String::new(),
        }
    }
}

/// Convenience: count total runtime actions across all operations.
impl RuntimeProfile {
    pub fn total_actions(&self) -> usize {
        self.operations.iter().map(|o| o.actions.len()).sum()
    }
}

/// Compute a deterministic content fingerprint for a RuntimeProfile.
/// Used by the Lua runtime to verify save file compatibility across compilations.
///
/// The hash is computed from the operations only (not metadata like name/description),
/// so that renamed profiles still match their save files.
pub fn compute_content_hash(profile: &RuntimeProfile) -> String {
    // Serialize operations to canonical JSON for deterministic input
    let ops_json = serde_json::to_string(&profile.operations).unwrap_or_default();
    // Simple polynomial hash (deterministic, no random seed)
    let mut h: u64 = 0;
    for b in ops_json.bytes() {
        h = h.wrapping_mul(31).wrapping_add(b as u64);
    }
    format!("{:016x}", h)
}
