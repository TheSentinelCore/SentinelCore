use std::sync::Arc;

use detour::types::Vec3;

use crate::cache::{CachedPath, PathCache};
use crate::services::{CacheService, CacheStats};

pub struct MokaCache {
    inner: Arc<PathCache>,
}

impl MokaCache {
    pub fn new(cache: Arc<PathCache>) -> Self {
        Self { inner: cache }
    }
}

impl CacheService for MokaCache {
    fn get(&self, map_id: u32, start: &Vec3, end: &Vec3) -> Option<CachedPath> {
        self.inner.get(map_id, start, end)
    }

    fn put(&self, map_id: u32, start: &Vec3, end: &Vec3, path: CachedPath) {
        self.inner.insert(map_id, start, end, path);
    }

    fn stats(&self) -> CacheStats {
        CacheStats {
            hits: self.inner.hit_count(),
            misses: self.inner.miss_count(),
            size: self.inner.len(),
        }
    }
}
