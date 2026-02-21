mod common;

use axum::body::Body;
use axum::http::Request;
use sentinel_query_server::routes;
use tower::ServiceExt;

#[tokio::test]
async fn middleware_records_endpoint_metrics_and_request_ids() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let blackboard = common::create_test_blackboard(&config);
    let app = routes::build_router(blackboard.clone());

    let ok = app
        .clone()
        .oneshot(
            Request::get("/api/v1/maps/0/vendors")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert!(ok.headers().contains_key("x-request-id"));

    let bad = app
        .oneshot(
            Request::get("/api/v1/maps/0/vendors?faction=bad")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert!(bad.headers().contains_key("x-request-id"));

    let snapshot = blackboard
        .metrics
        .endpoint_snapshot("/api/v1/maps/0/vendors")
        .expect("metrics should exist for endpoint");

    assert!(snapshot.0 >= 2, "expected at least two requests");
    assert!(snapshot.1 >= 1, "expected at least one error");
}
