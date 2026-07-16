//! Input parsing: waypoints, stops, avoidance zones, threats.

use detour::types::Vec3;

use crate::error::AppError;
use crate::validation::validate_coordinate;

use super::AvoidanceZone;

/// Parse semicolon-separated "x,y,z" coordinates into Vec3.
/// `noun` is used in error messages (e.g. "waypoint", "threat").
fn parse_xyz_list(input: &str, noun: &str) -> Result<Vec<Vec3>, AppError> {
    if input.is_empty() {
        return Err(AppError::InvalidParams(format!(
            "Empty {} string",
            noun
        )));
    }

    let mut result = Vec::new();
    for (i, part) in input.split(';').enumerate() {
        let coords: Vec<&str> = part.split(',').collect();
        if coords.len() != 3 {
            return Err(AppError::InvalidParams(format!(
                "Invalid {} {} format: expected 'x,y,z'",
                noun, i
            )));
        }

        let x: f32 = coords[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x in {} {}", noun, i))
        })?;
        let y: f32 = coords[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y in {} {}", noun, i))
        })?;
        let z: f32 = coords[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z in {} {}", noun, i))
        })?;

        validate_coordinate(x, y, z)?;
        result.push(Vec3::new(x, y, z));
    }

    Ok(result)
}

/// Parse waypoints from semicolon-separated string format "x1,y1,z1;x2,y2,z2;...".
pub fn parse_waypoints(waypoints_str: &str) -> Result<Vec<Vec3>, AppError> {
    parse_xyz_list(waypoints_str, "waypoint")
}

/// Parse stops from semicolon-separated string format (minimum 2 stops).
pub fn parse_stops(stops_str: &str) -> Result<Vec<Vec3>, AppError> {
    let stops = parse_waypoints(stops_str)?;
    if stops.len() < 2 {
        return Err(AppError::InvalidParams(
            "At least 2 stops required".into(),
        ));
    }
    Ok(stops)
}

/// Parse avoidance zones from semicolon-separated "x,y,z,radius,cost" strings.
pub fn parse_avoidance_zones(zones_str: &str) -> Result<Vec<AvoidanceZone>, AppError> {
    if zones_str.is_empty() {
        return Ok(Vec::new());
    }

    let zone_entries: Vec<&str> = zones_str.split(';').collect();
    let mut result = Vec::with_capacity(zone_entries.len());
    for (i, zone_str) in zone_entries.iter().enumerate() {
        let parts: Vec<&str> = zone_str.split(',').collect();
        if parts.len() != 5 {
            return Err(AppError::InvalidParams(format!(
                "Invalid avoidance zone {} format: expected 'x,y,z,radius,cost'",
                i
            )));
        }

        let x: f32 = parts[0].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid x in avoidance zone {}", i))
        })?;
        let y: f32 = parts[1].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid y in avoidance zone {}", i))
        })?;
        let z: f32 = parts[2].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid z in avoidance zone {}", i))
        })?;
        let radius: f32 = parts[3].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid radius in avoidance zone {}", i))
        })?;
        let cost: f32 = parts[4].trim().parse().map_err(|_| {
            AppError::InvalidParams(format!("Invalid cost in avoidance zone {}", i))
        })?;

        validate_coordinate(x, y, z)?;

        if !radius.is_finite() || radius <= 0.0 || radius > 1000.0 {
            return Err(AppError::InvalidParams(format!(
                "Avoidance zone {} radius must be between 0 and 1000 (got {})",
                i, radius
            )));
        }
        if !cost.is_finite() || cost < 1.0 || cost > 1000.0 {
            return Err(AppError::InvalidParams(format!(
                "Avoidance zone {} cost must be between 1 and 1000 (got {})",
                i, cost
            )));
        }

        result.push(AvoidanceZone {
            center: Vec3::new(x, y, z),
            radius,
            cost_multiplier: cost,
        });
    }

    if result.len() > 20 {
        return Err(AppError::InvalidParams(
            "Maximum 20 avoidance zones allowed".into(),
        ));
    }

    Ok(result)
}

/// Parse threat positions from semicolon-separated "x,y,z" strings.
pub fn parse_threats(threats_str: &str) -> Result<Vec<Vec3>, AppError> {
    parse_xyz_list(threats_str, "threat")
}
