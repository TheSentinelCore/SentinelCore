//! Filter creation, resolution, and pathfinding constants.

use detour::filter::{
    NAV_AREA_GROUND, NAV_AREA_GROUND_STEEP, NAV_AREA_MAGMA_SLIME, NAV_AREA_WATER, QueryFilter,
    QueryFilterBuilder,
};

use detour::types::Vec3;

use crate::error::AppError;

/// Default area costs for WoW pathfinding.
pub const DEFAULT_GROUND_COST: f32 = 1.0;
pub const DEFAULT_WATER_COST: f32 = 1.5;
pub const DEFAULT_LAVA_COST: f32 = 100.0;

/// Search extents for general polygon searches (recovery, avoidance, etc.).
/// Reduced from 50/50/500 to match reference implementations.
pub const SEARCH_EXTENTS: Vec3 = Vec3 {
    x: 50.0,
    y: 50.0,
    z: 50.0,
};

/// Height extents for waypoint surface projection (smaller for accuracy).
/// Tight z keeps wall-clearance, surface projection, and validation on the correct floor
/// in multi-level structures (towers, ramps, bridges).
pub const HEIGHT_EXTENTS: Vec3 = Vec3 {
    x: 5.0,
    y: 5.0,
    z: 5.0,
};

/// Maximum polygons in the path corridor.
pub const MAX_PATH_POLYS: usize = 1024;

/// Maximum waypoints in the straight path.
pub const MAX_STRAIGHT_PATH: usize = 2048;

/// Tiered 3D search extents (x, y, z) for polygon search.
/// Tight first for correct floor selection, broader as fallback.
/// Reference: CMaNGOS uses 5/10, AmeisenNavigation uses 6, BloogBot uses 3.
/// Previous Sentinel Navigation Server XY=50 was 10x larger than all references, causing water/edge issues.
pub const SEARCH_TIERS: [(f32, f32, f32); 3] = [
    (6.0, 6.0, 3.0),   // Tight Z — correct floor in multi-level buildings
    (10.0, 10.0, 6.0),  // Medium — still prefers correct floor
    (50.0, 50.0, 50.0), // Fallback — imprecise coordinates
];

/// Max Z deviation before rejecting a snap result (prevents wrong-floor selection).
pub(crate) const MAX_Z_SNAP_DELTA: f32 = 5.0; // only used internally by pathfinding.rs

/// XY offsets (yards) to try when the start/end poly is on a disconnected island.
/// Inner ring (~3 yd) for small GO islands; outer ring (~6 yd) for larger GO clusters.
pub(crate) const ISLAND_RETRY_OFFSETS: [(f32, f32); 16] = [
    // Inner ring: ~3 yards
    (3.0, 0.0),
    (-3.0, 0.0),
    (0.0, 3.0),
    (0.0, -3.0),
    (2.0, 2.0),
    (-2.0, 2.0),
    (2.0, -2.0),
    (-2.0, -2.0),
    // Outer ring: ~6 yards
    (6.0, 0.0),
    (-6.0, 0.0),
    (0.0, 6.0),
    (0.0, -6.0),
    (4.2, 4.2),
    (-4.2, 4.2),
    (4.2, -4.2),
    (-4.2, -4.2),
];

/// NAV_GROUND flag (1 << (11-11) = 0x01).
pub(crate) const NAV_FLAG_GROUND: u16 = 0x01;
/// NAV_WATER flag (1 << (11-9) = 0x04).
pub(crate) const NAV_FLAG_WATER: u16 = 0x04;

/// Check if any custom filter parameters are provided.
pub fn has_custom_filter(
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
) -> bool {
    filter_ground.is_some() || filter_water.is_some() || filter_lava.is_some()
}

/// Create a custom QueryFilter with specified area costs.
pub fn create_custom_filter(
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
) -> Result<QueryFilter, AppError> {
    let ground = filter_ground.unwrap_or(DEFAULT_GROUND_COST);
    let water = filter_water.unwrap_or(DEFAULT_WATER_COST);
    let lava = filter_lava.unwrap_or(DEFAULT_LAVA_COST);

    QueryFilterBuilder::new()
        .area_cost(NAV_AREA_GROUND, ground)        // area 11: ground
        .area_cost(NAV_AREA_GROUND_STEEP, ground)  // area 10: steep slopes (same cost as ground)
        .area_cost(NAV_AREA_WATER, water)           // area 9: water
        .area_cost(NAV_AREA_MAGMA_SLIME, lava)      // area 8: magma/slime
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to create filter: {}", e)))
}

/// Resolve the filter to use: custom if any filter params provided, otherwise pool default.
pub fn resolve_filter<'a>(
    pool_filter: &'a QueryFilter,
    filter_ground: Option<f32>,
    filter_water: Option<f32>,
    filter_lava: Option<f32>,
    custom_filter_storage: &'a mut Option<QueryFilter>,
) -> Result<&'a QueryFilter, AppError> {
    if has_custom_filter(filter_ground, filter_water, filter_lava) {
        let custom = create_custom_filter(filter_ground, filter_water, filter_lava)?;
        *custom_filter_storage = Some(custom);
        Ok(custom_filter_storage.as_ref().unwrap())
    } else {
        Ok(pool_filter)
    }
}
