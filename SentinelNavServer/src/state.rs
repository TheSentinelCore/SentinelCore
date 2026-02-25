//! Application state shared across handlers.

use std::sync::atomic::AtomicU64;

/// Server-wide request metrics.
pub struct Metrics {
    pub total_requests: AtomicU64,
    pub failed_requests: AtomicU64,
}

impl Metrics {
    pub fn new() -> Self {
        Self {
            total_requests: AtomicU64::new(0),
            failed_requests: AtomicU64::new(0),
        }
    }
}
