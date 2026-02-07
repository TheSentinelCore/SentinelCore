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
