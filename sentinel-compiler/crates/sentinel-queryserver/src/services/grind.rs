//! Grind Suggestion Service — Volume 4 §22

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct GrindSuggestionService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl GrindSuggestionService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn suggest_grind(
        &self,
        request: crate::api::grind::GrindSuggestRequest,
    ) -> Result<GrindSuggestion> {
        self.suggest(request).await
    }

    pub async fn suggest(
        &self,
        _req: crate::api::grind::GrindSuggestRequest,
    ) -> Result<GrindSuggestion> {
        Ok(GrindSuggestion {
            best_creatures: vec![],
            drop_rates: vec![],
            xp_per_hour: 0.0,
            suggested_loot: vec![],
            quest_overlap: vec![],
        })
    }
}
