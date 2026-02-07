//! Route optimization algorithms
//!
//! Provides multiple algorithms for optimizing gathering routes:
//! - TSP (Traveling Salesman Problem) - default, uses nearest neighbor + 2-opt
//! - Cluster - groups nodes into hotspots, then routes between them
//! - Density - follows high-density areas using kernel density estimation

mod cluster;
mod density;
mod tsp;

use crate::parser::DecodedNode;
use serde::{Deserialize, Serialize};

pub use cluster::ClusterOptimizer;
pub use density::DensityOptimizer;
pub use tsp::TspOptimizer;

/// Optimization algorithm selection
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum Algorithm {
    #[default]
    Tsp,
    Cluster,
    Density,
}

impl Algorithm {
    pub fn as_str(&self) -> &'static str {
        match self {
            Algorithm::Tsp => "TSP (Traveling Salesman)",
            Algorithm::Cluster => "Cluster + Connect",
            Algorithm::Density => "Density-Based",
        }
    }
}

/// Randomization strategy for profile uniqueness
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum RandomStrategy {
    /// No randomization
    None,
    /// Vary route: starting point, direction, coordinate jitter
    #[default]
    RouteVariation,
    /// Select random subset of nodes (70-90%)
    NodeSubset,
    /// Apply both strategies
    Both,
}

impl RandomStrategy {
    pub fn as_str(&self) -> &'static str {
        match self {
            RandomStrategy::None => "None",
            RandomStrategy::RouteVariation => "Route Variation",
            RandomStrategy::NodeSubset => "Node Subset",
            RandomStrategy::Both => "Route + Nodes",
        }
    }
}

/// Configuration for route optimization
#[derive(Debug, Clone)]
pub struct OptimizerConfig {
    /// Which algorithm to use
    pub algorithm: Algorithm,
    /// Randomization strategy
    pub randomization: RandomStrategy,
    /// Maximum 2-opt improvement iterations
    pub max_iterations: u32,
    /// Ratio of nodes to keep when using NodeSubset (0.7-1.0)
    pub node_subset_ratio: f32,
    /// Coordinate jitter range in yards (for RouteVariation)
    pub jitter_range: f32,
}

impl Default for OptimizerConfig {
    fn default() -> Self {
        Self {
            algorithm: Algorithm::Tsp,
            randomization: RandomStrategy::RouteVariation,
            max_iterations: 1000,
            node_subset_ratio: 0.85,
            jitter_range: 2.0,
        }
    }
}

/// A waypoint in the optimized route
#[derive(Debug, Clone)]
pub struct RouteWaypoint {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub waypoint_type: WaypointType,
    /// Original node ID (if from a node)
    pub source_node_id: Option<u16>,
    /// Note/description
    pub note: Option<String>,
}

/// Type of waypoint
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WaypointType {
    /// Standard path waypoint
    Path,
    /// Hotspot with scan radius
    Hotspot { radius: u32 },
}

/// A cluster of nearby nodes (used for hotspot generation)
#[derive(Debug, Clone)]
pub struct NodeCluster {
    pub center_x: f32,
    pub center_y: f32,
    pub center_z: f32,
    pub radius: f32,
    pub node_count: usize,
    pub node_ids: Vec<u16>,
}

/// Result of route optimization
#[derive(Debug, Clone)]
pub struct Route {
    /// Ordered waypoints
    pub waypoints: Vec<RouteWaypoint>,
    /// Total route distance in yards
    pub total_distance: f32,
    /// Identified hotspots (dense node areas)
    pub hotspots: Vec<NodeCluster>,
    /// Algorithm used
    pub algorithm: Algorithm,
    /// Whether randomization was applied
    pub randomized: bool,
    /// Source nodes used to create this route
    pub source_nodes: Vec<DecodedNode>,
}

impl Route {
    /// Get route as a simple list of (x, y, z) coordinates
    pub fn coords(&self) -> Vec<(f32, f32, f32)> {
        self.waypoints.iter().map(|w| (w.x, w.y, w.z)).collect()
    }
}

/// Trait for route optimizers
pub trait RouteOptimizer {
    /// Optimize a route through the given nodes
    fn optimize(&self, nodes: &[DecodedNode], config: &OptimizerConfig) -> Route;

    /// Get the algorithm type
    fn algorithm(&self) -> Algorithm;
}

/// Create an optimizer based on algorithm selection
pub fn create_optimizer(algorithm: Algorithm) -> Box<dyn RouteOptimizer> {
    match algorithm {
        Algorithm::Tsp => Box::new(TspOptimizer::default()),
        Algorithm::Cluster => Box::new(ClusterOptimizer::default()),
        Algorithm::Density => Box::new(DensityOptimizer::default()),
    }
}

/// Calculate Euclidean distance between two 2D points
pub(crate) fn distance_2d(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let dx = x2 - x1;
    let dy = y2 - y1;
    (dx * dx + dy * dy).sqrt()
}

/// Calculate Euclidean distance between two 3D points
pub(crate) fn distance_3d(x1: f32, y1: f32, z1: f32, x2: f32, y2: f32, z2: f32) -> f32 {
    let dx = x2 - x1;
    let dy = y2 - y1;
    let dz = z2 - z1;
    (dx * dx + dy * dy + dz * dz).sqrt()
}

/// Merge nodes within `min_distance` yards by averaging positions.
/// Keeps first node's metadata. Returns original vec if min_distance <= 0.
pub fn deduplicate_nodes(nodes: &[DecodedNode], min_distance: f32) -> Vec<DecodedNode> {
    if min_distance <= 0.0 || nodes.is_empty() {
        return nodes.to_vec();
    }

    let mut used = vec![false; nodes.len()];
    let mut result = Vec::new();

    for i in 0..nodes.len() {
        if used[i] {
            continue;
        }

        // Find all nodes within min_distance of node i
        let mut group = vec![i];
        for j in (i + 1)..nodes.len() {
            if used[j] {
                continue;
            }
            let dist = distance_2d(
                nodes[i].world_x,
                nodes[i].world_y,
                nodes[j].world_x,
                nodes[j].world_y,
            );
            if dist <= min_distance {
                group.push(j);
            }
        }

        // Average positions, keep first node's metadata
        let count = group.len() as f32;
        let mut merged = nodes[i].clone();
        if group.len() > 1 {
            let (sum_x, sum_y, sum_z) =
                group
                    .iter()
                    .fold((0.0, 0.0, 0.0), |(sx, sy, sz), &idx| {
                        (
                            sx + nodes[idx].world_x,
                            sy + nodes[idx].world_y,
                            sz + nodes[idx].world_z,
                        )
                    });
            merged.world_x = sum_x / count;
            merged.world_y = sum_y / count;
            merged.world_z = sum_z / count;
        }

        for &idx in &group {
            used[idx] = true;
        }
        result.push(merged);
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::NodeCategory;

    fn test_node() -> DecodedNode {
        DecodedNode {
            id: 0,
            zone_id: 1429,
            zone_name: "Elwynn Forest".to_string(),
            map_x: 0.5,
            map_y: 0.5,
            world_x: 0.0,
            world_y: 0.0,
            world_z: 0.0,
            category: NodeCategory::Ore,
            node_id: 1,
            node_name: "Copper Vein".to_string(),
        }
    }

    #[test]
    fn test_deduplicate_nearby_nodes() {
        let nodes = vec![
            DecodedNode {
                world_x: 100.0,
                world_y: 200.0,
                world_z: 50.0,
                node_id: 1,
                ..test_node()
            },
            DecodedNode {
                world_x: 101.0,
                world_y: 201.0,
                world_z: 51.0,
                node_id: 2,
                ..test_node()
            },
        ];
        let result = deduplicate_nodes(&nodes, 5.0);
        assert_eq!(result.len(), 1);
        assert!((result[0].world_x - 100.5).abs() < 0.01);
        assert!((result[0].world_y - 200.5).abs() < 0.01);
    }

    #[test]
    fn test_deduplicate_far_nodes_stay_separate() {
        let nodes = vec![
            DecodedNode {
                world_x: 100.0,
                world_y: 200.0,
                world_z: 50.0,
                node_id: 1,
                ..test_node()
            },
            DecodedNode {
                world_x: 200.0,
                world_y: 300.0,
                world_z: 60.0,
                node_id: 2,
                ..test_node()
            },
        ];
        let result = deduplicate_nodes(&nodes, 5.0);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_deduplicate_zero_distance_disables() {
        let nodes = vec![
            DecodedNode {
                world_x: 100.0,
                world_y: 200.0,
                world_z: 50.0,
                node_id: 1,
                ..test_node()
            },
            DecodedNode {
                world_x: 101.0,
                world_y: 201.0,
                world_z: 51.0,
                node_id: 2,
                ..test_node()
            },
        ];
        let result = deduplicate_nodes(&nodes, 0.0);
        assert_eq!(result.len(), 2);
    }
}
