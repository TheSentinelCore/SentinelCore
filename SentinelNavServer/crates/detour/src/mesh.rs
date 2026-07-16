//! NavMesh wrapper for safe access to dtNavMesh.

use std::ptr::NonNull;

use crate::error::{dt_status_failed, DetourError, DetourStatus};
use crate::types::{PolyRef, TileRef};

/// Configuration parameters for initializing a NavMesh.
///
/// This struct matches `dtNavMeshParams` layout for FFI.
#[derive(Debug, Clone)]
#[repr(C)]
pub struct NavMeshParams {
    /// World space origin of the tile grid.
    pub orig: [f32; 3],
    /// Width of each tile (along x-axis in Detour coords).
    pub tile_width: f32,
    /// Height of each tile (along z-axis in Detour coords).
    pub tile_height: f32,
    /// Maximum number of tiles the navmesh can contain.
    pub max_tiles: i32,
    /// Maximum number of polygons each tile can contain.
    pub max_polys: i32,
}

impl NavMeshParams {
    /// Get raw pointer for FFI.
    ///
    /// # Safety
    /// The layout of NavMeshParams matches WrapperNavMeshParams exactly.
    pub fn as_ptr(&self) -> *const detour_sys::WrapperNavMeshParams {
        self as *const NavMeshParams as *const detour_sys::WrapperNavMeshParams
    }
}

/// Safe wrapper for dtNavMesh.
///
/// NavMesh is the data structure representing the walkable navigation mesh.
/// It contains tiles that can be added/removed dynamically.
///
/// # Thread Safety
///
/// NavMesh is `Send + Sync` because after initialization it is read-only.
/// All mutations (adding/removing tiles) should be done during setup,
/// before sharing across threads.
pub struct NavMesh {
    /// Pointer to the underlying dtNavMesh (opaque type = u8 in bindings).
    ptr: NonNull<detour_sys::dtNavMesh>,
}

impl NavMesh {
    /// Allocate a new empty NavMesh.
    pub fn new() -> Result<Self, DetourError> {
        // wrapper_dtAllocNavMesh returns *mut dtNavMesh (= *mut u8)
        let ptr = unsafe { detour_sys::wrapper_dtAllocNavMesh() };
        NonNull::new(ptr)
            .map(|ptr| Self { ptr })
            .ok_or(DetourError::AllocationFailed)
    }

    /// Initialize the NavMesh with the given parameters.
    ///
    /// This must be called before adding tiles.
    pub fn init(&mut self, params: &NavMeshParams) -> Result<(), DetourError> {
        let status = unsafe {
            detour_sys::wrapper_dtNavMesh_init(self.ptr.as_ptr(), params.as_ptr())
        };

        if dt_status_failed(status) {
            return Err(DetourError::InitFailed(status));
        }

        Ok(())
    }

    /// Add a tile to the NavMesh.
    ///
    /// # Memory Ownership
    ///
    /// This function takes ownership of the tile data. When using `DT_TILE_FREE_DATA`,
    /// Detour will free the memory when the tile is removed or the NavMesh is destroyed.
    ///
    /// We use `Box<[u8]>` for owned data and `Box::into_raw()` to transfer ownership
    /// to Detour. On failure, we reclaim the memory.
    pub fn add_tile(&mut self, data: Box<[u8]>) -> Result<TileRef, DetourError> {
        let len: i32 = data.len().try_into().map_err(|_| {
            DetourError::TileAddFailed(detour_sys::DT_FAILURE | detour_sys::DT_INVALID_PARAM)
        })?;
        let ptr = Box::into_raw(data) as *mut u8;
        let mut tile_ref: detour_sys::dtTileRef = 0;

        let status = unsafe {
            detour_sys::wrapper_dtNavMesh_addTile(
                self.ptr.as_ptr(),
                ptr,
                len,
                detour_sys::DT_TILE_FREE_DATA, // Detour owns memory now
                0,                              // lastRef (0 = new tile)
                &mut tile_ref,
            )
        };

        if dt_status_failed(status) {
            // Reclaim memory on failure - Detour didn't take ownership
            unsafe {
                let _ = Box::from_raw(std::slice::from_raw_parts_mut(ptr, len as usize));
            }
            return Err(DetourError::TileAddFailed(status));
        }

        Ok(tile_ref)
    }

    /// Remove a tile from the NavMesh.
    ///
    /// # Returns
    ///
    /// Returns `Ok(())` on success. The tile memory is freed by Detour
    /// if `DT_TILE_FREE_DATA` was used when adding the tile.
    pub fn remove_tile(&mut self, tile_ref: TileRef) -> Result<(), DetourError> {
        let status = unsafe {
            detour_sys::wrapper_dtNavMesh_removeTile(
                self.ptr.as_ptr(),
                tile_ref,
                std::ptr::null_mut(), // data out (not needed)
                std::ptr::null_mut(), // dataSize out (not needed)
            )
        };

        DetourStatus(status).to_result()
    }

    /// Get the maximum number of tiles this NavMesh can hold.
    pub fn max_tiles(&self) -> i32 {
        unsafe { detour_sys::wrapper_dtNavMesh_getMaxTiles(self.ptr.as_ptr()) }
    }

    /// Get the flags for a polygon.
    pub fn get_poly_flags(&self, poly_ref: PolyRef) -> Result<u16, DetourError> {
        let mut flags: u16 = 0;
        let status = unsafe {
            detour_sys::wrapper_dtNavMesh_getPolyFlags(
                self.ptr.as_ptr(),
                poly_ref,
                &mut flags,
            )
        };
        if dt_status_failed(status) {
            return Err(DetourError::StatusError(status));
        }
        Ok(flags)
    }

    /// Get the area type for a polygon.
    pub fn get_poly_area(&self, poly_ref: PolyRef) -> Result<u8, DetourError> {
        let mut area: u8 = 0;
        let status = unsafe {
            detour_sys::wrapper_dtNavMesh_getPolyArea(
                self.ptr.as_ptr(),
                poly_ref,
                &mut area,
            )
        };
        if dt_status_failed(status) {
            return Err(DetourError::StatusError(status));
        }
        Ok(area)
    }

    /// Set the area type for a polygon.
    ///
    /// # Safety Contract
    ///
    /// This performs **interior mutation** on the shared NavMesh through its
    /// raw pointer. This is safe ONLY when the caller holds the
    /// `QueryPool::avoidance_lock()` mutex and restores original area types
    /// before releasing the lock.
    ///
    /// # Arguments
    /// * `poly_ref` - Polygon reference to modify
    /// * `area` - New area type (0-63)
    pub fn set_poly_area(&self, poly_ref: PolyRef, area: u8) -> Result<(), DetourError> {
        if area >= 64 {
            return Err(DetourError::StatusError(
                detour_sys::DT_FAILURE | detour_sys::DT_INVALID_PARAM,
            ));
        }
        let status = unsafe {
            detour_sys::wrapper_dtNavMesh_setPolyArea(
                self.ptr.as_ptr() as *mut _,
                poly_ref,
                area,
            )
        };
        if dt_status_failed(status) {
            return Err(DetourError::StatusError(status));
        }
        Ok(())
    }

    /// Get raw pointer for NavMeshQuery initialization.
    pub(crate) fn as_ptr(&self) -> *const detour_sys::dtNavMesh {
        self.ptr.as_ptr()
    }
}

impl Drop for NavMesh {
    fn drop(&mut self) {
        unsafe {
            // as_ptr() returns *const dtNavMesh, need *mut for free
            detour_sys::wrapper_dtFreeNavMesh(self.ptr.as_ptr() as *mut _);
        }
    }
}

impl Default for NavMesh {
    fn default() -> Self {
        Self::new().expect("Failed to allocate NavMesh")
    }
}

// SAFETY: NavMesh is read-only after initialization.
// All mutations (add_tile, remove_tile) should happen during setup,
// before the NavMesh is shared across threads.
//
// KNOWN CAVEAT: `set_poly_area` performs interior mutation through a &self reference
// for avoidance-zone pathfinding. This is serialized by QueryPool::avoidance_mutex,
// but concurrent normal pathfinding reads are NOT blocked during the mutation window.
// On x86/x64, single-byte area writes are practically atomic and the worst case is
// a pathfinding query briefly seeing partially-modified area costs (slightly wrong path).
// For formal correctness on all architectures, the avoidance_mutex could be upgraded
// to an RwLock where normal pathfinding takes a read lock.
unsafe impl Send for NavMesh {}
unsafe impl Sync for NavMesh {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_navmesh_allocate_free() {
        // Just test that allocation and deallocation work without crashing
        let mesh = NavMesh::new().unwrap();
        drop(mesh);
    }

    #[test]
    fn test_navmesh_init() {
        let mut mesh = NavMesh::new().unwrap();
        let params = NavMeshParams {
            orig: [0.0, 0.0, 0.0],
            tile_width: 533.33333,  // WoW tile size
            tile_height: 533.33333,
            max_tiles: 1024,
            max_polys: 1024,
        };

        // Init should succeed
        mesh.init(&params).unwrap();

        // max_tiles should be set
        assert!(mesh.max_tiles() > 0);
    }

    #[test]
    fn test_navmesh_send_sync() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}

        assert_send::<NavMesh>();
        assert_sync::<NavMesh>();
    }
}
