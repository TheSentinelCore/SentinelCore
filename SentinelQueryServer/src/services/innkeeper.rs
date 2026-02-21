use std::sync::Arc;

use crate::error::AppResult;
use crate::models::{PagedResponse, UtilityEntity};
use crate::storage::repositories::flight_master::{UtilityListQuery, UtilityNearbyQuery};
use crate::storage::repositories::innkeeper::InnkeeperRepository;

pub trait InnkeeperService: Send + Sync {
    fn list_innkeepers(
        &self,
        map_id: i64,
        query: UtilityListQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>>;
    fn nearby_innkeepers(
        &self,
        map_id: i64,
        query: UtilityNearbyQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>>;
}

#[derive(Clone)]
pub struct DefaultInnkeeperService {
    repo: Arc<InnkeeperRepository>,
}

impl DefaultInnkeeperService {
    pub fn new(repo: Arc<InnkeeperRepository>) -> Self {
        Self { repo }
    }
}

impl InnkeeperService for DefaultInnkeeperService {
    fn list_innkeepers(
        &self,
        map_id: i64,
        query: UtilityListQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>> {
        self.repo.list_innkeepers(map_id, &query)
    }

    fn nearby_innkeepers(
        &self,
        map_id: i64,
        query: UtilityNearbyQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>> {
        self.repo.nearby_innkeepers(map_id, &query)
    }
}
