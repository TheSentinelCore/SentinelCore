//! Reusable resolved polygon for Travel/Grind/Escort/Patrol at runtime.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::waypoint::RuntimeWaypoint;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeArea {
    pub id: Uuid,
    pub name: String,
    pub polygon: Vec<RuntimeWaypoint>,
    #[serde(default)]
    pub tags: Vec<String>,
}

impl RuntimeArea {
    pub fn new(id: Uuid, name: impl Into<String>, polygon: Vec<RuntimeWaypoint>) -> Self {
        Self {
            id,
            name: name.into(),
            polygon,
            tags: Vec::new(),
        }
    }
}
