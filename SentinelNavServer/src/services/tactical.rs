//! Concrete `TacticalService` implementation backed by Detour navmesh queries.

use std::sync::Arc;

use detour::types::Vec3;
use mmap_loader::MmapManager;

use crate::error::AppError;
use crate::pipeline::{
    apply_wall_clearance, resolve_filter,
    pathfind_maybe_avoid, PathResult, SEARCH_EXTENTS, HEIGHT_EXTENTS,
};
use crate::services::{
    self, CoverPosition, CoverRequest, CoverResult, FleeRequest, FleeResult,
    KiteRequest, KiteResult, TacticalService,
};

/// Tactical service backed by Detour navmesh queries.
pub struct DetourTactical {
    manager: Arc<MmapManager>,
}

impl DetourTactical {
    pub fn new(manager: Arc<MmapManager>) -> Self {
        Self { manager }
    }
}

impl TacticalService for DetourTactical {
    fn flee(&self, req: FleeRequest) -> Result<FleeResult, AppError> {
        if req.threats.is_empty() {
            return Err(AppError::InvalidParams("At least one threat required".into()));
        }

        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let mut custom_filter_storage = None;
        let filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

        // Compute threat centroid
        let centroid = {
            let mut cx = 0.0f32;
            let mut cy = 0.0f32;
            let mut cz = 0.0f32;
            for t in &req.threats {
                cx += t.x;
                cy += t.y;
                cz += t.z;
            }
            let n = req.threats.len() as f32;
            Vec3::new(cx / n, cy / n, cz / n)
        };

        // Flee vector: direction away from threat centroid
        let flee_dir = {
            let dx = req.player_pos.x - centroid.x;
            let dy = req.player_pos.y - centroid.y;
            let len = (dx * dx + dy * dy).sqrt();
            if len > 0.001 {
                (dx / len, dy / len)
            } else {
                (1.0, 0.0) // Arbitrary direction if player is at centroid
            }
        };

        // Try flee path at several rotated angles
        let angles = [0.0_f32, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0];
        let mut best_result: Option<PathResult> = None;
        let mut best_flee_point = req.player_pos;
        let mut best_min_threat_dist = 0.0f32;

        for &angle_deg in &angles {
            let angle_rad = angle_deg.to_radians();
            let rotated_x = flee_dir.0 * angle_rad.cos() - flee_dir.1 * angle_rad.sin();
            let rotated_y = flee_dir.0 * angle_rad.sin() + flee_dir.1 * angle_rad.cos();

            let target = Vec3::new(
                req.player_pos.x + rotated_x * req.flee_distance,
                req.player_pos.y + rotated_y * req.flee_distance,
                req.player_pos.z,
            );

            // Snap target to navmesh
            if let Ok((_, snapped)) = query.find_nearest_poly(target, SEARCH_EXTENTS, filter) {
                if let Ok(result) = pathfind_maybe_avoid(
                    &query, &pool, filter, req.player_pos, snapped, &req.options, &[],
                ) {
                    // Score: minimum distance from any waypoint to any threat
                    let min_dist = result
                        .waypoints
                        .iter()
                        .flat_map(|wp: &Vec3| req.threats.iter().map(move |t| wp.distance_2d(t)))
                        .fold(f32::MAX, f32::min);

                    if best_result.is_none() || min_dist > best_min_threat_dist {
                        best_min_threat_dist = min_dist;
                        best_flee_point = snapped;
                        best_result = Some(result);
                    }
                }
            }
        }

        match best_result {
            Some(path) => Ok(FleeResult {
                path,
                flee_point: best_flee_point,
                distance_from_threat: best_min_threat_dist,
            }),
            None => Err(AppError::PathfindingFailed(
                "Could not find any flee path".into(),
            )),
        }
    }

    fn find_cover(&self, req: CoverRequest) -> Result<CoverResult, AppError> {
        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;
        let filter = pool.filter();

        // Find player polygon for random sampling
        let (player_ref, _) = query
            .find_nearest_poly(req.player_pos, SEARCH_EXTENTS, filter)
            .map_err(|_| AppError::PathfindingFailed("Player not on navmesh".into()))?;

        let threats = vec![req.threat_pos];

        // Sample candidate positions around the player
        let mut candidates: Vec<(Vec3, usize, f32)> = Vec::new();

        for _ in 0..req.num_samples {
            if let Ok((_, candidate)) = query.find_random_point_around_circle(
                player_ref,
                req.player_pos,
                req.search_radius,
                filter,
            ) {
                // For each candidate, raycast to each threat
                let mut blocked = 0usize;
                if let Ok((cand_ref, _)) =
                    query.find_nearest_poly(candidate, HEIGHT_EXTENTS, filter)
                {
                    for threat in &threats {
                        match query.raycast(cand_ref, candidate, *threat, filter) {
                            Ok((hit_t, _)) => {
                                if hit_t < 1.0 {
                                    blocked += 1; // Wall blocks LoS
                                }
                            }
                            Err(_) => {
                                blocked += 1; // Assume blocked if raycast fails
                            }
                        }
                    }
                }

                let dist = req.player_pos.distance_2d(&candidate);
                candidates.push((candidate, blocked, dist));
            }
        }

        // Sort: most threats blocked first, then by distance (closer = better)
        candidates.sort_by(|a, b| {
            b.1.cmp(&a.1)
                .then_with(|| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal))
        });

        // Build cover positions (only those that block at least 1 threat)
        let positions: Vec<CoverPosition> = candidates
            .into_iter()
            .filter(|(_, blocked, _)| *blocked > 0)
            .map(|(pos, _blocked, _dist)| CoverPosition {
                position: pos,
                distance_to_threat: req.threat_pos.distance_2d(&pos),
                has_los: false, // LoS is blocked (that's why it's cover)
            })
            .collect();

        // Pathfind to the best cover position if one exists
        let path = if let Some(best) = positions.first() {
            let mut custom_filter_storage = None;
            let pf_filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

            pathfind_maybe_avoid(
                &query,
                &pool,
                pf_filter,
                req.player_pos,
                best.position,
                &req.options,
                &[],
            )
            .ok()
        } else {
            None
        };

        Ok(CoverResult { positions, path })
    }

    fn kite(&self, req: KiteRequest) -> Result<KiteResult, AppError> {
        let pool = services::acquire(&self.manager, req.map_id)?;
        let query = pool.acquire().map_err(|e| AppError::Internal(e.to_string()))?;

        let mut custom_filter_storage = None;
        let filter = resolve_filter(pool.filter(), req.options.filter_ground, req.options.filter_water, req.options.filter_lava, &mut custom_filter_storage)?;

        // Compute current angle from threat to player
        let dx = req.player_pos.x - req.threat_pos.x;
        let dy = req.player_pos.y - req.threat_pos.y;
        let start_angle = dy.atan2(dx);

        // Generate arc waypoints
        let arc_rad = req.arc_angle.to_radians();
        let num_points = req.num_arc_points.max(3).min(36);

        let mut arc_points = Vec::with_capacity(num_points);

        for i in 0..num_points {
            let t = i as f32 / (num_points - 1) as f32;
            // Default: counter-clockwise (positive angle direction)
            let angle = start_angle + arc_rad * t;

            let point = Vec3::new(
                req.threat_pos.x + angle.cos() * req.desired_distance,
                req.threat_pos.y + angle.sin() * req.desired_distance,
                req.player_pos.z, // Use player height as initial guess
            );

            // Snap to navmesh
            let search = Vec3::new(
                req.desired_distance * 0.3,
                req.desired_distance * 0.3,
                50.0,
            );
            if let Ok((_, snapped)) = query.find_nearest_poly(point, search, filter) {
                arc_points.push(snapped);
            }
        }

        let mut waypoints = arc_points.clone();

        // Apply wall clearance if requested
        if let Some(clearance) = req.options.wall_clearance {
            if clearance > 0.0 {
                waypoints = apply_wall_clearance(&waypoints, &query, filter, clearance);
            }
        }

        // Compute total distance along the arc path
        let distance: f32 = waypoints
            .windows(2)
            .map(|w| w[0].distance(&w[1]))
            .sum();

        Ok(KiteResult {
            path: PathResult {
                waypoints,
                distance,
                partial: false,
                out_of_nodes: false,
            },
            arc_points,
        })
    }
}
