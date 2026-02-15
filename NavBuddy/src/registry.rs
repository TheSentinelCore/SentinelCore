//! Runtime obstacle registry.
//!
//! Stores obstacles per-map so all path queries can automatically
//! incorporate them without per-request avoidance zone params.

use dashmap::DashMap;
use serde::Serialize;

use crate::pipeline::AvoidanceZone;
use detour::Vec3;

/// A registered obstacle with position and radius.
#[derive(Debug, Clone, Serialize)]
pub struct RegisteredObstacle {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub radius: f32,
    pub cost: f32,
}

impl RegisteredObstacle {
    /// Convert to AvoidanceZone for the pathfinding pipeline.
    pub fn to_avoidance_zone(&self) -> AvoidanceZone {
        AvoidanceZone {
            center: Vec3 {
                x: self.x,
                y: self.y,
                z: self.z,
            },
            radius: self.radius,
            cost_multiplier: self.cost,
        }
    }
}

/// Per-map obstacle store.
#[derive(Debug, Default)]
pub struct ObstacleRegistry {
    obstacles: DashMap<u32, Vec<RegisteredObstacle>>,
}

impl ObstacleRegistry {
    pub fn new() -> Self {
        Self {
            obstacles: DashMap::new(),
        }
    }

    /// Replace all obstacles for a given map.
    pub fn update(&self, map_id: u32, obstacles: Vec<RegisteredObstacle>) {
        self.obstacles.insert(map_id, obstacles);
    }

    /// Get obstacles for a map as AvoidanceZones.
    pub fn get_avoidance_zones(&self, map_id: u32) -> Vec<AvoidanceZone> {
        self.obstacles
            .get(&map_id)
            .map(|entry| entry.iter().map(|o| o.to_avoidance_zone()).collect())
            .unwrap_or_default()
    }

    /// Get raw registered obstacles for a map (for list endpoint).
    pub fn get_raw(&self, map_id: u32) -> Vec<RegisteredObstacle> {
        self.obstacles
            .get(&map_id)
            .map(|entry| entry.clone())
            .unwrap_or_default()
    }

    /// Clear obstacles for a map.
    pub fn clear(&self, map_id: u32) {
        self.obstacles.remove(&map_id);
    }

    /// Total number of registered obstacles across all maps.
    pub fn total_count(&self) -> usize {
        self.obstacles.iter().map(|e| e.value().len()).sum()
    }
}
