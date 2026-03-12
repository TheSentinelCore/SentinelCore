use std::sync::Arc;

use crate::error::AppResult;
use crate::models::{PagedResponse, TrainerDetail, TrainerEntity, TrainerSpell};
use crate::storage::repositories::trainer::{
    TrainerListQuery, TrainerNearbyQuery, TrainerRepository,
};

pub trait TrainerService: Send + Sync {
    fn list_trainers(
        &self,
        map_id: i64,
        query: TrainerListQuery,
    ) -> AppResult<PagedResponse<TrainerEntity>>;
    fn nearby_trainers(
        &self,
        map_id: i64,
        query: TrainerNearbyQuery,
    ) -> AppResult<PagedResponse<TrainerEntity>>;
    fn trainer_detail(&self, entry: i64) -> AppResult<TrainerDetail>;
    fn trainer_spells(&self, entry: i64) -> AppResult<Vec<TrainerSpell>>;
}

#[derive(Clone)]
pub struct DefaultTrainerService {
    repo: Arc<TrainerRepository>,
}

impl DefaultTrainerService {
    pub fn new(repo: Arc<TrainerRepository>) -> Self {
        Self { repo }
    }
}

impl TrainerService for DefaultTrainerService {
    fn list_trainers(
        &self,
        map_id: i64,
        query: TrainerListQuery,
    ) -> AppResult<PagedResponse<TrainerEntity>> {
        self.repo.list_trainers(map_id, &query)
    }

    fn nearby_trainers(
        &self,
        map_id: i64,
        query: TrainerNearbyQuery,
    ) -> AppResult<PagedResponse<TrainerEntity>> {
        self.repo.nearby_trainers(map_id, &query)
    }

    fn trainer_detail(&self, entry: i64) -> AppResult<TrainerDetail> {
        self.repo.trainer_detail(entry)
    }

    fn trainer_spells(&self, entry: i64) -> AppResult<Vec<TrainerSpell>> {
        self.repo.trainer_spells(entry)
    }
}
