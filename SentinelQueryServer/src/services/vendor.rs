use std::sync::Arc;

use crate::error::AppResult;
use crate::models::{PagedResponse, VendorEntity};
use crate::storage::repositories::vendor::{VendorListQuery, VendorNearbyQuery, VendorRepository};

pub trait VendorService: Send + Sync {
    fn list_vendors(
        &self,
        map_id: i64,
        query: VendorListQuery,
    ) -> AppResult<PagedResponse<VendorEntity>>;
    fn nearby_vendors(
        &self,
        map_id: i64,
        query: VendorNearbyQuery,
    ) -> AppResult<PagedResponse<VendorEntity>>;
}

#[derive(Clone)]
pub struct DefaultVendorService {
    repo: Arc<VendorRepository>,
}

impl DefaultVendorService {
    pub fn new(repo: Arc<VendorRepository>) -> Self {
        Self { repo }
    }
}

impl VendorService for DefaultVendorService {
    fn list_vendors(
        &self,
        map_id: i64,
        query: VendorListQuery,
    ) -> AppResult<PagedResponse<VendorEntity>> {
        self.repo.list_vendors(map_id, &query)
    }

    fn nearby_vendors(
        &self,
        map_id: i64,
        query: VendorNearbyQuery,
    ) -> AppResult<PagedResponse<VendorEntity>> {
        self.repo.nearby_vendors(map_id, &query)
    }
}
