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
    /// Tiered polygon search extents [tight, medium, wide] in yards.
    #[serde(default = "default_search_extents")]
    pub search_extents: [f32; 3],
    /// Max segment length before densification (yards).
    #[serde(default = "default_max_segment_length")]
    pub max_segment_length: f32,
    /// Island recovery retry count.
    #[serde(default = "default_island_retry_count")]
    pub island_retry_count: usize,
    /// Default area costs [ground, water, lava].
    #[serde(default = "default_area_costs")]
    pub default_area_costs: [f32; 3],
    /// Maximum A* search nodes per NavMeshQuery.
    /// Higher values allow pathfinding through denser navmeshes (GO-injected areas).
    /// Each node uses ~36 bytes. Default: 65535 (Detour maximum).
    #[serde(default = "default_max_query_nodes")]
    pub max_query_nodes: u32,
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

fn default_search_extents() -> [f32; 3] {
    [6.0, 10.0, 50.0]
}

fn default_max_segment_length() -> f32 {
    3.0
}

fn default_island_retry_count() -> usize {
    16
}

fn default_area_costs() -> [f32; 3] {
    [1.0, 1.5, 100.0]
}

fn default_max_query_nodes() -> u32 {
    65535
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
            search_extents: default_search_extents(),
            max_segment_length: default_max_segment_length(),
            island_retry_count: default_island_retry_count(),
            default_area_costs: default_area_costs(),
            max_query_nodes: default_max_query_nodes(),
        }
    }
}

impl Config {
    /// Load configuration from file or defaults.
    pub fn load() -> anyhow::Result<Self> {
        // Try to load from config.toml
        let config_path = std::env::var("SENTINEL_NAV_SERVER_CONFIG")
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
