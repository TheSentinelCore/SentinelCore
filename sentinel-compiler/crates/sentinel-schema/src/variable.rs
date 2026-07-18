//! Variable types — Volume 5 §"Variables", Volume 2 §9
//! 
//! See: docs/adr/005-schema.md, docs/adr/002-runtime-architecture.md

use serde::{Deserialize, Serialize};

use crate::geometry::Waypoint;

// VariableValue is defined in enums.rs and re-exported from there
use crate::enums::VariableValue;

/// Variable — Volume 5 §"Variables"
/// 
/// Strongly-typed variables replacing hidden runtime flags.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Variable {
    pub name: String,
    pub value: VariableValue,
}

impl Variable {
    pub fn bool(name: impl Into<String>, value: bool) -> Self {
        Self { name: name.into(), value: VariableValue::Bool(value) }
    }
    
    pub fn integer(name: impl Into<String>, value: i64) -> Self {
        Self { name: name.into(), value: VariableValue::Integer(value) }
    }
    
    pub fn float(name: impl Into<String>, value: f64) -> Self {
        Self { name: name.into(), value: VariableValue::Float(value) }
    }
    
    pub fn string(name: impl Into<String>, value: impl Into<String>) -> Self {
        Self { name: name.into(), value: VariableValue::String(value.into()) }
    }
    
    pub fn position(name: impl Into<String>, value: Waypoint) -> Self {
        Self { name: name.into(), value: VariableValue::Position(value) }
    }
    
    pub fn quest_id(name: impl Into<String>, value: u32) -> Self {
        Self { name: name.into(), value: VariableValue::QuestId(value) }
    }
    
    pub fn npc_id(name: impl Into<String>, value: u32) -> Self {
        Self { name: name.into(), value: VariableValue::NpcId(value) }
    }
}