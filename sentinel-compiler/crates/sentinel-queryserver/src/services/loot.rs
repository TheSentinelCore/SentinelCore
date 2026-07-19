//! Loot Service — Volume 4 §23

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct LootService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl LootService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn get_item_drops(&self, item_id: u32) -> Result<ItemDrops> {
        self.get_drops(item_id).await
    }

    pub async fn get_drops(&self, item_id: u32) -> Result<ItemDrops> {
        Ok(ItemDrops {
            item_id,
            drops: vec![],
        })
    }
}
