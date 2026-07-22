//! Variables replace dozens of Honorbuddy hacks (ADR `02_DATA_MODEL` §7).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::enums::{VariableType, VariableValue};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Variable {
    pub id: Uuid,
    pub name: String,
    pub type_: VariableType,
    pub default_value: VariableValue,
    /// Runtime-populated; absent in a freshly authored project.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_value: Option<VariableValue>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

impl Variable {
    pub fn new(name: impl Into<String>, type_: VariableType, default_value: VariableValue) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            type_,
            default_value,
            current_value: None,
            description: None,
        }
    }
}
