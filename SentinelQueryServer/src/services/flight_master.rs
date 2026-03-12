use std::sync::Arc;

use crate::error::AppResult;
use crate::models::{PagedResponse, UtilityEntity};
use crate::storage::repositories::flight_master::{
    FlightMasterRepository, UtilityListQuery, UtilityNearbyQuery,
};

pub trait FlightMasterService: Send + Sync {
    fn list_flight_masters(
        &self,
        map_id: i64,
        query: UtilityListQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>>;
    fn nearby_flight_masters(
        &self,
        map_id: i64,
        query: UtilityNearbyQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>>;
}

#[derive(Clone)]
pub struct DefaultFlightMasterService {
    repo: Arc<FlightMasterRepository>,
}

impl DefaultFlightMasterService {
    pub fn new(repo: Arc<FlightMasterRepository>) -> Self {
        Self { repo }
    }
}

impl FlightMasterService for DefaultFlightMasterService {
    fn list_flight_masters(
        &self,
        map_id: i64,
        query: UtilityListQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>> {
        self.repo.list_flight_masters(map_id, &query)
    }

    fn nearby_flight_masters(
        &self,
        map_id: i64,
        query: UtilityNearbyQuery,
    ) -> AppResult<PagedResponse<UtilityEntity>> {
        self.repo.nearby_flight_masters(map_id, &query)
    }
}
