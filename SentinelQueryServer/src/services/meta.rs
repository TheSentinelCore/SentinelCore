use std::sync::Arc;

use crate::error::AppResult;
use crate::models::DatasetManifest;
use crate::storage::repositories::meta::MetaRepository;

pub trait MetaService: Send + Sync {
    fn get_manifest(&self) -> AppResult<DatasetManifest>;
}

#[derive(Clone)]
pub struct DefaultMetaService {
    repo: Arc<MetaRepository>,
}

impl DefaultMetaService {
    pub fn new(repo: Arc<MetaRepository>) -> Self {
        Self { repo }
    }
}

impl MetaService for DefaultMetaService {
    fn get_manifest(&self) -> AppResult<DatasetManifest> {
        self.repo.get_manifest()
    }
}
