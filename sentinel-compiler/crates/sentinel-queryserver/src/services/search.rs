//! Search Everywhere Service — Volume 4 §20

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct SearchService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl SearchService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn search_all(&self, _query: &str, _limit: u32) -> Result<SearchResult> {
        Ok(SearchResult {
            npcs: vec![],
            quests: vec![],
            items: vec![],
            objects: vec![],
            zones: vec![],
            creatures: vec![],
            vendors: vec![],
            trainers: vec![],
        })
    }
}
