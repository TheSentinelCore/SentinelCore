//! Core enums — Volume 5 §"Enums" + Volume 7 additions
//! 
//! See: docs/adr/005-schema.md §"Design Decisions", docs/adr/007-operations.md §3

use serde::{Deserialize, Serialize};

use crate::geometry::Waypoint;

/// Game version target — Volume 5 §"Root Profile"
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum GameVersion {
    TbcClassic,
    WrathClassic,
    CataclysmClassic,
}

/// Faction — Volume 5 §"Root Profile"
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Faction {
    Alliance,
    Horde,
    Neutral,
}

/// Race — Volume 5 §"Root Profile"
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Race {
    Human,
    Orc,
    Dwarf,
    NightElf,
    Undead,
    Tauren,
    Gnome,
    Troll,
    BloodElf,
    Draenei,
}

/// Class — Volume 5 §"Root Profile"
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Class {
    Warrior,
    Paladin,
    Hunter,
    Rogue,
    Priest,
    DeathKnight,
    Shaman,
    Mage,
    Warlock,
    Druid,
}

/// NPC Role — Volume 5 §"NPC Reference"
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum NpcRole {
    QuestGiver,
    Vendor,
    Trainer,
    Innkeeper,
    FlightMaster,
    Repair,
    Mailbox,
    Bank,
    Auctioneer,
    SpiritHealer,
    Generic,
}

/// Blueprint Category — Volume 6 §4
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum BlueprintCategory {
    Quest,
    Travel,
    Combat,
    Npc,
    NpcServices,
    Inventory,
    Economy,
    Utility,
    Recovery,
    Dungeon,
    Custom,
}

/// Goal Type — Volume 7 §4
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "PascalCase")]
pub enum GoalType {
    CompleteQuest(u32),
    CompleteQuestChain(Vec<u32>),
    ReachLevel(u8),
    GainXp(u64),
    ReachZone(String),
    ReachWaypoint(Waypoint),
    AcquireItem(u32, u32), // item_id, count
    KillCount(u32, u32),    // creature_id, count
    UnlockFlightPath(u32),
    LearnSpell(u32),
    Custom(String),
}

/// Dependency Type — Volume 7 §10
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum DependencyType {
    Requires,
    SoftPrefers,
    ExcludesWith,
    UnlocksAfter,
}

/// Operation Status — Volume 7 §13
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum OperationStatus {
    Locked,
    Ready,
    Active,
    Completed,
    Failed,
    Aborted,
    Skipped,
}

/// Variable Value — Volume 5 §"Variable Types" + Volume 2 §9
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "PascalCase")]
pub enum VariableValue {
    Bool(bool),
    Integer(i64),
    Float(f64),
    String(String),
    Position(Waypoint),
    QuestId(u32),
    NpcId(u32),
    Enum(String), // string value of enum
}

/// Level Range — Volume 5 §"Root Profile", "Operation"
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
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

/// Optimization Policy — Volume 7 §8
/// 
/// Per-Operation tuning instead of global policy.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OptimizationPolicy {
    pub travel_weight: f32,
    pub xp_weight: f32,
    pub time_weight: f32,
    pub risk_weight: f32,
    pub cluster_objectives: bool,
    pub allow_reordering: bool,
    pub grind_fallback: bool,
    pub max_deaths: Option<u32>,
}

impl Default for OptimizationPolicy {
    fn default() -> Self {
        Self {
            travel_weight: 0.5,
            xp_weight: 0.3,
            time_weight: 0.2,
            risk_weight: 0.3,
            cluster_objectives: true,
            allow_reordering: true,
            grind_fallback: false,
            max_deaths: None,
        }
    }
}

impl OptimizationPolicy {
    pub fn safe_low_level() -> Self {
        Self {
            risk_weight: 0.1,
            cluster_objectives: true,
            allow_reordering: true,
            grind_fallback: false,
            max_deaths: Some(3),
            ..Default::default()
        }
    }
    
    pub fn dangerous_high_level() -> Self {
        Self {
            risk_weight: 0.8,
            cluster_objectives: false,
            allow_reordering: false,
            grind_fallback: true,
            max_deaths: Some(1),
            ..Default::default()
        }
    }
}

/// Completion Metrics — Volume 7 §9
/// 
/// Targets for analytics comparison, not pass/fail gates.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct CompletionMetrics {
    pub target_duration_ms: Option<u64>,
    pub target_xp: Option<u64>,
    pub min_success_rate: Option<f32>,
    pub max_acceptable_deaths: Option<u32>,
}

/// Operation Analytics — Volume 7 §19
/// 
/// Runtime telemetry for telemetry-driven authoring feedback.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct OperationAnalytics {
    pub runs: u32,
    pub average_duration_ms: u64,
    pub average_xp: f64,
    pub average_gold: f64,
    pub average_deaths: f32,
    pub success_rate: f32,
    pub skip_rate: f32,
    pub last_run: Option<chrono::DateTime<chrono::Utc>>,
    pub bottleneck_actions: Vec<uuid::Uuid>,
}

/// Retry Policy — Volume 5 §"Retry Policy"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RetryPolicy {
    pub retries: u32,
    pub delay_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self { retries: 3, delay_ms: 1000 }
    }
}

impl RetryPolicy {
    pub fn new(retries: u32, delay_ms: u64) -> Self {
        Self { retries, delay_ms }
    }
    
    pub fn none() -> Self {
        Self { retries: 0, delay_ms: 0 }
    }
    
    pub fn aggressive() -> Self {
        Self { retries: 5, delay_ms: 500 }
    }
    
    pub fn conservative() -> Self {
        Self { retries: 2, delay_ms: 5000 }
    }
}