//! Avoidance pathfinding: stamp navmesh polygons to route around zones.

use detour::filter::{
    NAV_AREA_AVOID, NAV_AREA_GROUND, NAV_AREA_GROUND_STEEP, NAV_AREA_MAGMA_SLIME, NAV_AREA_WATER,
    QueryFilter, QueryFilterBuilder,
};
use detour::mesh::NavMesh;
use detour::query::NavMeshQuery;
use detour::types::{PolyRef, Vec3};

use crate::error::AppError;

use super::pathfinding::{execute_pathfind, execute_pathfind_raw};

/// Maximum polygons returned by queryPolygons per avoidance zone.
const MAX_QUERY_POLYS_PER_ZONE: usize = 512;

/// An avoidance zone that paths should route around.
#[derive(Debug, Clone)]
pub struct AvoidanceZone {
    pub center: Vec3,
    pub radius: f32,
    pub cost_multiplier: f32,
}

/// RAII guard that restores polygon area types on drop.
///
/// Ensures the shared NavMesh is returned to its original state
/// even if pathfinding panics or returns early via `?`.
struct AreaRestoreGuard<'a> {
    mesh: &'a NavMesh,
    originals: Vec<(PolyRef, u8)>,
}

impl<'a> AreaRestoreGuard<'a> {
    fn new(mesh: &'a NavMesh) -> Self {
        Self {
            mesh,
            originals: Vec::new(),
        }
    }

    /// Record original area and set polygon to avoidance area type.
    fn stamp_polygon(&mut self, poly_ref: PolyRef, new_area: u8) -> Result<(), AppError> {
        let original = self
            .mesh
            .get_poly_area(poly_ref)
            .map_err(|e| AppError::Internal(format!("get_poly_area failed: {e}")))?;
        self.mesh
            .set_poly_area(poly_ref, new_area)
            .map_err(|e| AppError::Internal(format!("set_poly_area failed: {e}")))?;
        self.originals.push((poly_ref, original));
        Ok(())
    }
}

impl Drop for AreaRestoreGuard<'_> {
    fn drop(&mut self) {
        for &(poly_ref, original_area) in &self.originals {
            if let Err(e) = self.mesh.set_poly_area(poly_ref, original_area) {
                tracing::error!("Failed to restore poly area for ref {poly_ref}: {e}");
            }
        }
    }
}

/// Stamp avoidance zones on the navmesh and build a filter with high NAV_AREA_AVOID cost.
///
/// Returns the RAII guard (which restores polygon areas on drop) and the avoidance filter.
fn stamp_and_build_filter<'a>(
    mesh: &'a NavMesh,
    query: &NavMeshQuery,
    base_filter: &QueryFilter,
    zones: &[AvoidanceZone],
) -> Result<(AreaRestoreGuard<'a>, QueryFilter), AppError> {
    let mut guard = AreaRestoreGuard::new(mesh);
    let avoid_cost = zones
        .iter()
        .map(|z| z.cost_multiplier)
        .fold(1.0f32, f32::max);

    // Use default filter for polygon search (include all walkable areas)
    let search_filter = QueryFilter::default();

    for zone in zones {
        let half_extents = Vec3::new(zone.radius, zone.radius, 50.0);

        let poly_refs = match query.query_polygons(
            zone.center,
            half_extents,
            &search_filter,
            MAX_QUERY_POLYS_PER_ZONE,
        ) {
            Ok(refs) => refs,
            Err(e) => {
                tracing::warn!(
                    "queryPolygons failed for zone at {:?}: {e}",
                    zone.center
                );
                continue;
            }
        };

        // Refine AABB to circle: check polygon's closest point distance
        for poly_ref in &poly_refs {
            let (closest, _) = match query.closest_point_on_poly(*poly_ref, zone.center) {
                Ok(result) => result,
                Err(_) => continue,
            };

            if closest.distance_2d(&zone.center) <= zone.radius {
                // Only stamp if not already stamped (prevent double-stamp from overlapping zones)
                let current_area = match mesh.get_poly_area(*poly_ref) {
                    Ok(a) => a,
                    Err(_) => continue,
                };
                if current_area != NAV_AREA_AVOID {
                    guard.stamp_polygon(*poly_ref, NAV_AREA_AVOID)?;
                }
            }
        }
    }

    // Build filter with high cost for avoidance area
    let avoidance_filter = QueryFilterBuilder::new()
        .area_cost(NAV_AREA_GROUND, base_filter.area_cost(NAV_AREA_GROUND))
        .area_cost(
            NAV_AREA_GROUND_STEEP,
            base_filter.area_cost(NAV_AREA_GROUND_STEEP),
        )
        .area_cost(NAV_AREA_WATER, base_filter.area_cost(NAV_AREA_WATER))
        .area_cost(
            NAV_AREA_MAGMA_SLIME,
            base_filter.area_cost(NAV_AREA_MAGMA_SLIME),
        )
        .area_cost(NAV_AREA_AVOID, avoid_cost)
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to create avoidance filter: {e}")))?;

    Ok((guard, avoidance_filter))
}

/// Execute pathfinding with avoidance zones integrated into the A* cost model.
///
/// Instead of post-processing waypoints, this function temporarily stamps
/// navmesh polygons inside zones with `NAV_AREA_AVOID` (area 63) at high cost,
/// causing Detour's A* to naturally route around them.
///
/// # Thread Safety
///
/// Caller MUST hold the `QueryPool::avoidance_lock()` for the entire duration.
#[allow(clippy::too_many_arguments)]
pub fn execute_pathfind_with_avoidance(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    base_filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &super::PathOptions,
    zones: &[AvoidanceZone],
    _avoidance_proof: &parking_lot::RwLockWriteGuard<'_, ()>,
) -> Result<super::PathResult, AppError> {
    if zones.is_empty() {
        return execute_pathfind(query, mesh, base_filter, start_pos, end_pos, options);
    }

    let (guard, avoidance_filter) = stamp_and_build_filter(mesh, query, base_filter, zones)?;

    tracing::info!(
        "Avoidance: stamped {} polygons across {} zones",
        guard.originals.len(),
        zones.len(),
    );

    // guard drops after this, restoring all original polygon areas
    execute_pathfind(query, mesh, &avoidance_filter, start_pos, end_pos, options)
}

/// Raw variant of `execute_pathfind_with_avoidance` — stamps avoidance polygons
/// but returns raw waypoints without post-processing (no string-pull, densify, wall_clearance).
#[allow(clippy::too_many_arguments)]
pub fn execute_pathfind_with_avoidance_raw(
    query: &NavMeshQuery,
    mesh: &NavMesh,
    base_filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &super::PathOptions,
    zones: &[AvoidanceZone],
    _avoidance_proof: &parking_lot::RwLockWriteGuard<'_, ()>,
) -> Result<super::PathResult, AppError> {
    if zones.is_empty() {
        return execute_pathfind_raw(query, mesh, base_filter, start_pos, end_pos, options);
    }

    let (_guard, avoidance_filter) = stamp_and_build_filter(mesh, query, base_filter, zones)?;

    execute_pathfind_raw(query, mesh, &avoidance_filter, start_pos, end_pos, options)
}

/// Pathfind with optional avoidance zones.
///
/// If `zones` is empty, delegates to `execute_pathfind`.
/// Otherwise, acquires the avoidance lock and calls `execute_pathfind_with_avoidance`.
pub fn pathfind_maybe_avoid(
    query: &NavMeshQuery,
    pool: &detour::pool::QueryPool,
    filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &super::PathOptions,
    zones: &[AvoidanceZone],
) -> Result<super::PathResult, AppError> {
    if zones.is_empty() {
        let _pathfind_guard = pool.pathfind_lock();
        execute_pathfind(query, pool.mesh(), filter, start_pos, end_pos, options)
    } else {
        let guard = pool.avoidance_lock();
        execute_pathfind_with_avoidance(
            query,
            pool.mesh(),
            filter,
            start_pos,
            end_pos,
            options,
            zones,
            &guard,
        )
    }
}

/// Pathfind returning raw waypoints (no string-pull, densify, or wall_clearance).
///
/// Used by multi-leg endpoints that concatenate raw legs before applying
/// `post_process_path` to the full combined path.
pub fn pathfind_maybe_avoid_raw(
    query: &NavMeshQuery,
    pool: &detour::pool::QueryPool,
    filter: &QueryFilter,
    start_pos: Vec3,
    end_pos: Vec3,
    options: &super::PathOptions,
    zones: &[AvoidanceZone],
) -> Result<super::PathResult, AppError> {
    if zones.is_empty() {
        let _pathfind_guard = pool.pathfind_lock();
        execute_pathfind_raw(query, pool.mesh(), filter, start_pos, end_pos, options)
    } else {
        let guard = pool.avoidance_lock();
        execute_pathfind_with_avoidance_raw(
            query,
            pool.mesh(),
            filter,
            start_pos,
            end_pos,
            options,
            zones,
            &guard,
        )
    }
}
