use std::sync::Arc;

use mmap_loader::error::MmapError;
use mmap_loader::MmapManager;

use crate::error::AppError;
use crate::pipeline::{
    compute_corridor_widths, find_poly_tiered, has_custom_filter, create_custom_filter,
    pathfind_maybe_avoid,
};
use crate::services::{
    AvoidanceRequest, ConnectivityRequest, CorridorRequest, CorridorResult,
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
}

impl PathfindingService for DetourPathfinder {
    fn find_path(&self, req: PathRequest) -> Result<PathResult, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let custom_filter;
        let filter = if has_custom_filter(req.options.filter_ground, req.options.filter_water, req.options.filter_lava) {
            custom_filter = create_custom_filter(req.options.filter_ground, req.options.filter_water, req.options.filter_lava)?;
            &custom_filter
        } else {
            pool.filter()
        };

        pathfind_maybe_avoid(&query, &pool, filter, req.start, req.end, &req.options, &[])
    }

    fn find_path_with_avoidance(&self, req: AvoidanceRequest) -> Result<PathResult, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let custom_filter;
        let filter = if has_custom_filter(req.options.filter_ground, req.options.filter_water, req.options.filter_lava) {
            custom_filter = create_custom_filter(req.options.filter_ground, req.options.filter_water, req.options.filter_lava)?;
            &custom_filter
        } else {
            pool.filter()
        };

        pathfind_maybe_avoid(&query, &pool, filter, req.start, req.end, &req.options, &req.zones)
    }

    fn find_corridor(&self, req: CorridorRequest) -> Result<CorridorResult, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let custom_filter;
        let filter = if has_custom_filter(req.options.filter_ground, req.options.filter_water, req.options.filter_lava) {
            custom_filter = create_custom_filter(req.options.filter_ground, req.options.filter_water, req.options.filter_lava)?;
            &custom_filter
        } else {
            pool.filter()
        };

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

        let pool = self.acquire(req.map_id)?;
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
