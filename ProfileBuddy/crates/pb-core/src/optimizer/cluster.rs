//! Cluster-based route optimizer
//!
//! Uses DBSCAN clustering to group nodes into hotspots,
//! then routes between cluster centroids.

use super::{
    distance_2d, Algorithm, NodeCluster, OptimizerConfig, Route, RouteOptimizer, RouteWaypoint,
    WaypointType,
};
use crate::parser::DecodedNode;

/// Cluster-based route optimizer
#[derive(Debug)]
pub struct ClusterOptimizer {
    /// DBSCAN epsilon (neighborhood radius in yards)
    pub eps: f32,
    /// DBSCAN min_samples (minimum points to form a cluster)
    pub min_samples: usize,
}

impl ClusterOptimizer {
    pub fn new(eps: f32, min_samples: usize) -> Self {
        Self { eps, min_samples }
    }
}

impl Default for ClusterOptimizer {
    fn default() -> Self {
        Self {
            eps: 50.0,       // 50 yards
            min_samples: 3,  // At least 3 nodes
        }
    }
}

impl RouteOptimizer for ClusterOptimizer {
    fn optimize(&self, nodes: &[DecodedNode], config: &OptimizerConfig) -> Route {
        if nodes.is_empty() {
            return Route {
                waypoints: Vec::new(),
                total_distance: 0.0,
                hotspots: Vec::new(),
                algorithm: Algorithm::Cluster,
                randomized: false,
                source_nodes: Vec::new(),
            };
        }

        // Step 1: Cluster nodes using DBSCAN
        let clusters = self.dbscan_cluster(nodes);

        // Step 2: For unclustered nodes, treat as individual waypoints
        let unclustered: Vec<&DecodedNode> = nodes
            .iter()
            .filter(|n| !clusters.iter().any(|c| c.node_ids.contains(&n.node_id)))
            .collect();

        // Step 3: Create waypoints from cluster centroids
        let mut waypoints: Vec<RouteWaypoint> = clusters
            .iter()
            .map(|c| RouteWaypoint {
                x: c.center_x,
                y: c.center_y,
                z: c.center_z,
                waypoint_type: WaypointType::Hotspot {
                    radius: c.radius as u32,
                },
                source_node_id: None,
                note: Some(format!("{} nodes", c.node_count)),
            })
            .collect();

        // Add unclustered nodes as path waypoints
        for node in &unclustered {
            waypoints.push(RouteWaypoint {
                x: node.world_x,
                y: node.world_y,
                z: node.world_z,
                waypoint_type: WaypointType::Path,
                source_node_id: Some(node.node_id),
                note: None,
            });
        }

        // Step 4: Order waypoints using nearest neighbor
        let ordered_waypoints = self.order_waypoints(&waypoints);

        // Calculate total distance
        let total_distance = self.calculate_distance(&ordered_waypoints);

        Route {
            waypoints: ordered_waypoints,
            total_distance,
            hotspots: clusters,
            algorithm: Algorithm::Cluster,
            randomized: matches!(
                config.randomization,
                super::RandomStrategy::RouteVariation
                    | super::RandomStrategy::NodeSubset
                    | super::RandomStrategy::Both
            ),
            source_nodes: nodes.to_vec(),
        }
    }

    fn algorithm(&self) -> Algorithm {
        Algorithm::Cluster
    }
}

impl ClusterOptimizer {
    /// DBSCAN clustering algorithm
    fn dbscan_cluster(&self, nodes: &[DecodedNode]) -> Vec<NodeCluster> {
        let mut clusters = Vec::new();
        let mut visited = vec![false; nodes.len()];
        let mut cluster_assignment = vec![None; nodes.len()];

        for i in 0..nodes.len() {
            if visited[i] {
                continue;
            }
            visited[i] = true;

            // Find neighbors
            let neighbors = self.region_query(nodes, i);

            if neighbors.len() >= self.min_samples {
                // Start new cluster
                let cluster_id = clusters.len();
                let mut cluster_nodes = vec![i];
                cluster_assignment[i] = Some(cluster_id);

                // Expand cluster
                let mut seeds: Vec<usize> = neighbors.clone();
                while let Some(q) = seeds.pop() {
                    if !visited[q] {
                        visited[q] = true;
                        let q_neighbors = self.region_query(nodes, q);
                        if q_neighbors.len() >= self.min_samples {
                            seeds.extend(q_neighbors);
                        }
                    }
                    if cluster_assignment[q].is_none() {
                        cluster_assignment[q] = Some(cluster_id);
                        cluster_nodes.push(q);
                    }
                }

                // Create cluster from nodes
                let cluster = self.create_cluster(nodes, &cluster_nodes);
                clusters.push(cluster);
            }
        }

        clusters
    }

    /// Find all points within eps distance
    fn region_query(&self, nodes: &[DecodedNode], point_idx: usize) -> Vec<usize> {
        let point = &nodes[point_idx];
        nodes
            .iter()
            .enumerate()
            .filter(|(i, n)| {
                *i != point_idx
                    && distance_2d(point.world_x, point.world_y, n.world_x, n.world_y) <= self.eps
            })
            .map(|(i, _)| i)
            .collect()
    }

    /// Create a cluster from a list of node indices
    fn create_cluster(&self, nodes: &[DecodedNode], indices: &[usize]) -> NodeCluster {
        let mut sum_x = 0.0;
        let mut sum_y = 0.0;
        let mut sum_z = 0.0;
        let mut node_ids = Vec::new();

        for &idx in indices {
            sum_x += nodes[idx].world_x;
            sum_y += nodes[idx].world_y;
            sum_z += nodes[idx].world_z;
            node_ids.push(nodes[idx].node_id);
        }

        let count = indices.len() as f32;
        let center_x = sum_x / count;
        let center_y = sum_y / count;
        let center_z = sum_z / count;

        // Calculate radius
        let mut max_dist = 0.0f32;
        for &idx in indices {
            let dist = distance_2d(center_x, center_y, nodes[idx].world_x, nodes[idx].world_y);
            max_dist = max_dist.max(dist);
        }

        NodeCluster {
            center_x,
            center_y,
            center_z,
            radius: max_dist + 10.0,
            node_count: indices.len(),
            node_ids,
        }
    }

    /// Order waypoints using nearest neighbor
    fn order_waypoints(&self, waypoints: &[RouteWaypoint]) -> Vec<RouteWaypoint> {
        if waypoints.is_empty() {
            return Vec::new();
        }

        let mut ordered = Vec::with_capacity(waypoints.len());
        let mut remaining: Vec<_> = waypoints.iter().cloned().collect();

        // Start with first waypoint
        ordered.push(remaining.remove(0));

        while !remaining.is_empty() {
            let current = ordered.last().unwrap();
            let mut nearest_idx = 0;
            let mut nearest_dist = f32::MAX;

            for (i, wp) in remaining.iter().enumerate() {
                let dist = distance_2d(current.x, current.y, wp.x, wp.y);
                if dist < nearest_dist {
                    nearest_dist = dist;
                    nearest_idx = i;
                }
            }

            ordered.push(remaining.remove(nearest_idx));
        }

        ordered
    }

    /// Calculate total route distance
    fn calculate_distance(&self, waypoints: &[RouteWaypoint]) -> f32 {
        if waypoints.len() < 2 {
            return 0.0;
        }

        let mut total = 0.0;
        for i in 0..waypoints.len() - 1 {
            total += distance_2d(
                waypoints[i].x,
                waypoints[i].y,
                waypoints[i + 1].x,
                waypoints[i + 1].y,
            );
        }

        // Add loop back
        total += distance_2d(
            waypoints.last().unwrap().x,
            waypoints.last().unwrap().y,
            waypoints.first().unwrap().x,
            waypoints.first().unwrap().y,
        );

        total
    }
}
