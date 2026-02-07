//! Configuration loading and types.

use serde::Deserialize;
use std::path::PathBuf;

/// Main configuration structure.
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub navmesh: NavmeshConfig,
    pub pathfinding: PathfindingConfig,
}

/// Server configuration.
#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    /// Host to bind to.
    #[serde(default = "default_host")]
    pub host: String,
    /// Port to listen on.
    #[serde(default = "default_port")]
    pub port: u16,
    /// Maximum concurrent requests.
    #[serde(default = "default_max_concurrent")]
    pub max_concurrent_requests: usize,
}

/// Navmesh configuration.
#[derive(Debug, Clone, Deserialize)]
pub struct NavmeshConfig {
    /// Path to mmap files directory.
    pub mmap_path: PathBuf,
    /// Maps to preload at startup.
    #[serde(default)]
    pub preload_maps: Vec<u32>,
}

/// Pathfinding configuration.
#[derive(Debug, Clone, Deserialize)]
pub struct PathfindingConfig {
    /// Default smoothing algorithm.
    #[serde(default)]
    pub default_smoothing: String,
    /// Maximum path length in waypoints.
    #[serde(default = "default_max_path_length")]
    pub max_path_length: usize,
    /// Query pool size per map.
    #[serde(default = "default_query_pool_size")]
    pub query_pool_size: usize,
}

fn default_host() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    47110
}

fn default_max_concurrent() -> usize {
    100
}

fn default_max_path_length() -> usize {
    2048
}

fn default_query_pool_size() -> usize {
    4
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: default_host(),
            port: default_port(),
            max_concurrent_requests: default_max_concurrent(),
        }
    }
}

impl Default for PathfindingConfig {
    fn default() -> Self {
        Self {
            default_smoothing: "none".to_string(),
            max_path_length: default_max_path_length(),
            query_pool_size: default_query_pool_size(),
        }
    }
}

impl Config {
    /// Load configuration from file or defaults.
    pub fn load() -> anyhow::Result<Self> {
        // Try to load from config.toml
        let config_path = std::env::var("NAVBUDDY_CONFIG")
            .unwrap_or_else(|_| "config.toml".to_string());

        if let Ok(content) = std::fs::read_to_string(&config_path) {
            let config: Config = toml::from_str(&content)?;
            return Ok(config);
        }

        // Use defaults
        Ok(Self {
            server: ServerConfig::default(),
            navmesh: NavmeshConfig {
                mmap_path: PathBuf::from("./mmaps"),
                preload_maps: vec![],
            },
            pathfinding: PathfindingConfig::default(),
        })
    }
}
