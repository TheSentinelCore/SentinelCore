# SentinelDuo — Duo Frost Mage Dungeon Farming Bot
## Implementation-Ready Design Document

**Version:** 1.0
**Date:** 2026-03-15
**Target:** TBC Classic — Stratholme Service Entrance Duo Mage Farm
**For:** Claude Code agentic implementation session

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture](#2-system-architecture)
3. [Rust Coordination Server Design](#3-rust-coordination-server-design)
4. [Lua Client Architecture](#4-lua-client-architecture)
5. [Spell Data Layer](#5-spell-data-layer)
6. [Dungeon Farm Profile Schema](#6-dungeon-farm-profile-schema)
7. [State Machine Specifications](#7-state-machine-specifications)
8. [Edge Case Handling](#8-edge-case-handling)
9. [UI/UX Design](#9-uiux-design)
10. [Debug & Observability](#10-debug--observability)
11. [Anti-Detection Considerations](#11-anti-detection-considerations)
12. [Future Extensibility Notes](#12-future-extensibility-notes)

---

## 1. Executive Summary

SentinelDuo is a fully autonomous, two-client TBC Classic bot system that executes duo Frost Mage dungeon farm loops. The flagship target is the Stratholme Service Entrance (Strath SE) duo mage farm — a well-established gold-per-hour strategy requiring precise timing between two Frost Mages to AoE large packs of undead.

The system consists of three executable components:

1. **SentinelDuoFarm (Lua, ×2)** — One instance per WoW client. Implements the complete farming loop: navigate → enter → pull → AoE → loot → exit → reset → vendor → return. Built on the existing Sentinel Lua infrastructure (Blackboard, EventBus, NavAdapter, BT framework).

2. **SentinelDuoCoordServer (Rust)** — A minimal Axum HTTP server running locally on the same machine as both WoW clients. Acts as a shared state bus: tracks which phase each mage is in, enforces sync barriers, manages instance lockout budgets, and detects heartbeat failures. Listens on `127.0.0.1:7300`.

3. **spell_data.lua** — A pre-extracted Lua table of all Frost Mage spells (from MaNGOS DB), consulted at runtime for spell ID resolution by rank.

The two Lua clients never communicate directly. All coordination flows through the Rust server via `core.http_get` GET requests. Each client polls the server every 300ms and receives the authoritative session state and partner status in every response.

**Design philosophy:** The coordination server is a dumb shared blackboard — it does not control game logic. Each Lua client decides what to do based on its own game state and the partner state fetched from the server. All gameplay decisions are local.

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Host Machine (single PC)                             │
│                                                                          │
│  ┌─────────────────────────┐    ┌──────────────────────────────────┐   │
│  │   WoW Client A          │    │   WoW Client B                    │   │
│  │   ┌─────────────────┐   │    │   ┌─────────────────────────┐    │   │
│  │   │ SentinelDuoFarm │   │    │   │ SentinelDuoFarm         │    │   │
│  │   │  ┌───────────┐  │   │    │   │  ┌─────────────────┐    │    │   │
│  │   │  │Master FSM │  │   │    │   │  │ Master FSM      │    │    │   │
│  │   │  └─────┬─────┘  │   │    │   │  └────────┬────────┘    │    │   │
│  │   │        │        │   │    │   │           │             │    │   │
│  │   │  ┌─────▼──────┐ │   │    │   │  ┌────────▼────────┐   │    │   │
│  │   │  │CoordClient │ │   │    │   │  │ CoordClient     │   │    │   │
│  │   │  └─────┬──────┘ │   │    │   │  └────────┬────────┘   │    │   │
│  │   │        │ 300ms  │   │    │   │           │ 300ms      │    │   │
│  │   │  ┌─────▼──────┐ │   │    │   │  ┌────────▼────────┐   │    │   │
│  │   │  │ NavAdapter │ │   │    │   │  │  NavAdapter     │   │    │   │
│  │   │  └─────┬──────┘ │   │    │   │  └────────┬────────┘   │    │   │
│  │   └────────┼────────┘   │    │   └───────────┼────────────┘    │   │
│  └────────────┼────────────┘    └───────────────┼─────────────────┘   │
│               │ core.http_get                    │ core.http_get        │
│               │                                  │                      │
│               └──────────────┐  ┌───────────────┘                      │
│                              │  │                                       │
│                     ┌────────▼──▼────────┐                             │
│                     │ SentinelDuoCoord   │  :7300                      │
│                     │   Server (Rust)    │                             │
│                     │                    │                             │
│                     │  SessionState      │                             │
│                     │  HeartbeatTracker  │                             │
│                     │  LockoutBudget     │                             │
│                     │  SyncBarriers      │                             │
│                     └────────────────────┘                             │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ SentinelNavServer (existing) :7200  ←── NavAdapter HTTP          │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

**Data flow per 300ms tick (Lua client):**

1. Client builds heartbeat GET with its current phase, HP%, MP%, bags_full flag
2. `core.http_get` dispatched asynchronously
3. Server updates this client's record, returns full session JSON
4. Client parses response: updates partner state in local Blackboard
5. Master FSM evaluates: current state + partner state + local game state → next action

**Data flow on sync barrier:**

1. Client A reaches barrier "ready_to_pull", calls `GET /api/v1/barrier/enter?...`
2. Server marks A as waiting at this barrier, returns `{"waiting": true, "partner_ready": false}`
3. Client A polls `GET /api/v1/barrier/poll?...` until `partner_ready: true`
4. Client B reaches same barrier, server marks both ready, returns `{"waiting": false, "both_ready": true}`
5. Both clients' next poll returns `both_ready: true` → proceed simultaneously

---

## 3. Rust Coordination Server Design

### 3.1 File Structure

```
SentinelDuoCoordServer/
├── Cargo.toml
├── config.toml
└── src/
    ├── main.rs
    ├── config.rs
    ├── error.rs
    ├── state.rs          # SessionState, ClientState, all shared state
    └── routes/
        ├── mod.rs        # Router registration
        ├── health.rs
        ├── session.rs    # heartbeat, session state read
        ├── barrier.rs    # sync barrier enter/poll/release
        ├── role.rs       # pull role and index management
        └── lockout.rs    # instance lockout tracking
```

### 3.2 Cargo.toml Dependencies

```toml
[package]
name = "sentinel-duo-coord-server"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.35", features = ["full"] }
axum = "0.7"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tracing = "0.1"
tracing-subscriber = "0.3"
tower-http = { version = "0.5", features = ["trace", "timeout"] }
anyhow = "1.0"
toml = "0.8"
```

### 3.3 Configuration (config.toml)

```toml
[server]
host = "127.0.0.1"
port = 7300

[session]
heartbeat_timeout_ms = 5000      # Client considered disconnected after 5s without heartbeat
barrier_timeout_ms = 90000       # Sync barrier breaks after 90s (e.g. loading screen)
max_clients = 2

[lockout]
max_resets_per_hour = 5          # Hard limit; triggers wait state at 4 (1 buffer)
warn_at = 4                      # Warn at 4 resets
```

### 3.4 State Types (state.rs)

```rust
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ClientPhase {
    Offline,
    Initializing,
    Buffing,
    TravelingToInstance,
    EnteringInstance,
    Positioning,          // non-puller moving to safe spot
    PullRunning,          // puller running pull path
    PullIceBlock,         // puller in Ice Block
    AoeOpening,           // support casting first Blizzard
    AoeBoth,              // both Blizzarding
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

impl Default for ClientPhase {
    fn default() -> Self { ClientPhase::Offline }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientState {
    pub id: String,           // "mage_a" or "mage_b"
    pub phase: ClientPhase,
    pub health_pct: u8,       // 0-100
    pub mana_pct: u8,         // 0-100
    pub bags_full: bool,
    pub is_dead: bool,
    pub in_instance: bool,
    pub last_heartbeat: Option<Instant>,
    pub connected: bool,
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
            last_heartbeat: None,
            connected: false,
        }
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct BarrierState {
    pub name: String,
    pub mage_a_ready: bool,
    pub mage_b_ready: bool,
    pub entered_at: Option<Instant>,  // first client entered at
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SessionPhase {
    Idle,
    Farming,
    Resetting,
    Vendoring,
    WaitingForLockout,
}

impl Default for SessionPhase { fn default() -> Self { SessionPhase::Idle } }

#[derive(Debug, Default)]
pub struct LockoutState {
    pub reset_count: u32,
    pub window_start: Option<Instant>,
    pub near_limit: bool,
}

#[derive(Debug, Default)]
pub struct SessionState {
    pub phase: SessionPhase,
    pub mage_a: ClientState,
    pub mage_b: ClientState,
    pub pull_index: u32,          // 0-based, which pull in the profile we're on
    pub puller_id: String,         // "mage_a" or "mage_b"
    pub barriers: HashMap<String, BarrierState>,
    pub lockout: LockoutState,
    pub vendor_requested_by: Option<String>,   // which client triggered vendor break
    pub session_start: Option<Instant>,
    pub runs_completed: u32,
    pub total_gold_earned_copper: u64,
}

pub type SharedState = Arc<Mutex<SessionState>>;
```

### 3.5 HTTP API Specification

All endpoints are GET. All responses are JSON. Client IDs are `"mage_a"` or `"mage_b"` (assigned by connection order — first connector gets `mage_a`).

---

#### `GET /health`

**Response:**
```json
{
  "status": "ok",
  "uptime_secs": 3600,
  "session_phase": "farming",
  "clients_connected": 2,
  "pull_index": 3,
  "reset_count": 2,
  "near_lockout_limit": false
}
```

---

#### `GET /api/v1/session`

Returns the full session state. Called after barrier waits to get fresh state.

**Response:**
```json
{
  "session_phase": "farming",
  "pull_index": 3,
  "puller_id": "mage_a",
  "runs_completed": 4,
  "mage_a": {
    "id": "mage_a",
    "phase": "aoe_both",
    "health_pct": 75,
    "mana_pct": 62,
    "bags_full": false,
    "is_dead": false,
    "in_instance": true,
    "connected": true
  },
  "mage_b": { ... }
}
```

---

#### `GET /api/v1/heartbeat?client_id=<id>&phase=<phase>&hp=<0-100>&mp=<0-100>&bags_full=<0|1>&is_dead=<0|1>&in_instance=<0|1>`

The primary polling endpoint. Called every 300ms. Sends client's state, receives full session state in response. The server updates this client's record atomically before responding.

**Query Parameters:**
- `client_id`: `"mage_a"` or `"mage_b"` (required)
- `phase`: Any `ClientPhase` variant in snake_case (required)
- `hp`: Integer 0-100 (required)
- `mp`: Integer 0-100 (required)
- `bags_full`: 0 or 1 (required)
- `is_dead`: 0 or 1 (required)
- `in_instance`: 0 or 1 (required)

**Server logic:**
1. Parse client_id — if unknown, assign role ("mage_a" if no clients registered, "mage_b" if one exists)
2. Update this client's record in SessionState
3. Check heartbeat of other client — if `last_heartbeat` > `heartbeat_timeout_ms`, mark as `Offline`
4. Return full session state

**Response:** Same as `GET /api/v1/session` plus a `"your_role"` field and an `"assigned_client_id"` field (so clients know their assigned ID).

```json
{
  "assigned_client_id": "mage_a",
  "your_role": "mage_a",
  "session_phase": "farming",
  "pull_index": 3,
  "puller_id": "mage_b",
  "lockout": {
    "reset_count": 2,
    "near_limit": false,
    "next_window_reset_secs": 1847
  },
  "vendor_break_requested": false,
  "mage_a": { ... },
  "mage_b": { ... }
}
```

---

#### `GET /api/v1/barrier/enter?client_id=<id>&name=<barrier_name>`

Client signals it has reached a named sync barrier and is waiting for its partner.

**Named barriers used by the farming loop:**

| Barrier Name | Description |
|---|---|
| `enter_instance` | Both ready to enter the instance portal |
| `pull_start` | Both in position; puller about to start run |
| `ice_block_up` | Puller has Ice Block; support opens Blizzard |
| `ice_block_cancel` | Support's first Blizzard tick landed; puller cancels IB + Nova |
| `pull_complete` | All mobs dead; advance to loot |
| `loot_complete` | All corpses looted; advance to next pull or exit |
| `ready_to_exit` | Farm route complete; both navigate to exit |
| `ready_to_reset` | Both outside; party leader resets |
| `ready_to_vendor` | Both at vendor zone; begin selling |
| `vendor_complete` | Both finished vendoring; return to instance |
| `return_complete` | Both back at instance entrance; resume farm |

**Response:**
```json
{
  "barrier": "ice_block_up",
  "your_ready": true,
  "partner_ready": false,
  "both_ready": false,
  "waiting_ms": 0
}
```

**Server logic:** Create barrier entry if not exists, mark this client's slot as ready, check if both ready.

---

#### `GET /api/v1/barrier/poll?client_id=<id>&name=<barrier_name>`

Poll whether the barrier has been satisfied. Client calls this after `enter` returns `both_ready: false`.

**Response:** Same as `/barrier/enter` but with `waiting_ms` showing elapsed time.

If `waiting_ms` > `barrier_timeout_ms` and partner is `Offline`, the server also sets `"partner_disconnected": true` — this allows the waiting client to break out of the barrier and enter solo recovery mode.

---

#### `GET /api/v1/barrier/release?client_id=<id>&name=<barrier_name>`

Client signals it is leaving the barrier (only needed for barriers where clients need to explicitly release, e.g., after a barrier is broken by timeout). Normally barriers auto-clear once both have passed through.

**Response:** `{"ok": true}`

---

#### `GET /api/v1/pull/advance?client_id=<id>`

Client signals it has finished looting and is ready to advance the pull index. When both clients call this, the server increments `pull_index` and swaps `puller_id`.

**Response:**
```json
{
  "new_pull_index": 4,
  "new_puller_id": "mage_b",
  "farm_complete": false    // true when pull_index >= profile.pull_count
}
```

**Server logic:**
1. Mark this client as "advance_ready"
2. If both ready: increment `pull_index`, swap `puller_id` (toggle between "mage_a" and "mage_b")
3. Clear advance_ready flags
4. If `pull_index >= total_pulls`: set `farm_complete: true`

---

#### `GET /api/v1/lockout/record?client_id=<id>`

Called by the party leader client immediately after calling `core.game_ui.reset_instances()`.

**Server logic:**
1. Increment `reset_count`
2. If `window_start` is nil or older than 1 hour, reset window
3. If `reset_count >= config.lockout.warn_at`: set `near_limit: true`
4. If `reset_count >= config.lockout.max_resets_per_hour`: calculate wait time until window resets

**Response:**
```json
{
  "reset_count": 4,
  "near_limit": true,
  "must_wait": false,
  "wait_remaining_secs": 0,
  "window_resets_at_secs": 847
}
```

---

#### `GET /api/v1/vendor/request?client_id=<id>`

Either client calls this when its bags are full. The server records who requested and marks the session as needing a vendor break.

**Response:**
```json
{
  "vendor_break_active": true,
  "requested_by": "mage_b"
}
```

---

#### `GET /api/v1/admin/reset`

Resets entire session state. Used for manual recovery or at bot start. No auth (localhost-only binding).

**Response:** `{"ok": true}`

---

### 3.6 Server State Machine

```
IDLE ──connect_both──► FARMING
FARMING ──farm_complete──► RESETTING
FARMING ──bags_full──► VENDORING
RESETTING ──near_lockout──► WAITING_FOR_LOCKOUT
RESETTING ──reset_ok──► FARMING
WAITING_FOR_LOCKOUT ──window_elapsed──► FARMING
VENDORING ──vendor_done──► FARMING
```

The server FSM is implicit in the `session.phase` field — it transitions atomically inside the mutex during heartbeat processing.

### 3.7 Role Assignment Algorithm

1. First client to successfully call `/api/v1/heartbeat` receives `assigned_client_id: "mage_a"` and becomes the initial puller.
2. Second client receives `assigned_client_id: "mage_b"`.
3. If only one client ever connects, the server operates in solo-degraded mode (returns `{"partner_disconnected": true}` on all endpoints).
4. Roles (puller/support) alternate every pull: `puller_id` starts as "mage_a" and toggles on each `/pull/advance` call when both clients are advance-ready.
5. The **gate opener** is always the client that has the Key to the City in its inventory (checked locally by Lua, stored in blackboard as `duo.has_instance_key`). This is independent of pull role.

### 3.8 Heartbeat Liveness Protocol

- Server tracks `last_heartbeat: Instant` per client in `ClientState`.
- On every heartbeat call: update `last_heartbeat`.
- On every response: check if the OTHER client's `last_heartbeat` is older than `heartbeat_timeout_ms` (5000ms). If so: set their `connected: false` and `phase: Offline`.
- Lua clients check `partner.connected` in every heartbeat response. If `false`: enter `PARTNER_DISCONNECTED` handling (see §8.4).

---

## 4. Lua Client Architecture

### 4.1 File/Module Structure

```
SentinelDuoFarm/
├── header.lua                         # Script metadata (name, version, author)
├── main.lua                           # Entry point: registers PS callbacks, boots App
├── core/
│   ├── App.lua                        # Top-level orchestrator (owns all objects)
│   ├── StateMachine.lua               # Generic table-driven FSM
│   └── Config.lua                     # Local configuration (server URL, poll rate, etc.)
├── coordination/
│   ├── CoordClient.lua                # HTTP polling client for coord server
│   └── PartnerState.lua               # Parsed partner state model
├── states/
│   ├── StateInit.lua                  # Connect to coord server, detect role
│   ├── StateBuffing.lua               # Ice Armor, Ice Barrier, conjure consumables
│   ├── StateTravelToInstance.lua      # Navigate to Stratholme SE entrance
│   ├── StateEntering.lua              # Open gate (if key holder), enter portal
│   ├── StateFarming.lua               # Farm sub-FSM controller
│   ├── farm/
│   │   ├── FarmPositioning.lua        # Non-puller → safe position
│   │   ├── FarmPullRunning.lua        # Puller runs pull path, tags mobs
│   │   ├── FarmPullIceBlock.lua       # Puller enters Ice Block
│   │   ├── FarmAoeOpening.lua         # Support casts first Blizzard
│   │   ├── FarmIceBlockCancel.lua     # Puller cancels IB, Nova, repositions
│   │   ├── FarmAoeBoth.lua            # Both mages Blizzarding until clear
│   │   └── FarmLooting.lua            # Loot all corpses
│   ├── StateExiting.lua               # Navigate to exit or release+ghost
│   ├── StateResetting.lua             # Party leader calls reset_instances()
│   ├── StateWaitingLockout.lua        # Idle at entrance, waiting for window
│   ├── StateTravelToVendor.lua        # Hearthstone → fly → walk to vendor
│   ├── StateVendoring.lua             # Sell + repair + restock
│   ├── StateTravelReturn.lua          # Fly back → walk to Stratholme SE
│   ├── StateDead.lua                  # Ghost nav to corpse, resurrect
│   └── StatePaused.lua                # User paused
├── combat/
│   ├── AoeRotation.lua                # Blizzard + Frost Nova chain logic
│   ├── DefensiveManager.lua           # Ice Block, Cold Snap, Ice Barrier tracking
│   └── PullExecutor.lua               # Run pull path, cast R1 Frostbolt/CS to tag
├── navigation/
│   └── DuoNav.lua                     # Thin wrapper around NavAdapter
├── loot/
│   └── LootEngine.lua                 # Corpse detection, loot window, bag check
├── travel/
│   ├── HearthstoneManager.lua         # Use HS, wait for loading screen
│   ├── VendorInteractor.lua           # Navigate to NPC, sell, repair
│   └── FlightMasterInteractor.lua     # Interact with flight master, take flight
├── profiles/
│   ├── stratholme_se.lua              # Reference Stratholme SE profile
│   └── ProfileLoader.lua              # Load profile by name
├── spells/
│   ├── spell_data.lua                 # Pre-extracted MaNGOS spell table
│   └── SpellCatalog.lua               # Rank selection + spell resolution
├── ui/
│   ├── DuoWindow.lua                  # Main window (SentinelUI wrapper)
│   └── tabs/
│       ├── DashboardTab.lua
│       ├── CoordTab.lua
│       ├── StatsTab.lua
│       ├── ProfileTab.lua
│       └── DebugTab.lua
└── lib/
    └── json.lua                       # JSON encode/decode (copy from sentinel/lib)
```

### 4.2 main.lua Entry Point

```lua
-- header.lua sets: _G.SENTINEL_DUO_VERSION = "1.0.0"
local App = require("core/App")

local _app = nil

core.register_on_pre_tick_callback(function()
    if _app then _app:on_pre_tick() end
end)

core.register_on_update_callback(function()
    if not _app then
        _app = App:new()
        _app:initialize()
    end
    _app:on_update()
end)

core.register_on_render_callback(function()
    if _app then _app:on_render() end
end)

core.register_on_render_menu_callback(function()
    if _app then _app:on_render_menu() end
end)
```

### 4.3 App.lua — Top-Level Orchestrator

```lua
-- Public interface:
function App:new() → App
function App:initialize()                    -- boot all subsystems
function App:on_pre_tick()
function App:on_update()                     -- called by PS update callback
function App:on_render()
function App:on_render_menu()
function App:get_blackboard() → table
function App:get_event_bus() → table
function App:shutdown()
```

`on_update` sequence:
1. Refresh sensors (player HP/MP/position/state from `core.object_manager`)
2. Poll CoordClient (if 300ms elapsed since last poll)
3. Poll NavAdapter
4. Tick master FSM
5. If in a farm state: tick AoeRotation/DefensiveManager
6. Sync UI

### 4.4 Blackboard Keys

All duo-specific blackboard keys use the `duo.` prefix to avoid collision with Sentinel's existing keys.

```lua
-- Identity
"duo.my_client_id"           -- "mage_a" or "mage_b"
"duo.is_puller"              -- boolean
"duo.has_instance_key"       -- boolean (Key to the City in inventory)

-- Coordination
"duo.coord_connected"        -- boolean
"duo.coord_last_poll_ms"     -- game_time ms
"duo.partner_phase"          -- ClientPhase string
"duo.partner_health_pct"     -- 0-100
"duo.partner_mana_pct"       -- 0-100
"duo.partner_connected"      -- boolean
"duo.partner_bags_full"      -- boolean
"duo.session_phase"          -- server session phase
"duo.pull_index"             -- current pull index
"duo.puller_id"              -- "mage_a" or "mage_b"
"duo.vendor_break_active"    -- boolean
"duo.lockout.reset_count"    -- number
"duo.lockout.near_limit"     -- boolean
"duo.lockout.wait_secs"      -- number (remaining wait if must_wait)

-- Combat state
"duo.current_blizzard_pos"   -- vec3
"duo.frost_nova_last_cast_ms" -- game_time ms
"duo.ice_block_active"       -- boolean
"duo.ice_block_cast_ms"      -- game_time ms
"duo.cold_snap_last_cast_ms" -- game_time ms
"duo.mob_count_in_pack"      -- number of mobs currently in pull
"duo.pull_path_index"        -- which waypoint in pull path puller is at
"duo.pull_tagging_complete"  -- boolean (enough mobs tagged, IB time)
"duo.all_mobs_dead"          -- boolean

-- Travel
"duo.hs_used_ms"             -- game_time ms when HS was used
"duo.at_vendor"              -- boolean
"duo.vendor_sell_complete"   -- boolean
"duo.at_flight_master"       -- boolean
"duo.flight_in_progress"     -- boolean
"duo.at_instance_entrance"   -- boolean

-- Stats
"duo.session_start_ms"       -- game_time ms
"duo.runs_completed"         -- number
"duo.gold_earned_copper"     -- number
"duo.deaths_this_session"    -- number
"duo.gph_estimate"           -- gold per hour (rolling avg)
```

### 4.5 CoordClient.lua — Public Interface

```lua
-- Create once; pass to App
function CoordClient:new(config) → CoordClient
  -- config: { server_url, poll_interval_ms, my_client_id }

-- Call from App:on_update() every frame; internally throttles to poll_interval_ms
function CoordClient:tick(blackboard, game_time_ms)

-- Explicitly enter a named sync barrier; returns immediately (async)
function CoordClient:enter_barrier(name)

-- Poll barrier status — returns true if both_ready, false if still waiting
-- Returns "timeout" if partner_disconnected
function CoordClient:poll_barrier(name) → boolean | "timeout"

-- Release a barrier (after both_ready confirmed)
function CoordClient:release_barrier(name)

-- Signal pull advance (called after loot complete)
function CoordClient:advance_pull()

-- Signal bag full / need vendor
function CoordClient:request_vendor_break()

-- Record a lockout reset (call after reset_instances())
function CoordClient:record_reset()

-- Last received session state (may be nil before first poll)
function CoordClient:get_session() → table | nil

-- Returns true if coord server is reachable and connected
function CoordClient:is_connected() → boolean
```

**Internal implementation note:** `core.http_get` is async. CoordClient maintains a `_pending_request` flag. If a request is in flight, `tick()` skips dispatching a new one. Responses are processed in the callback. If the callback hasn't fired within 2× `poll_interval_ms`, the request is considered timed out and `_pending_request` is cleared.

### 4.6 Master State Machine

The `StateMachine.lua` is a simple table-driven FSM:

```lua
-- State entry: function(fsm, blackboard) → void
-- State update: function(fsm, blackboard) → next_state_name | nil (nil = stay)
-- State exit: function(fsm, blackboard) → void
-- All transitions are explicit returns from update()
```

---

## 5. Spell Data Layer

### 5.1 MaNGOS Extraction Query

Run once to generate `spell_data.lua`:

```bash
mycli -u root -pascent mangos --table -e "
SELECT
  s.ID              AS spell_id,
  s.SpellName_0     AS name,
  s.Rank_0          AS rank,
  s.ManaCost        AS mana_cost,
  s.RecoveryTime    AS cooldown_ms,
  r.RangeMax        AS max_range,
  r.RangeMin        AS min_range,
  IFNULL(ct.CastTime, 0) AS cast_time_ms,
  s.School          AS school,
  s.Effect1         AS effect1
FROM spell s
LEFT JOIN SpellRange r ON s.rangeIndex = r.ID
LEFT JOIN SpellCastTimes ct ON s.CastingTimeIndex = ct.ID
WHERE s.ID IN (
  10185,10186,10187,10188,10189,10190,27085,
  122,865,6131,10230,27088,
  45438,
  11958,
  11426,13031,13032,13033,
  2139,
  116,205,837,7322,8406,8407,8408,10179,10180,10181,25304,27071,
  1953,
  12051,
  120,8492,10159,10160,10161,27087,
  7302,7320,10219,10220,
  168,7300,7301,
  5504,5505,7326,7327,7328,10138,10139,27090,
  587,597,990,6129,10144,10145,28612,
  604,8450,8451,10173,10174,33944,
  1463,8494,8495,10191,10192,10193,27131,
  6948,
  8690
)
ORDER BY s.SpellName_0, s.ManaCost
" 2>/dev/null
```

### 5.2 Spell Data Table Schema (spell_data.lua)

```lua
-- spell_data.lua — Auto-generated from MaNGOS DB. Do not edit manually.
-- Format: spell_data[spell_id] = { name, rank, mana_cost, cooldown_ms, max_range, min_range, cast_time_ms, school }
local spell_data = {
    -- Blizzard
    [10185] = { name="Blizzard", rank=1,  mana_cost=320,  cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },  -- school 16 = frost
    [10186] = { name="Blizzard", rank=2,  mana_cost=440,  cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },
    [10187] = { name="Blizzard", rank=3,  mana_cost=560,  cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },
    [10188] = { name="Blizzard", rank=4,  mana_cost=665,  cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },
    [10189] = { name="Blizzard", rank=5,  mana_cost=765,  cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },
    [10190] = { name="Blizzard", rank=6,  mana_cost=880,  cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },
    [27085] = { name="Blizzard", rank=7,  mana_cost=1045, cooldown_ms=0, max_range=30, cast_time_ms=0,    school=16 },  -- TBC max rank

    -- Frost Nova
    [122]   = { name="Frost Nova", rank=1, mana_cost=65,  cooldown_ms=25000, max_range=0, cast_time_ms=0, school=16 },
    [865]   = { name="Frost Nova", rank=2, mana_cost=75,  cooldown_ms=25000, max_range=0, cast_time_ms=0, school=16 },
    [6131]  = { name="Frost Nova", rank=3, mana_cost=90,  cooldown_ms=25000, max_range=0, cast_time_ms=0, school=16 },
    [10230] = { name="Frost Nova", rank=4, mana_cost=105, cooldown_ms=25000, max_range=0, cast_time_ms=0, school=16 },
    [27088] = { name="Frost Nova", rank=5, mana_cost=115, cooldown_ms=25000, max_range=0, cast_time_ms=0, school=16 },  -- TBC max

    -- Ice Block
    [45438] = { name="Ice Block", rank=1, mana_cost=0, cooldown_ms=300000, max_range=0, cast_time_ms=0, school=16 },

    -- Cold Snap
    [11958] = { name="Cold Snap", rank=1, mana_cost=0, cooldown_ms=600000, max_range=0, cast_time_ms=0, school=16 },

    -- Ice Barrier (talent)
    [11426] = { name="Ice Barrier", rank=4, mana_cost=375, cooldown_ms=30000, max_range=0, cast_time_ms=0, school=16 },
    [13031] = { name="Ice Barrier", rank=5, mana_cost=440, cooldown_ms=30000, max_range=0, cast_time_ms=0, school=16 },
    [13032] = { name="Ice Barrier", rank=6, mana_cost=515, cooldown_ms=30000, max_range=0, cast_time_ms=0, school=16 },
    [13033] = { name="Ice Barrier", rank=7, mana_cost=595, cooldown_ms=30000, max_range=0, cast_time_ms=0, school=16 },  -- TBC max

    -- Counterspell
    [2139]  = { name="Counterspell", rank=1, mana_cost=150, cooldown_ms=24000, max_range=30, cast_time_ms=0, school=64 },

    -- Frostbolt (key ranks)
    [116]   = { name="Frostbolt", rank=1,  mana_cost=25,  cooldown_ms=0, max_range=30, cast_time_ms=1500, school=16 },  -- pull tag
    [27071] = { name="Frostbolt", rank=12, mana_cost=330, cooldown_ms=0, max_range=30, cast_time_ms=3000, school=16 },  -- TBC max

    -- Blink
    [1953]  = { name="Blink", rank=1, mana_cost=195, cooldown_ms=15000, max_range=0, cast_time_ms=0, school=64 },

    -- Evocation
    [12051] = { name="Evocation", rank=1, mana_cost=0, cooldown_ms=480000, max_range=0, cast_time_ms=0, school=64 },

    -- Cone of Cold (TBC max)
    [27087] = { name="Cone of Cold", rank=6, mana_cost=290, cooldown_ms=10000, max_range=0, cast_time_ms=0, school=16 },

    -- Ice Armor (TBC max)
    [10220] = { name="Ice Armor", rank=4, mana_cost=400, cooldown_ms=0, max_range=0, cast_time_ms=0, school=16 },

    -- Dampen Magic (TBC max, for pulling to reduce threat/aggro range)
    [33944] = { name="Dampen Magic", rank=6, mana_cost=295, cooldown_ms=0, max_range=30, cast_time_ms=0, school=64 },

    -- Mana Shield (TBC max)
    [27131] = { name="Mana Shield", rank=7, mana_cost=110, cooldown_ms=0, max_range=0, cast_time_ms=0, school=64 },

    -- Conjure Water (max conjurable in TBC at 70)
    [27090] = { name="Conjure Water", rank=8, mana_cost=665, cooldown_ms=0, max_range=0, cast_time_ms=3000, school=64 },

    -- Conjure Food (max)
    [28612] = { name="Conjure Food", rank=7, mana_cost=520, cooldown_ms=0, max_range=0, cast_time_ms=3000, school=64 },

    -- Hearthstone (item, not spell — but tracked for CD)
    [8690]  = { name="Hearthstone", rank=1, mana_cost=0, cooldown_ms=3600000, max_range=0, cast_time_ms=10000, school=0 },
}
return spell_data
```

### 5.3 SpellCatalog.lua — Rank Selection Algorithm

```lua
-- Public interface:
function SpellCatalog:new(spell_data_table) → SpellCatalog
function SpellCatalog:resolve(spell_name, player) → spell_id | nil
  -- Returns highest known rank of the spell that the player has learned.
  -- Algorithm: for each (id, entry) where entry.name == spell_name,
  --   if core.spell_book.has_spell(id) → collect
  -- Return the id with the highest rank number.

function SpellCatalog:resolve_by_id(spell_id) → entry | nil
function SpellCatalog:get_mana_cost(spell_name, player) → number
function SpellCatalog:get_cooldown_remaining(spell_name, player) → seconds
function SpellCatalog:is_ready(spell_name, player) → boolean
  -- Returns true if: has_spell AND gcd < 0.1 AND cooldown_remaining < 0.1
```

---

## 6. Dungeon Farm Profile Schema

### 6.1 Profile Table Schema

```lua
---@class DuoPullDefinition
---@field id number                     -- 1-based pull index
---@field pull_path vec3[]              -- ordered waypoints puller runs through to aggro mobs
---@field aggro_radius number           -- puller tags mobs within this radius of each waypoint
---@field pull_tag_spell string         -- "counterspell" or "frostbolt_r1" (which to use for tagging)
---@field expected_mob_count_min number -- fail-check: if fewer mobs tagged, abort pull
---@field expected_mob_count_max number -- fail-check: if more mobs tagged, emergency IB immediately
---@field ice_block_position vec3       -- where puller stands when it Ice Blocks
---@field blizzard_center vec3          -- where support and puller cast Blizzard (center of pack)
---@field safe_position vec3            -- where support stands during pull run phase
---@field puller_reposition vec3        -- where puller moves after canceling Ice Block
---@field mob_ids number[]              -- optional: if non-empty, only these NPC IDs count as valid pulls
---@field mob_ids_avoid number[]        -- optional: avoid tagging these NPC IDs (e.g. elites)
---@field pull_delay_ms number          -- ms between starting pull run and casting first tag spell

---@class DuoVendorRoute
---@field hearthstone_item_id number    -- item ID for hearthstone (6948)
---@field hearthstone_dest_map_id number -- expected map ID after HS lands
---@field vendor_npc_id number          -- NPC entry ID of vendor
---@field vendor_position vec3          -- world coords of vendor NPC
---@field vendor_walk_path vec3[]       -- waypoints from HS landing point to vendor
---@field flight_master_npc_id number   -- NPC entry ID of flight master
---@field flight_master_position vec3   -- world coords
---@field flight_dest_name string       -- flight destination display name (for click)
---@field flight_dest_map_id number     -- expected map ID after flight lands
---@field flight_dest_position vec3     -- approx landing coords
---@field walkback_path vec3[]          -- waypoints from flight landing → instance entrance
---@field repair_at_vendor boolean      -- whether to repair

---@class DuoProfile
---@field id string                     -- unique profile ID, e.g. "stratholme_se_v1"
---@field dungeon_name string
---@field instance_map_id number        -- map ID inside the instance (for detection)
---@field outdoor_map_id number         -- map ID of the outdoor zone
---@field entrance_position vec3        -- world coords of the instance portal
---@field entrance_walk_path vec3[]     -- final approach path (last 50 yards to entrance)
---@field gate_object_id number         -- game object ID of the gate/door to interact with (0 if none)
---@field gate_position vec3            -- world coords of gate object
---@field gate_key_item_id number       -- item ID required for gate (0 if none); check keyring bag -2
---@field exit_position vec3            -- world coords of the instance exit (inside)
---@field exit_use_death boolean        -- if true: die and release to exit; if false: nav to exit portal
---@field pulls DuoPullDefinition[]     -- ordered pull definitions
---@field vendor_route DuoVendorRoute
---@field timing table                  -- timing overrides (see §6.3)
---@field min_mana_pct_to_pull number   -- don't start a pull below this mana% (e.g. 0.60)
---@field min_hp_pct_to_pull number     -- don't start a pull below this HP% (e.g. 0.50)
---@field bags_full_threshold number    -- free slots below this = bags full (e.g. 4)
```

### 6.2 Timing Parameters

```lua
---@field timing.pull_to_ib_mob_count number         -- tag at least this many mobs before Ice Block (default 5)
---@field timing.ice_block_cancel_delay_ms number    -- ms after support's first Blizzard tick before puller cancels IB (default 2500)
---@field timing.frost_nova_after_ib_cancel_ms number -- ms delay between IB cancel and Nova cast (default 200)
---@field timing.blizzard_recast_buffer_ms number    -- ms before Blizzard expires to start next cast (default 500)
---@field timing.loot_settle_ms number               -- ms after last mob death before looting starts (default 2000)
---@field timing.between_pulls_ms number             -- ms pause between loot complete and next pull (default 1500)
---@field timing.hs_landing_detect_timeout_ms number -- ms to wait for map change after HS use (default 30000)
---@field timing.flight_arrive_detect_timeout_ms number -- ms to wait for flight to land (default 300000)
---@field timing.barrier_timeout_ms number           -- per-profile barrier override (default uses server config)
```

### 6.3 Stratholme Service Entrance Reference Profile

```lua
-- profiles/stratholme_se.lua
-- IMPORTANT: All vec3 coordinates are approximate and MUST be verified and captured
-- in-game using the SentinelDuoFarm coordinate capture tool before use.
-- X/Y/Z values below are based on known Stratholme SE layout geometry.

local Profile = {}

Profile.id = "stratholme_se_v1"
Profile.dungeon_name = "Stratholme Service Entrance"
Profile.instance_map_id = 329
Profile.outdoor_map_id = 0  -- Eastern Plaguelands is in the main world (map 0)

-- Outside the instance — Eastern Plaguelands coordinates
Profile.entrance_position  = { x = 3355.0, y = -3381.0, z = 133.5 }
Profile.gate_position      = { x = 3358.0, y = -3378.0, z = 133.2 }
Profile.gate_object_id     = 183396   -- "Stratholme Gate" (Service Entrance)
Profile.gate_key_item_id   = 12382    -- "Key to the City"

-- Final walk-in path (from main road to entrance gate, ~120 yards)
Profile.entrance_walk_path = {
    { x = 3305.0, y = -3381.0, z = 130.0 },
    { x = 3330.0, y = -3381.0, z = 131.5 },
    { x = 3355.0, y = -3381.0, z = 133.5 },
}

-- Inside instance: exit coordinates
-- Strategy: use death+release to exit (faster than navigating to portal)
Profile.exit_position = { x = 2905.0, y = -1225.0, z = 101.0 }
Profile.exit_use_death = true  -- die, release, ghost-nav to entrance, reset outside

-- Pull definitions (3 pulls covering the Service Entrance farm zone)
Profile.pulls = {}

-- ─────────────────────────────────────────────────────────
-- PULL 1: Entry corridor groups
-- Puller runs north through the first corridor, tags 2-3 groups (6-10 mobs)
-- ─────────────────────────────────────────────────────────
Profile.pulls[1] = {
    id = 1,
    pull_path = {
        { x = 2920.0, y = -1210.0, z = 101.0 },
        { x = 2940.0, y = -1195.0, z = 101.0 },
        { x = 2955.0, y = -1180.0, z = 101.0 },
        { x = 2965.0, y = -1168.0, z = 101.0 },
    },
    aggro_radius = 18.0,
    pull_tag_spell = "frostbolt_r1",
    expected_mob_count_min = 4,
    expected_mob_count_max = 12,
    ice_block_position     = { x = 2930.0, y = -1205.0, z = 101.0 },
    blizzard_center        = { x = 2940.0, y = -1195.0, z = 101.0 },
    safe_position          = { x = 2912.0, y = -1218.0, z = 101.0 },
    puller_reposition      = { x = 2920.0, y = -1210.0, z = 101.0 },
    mob_ids = {},
    mob_ids_avoid = {},
    pull_delay_ms = 500,
}

-- ─────────────────────────────────────────────────────────
-- PULL 2: Mid-corridor groups (roles swapped — Mage B pulls)
-- ─────────────────────────────────────────────────────────
Profile.pulls[2] = {
    id = 2,
    pull_path = {
        { x = 2960.0, y = -1165.0, z = 101.0 },
        { x = 2975.0, y = -1150.0, z = 101.0 },
        { x = 2990.0, y = -1138.0, z = 101.0 },
    },
    aggro_radius = 18.0,
    pull_tag_spell = "frostbolt_r1",
    expected_mob_count_min = 4,
    expected_mob_count_max = 12,
    ice_block_position     = { x = 2948.0, y = -1158.0, z = 101.0 },
    blizzard_center        = { x = 2960.0, y = -1155.0, z = 101.0 },
    safe_position          = { x = 2930.0, y = -1200.0, z = 101.0 },
    puller_reposition      = { x = 2950.0, y = -1165.0, z = 101.0 },
    mob_ids = {},
    mob_ids_avoid = {},
    pull_delay_ms = 500,
}

-- ─────────────────────────────────────────────────────────
-- PULL 3: Deep corridor / Market Row groups (Mage A pulls again)
-- ─────────────────────────────────────────────────────────
Profile.pulls[3] = {
    id = 3,
    pull_path = {
        { x = 2995.0, y = -1132.0, z = 101.0 },
        { x = 3010.0, y = -1120.0, z = 101.0 },
        { x = 3025.0, y = -1110.0, z = 101.0 },
    },
    aggro_radius = 18.0,
    pull_tag_spell = "frostbolt_r1",
    expected_mob_count_min = 4,
    expected_mob_count_max = 14,
    ice_block_position     = { x = 2985.0, y = -1135.0, z = 101.0 },
    blizzard_center        = { x = 2998.0, y = -1128.0, z = 101.0 },
    safe_position          = { x = 2960.0, y = -1162.0, z = 101.0 },
    puller_reposition      = { x = 2988.0, y = -1138.0, z = 101.0 },
    mob_ids = {},
    mob_ids_avoid = { 10184 },  -- avoid tagging Timmy the Cruel (elite, not farmable)
    pull_delay_ms = 500,
}

-- ─────────────────────────────────────────────────────────
-- Vendor Route: Hearthstone to Aerie Peak (Hinterlands)
-- Vendor: Bro'kin the vendor at Aerie Peak
-- Flight: Aerie Peak → Light's Hope Chapel (Eastern Plaguelands)
-- Walk-back: LHC → Stratholme SE entrance
-- ─────────────────────────────────────────────────────────
Profile.vendor_route = {
    hearthstone_item_id      = 6948,
    hearthstone_dest_map_id  = 0,    -- Aerie Peak is in the world map (Hinterlands)
    -- Expected approx landing position at Aerie Peak hearthstone inn
    hearthstone_dest_position = { x = -731.0, y = -2233.0, z = 132.0 },

    vendor_npc_id     = 4300,        -- A Hinterlands vendor (confirm NPC ID in-game)
    vendor_position   = { x = -720.0, y = -2238.0, z = 132.0 },
    vendor_walk_path  = {
        { x = -731.0, y = -2233.0, z = 132.0 },
        { x = -720.0, y = -2238.0, z = 132.0 },
    },
    repair_at_vendor = true,

    flight_master_npc_id    = 4317,  -- Aerie Peak flight master (confirm in-game)
    flight_master_position  = { x = -709.5, y = -2252.0, z = 135.0 },
    flight_dest_name        = "Light's Hope Chapel",
    flight_dest_map_id      = 0,
    flight_dest_position    = { x = 3439.0, y = -1364.0, z = 56.5 },

    -- Walk from Light's Hope Chapel to Stratholme SE entrance (~4km, use NavAdapter)
    walkback_path = {
        { x = 3439.0, y = -1364.0, z = 56.5 },   -- LHC flight landing
        { x = 3380.0, y = -1820.0, z = 107.0 },
        { x = 3362.0, y = -2200.0, z = 115.0 },
        { x = 3358.0, y = -2800.0, z = 126.0 },
        { x = 3355.0, y = -3381.0, z = 133.5 },   -- Stratholme SE entrance
    },
}

Profile.timing = {
    pull_to_ib_mob_count          = 5,
    ice_block_cancel_delay_ms     = 2500,
    frost_nova_after_ib_cancel_ms = 200,
    blizzard_recast_buffer_ms     = 500,
    loot_settle_ms                = 2000,
    between_pulls_ms              = 1500,
    hs_landing_detect_timeout_ms  = 30000,
    flight_arrive_detect_timeout_ms = 300000,
    barrier_timeout_ms            = 90000,
}

Profile.min_mana_pct_to_pull  = 0.60
Profile.min_hp_pct_to_pull    = 0.50
Profile.bags_full_threshold   = 4  -- free bag slots below this = bags full

return Profile
```

---

## 7. State Machine Specifications

### 7.1 Master FSM — State Transition Table

| Current State | Event / Condition | Next State | Actions |
|---|---|---|---|
| `INIT` | coord server responds | `COORD_CONNECT` | Assign client_id from server |
| `INIT` | coord server unreachable (5s) | `ERROR` | Log "coord server unreachable" |
| `COORD_CONNECT` | partner.connected == true | `BUFFING` | Publish `duo:partner_connected` |
| `COORD_CONNECT` | timeout 120s | `SOLO_MODE` | Log warning, continue alone |
| `BUFFING` | all buffs active AND mana > 80% | `TRAVEL_TO_INSTANCE` | — |
| `BUFFING` | missing Ice Armor | self | Cast Ice Armor |
| `BUFFING` | missing Ice Barrier | self | Cast Ice Barrier |
| `BUFFING` | mana < 80%, have water | self | Sit and drink |
| `TRAVEL_TO_INSTANCE` | at_instance_entrance == true | `ENTERING` | Stop navigation |
| `ENTERING` | is_puller AND has_key AND gate_not_open | self | Interact with gate object |
| `ENTERING` | inside_instance == true (both at barrier `enter_instance`) | `FARMING` | Init pull_index = 0 |
| `FARMING` | farm_complete == true | `EXITING` | Stop combat |
| `FARMING` | vendor_break_active == true | `EXITING` | Set exit reason = vendor |
| `FARMING` | player.is_dead == true | `DEAD` | Record death |
| `EXITING` | outside_instance AND exit_reason == reset | `RESETTING` | — |
| `EXITING` | outside_instance AND exit_reason == vendor | `TRAVEL_TO_VENDOR` | — |
| `RESETTING` | lockout.must_wait == true | `WAITING_LOCKOUT` | — |
| `RESETTING` | both at barrier `ready_to_reset` AND is_party_leader | self | Call reset_instances() + record_reset() |
| `RESETTING` | reset_confirmed (re-enter instance works) | `BUFFING` | Clear farm state |
| `WAITING_LOCKOUT` | lockout.wait_remaining_secs <= 0 | `BUFFING` | — |
| `TRAVEL_TO_VENDOR` | at_vendor == true | `VENDORING` | — |
| `VENDORING` | sell_complete AND repair_complete AND stocks_ok | `TRAVEL_RETURN` | Signal vendor_complete barrier |
| `TRAVEL_RETURN` | at_instance_entrance == true | `BUFFING` | — |
| `DEAD` | player.is_alive == true | `BUFFING` | Re-buff after rez |
| `PAUSED` | user unpauses | previous_state | Restore state |
| `ERROR` | — | terminal | Log + stop |

### 7.2 Farm Sub-FSM — State Transition Table

| Current State | Event / Condition | Next State | Actions |
|---|---|---|---|
| `FARM_INIT` | pull_index loaded | `FARM_POSITIONING` | Set role from puller_id |
| `FARM_POSITIONING` | is_puller: at pull path start | `FARM_BARRIER_PULL_START` | Enter `pull_start` barrier |
| `FARM_POSITIONING` | is_support: at safe_position | `FARM_BARRIER_PULL_START` | Enter `pull_start` barrier |
| `FARM_BARRIER_PULL_START` | both_ready == true | `FARM_PULL_RUNNING` | — |
| `FARM_PULL_RUNNING` | is_puller: mob_count >= pull_to_ib_mob_count | `FARM_PULL_ICEBLOCK` | Navigate to ice_block_position |
| `FARM_PULL_RUNNING` | is_puller: at path end with < min_mobs | `FARM_ABORT_PULL` | Enter `pull_start` barrier to regroup |
| `FARM_PULL_RUNNING` | is_support: wait in safe_position, maintain buffs | self | — |
| `FARM_PULL_ICEBLOCK` | is_puller: Ice Block cast confirmed | `FARM_BARRIER_IB_UP` | Enter `ice_block_up` barrier |
| `FARM_BARRIER_IB_UP` | both_ready | `FARM_AOE_OPENING` | — |
| `FARM_AOE_OPENING` | is_support: Blizzard channel started | `FARM_BARRIER_IB_CANCEL` | Enter `ice_block_cancel` barrier |
| `FARM_AOE_OPENING` | is_puller: wait in Ice Block | self | Monitor Ice Block duration |
| `FARM_BARRIER_IB_CANCEL` | ice_block_cancel_delay_ms elapsed | `FARM_ICEBLOCK_CANCEL` | — |
| `FARM_ICEBLOCK_CANCEL` | is_puller: IB cancelled, Nova cast, reposition | `FARM_AOE_BOTH` | — |
| `FARM_ICEBLOCK_CANCEL` | is_support: continue Blizzard | `FARM_AOE_BOTH` | — |
| `FARM_AOE_BOTH` | all_mobs_dead == true | `FARM_BARRIER_PULL_COMPLETE` | Enter `pull_complete` barrier |
| `FARM_AOE_BOTH` | mana < 20% AND safe (all rooted) | self | Use Cold Snap, re-Nova, Evocation if applicable |
| `FARM_BARRIER_PULL_COMPLETE` | both_ready | `FARM_LOOTING` | Wait loot_settle_ms |
| `FARM_LOOTING` | all corpses looted | `FARM_BARRIER_LOOT_COMPLETE` | Enter `loot_complete` barrier |
| `FARM_BARRIER_LOOT_COMPLETE` | both_ready | `FARM_ADVANCE` | Call /pull/advance |
| `FARM_ADVANCE` | farm_complete == true | exit to master `EXITING` | Signal farm done |
| `FARM_ADVANCE` | more pulls remain | `FARM_INIT` | Reset combat state |
| `FARM_ABORT_PULL` | both at barrier | `FARM_INIT` | Reuse same pull_index |

### 7.3 AoE Rotation Logic (FarmAoeBoth.lua)

Tick at 75ms:

```
Priority:
1. EMERGENCY: HP < 20% → Ice Block (if off CD); OR Cold Snap + Ice Block
2. DEFENSIVE: Ice Barrier missing → queue_ice_barrier
3. SUSTAIN: Blizzard channel < 0.5s remaining → cast_position_spell(blizzard_max, center)
4. NOVA: Frost Nova off CD AND mobs not all rooted → cast_self_spell(frost_nova_max)
5. MANA: mana < 20% AND Cold Snap available → cast_self_spell(cold_snap) [resets Frost Nova, Ice Block]
6. MANA: mana < 15% AND Evocation available AND no mobs in 8yd → cast_self_spell(evocation)
7. FILLER: Blizzard on CD (should not happen normally) → cast_position_spell(blizzard)
```

**Blizzard Tracking:** Track channel start time in blackboard. Blizzard is an 8-second channel with ticks every 1 second. The Lua client should re-cast when `(game_time_ms - channel_start_ms) >= 7500` (0.5s before expiry).

**Mob death detection:** Scan `unit_helper:get_enemy_list_around(blizzard_center, 25, false, false)` every 500ms. When count == 0 for 2 consecutive scans → `all_mobs_dead = true`.

### 7.4 Timeout and Retry Policies

| State / Operation | Timeout | Retry Action |
|---|---|---|
| Coord server initial connect | 5s | Retry indefinitely (log warning every 10s) |
| Sync barrier | 90s (configurable) | Check partner.connected; if offline → degraded solo mode |
| Navigation move_to | 60s without arrival | Stop + retry from current position; after 3 retries → stuck |
| Instance entrance detection | 30s after entering portal area | If no map change → retry interact with gate |
| Loot window open | 5s after interact | Skip corpse, continue |
| Vendor interaction | 10s | Retry interact_with_object |
| Flight master interaction | 10s | Retry |
| Hearthstone landing | 30s after use | Re-check map_id; if same map → HS may have failed, retry |
| Pull (insufficient mobs) | immediately on pull path complete | Abort, enter regroup barrier |
| Death resurrection delay | per `get_resurrect_corpse_delay()` | Wait until 0, then resurrect_corpse() |

---

## 8. Edge Case Handling

### 8.1 Death Recovery Protocol

**Detection:**
```lua
local is_dead  = player:is_dead()       -- alive = false
local is_ghost = player:is_ghost()      -- alive = false AND ghost buff active
```

**Single Death (one mage dies, partner survives):**

1. Dead mage transitions to `DEAD` state.
2. Dead mage sends heartbeat with `phase: dead`, `is_dead: true`.
3. Living mage sees `partner.is_dead = true` → enters `FARM_BARRIER_PULL_COMPLETE` immediately (stops AoE, waits for partner).
4. Dead mage: wait `get_resurrect_corpse_delay()` seconds, then call `resurrect_corpse()` with a jitter of 0-3s.
5. Dead mage navigates (as ghost) to `get_corpse_position()` using NavAdapter `move_to`.
6. Dead mage calls `resurrect_corpse()` once within 4 yards of corpse.
7. Dead mage: re-buff (Ice Armor, Ice Barrier, mana check) → rejoin at current pull_index.
8. If dead mage resurrected in ghost-nav outside instance: navigate back to entrance and re-enter.

**Full Wipe (both die):**

1. Both mages transition to `DEAD` state.
2. Both navigate (as ghosts) to their respective corpse positions.
3. Whichever mage gets to their corpse first resurrects, waits at entrance.
4. Both must be outside instance to reset (death exits the instance automatically in TBC if no living party member).
5. After both alive and outside: enter `RESETTING` state normally.
6. **Special case:** If corpses are inside the instance, mages' ghosts are inside the instance. Navigate ghost to the instance exit (use `Profile.exit_position` or generic world exit portal). Once outside, resurrect.

**Ghost Navigation:**
- NavAdapter `move_to` works for ghost movement (same navmesh, different Z offset sometimes).
- If ghost gets stuck: use `core.input.release_spirit()` to re-release (pushes to nearest graveyard), then navigate from graveyard to corpse.

### 8.2 Instance Lockout Management

**Budget:** TBC allows 5 instances per hour. We trigger a wait state at 4 resets (keep 1 in reserve).

**Detection:** The coord server tracks resets. After a reset is recorded, the coord server checks:
- `reset_count >= 4` → `near_limit: true` — both clients get a warning in next heartbeat
- `reset_count >= 5` → `must_wait: true` + `wait_remaining_secs: N`

**Wait state behavior:**
1. Both mages navigate to the Stratholme SE entrance area (they're already there post-reset).
2. Both mages sit and drink (if mana < 95%).
3. Both mages re-cast Ice Armor if missing.
4. Both mages conjure water/food if needed.
5. Loop until `lockout.wait_remaining_secs <= 0`.
6. The coord server's lockout window is based on `Instant` — it reports remaining seconds until the hour window expires.
7. After waiting, both resume from `BUFFING`.

**Lockout window tracking on server:**
```rust
// In lockout.rs
fn record_reset(state: &mut SessionState) -> LockoutResponse {
    let now = Instant::now();
    if let Some(window_start) = state.lockout.window_start {
        if now.duration_since(window_start).as_secs() >= 3600 {
            // Window expired, reset count
            state.lockout.reset_count = 0;
            state.lockout.window_start = Some(now);
        }
    } else {
        state.lockout.window_start = Some(now);
    }
    state.lockout.reset_count += 1;
    let near_limit = state.lockout.reset_count >= 4;
    let must_wait = state.lockout.reset_count >= 5;
    let wait_secs = if must_wait {
        3600u64.saturating_sub(now.duration_since(state.lockout.window_start.unwrap()).as_secs())
    } else { 0 };
    LockoutResponse { reset_count: state.lockout.reset_count, near_limit, must_wait, wait_remaining_secs: wait_secs }
}
```

### 8.3 Inventory Overflow Handling

**Detection (runs every heartbeat tick):**
```lua
local function count_free_bag_slots()
    local free = 0
    for bag_id = 0, 4 do
        local items = core.inventory.get_items_in_bag(bag_id)
        if items then
            local slots = core.inventory.get_num_bag_slots(bag_id)
            if slots then free = free + (slots - #items) end
        end
    end
    return free
end

local bags_full = count_free_bag_slots() < Profile.bags_full_threshold
bb:set("duo.bags_full_local", bags_full)
```

**Flow:**
1. If `bags_full_local == true`: call `CoordClient:request_vendor_break()`.
2. Server sets `vendor_break_active: true`. Both clients see this on next heartbeat.
3. Even if only one mage's bags are full, **both** mages vendor (they travel together).
4. Current pull is completed if already in `FARM_AOE_BOTH` or `FARM_LOOTING`. Do not abort mid-combat.
5. After `loot_complete` barrier: check `vendor_break_active`. If true, exit farm loop and enter `TRAVEL_TO_VENDOR`.
6. If bags fill up while at safe_position (not yet pulling): abort pull, exit immediately.

**Sell logic:**
- Sell items by quality: sell all grey items, sell white items if `grind_vendor_sell_quality >= 1`.
- Never sell: conjured water, conjured food, Key to the City (item 12382), hearthstone (6948).
- Use `core.game_ui.get_vendor_item_count()` to scan — but actually selling requires iterating bags and calling sell interaction. Use `core.input.interact_with_object(vendor)` to open vendor, then iterate bag items and sell by quality threshold.

### 8.4 Disconnection / Desync Recovery

**Scenario: One client loses connectivity to coord server (but game is still running):**

1. `CoordClient._pending_request` never resolves for 2 poll intervals (600ms).
2. Client marks `duo.coord_connected = false`.
3. Client enters `PAUSED` state (stops all actions).
4. Client continues retrying coord server connection every 2 seconds.
5. On reconnect: call `GET /api/v1/heartbeat` — server returns current session state.
6. Client re-syncs from the session state: sets `pull_index`, `puller_id`, reads `session.phase`.
7. Client exits `PAUSED` and re-enters the appropriate state based on synced data.
8. If client missed multiple full pulls while disconnected: the server's `pull_index` is ahead — client fast-joins at the current pull_index.

**Scenario: Partner WoW client crashes:**

1. Coord server detects heartbeat timeout (5s without heartbeat).
2. Partner marked as `connected: false, phase: Offline`.
3. Active client's next heartbeat response includes `partner.connected: false`.
4. Active client: complete current pull if in combat (do not abandon mobs).
5. After pull complete + loot: active client transitions to `SOLO_MODE`.
6. In `SOLO_MODE`: skip all sync barriers, skip "needs partner" checks, continue farming solo.
7. Solo farming: skip the pull phase (don't pull — too dangerous alone), instead: exit → reset → vendor if needed → wait for partner reconnect.
8. When partner reconnects: coord server sees both connected → clears solo mode → resync.

**Stale State Detection:**

The client validates coherence on reconnect:
- If `duo.in_instance` (local) but `session.phase = vendoring` → something is very wrong → enter `ERROR` state → alert user.
- If `duo.pull_index` (local) differs from `session.pull_index` by > 2 → re-sync to server pull_index.

### 8.5 Stuck Detection and Recovery

**Nav stuck detection:**
```lua
-- In DuoNav.lua
local nav_state, progress = nav_adapter:poll()
if nav_state == "stuck" then
    -- Record stuck position
    local stuck_count = bb:get("duo.nav_stuck_count", 0) + 1
    bb:set("duo.nav_stuck_count", stuck_count)
    nav_adapter:stop("duo_stuck_" .. stuck_count)
    if stuck_count >= 3 then
        -- Three consecutive stucks at same phase → escalate
        event_bus:publish("duo:stuck_escalation", { phase = current_phase })
    else
        -- Retry navigation with a random lateral offset (jitter position)
        local offset_pos = apply_lateral_jitter(target_pos, 2.0)
        nav_adapter:move_to(offset_pos)
    end
end
```

**Stuck during pull run:**
- If puller is stuck while running pull path: abandon pull, cast Blizzard on current position, enter defensive mode (Ice Block), enter `FARM_ABORT_PULL`.
- If mobs are on puller while stuck: prioritize Ice Block → sync with support via `ice_block_up` barrier.

**Gate interaction stuck:**
- If gate interact fails 3 times: try moving 2 yards closer, retry.
- If still fails after 5 attempts: check if inside instance already (maybe gate was already open) → proceed.

### 8.6 Unexpected Combat (Adds / Patrol Aggro)

**Detection:**
```lua
local function check_unexpected_adds(profile, bb)
    local player = bb:get("player.object")
    local pos = bb:get("player.position")
    if not pos then return end
    local enemies = unit_helper:get_enemy_list_around(pos, 30, true, false)
    for _, mob in ipairs(enemies) do
        if not is_in_current_pull(mob, bb) and mob:is_in_combat() then
            return true  -- unexpected add
        end
    end
    return false
end
```

**Response:**
1. If puller is in pull run phase and gets unexpected adds: immediately abort pull, cast Ice Block.
2. Signal support via `ice_block_up` barrier (emergency).
3. Support opens Blizzard on largest cluster.
4. After pack dead: enter `FARM_ABORT_PULL`, retry pull from beginning.

---

## 9. UI/UX Design

### 9.1 Window Configuration

```lua
-- DuoWindow.lua initialization
local _ui = SentinelUI.new({
    id = "sentinel_duo_control",
    title = "SentinelDuo",
    default_x = 560,
    default_y = 80,
    default_w = 900,
    default_h = 720,
    theme = "sentinel",
    render_layer = 1,
})
```

### 9.2 Menu Tree (PS Menu System)

The PS menu callback registers a `core.menu.tree_node` labeled "SentinelDuo" with a single "Open UI" button. All configuration is in the tabbed window.

### 9.3 Tab Structure

#### Tab 1: Dashboard

Rendered via `custom_render` tab type (full manual render). Elements:

**Header bar (always visible):**
- Bot status indicator: green = running, yellow = paused, red = error, grey = idle
- `[START]` / `[STOP]` / `[PAUSE]` buttons (via `core.menu.button`)
- `[FORCE VENDOR]` button — triggers `request_vendor_break()` immediately
- `[EMERGENCY STOP]` button — stops all actions, stops nav, clears state

**Mage A Panel (left half):**
```
╔══════════════════════════════╗
║  Mage A                [YOU] ║
║  Phase: AoE (Both)           ║
║  HP: ████████░░ 78%          ║
║  MP: ██████░░░░ 62%          ║
║  Bags: 8/80 free             ║
╚══════════════════════════════╝
```

**Mage B Panel (right half):** Same layout. If disconnected: grey panel with "Offline" label.

**Session Stats bar:**
```
Pull #4/6 | Puller: Mage B | Resets: 2/5 | Runs: 7 | Gold: 45.3g | GPH: 312g/hr
```

**Lockout alert banner (conditional, shown when near_limit):**
```
⚠ LOCKOUT: 4/5 resets used. Pausing after this run.
```

Implementation note: Use `core.graphics.text_2d` for labels and `core.graphics.rect_2d_filled` for HP/MP bars. Call within `on_render_callback`.

#### Tab 2: Coordination

- Coord server URL display (read-only)
- Connection status indicator (connected/disconnected/error) with last ping time
- Partner heartbeat: "Last seen: 0.3s ago"
- Current session phase
- Barrier status: table showing all named barriers and their ready states
- `[RESET SESSION]` button — calls `GET /api/v1/admin/reset`

#### Tab 3: Statistics

Rolling session stats:
- Runs completed
- Total gold earned (copper → g/s/c display)
- Gold per hour (computed as `(gold_earned_copper / elapsed_seconds) * 3600 / 10000`)
- Average run time
- Deaths this session
- Vendor trips
- Items looted count

**Reset stats button**: Clears session counters.

#### Tab 4: Profile Config

- Dungeon selection: dropdown of available profiles in `profiles/` directory
- Pull route visualization toggle
- Timing overrides: sliders for key timing values (ice_block_cancel_delay_ms, etc.)
- Min mana/HP to pull: sliders
- Bags full threshold: slider (1-10 free slots)
- `[RELOAD PROFILE]` button

#### Tab 5: Debug

View selector (slider 1-3):
1. **Blackboard dump**: key-value view of all `duo.*` blackboard keys
2. **State trace**: last 20 state transitions with timestamps
3. **Coord log**: last 20 HTTP requests/responses (URL + status code + response snippet)

### 9.4 Debug 3D Overlay

Rendered via `core.register_on_render_callback`:

```lua
-- Toggle via duo.show_overlay blackboard key
if not bb:get("duo.show_overlay") then return end

local profile = get_current_profile()
if not profile then return end

-- Draw pull paths (blue lines)
for _, pull in ipairs(profile.pulls) do
    for i = 1, #pull.pull_path - 1 do
        core.graphics.line_3d(pull.pull_path[i], pull.pull_path[i+1],
            {r=0.3, g=0.6, b=1.0, a=0.8}, 2.0)
    end
end

-- Draw Blizzard AoE positions (purple circles)
for _, pull in ipairs(profile.pulls) do
    core.graphics.circle_3d(pull.blizzard_center, 8.0,
        {r=0.7, g=0.3, b=1.0, a=0.6}, 2.0)
end

-- Draw safe positions (green circles)
for _, pull in ipairs(profile.pulls) do
    core.graphics.circle_3d(pull.safe_position, 2.0,
        {r=0.2, g=0.9, b=0.2, a=0.8}, 2.0)
end

-- Draw mob count at Ice Block position (text)
local pack_count = bb:get("duo.mob_count_in_pack", 0)
local ib_pos = profile.pulls[current_pull_idx + 1]
if ib_pos then
    core.graphics.text_3d(
        string.format("Mobs: %d", pack_count),
        ib_pos.ice_block_position, 14, {r=1,g=1,b=0,a=1}, true)
end

-- Draw state labels above player positions
-- (w2s both mage positions via their last-known coords from blackboard)
```

### 9.5 Controls State Flow

```
IDLE → (user clicks START) → INIT → FARMING
FARMING → (user clicks PAUSE) → PAUSED
PAUSED → (user clicks RESUME) → previous_state
FARMING → (user clicks STOP) → IDLE (stops nav, clears all state)
FARMING → (user clicks FORCE VENDOR) → sets vendor_break_active → EXITING (vendor)
ANY STATE → (user clicks EMERGENCY STOP) → IDLE (immediate, no cleanup)
```

---

## 10. Debug & Observability

### 10.1 Logging Strategy

All log calls wrapped in `pcall`:
```lua
local function log(msg)
    pcall(core.log, "[DuoFarm] " .. tostring(msg))
end
local function log_err(msg)
    pcall(core.log_error, "[DuoFarm] ERROR: " .. tostring(msg))
end
```

**Log levels (encoded in prefix):**
- `[DuoFarm]` — normal operational messages
- `[DuoFarm] WARN:` — unusual conditions, not fatal
- `[DuoFarm] ERROR:` — errors requiring attention
- `[DuoFarm] STATE:` — state transitions (always logged)
- `[DuoFarm] COORD:` — coordination server messages
- `[DuoFarm] COMBAT:` — combat decisions

### 10.2 State Transition Logging

Every FSM state transition logs:
```lua
log(string.format("STATE: %s → %s  [pull=%d, role=%s, hp=%.0f%%, mp=%.0f%%]",
    old_state, new_state, pull_index, my_role,
    hp_pct * 100, mp_pct * 100))
```

Store last 100 state transitions in a circular buffer in the blackboard for the debug tab.

### 10.3 Performance Metrics

Track per-run timing:
- `run_start_ms` → `loot_complete_ms` = run duration
- `pull_start_ms[i]` → `all_mobs_dead_ms[i]` = time per pull
- `looting_start_ms` → `loot_complete_ms` = loot duration
- `travel_start_ms` → `back_at_entrance_ms` = vendor trip duration

Compute rolling 3-run average for GPH display.

### 10.4 Coord Server Logging

The Rust server uses `tracing` at INFO level for all barrier transitions, heartbeat misses, and lockout changes. Use structured logging:
```rust
tracing::info!(
    client_id = %client_id,
    phase = ?new_phase,
    pull_index = session.pull_index,
    "heartbeat received"
);
```

---

## 11. Anti-Detection Considerations

### 11.1 Timing Jitter

All timing constants have an applied jitter range. Implement via a `jitter(base_ms, pct)` helper:

```lua
local function jitter(base_ms, pct)
    pct = pct or 0.15  -- 15% default variance
    local variance = base_ms * pct
    return base_ms + math.random() * variance * 2 - variance
end
```

Apply to:
- `pull_delay_ms` → `jitter(500, 0.2)` = 400-600ms
- `between_pulls_ms` → `jitter(1500, 0.3)` = 1050-1950ms
- `loot_settle_ms` → `jitter(2000, 0.2)` = 1600-2400ms
- `frost_nova_after_ib_cancel_ms` → `jitter(200, 0.5)` = 100-300ms
- Spell re-cast timing: ±50-150ms random offset on all queued spells

### 11.2 Movement Humanization

- Use NavAdapter `plan_route` rather than raw `move_to` where possible (smoother paths via Catmull-Rom spline)
- Add random lateral displacement (±1-3 yards) to pull path waypoints at runtime: each pull path point has jitter applied once per run, not per pull
- Avoid perfectly straight-line pathing by using the navserver's `path-random` endpoint for long travel routes

### 11.3 Input Rate Limiting

- Spell queue priority 1 for all rotation spells (per PS docs recommendation)
- Never call `core.input.cast_*` directly in tight loops — always via spell_queue or with a `last_cast_ms` guard ensuring minimum 100ms between raw cast attempts
- Loot: add 150-350ms random delay between each `loot_item(i)` call
- Vendor interaction: add 200-500ms delay between sell actions

### 11.4 Coordination Server Polling Rate

- Default: 300ms poll interval
- When in barriers (waiting for partner): increase to 500ms (less urgency, less traffic)
- The server is localhost, so latency is negligible; the concern is packet volume to the game server, not the coord server

### 11.5 Session Duration Caps

- Recommend max session duration of 4-6 hours before a mandatory break
- Implement `session_max_runtime_ms` config key (default 14400000ms = 4 hours)
- When exceeded: complete current pull → vendor → stop + alert user

---

## 12. Future Extensibility Notes

### 12.1 Adding New Dungeon Profiles

Creating a new profile for a different dungeon:
1. Copy `profiles/stratholme_se.lua` as a template
2. Capture coordinates in-game using the SentinelDuoFarm coordinate capture mode (profile_capture toggle in UI):
   - Walk to each pull path waypoint and press a keybind to record position
   - Walk to safe, blizzard, ice_block, and reposition positions and record them
   - The UI writes them directly to a new profile file
3. Set `gate_object_id = 0` if no key is required
4. Set `exit_use_death = false` if the dungeon has a walkable exit
5. Adjust `timing` values based on corridor width (wider rooms need longer Blizzard repositioning time)
6. Set `mob_ids_avoid` to prevent accidental elite tagging

**Profile naming convention:** `{dungeon_shortname}_{variant}.lua`, e.g., `dm_north_v1.lua`, `strat_se_v2.lua`

### 12.2 Expanding Beyond Duo Frost Mage

The architecture supports expansion without redesign:

- **Different classes:** Replace `AoeRotation.lua` and `PullExecutor.lua` with class-specific implementations. The Farm sub-FSM's pull/IB/Nova/Blizzard phases are profile-configurable: a `profile.pull_strategy` field could switch between "frost_mage_aoe", "warlock_seed", etc.

- **Trio/Group farming:** The coord server's `max_clients = 2` is a config value. Barriers are generic named barriers — increasing to 3 clients requires only changing the barrier ready check from "mage_a AND mage_b" to a quorum check.

- **Multiple dungeons per session (route farming):** Add a `session_profile_list` config that cycles through multiple profiles per session. The master FSM's `RESETTING` state could load the next profile instead of repeating.

- **Solo mode:** The `SOLO_MODE` degraded state (§8.4) is already designed. A full solo implementation would remove the pull/IB/Nova/Blizzard timing handoffs entirely.

---

## Appendix A: Complete Spell ID Reference

| Spell Name | Rank | Spell ID | Notes |
|---|---|---|---|
| Blizzard | 1-7 | 10185-10190, 27085 | AoE; 27085 is TBC max |
| Frost Nova | 1-5 | 122, 865, 6131, 10230, 27088 | 27088 TBC max |
| Ice Block | 1 | 45438 | 10s immunity |
| Cold Snap | 1 | 11958 | Resets IB, Nova, Barrier CDs |
| Ice Barrier | 4-7 | 11426, 13031-13033 | 13033 TBC max |
| Counterspell | 1 | 2139 | 8s school lockout |
| Frostbolt | 1 | 116 | R1 for pull tagging (cheap) |
| Frostbolt | 12 | 27071 | TBC max rank |
| Blink | 1 | 1953 | — |
| Evocation | 1 | 12051 | 8s channel, 100% mana |
| Cone of Cold | 6 | 27087 | TBC max |
| Ice Armor | 4 | 10220 | TBC max |
| Dampen Magic | 6 | 33944 | TBC max; optional on pulls |
| Mana Shield | 7 | 27131 | TBC max |
| Conjure Water | 8 | 27090 | TBC max |
| Conjure Food | 7 | 28612 | TBC max |
| Hearthstone | — | item 6948 | 60min CD |
| Key to the City | — | item 12382 | Stratholme SE gate key |

## Appendix B: Key Game Constants (TBC)

| Mechanic | Value |
|---|---|
| GCD (base) | 1.5s |
| Ice Block duration | 10s |
| Frost Nova duration | 8s |
| Frost Nova cooldown | 25s |
| Blizzard channel | 8s (8 ticks of 1s) |
| Cold Snap cooldown | 10 min |
| Ice Block cooldown | 5 min |
| Ice Barrier cooldown | 30s |
| Hearthstone cooldown | 60 min |
| Instance lockout limit | 5 per hour |
| Aggro range (typical undead, Strath SE) | 10-15 yards |
| Blizzard tick to generate aggro | ~1-2 ticks (~2s) |

## Appendix C: Stratholme SE Quick Reference

| Location | vec3 (approximate) | Notes |
|---|---|---|
| Outdoor entrance gate | {3358, -3378, 133} | Gate object 183396; key item 12382 |
| Instance portal | {3355, -3381, 133} | Enter to go inside |
| Inside spawn point | {2905, -1225, 101} | After entering |
| Pull 1 safe pos | {2912, -1218, 101} | Support stands here |
| Pull 1 Blizzard center | {2940, -1195, 101} | — |
| Pull 2 safe pos | {2930, -1200, 101} | — |
| Pull 2 Blizzard center | {2960, -1155, 101} | — |
| Pull 3 Blizzard center | {2998, -1128, 101} | Deep corridor |
| Light's Hope Chapel | {3439, -1364, 56} | Flight destination |

**Note:** All coordinates are approximate and must be verified in-game using the profile capture tool before first use. Stratholme's internal geometry is fixed but PS coordinate precision requires in-game sampling.

---

*End of SentinelDuo Design Document v1.0*
