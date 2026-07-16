//! Concrete `RoutingService` implementation backed by Detour navmesh queries.

use std::sync::Arc;

use detour::types::Vec3;
use mmap_loader::MmapManager;

use crate::error::AppError;
use crate::pipeline::{resolve_filter, pathfind_maybe_avoid, solve_tsp, PathOptions};
use crate::services::{self, MultiStopRequest, MultiStopResult, RoutingService, TspRequest};

/// Routing service that delegates leg pathfinding to Detour via `pathfind_maybe_avoid`.
pub struct DetourRouter {
    manager: Arc<MmapManager>,
}

impl DetourRouter {
    pub fn new(manager: Arc<MmapManager>) -> Self {
        Self { manager }
    }

    /// Pathfind consecutive stop pairs and collect waypoints, distances, and boundaries.
    fn pathfind_legs(
        &self,
        map_id: u32,
        stops: &[Vec3],
        options: &PathOptions,
    ) -> Result<MultiStopResult, AppError> {
        let pool = services::acquire(&self.manager, map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let mut custom_filter_storage = None;
        let filter = resolve_filter(pool.filter(), options.filter_ground, options.filter_water, options.filter_lava, &mut custom_filter_storage)?;

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
            let pool = services::acquire(&self.manager, req.map_id)?;
            let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

            let mut custom_filter_storage = None;
            let filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

            let no_smooth = PathOptions {
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
        let visit_order = solve_tsp(&distances, &weights);

        // --- Pathfind the optimized route ---
        let ordered_stops: Vec<Vec3> = visit_order.iter().map(|&i| req.stops[i]).collect();
        self.pathfind_legs(req.map_id, &ordered_stops, &req.options)
    }
}
