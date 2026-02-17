//! Height reprojection onto navmesh detail mesh.
//!
//! After smoothing modifies XY positions, Z (height) values become inaccurate.
//! This module reprojects each waypoint's Z onto the navmesh detail mesh using
//! `get_poly_height()`, which samples the detail triangulation for sub-polygon
//! accuracy on stairs, ramps, and uneven terrain.

use detour::query::NavMeshQuery;
use detour::filter::QueryFilter;
use detour::types::Vec3;

/// Reproject waypoint heights onto the navmesh detail mesh.
///
/// For each waypoint:
/// 1. `find_nearest_poly` with tight extents to get the correct polygon
/// 2. `get_poly_height` for detail mesh height at that XZ position
/// 3. Set `waypoint.z = height`
/// 4. On failure, keep original Z (graceful degradation)
///
/// Tight Y extents prevent wrong-floor snapping in multi-level structures.
pub fn reproject_heights(
    waypoints: &mut [Vec3],
    query: &NavMeshQuery,
    filter: &QueryFilter,
    extents: [f32; 3],
) {
    let search_extents = Vec3::new(extents[0], extents[1], extents[2]);
    let fallback_extents = Vec3::new(
        (extents[0] * 2.0).min(10.0),
        (extents[1] * 2.0).min(10.0),
        (extents[2] * 2.0).min(10.0),
    );

    for waypoint in waypoints.iter_mut() {
        let poly_result = query
            .find_nearest_poly(*waypoint, search_extents, filter)
            .or_else(|_| query.find_nearest_poly(*waypoint, fallback_extents, filter));

        if let Ok((poly_ref, _)) = poly_result {
            if let Ok(height) = query.get_poly_height(poly_ref, *waypoint) {
                waypoint.z = height;
            }
            // get_poly_height failed: keep existing Z
        }
        // find_nearest_poly failed on both tiers: keep original Z
    }
}
