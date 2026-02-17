//! Input validation for API parameters.
//!
//! Validates coordinates, map IDs, and other parameters to prevent crashes
//! from invalid inputs (NaN, Infinity, out-of-bounds values).

use crate::error::AppError;

/// WoW coordinate bounds (approximately ±65k yards covers all continents)
const MAX_COORD: f32 = 65536.0;

/// Height bounds (WoW terrain ranges roughly -10k to +10k)
const MAX_HEIGHT: f32 = 10000.0;

/// Maximum valid map ID (WoW emulator maps are typically < 1000)
const MAX_MAP_ID: u32 = 10000;

/// Maximum search/circle radius
const MAX_RADIUS: f32 = 10000.0;

/// Maximum path deviation for anti-detection
const MAX_DEVIATION: f32 = 100.0;

/// Maximum area cost multiplier
const MAX_AREA_COST: f32 = 1000.0;

/// Minimum area cost multiplier
const MIN_AREA_COST: f32 = 0.01;

/// Maximum minimum distance for polygon sampling
const MAX_MIN_DISTANCE: f32 = 1000.0;

/// Maximum polygon vertices
const MAX_POLYGON_VERTICES: usize = 100;

/// Maximum smoothing iterations for Chaikin algorithm
const MAX_SMOOTH_ITERATIONS: u32 = 5;

/// Minimum smoothing iterations for Chaikin algorithm
const MIN_SMOOTH_ITERATIONS: u32 = 1;

/// Maximum samples per segment for Catmull-Rom/Bezier
const MAX_SMOOTH_SAMPLES: u32 = 50;

/// Minimum samples per segment for Catmull-Rom/Bezier
const MIN_SMOOTH_SAMPLES: u32 = 5;

/// Maximum Chaikin corner-cut ratio
const MAX_SMOOTH_RATIO: f32 = 0.95;

/// Minimum Chaikin corner-cut ratio
const MIN_SMOOTH_RATIO: f32 = 0.5;

/// Validate a 3D coordinate (x, y, z).
///
/// Checks that all values are finite and within WoW bounds.
pub fn validate_coordinate(x: f32, y: f32, z: f32) -> Result<(), AppError> {
    // Check for NaN/Inf
    if !x.is_finite() || !y.is_finite() || !z.is_finite() {
        return Err(AppError::InvalidParams(
            "Coordinates must be finite numbers".into(),
        ));
    }

    // Check horizontal bounds (x, y)
    if x.abs() > MAX_COORD || y.abs() > MAX_COORD {
        return Err(AppError::InvalidParams(
            "Coordinates out of WoW bounds (must be within ±65536)".into(),
        ));
    }

    // Check height bounds (z)
    if z.abs() > MAX_HEIGHT {
        return Err(AppError::InvalidParams(
            "Height out of range (must be within ±10000)".into(),
        ));
    }

    Ok(())
}

/// Validate a map ID.
///
/// Map IDs should be reasonable (< 10000 for WoW emulators).
pub fn validate_map_id(map_id: u32) -> Result<(), AppError> {
    if map_id >= MAX_MAP_ID {
        return Err(AppError::InvalidParams(format!(
            "Invalid map ID: {} (must be < {})",
            map_id, MAX_MAP_ID
        )));
    }
    Ok(())
}

/// Validate a radius parameter.
///
/// Radius must be positive and bounded.
pub fn validate_radius(radius: f32) -> Result<(), AppError> {
    if !radius.is_finite() || radius <= 0.0 || radius > MAX_RADIUS {
        return Err(AppError::InvalidParams(format!(
            "Radius must be positive and <= {} (got {})",
            MAX_RADIUS, radius
        )));
    }
    Ok(())
}

/// Validate a deviation parameter for random paths.
///
/// Deviation must be positive and reasonable.
pub fn validate_deviation(deviation: f32) -> Result<(), AppError> {
    if !deviation.is_finite() || deviation <= 0.0 || deviation > MAX_DEVIATION {
        return Err(AppError::InvalidParams(format!(
            "Deviation must be between 0 and {} (got {})",
            MAX_DEVIATION, deviation
        )));
    }
    Ok(())
}

/// Validate an area cost multiplier for pathfinding filters.
///
/// Cost must be finite and within reasonable bounds.
pub fn validate_area_cost(cost: f32, name: &str) -> Result<(), AppError> {
    if !cost.is_finite() || cost < MIN_AREA_COST || cost > MAX_AREA_COST {
        return Err(AppError::InvalidParams(format!(
            "{} cost must be between {} and {} (got {})",
            name, MIN_AREA_COST, MAX_AREA_COST, cost
        )));
    }
    Ok(())
}

/// Validate polygon vertices for exploration.
///
/// Requires at least 3 vertices with finite coordinates.
pub fn validate_polygon(vertices: &[(f32, f32, f32)]) -> Result<(), AppError> {
    if vertices.len() < 3 {
        return Err(AppError::InvalidParams(format!(
            "Polygon must have at least 3 vertices (got {})",
            vertices.len()
        )));
    }

    if vertices.len() > MAX_POLYGON_VERTICES {
        return Err(AppError::InvalidParams(format!(
            "Polygon has too many vertices: {} (max {})",
            vertices.len(),
            MAX_POLYGON_VERTICES
        )));
    }

    for (i, (x, y, z)) in vertices.iter().enumerate() {
        if !x.is_finite() || !y.is_finite() || !z.is_finite() {
            return Err(AppError::InvalidParams(format!(
                "Polygon vertex {} has non-finite coordinates",
                i
            )));
        }
        // Also validate against coordinate bounds
        validate_coordinate(*x, *y, *z)?;
    }

    Ok(())
}

/// Validate minimum distance for polygon sampling.
///
/// Distance must be positive and bounded.
pub fn validate_min_distance(distance: f32) -> Result<(), AppError> {
    if !distance.is_finite() || distance <= 0.0 || distance > MAX_MIN_DISTANCE {
        return Err(AppError::InvalidParams(format!(
            "min_distance must be between 0 and {} (got {})",
            MAX_MIN_DISTANCE, distance
        )));
    }
    Ok(())
}

/// Validate smoothing iterations for Chaikin algorithm.
///
/// Iterations must be within reasonable bounds (1-5).
pub fn validate_smooth_iterations(iterations: u32) -> Result<(), AppError> {
    if iterations < MIN_SMOOTH_ITERATIONS || iterations > MAX_SMOOTH_ITERATIONS {
        return Err(AppError::InvalidParams(format!(
            "smooth_iterations must be between {} and {} (got {})",
            MIN_SMOOTH_ITERATIONS, MAX_SMOOTH_ITERATIONS, iterations
        )));
    }
    Ok(())
}

/// Validate smoothing samples per segment for Catmull-Rom/Bezier.
///
/// Samples must be within reasonable bounds (5-50).
pub fn validate_smooth_samples(samples: u32) -> Result<(), AppError> {
    if samples < MIN_SMOOTH_SAMPLES || samples > MAX_SMOOTH_SAMPLES {
        return Err(AppError::InvalidParams(format!(
            "smooth_samples must be between {} and {} (got {})",
            MIN_SMOOTH_SAMPLES, MAX_SMOOTH_SAMPLES, samples
        )));
    }
    Ok(())
}

/// Validate Chaikin corner-cut ratio.
///
/// Ratio must be within reasonable bounds (0.5-0.95).
pub fn validate_smooth_ratio(ratio: f32) -> Result<(), AppError> {
    if !ratio.is_finite() || ratio < MIN_SMOOTH_RATIO || ratio > MAX_SMOOTH_RATIO {
        return Err(AppError::InvalidParams(format!(
            "smooth_ratio must be between {} and {} (got {})",
            MIN_SMOOTH_RATIO, MAX_SMOOTH_RATIO, ratio
        )));
    }
    Ok(())
}

/// Validate custom Z search extent for polygon lookup.
///
/// Z extent controls the vertical search range for `findNearestPoly`.
/// Smaller values pick the correct floor in multi-story buildings;
/// larger values handle steep terrain and cliffs.
pub fn validate_z_extent(z: f32) -> Result<(), AppError> {
    if !z.is_finite() || z <= 0.0 || z > 1000.0 {
        return Err(AppError::InvalidParams(format!(
            "z_extent must be between 0 and 1000 (got {})",
            z
        )));
    }
    Ok(())
}

/// Validate wall clearance distance.
///
/// Must be between 0 and 5.0 yards (WoW doorways are ~3-4 yards wide).
pub fn validate_wall_clearance(clearance: f32) -> Result<(), AppError> {
    if !clearance.is_finite() || clearance < 0.0 || clearance > 5.0 {
        return Err(AppError::InvalidParams(format!(
            "wall_clearance must be between 0 and 5.0 (got {})",
            clearance
        )));
    }
    Ok(())
}

/// Validate minimum corner angle for Chaikin smoothing.
///
/// Angle must be between 0 and 180 degrees.
/// - 0 = smooth all corners (default)
/// - 90 = only smooth corners wider than 90 degrees (skip tight turns)
/// - 180 = don't smooth any corners
pub fn validate_min_corner_angle(angle: f32) -> Result<(), AppError> {
    if !angle.is_finite() || angle < 0.0 || angle > 180.0 {
        return Err(AppError::InvalidParams(format!(
            "min_corner_angle must be between 0 and 180 (got {})",
            angle
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // Coordinate validation tests
    #[test]
    fn test_rejects_nan_coordinates() {
        assert!(validate_coordinate(f32::NAN, 0.0, 0.0).is_err());
        assert!(validate_coordinate(0.0, f32::NAN, 0.0).is_err());
        assert!(validate_coordinate(0.0, 0.0, f32::NAN).is_err());
    }

    #[test]
    fn test_rejects_infinity() {
        assert!(validate_coordinate(f32::INFINITY, 0.0, 0.0).is_err());
        assert!(validate_coordinate(f32::NEG_INFINITY, 0.0, 0.0).is_err());
        assert!(validate_coordinate(0.0, f32::INFINITY, 0.0).is_err());
    }

    #[test]
    fn test_rejects_out_of_bounds_xy() {
        assert!(validate_coordinate(70000.0, 0.0, 0.0).is_err());
        assert!(validate_coordinate(0.0, -70000.0, 0.0).is_err());
        assert!(validate_coordinate(-66000.0, 66000.0, 0.0).is_err());
    }

    #[test]
    fn test_rejects_out_of_bounds_z() {
        assert!(validate_coordinate(0.0, 0.0, 15000.0).is_err());
        assert!(validate_coordinate(0.0, 0.0, -15000.0).is_err());
    }

    #[test]
    fn test_accepts_valid_stormwind_coords() {
        assert!(validate_coordinate(-8949.95, -132.493, 83.53).is_ok());
    }

    #[test]
    fn test_accepts_valid_orgrimmar_coords() {
        assert!(validate_coordinate(1629.36, -4373.39, 31.26).is_ok());
    }

    #[test]
    fn test_accepts_edge_case_coords() {
        assert!(validate_coordinate(65535.0, -65535.0, 9999.0).is_ok());
        assert!(validate_coordinate(0.0, 0.0, 0.0).is_ok());
    }

    // Map ID validation tests
    #[test]
    fn test_rejects_invalid_map_id() {
        assert!(validate_map_id(10000).is_err());
        assert!(validate_map_id(999999).is_err());
        assert!(validate_map_id(u32::MAX).is_err());
    }

    #[test]
    fn test_accepts_valid_map_ids() {
        assert!(validate_map_id(0).is_ok()); // Eastern Kingdoms
        assert!(validate_map_id(1).is_ok()); // Kalimdor
        assert!(validate_map_id(530).is_ok()); // Outland
        assert!(validate_map_id(571).is_ok()); // Northrend
        assert!(validate_map_id(9999).is_ok()); // Edge case
    }

    // Radius validation tests
    #[test]
    fn test_rejects_invalid_radius() {
        assert!(validate_radius(0.0).is_err());
        assert!(validate_radius(-5.0).is_err());
        assert!(validate_radius(f32::NAN).is_err());
        assert!(validate_radius(f32::INFINITY).is_err());
        assert!(validate_radius(50000.0).is_err());
    }

    #[test]
    fn test_accepts_valid_radius() {
        assert!(validate_radius(0.001).is_ok());
        assert!(validate_radius(50.0).is_ok());
        assert!(validate_radius(10000.0).is_ok());
    }

    // Deviation validation tests
    #[test]
    fn test_rejects_invalid_deviation() {
        assert!(validate_deviation(0.0).is_err());
        assert!(validate_deviation(-1.0).is_err());
        assert!(validate_deviation(f32::NAN).is_err());
        assert!(validate_deviation(101.0).is_err());
    }

    #[test]
    fn test_accepts_valid_deviation() {
        assert!(validate_deviation(0.1).is_ok());
        assert!(validate_deviation(5.0).is_ok());
        assert!(validate_deviation(100.0).is_ok());
    }

    // Area cost validation tests
    #[test]
    fn test_rejects_invalid_area_cost() {
        assert!(validate_area_cost(0.0, "ground").is_err());
        assert!(validate_area_cost(-1.0, "water").is_err());
        assert!(validate_area_cost(f32::NAN, "lava").is_err());
        assert!(validate_area_cost(f32::INFINITY, "ground").is_err());
        assert!(validate_area_cost(1001.0, "water").is_err());
        assert!(validate_area_cost(0.001, "ground").is_err()); // Below MIN_AREA_COST
    }

    #[test]
    fn test_accepts_valid_area_cost() {
        assert!(validate_area_cost(0.01, "ground").is_ok());
        assert!(validate_area_cost(1.0, "ground").is_ok());
        assert!(validate_area_cost(10.0, "water").is_ok());
        assert!(validate_area_cost(100.0, "lava").is_ok());
        assert!(validate_area_cost(1000.0, "steep").is_ok());
    }

    // Polygon validation tests
    #[test]
    fn test_rejects_invalid_polygon() {
        // Too few vertices
        assert!(validate_polygon(&[]).is_err());
        assert!(validate_polygon(&[(0.0, 0.0, 0.0)]).is_err());
        assert!(validate_polygon(&[(0.0, 0.0, 0.0), (1.0, 0.0, 0.0)]).is_err());

        // Non-finite coordinates
        assert!(validate_polygon(&[
            (f32::NAN, 0.0, 0.0),
            (1.0, 0.0, 0.0),
            (1.0, 1.0, 0.0),
        ])
        .is_err());
        assert!(validate_polygon(&[
            (0.0, f32::INFINITY, 0.0),
            (1.0, 0.0, 0.0),
            (1.0, 1.0, 0.0),
        ])
        .is_err());
    }

    #[test]
    fn test_accepts_valid_polygon() {
        // Triangle
        assert!(validate_polygon(&[
            (0.0, 0.0, 50.0),
            (100.0, 0.0, 50.0),
            (50.0, 100.0, 50.0),
        ])
        .is_ok());

        // Square
        assert!(validate_polygon(&[
            (-8960.0, -120.0, 83.0),
            (-8900.0, -120.0, 83.0),
            (-8900.0, -170.0, 83.0),
            (-8960.0, -170.0, 83.0),
        ])
        .is_ok());
    }

    // Min distance validation tests
    #[test]
    fn test_rejects_invalid_min_distance() {
        assert!(validate_min_distance(0.0).is_err());
        assert!(validate_min_distance(-5.0).is_err());
        assert!(validate_min_distance(f32::NAN).is_err());
        assert!(validate_min_distance(f32::INFINITY).is_err());
        assert!(validate_min_distance(1001.0).is_err());
    }

    #[test]
    fn test_accepts_valid_min_distance() {
        assert!(validate_min_distance(0.1).is_ok());
        assert!(validate_min_distance(20.0).is_ok());
        assert!(validate_min_distance(100.0).is_ok());
        assert!(validate_min_distance(1000.0).is_ok());
    }

    // Smoothing parameter validation tests
    #[test]
    fn test_rejects_invalid_smooth_iterations() {
        assert!(validate_smooth_iterations(0).is_err());
        assert!(validate_smooth_iterations(6).is_err());
        assert!(validate_smooth_iterations(100).is_err());
    }

    #[test]
    fn test_accepts_valid_smooth_iterations() {
        assert!(validate_smooth_iterations(1).is_ok());
        assert!(validate_smooth_iterations(2).is_ok());
        assert!(validate_smooth_iterations(3).is_ok());
        assert!(validate_smooth_iterations(5).is_ok());
    }

    #[test]
    fn test_rejects_invalid_smooth_samples() {
        assert!(validate_smooth_samples(0).is_err());
        assert!(validate_smooth_samples(4).is_err());
        assert!(validate_smooth_samples(51).is_err());
        assert!(validate_smooth_samples(100).is_err());
    }

    #[test]
    fn test_accepts_valid_smooth_samples() {
        assert!(validate_smooth_samples(5).is_ok());
        assert!(validate_smooth_samples(10).is_ok());
        assert!(validate_smooth_samples(20).is_ok());
        assert!(validate_smooth_samples(50).is_ok());
    }

    #[test]
    fn test_rejects_invalid_smooth_ratio() {
        assert!(validate_smooth_ratio(0.0).is_err());
        assert!(validate_smooth_ratio(0.49).is_err());
        assert!(validate_smooth_ratio(0.96).is_err());
        assert!(validate_smooth_ratio(1.0).is_err());
        assert!(validate_smooth_ratio(f32::NAN).is_err());
        assert!(validate_smooth_ratio(f32::INFINITY).is_err());
    }

    #[test]
    fn test_accepts_valid_smooth_ratio() {
        assert!(validate_smooth_ratio(0.5).is_ok());
        assert!(validate_smooth_ratio(0.75).is_ok());
        assert!(validate_smooth_ratio(0.9).is_ok());
        assert!(validate_smooth_ratio(0.95).is_ok());
    }

    // Z extent validation tests
    #[test]
    fn test_rejects_invalid_z_extent() {
        assert!(validate_z_extent(0.0).is_err());
        assert!(validate_z_extent(-5.0).is_err());
        assert!(validate_z_extent(f32::NAN).is_err());
        assert!(validate_z_extent(f32::INFINITY).is_err());
        assert!(validate_z_extent(1001.0).is_err());
    }

    #[test]
    fn test_accepts_valid_z_extent() {
        assert!(validate_z_extent(0.1).is_ok());
        assert!(validate_z_extent(10.0).is_ok());
        assert!(validate_z_extent(50.0).is_ok());
        assert!(validate_z_extent(500.0).is_ok());
        assert!(validate_z_extent(1000.0).is_ok());
    }

    // Min corner angle validation tests
    #[test]
    fn test_rejects_invalid_min_corner_angle() {
        assert!(validate_min_corner_angle(-1.0).is_err());
        assert!(validate_min_corner_angle(181.0).is_err());
        assert!(validate_min_corner_angle(f32::NAN).is_err());
        assert!(validate_min_corner_angle(f32::INFINITY).is_err());
    }

    #[test]
    fn test_accepts_valid_min_corner_angle() {
        assert!(validate_min_corner_angle(0.0).is_ok());
        assert!(validate_min_corner_angle(45.0).is_ok());
        assert!(validate_min_corner_angle(90.0).is_ok());
        assert!(validate_min_corner_angle(120.0).is_ok());
        assert!(validate_min_corner_angle(180.0).is_ok());
    }
}
