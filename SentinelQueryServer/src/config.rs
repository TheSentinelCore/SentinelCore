use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub paths: PathsConfig,
    pub limits: LimitsConfig,
    #[serde(default)]
    pub importer: ImporterConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    #[serde(default = "default_max_concurrent_requests")]
    pub max_concurrent_requests: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PathsConfig {
    pub source_dump_sql: PathBuf,
    pub sqlite3_exe: PathBuf,
    pub runtime_db: PathBuf,
    pub work_dir: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LimitsConfig {
    pub max_radius: f64,
    pub max_limit: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ImporterConfig {
    #[serde(default = "default_importer_schema_version")]
    pub schema_version: u32,
    #[serde(default)]
    pub enable_rtree: bool,
    #[serde(default = "default_sqlite_import_timeout_secs")]
    pub sqlite_import_timeout_secs: u64,
}

fn default_max_concurrent_requests() -> usize {
    128
}

fn default_importer_schema_version() -> u32 {
    1
}

fn default_sqlite_import_timeout_secs() -> u64 {
    600
}

impl Default for ImporterConfig {
    fn default() -> Self {
        Self {
            schema_version: default_importer_schema_version(),
            enable_rtree: false,
            sqlite_import_timeout_secs: default_sqlite_import_timeout_secs(),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("configuration file not found: {0}")]
    FileNotFound(PathBuf),
    #[error("failed to read config file {path}: {source}")]
    FileRead {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse config file {path}: {source}")]
    Parse {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },
    #[error("invalid config: {0}")]
    Invalid(String),
}

impl Config {
    pub fn load() -> Result<Self, ConfigError> {
        let config_path = std::env::var("SENTINEL_QUERY_SERVER_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("config.toml"));

        Self::load_from_path(config_path)
    }

    pub fn load_from_path(path: impl AsRef<Path>) -> Result<Self, ConfigError> {
        let path = path.as_ref().to_path_buf();
        if !path.exists() {
            return Err(ConfigError::FileNotFound(path));
        }

        let raw = std::fs::read_to_string(&path).map_err(|source| ConfigError::FileRead {
            path: path.clone(),
            source,
        })?;

        let config: Config = toml::from_str(&raw).map_err(|source| ConfigError::Parse {
            path: path.clone(),
            source,
        })?;

        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> Result<(), ConfigError> {
        if self.server.host.trim().is_empty() {
            return Err(ConfigError::Invalid("server.host is required".to_string()));
        }

        if self.server.port == 0 {
            return Err(ConfigError::Invalid(
                "server.port must be greater than 0".to_string(),
            ));
        }

        if self.server.max_concurrent_requests == 0 {
            return Err(ConfigError::Invalid(
                "server.max_concurrent_requests must be greater than 0".to_string(),
            ));
        }

        if self.limits.max_radius <= 0.0 {
            return Err(ConfigError::Invalid(
                "limits.max_radius must be greater than 0".to_string(),
            ));
        }

        if self.limits.max_limit == 0 || self.limits.max_limit > 500 {
            return Err(ConfigError::Invalid(
                "limits.max_limit must be between 1 and 500".to_string(),
            ));
        }

        if self.importer.schema_version == 0 {
            return Err(ConfigError::Invalid(
                "importer.schema_version must be greater than 0".to_string(),
            ));
        }

        if self.importer.sqlite_import_timeout_secs == 0 {
            return Err(ConfigError::Invalid(
                "importer.sqlite_import_timeout_secs must be greater than 0".to_string(),
            ));
        }

        if self.paths.source_dump_sql.as_os_str().is_empty() {
            return Err(ConfigError::Invalid(
                "paths.source_dump_sql is required".to_string(),
            ));
        }

        if self.paths.sqlite3_exe.as_os_str().is_empty() {
            return Err(ConfigError::Invalid(
                "paths.sqlite3_exe is required".to_string(),
            ));
        }

        if self.paths.runtime_db.as_os_str().is_empty() {
            return Err(ConfigError::Invalid(
                "paths.runtime_db is required".to_string(),
            ));
        }

        if self.paths.work_dir.as_os_str().is_empty() {
            return Err(ConfigError::Invalid(
                "paths.work_dir is required".to_string(),
            ));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_validation_rejects_missing_host() {
        let cfg = Config {
            server: ServerConfig {
                host: String::new(),
                port: 8080,
                max_concurrent_requests: 1,
            },
            paths: PathsConfig {
                source_dump_sql: "a.sql".into(),
                sqlite3_exe: "sqlite3.exe".into(),
                runtime_db: "world.db".into(),
                work_dir: "work".into(),
            },
            limits: LimitsConfig {
                max_radius: 200.0,
                max_limit: 50,
            },
            importer: ImporterConfig::default(),
        };

        let err = cfg.validate().expect_err("validation should fail");
        assert!(err.to_string().contains("server.host"));
    }

    #[test]
    fn config_validation_rejects_invalid_limit() {
        let cfg = Config {
            server: ServerConfig {
                host: "127.0.0.1".to_string(),
                port: 8080,
                max_concurrent_requests: 1,
            },
            paths: PathsConfig {
                source_dump_sql: "a.sql".into(),
                sqlite3_exe: "sqlite3.exe".into(),
                runtime_db: "world.db".into(),
                work_dir: "work".into(),
            },
            limits: LimitsConfig {
                max_radius: 200.0,
                max_limit: 501,
            },
            importer: ImporterConfig::default(),
        };

        let err = cfg.validate().expect_err("validation should fail");
        assert!(err.to_string().contains("max_limit"));
    }
}
