//! Creature Service — Volume 4 §9

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct CreatureService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl CreatureService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn search_creatures(
        &self,
        _params: crate::api::creatures::CreatureSearchParams,
        _limit: u32,
    ) -> Result<Vec<CreatureDetails>> {
        // TODO: Implement actual search
        Ok(vec![])
    }

    pub async fn get_creature_spawns(&self, _entry: u32) -> Result<Vec<CreatureSpawn>> {
        // TODO: Implement actual spawn lookup
        Ok(vec![])
    }
}
