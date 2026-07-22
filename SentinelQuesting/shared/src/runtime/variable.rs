//! Runtime variables — seeded from defaults at compile time.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::authoring::{VariableType, VariableValue};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeVariable {
    pub id: Uuid,
    pub name: String,
    pub type_: VariableType,
    pub default_value: VariableValue,
    /// Seeded from `default_value` by the compiler; mutated by `RuntimeSetVariable` at runtime.
    pub current_value: VariableValue,
}

impl RuntimeVariable {
    pub fn new(name: impl Into<String>, type_: VariableType, default_value: VariableValue) -> Self {
        let current = default_value.clone();
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            type_,
            default_value,
            current_value: current,
        }
    }
}
