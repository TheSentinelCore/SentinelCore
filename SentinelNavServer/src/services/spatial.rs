use std::sync::Arc;

use detour::types::Vec3;
use mmap_loader::error::MmapError;
use mmap_loader::MmapManager;

use crate::error::AppError;
use crate::pipeline::{find_poly_tiered, HEIGHT_EXTENTS};
use crate::services::{
    BatchHeightRequest, HeightRequest, HeightResult, MoveRequest, MoveResult, RandomPointRequest,
    RaycastRequest, RaycastResult, SpatialService,
};

pub struct DetourSpatial {
    manager: Arc<MmapManager>,
}

impl DetourSpatial {
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

impl SpatialService for DetourSpatial {
    fn raycast(&self, req: RaycastRequest) -> Result<RaycastResult, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        let (start_ref, start_nearest) =
            find_poly_tiered(&query, pool.mesh(), req.start, filter, None)?;

        let _guard = pool.pathfind_lock();
        let (t, _hit_normal) = query
            .raycast(start_ref, start_nearest, req.end, filter)
            .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

        let hit = t < 1.0;
        let full_dist = start_nearest.distance(&req.end);
        let hit_position = if hit {
            Vec3::new(
                start_nearest.x + t * (req.end.x - start_nearest.x),
                start_nearest.y + t * (req.end.y - start_nearest.y),
                start_nearest.z + t * (req.end.z - start_nearest.z),
            )
        } else {
            req.end
        };

        Ok(RaycastResult {
            hit,
            t,
            hit_distance: t * full_dist,
            hit_position,
        })
    }

    fn get_height(&self, req: HeightRequest) -> Result<HeightResult, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        let pos = Vec3::new(req.x, req.y, req.z);
        match query.find_nearest_poly(pos, HEIGHT_EXTENTS, filter) {
            Ok((_poly_ref, snapped)) => Ok(HeightResult {
                x: req.x,
                y: req.y,
                z: snapped.z,
                found: true,
            }),
            Err(_) => Ok(HeightResult {
                x: req.x,
                y: req.y,
                z: req.z,
                found: false,
            }),
        }
    }

    fn get_heights(&self, req: BatchHeightRequest) -> Result<Vec<HeightResult>, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        let mut results = Vec::with_capacity(req.positions.len());
        for pos in &req.positions {
            let result = match query.find_nearest_poly(*pos, HEIGHT_EXTENTS, filter) {
                Ok((_poly_ref, snapped)) => HeightResult {
                    x: pos.x,
                    y: pos.y,
                    z: snapped.z,
                    found: true,
                },
                Err(_) => HeightResult {
                    x: pos.x,
                    y: pos.y,
                    z: pos.z,
                    found: false,
                },
            };
            results.push(result);
        }
        Ok(results)
    }

    fn random_point(&self, req: RandomPointRequest) -> Result<Vec3, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        let (center_ref, center_nearest) =
            find_poly_tiered(&query, pool.mesh(), req.center, filter, None)?;

        let (_poly_ref, random_pos) = query
            .find_random_point_around_circle(center_ref, center_nearest, req.radius, filter)
            .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

        Ok(random_pos)
    }

    fn move_along_surface(&self, req: MoveRequest) -> Result<MoveResult, AppError> {
        let pool = self.acquire(req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        let (start_ref, start_nearest) =
            find_poly_tiered(&query, pool.mesh(), req.start, filter, None)?;

        let result_pos = query
            .move_along_surface(start_ref, start_nearest, req.end, filter)
            .map_err(|e| AppError::PathfindingFailed(e.to_string()))?;

        Ok(MoveResult {
            position: result_pos,
            visited_count: 0,
        })
    }
}
