use std::sync::{Arc, Mutex};

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use tower::ServiceExt;

use sentinel_duo_coord_server::{
    app_state::AppState,
    config::{Config, LockoutConfig, ServerConfig, SessionConfig},
    routes,
    state::SessionState,
};

fn test_config() -> Config {
    Config {
        server: ServerConfig {
            host: "127.0.0.1".to_string(),
            port: 7300,
        },
        session: SessionConfig {
            heartbeat_timeout_ms: 5000,
            barrier_timeout_ms: 90000,
            max_clients: 2,
        },
        lockout: LockoutConfig {
            max_resets_per_hour: 5,
            warn_at: 4,
        },
    }
}

fn test_app() -> axum::Router {
    let session = Arc::new(Mutex::new(SessionState::default()));
    let app_state = AppState {
        session,
        config: test_config(),
    };
    routes::build_router(app_state)
}

async fn get_json(app: axum::Router, url: &str) -> (StatusCode, Value) {
    let req = Request::builder()
        .method("GET")
        .uri(url)
        .body(Body::empty())
        .unwrap();

    let response = app.oneshot(req).await.unwrap();
    let status = response.status();
    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
    (status, json)
}

// Test 1: Health endpoint returns ok
#[tokio::test]
async fn test_health() {
    let app = test_app();
    let (status, json) = get_json(app, "/health").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "ok");
    assert_eq!(json["clients_connected"], 0);
}

// Test 2: Client A registers as mage_a on first heartbeat
#[tokio::test]
async fn test_client_a_registers_as_mage_a() {
    let app = test_app();
    let (status, json) = get_json(
        app,
        "/api/v1/heartbeat?hp=100&mp=100&bags_full=0&is_dead=0&in_instance=0&phase=initializing",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["assigned_client_id"], "mage_a");
    assert_eq!(json["your_role"], "mage_a");
}

// Test 3: Client B registers as mage_b on second heartbeat
#[tokio::test]
async fn test_client_b_registers_as_mage_b() {
    let session = Arc::new(Mutex::new(SessionState::default()));
    let app_state = AppState {
        session: session.clone(),
        config: test_config(),
    };
    let app = routes::build_router(app_state);

    // First heartbeat — no client_id, gets mage_a
    let req = Request::builder()
        .uri("/api/v1/heartbeat?hp=100&mp=100&bags_full=0&is_dead=0&in_instance=0&phase=initializing")
        .body(Body::empty())
        .unwrap();
    let _ = app.clone().oneshot(req).await.unwrap();

    // Second heartbeat — no client_id, should get mage_b
    let (status, json) = get_json(
        app,
        "/api/v1/heartbeat?hp=100&mp=100&bags_full=0&is_dead=0&in_instance=0&phase=initializing",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["assigned_client_id"], "mage_b");
}

// Test 4: Heartbeat updates state fields correctly
#[tokio::test]
async fn test_heartbeat_updates_state() {
    let app = test_app();
    let (status, json) = get_json(
        app,
        "/api/v1/heartbeat?client_id=mage_a&hp=75&mp=60&bags_full=1&is_dead=0&in_instance=1&phase=aoe_both",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["mage_a"]["health_pct"], 75);
    assert_eq!(json["mage_a"]["mana_pct"], 60);
    assert_eq!(json["mage_a"]["bags_full"], true);
    assert_eq!(json["mage_a"]["in_instance"], true);
    assert_eq!(json["mage_a"]["phase"], "aoe_both");
}

// Test 5: Barrier enter/poll/release full flow
#[tokio::test]
async fn test_barrier_enter_poll_release() {
    let session = Arc::new(Mutex::new(SessionState::default()));
    let app_state = AppState {
        session: session.clone(),
        config: test_config(),
    };
    let app = routes::build_router(app_state);

    // Mage A enters barrier
    let (status, json) = get_json(
        app.clone(),
        "/api/v1/barrier/enter?client_id=mage_a&name=pull_start",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["both_ready"], false);
    assert_eq!(json["your_ready"], true);
    assert_eq!(json["partner_ready"], false);

    // Mage B enters barrier
    let (status, json) = get_json(
        app.clone(),
        "/api/v1/barrier/enter?client_id=mage_b&name=pull_start",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["both_ready"], true);

    // Poll should still show both_ready
    let (status, json) = get_json(
        app.clone(),
        "/api/v1/barrier/poll?client_id=mage_a&name=pull_start",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["both_ready"], true);

    // Release
    let (status, json) = get_json(
        app,
        "/api/v1/barrier/release?client_id=mage_a&name=pull_start",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["ok"], true);
}

// Test 6: pull/advance increments index and toggles puller when both ready
#[tokio::test]
async fn test_pull_advance() {
    let session = Arc::new(Mutex::new(SessionState::default()));
    {
        let mut s = session.lock().unwrap();
        s.puller_id = "mage_a".to_string();
    }
    let app_state = AppState {
        session: session.clone(),
        config: test_config(),
    };
    let app = routes::build_router(app_state);

    // Only mage_a advances — index should NOT change yet
    let (status, json) = get_json(app.clone(), "/api/v1/pull/advance?client_id=mage_a").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["new_pull_index"], 0u64);

    // mage_b advances — both ready, should increment and swap
    let (status, json) = get_json(app, "/api/v1/pull/advance?client_id=mage_b").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["new_pull_index"], 1u64);
    assert_eq!(json["new_puller_id"], "mage_b");
}

// Test 7: lockout/record tracks resets, near_limit at 4, must_wait at 5
#[tokio::test]
async fn test_lockout_record() {
    let session = Arc::new(Mutex::new(SessionState::default()));
    let app_state = AppState {
        session: session.clone(),
        config: test_config(),
    };
    let app = routes::build_router(app_state);

    // Record 3 resets — not near limit yet
    for _ in 0..3 {
        let (status, json) = get_json(
            app.clone(),
            "/api/v1/lockout/record?client_id=mage_a",
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(json["near_limit"], false);
        assert_eq!(json["must_wait"], false);
    }

    // 4th reset — near_limit
    let (status, json) = get_json(app.clone(), "/api/v1/lockout/record?client_id=mage_a").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["reset_count"], 4);
    assert_eq!(json["near_limit"], true);
    assert_eq!(json["must_wait"], false);

    // 5th reset — must_wait
    let (status, json) = get_json(app, "/api/v1/lockout/record?client_id=mage_a").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["reset_count"], 5);
    assert_eq!(json["near_limit"], true);
    assert_eq!(json["must_wait"], true);
    assert!(json["wait_remaining_secs"].as_u64().unwrap_or(0) > 0);
}

// Test 8: vendor/request sets vendor_break_active
#[tokio::test]
async fn test_vendor_request() {
    let app = test_app();
    let (status, json) = get_json(app, "/api/v1/vendor/request?client_id=mage_b").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["vendor_break_active"], true);
    assert_eq!(json["requested_by"], "mage_b");
}

// Test 9: admin/reset clears all state
#[tokio::test]
async fn test_admin_reset() {
    let session = Arc::new(Mutex::new(SessionState::default()));
    {
        let mut s = session.lock().unwrap();
        s.mage_a.id = "mage_a".to_string();
        s.mage_a.connected = true;
        s.pull_index = 3;
        s.lockout.reset_count = 4;
    }
    let app_state = AppState {
        session: session.clone(),
        config: test_config(),
    };
    let app = routes::build_router(app_state);

    let (status, json) = get_json(app, "/api/v1/admin/reset").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["ok"], true);

    // Verify state was reset
    let s = session.lock().unwrap();
    assert_eq!(s.pull_index, 0);
    assert_eq!(s.lockout.reset_count, 0);
    assert_eq!(s.mage_a.id, "");
}
