use std::sync::Arc;

use crate::error::AppResult;
use crate::models::{ContextResolveRequest, ContextResolveResponse};
use crate::storage::repositories::context::ContextRepository;

pub trait ContextService: Send + Sync {
    fn resolve_context(&self, request: ContextResolveRequest) -> AppResult<ContextResolveResponse>;
}

#[derive(Clone)]
pub struct DefaultContextService {
    repo: Arc<ContextRepository>,
}

impl DefaultContextService {
    pub fn new(repo: Arc<ContextRepository>) -> Self {
        Self { repo }
    }
}

impl ContextService for DefaultContextService {
    fn resolve_context(&self, request: ContextResolveRequest) -> AppResult<ContextResolveResponse> {
        self.repo.resolve_context(&request)
    }
}
