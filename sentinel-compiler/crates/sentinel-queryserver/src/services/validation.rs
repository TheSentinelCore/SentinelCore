//! Validation Service — Volume 4 §19

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct ValidationService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl ValidationService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn validate_profile(&self, fragment: serde_json::Value) -> Result<ValidationResult> {
        self.validate(fragment).await
    }

    pub async fn validate(&self, _fragment: serde_json::Value) -> Result<ValidationResult> {
        Ok(ValidationResult {
            warnings: vec![],
            errors: vec![],
            suggestions: vec![],
            database_issues: vec![],
        })
    }
}
