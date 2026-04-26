use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_host")]
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
}

fn default_host() -> String {
    "127.0.0.1".to_string()
}
fn default_port() -> u16 {
    7300
}

impl Default for ServerConfig {
    fn default() -> Self {
        ServerConfig {
            host: default_host(),
            port: default_port(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionConfig {
    #[serde(default = "default_heartbeat_timeout_ms")]
    pub heartbeat_timeout_ms: u64,
    #[serde(default = "default_barrier_timeout_ms")]
    pub barrier_timeout_ms: u64,
    #[serde(default = "default_max_clients")]
    pub max_clients: u32,
}

fn default_heartbeat_timeout_ms() -> u64 {
    5000
}
fn default_barrier_timeout_ms() -> u64 {
    90000
}
fn default_max_clients() -> u32 {
    2
}

impl Default for SessionConfig {
    fn default() -> Self {
        SessionConfig {
            heartbeat_timeout_ms: default_heartbeat_timeout_ms(),
            barrier_timeout_ms: default_barrier_timeout_ms(),
            max_clients: default_max_clients(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LockoutConfig {
    #[serde(default = "default_max_resets_per_hour")]
    pub max_resets_per_hour: u32,
    #[serde(default = "default_warn_at")]
    pub warn_at: u32,
}

fn default_max_resets_per_hour() -> u32 {
    5
}
fn default_warn_at() -> u32 {
    4
}

impl Default for LockoutConfig {
    fn default() -> Self {
        LockoutConfig {
            max_resets_per_hour: default_max_resets_per_hour(),
            warn_at: default_warn_at(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Config {
    #[serde(default)]
    pub server: ServerConfig,
    #[serde(default)]
    pub session: SessionConfig,
    #[serde(default)]
    pub lockout: LockoutConfig,
}

impl Config {
    pub fn load() -> Result<Self> {
        let path = "config.toml";
        if let Ok(content) = fs::read_to_string(path) {
            let config: Config = toml::from_str(&content)?;
            Ok(config)
        } else {
            tracing::info!("config.toml not found, using defaults");
            Ok(Config::default())
        }
    }
}
