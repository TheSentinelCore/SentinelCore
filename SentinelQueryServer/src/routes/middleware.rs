use std::sync::Arc;
use std::time::Instant;

use axum::extract::Request;
use axum::extract::State;
use axum::http::HeaderValue;
use axum::middleware::Next;
use axum::response::Response;

use crate::blackboard::ServerBlackboard;
use crate::telemetry::RequestContext;

pub async fn request_tracking(
    State(state): State<Arc<ServerBlackboard>>,
    mut request: Request,
    next: Next,
) -> Response {
    let request_id = uuid::Uuid::new_v4().to_string();
    request.extensions_mut().insert(RequestContext {
        request_id: request_id.clone(),
    });

    let path = request.uri().path().to_string();
    let method = request.method().to_string();
    let start = Instant::now();
    let mut response = next.run(request).await;

    let status = response.status();
    let latency_ms = start.elapsed().as_millis() as u64;
    let error_code = response
        .headers()
        .get("x-error-code")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .to_string();

    if !response.headers().contains_key("x-request-id") {
        if let Ok(value) = HeaderValue::from_str(&request_id) {
            response.headers_mut().insert("x-request-id", value);
        }
    }

    state
        .metrics
        .record_request(&path, !status.is_success(), latency_ms);

    if status.is_success() {
        tracing::debug!(
            request_id = %request_id,
            endpoint = %path,
            method = %method,
            status_code = status.as_u16(),
            latency_ms = latency_ms,
            "request_complete"
        );
    } else {
        tracing::warn!(
            request_id = %request_id,
            endpoint = %path,
            method = %method,
            status_code = status.as_u16(),
            latency_ms = latency_ms,
            error_code = %error_code,
            "request_failed"
        );
    }

    response
}
