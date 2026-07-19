//! Blueprint — Volume 6 §6 Blueprint Structure
//! 
//! See: docs/adr/006-blueprints.md

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::enums::BlueprintCategory;
use crate::action::Action;
use crate::reference::{NpcReference, QuestReference, VendorEntry, CreatureReference, FlightNode};
use crate::geometry::{Waypoint, Polygon};

/// Blueprint — Volume 6 §6
/// 
/// Reusable authoring template that expands into runtime actions during compilation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Blueprint {
    pub id: Uuid,
    pub name: String,
    pub category: BlueprintCategory,
    pub description: String,
    pub icon: String,
    pub parameters: Vec<BlueprintParameter>,
    pub outputs: Vec<Action>, // Template actions with parameter placeholders
}

impl Blueprint {
    pub fn new(name: impl Into<String>, category: BlueprintCategory) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            category,
            description: String::new(),
            icon: String::new(),
            parameters: Vec::new(),
            outputs: Vec::new(),
        }
    }
}

/// Blueprint Parameter — Volume 6 §7, §13
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BlueprintParameter {
    pub name: String,
    pub param_type: ParameterType,
    pub required: bool,
    pub default: Option<ParameterValue>,
    pub description: String,
}

/// Parameter Types — Volume 6 §13
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum ParameterType {
    Npc,
    Quest,
    Waypoint,
    Polygon,
    Creature,
    Vendor,
    Trainer,
    Flight,
    Boolean,
    Integer,
    Float,
    String,
    Enum,
}

/// Parameter Value for blueprint instantiation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "PascalCase")]
pub enum ParameterValue {
    Npc(NpcReference),
    Quest(QuestReference),
    Waypoint(Waypoint),
    Polygon(Polygon),
    Creature(CreatureReference),
    Vendor(VendorEntry),
    Trainer(NpcReference),
    Flight(FlightNode),
    Boolean(bool),
    Integer(i64),
    Float(f64),
    String(String),
    Enum(String),
}

impl BlueprintParameter {
    pub fn required(name: impl Into<String>, param_type: ParameterType, description: impl Into<String>) -> Self {
        Self { name: name.into(), param_type, description: description.into(), required: true, default: None }
    }
    
    pub fn optional(name: impl Into<String>, param_type: ParameterType, description: impl Into<String>, default: ParameterValue) -> Self {
        Self { name: name.into(), param_type, description: description.into(), required: false, default: Some(default) }
    }
}

/// Blueprint Reference — Volume 5 §"Blueprint Reference" + Volume 6
/// 
/// Reference to a Blueprint instance with parameter values filled in.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BlueprintReference {
    pub id: String,
    pub version: String,
    pub parameters: serde_json::Value, // Keyed by parameter name
}

impl BlueprintReference {
    pub fn new(id: impl Into<String>, version: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            version: version.into(),
            parameters: serde_json::Value::Object(Default::default()),
        }
    }
    
    pub fn with_param(mut self, name: impl Into<String>, value: serde_json::Value) -> Self {
        if let serde_json::Value::Object(ref mut map) = self.parameters {
            map.insert(name.into(), value);
        }
        self
    }
}