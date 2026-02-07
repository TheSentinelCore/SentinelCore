//! NavBuddy HTTP client for coordinate validation.

use std::time::Duration;

use serde::Deserialize;

use crate::error::{Error, Result};

/// Response from NavBuddy's height endpoint.
#[derive(Debug, Deserialize)]
struct HeightResponse {
    success: bool,
    height: f32,
}

/// Response from NavBuddy's health endpoint.
#[derive(Debug, Deserialize)]
struct HealthResponse {
    status: String,
}

/// Waypoint from NavBuddy's path endpoint.
#[derive(Debug, Clone, Deserialize)]
pub struct PathWaypoint {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// Response from NavBuddy's path endpoint.
#[derive(Debug, Clone, Deserialize)]
pub struct PathResponse {
    pub success: bool,
    pub path: Vec<PathWaypoint>,
    pub distance: f32,
    /// TRUE if the path is partial (destination unreachable)
    #[serde(default)]
    pub partial: bool,
    #[serde(default)]
    pub computation_time_ms: f64,
}

/// HTTP client for communicating with NavBuddy.
#[derive(Debug, Clone)]
pub struct NavBuddyClient {
    client: reqwest::blocking::Client,
    base_url: String,
}

impl NavBuddyClient {
    /// Create a new NavBuddy client.
    ///
    /// # Arguments
    /// * `base_url` - Base URL of the NavBuddy server (e.g., "http://localhost:3000")
    /// * `timeout_ms` - Request timeout in milliseconds
    pub fn new(base_url: impl Into<String>, timeout_ms: u32) -> Result<Self> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_millis(timeout_ms as u64))
            .build()
            .map_err(Error::HttpError)?;

        Ok(Self {
            client,
            base_url: base_url.into(),
        })
    }

    /// Check if NavBuddy is available and healthy.
    pub fn health_check(&self) -> Result<bool> {
        let url = format!("{}/health", self.base_url);

        match self.client.get(&url).send() {
            Ok(response) => {
                if response.status().is_success() {
                    if let Ok(health) = response.json::<HealthResponse>() {
                        return Ok(health.status == "ok");
                    }
                }
                Ok(false)
            }
            Err(_) => Ok(false),
        }
    }

    /// Get the navmesh height at a position.
    ///
    /// # Arguments
    /// * `map_id` - Map/continent ID (0 = Eastern Kingdoms, 1 = Kalimdor, etc.)
    /// * `x` - X coordinate (North-South)
    /// * `y` - Y coordinate (West-East)
    /// * `z` - Approximate Z for polygon search
    ///
    /// # Returns
    /// The navmesh height at the position, or an error if the position is not on the navmesh.
    pub fn get_height(&self, map_id: u32, x: f32, y: f32, z: f32) -> Result<f32> {
        let url = format!(
            "{}/api/v1/height?map_id={}&x={}&y={}&z={}",
            self.base_url, map_id, x, y, z
        );

        let response = self.client.get(&url).send().map_err(Error::HttpError)?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().unwrap_or_default();
            return Err(Error::InvalidCoordinate(format!(
                "NavBuddy returned {}: {}",
                status, body
            )));
        }

        let height_response: HeightResponse = response.json().map_err(Error::HttpError)?;

        if height_response.success {
            Ok(height_response.height)
        } else {
            Err(Error::InvalidCoordinate(
                "Position not on navmesh".to_string(),
            ))
        }
    }

    /// Get heights for multiple positions in parallel.
    ///
    /// # Arguments
    /// * `map_id` - Map/continent ID
    /// * `positions` - List of (x, y, z) coordinates to query
    ///
    /// # Returns
    /// A vector of Results, one per input position.
    pub fn batch_get_heights(
        &self,
        map_id: u32,
        positions: &[(f32, f32, f32)],
    ) -> Vec<Result<f32>> {
        use rayon::prelude::*;

        positions
            .par_iter()
            .map(|(x, y, z)| self.get_height(map_id, *x, *y, *z))
            .collect()
    }

    /// Find a path between two positions.
    ///
    /// # Arguments
    /// * `map_id` - Map/continent ID
    /// * `start` - Start position (x, y, z)
    /// * `end` - End position (x, y, z)
    ///
    /// # Returns
    /// A PathResponse containing the path and whether it's partial (destination unreachable).
    pub fn find_path(
        &self,
        map_id: u32,
        start: (f32, f32, f32),
        end: (f32, f32, f32),
    ) -> Result<PathResponse> {
        let url = format!(
            "{}/api/v1/path?map_id={}&start_x={}&start_y={}&start_z={}&end_x={}&end_y={}&end_z={}",
            self.base_url, map_id, start.0, start.1, start.2, end.0, end.1, end.2
        );

        let response = self.client.get(&url).send().map_err(Error::HttpError)?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().unwrap_or_default();
            return Err(Error::InvalidCoordinate(format!(
                "NavBuddy pathfinding returned {}: {}",
                status, body
            )));
        }

        let path_response: PathResponse = response.json().map_err(Error::HttpError)?;
        Ok(path_response)
    }

    /// Check if a position is reachable from a reference point.
    ///
    /// # Arguments
    /// * `map_id` - Map/continent ID
    /// * `reference` - Known-good reference position (x, y, z)
    /// * `target` - Target position to check (x, y, z)
    ///
    /// # Returns
    /// `true` if the target is reachable (path is not partial), `false` otherwise.
    pub fn is_reachable(
        &self,
        map_id: u32,
        reference: (f32, f32, f32),
        target: (f32, f32, f32),
    ) -> Result<bool> {
        let path_response = self.find_path(map_id, reference, target)?;
        Ok(path_response.success && !path_response.partial)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = NavBuddyClient::new("http://localhost:3000", 500);
        assert!(client.is_ok());
    }

    // Integration tests would require a running NavBuddy server
    // They're marked as ignored and can be run manually
    #[test]
    #[ignore]
    fn test_health_check() {
        let client = NavBuddyClient::new("http://localhost:3000", 500).unwrap();
        let result = client.health_check();
        println!("Health check result: {:?}", result);
    }

    #[test]
    #[ignore]
    fn test_get_height() {
        let client = NavBuddyClient::new("http://localhost:3000", 500).unwrap();
        // Test with Elwynn Forest coordinates
        let result = client.get_height(0, -8900.0, -200.0, 50.0);
        println!("Height result: {:?}", result);
    }
}
