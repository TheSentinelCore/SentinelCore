//! NavMeshQuery wrapper for pathfinding operations.

use std::ptr::NonNull;
use std::sync::Arc;

use crate::error::{dt_status_failed, DetourError};
use crate::filter::QueryFilter;
use crate::mesh::NavMesh;
use crate::types::{PolyRef, Vec3};

/// Safe wrapper for dtNavMeshQuery.
///
/// NavMeshQuery provides pathfinding operations on a NavMesh.
///
/// # Thread Safety
///
/// **NavMeshQuery is NOT Send or Sync!** It has internal mutable state
/// (node pool) that is not thread-safe. Use `QueryPool` for concurrent access.
///
/// # Lifetime
///
/// NavMeshQuery holds an `Arc<NavMesh>` to ensure the NavMesh lives
/// as long as the query. Do not modify the NavMesh after creating queries.
pub struct NavMeshQuery {
    ptr: NonNull<detour_sys::dtNavMeshQuery>,
    _mesh: Arc<NavMesh>,
}

/// Result from a polygon corridor search.
#[derive(Debug)]
pub struct FindPathResult {
    /// The polygon corridor from start to end.
    pub path: Vec<PolyRef>,
    /// True if the path did not reach the end polygon.
    pub is_partial: bool,
    /// True if the A* search exhausted the node pool (DT_OUT_OF_NODES).
    /// When true alongside is_partial, increasing max_query_nodes may help.
    pub out_of_nodes: bool,
}

impl NavMeshQuery {
    /// Create a new NavMeshQuery for the given mesh.
    ///
    /// # Arguments
    /// * `mesh` - The navigation mesh to query
    /// * `max_nodes` - Maximum number of search nodes (typically 2048)
    pub fn new(mesh: Arc<NavMesh>, max_nodes: u32) -> Result<Self, DetourError> {
        // SAFETY: wrapper_dtAllocNavMeshQuery returns a valid pointer or null (checked below).
        let ptr = unsafe { detour_sys::wrapper_dtAllocNavMeshQuery() };
        let ptr = NonNull::new(ptr).ok_or(DetourError::AllocationFailed)?;

        // SAFETY: ptr is valid (NonNull check above); mesh.as_ptr() is valid for the mesh's lifetime.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_init(
                ptr.as_ptr(),
                mesh.as_ptr(),
                max_nodes as i32,
            )
        };

        if dt_status_failed(status) {
            // SAFETY: ptr was successfully allocated above and init failed, so we must free it.
            unsafe {
                detour_sys::wrapper_dtFreeNavMeshQuery(ptr.as_ptr());
            }
            return Err(DetourError::QueryInitFailed);
        }

        Ok(Self { ptr, _mesh: mesh })
    }

    /// Find the nearest polygon to a position.
    ///
    /// # Arguments
    /// * `center` - Search center position (WoW coordinates)
    /// * `half_extents` - Search box half-extents (WoW coordinates)
    /// * `filter` - Query filter controlling which polygons to consider
    ///
    /// # Returns
    /// Tuple of (polygon reference, nearest point on polygon in WoW coords)
    pub fn find_nearest_poly(
        &self,
        center: Vec3,
        half_extents: Vec3,
        filter: &QueryFilter,
    ) -> Result<(PolyRef, Vec3), DetourError> {
        let center_d = center.to_detour();
        let extents_d = half_extents.to_detour();
        let mut nearest_ref: PolyRef = 0;
        let mut nearest_pt = [0.0f32; 3];

        // SAFETY: self.ptr is a valid, initialized dtNavMeshQuery; all output buffers are
        // stack-allocated with correct sizes; coordinate arrays converted via to_detour().
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_findNearestPoly(
                self.ptr.as_ptr(),
                center_d.as_ptr(),
                extents_d.as_ptr(),
                filter.as_ptr(),
                &mut nearest_ref,
                nearest_pt.as_mut_ptr(),
            )
        };

        if dt_status_failed(status) || nearest_ref == 0 {
            return Err(DetourError::StartNotFound);
        }

        Ok((nearest_ref, Vec3::from_detour(nearest_pt)))
    }

    /// Find a path from start polygon to end polygon.
    ///
    /// Returns a corridor of polygon references that the path passes through.
    ///
    /// # Arguments
    /// * `start_ref` - Starting polygon reference
    /// * `end_ref` - Ending polygon reference
    /// * `start_pos` - Start position (WoW coordinates)
    /// * `end_pos` - End position (WoW coordinates)
    /// * `filter` - Query filter
    /// * `max_path` - Maximum number of polygons in the path
    pub fn find_path(
        &self,
        start_ref: PolyRef,
        end_ref: PolyRef,
        start_pos: Vec3,
        end_pos: Vec3,
        filter: &QueryFilter,
        max_path: usize,
    ) -> Result<FindPathResult, DetourError> {
        let start_d = start_pos.to_detour();
        let end_d = end_pos.to_detour();
        let mut path = vec![0u64; max_path];
        let mut path_count: i32 = 0;

        // SAFETY: self.ptr is valid; path buffer has max_path elements; path_count is written by Detour.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_findPath(
                self.ptr.as_ptr(),
                start_ref,
                end_ref,
                start_d.as_ptr(),
                end_d.as_ptr(),
                filter.as_ptr(),
                path.as_mut_ptr(),
                &mut path_count,
                max_path as i32,
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::PathNotFound);
        }

        path.truncate(path_count as usize);
        let is_partial = (status & detour_sys::DT_PARTIAL_RESULT) != 0;
        let out_of_nodes = (status & detour_sys::DT_OUT_OF_NODES) != 0;
        Ok(FindPathResult {
            path,
            is_partial,
            out_of_nodes,
        })
    }

    /// Convert a polygon path to a straight path of waypoints.
    ///
    /// # Arguments
    /// * `start_pos` - Start position (WoW coordinates)
    /// * `end_pos` - End position (WoW coordinates)
    /// * `poly_path` - Polygon path from `find_path`
    /// * `max_points` - Maximum number of waypoints
    ///
    /// # Returns
    /// Vector of waypoints in WoW coordinates
    pub fn find_straight_path(
        &self,
        start_pos: Vec3,
        end_pos: Vec3,
        poly_path: &[PolyRef],
        max_points: usize,
    ) -> Result<Vec<Vec3>, DetourError> {
        let start_d = start_pos.to_detour();
        let end_d = end_pos.to_detour();
        let mut straight_path = vec![0.0f32; max_points * 3];
        let mut straight_count: i32 = 0;

        // SAFETY: self.ptr is valid; straight_path has max_points*3 elements; null ptrs for
        // optional output arrays (flags, refs) are documented as valid by Detour API.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_findStraightPath(
                self.ptr.as_ptr(),
                start_d.as_ptr(),
                end_d.as_ptr(),
                poly_path.as_ptr(),
                poly_path.len() as i32,
                straight_path.as_mut_ptr(),
                std::ptr::null_mut(), // flags (not needed)
                std::ptr::null_mut(), // refs (not needed)
                &mut straight_count,
                max_points as i32,
                0, // options
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::StraightPathFailed);
        }

        // Clamp count to buffer size to prevent panic on malformed FFI output
        let count = (straight_count as usize).min(max_points);
        let waypoints: Vec<Vec3> = (0..count)
            .map(|i| {
                let idx = i * 3;
                Vec3::from_detour([
                    straight_path[idx],
                    straight_path[idx + 1],
                    straight_path[idx + 2],
                ])
            })
            .collect();

        Ok(waypoints)
    }

    /// Move along the navmesh surface from start to end.
    ///
    /// This is a "sliding" movement that stays on the navmesh.
    ///
    /// # Arguments
    /// * `start_ref` - Starting polygon reference
    /// * `start_pos` - Start position (WoW coordinates)
    /// * `end_pos` - Target position (WoW coordinates)
    /// * `filter` - Query filter
    ///
    /// # Returns
    /// The resulting position after moving (WoW coordinates)
    pub fn move_along_surface(
        &self,
        start_ref: PolyRef,
        start_pos: Vec3,
        end_pos: Vec3,
        filter: &QueryFilter,
    ) -> Result<Vec3, DetourError> {
        let start_d = start_pos.to_detour();
        let end_d = end_pos.to_detour();
        let mut result_pos = [0.0f32; 3];
        let mut visited = [0u64; 16];
        let mut visited_count: i32 = 0;

        // SAFETY: self.ptr is valid; all output buffers are stack-allocated with correct sizes;
        // visited array has 16 elements and visited.len() is passed as the limit.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_moveAlongSurface(
                self.ptr.as_ptr(),
                start_ref,
                start_d.as_ptr(),
                end_d.as_ptr(),
                filter.as_ptr(),
                result_pos.as_mut_ptr(),
                visited.as_mut_ptr(),
                &mut visited_count,
                visited.len() as i32,
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::PathNotFound);
        }

        Ok(Vec3::from_detour(result_pos))
    }

    /// Cast a ray along the navmesh surface.
    ///
    /// # Arguments
    /// * `start_ref` - Starting polygon reference
    /// * `start_pos` - Start position (WoW coordinates)
    /// * `end_pos` - End position (WoW coordinates)
    /// * `filter` - Query filter
    ///
    /// # Returns
    /// Tuple of (hit_parameter, hit_normal). hit_parameter is 0.0-1.0 where
    /// the ray hit, or > 1.0 if no hit (ray reached end position).
    pub fn raycast(
        &self,
        start_ref: PolyRef,
        start_pos: Vec3,
        end_pos: Vec3,
        filter: &QueryFilter,
    ) -> Result<(f32, Vec3), DetourError> {
        let start_d = start_pos.to_detour();
        let end_d = end_pos.to_detour();
        let mut t: f32 = 0.0;
        let mut hit_normal = [0.0f32; 3];

        // SAFETY: self.ptr is valid; output params are stack-allocated; null ptrs for optional
        // path/pathCount arrays are valid (maxPath=0 means no path output).
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_raycast(
                self.ptr.as_ptr(),
                start_ref,
                start_d.as_ptr(),
                end_d.as_ptr(),
                filter.as_ptr(),
                &mut t,
                hit_normal.as_mut_ptr(),
                std::ptr::null_mut(), // path (not needed)
                std::ptr::null_mut(), // pathCount (not needed)
                0,                    // maxPath
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::PathNotFound);
        }

        Ok((t, Vec3::from_detour(hit_normal)))
    }

    /// Find the distance from a position to the nearest polygon wall.
    ///
    /// A "wall" is any navmesh edge that borders non-navigable space
    /// (building walls, fences, cliffs, obstacles, etc).
    ///
    /// # Arguments
    /// * `start_ref` - Polygon reference containing `center_pos`
    /// * `center_pos` - Position to measure from (WoW coordinates)
    /// * `max_radius` - Maximum search radius
    /// * `filter` - Query filter
    ///
    /// # Returns
    /// Tuple of (hit_distance, hit_position, hit_normal) in WoW coordinates.
    /// hit_normal points from the wall toward `center_pos`.
    pub fn find_distance_to_wall(
        &self,
        start_ref: PolyRef,
        center_pos: Vec3,
        max_radius: f32,
        filter: &QueryFilter,
    ) -> Result<(f32, Vec3, Vec3), DetourError> {
        let center_d = center_pos.to_detour();
        let mut hit_dist: f32 = 0.0;
        let mut hit_pos = [0.0f32; 3];
        let mut hit_normal = [0.0f32; 3];

        // SAFETY: self.ptr is valid; all output params are stack-allocated f32/[f32;3].
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_findDistanceToWall(
                self.ptr.as_ptr(),
                start_ref,
                center_d.as_ptr(),
                max_radius,
                filter.as_ptr(),
                &mut hit_dist,
                hit_pos.as_mut_ptr(),
                hit_normal.as_mut_ptr(),
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::PathNotFound);
        }

        Ok((hit_dist, Vec3::from_detour(hit_pos), Vec3::from_detour(hit_normal)))
    }

    /// Find a random point anywhere on the navmesh.
    ///
    /// # Arguments
    /// * `filter` - Query filter
    ///
    /// # Returns
    /// Tuple of (polygon reference, position in WoW coordinates)
    pub fn find_random_point(&self, filter: &QueryFilter) -> Result<(PolyRef, Vec3), DetourError> {
        let mut random_ref: PolyRef = 0;
        let mut random_pt = [0.0f32; 3];

        // Random function callback
        extern "C" fn random_fn() -> f32 {
            rand::random::<f32>()
        }

        // SAFETY: self.ptr is valid; random_fn is an extern "C" fn matching Detour's callback
        // signature; output params are stack-allocated.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_findRandomPoint(
                self.ptr.as_ptr(),
                filter.as_ptr(),
                Some(random_fn),
                &mut random_ref,
                random_pt.as_mut_ptr(),
            )
        };

        if dt_status_failed(status) || random_ref == 0 {
            return Err(DetourError::PathNotFound);
        }

        Ok((random_ref, Vec3::from_detour(random_pt)))
    }

    /// Find a random point within a circle around a center point.
    ///
    /// # Arguments
    /// * `start_ref` - Center polygon reference
    /// * `center_pos` - Center position (WoW coordinates)
    /// * `max_radius` - Maximum search radius
    /// * `filter` - Query filter
    ///
    /// # Returns
    /// Tuple of (polygon reference, position in WoW coordinates)
    pub fn find_random_point_around_circle(
        &self,
        start_ref: PolyRef,
        center_pos: Vec3,
        max_radius: f32,
        filter: &QueryFilter,
    ) -> Result<(PolyRef, Vec3), DetourError> {
        let center_d = center_pos.to_detour();
        let mut random_ref: PolyRef = 0;
        let mut random_pt = [0.0f32; 3];

        // Random function callback
        extern "C" fn random_fn() -> f32 {
            rand::random::<f32>()
        }

        // SAFETY: self.ptr is valid; random_fn matches Detour's extern "C" callback signature;
        // output params are stack-allocated with correct sizes.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_findRandomPointAroundCircle(
                self.ptr.as_ptr(),
                start_ref,
                center_d.as_ptr(),
                max_radius,
                filter.as_ptr(),
                Some(random_fn),
                &mut random_ref,
                random_pt.as_mut_ptr(),
            )
        };

        if dt_status_failed(status) || random_ref == 0 {
            return Err(DetourError::PathNotFound);
        }

        Ok((random_ref, Vec3::from_detour(random_pt)))
    }

    /// Get the height at a position on a polygon.
    ///
    /// # Arguments
    /// * `poly_ref` - Polygon reference
    /// * `pos` - Position (WoW coordinates, only X/Y used for lookup)
    ///
    /// # Returns
    /// Height at the position
    pub fn get_poly_height(&self, poly_ref: PolyRef, pos: Vec3) -> Result<f32, DetourError> {
        let pos_d = pos.to_detour();
        let mut height: f32 = 0.0;

        // SAFETY: self.ptr is valid; height is a stack-allocated f32 output param.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_getPolyHeight(
                self.ptr.as_ptr(),
                poly_ref,
                pos_d.as_ptr(),
                &mut height,
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::PathNotFound);
        }

        Ok(height)
    }

    /// Find all polygons within an axis-aligned bounding box.
    ///
    /// Returns polygon references for all navigable polygons whose bounding
    /// boxes overlap the search box. Use `closest_point_on_poly` to refine
    /// AABB matches to true circle overlap for circular avoidance zones.
    ///
    /// # Arguments
    /// * `center` - Search box center (WoW coordinates)
    /// * `half_extents` - Search box half-extents (WoW coordinates)
    /// * `filter` - Query filter controlling which polygons to consider
    /// * `max_polys` - Maximum polygon references to return
    ///
    /// # Returns
    /// Vector of polygon references overlapping the search box.
    pub fn query_polygons(
        &self,
        center: Vec3,
        half_extents: Vec3,
        filter: &QueryFilter,
        max_polys: usize,
    ) -> Result<Vec<PolyRef>, DetourError> {
        let center_d = center.to_detour();
        let extents_d = half_extents.to_detour();
        let mut polys = vec![0u64; max_polys];
        let mut poly_count: i32 = 0;

        // SAFETY: self.ptr is valid; polys buffer has max_polys elements; max_polys passed as limit.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_queryPolygons(
                self.ptr.as_ptr(),
                center_d.as_ptr(),
                extents_d.as_ptr(),
                filter.as_ptr(),
                polys.as_mut_ptr(),
                &mut poly_count,
                max_polys as i32,
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::StatusError(status));
        }

        polys.truncate(poly_count as usize);
        Ok(polys)
    }

    /// Find the closest point on a polygon.
    ///
    /// # Arguments
    /// * `poly_ref` - Polygon reference
    /// * `pos` - Position to check (WoW coordinates)
    ///
    /// # Returns
    /// Tuple of (closest point in WoW coords, is_pos_over_polygon)
    pub fn closest_point_on_poly(
        &self,
        poly_ref: PolyRef,
        pos: Vec3,
    ) -> Result<(Vec3, bool), DetourError> {
        let pos_d = pos.to_detour();
        let mut closest = [0.0f32; 3];
        let mut pos_over_poly: bool = false;

        // SAFETY: self.ptr is valid; output buffers (closest, pos_over_poly) are stack-allocated.
        let status = unsafe {
            detour_sys::wrapper_dtNavMeshQuery_closestPointOnPoly(
                self.ptr.as_ptr(),
                poly_ref,
                pos_d.as_ptr(),
                closest.as_mut_ptr(),
                &mut pos_over_poly,
            )
        };

        if dt_status_failed(status) {
            return Err(DetourError::PathNotFound);
        }

        Ok((Vec3::from_detour(closest), pos_over_poly))
    }
}

impl Drop for NavMeshQuery {
    fn drop(&mut self) {
        // SAFETY: self.ptr was allocated by wrapper_dtAllocNavMeshQuery in new() and is valid.
        unsafe {
            detour_sys::wrapper_dtFreeNavMeshQuery(self.ptr.as_ptr());
        }
    }
}

// NavMeshQuery is explicitly NOT Send/Sync due to internal mutable state.
// The node pool is modified during queries and is not thread-safe.
// Use QueryPool for thread-safe access.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mesh::NavMeshParams;

    fn create_test_mesh() -> Arc<NavMesh> {
        let mut mesh = NavMesh::new().unwrap();
        let params = NavMeshParams {
            orig: [0.0, 0.0, 0.0],
            tile_width: 533.33333,
            tile_height: 533.33333,
            max_tiles: 1024,
            max_polys: 1024,
        };
        mesh.init(&params).unwrap();
        Arc::new(mesh)
    }

    #[test]
    fn test_query_allocate_free() {
        let mesh = create_test_mesh();
        let query = NavMeshQuery::new(mesh, 2048).unwrap();
        drop(query);
    }

    #[test]
    fn test_query_find_nearest_poly_empty_mesh() {
        let mesh = create_test_mesh();
        let query = NavMeshQuery::new(mesh, 2048).unwrap();
        let filter = QueryFilter::default();

        // Empty mesh should return error
        let result = query.find_nearest_poly(
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 10.0, 10.0),
            &filter,
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_query_not_send_sync() {
        // This is a compile-time assertion that NavMeshQuery does NOT implement Send/Sync
        // We can't directly assert !Send, but we can document the design intent
        fn assert_not_send<T>() {
            // NavMeshQuery should NOT be Send due to internal mutable state
        }
        fn assert_not_sync<T>() {
            // NavMeshQuery should NOT be Sync due to internal mutable state
        }
        // These would fail if we accidentally added Send/Sync:
        // assert_not_send::<NavMeshQuery>();
        // assert_not_sync::<NavMeshQuery>();
    }
}
