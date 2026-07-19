//! Metadata & Settings — Volume 5 §"Metadata", "Profile Settings"
//! 
//! See: docs/adr/005-schema.md

use serde::{Deserialize, Serialize};

/// Profile Settings — Volume 5 §"Profile Settings"
/// 
/// Automation behavior flags.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ProfileSettings {
    pub auto_vendor: bool,
    pub auto_repair: bool,
    pub auto_train: bool,
    pub auto_loot: bool,
    pub auto_accept: bool,
    pub auto_turnin: bool,
    pub use_flight_paths: bool,
    pub allow_hearthstone: bool,
    pub use_mailbox: bool,
    pub death_skip: bool,
    pub dry_run_enabled: bool,
}

/// Metadata — Volume 5 §"Metadata"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Metadata {
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub editor_version: String,
    pub compiler_version: String,
    pub notes: Option<String>,
    pub source: SourceType,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "PascalCase")]
pub enum SourceType {
    #[default]
    Manual,
    Captured,
    Imported,
    Migrated,
}

impl Default for Metadata {
    fn default() -> Self {
        let now = chrono::Utc::now();
        Self {
            created_at: now,
            updated_at: now,
            editor_version: env!("CARGO_PKG_VERSION").to_string(),
            compiler_version: env!("CARGO_PKG_VERSION").to_string(),
            notes: None,
            source: SourceType::Manual,
        }
    }
}

/// Level Range — Volume 5 §"Root Profile", "Operation"
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LevelRange {
    pub min: u8,
    pub max: u8,
}

impl Default for LevelRange {
    fn default() -> Self {
        Self { min: 1, max: 80 }
    }
}

impl LevelRange {
    pub fn new(min: u8, max: u8) -> Self {
        Self { min, max }
    }
    
    pub fn contains(&self, level: u8) -> bool {
        level >= self.min && level <= self.max
    }
}

/// Source Type for profile origin tracking
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "PascalCase")]
pub enum ProfileSource {
    #[default]
    Manual,
    Captured,
    Imported,
    Migrated,
}