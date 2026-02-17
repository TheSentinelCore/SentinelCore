//! Integration tests for Sentinel Navigation Server HTTP endpoints.
//!
//! These tests require mmap files to be present at the configured path.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use tower::ServiceExt;

use sentinel_nav_server::config::{Config, NavmeshConfig, PathfindingConfig, ServerConfig};
use sentinel_nav_server::routes::build_router;
use sentinel_nav_server::state::AppState;

/// Path to mmap files for testing.
const TEST_MMAP_PATH: &str = "./mmaps";

/// Create test application with Eastern Kingdoms preloaded.
fn create_test_app() -> axum::Router {
    let config = Config {
        server: ServerConfig::default(),
        navmesh: NavmeshConfig {
            mmap_path: TEST_MMAP_PATH.into(),
            preload_maps: vec![0], // Preload Eastern Kingdoms
        },
        pathfinding: PathfindingConfig::default(),
    };

    let state = AppState::new(config).expect("Failed to create AppState");
    build_router(state)
}

#[tokio::test]
async fn test_health_endpoint() {
    let app = create_test_app();

    let response = app
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["status"], "ok");
    assert!(json["loaded_map_count"].as_u64().unwrap() >= 1);
    assert!(json["loaded_maps"].as_array().unwrap().contains(&Value::from(0)));
}

#[tokio::test]
async fn test_path_endpoint_success() {
    let app = create_test_app();

    // Stormwind area coordinates
    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    assert!(json["path"].as_array().unwrap().len() >= 2);
    assert!(json["distance"].as_f64().unwrap() > 0.0);
    assert!(json["computation_time_ms"].as_f64().unwrap() < 100.0);
}

#[tokio::test]
async fn test_path_endpoint_invalid_map() {
    let app = create_test_app();

    let uri = "/api/v1/path?map_id=999&start_x=0&start_y=0&start_z=0&end_x=1&end_y=1&end_z=1";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["code"], "MAP_NOT_FOUND");
}

#[tokio::test]
async fn test_path_random_endpoint() {
    let app = create_test_app();

    let uri = "/api/v1/path-random?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&max_deviation=5.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    assert!(json["path"].as_array().unwrap().len() >= 2);
}

#[tokio::test]
async fn test_height_endpoint() {
    let app = create_test_app();

    let uri = "/api/v1/height?map_id=0&x=-8949.95&y=-132.493&z=83.53";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    let height = json["height"].as_f64().unwrap();
    assert!(height > 0.0 && height < 1000.0);
}

#[tokio::test]
async fn test_random_point_global() {
    let app = create_test_app();

    let uri = "/api/v1/random?map_id=0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    assert!(json["x"].as_f64().is_some());
    assert!(json["y"].as_f64().is_some());
    assert!(json["z"].as_f64().is_some());
}

#[tokio::test]
async fn test_random_point_in_circle() {
    let app = create_test_app();

    let uri = "/api/v1/random?map_id=0&center_x=-8949.95&center_y=-132.493&center_z=83.53&radius=50";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    // Point should be within radius of center
    let x = json["x"].as_f64().unwrap();
    let y = json["y"].as_f64().unwrap();
    let dx = x - (-8949.95);
    let dy = y - (-132.493);
    let distance = (dx * dx + dy * dy).sqrt();
    // Allow some margin for navmesh snapping
    assert!(distance < 100.0, "Point too far from center: {}", distance);
}

#[tokio::test]
async fn test_move_along_surface() {
    let app = create_test_app();

    let uri = "/api/v1/move?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8900&end_y=-150&end_z=85";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    // Result should be somewhere between start and end
    let x = json["x"].as_f64().unwrap();
    assert!(x > -8960.0 && x < -8890.0, "X out of expected range: {}", x);
}

#[tokio::test]
async fn test_raycast() {
    let app = create_test_app();

    let uri = "/api/v1/raycast?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8800&end_y=-100&end_z=83.53";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    // Raycast should return hit info
    let t = json["t"].as_f64().unwrap();
    assert!(t >= 0.0 && t <= 1.0, "t parameter out of range: {}", t);
}

#[tokio::test]
async fn test_path_with_smoothing() {
    let app = create_test_app();

    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&smoothing=chaikin";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["success"], true);
    // Smoothed path typically has more points
    assert!(json["path"].as_array().unwrap().len() >= 2);
}

// =============================================================================
// EDGE CASE TESTS
// =============================================================================

/// Helper function to parse JSON from response body.
async fn parse_json(response: axum::response::Response) -> Value {
    let body = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&body).unwrap()
}

// -----------------------------------------------------------------------------
// Long-Distance Path Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_long_path_goldshire_to_stormwind() {
    let app = create_test_app();

    // Goldshire to Stormwind (~500 yards)
    let uri = "/api/v1/path?map_id=0&start_x=-9456.2&start_y=64.8&start_z=56.0&end_x=-8949.95&end_y=-132.493&end_z=83.53";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let json = parse_json(response).await;

    assert_eq!(json["success"], true);
    let path = json["path"].as_array().unwrap();
    assert!(path.len() > 5, "Long path should have multiple waypoints, got {}", path.len());

    let distance = json["distance"].as_f64().unwrap();
    assert!(
        distance > 300.0 && distance < 1000.0,
        "Distance should be ~500 yards, got {}",
        distance
    );
}

// -----------------------------------------------------------------------------
// Same Position / Close Points Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_same_start_end_position() {
    let app = create_test_app();

    // Same position for start and end
    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8949.95&end_y=-132.493&end_z=83.53";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let json = parse_json(response).await;

    assert_eq!(json["success"], true);
    // Path should have minimal points for same position
    let path_len = json["path"].as_array().unwrap().len();
    assert!(
        path_len <= 2,
        "Same position path should be minimal, got {} points",
        path_len
    );

    let distance = json["distance"].as_f64().unwrap();
    assert!(distance < 1.0, "Distance should be ~0, got {}", distance);
}

#[tokio::test]
async fn test_very_close_points() {
    let app = create_test_app();

    // Points less than 1 yard apart
    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8949.5&end_y=-132.0&end_z=83.53";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let json = parse_json(response).await;

    assert_eq!(json["success"], true);
    let distance = json["distance"].as_f64().unwrap();
    assert!(
        distance < 2.0,
        "Close points distance should be small, got {}",
        distance
    );
}

// -----------------------------------------------------------------------------
// Off-Navmesh Position Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_start_off_navmesh() {
    let app = create_test_app();

    // Position in the ocean (no navmesh) - within validation bounds
    let uri = "/api/v1/path?map_id=0&start_x=-15000.0&start_y=0.0&start_z=0.0&end_x=-8949.95&end_y=-132.493&end_z=83.53";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Should return 422 (pathfinding failed) - position not on navmesh
    let status = response.status();
    assert!(
        status == StatusCode::UNPROCESSABLE_ENTITY || status == StatusCode::OK,
        "Expected 422 or 200, got {}",
        status
    );
}

#[tokio::test]
async fn test_end_off_navmesh() {
    let app = create_test_app();

    // Valid start, ocean end
    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-15000.0&end_y=0.0&end_z=0.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    let status = response.status();
    assert!(
        status == StatusCode::UNPROCESSABLE_ENTITY || status == StatusCode::OK,
        "Expected 422 or 200, got {}",
        status
    );
}

#[tokio::test]
async fn test_underground_position() {
    let app = create_test_app();

    // Position underground (Z too low but within validation bounds)
    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=-500.0&end_x=-8898.3&end_y=-161.27&end_z=81.97";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Position may be snapped to navmesh or fail
    let status = response.status();
    assert!(
        status == StatusCode::UNPROCESSABLE_ENTITY || status == StatusCode::OK,
        "Expected pathfinding result, got {}",
        status
    );
}

// -----------------------------------------------------------------------------
// Input Validation Edge Case Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_out_of_bounds_coordinate_rejected() {
    let app = create_test_app();

    // X coordinate beyond WoW bounds (±65536)
    let uri = "/api/v1/path?map_id=0&start_x=70000&start_y=0&start_z=0&end_x=0&end_y=0&end_z=0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let json = parse_json(response).await;
    // Error response uses "error" field, not "message"
    let error_msg = json["error"].as_str().unwrap_or("");
    assert!(
        error_msg.contains("out of") || error_msg.contains("bounds") || error_msg.contains("WoW"),
        "Error message should mention bounds: {}",
        error_msg
    );
}

#[tokio::test]
async fn test_invalid_map_id_validation() {
    let app = create_test_app();

    // Map ID >= 10000 should be rejected by validation
    let uri = "/api/v1/path?map_id=99999&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Either BAD_REQUEST (validation) or NOT_FOUND (map not found)
    assert!(
        response.status() == StatusCode::BAD_REQUEST
            || response.status() == StatusCode::NOT_FOUND,
        "Expected 400 or 404, got {}",
        response.status()
    );
}

#[tokio::test]
async fn test_height_out_of_range_rejected() {
    let app = create_test_app();

    // Z (height) beyond validation bounds (±10000)
    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=15000&end_x=-8898.3&end_y=-161.27&end_z=81.97";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

// -----------------------------------------------------------------------------
// Smoothing Algorithm Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_all_smoothing_algorithms() {
    let algorithms = ["none", "chaikin", "catmull_rom", "bezier"];
    let base_uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97";

    let mut path_lengths: std::collections::HashMap<String, usize> =
        std::collections::HashMap::new();

    for algo in algorithms {
        let app = create_test_app();
        let uri = format!("{}&smoothing={}", base_uri, algo);

        let response = app
            .oneshot(Request::get(&uri).body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(
            response.status(),
            StatusCode::OK,
            "Smoothing '{}' should succeed",
            algo
        );

        let json = parse_json(response).await;
        assert_eq!(json["success"], true);

        let path_len = json["path"].as_array().unwrap().len();
        path_lengths.insert(algo.to_string(), path_len);
    }

    // Smoothing algorithms typically produce more points than "none"
    let none_len = path_lengths["none"];
    for (algo, len) in &path_lengths {
        if algo != "none" && none_len > 2 {
            // Only check if raw path has enough points
            assert!(
                *len >= none_len,
                "Smoothed path '{}' ({}) should have >= points than raw ({})",
                algo,
                len,
                none_len
            );
        }
    }
}

#[tokio::test]
async fn test_invalid_smoothing_algorithm() {
    let app = create_test_app();

    let uri = "/api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&smoothing=invalid_algo";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Should either ignore invalid algorithm (return raw path) or return error
    let status = response.status();
    assert!(
        status == StatusCode::OK || status == StatusCode::BAD_REQUEST,
        "Expected 200 or 400, got {}",
        status
    );
}

// -----------------------------------------------------------------------------
// Random Path Deviation Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_random_path_deviation_at_max() {
    let app = create_test_app();

    // Max allowed deviation (100.0)
    let uri = "/api/v1/path-random?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&max_deviation=100.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let json = parse_json(response).await;
    assert_eq!(json["success"], true);
}

#[tokio::test]
async fn test_random_path_excessive_deviation_rejected() {
    let app = create_test_app();

    // Deviation > 100 should be rejected
    let uri = "/api/v1/path-random?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&max_deviation=150.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_random_path_zero_deviation_rejected() {
    let app = create_test_app();

    let uri = "/api/v1/path-random?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&max_deviation=0.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_random_path_negative_deviation_rejected() {
    let app = create_test_app();

    let uri = "/api/v1/path-random?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97&max_deviation=-5.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

// -----------------------------------------------------------------------------
// Spatial Query Edge Case Tests
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_random_point_in_small_radius() {
    let app = create_test_app();

    // Small radius (5 yards) - more realistic for navmesh snapping
    let uri = "/api/v1/random?map_id=0&center_x=-8949.95&center_y=-132.493&center_z=83.53&radius=5.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Should succeed and return valid coordinates
    assert_eq!(response.status(), StatusCode::OK);
    let json = parse_json(response).await;
    assert_eq!(json["success"], true);

    // Point should be reasonably close to center (allowing for navmesh snapping)
    let x = json["x"].as_f64().unwrap();
    let y = json["y"].as_f64().unwrap();
    let dx = x - (-8949.95);
    let dy = y - (-132.493);
    let distance = (dx * dx + dy * dy).sqrt();
    // Allow generous tolerance as Detour may find nearby polygon
    assert!(
        distance < 50.0,
        "Point should be reasonably near center, got distance {}",
        distance
    );
}

#[tokio::test]
async fn test_radius_at_maximum() {
    let app = create_test_app();

    // Radius at max allowed (10000.0)
    let uri = "/api/v1/random?map_id=0&center_x=-8949.95&center_y=-132.493&center_z=83.53&radius=10000.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_radius_exceeds_max_rejected() {
    let app = create_test_app();

    let uri = "/api/v1/random?map_id=0&center_x=-8949.95&center_y=-132.493&center_z=83.53&radius=15000.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_radius_zero_rejected() {
    let app = create_test_app();

    let uri = "/api/v1/random?map_id=0&center_x=-8949.95&center_y=-132.493&center_z=83.53&radius=0.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_raycast_long_distance() {
    let app = create_test_app();

    // Raycast across a large distance (Stormwind to Goldshire direction)
    let uri = "/api/v1/raycast?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.53&end_x=-9456.2&end_y=64.8&end_z=56.0";

    let response = app
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let json = parse_json(response).await;

    // Long raycast will likely hit something (t < 1.0)
    let t = json["t"].as_f64().unwrap();
    assert!(t >= 0.0 && t <= 1.0, "t should be in [0,1], got {}", t);
}

// -----------------------------------------------------------------------------
// Concurrent Requests Test
// -----------------------------------------------------------------------------

#[tokio::test]
async fn test_concurrent_path_requests() {
    // Spawn 10 concurrent requests
    let mut handles = vec![];

    for i in 0..10 {
        let offset = i as f64 * 5.0;

        let handle = tokio::spawn(async move {
            let app = create_test_app();
            let uri = format!(
                "/api/v1/path?map_id=0&start_x={}&start_y=-132.493&start_z=83.53&end_x=-8898.3&end_y=-161.27&end_z=81.97",
                -8949.95 + offset
            );

            let response = app
                .oneshot(Request::get(&uri).body(Body::empty()).unwrap())
                .await
                .unwrap();

            response.status()
        });

        handles.push(handle);
    }

    // All requests should succeed
    let mut success_count = 0;
    for handle in handles {
        let status = handle.await.unwrap();
        if status == StatusCode::OK {
            success_count += 1;
        }
    }

    assert!(
        success_count >= 8,
        "At least 80% of concurrent requests should succeed, got {}/10",
        success_count
    );
}
