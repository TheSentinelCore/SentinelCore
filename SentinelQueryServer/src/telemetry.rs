use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use dashmap::DashMap;

#[derive(Debug, Clone)]
pub struct RequestContext {
    pub request_id: String,
}

#[derive(Debug, Default)]
pub struct EndpointMetrics {
    pub requests: AtomicU64,
    pub errors: AtomicU64,
    pub total_latency_ms: AtomicU64,
}

#[derive(Debug, Default)]
pub struct ImportMetrics {
    pub runs_started: AtomicU64,
    pub runs_completed: AtomicU64,
    pub runs_failed: AtomicU64,
}

#[derive(Debug, Default)]
pub struct MetricsRegistry {
    endpoints: DashMap<String, Arc<EndpointMetrics>>,
    pub import: ImportMetrics,
}

impl MetricsRegistry {
    pub fn record_request(&self, endpoint: &str, is_error: bool, latency_ms: u64) {
        let slot = self
            .endpoints
            .entry(endpoint.to_string())
            .or_insert_with(|| Arc::new(EndpointMetrics::default()));
        slot.requests.fetch_add(1, Ordering::Relaxed);
        if is_error {
            slot.errors.fetch_add(1, Ordering::Relaxed);
        }
        slot.total_latency_ms
            .fetch_add(latency_ms, Ordering::Relaxed);
    }

    pub fn endpoint_snapshot(&self, endpoint: &str) -> Option<(u64, u64, u64)> {
        self.endpoints.get(endpoint).map(|metric| {
            (
                metric.requests.load(Ordering::Relaxed),
                metric.errors.load(Ordering::Relaxed),
                metric.total_latency_ms.load(Ordering::Relaxed),
            )
        })
    }
}
