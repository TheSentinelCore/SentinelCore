//! Concrete `RoutingService` implementation backed by Detour navmesh queries.

use std::sync::Arc;

use detour::types::Vec3;
use mmap_loader::error::MmapError;
use mmap_loader::MmapManager;

use crate::error::AppError;
use crate::pipeline::{has_custom_filter, create_custom_filter, pathfind_maybe_avoid, PathOptions};
use crate::services::{MultiStopRequest, MultiStopResult, RoutingService, TspRequest};

/// Routing service that delegates leg pathfinding to Detour via `pathfind_maybe_avoid`.
pub struct DetourRouter {
    manager: Arc<MmapManager>,
}

impl DetourRouter {
    pub fn new(manager: Arc<MmapManager>) -> Self {
        Self { manager }
    }

    /// Acquire a query pool reference for the given map, loading tiles on demand.
    fn acquire(
        &self,
        map_id: u32,
    ) -> Result<dashmap::mapref::one::Ref<'_, u32, detour::pool::QueryPool>, AppError> {
        let _mesh = self.manager.get_or_load_mesh(map_id).map_err(|e| match &e {
            MmapError::MapNotFound(_) => AppError::MapNotFound(map_id),
            _ => AppError::Internal(e.to_string()),
        })?;
        self.manager
            .get_query_pool(map_id)
            .ok_or_else(|| AppError::MapNotFound(map_id))
    }

    /// Pathfind consecutive stop pairs and collect waypoints, distances, and boundaries.
    fn pathfind_legs(
        &self,
        map_id: u32,
        stops: &[Vec3],
        options: &PathOptions,
    ) -> Result<MultiStopResult, AppError> {
        let pool = self.acquire(map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let custom_filter;
        let filter = if has_custom_filter(
            options.filter_ground,
            options.filter_water,
            options.filter_lava,
        ) {
            custom_filter = create_custom_filter(
                options.filter_ground,
                options.filter_water,
                options.filter_lava,
            )?;
            &custom_filter
        } else {
            pool.filter()
        };

        let mut all_waypoints: Vec<Vec3> = Vec::new();
        let mut leg_distances = Vec::new();
        let mut leg_boundaries = vec![0usize];
        let mut total_distance = 0.0f32;
        let mut partial = false;

        for i in 0..stops.len() - 1 {
            let result = pathfind_maybe_avoid(
                &query, &pool, filter, stops[i], stops[i + 1], options, &[],
            )?;

            if result.partial {
                partial = true;
            }

            leg_distances.push(result.distance);
            total_distance += result.distance;

            // Append waypoints, deduplicating the shared endpoint between legs
            if all_waypoints.is_empty() {
                all_waypoints.extend_from_slice(&result.waypoints);
            } else if !result.waypoints.is_empty() {
                all_waypoints.extend_from_slice(&result.waypoints[1..]);
            }

            leg_boundaries.push(all_waypoints.len());
        }

        Ok(MultiStopResult {
            waypoints: all_waypoints,
            total_distance,
            leg_distances,
            leg_boundaries,
            partial,
        })
    }
}

/// Nearest-neighbor TSP with 2-opt improvement.
///
/// Ported from `intelligence.rs::solve_tsp`. Weights bias the greedy selection:
/// `cost = distance / weight` (higher weight = visited sooner).
fn solve_tsp(distances: &[Vec<f32>], start_idx: usize, weights: &[f32]) -> Vec<usize> {
    let n = distances.len();
    if n <= 2 {
        return (0..n).collect();
    }

    // --- Nearest-neighbor greedy ---
    let mut visited = vec![false; n];
    let mut order = Vec::with_capacity(n);
    let mut current = start_idx;
    visited[current] = true;
    order.push(current);

    for _ in 1..n {
        let mut best_idx = None;
        let mut best_cost = f32::MAX;

        for j in 0..n {
            if !visited[j] {
                let cost = distances[current][j] / weights[j];
                if cost < best_cost {
                    best_cost = cost;
                    best_idx = Some(j);
                }
            }
        }

        if let Some(next) = best_idx {
            visited[next] = true;
            order.push(next);
            current = next;
        }
    }

    // --- 2-opt improvement ---
    let mut improved = true;
    while improved {
        improved = false;
        for i in 1..order.len() - 1 {
            for j in (i + 1)..order.len() {
                let old_cost = distances[order[i - 1]][order[i]]
                    + distances[order[j - 1]][order[j % order.len()]];
                let new_cost = distances[order[i - 1]][order[j - 1]]
                    + distances[order[i]][order[j % order.len()]];

                if new_cost < old_cost - 0.01 {
                    order[i..j].reverse();
                    improved = true;
                }
            }
        }
    }

    order
}

impl RoutingService for DetourRouter {
    fn multi_stop(&self, req: MultiStopRequest) -> Result<MultiStopResult, AppError> {
        if req.stops.len() < 2 {
            return Err(AppError::InvalidParams(
                "At least 2 stops required".into(),
            ));
        }
        self.pathfind_legs(req.map_id, &req.stops, &req.options)
    }

    fn tsp_optimize(&self, req: TspRequest) -> Result<MultiStopResult, AppError> {
        let n = req.stops.len();
        if n < 2 {
            return Err(AppError::InvalidParams(
                "At least 2 stops required".into(),
            ));
        }

        // --- Build pairwise distance matrix ---
        // For small N (<=15) use navmesh distances; otherwise Euclidean.
        let mut distances = vec![vec![0.0f32; n]; n];

        if n <= 15 {
            let pool = self.acquire(req.map_id)?;
            let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

            let custom_filter;
            let filter = if has_custom_filter(
                req.options.filter_ground,
                req.options.filter_water,
                req.options.filter_lava,
            ) {
                custom_filter = create_custom_filter(
                    req.options.filter_ground,
                    req.options.filter_water,
                    req.options.filter_lava,
                )?;
                &custom_filter
            } else {
                pool.filter()
            };

            let no_smooth = PathOptions {
                smoothing: Some("none".to_string()),
                optimize: true,
                ..Default::default()
            };

            for i in 0..n {
                for j in (i + 1)..n {
                    let dist = match pathfind_maybe_avoid(
                        &query,
                        &pool,
                        filter,
                        req.stops[i],
                        req.stops[j],
                        &no_smooth,
                        &[],
                    ) {
                        Ok(result) => result.distance,
                        Err(_) => req.stops[i].distance(&req.stops[j]) * 1.5,
                    };
                    distances[i][j] = dist;
                    distances[j][i] = dist;
                }
            }
        } else {
            for i in 0..n {
                for j in (i + 1)..n {
                    let dist = req.stops[i].distance(&req.stops[j]);
                    distances[i][j] = dist;
                    distances[j][i] = dist;
                }
            }
        }

        // --- Solve TSP (uniform weights, start from index 0) ---
        let weights = vec![1.0f32; n];
        let visit_order = solve_tsp(&distances, 0, &weights);

        // --- Pathfind the optimized route ---
        let ordered_stops: Vec<Vec3> = visit_order.iter().map(|&i| req.stops[i]).collect();
        self.pathfind_legs(req.map_id, &ordered_stops, &req.options)
    }
}
