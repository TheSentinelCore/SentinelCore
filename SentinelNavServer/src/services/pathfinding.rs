use std::sync::Arc;

use mmap_loader::MmapManager;

use crate::error::AppError;
use crate::pipeline::{
    compute_corridor_widths, find_poly_tiered, resolve_filter,
    pathfind_maybe_avoid,
};
use crate::services::{
    self, AvoidanceRequest, ConnectivityRequest, CorridorRequest, CorridorResult,
    PathRequest, PathfindingService,
};
use crate::pipeline::PathResult;

pub struct DetourPathfinder {
    manager: Arc<MmapManager>,
}

impl DetourPathfinder {
    pub fn new(manager: Arc<MmapManager>) -> Self {
        Self { manager }
    }
}

impl PathfindingService for DetourPathfinder {
    fn find_path(&self, req: PathRequest) -> Result<PathResult, AppError> {
        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let mut custom_filter_storage = None;
        let filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

        pathfind_maybe_avoid(&query, &pool, filter, req.start, req.end, &req.options, &[])
    }

    fn find_path_with_avoidance(&self, req: AvoidanceRequest) -> Result<PathResult, AppError> {
        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let mut custom_filter_storage = None;
        let filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

        pathfind_maybe_avoid(&query, &pool, filter, req.start, req.end, &req.options, &req.zones)
    }

    fn find_corridor(&self, req: CorridorRequest) -> Result<CorridorResult, AppError> {
        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let mut custom_filter_storage = None;
        let filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

        let path = pathfind_maybe_avoid(&query, &pool, filter, req.start, req.end, &req.options, &[])?;
        let corridor_widths = compute_corridor_widths(&path.waypoints, &query, filter, req.probe_distance);

        Ok(CorridorResult {
            path,
            corridor_widths,
        })
    }

    fn check_connectivity(&self, req: ConnectivityRequest) -> Result<Vec<bool>, AppError> {
        if req.waypoints.len() < 2 {
            return Ok(vec![]);
        }

        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        let mut results = Vec::with_capacity(req.waypoints.len() - 1);

        for pair in req.waypoints.windows(2) {
            let walkable = (|| -> Result<bool, AppError> {
                let (start_ref, _start_pos) = find_poly_tiered(&query, pool.mesh(), pair[0], filter, None)?;
                let (_end_ref, end_pos) = find_poly_tiered(&query, pool.mesh(), pair[1], filter, None)?;

                let _pathfind_guard = pool.pathfind_lock();
                match query.raycast(start_ref, pair[0], end_pos, filter) {
                    Ok((t, _)) => Ok(t >= 1.0),
                    Err(_) => Ok(false),
                }
            })();

            results.push(walkable.unwrap_or(false));
        }

        Ok(results)
    }
}
