use axum::{
    extract::{Query, State},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::Instant;

use crate::{
    config::Config,
    error::AppError,
    state::{ClientPhase, SharedState},
};

pub async fn get_session(State(state): State<SharedState>) -> Json<Value> {
    let session = state.lock().unwrap();
    build_session_json(&session)
}

fn build_session_json(session: &crate::state::SessionState) -> Json<Value> {
    Json(json!({
        "session_phase": session.phase,
        "pull_index": session.pull_index,
        "puller_id": session.puller_id,
        "runs_completed": session.runs_completed,
        "mage_a": session.mage_a,
        "mage_b": session.mage_b,
    }))
}

#[derive(Debug, Deserialize)]
pub struct HeartbeatParams {
    pub client_id: Option<String>,
    pub phase: Option<String>,
    pub hp: Option<u8>,
    pub mp: Option<u8>,
    pub bags_full: Option<u8>,
    pub is_dead: Option<u8>,
    pub in_instance: Option<u8>,
}

pub async fn heartbeat(
    State(state): State<SharedState>,
    State(config): State<Config>,
    Query(params): Query<HeartbeatParams>,
) -> Result<Json<Value>, AppError> {
    let hp = params.hp.ok_or_else(|| AppError::InvalidParams("hp required".into()))?;
    let mp = params.mp.ok_or_else(|| AppError::InvalidParams("mp required".into()))?;

    if hp > 100 || mp > 100 {
        return Err(AppError::InvalidParams("hp/mp must be 0-100".into()));
    }

    let phase_str = params.phase.clone().unwrap_or_else(|| "offline".to_string());
    let new_phase: ClientPhase = serde_json::from_value(
        serde_json::Value::String(phase_str.clone())
    ).unwrap_or(ClientPhase::Offline);

    let mut session = state.lock().unwrap();

    // Initialize start_time
    if session.start_time.is_none() {
        session.start_time = Some(Instant::now());
    }

    // Role assignment:
    // - If client sends a known role ("mage_a" / "mage_b") → use it.
    // - If client sends empty/unknown id → assign mage_a slot if free, else mage_b.
    // - If both slots are already taken → still return the slot that last-updated this
    //   connection's IP (we fall back to mage_a to avoid returning empty string).
    let assigned_id = match params.client_id.as_deref() {
        Some("mage_a") => "mage_a".to_string(),
        Some("mage_b") => "mage_b".to_string(),
        _ => {
            // Unknown / missing client_id — assign a slot.
            if session.mage_a.id.is_empty() {
                "mage_a".to_string()
            } else if session.mage_b.id.is_empty() {
                "mage_b".to_string()
            } else {
                // Both slots are claimed. Assign to whichever has been silent
                // the longest — this handles script reloads where both clients
                // restart and send empty client_id before their previous
                // heartbeat entry times out.
                let a_age = session.mage_a.last_heartbeat
                    .map(|t| t.elapsed().as_millis())
                    .unwrap_or(u128::MAX);
                let b_age = session.mage_b.last_heartbeat
                    .map(|t| t.elapsed().as_millis())
                    .unwrap_or(u128::MAX);
                // Assign to the slot that has been offline longer.
                if a_age >= b_age {
                    "mage_a".to_string()
                } else {
                    "mage_b".to_string()
                }
            }
        }
    };

    let bags_full = params.bags_full.unwrap_or(0) != 0;
    let is_dead = params.is_dead.unwrap_or(0) != 0;
    let in_instance = params.in_instance.unwrap_or(0) != 0;

    // Update the appropriate client record
    if assigned_id == "mage_a" {
        session.mage_a.id = "mage_a".to_string();
        session.mage_a.phase = new_phase;
        session.mage_a.health_pct = hp;
        session.mage_a.mana_pct = mp;
        session.mage_a.bags_full = bags_full;
        session.mage_a.is_dead = is_dead;
        session.mage_a.in_instance = in_instance;
        session.mage_a.last_heartbeat = Some(Instant::now());
        session.mage_a.connected = true;
    } else {
        session.mage_b.id = "mage_b".to_string();
        session.mage_b.phase = new_phase;
        session.mage_b.health_pct = hp;
        session.mage_b.mana_pct = mp;
        session.mage_b.bags_full = bags_full;
        session.mage_b.is_dead = is_dead;
        session.mage_b.in_instance = in_instance;
        session.mage_b.last_heartbeat = Some(Instant::now());
        session.mage_b.connected = true;
    }

    // Initialize puller_id if not set
    if session.puller_id.is_empty() {
        session.puller_id = "mage_a".to_string();
    }

    // Check partner liveness
    session.check_partner_liveness(config.session.heartbeat_timeout_ms);

    // Compute lockout window time remaining
    let wait_remaining_secs = if session.lockout.window_start.is_some() {
        let elapsed = session.lockout.window_start.unwrap().elapsed().as_secs();
        3600u64.saturating_sub(elapsed)
    } else {
        0
    };

    let vendor_break_requested = session.vendor_requested_by.is_some();

    let response = json!({
        "assigned_client_id": assigned_id,
        "your_role": assigned_id,
        "session_phase": session.phase,
        "pull_index": session.pull_index,
        "puller_id": session.puller_id,
        "runs_completed": session.runs_completed,
        "lockout": {
            "reset_count": session.lockout.reset_count,
            "near_limit": session.lockout.near_limit,
            "next_window_reset_secs": wait_remaining_secs,
        },
        "vendor_break_requested": vendor_break_requested,
        "mage_a": session.mage_a,
        "mage_b": session.mage_b,
    });

    tracing::info!(
        client_id = %assigned_id,
        phase = %phase_str,
        hp = hp,
        mp = mp,
        "heartbeat received"
    );

    Ok(Json(response))
}
