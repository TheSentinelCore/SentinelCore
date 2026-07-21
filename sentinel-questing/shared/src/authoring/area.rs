//! Reusable polygon areas (ADR `02_DATA_MODEL` §24). Used by Travel, Grind, Escort, Patrol.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::position::Position;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Area {
    pub id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub zone: Option<String>,
    pub name: String,
    /// Vertices of the area polygon in world space.
    #[serde(default)]
    pub points: Vec<Position>,
    #[serde(default)]
    pub tags: Vec<String>,
}

impl Area {
    pub fn new(name: impl Into<String>, points: Vec<Position>) -> Self {
        Self {
            id: Uuid::new_v4(),
            zone: None,
            name: name.into(),
            points,
            tags: Vec::new(),
        }
    }
}
