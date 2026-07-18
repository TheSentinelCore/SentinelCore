//! Blueprint Suggestion Service — Volume 4 §21

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct BlueprintSuggestionService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl BlueprintSuggestionService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn suggest_blueprint(
        &self,
        request: crate::api::blueprints::BlueprintSuggestRequest,
    ) -> Result<BlueprintSuggestion> {
        self.suggest(request).await
    }

    pub async fn suggest(
        &self,
        _req: crate::api::blueprints::BlueprintSuggestRequest,
    ) -> Result<BlueprintSuggestion> {
        Ok(BlueprintSuggestion {
            blueprint_type: "QuestHub".to_string(),
            confidence: 0.8,
            suggested_params: serde_json::Value::Null,
        })
    }
}
