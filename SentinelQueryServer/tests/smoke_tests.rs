mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sentinel_query_server::importer::Importer;
use sentinel_query_server::routes;
use tower::ServiceExt;

#[tokio::test]
async fn smoke_startup_import_health_and_vendor_query() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());

    assert!(!config.paths.runtime_db.exists());
    let importer = Importer::new(config.clone());
    importer
        .ensure_runtime_db()
        .expect("startup import should build missing runtime db");

    let app = routes::build_router(common::create_test_blackboard(&config));

    let health = app
        .clone()
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(health.status(), StatusCode::OK);

    let vendors = app
        .oneshot(
            Request::get("/api/v1/maps/0/vendors/nearby?x=-10&y=5&radius=5")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(vendors.status(), StatusCode::OK);
    let body = vendors.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(json["count"].as_u64().unwrap() >= 1);
}

#[test]
fn smoke_invalid_dump_fails_closed() {
    let temp = tempfile::tempdir().expect("tempdir");
    let mut config = common::make_config(temp.path());

    let invalid_dump = temp.path().join("invalid_dump.sql");
    std::fs::write(&invalid_dump, "this is not sql").expect("write invalid dump");
    config.paths.source_dump_sql = invalid_dump;

    let importer = Importer::new(config);
    let err = importer
        .ensure_runtime_db()
        .expect_err("invalid dump should fail closed");

    assert_eq!(err.code.as_str(), "DATASET_INVALID");
}

#[tokio::test]
async fn smoke_context_unresolved_is_explicit() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let response = app
        .oneshot(
            Request::get("/api/v1/context/resolve?x=1.0&y=2.0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["resolution"], "unresolved");
}
