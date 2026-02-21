use std::sync::Arc;

use crate::error::AppError;
use crate::models::{PagedResponse, UtilityEntity};
use crate::storage::repositories::flight_master::{
    list_utility_entities, nearby_utility_entities, UtilityListQuery, UtilityNearbyQuery,
};
use crate::storage::SqliteStore;
use crate::validation::NPC_FLAG_INNKEEPER;

const ENDPOINT_INNKEEPERS_LIST: &str = "innkeepers_list";
const ENDPOINT_INNKEEPERS_NEARBY: &str = "innkeepers_nearby";

#[derive(Clone)]
pub struct InnkeeperRepository {
    store: Arc<SqliteStore>,
}

impl InnkeeperRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn list_innkeepers(
        &self,
        map_id: i64,
        query: &UtilityListQuery,
    ) -> Result<PagedResponse<UtilityEntity>, AppError> {
        list_utility_entities(
            &self.store,
            map_id,
            query,
            NPC_FLAG_INNKEEPER,
            ENDPOINT_INNKEEPERS_LIST,
        )
    }

    pub fn nearby_innkeepers(
        &self,
        map_id: i64,
        query: &UtilityNearbyQuery,
    ) -> Result<PagedResponse<UtilityEntity>, AppError> {
        nearby_utility_entities(
            &self.store,
            map_id,
            query,
            NPC_FLAG_INNKEEPER,
            ENDPOINT_INNKEEPERS_NEARBY,
        )
    }
}
