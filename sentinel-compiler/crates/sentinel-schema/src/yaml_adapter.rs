//! YAML Serialization Adapter — Volume 11 §2
//!
//! Provides YAML (de)serialization for all Phase 1 schema types.

use serde::{Deserialize, Serialize};

/// Serialize a Profile to YAML format
pub fn to_yaml_string<T: Serialize>(value: &T) -> Result<String, serde_yaml::Error> {
    serde_yaml::to_string(value)
}

/// Deserialize a Profile from YAML format
pub fn from_yaml_string<T: for<'de> Deserialize<'de>>(yaml: &str) -> Result<T, serde_yaml::Error> {
    serde_yaml::from_str(yaml)
}

/// Workspace definition — Volume 11 §3
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Workspace {
    pub version: String,
    pub profile: WorkspaceProfileRef,
    pub settings: WorkspaceSettings,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceProfileRef {
    pub file: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceSettings {
    pub editor: EditorSettings,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EditorSettings {
    pub layout: String, // JSON string for layout state
}

// Re-export commonly used functions
pub use to_yaml_string as to_yaml;
pub use from_yaml_string as from_yaml;