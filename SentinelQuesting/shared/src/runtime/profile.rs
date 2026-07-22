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

// ======================================================================
// Tests (W8.3 — Profile hash stability)
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::RuntimeOperation;

    fn sample_op(name: &str) -> RuntimeOperation {
        RuntimeOperation {
            id: uuid::Uuid::nil(),
            name: name.to_string(),
            entry_conditions: Vec::new(),
            exit_conditions: Vec::new(),
            actions: Vec::new(),
        }
    }

    /// Verifies that identical profiles produce the same hash.
    #[test]
    fn deterministic_hash_identical() {
        let ops = vec![sample_op("op1"), sample_op("op2")];
        let p1 = RuntimeProfile::new("a".to_string(), ops.clone());
        let p2 = RuntimeProfile::new("b".to_string(), ops.clone());
        // Different profile names but same operations → same hash
        assert_eq!(
            compute_content_hash(&p1),
            compute_content_hash(&p2),
            "Hash must depend on operations only, not metadata"
        );
    }

    /// Verifies that different operations produce different hashes.
    #[test]
    fn different_ops_different_hash() {
        let ops_a = vec![sample_op("alpha")];
        let ops_b = vec![sample_op("beta")];
        let p1 = RuntimeProfile::new("x".to_string(), ops_a);
        let p2 = RuntimeProfile::new("x".to_string(), ops_b);
        assert_ne!(
            compute_content_hash(&p1),
            compute_content_hash(&p2),
            "Different ops must produce different hashes"
        );
    }

    /// Verifies the hash is deterministic (same input → same output, always).
    #[test]
    fn hash_is_deterministic() {
        let ops = vec![sample_op("deterministic")];
        let profile = RuntimeProfile::new("test".to_string(), ops);
        // Run twice, expect same result
        let hash1 = compute_content_hash(&profile);
        let hash2 = compute_content_hash(&profile);
        assert_eq!(hash1, hash2);
    }

    /// Verifies the hash is non-empty and hex-formatted.
    #[test]
    fn hash_format() {
        let ops = vec![sample_op("format-test")];
        let profile = RuntimeProfile::new("test".to_string(), ops);
        let hash = compute_content_hash(&profile);
        assert_eq!(hash.len(), 16, "Expected 16-char hex hash, got {}", hash);
        assert!(
            hash.chars().all(|c| c.is_ascii_hexdigit()),
            "Hash must be hex-only: {}",
            hash
        );
    }

    /// Adding an action to an operation must change the hash.
    #[test]
    fn adding_action_changes_hash() {
        let ops1 = vec![sample_op("action-test")];
        let mut ops2 = vec![sample_op("action-test")];
        // Give ops2 an action
        if let Some(op) = ops2.get_mut(0) {
            op.actions.push(crate::runtime::RuntimeAction::Comment(
                crate::runtime::RuntimeComment {
                    text: "hi".to_string(),
                },
            ));
        }
        let p1 = RuntimeProfile::new("x".to_string(), ops1);
        let p2 = RuntimeProfile::new("x".to_string(), ops2);
        assert_ne!(compute_content_hash(&p1), compute_content_hash(&p2));
    }
}
