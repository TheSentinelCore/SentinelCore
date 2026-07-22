//! NPC library — referenced by ID, never duplicated (ADR `02_DATA_MODEL` §8, ADR-202).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{enums::Faction, enums::NpcRole, position::Position};

/// An NPC that may fill several roles. Stored once in the project's `npc_library` and
/// referenced by [`Uuid`] from actions and quests.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NPCReference {
    pub id: Uuid,
    /// Game creature entry; `None` when only a name hint is known pre-resolution.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub entry: Option<u32>,
    /// Instance GUID when captured in-game; optional.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub guid: Option<u64>,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub faction: Option<Faction>,
    #[serde(default)]
    pub roles: Vec<NpcRole>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position: Option<Position>,
    /// Where this reference originated (e.g. `"RestedXP"` or `"capture"`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

impl NPCReference {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            entry: None,
            guid: None,
            name: name.into(),
            faction: None,
            roles: Vec::new(),
            position: None,
            source: None,
            notes: None,
        }
    }
}

/// Helper alias kept for callers that want to talk about the role set explicitly.
pub type NpcRoleSet = std::collections::BTreeSet<NpcRole>;
