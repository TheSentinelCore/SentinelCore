use std::sync::Arc;

use crate::error::AppResult;
use crate::models::ItemInfo;
use crate::storage::repositories::item::ItemRepository;

pub trait ItemService: Send + Sync {
    fn get_items_by_ids(&self, ids: &[i64]) -> AppResult<Vec<ItemInfo>>;
}

#[derive(Clone)]
pub struct DefaultItemService {
    repo: Arc<ItemRepository>,
}

impl DefaultItemService {
    pub fn new(repo: Arc<ItemRepository>) -> Self {
        Self { repo }
    }
}

impl ItemService for DefaultItemService {
    fn get_items_by_ids(&self, ids: &[i64]) -> AppResult<Vec<ItemInfo>> {
        self.repo.get_items_by_ids(ids)
    }
}
