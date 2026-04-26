use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "snake_case")]
pub enum ClientPhase {
    #[default]
    Offline,
    Initializing,
    Buffing,
    TravelingToInstance,
    EnteringInstance,
    Positioning,
    PullRunning,
    PullIceBlock,
    AoeOpening,
    AoeBoth,
    Looting,
    ExitingInstance,
    Resetting,
    WaitingLockout,
    TravelingToVendor,
    Vendoring,
    ReturningToInstance,
    Dead,
    GhostRunning,
    Paused,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientState {
    pub id: String,
    pub phase: ClientPhase,
    pub health_pct: u8,
    pub mana_pct: u8,
    pub bags_full: bool,
    pub is_dead: bool,
    pub in_instance: bool,
    pub connected: bool,
    #[serde(skip)]
    pub last_heartbeat: Option<Instant>,
}

impl Default for ClientState {
    fn default() -> Self {
        ClientState {
            id: String::new(),
            phase: ClientPhase::Offline,
            health_pct: 100,
            mana_pct: 100,
            bags_full: false,
            is_dead: false,
            in_instance: false,
            connected: false,
            last_heartbeat: None,
        }
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct BarrierState {
    pub name: String,
    pub mage_a_ready: bool,
    pub mage_b_ready: bool,
    #[serde(skip)]
    pub entered_at: Option<Instant>,
}

impl BarrierState {
    pub fn waiting_ms(&self) -> u64 {
        self.entered_at
            .map(|t| t.elapsed().as_millis() as u64)
            .unwrap_or(0)
    }

    pub fn both_ready(&self) -> bool {
        self.mage_a_ready && self.mage_b_ready
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "snake_case")]
pub enum SessionPhase {
    #[default]
    Idle,
    Farming,
    Resetting,
    Vendoring,
    WaitingForLockout,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct LockoutState {
    pub reset_count: u32,
    pub near_limit: bool,
    #[serde(skip)]
    pub window_start: Option<Instant>,
}

#[derive(Debug, Default)]
pub struct SessionState {
    pub phase: SessionPhase,
    pub mage_a: ClientState,
    pub mage_b: ClientState,
    pub pull_index: u32,
    pub puller_id: String,
    pub barriers: HashMap<String, BarrierState>,
    pub lockout: LockoutState,
    pub vendor_requested_by: Option<String>,
    pub runs_completed: u32,
    pub total_gold_earned_copper: u64,
    pub mage_a_advance_ready: bool,
    pub mage_b_advance_ready: bool,
    pub start_time: Option<Instant>,
}

impl SessionState {
    pub fn uptime_secs(&self) -> u64 {
        self.start_time
            .map(|t| t.elapsed().as_secs())
            .unwrap_or(0)
    }

    pub fn clients_connected(&self) -> u32 {
        let a = if self.mage_a.connected { 1 } else { 0 };
        let b = if self.mage_b.connected { 1 } else { 0 };
        a + b
    }

    /// Check and update partner liveness based on heartbeat timeout.
    pub fn check_partner_liveness(&mut self, heartbeat_timeout_ms: u64) {
        let now = Instant::now();
        if let Some(last) = self.mage_a.last_heartbeat {
            if now.duration_since(last).as_millis() as u64 > heartbeat_timeout_ms {
                self.mage_a.connected = false;
                self.mage_a.phase = ClientPhase::Offline;
            }
        }
        if let Some(last) = self.mage_b.last_heartbeat {
            if now.duration_since(last).as_millis() as u64 > heartbeat_timeout_ms {
                self.mage_b.connected = false;
                self.mage_b.phase = ClientPhase::Offline;
            }
        }
    }
}

pub type SharedState = Arc<Mutex<SessionState>>;
