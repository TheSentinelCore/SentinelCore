//! Quest Hub Analysis Service — Volume 4 §18

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct HubService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl HubService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn analyze_quest_hub(&self, entry: u32) -> Result<QuestHubAnalysis> {
        self.analyze(entry).await
    }

    pub async fn analyze(&self, _entry: u32) -> Result<QuestHubAnalysis> {
        Ok(QuestHubAnalysis {
            available_quests: vec![],
            nearby_vendor: None,
            nearby_trainer: None,
            nearby_mailbox: None,
            nearby_flight: None,
            nearby_repair: None,
            nearby_inn: None,
            nearby_bank: None,
        })
    }
}
