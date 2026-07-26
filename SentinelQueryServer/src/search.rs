//! Types for the two Phase-1 IDE endpoints: federated Smart Search and spawn lookup.
//!
//! They live here rather than in `sentinel-query-types` because that crate sits in the
//! `SentinelQuesting` tree and is owned by another work unit; nothing outside this server
//! consumes these shapes yet.

use serde::{Deserialize, Serialize};
use std::str::FromStr;

/// Applied when the caller sends no `limit`.
pub const DEFAULT_SEARCH_LIMIT: usize = 25;

/// Hard ceiling. Without it a query string could ask for an unbounded LIKE sweep over 109k
/// creatures plus every other searched table.
pub const MAX_SEARCH_LIMIT: usize = 100;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SearchKind {
    Npc,
    Quest,
    Item,
    Object,
    Area,
}

/// One typed hit. `context` is the short disambiguator the IDE shows next to the name —
/// three creatures called "Fang" are only distinguishable by their level band and map.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchHit {
    pub kind: SearchKind,
    pub id: u32,
    pub name: String,
    pub context: String,
    /// 3 = exact, 2 = prefix, 1 = substring. Exposed so the IDE can group by match quality.
    pub score: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpawnType {
    Npc,
    Object,
}

impl SpawnType {
    /// `(spawn table, template table)`. Both spawn tables key the template by `id`.
    pub fn tables(self) -> (&'static str, &'static str) {
        match self {
            SpawnType::Npc => ("creature", "creature_template"),
            SpawnType::Object => ("gameobject", "gameobject_template"),
        }
    }
}

impl FromStr for SpawnType {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "npc" => Ok(SpawnType::Npc),
            "object" => Ok(SpawnType::Object),
            other => Err(format!("Unknown spawn type: {other}")),
        }
    }
}

/// A single spawn point.
///
/// `position_z` is the reason this endpoint exists: guide text never carried ground height, so
/// every imported Travel position landed at `world_z = 0` — underground, and unusable for navmesh
/// queries. `creature.position_z` / `gameobject.position_z` are the real heights.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpawnPoint {
    pub guid: u32,
    pub map: u32,
    pub position_x: f32,
    pub position_y: f32,
    pub position_z: f32,
    pub orientation: f32,
}

/// Neutralise LIKE metacharacters so caller text is matched literally.
///
/// A bare `%` in `q` would otherwise match every row of every searched table.
pub fn escape_like(term: &str) -> String {
    let mut out = String::with_capacity(term.len());
    for ch in term.chars() {
        if matches!(ch, '\\' | '%' | '_') {
            out.push('\\');
        }
        out.push(ch);
    }
    out
}

/// Parse and bound the `limit` query parameter. Absent means the default; out of range clamps;
/// unparseable is a client error rather than a silent fallback.
pub fn parse_limit(raw: Option<&str>) -> Result<usize, String> {
    match raw {
        None => Ok(DEFAULT_SEARCH_LIMIT),
        Some(text) => text
            .trim()
            .parse::<usize>()
            .map(|n| n.clamp(1, MAX_SEARCH_LIMIT))
            .map_err(|_| format!("Invalid 'limit' parameter: {text}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_like_neutralises_wildcards() {
        assert_eq!(escape_like("100%"), "100\\%");
        assert_eq!(escape_like("a_b"), "a\\_b");
        assert_eq!(escape_like("c:\\path"), "c:\\\\path");
        assert_eq!(escape_like("Fang"), "Fang");
    }

    #[test]
    fn parse_limit_defaults_and_clamps() {
        assert_eq!(parse_limit(None), Ok(DEFAULT_SEARCH_LIMIT));
        assert_eq!(parse_limit(Some("10")), Ok(10));
        assert_eq!(parse_limit(Some("100000")), Ok(MAX_SEARCH_LIMIT));
        assert_eq!(parse_limit(Some("0")), Ok(1));
        assert!(parse_limit(Some("abc")).is_err());
        assert!(parse_limit(Some("-5")).is_err());
    }

    #[test]
    fn spawn_type_parses_only_known_kinds() {
        assert_eq!("npc".parse::<SpawnType>(), Ok(SpawnType::Npc));
        assert_eq!("object".parse::<SpawnType>(), Ok(SpawnType::Object));
        assert!("dragon".parse::<SpawnType>().is_err());
    }

    #[test]
    fn search_kind_serialises_lowercase() {
        let json = serde_json::to_string(&SearchKind::Npc).unwrap();
        assert_eq!(json, "\"npc\"");
        let json = serde_json::to_string(&SearchKind::Area).unwrap();
        assert_eq!(json, "\"area\"");
    }
}
