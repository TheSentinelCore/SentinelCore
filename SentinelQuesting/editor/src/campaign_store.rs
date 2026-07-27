//! CampaignStore — filesystem CRUD for `.questing/campaigns/*.json`.
//!
//! Each campaign is stored as a self-contained JSON file in the campaigns
//! directory, keyed by `slugify(name).json`. Load/save use atomic write to
//! prevent corruption on crash.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sentinel_models::platform::Campaign;
use uuid::Uuid;

use crate::EditorError;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert a display name into a safe file‑system identifier.
///
/// * Lowercases
/// * Replaces any non‑alphanumeric character (except `-` / `_`) with `_`
fn slugify(name: &str) -> String {
    name.to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect()
}

fn campaign_path(campaigns_dir: &Path, name: &str) -> PathBuf {
    campaigns_dir.join(format!("{}.json", slugify(name)))
}

fn format_timestamp(modified: Option<std::time::SystemTime>) -> String {
    match modified {
        Some(time) => {
            let dt: DateTime<Utc> = time.into();
            dt.to_rfc3339()
        }
        None => "unknown".to_string(),
    }
}

/// Atomically write a file by writing to a temporary then renaming.
fn atomic_write(path: &Path, content: &str) -> Result<(), EditorError> {
    let tmp_path = path.with_extension("tmp");
    fs::write(&tmp_path, content)?;
    fs::rename(&tmp_path, path)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A lightweight summary of a campaign, returned by `CampaignApi::list()`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CampaignSummary {
    pub name: String,
    pub id: Uuid,
    pub updated_at: String,
    pub node_count: usize,
    pub edge_count: usize,
}

// ---------------------------------------------------------------------------
// CampaignApi — filesystem CRUD
// ---------------------------------------------------------------------------

pub struct CampaignApi;

impl CampaignApi {
    /// Validate a campaign name (no path separators, no `..`, not empty).
    fn validate_name(name: &str) -> Result<(), EditorError> {
        if name.is_empty() || name.contains('/') || name.contains('\\') || name.contains("..") {
            return Err(EditorError::InvalidName(name.to_string()));
        }
        Ok(())
    }

    /// Scan the campaigns directory and return a sorted listing.
    pub fn list(campaigns_dir: &Path) -> Result<Vec<CampaignSummary>, EditorError> {
        if !campaigns_dir.exists() {
            return Ok(Vec::new());
        }

        let mut summaries = Vec::new();
        for entry in fs::read_dir(campaigns_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "json") {
                let stem = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .to_string();

                match Self::load_inner(&path) {
                    Ok(campaign) => {
                        let node_count: usize =
                            campaign.graphs.iter().map(|g| g.nodes.len()).sum();
                        let edge_count: usize =
                            campaign.graphs.iter().map(|g| g.edges.len()).sum();
                        summaries.push(CampaignSummary {
                            name: campaign.name,
                            id: campaign.id,
                            updated_at: format_timestamp(
                                fs::metadata(&path).ok().and_then(|m| m.modified().ok()),
                            ),
                            node_count,
                            edge_count,
                        });
                    }
                    Err(_) => {
                        // Corrupt entry — list with basic metadata.
                        if let Ok(meta) = fs::metadata(&path) {
                            summaries.push(CampaignSummary {
                                name: stem,
                                id: Uuid::nil(),
                                updated_at: format_timestamp(meta.modified().ok()),
                                node_count: 0,
                                edge_count: 0,
                            });
                        }
                    }
                }
            }
        }

        summaries.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(summaries)
    }

    /// Create a new empty campaign with the given display name.
    pub fn create(campaigns_dir: &Path, name: &str) -> Result<Campaign, EditorError> {
        Self::validate_name(name)?;
        let path = campaign_path(campaigns_dir, name);
        if path.exists() {
            return Err(EditorError::AlreadyExists(name.to_string()));
        }

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        let campaign = Campaign::new(name);
        let json = serde_json::to_string_pretty(&campaign)?;
        atomic_write(&path, &json)?;
        Ok(campaign)
    }

    /// Load a campaign by its display name.
    pub fn load(campaigns_dir: &Path, name: &str) -> Result<Campaign, EditorError> {
        Self::validate_name(name)?;
        let path = campaign_path(campaigns_dir, name);
        Self::load_inner(&path)
    }

    /// Load a campaign from an explicit path.
    fn load_inner(path: &Path) -> Result<Campaign, EditorError> {
        if !path.exists() {
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("?");
            return Err(EditorError::NotFound(name.to_string()));
        }
        let json = fs::read_to_string(path)?;
        let campaign: Campaign = serde_json::from_str(&json)?;
        Ok(campaign)
    }

    /// Save (overwrite) a campaign to disk. Uses atomic write.
    pub fn save(campaigns_dir: &Path, campaign: &Campaign) -> Result<(), EditorError> {
        let name = &campaign.name;
        Self::validate_name(name)?;

        let path = campaign_path(campaigns_dir, name);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        let json = serde_json::to_string_pretty(campaign)?;
        atomic_write(&path, &json)?;
        Ok(())
    }

    /// Delete a campaign file by display name.
    pub fn delete(campaigns_dir: &Path, name: &str) -> Result<(), EditorError> {
        Self::validate_name(name)?;
        let path = campaign_path(campaigns_dir, name);
        if !path.exists() {
            return Err(EditorError::NotFound(name.to_string()));
        }
        fs::remove_file(path)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// Helper: create a temporary directory for campaign files.
    fn tmp_campaigns_dir() -> (PathBuf, tempfile::TempDir) {
        let dir = tempfile::tempdir().expect("failed to create temp dir");
        let campaigns_dir = dir.path().join("campaigns");
        std::fs::create_dir_all(&campaigns_dir).unwrap();
        (campaigns_dir, dir)
    }

    #[test]
    fn list_empty_when_dir_missing() {
        let dir = PathBuf::from("/tmp/nonexistent-campaigns-test");
        let campaigns = CampaignApi::list(&dir).unwrap();
        assert!(campaigns.is_empty());
    }

    #[test]
    fn create_and_list_campaign() {
        let (dir, _tmp) = tmp_campaigns_dir();
        let campaign = CampaignApi::create(&dir, "Test Campaign").unwrap();
        assert_eq!(campaign.name, "Test Campaign");
        assert_ne!(campaign.id, Uuid::nil());

        let campaigns = CampaignApi::list(&dir).unwrap();
        assert_eq!(campaigns.len(), 1);
        assert_eq!(campaigns[0].name, "Test Campaign");
    }

    #[test]
    fn create_duplicate_fails() {
        let (dir, _tmp) = tmp_campaigns_dir();
        CampaignApi::create(&dir, "dup-campaign").unwrap();
        let result = CampaignApi::create(&dir, "dup-campaign");
        assert!(matches!(result, Err(EditorError::AlreadyExists(_))));
    }

    #[test]
    fn load_nonexistent_fails() {
        let (dir, _tmp) = tmp_campaigns_dir();
        let result = CampaignApi::load(&dir, "nope");
        assert!(matches!(result, Err(EditorError::NotFound(_))));
    }

    #[test]
    fn save_and_reload_campaign() {
        let (dir, _tmp) = tmp_campaigns_dir();
        let mut campaign = CampaignApi::create(&dir, "save-test").unwrap();
        campaign.schema_version = 42;
        CampaignApi::save(&dir, &campaign).unwrap();

        let loaded = CampaignApi::load(&dir, "save-test").unwrap();
        assert_eq!(loaded.schema_version, 42);
    }

    #[test]
    fn delete_campaign() {
        let (dir, _tmp) = tmp_campaigns_dir();
        CampaignApi::create(&dir, "to-delete").unwrap();
        CampaignApi::delete(&dir, "to-delete").unwrap();
        let campaigns = CampaignApi::list(&dir).unwrap();
        assert!(campaigns.is_empty());
    }

    #[test]
    fn slugify_creates_safe_filename() {
        let (dir, _tmp) = tmp_campaigns_dir();
        CampaignApi::create(&dir, "My Campaign!").unwrap();
        // Should exist as `my_campaign_.json`
        let path = dir.join("my_campaign_.json");
        assert!(path.exists());

        // Load by original display name
        let loaded = CampaignApi::load(&dir, "My Campaign!").unwrap();
        assert_eq!(loaded.name, "My Campaign!");

        // Load by slug
        let loaded2 = CampaignApi::load(&dir, "my_campaign_").unwrap();
        assert_eq!(loaded2.name, "My Campaign!");
    }

    #[test]
    fn list_returns_summary_counts() {
        let (dir, _tmp) = tmp_campaigns_dir();
        // A fresh campaign has no graphs, so counts are zero.
        CampaignApi::create(&dir, "counts").unwrap();
        let summaries = CampaignApi::list(&dir).unwrap();
        assert_eq!(summaries[0].node_count, 0);
        assert_eq!(summaries[0].edge_count, 0);
    }

    #[test]
    fn invalid_name_rejected() {
        let (dir, _tmp) = tmp_campaigns_dir();
        assert!(matches!(
            CampaignApi::create(&dir, "has/slash"),
            Err(EditorError::InvalidName(_))
        ));
        assert!(matches!(
            CampaignApi::create(&dir, ""),
            Err(EditorError::InvalidName(_))
        ));
        assert!(matches!(
            CampaignApi::create(&dir, "has..dots"),
            Err(EditorError::InvalidName(_))
        ));
    }
}
