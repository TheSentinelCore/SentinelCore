use std::sync::Arc;

use crate::error::AppResult;
use crate::storage::repositories::entity::{
    EntityRepository, UnifiedNearbyQuery, UnifiedNearbyResponse,
};

pub trait EntityService: Send + Sync {
    fn nearby_entities(
        &self,
        map_id: i64,
        query: UnifiedNearbyQuery,
    ) -> AppResult<UnifiedNearbyResponse>;
}

#[derive(Clone)]
pub struct DefaultEntityService {
    repo: Arc<EntityRepository>,
}

impl DefaultEntityService {
    pub fn new(repo: Arc<EntityRepository>) -> Self {
        Self { repo }
    }
}

impl EntityService for DefaultEntityService {
    fn nearby_entities(
        &self,
        map_id: i64,
        query: UnifiedNearbyQuery,
    ) -> AppResult<UnifiedNearbyResponse> {
        self.repo.nearby_entities(map_id, &query)
    }
}
