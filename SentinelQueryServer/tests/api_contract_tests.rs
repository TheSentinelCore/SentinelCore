mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use tower::ServiceExt;

use sentinel_query_server::routes;

async fn body_json(response: axum::response::Response) -> Value {
    let body = response
        .into_body()
        .collect()
        .await
        .expect("body should collect")
        .to_bytes();
    serde_json::from_slice(&body).expect("body should be valid json")
}

#[tokio::test]
async fn health_and_dataset_meta_contract() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let health = app
        .clone()
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(health.status(), StatusCode::OK);
    let health_json = body_json(health).await;
    assert_eq!(health_json["status"], "ok");
    assert_eq!(health_json["game_version"], "tbc");

    let dataset = app
        .oneshot(
            Request::get("/api/v1/meta/dataset")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(dataset.status(), StatusCode::OK);
    let dataset_json = body_json(dataset).await;
    assert_eq!(dataset_json["source"], "cmangos");
    assert_eq!(dataset_json["game_version"], "tbc");
    assert!(dataset_json["dataset_version"]
        .as_str()
        .unwrap()
        .contains("importer-v1"));
}

#[tokio::test]
async fn context_resolve_returns_partial_and_unresolved_states() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let partial = app
        .clone()
        .oneshot(
            Request::get("/api/v1/context/resolve?map_id=0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(partial.status(), StatusCode::OK);
    let partial_json = body_json(partial).await;
    assert_eq!(partial_json["resolution"], "partial");
    assert_eq!(partial_json["source"], "direct_map");
    assert_eq!(partial_json["resolved"], true);
    assert_eq!(partial_json["ambiguous"], false);
    assert_eq!(partial_json["diagnostic_confidence"], 1.0);
    assert_eq!(partial_json["canonical_map_id"], 0);

    let ui_map_fallback = app
        .clone()
        .oneshot(
            Request::get("/api/v1/context/resolve?ui_map_id=0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ui_map_fallback.status(), StatusCode::OK);
    let ui_map_fallback_json = body_json(ui_map_fallback).await;
    assert_eq!(ui_map_fallback_json["resolution"], "partial");
    assert_eq!(ui_map_fallback_json["source"], "ui_map_fallback_direct_map");
    assert_eq!(ui_map_fallback_json["canonical_map_id"], 0);

    let ui_map_position_fallback = app
        .clone()
        .oneshot(
            Request::get("/api/v1/context/resolve?ui_map_id=99999&x=-10&y=5&instance_type=none")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ui_map_position_fallback.status(), StatusCode::OK);
    let ui_map_position_fallback_json = body_json(ui_map_position_fallback).await;
    assert_eq!(ui_map_position_fallback_json["resolution"], "partial");
    assert_eq!(
        ui_map_position_fallback_json["source"],
        "ui_map_fallback_position"
    );
    assert_eq!(ui_map_position_fallback_json["canonical_map_id"], 0);

    let unresolved = app
        .oneshot(
            Request::get("/api/v1/context/resolve?map_id=9999")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(unresolved.status(), StatusCode::OK);
    let unresolved_json = body_json(unresolved).await;
    assert_eq!(unresolved_json["resolution"], "unresolved");
    assert_eq!(unresolved_json["resolved"], false);
    assert_eq!(unresolved_json["ambiguous"], false);
    assert_eq!(unresolved_json["canonical_map_id"], Value::Null);
}

#[tokio::test]
async fn vendor_nearby_is_deterministic_and_orders_by_distance_then_guid() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let uri = "/api/v1/maps/0/vendors/nearby?x=-10&y=5&radius=5&limit=10";

    let first = app
        .clone()
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let second = app
        .clone()
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(first.status(), StatusCode::OK);
    assert_eq!(second.status(), StatusCode::OK);

    let first_json = body_json(first).await;
    let second_json = body_json(second).await;
    assert_eq!(first_json, second_json);

    let items = first_json["items"].as_array().unwrap();
    assert!(items.len() >= 2);
    assert_eq!(items[0]["guid"], 1001);
    assert_eq!(items[1]["guid"], 1004);
}

#[tokio::test]
async fn vendor_invalid_filter_has_explicit_error_code_and_request_id() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let response = app
        .oneshot(
            Request::get("/api/v1/maps/0/vendors?faction=bad_faction")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(response.headers().contains_key("x-request-id"));
    let json = body_json(response).await;
    assert_eq!(json["error"]["code"], "FACTION_FILTER_UNSUPPORTED");
    assert!(json["request_id"].as_str().unwrap().len() > 5);
}

#[tokio::test]
async fn vendor_numeric_faction_filter_is_accepted() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let response = app
        .oneshot(
            Request::get("/api/v1/maps/0/vendors/nearby?x=-10&y=5&radius=10&faction=469")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let json = body_json(response).await;
    assert!(json["items"].is_array());
}

#[tokio::test]
async fn trainer_detail_and_spells_are_deterministic() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let detail = app
        .clone()
        .oneshot(
            Request::get("/api/v1/trainers/101")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(detail.status(), StatusCode::OK);
    let detail_json = body_json(detail).await;
    assert_eq!(detail_json["entry"], 101);

    let spells_1 = app
        .clone()
        .oneshot(
            Request::get("/api/v1/trainers/101/spells")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let spells_2 = app
        .oneshot(
            Request::get("/api/v1/trainers/101/spells")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(spells_1.status(), StatusCode::OK);
    assert_eq!(spells_2.status(), StatusCode::OK);
    assert_eq!(body_json(spells_1).await, body_json(spells_2).await);
}

#[tokio::test]
async fn flight_master_and_innkeeper_endpoints_return_role_scoped_entities() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let flight = app
        .clone()
        .oneshot(
            Request::get("/api/v1/maps/0/flight-masters")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(flight.status(), StatusCode::OK);
    let flight_json = body_json(flight).await;
    assert_eq!(flight_json["items"][0]["entry"], 104);

    let inn = app
        .oneshot(
            Request::get("/api/v1/maps/1/innkeepers")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(inn.status(), StatusCode::OK);
    let inn_json = body_json(inn).await;
    assert_eq!(inn_json["items"][0]["entry"], 102);
}

#[tokio::test]
async fn unified_nearby_returns_stable_merged_order() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let uri =
        "/api/v1/maps/0/entities/nearby?x=-10&y=5&radius=6&types=vendor,trainer,flight_master";

    let response = app
        .clone()
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let json = body_json(response).await;
    assert_eq!(status, StatusCode::OK, "unexpected body: {}", json);
    let items = json["items"].as_array().unwrap();
    assert!(items.len() >= 3);

    let response_repeat = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response_repeat.status(), StatusCode::OK);
    let json_repeat = body_json(response_repeat).await;
    assert_eq!(json, json_repeat);

    // Closest entity in fixture is vendor guid 1001 at exact center.
    assert_eq!(items[0]["guid"], 1001);
}

#[tokio::test]
async fn pagination_invalid_cursor_returns_explicit_error() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let app = routes::build_router(common::create_test_blackboard(&config));

    let response = app
        .oneshot(
            Request::get("/api/v1/maps/0/vendors?cursor=not_a_cursor")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let json = body_json(response).await;
    assert_eq!(json["error"]["code"], "PAGINATION_INVALID");
}
