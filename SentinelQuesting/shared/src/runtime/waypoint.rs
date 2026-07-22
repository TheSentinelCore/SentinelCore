//! A single resolved world coordinate used by the runtime (no orientation — navigation only).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct RuntimeWaypoint {
    pub map: u32,
    pub world_x: f32,
    pub world_y: f32,
    pub world_z: f32,
}

impl RuntimeWaypoint {
    pub fn new(map: u32, world_x: f32, world_y: f32, world_z: f32) -> Self {
        Self {
            map,
            world_x,
            world_y,
            world_z,
        }
    }
}
