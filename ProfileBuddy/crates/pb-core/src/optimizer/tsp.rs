//! TSP (Traveling Salesman Problem) route optimizer
//!
//! Uses nearest neighbor heuristic for initial route construction,
//! then applies 2-opt improvement to reduce total distance.

use super::{
    distance_2d, Algorithm, NodeCluster, OptimizerConfig, RandomStrategy, Route, RouteOptimizer,
    RouteWaypoint, WaypointType,
};
use crate::parser::DecodedNode;
use rand::prelude::*;

/// TSP-based route optimizer
#[derive(Debug, Default)]
pub struct TspOptimizer;

impl RouteOptimizer for TspOptimizer {
    fn optimize(&self, nodes: &[DecodedNode], config: &OptimizerConfig) -> Route {
        if nodes.is_empty() {
            return Route {
                waypoints: Vec::new(),
                total_distance: 0.0,
                hotspots: Vec::new(),
                algorithm: Algorithm::Tsp,
                randomized: false,
                source_nodes: Vec::new(),
            };
        }

        let mut rng = rand::thread_rng();

        // Apply node subset selection if configured
        let working_nodes: Vec<&DecodedNode> = match config.randomization {
            RandomStrategy::NodeSubset | RandomStrategy::Both => {
                let keep_count =
                    (nodes.len() as f32 * config.node_subset_ratio).ceil() as usize;
                let mut indices: Vec<usize> = (0..nodes.len()).collect();
                indices.shuffle(&mut rng);
                indices.truncate(keep_count);
                indices.sort(); // Keep some spatial locality
                indices.iter().map(|&i| &nodes[i]).collect()
            }
            _ => nodes.iter().collect(),
        };

        if working_nodes.is_empty() {
            return Route {
                waypoints: Vec::new(),
                total_distance: 0.0,
                hotspots: Vec::new(),
                algorithm: Algorithm::Tsp,
                randomized: false,
                source_nodes: Vec::new(),
            };
        }

        // Build initial route using nearest neighbor
        let mut route = self.nearest_neighbor(&working_nodes, &mut rng, config);

        // Apply 2-opt improvement
        self.two_opt_improve(&mut route, config.max_iterations);

        // Apply route variation if configured
        let randomized = matches!(
            config.randomization,
            RandomStrategy::RouteVariation | RandomStrategy::Both
        );

        if randomized {
            self.apply_route_variation(&mut route, &mut rng, config);
        }

        // Identify hotspots (clusters of nearby nodes)
        let hotspots = self.identify_hotspots(&working_nodes);

        // Convert to waypoints, marking hotspots
        let waypoints = self.create_waypoints(&route, &hotspots, config);

        // Calculate total distance
        let total_distance = self.calculate_distance(&waypoints);

        // Collect source nodes that were used
        let source_nodes: Vec<DecodedNode> = working_nodes.iter().map(|n| (*n).clone()).collect();

        Route {
            waypoints,
            total_distance,
            hotspots,
            algorithm: Algorithm::Tsp,
            randomized,
            source_nodes,
        }
    }

    fn algorithm(&self) -> Algorithm {
        Algorithm::Tsp
    }
}

impl TspOptimizer {
    /// Build initial route using nearest neighbor heuristic
    fn nearest_neighbor<'a>(
        &self,
        nodes: &[&'a DecodedNode],
        rng: &mut impl Rng,
        _config: &OptimizerConfig,
    ) -> Vec<&'a DecodedNode> {
        if nodes.is_empty() {
            return Vec::new();
        }

        let mut route = Vec::with_capacity(nodes.len());
        let mut visited = vec![false; nodes.len()];

        // Start at a random node
        let start = rng.gen_range(0..nodes.len());
        route.push(nodes[start]);
        visited[start] = true;

        // Repeatedly visit nearest unvisited node
        while route.len() < nodes.len() {
            let current = route.last().unwrap();
            let mut nearest_idx = None;
            let mut nearest_dist = f32::MAX;

            for (i, &visited_flag) in visited.iter().enumerate() {
                if visited_flag {
                    continue;
                }

                let dist = distance_2d(
                    current.world_x,
                    current.world_y,
                    nodes[i].world_x,
                    nodes[i].world_y,
                );

                if dist < nearest_dist {
                    nearest_dist = dist;
                    nearest_idx = Some(i);
                }
            }

            if let Some(idx) = nearest_idx {
                route.push(nodes[idx]);
                visited[idx] = true;
            } else {
                break;
            }
        }

        route
    }

    /// Apply 2-opt improvement to reduce total distance
    fn two_opt_improve(&self, route: &mut Vec<&DecodedNode>, max_iterations: u32) {
        if route.len() < 4 {
            return;
        }

        let mut improved = true;
        let mut iterations = 0;

        while improved && iterations < max_iterations {
            improved = false;
            iterations += 1;

            for i in 0..route.len() - 2 {
                for j in (i + 2)..route.len() {
                    // Skip if j is the last and i is the first (same edge for closed loop)
                    if i == 0 && j == route.len() - 1 {
                        continue;
                    }

                    // Calculate current distance for edges (i, i+1) and (j, j+1 mod n)
                    let a = route[i];
                    let b = route[i + 1];
                    let c = route[j];
                    let d = route[(j + 1) % route.len()];

                    let current_dist = distance_2d(a.world_x, a.world_y, b.world_x, b.world_y)
                        + distance_2d(c.world_x, c.world_y, d.world_x, d.world_y);

                    // Calculate new distance if we reverse the segment between i+1 and j
                    let new_dist = distance_2d(a.world_x, a.world_y, c.world_x, c.world_y)
                        + distance_2d(b.world_x, b.world_y, d.world_x, d.world_y);

                    if new_dist < current_dist - 0.001 {
                        // Reverse the segment
                        route[i + 1..=j].reverse();
                        improved = true;
                    }
                }
            }
        }
    }

    /// Apply route variation: random direction, coordinate jitter
    fn apply_route_variation(
        &self,
        route: &mut Vec<&DecodedNode>,
        rng: &mut impl Rng,
        _config: &OptimizerConfig,
    ) {
        // Random direction (50% chance to reverse)
        if rng.gen_bool(0.5) {
            route.reverse();
        }

        // Random starting point
        if route.len() > 1 {
            let rotation = rng.gen_range(0..route.len());
            route.rotate_left(rotation);
        }
    }

    /// Identify clusters of nearby nodes as potential hotspots
    fn identify_hotspots(&self, nodes: &[&DecodedNode]) -> Vec<NodeCluster> {
        super::identify_hotspots(nodes, 50.0, 3)
    }

    /// Create waypoints from route, collapsing hotspot clusters into single centroids
    fn create_waypoints(
        &self,
        route: &[&DecodedNode],
        hotspots: &[NodeCluster],
        config: &OptimizerConfig,
    ) -> Vec<RouteWaypoint> {
        let mut rng = rand::thread_rng();
        let mut waypoints = Vec::new();
        let mut emitted_clusters: std::collections::HashSet<usize> =
            std::collections::HashSet::new();

        for node in route {
            // Check if this node belongs to a hotspot cluster
            let cluster_match = hotspots
                .iter()
                .enumerate()
                .find(|(_, h)| h.node_ids.contains(&node.id));

            if let Some((cluster_idx, cluster)) = cluster_match {
                // Only emit ONE waypoint per cluster (the centroid)
                if emitted_clusters.insert(cluster_idx) {
                    waypoints.push(RouteWaypoint {
                        x: cluster.center_x,
                        y: cluster.center_y,
                        z: cluster.center_z,
                        waypoint_type: WaypointType::Hotspot {
                            radius: cluster.radius as u32,
                        },
                        source_node_id: None,
                        note: Some(format!("{} nodes", cluster.node_count)),
                    });
                }
            } else {
                // Not in any cluster - emit as path waypoint
                let (x, y, z) = if matches!(
                    config.randomization,
                    RandomStrategy::RouteVariation | RandomStrategy::Both
                ) {
                    let jitter_x = rng.gen_range(-config.jitter_range..config.jitter_range);
                    let jitter_y = rng.gen_range(-config.jitter_range..config.jitter_range);
                    (node.world_x + jitter_x, node.world_y + jitter_y, node.world_z)
                } else {
                    (node.world_x, node.world_y, node.world_z)
                };

                waypoints.push(RouteWaypoint {
                    x,
                    y,
                    z,
                    waypoint_type: WaypointType::Path,
                    source_node_id: Some(node.node_id),
                    note: None,
                });
            }
        }

        waypoints
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

        // Add distance from last to first (loop)
        total += distance_2d(
            waypoints.last().unwrap().x,
            waypoints.last().unwrap().y,
            waypoints.first().unwrap().x,
            waypoints.first().unwrap().y,
        );

        total
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::NodeCategory;

    fn create_test_nodes() -> Vec<DecodedNode> {
        vec![
            DecodedNode {
                id: 1,
                zone_id: 1429,
                zone_name: "Elwynn Forest".to_string(),
                map_x: 0.5,
                map_y: 0.5,
                world_x: 0.0,
                world_y: 0.0,
                world_z: 50.0,
                category: NodeCategory::Herb,
                node_id: 403,
                node_name: "Peacebloom".to_string(),
            },
            DecodedNode {
                id: 2,
                zone_id: 1429,
                zone_name: "Elwynn Forest".to_string(),
                map_x: 0.6,
                map_y: 0.5,
                world_x: 100.0,
                world_y: 0.0,
                world_z: 50.0,
                category: NodeCategory::Herb,
                node_id: 403,
                node_name: "Peacebloom".to_string(),
            },
            DecodedNode {
                id: 3,
                zone_id: 1429,
                zone_name: "Elwynn Forest".to_string(),
                map_x: 0.6,
                map_y: 0.6,
                world_x: 100.0,
                world_y: 100.0,
                world_z: 50.0,
                category: NodeCategory::Herb,
                node_id: 401,
                node_name: "Silverleaf".to_string(),
            },
            DecodedNode {
                id: 4,
                zone_id: 1429,
                zone_name: "Elwynn Forest".to_string(),
                map_x: 0.5,
                map_y: 0.6,
                world_x: 0.0,
                world_y: 100.0,
                world_z: 50.0,
                category: NodeCategory::Herb,
                node_id: 401,
                node_name: "Silverleaf".to_string(),
            },
        ]
    }

    #[test]
    fn test_tsp_optimizer() {
        let nodes = create_test_nodes();
        let optimizer = TspOptimizer::default();
        let config = OptimizerConfig {
            randomization: RandomStrategy::None,
            ..Default::default()
        };

        let route = optimizer.optimize(&nodes, &config);

        assert_eq!(route.waypoints.len(), 4);
        assert!(route.total_distance > 0.0);
        assert!(!route.randomized);
    }

    #[test]
    fn test_tsp_with_randomization() {
        let nodes = create_test_nodes();
        let optimizer = TspOptimizer::default();
        let config = OptimizerConfig {
            randomization: RandomStrategy::RouteVariation,
            ..Default::default()
        };

        let route = optimizer.optimize(&nodes, &config);

        assert_eq!(route.waypoints.len(), 4);
        assert!(route.randomized);
    }

    #[test]
    fn test_empty_nodes() {
        let optimizer = TspOptimizer::default();
        let config = OptimizerConfig::default();

        let route = optimizer.optimize(&[], &config);

        assert!(route.waypoints.is_empty());
        assert_eq!(route.total_distance, 0.0);
    }

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
    fn test_hotspot_collapsing_same_node_type() {
        // All 7 nodes are same type (node_id=201) but unique IDs
        // 5 close nodes = 1 cluster + 2 isolated = 3 waypoints
        let nodes = vec![
            DecodedNode { id: 2001, world_x: 100.0, world_y: 200.0, world_z: 50.0, node_id: 201, ..test_node() },
            DecodedNode { id: 2002, world_x: 102.0, world_y: 201.0, world_z: 50.0, node_id: 201, ..test_node() },
            DecodedNode { id: 2003, world_x: 104.0, world_y: 203.0, world_z: 50.0, node_id: 201, ..test_node() },
            DecodedNode { id: 2004, world_x: 98.0, world_y: 199.0, world_z: 50.0, node_id: 201, ..test_node() },
            DecodedNode { id: 2005, world_x: 101.0, world_y: 202.0, world_z: 50.0, node_id: 201, ..test_node() },
            // 2 isolated
            DecodedNode { id: 2006, world_x: 500.0, world_y: 500.0, world_z: 60.0, node_id: 201, ..test_node() },
            DecodedNode { id: 2007, world_x: 800.0, world_y: 800.0, world_z: 70.0, node_id: 201, ..test_node() },
        ];

        let optimizer = TspOptimizer::default();
        let config = OptimizerConfig {
            randomization: RandomStrategy::None,
            ..Default::default()
        };
        let route = optimizer.optimize(&nodes, &config);

        assert_eq!(route.waypoints.len(), 3, "Expected 3 waypoints (1 hotspot + 2 path), got {}", route.waypoints.len());

        let hotspot_count = route.waypoints.iter()
            .filter(|w| matches!(w.waypoint_type, WaypointType::Hotspot { .. }))
            .count();
        let path_count = route.waypoints.iter()
            .filter(|w| matches!(w.waypoint_type, WaypointType::Path))
            .count();
        assert_eq!(hotspot_count, 1, "Expected 1 hotspot centroid, got {}", hotspot_count);
        assert_eq!(path_count, 2, "Expected 2 path waypoints, got {}", path_count);
    }

    #[test]
    fn test_hotspot_collapsing() {
        // 5 nearby nodes (1 cluster) + 2 isolated = should produce 3 waypoints
        // Each node needs a unique `id` for cluster membership tracking
        let nodes = vec![
            DecodedNode { id: 1, world_x: 100.0, world_y: 200.0, world_z: 50.0, node_id: 1, ..test_node() },
            DecodedNode { id: 2, world_x: 102.0, world_y: 201.0, world_z: 50.0, node_id: 2, ..test_node() },
            DecodedNode { id: 3, world_x: 104.0, world_y: 203.0, world_z: 50.0, node_id: 3, ..test_node() },
            DecodedNode { id: 4, world_x: 98.0, world_y: 199.0, world_z: 50.0, node_id: 4, ..test_node() },
            DecodedNode { id: 5, world_x: 101.0, world_y: 202.0, world_z: 50.0, node_id: 5, ..test_node() },
            // 2 isolated
            DecodedNode { id: 6, world_x: 500.0, world_y: 500.0, world_z: 60.0, node_id: 6, ..test_node() },
            DecodedNode { id: 7, world_x: 800.0, world_y: 800.0, world_z: 70.0, node_id: 7, ..test_node() },
        ];

        let optimizer = TspOptimizer::default();
        let config = OptimizerConfig {
            randomization: RandomStrategy::None,
            ..Default::default()
        };
        let route = optimizer.optimize(&nodes, &config);

        assert_eq!(route.waypoints.len(), 3, "Expected 3 waypoints (1 hotspot + 2 path), got {}", route.waypoints.len());

        let hotspot_count = route.waypoints.iter()
            .filter(|w| matches!(w.waypoint_type, WaypointType::Hotspot { .. }))
            .count();
        assert_eq!(hotspot_count, 1, "Expected 1 hotspot centroid, got {}", hotspot_count);
    }
}
