//! Sentinel Schema — Canonical authoring data model
//! 
//! Volume 5 (Canonical Profile Schema) + Volume 7 (Operation System revisions)
//! 
//! This crate defines the data structures that the in-game editor manipulates
//! and the compiler consumes. It has NO logic — just types and serde.
//! 
//! See: docs/adr/005-schema.md, docs/adr/007-operations.md

pub mod action;
pub mod analytics;
pub mod blueprint;
pub mod condition;
pub mod enums;
pub mod geometry;
pub mod metadata;
pub mod operation;
pub mod profile;
pub mod reference;
pub mod retry;
pub mod variable;

// Re-export commonly used types
pub use action::{Action, ActionPayload};
pub use analytics::Analytics;
pub use blueprint::{Blueprint, BlueprintReference, BlueprintParameter, ParameterType, ParameterValue};
pub use condition::{Condition, ExitConditions, OperationGoal, OperationDependency};
pub use enums::*;
pub use geometry::{Waypoint, Path, Polygon};
pub use metadata::{Metadata, ProfileSettings, LevelRange, ProfileSource};
pub use operation::Operation;
pub use profile::Profile;
pub use reference::*;
pub use retry::RetryPolicy;
pub use variable::{Variable};
pub use enums::VariableValue;

/// Prelude for common imports
pub mod prelude {
    pub use crate::{
        Profile, Operation, Action, ActionPayload,
        Blueprint, BlueprintReference, BlueprintParameter,
        NpcReference, QuestReference, VendorEntry,
        CreatureReference, ItemReference, GameObjectReference,
        Waypoint, Path, Polygon,
        Variable, VariableValue,
        Condition, ExitConditions,
        OperationGoal, OperationDependency,
        RetryPolicy, LevelRange,
        ProfileSettings, Metadata, ProfileSource,
        Analytics,
        GoalType, NpcRole, BlueprintCategory, ParameterType,
        OperationStatus, GameVersion, Faction, Race, Class,
    };
    
    pub use uuid::Uuid;
    pub use serde::{Serialize, Deserialize};
}