//! Condition types — Volume 5 §"Conditions" + Volume 7 §6 extensions
//! 
//! See: docs/adr/005-schema.md §"Conditions", docs/adr/007-operations.md §6

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::enums::{Faction, Race, Class, VariableValue};

/// Condition — Volume 5 §"Conditions" + Volume 7 §6
/// 
/// Used for action conditions, entry conditions, and exit conditions.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "PascalCase")]
pub enum Condition {
    // Volume 5 base conditions
    QuestAccepted(u32),
    QuestCompleted(u32),
    QuestRewarded(u32),
    LevelAtLeast(u8),
    LevelBelow(u8),
    HasItem(u32),
    BagSpace(u32),
    DurabilityBelow(f32),
    GoldAbove(u32),
    VariableEquals(String, VariableValue), // name, value
    VariableTrue(String),
    VariableFalse(String),
    
    // Volume 7 §6 additions — Operation-aware conditions
    OperationCompleted(Uuid),
    OperationSkipped(Uuid),
    OperationFailed(Uuid),
    FactionIs(Faction),
    RaceIs(Race),
    ClassIs(Class),
    ZoneEntered(String),
    
    // Quest chain conditions
    QuestFailed(u32),
    QuestTurnedIn(u32),
    QuestAvailable(u32),
    
    // State conditions
    HasFlightPath(u32),
    HasSpell(u32),
    InCombat(bool),
    Dead(bool),
    Mounted(bool),
    
    // Custom
    Custom(String),
}

/// Exit Conditions — Volume 7 §7
/// 
/// Three distinct outcome categories checked in priority order: Abort > Failure > Success
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ExitConditions {
    pub success: Vec<Condition>,
    pub failure: Vec<Condition>,
    pub abort: Vec<Condition>,
}

impl ExitConditions {
    pub fn new() -> Self {
        Self::default()
    }
    
    pub fn with_success(mut self, conditions: Vec<Condition>) -> Self {
        self.success = conditions;
        self
    }
    
    pub fn with_failure(mut self, conditions: Vec<Condition>) -> Self {
        self.failure = conditions;
        self
    }
    
    pub fn with_abort(mut self, conditions: Vec<Condition>) -> Self {
        self.abort = conditions;
        self
    }
}

/// Operation Goal — Volume 7 §4
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OperationGoal {
    pub id: Uuid,
    pub description: String,
    pub goal_type: crate::enums::GoalType,
    pub required: bool,
    pub weight: f32,
}

impl OperationGoal {
    pub fn required(description: impl Into<String>, goal_type: crate::enums::GoalType, weight: f32) -> Self {
        Self {
            id: Uuid::new_v4(),
            description: description.into(),
            goal_type,
            required: true,
            weight,
        }
    }
    
    pub fn optional(description: impl Into<String>, goal_type: crate::enums::GoalType, weight: f32) -> Self {
        Self {
            id: Uuid::new_v4(),
            description: description.into(),
            goal_type,
            required: false,
            weight,
        }
    }
}

/// Operation Dependency — Volume 7 §10
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OperationDependency {
    pub operation_id: Uuid,
    pub relationship: crate::enums::DependencyType,
}

impl OperationDependency {
    pub fn requires(operation_id: Uuid) -> Self {
        Self { operation_id, relationship: crate::enums::DependencyType::Requires }
    }
    
    pub fn soft_prefers(operation_id: Uuid) -> Self {
        Self { operation_id, relationship: crate::enums::DependencyType::SoftPrefers }
    }
    
    pub fn excludes_with(operation_id: Uuid) -> Self {
        Self { operation_id, relationship: crate::enums::DependencyType::ExcludesWith }
    }
    
    pub fn unlocks_after(operation_id: Uuid) -> Self {
        Self { operation_id, relationship: crate::enums::DependencyType::UnlocksAfter }
    }
}