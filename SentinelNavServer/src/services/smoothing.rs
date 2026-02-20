use std::sync::Arc;

use detour::types::Vec3;
use mmap_loader::MmapManager;
use path_smoothing::SmootherPipeline;

use crate::services::SmoothingService;

pub struct PipelineSmoother {
    pub manager: Arc<MmapManager>,
}

impl PipelineSmoother {
    pub fn new(manager: Arc<MmapManager>) -> Self {
        Self { manager }
    }
}

impl SmoothingService for PipelineSmoother {
    fn smooth(&self, path: &[Vec3], algorithm: &str, map_id: u32) -> Vec<Vec3> {
        if algorithm == "none" || algorithm.is_empty() || path.len() < 3 {
            return path.to_vec();
        }

        let pool = match self.manager.get_query_pool(map_id) {
            Some(p) => p,
            None => return path.to_vec(),
        };
        let query = match pool.acquire() {
            Ok(q) => q,
            Err(_) => return path.to_vec(),
        };

        let smoother = SmootherPipeline::with_default_config();
        smoother.smooth(path, &query, pool.filter())
    }
}
