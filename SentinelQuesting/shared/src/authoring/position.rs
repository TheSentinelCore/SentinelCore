//! World-space position (ADR `02_DATA_MODEL` §25). World coordinates only (ADR-203).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Position {
    /// Continent/map id.
    pub map: u32,
    pub world_x: f32,
    pub world_y: f32,
    pub world_z: f32,
    /// Facing in radians; optional, used for interaction orientation.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub orientation: Option<f32>,
}

impl Position {
    pub fn new(map: u32, world_x: f32, world_y: f32, world_z: f32) -> Self {
        Self {
            map,
            world_x,
            world_y,
            world_z,
            orientation: None,
        }
    }

    pub fn with_orientation(mut self, orientation: f32) -> Self {
        self.orientation = Some(orientation);
        self
    }
}
