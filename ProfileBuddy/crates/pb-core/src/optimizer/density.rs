//! Density-based route optimizer
//!
//! Uses kernel density estimation to identify high-density areas,
//! then creates routes that follow density gradients.

use super::{
    distance_2d, Algorithm, NodeCluster, OptimizerConfig, Route, RouteOptimizer, RouteWaypoint,
    WaypointType,
};
use crate::parser::DecodedNode;

/// Density-based route optimizer
#[derive(Debug)]
pub struct DensityOptimizer {
    /// Kernel bandwidth in yards
    pub bandwidth: f32,
    /// Grid resolution for density estimation
    pub grid_resolution: f32,
}

impl Default for DensityOptimizer {
    fn default() -> Self {
        Self {
            bandwidth: 30.0,
            grid_resolution: 20.0,
        }
    }
}

impl RouteOptimizer for DensityOptimizer {
    fn optimize(&self, nodes: &[DecodedNode], config: &OptimizerConfig) -> Route {
        if nodes.is_empty() {
            return Route {
                waypoints: Vec::new(),
                total_distance: 0.0,
                hotspots: Vec::new(),
                algorithm: Algorithm::Density,
                randomized: false,
                source_nodes: Vec::new(),
            };
        }

        // Step 1: Build density grid
        let (grid, min_x, min_y, cols, rows) = self.build_density_grid(nodes);

        // Step 2: Find density peaks (local maxima)
        let peaks = self.find_peaks(&grid, cols, rows, min_x, min_y);

        // Step 3: Create waypoints at peaks
        let mut waypoints: Vec<RouteWaypoint> = peaks
            .iter()
            .map(|(x, y, density)| {
                // Find average Z at this location
                let avg_z = self.average_z_near(nodes, *x, *y, self.bandwidth);
                RouteWaypoint {
                    x: *x,
                    y: *y,
                    z: avg_z,
                    waypoint_type: if *density > 0.5 {
                        WaypointType::Hotspot {
                            radius: (self.bandwidth * 1.5) as u32,
                        }
                    } else {
                        WaypointType::Path
                    },
                    source_node_id: None,
                    note: Some(format!("Density: {:.2}", density)),
                }
            })
            .collect();

        // Step 4: If not enough peaks, add highest density nodes directly
        if waypoints.len() < 5 && nodes.len() > 5 {
            let mut node_densities: Vec<(usize, f32)> = nodes
                .iter()
                .enumerate()
                .map(|(i, n)| {
                    let density = self.point_density(nodes, n.world_x, n.world_y);
                    (i, density)
                })
                .collect();
            node_densities.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

            for (i, _density) in node_densities.into_iter().take(15) {
                let node = &nodes[i];
                // Skip if we already have a waypoint nearby
                let has_nearby = waypoints.iter().any(|w| {
                    distance_2d(w.x, w.y, node.world_x, node.world_y) < self.bandwidth
                });
                if !has_nearby {
                    waypoints.push(RouteWaypoint {
                        x: node.world_x,
                        y: node.world_y,
                        z: node.world_z,
                        waypoint_type: WaypointType::Path,
                        source_node_id: Some(node.node_id),
                        note: None,
                    });
                }
            }
        }

        // Step 5: Order waypoints by following density gradient
        let ordered_waypoints = self.order_by_density(waypoints, nodes);

        // Identify clusters as hotspots
        let hotspots = self.identify_hotspots(nodes);

        // Calculate total distance
        let total_distance = self.calculate_distance(&ordered_waypoints);

        Route {
            waypoints: ordered_waypoints,
            total_distance,
            hotspots,
            algorithm: Algorithm::Density,
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
        Algorithm::Density
    }
}

impl DensityOptimizer {
    /// Build a 2D density grid using kernel density estimation
    fn build_density_grid(
        &self,
        nodes: &[DecodedNode],
    ) -> (Vec<f32>, f32, f32, usize, usize) {
        // Find bounds
        let min_x = nodes.iter().map(|n| n.world_x).fold(f32::MAX, f32::min);
        let max_x = nodes.iter().map(|n| n.world_x).fold(f32::MIN, f32::max);
        let min_y = nodes.iter().map(|n| n.world_y).fold(f32::MAX, f32::min);
        let max_y = nodes.iter().map(|n| n.world_y).fold(f32::MIN, f32::max);

        let cols = ((max_x - min_x) / self.grid_resolution).ceil() as usize + 1;
        let rows = ((max_y - min_y) / self.grid_resolution).ceil() as usize + 1;

        let mut grid = vec![0.0f32; cols * rows];

        // Apply Gaussian kernel for each node
        for node in nodes {
            let grid_x = ((node.world_x - min_x) / self.grid_resolution) as i32;
            let grid_y = ((node.world_y - min_y) / self.grid_resolution) as i32;

            // Influence radius in grid cells
            let influence = (self.bandwidth / self.grid_resolution).ceil() as i32;

            for dx in -influence..=influence {
                for dy in -influence..=influence {
                    let gx = grid_x + dx;
                    let gy = grid_y + dy;

                    if gx >= 0 && gx < cols as i32 && gy >= 0 && gy < rows as i32 {
                        let world_x = min_x + gx as f32 * self.grid_resolution;
                        let world_y = min_y + gy as f32 * self.grid_resolution;
                        let dist = distance_2d(node.world_x, node.world_y, world_x, world_y);

                        // Gaussian kernel
                        let weight = (-0.5 * (dist / self.bandwidth).powi(2)).exp();
                        grid[gy as usize * cols + gx as usize] += weight;
                    }
                }
            }
        }

        // Normalize
        let max_density = grid.iter().cloned().fold(0.0f32, f32::max);
        if max_density > 0.0 {
            for cell in &mut grid {
                *cell /= max_density;
            }
        }

        (grid, min_x, min_y, cols, rows)
    }

    /// Find local maxima in the density grid
    fn find_peaks(
        &self,
        grid: &[f32],
        cols: usize,
        rows: usize,
        min_x: f32,
        min_y: f32,
    ) -> Vec<(f32, f32, f32)> {
        let mut peaks = Vec::new();
        let min_density = 0.3; // Only consider cells with at least 30% of max density

        for y in 1..rows - 1 {
            for x in 1..cols - 1 {
                let idx = y * cols + x;
                let density = grid[idx];

                if density < min_density {
                    continue;
                }

                // Check if this is a local maximum
                let is_peak = [
                    (y - 1) * cols + x - 1,
                    (y - 1) * cols + x,
                    (y - 1) * cols + x + 1,
                    y * cols + x - 1,
                    y * cols + x + 1,
                    (y + 1) * cols + x - 1,
                    (y + 1) * cols + x,
                    (y + 1) * cols + x + 1,
                ]
                .iter()
                .all(|&neighbor| grid[neighbor] <= density);

                if is_peak {
                    let world_x = min_x + x as f32 * self.grid_resolution;
                    let world_y = min_y + y as f32 * self.grid_resolution;
                    peaks.push((world_x, world_y, density));
                }
            }
        }

        peaks
    }

    /// Calculate density at a single point
    fn point_density(&self, nodes: &[DecodedNode], x: f32, y: f32) -> f32 {
        nodes
            .iter()
            .map(|n| {
                let dist = distance_2d(n.world_x, n.world_y, x, y);
                (-0.5 * (dist / self.bandwidth).powi(2)).exp()
            })
            .sum()
    }

    /// Find average Z coordinate near a point
    fn average_z_near(&self, nodes: &[DecodedNode], x: f32, y: f32, radius: f32) -> f32 {
        let nearby: Vec<_> = nodes
            .iter()
            .filter(|n| distance_2d(n.world_x, n.world_y, x, y) <= radius)
            .collect();

        if nearby.is_empty() {
            // Return average of all nodes
            nodes.iter().map(|n| n.world_z).sum::<f32>() / nodes.len() as f32
        } else {
            nearby.iter().map(|n| n.world_z).sum::<f32>() / nearby.len() as f32
        }
    }

    /// Order waypoints by following density gradient (nearest high-density neighbor)
    fn order_by_density(
        &self,
        waypoints: Vec<RouteWaypoint>,
        nodes: &[DecodedNode],
    ) -> Vec<RouteWaypoint> {
        if waypoints.len() <= 1 {
            return waypoints;
        }

        let mut ordered = Vec::with_capacity(waypoints.len());
        let mut remaining: Vec<_> = waypoints.into_iter().collect();

        // Start with highest density point
        remaining.sort_by(|a, b| {
            let da = self.point_density(nodes, a.x, a.y);
            let db = self.point_density(nodes, b.x, b.y);
            db.partial_cmp(&da).unwrap()
        });
        ordered.push(remaining.remove(0));

        // Greedily add nearest points, slightly favoring higher density
        while !remaining.is_empty() {
            let current = ordered.last().unwrap();
            let mut best_idx = 0;
            let mut best_score = f32::MAX;

            for (i, wp) in remaining.iter().enumerate() {
                let dist = distance_2d(current.x, current.y, wp.x, wp.y);
                let density = self.point_density(nodes, wp.x, wp.y);
                // Score: distance minus density bonus
                let score = dist - density * 20.0;
                if score < best_score {
                    best_score = score;
                    best_idx = i;
                }
            }

            ordered.push(remaining.remove(best_idx));
        }

        ordered
    }

    /// Identify hotspots (same as TSP optimizer)
    fn identify_hotspots(&self, nodes: &[DecodedNode]) -> Vec<NodeCluster> {
        let cluster_radius = self.bandwidth * 1.5;
        let min_cluster_size = 3;
        let mut hotspots = Vec::new();
        let mut used = vec![false; nodes.len()];

        for (i, node) in nodes.iter().enumerate() {
            if used[i] {
                continue;
            }

            let mut cluster_nodes: Vec<usize> = vec![i];
            for (j, other) in nodes.iter().enumerate() {
                if i == j || used[j] {
                    continue;
                }
                if distance_2d(node.world_x, node.world_y, other.world_x, other.world_y)
                    <= cluster_radius
                {
                    cluster_nodes.push(j);
                }
            }

            if cluster_nodes.len() >= min_cluster_size {
                let mut sum_x = 0.0;
                let mut sum_y = 0.0;
                let mut sum_z = 0.0;
                let mut node_ids = Vec::new();

                for &idx in &cluster_nodes {
                    sum_x += nodes[idx].world_x;
                    sum_y += nodes[idx].world_y;
                    sum_z += nodes[idx].world_z;
                    node_ids.push(nodes[idx].id);
                }

                let count = cluster_nodes.len() as f32;
                let center_x = sum_x / count;
                let center_y = sum_y / count;
                let center_z = sum_z / count;

                let mut max_dist = 0.0f32;
                for &idx in &cluster_nodes {
                    let dist =
                        distance_2d(center_x, center_y, nodes[idx].world_x, nodes[idx].world_y);
                    max_dist = max_dist.max(dist);
                }

                hotspots.push(NodeCluster {
                    center_x,
                    center_y,
                    center_z,
                    radius: max_dist + 10.0,
                    node_count: cluster_nodes.len(),
                    node_ids,
                });

                for &idx in &cluster_nodes {
                    used[idx] = true;
                }
            }
        }

        hotspots
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

        total += distance_2d(
            waypoints.last().unwrap().x,
            waypoints.last().unwrap().y,
            waypoints.first().unwrap().x,
            waypoints.first().unwrap().y,
        );

        total
    }
}
