//! Geometry — Volume 5 §"Waypoint", "Path", "Polygon"
//! 
//! See: docs/adr/005-schema.md

use serde::{Deserialize, Serialize};

/// Waypoint — Volume 5 §"Waypoint"
/// 
/// 3D position with map/zone context and arrival radius.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Waypoint {
    pub map: u32,
    pub zone: String,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub radius: f32,
}

impl Waypoint {
    pub fn new(map: u32, zone: impl Into<String>, x: f32, y: f32, z: f32, radius: f32) -> Self {
        Self { map, zone: zone.into(), x, y, z, radius }
    }
    
    pub fn zero() -> Self {
        Self { map: 0, zone: String::new(), x: 0.0, y: 0.0, z: 0.0, radius: 5.0 }
    }
    
    pub fn distance_2d(&self, other: &Self) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }
    
    pub fn distance_3d(&self, other: &Self) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        let dz = self.z - other.z;
        (dx * dx + dy * dy + dz * dz).sqrt()
    }
}

/// Path — Volume 5 §"Path"
/// 
/// Sequence of waypoints forming a recorded path.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Path {
    pub points: Vec<Waypoint>,
}

impl Path {
    pub fn new(points: Vec<Waypoint>) -> Self {
        Self { points }
    }
    
    pub fn is_empty(&self) -> bool {
        self.points.is_empty()
    }
    
    pub fn len(&self) -> usize {
        self.points.len()
    }
    
    pub fn length(&self) -> f32 {
        self.points.windows(2).map(|w| w[0].distance_3d(&w[1])).sum()
    }
}

/// Polygon — Volume 5 §"Polygon"
/// 
/// Grind area defined by vertices (minimum 3 for validity).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Polygon {
    pub vertices: Vec<Waypoint>,
}

impl Polygon {
    pub fn new(vertices: Vec<Waypoint>) -> Self {
        Self { vertices }
    }
    
    /// Validate polygon has at least 3 vertices (Volume 8 §4 structural check)
    pub fn is_valid(&self) -> bool {
        self.vertices.len() >= 3
    }
    
    pub fn vertex_count(&self) -> usize {
        self.vertices.len()
    }
    
    /// Get centroid (average of vertices)
    pub fn centroid(&self) -> Option<Waypoint> {
        if self.vertices.is_empty() { return None; }
        let n = self.vertices.len() as f32;
        let x = self.vertices.iter().map(|v| v.x).sum::<f32>() / n;
        let y = self.vertices.iter().map(|v| v.y).sum::<f32>() / n;
        let z = self.vertices.iter().map(|v| v.z).sum::<f32>() / n;
        let map = self.vertices[0].map;
        let zone = self.vertices[0].zone.clone();
        Some(Waypoint::new(map, zone, x, y, z, 0.0))
    }
}