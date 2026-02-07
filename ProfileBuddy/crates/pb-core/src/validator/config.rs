//! Validator configuration for NavBuddy integration.

use serde::{Deserialize, Serialize};

/// Configuration for coordinate validation via NavBuddy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidatorConfig {
    /// Whether validation is enabled.
    pub enabled: bool,

    /// NavBuddy server URL (e.g., "http://localhost:3000").
    pub navbuddy_url: String,

    /// Timeout for HTTP requests in milliseconds.
    pub timeout_ms: u32,

    /// If true, use zone's default_z when NavBuddy is unavailable or fails.
    /// If false, fail profile generation when NavBuddy errors occur.
    pub fallback_on_error: bool,

    /// If true, remove nodes that fail validation (not on navmesh).
    /// If false, keep them with fallback Z.
    pub remove_invalid: bool,

    /// If true, detect and exclude underground/cave nodes.
    pub exclude_caves: bool,

    /// Height difference threshold (in yards) to consider a node underground.
    /// If (surface_z - node_z) > cave_threshold, the node is excluded.
    pub cave_threshold: f32,

    /// If true, check if nodes are reachable via pathfinding (not on isolated polygons).
    /// This catches building roofs, isolated rocks, etc.
    pub validate_connectivity: bool,

    /// Optional reference point (x, y, z) for connectivity checks.
    /// If provided, all nodes must be reachable from this point.
    /// If not provided, the first valid node is used as reference (which might be isolated).
    pub reference_point: Option<(f32, f32, f32)>,
}

impl Default for ValidatorConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            navbuddy_url: "http://localhost:47110".to_string(),
            timeout_ms: 500,
            fallback_on_error: true,
            remove_invalid: false,
            exclude_caves: true,
            cave_threshold: 15.0,
            validate_connectivity: false,
            reference_point: None,
        }
    }
}

impl ValidatorConfig {
    /// Create a new config with validation disabled.
    pub fn disabled() -> Self {
        Self {
            enabled: false,
            ..Default::default()
        }
    }

    /// Create a config with custom NavBuddy URL.
    pub fn with_url(url: impl Into<String>) -> Self {
        Self {
            navbuddy_url: url.into(),
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = ValidatorConfig::default();
        assert!(config.enabled);
        assert_eq!(config.navbuddy_url, "http://localhost:47110");
        assert_eq!(config.timeout_ms, 500);
        assert!(config.fallback_on_error);
        assert!(!config.remove_invalid);
        assert!(config.exclude_caves);
        assert!((config.cave_threshold - 15.0).abs() < 0.01);
        assert!(!config.validate_connectivity);
    }

    #[test]
    fn test_disabled_config() {
        let config = ValidatorConfig::disabled();
        assert!(!config.enabled);
    }
}
