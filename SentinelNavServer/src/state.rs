//! Application state shared across handlers.

use std::sync::atomic::{AtomicU64, Ordering};

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

    pub fn record_request(&self) {
        self.total_requests.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_failure(&self) {
        self.failed_requests.fetch_add(1, Ordering::Relaxed);
    }
}

/// Initialize the metrics crate counters/histograms.
pub fn init_metrics() {
    metrics::describe_counter!(
        "http_requests_total",
        "Total HTTP requests processed"
    );
    metrics::describe_counter!(
        "http_requests_failed",
        "Failed HTTP requests"
    );
    metrics::describe_histogram!(
        "http_request_duration_seconds",
        "Request latency in seconds"
    );
}

/// Record a successful request to the metrics crate.
pub fn record_request(handler: &str) {
    metrics::counter!(
        "http_requests_total",
        "handler" => handler.to_string(),
        "method" => "GET".to_string()
    )
    .increment(1);
}

/// Record a failed request to the metrics crate.
pub fn record_failure(handler: &str, error_code: &str) {
    metrics::counter!(
        "http_requests_failed",
        "handler" => handler.to_string(),
        "error" => error_code.to_string()
    )
    .increment(1);
}

/// Record request latency to the metrics crate.
pub fn record_latency(handler: &str, duration: std::time::Duration) {
    metrics::histogram!(
        "http_request_duration_seconds",
        "handler" => handler.to_string()
    )
    .record(duration.as_secs_f64());
}
