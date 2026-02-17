# Sentinel System Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix confirmed bugs across the Lua client/gather stack, harden the Rust pathfinding server, improve client reliability, and reorganize shared config.

**Architecture:** 4 phases — (A) shared config extraction, (B) 6 Lua bug fixes in SentinelNavClient, (C) 7 Rust server improvements in SentinelNavServer, (D) 7 client reliability improvements across SentinelNavClient and SentinelGather. Each phase commits independently.

**Tech Stack:** Lua (Sylvannas API), Rust (axum, tokio, moka, parking_lot, dashmap)

---

## Phase A: Shared Config & Folder Structure

### Task 1: Create shared server config module

**Files:**
- Create: `config/server.lua`

**Step 1: Create config directory and server config file**

```lua
-- config/server.lua
-- Shared server configuration consumed by SentinelNavClient and other projects.
-- Single source of truth for SentinelNavServer connection details.

local ServerConfig = {
    --- Base URL for SentinelNavServer HTTP API
    base_url = "http://127.0.0.1:47110",

    --- Maximum HTTP request retries before marking as failed
    max_retries = 3,

    --- Health check interval in seconds (0 = disabled)
    health_check_interval = 30,
}

return ServerConfig
```

**Step 2: Commit**

```bash
git add config/server.lua
git commit -m "feat: add shared server config module"
```

---

### Task 2: Wire Navigation.lua to use shared config

**Files:**
- Modify: `SentinelNavClient/core/Navigation.lua:189-198`

**Step 1: Add require for shared config and use it as default**

Replace the Navigation:new constructor default:

```lua
-- At the top of Navigation.lua, after existing requires:
local ok_cfg, ServerConfig = pcall(require, "config/server")
if not ok_cfg then ServerConfig = { base_url = "http://127.0.0.1:47110", max_retries = 3 } end

-- Then in Navigation:new (line 189-198):
function Navigation:new(config)
    config = config or {}
    local o = setmetatable({}, Navigation)
    o._base_url = config.base_url or ServerConfig.base_url
    o._max_retries = config.max_retries or ServerConfig.max_retries
    o._is_connected = false
    o._consecutive_failures = 0
    o._last_success_time = 0
    return o
end
```

**Step 2: Verify the old hardcoded IP is removed**

Search for the old IP — should return zero results:
```bash
grep -r "78.31.71.163" SentinelNavClient/
```
Expected: no matches

**Step 3: Commit**

```bash
git add SentinelNavClient/core/Navigation.lua
git commit -m "fix(sentinel-nav-client): use shared server config instead of hardcoded IP"
```

---

### Task 3: Register unload callback

**Files:**
- Modify: `SentinelNavClient/main.lua:136-138`

**Step 1: Register the on_unload callback with the engine**

After line 136 (`end` closing on_unload), add the registration:

```lua
local function on_unload()
    SentinelNavClient:destroy()
    _G.SentinelNavClient = nil
    _is_loaded = false
    core.log("[SentinelNavClient] Unloaded")
end

-- Register unload so state is cleaned up on plugin reload
core.register_on_unload_callback(on_unload)
```

**Step 2: Commit**

```bash
git add SentinelNavClient/main.lua
git commit -m "fix(sentinel-nav-client): register on_unload callback to prevent state leak"
```

---

## Phase B: Tier 1 Bug Fixes (Lua)

### Task 4: Fix pending_move dropping navmesh flag

**Files:**
- Modify: `SentinelNavClient/core/Movement.lua:688-699`

**Step 1: Preserve original opts when deferring during casting**

The bug is at line 692-695 in `_start_movement()` where `use_navmesh = false` is hardcoded. Fix:

```lua
    -- Re-defer if still casting
    if player:is_casting_spell() or player:is_channelling_spell() then
        self:_verbose("Player still casting, re-deferring")
        self._pending_move = {
            target = self._destination,
            callback = self._callback,
            opts = { use_navmesh = true },  -- preserve navmesh intent
        }
        -- Store waypoints so deferred path uses them directly
        self._current_path = waypoints
        return
    end
```

**Step 2: Also fix the initial deferral in move_to**

At line 521-527, the initial deferral already passes the original `opts` correctly:
```lua
self._pending_move = { target = target, callback = callback, opts = opts }
```
This is correct — only `_start_movement`'s re-deferral was broken.

**Step 3: Commit**

```bash
git add SentinelNavClient/core/Movement.lua
git commit -m "fix(sentinel-nav-client): preserve navmesh flag when deferring move during casting"
```

---

### Task 5: Guard unstuck recovery from casting

**Files:**
- Modify: `SentinelNavClient/core/Movement.lua:832-855`

**Step 1: Add casting guard at the top of _handle_stuck**

```lua
---Apply recovery strategy based on stuck count
function Movement:_handle_stuck()
    -- Don't attempt recovery while casting (would desync state)
    local player = core.object_manager.get_local_player()
    if player and (player:is_casting_spell() or player:is_channelling_spell()) then
        self:_verbose("Unstuck: deferring — player is casting")
        return
    end

    if self._stuck_count >= self._config.max_stuck_attempts then
        core.log_error("[Movement] Max stuck attempts reached, failing")
        self:_set_state(S_FAILED)
        if self._callback then
            self._callback(false, "Stuck — max attempts exceeded")
            self._callback = nil
        end
        return
    end

    if self._stuck_count == 1 then
        self:_unstuck_jump()
    elseif self._stuck_count == 2 then
        self:_unstuck_probe_and_repath()
    elseif self._stuck_count == 3 then
        self:_unstuck_strafe()
    elseif self._stuck_count == 4 then
        self:_unstuck_backward()
    else
        self:_unstuck_zone_and_repath()
    end
end
```

**Step 2: Commit**

```bash
git add SentinelNavClient/core/Movement.lua
git commit -m "fix(sentinel-nav-client): guard unstuck recovery from executing during casting"
```

---

### Task 6: Add soft repath safety guard

**Files:**
- Modify: `SentinelNavClient/core/Movement.lua:1176-1189`

**Step 1: Track repath-in-flight and stop movement if path runs out**

Add a `_soft_repath_pending` flag and modify `_soft_repath`:

```lua
---Request a fresh path without stopping movement (used by path validity check).
---The character keeps walking the current path while the new one is fetched.
function Movement:_soft_repath()
    if not self._destination then return end
    if self._soft_repath_pending then return end  -- already in flight
    if self._route_data then
        self:_unstuck_repath()
        return
    end
    if self._partial_path then
        self:_unstuck_repath()
        return
    end

    self._soft_repath_pending = true
    self:_verbose("Soft repath (no stop)")
```

Then in the callback that receives the new path (the on_path handler inside the repath), clear the flag:

```lua
    -- At the end of the repath success callback:
    self._soft_repath_pending = false
```

And in the update loop, add a guard: if `_soft_repath_pending` and we've consumed all waypoints, stop:

In `Movement:update()`, after the movement completion check, add:

```lua
    -- Safety: if soft repath is pending and we've run out of path, stop and wait
    if self._soft_repath_pending and simple_movement:is_finished() then
        self:_verbose("Path exhausted while soft repath in-flight, stopping to wait")
        simple_movement:stop()
    end
```

**Step 2: Initialize the flag in move_to (line 510 area)**

```lua
    self._soft_repath_pending = false
```

**Step 3: Commit**

```bash
git add SentinelNavClient/core/Movement.lua
git commit -m "fix(sentinel-nav-client): stop movement when path exhausted during soft repath"
```

---

### Task 7: Fix obstacle probe direction

**Files:**
- Modify: `SentinelNavClient/core/Obstacle.lua:85-89`

**Step 1: Verify and fix rotation math**

The current code for the "right" direction at line 88:
```lua
{ dx = dx * cos_s + dy * sin_s, dy = -dx * sin_s + dy * cos_s }, -- right
```

Standard 2D rotation by angle θ:
- Counterclockwise (left): `(x*cos - y*sin, x*sin + y*cos)`
- Clockwise (right): `(x*cos + y*sin, -x*sin + y*cos)`

The current code has:
- Line 87 (left): `dx*cos_s - dy*sin_s, dx*sin_s + dy*cos_s` — counterclockwise, correct
- Line 88 (right): `dx*cos_s + dy*sin_s, -dx*sin_s + dy*cos_s` — clockwise, correct

The rotation math is actually **correct**. The explore agent's concern was a false positive. No change needed.

**Step 2: Commit (skip — no change)**

---

## Phase C: Tier 2 Server Hardening (Rust)

### Task 8: Replace PathCache with moka LRU

**Files:**
- Modify: `SentinelNavServer/Cargo.toml` (add moka dependency)
- Rewrite: `SentinelNavServer/src/cache.rs`

**Step 1: Add moka dependency**

In `SentinelNavServer/Cargo.toml` under `[dependencies]`, add:
```toml
moka = { version = "0.12", features = ["future"] }
```

**Step 2: Rewrite cache.rs with moka**

```rust
//! Path cache with spatial quantization for fast repeated lookups.
//!
//! Uses moka's concurrent LRU cache keyed by (map_id, quantized_start, quantized_end)
//! so that similar start/end positions within a 5-yard grid cell hit the cache.

use detour::types::Vec3;
use moka::sync::Cache;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

/// Grid cell size in yards for spatial quantization.
const CELL_SIZE: f32 = 5.0;

/// Default cache TTL.
const DEFAULT_TTL: Duration = Duration::from_secs(60);

/// Default max entries.
const DEFAULT_MAX_ENTRIES: u64 = 1000;

/// A cached path entry.
#[derive(Debug, Clone)]
pub struct CachedPath {
    pub waypoints: Vec<Vec3>,
    pub distance: f32,
    pub partial: bool,
}

/// Cache key with spatial quantization.
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
struct PathCacheKey {
    map_id: u32,
    start_cell: (i32, i32, i32),
    end_cell: (i32, i32, i32),
}

/// Quantize a coordinate to a grid cell index.
fn quantize(v: f32) -> i32 {
    (v / CELL_SIZE).floor() as i32
}

/// Quantize a Vec3 to grid cell indices.
fn quantize_vec3(v: &Vec3) -> (i32, i32, i32) {
    (quantize(v.x), quantize(v.y), quantize(v.z))
}

/// Thread-safe path cache using moka LRU.
pub struct PathCache {
    cache: Cache<PathCacheKey, CachedPath>,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl PathCache {
    /// Create a new path cache with default settings.
    pub fn new() -> Self {
        Self {
            cache: Cache::builder()
                .max_capacity(DEFAULT_MAX_ENTRIES)
                .time_to_live(DEFAULT_TTL)
                .build(),
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        }
    }

    /// Look up a cached path.
    pub fn get(&self, map_id: u32, start: &Vec3, end: &Vec3) -> Option<CachedPath> {
        let key = PathCacheKey {
            map_id,
            start_cell: quantize_vec3(start),
            end_cell: quantize_vec3(end),
        };

        match self.cache.get(&key) {
            Some(entry) => {
                self.hits.fetch_add(1, Ordering::Relaxed);
                Some(entry)
            }
            None => {
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    /// Insert a path into the cache.
    pub fn insert(&self, map_id: u32, start: &Vec3, end: &Vec3, path: CachedPath) {
        let key = PathCacheKey {
            map_id,
            start_cell: quantize_vec3(start),
            end_cell: quantize_vec3(end),
        };
        self.cache.insert(key, path);
    }

    /// Get the number of cached entries (for health endpoint).
    pub fn len(&self) -> usize {
        self.cache.entry_count() as usize
    }

    /// Check if cache is empty.
    pub fn is_empty(&self) -> bool {
        self.cache.entry_count() == 0
    }

    /// Get cache hit count.
    pub fn hit_count(&self) -> u64 {
        self.hits.load(Ordering::Relaxed)
    }

    /// Get cache miss count.
    pub fn miss_count(&self) -> u64 {
        self.misses.load(Ordering::Relaxed)
    }
}

impl Default for PathCache {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quantize() {
        assert_eq!(quantize(0.0), 0);
        assert_eq!(quantize(4.9), 0);
        assert_eq!(quantize(5.0), 1);
        assert_eq!(quantize(-1.0), -1);
        assert_eq!(quantize(-5.0), -1);
        assert_eq!(quantize(-5.1), -2);
    }

    #[test]
    fn test_cache_hit_same_cell() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Same cell — should hit
        let nearby_start = Vec3::new(2.0, 3.0, 4.0);
        let nearby_end = Vec3::new(101.0, 201.0, 51.0);
        assert!(cache.get(0, &nearby_start, &nearby_end).is_some());
        assert_eq!(cache.hit_count(), 1);
        assert_eq!(cache.miss_count(), 0);
    }

    #[test]
    fn test_cache_miss_different_cell() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Different cell — should miss
        let far_start = Vec3::new(50.0, 50.0, 3.0);
        assert!(cache.get(0, &far_start, &end).is_none());
        assert_eq!(cache.miss_count(), 1);
    }

    #[test]
    fn test_cache_miss_different_map() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Different map — should miss
        assert!(cache.get(1, &start, &end).is_none());
    }

    #[test]
    fn test_cache_metrics() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        // Miss
        cache.get(0, &start, &end);
        assert_eq!(cache.hit_count(), 0);
        assert_eq!(cache.miss_count(), 1);

        // Insert + hit
        cache.insert(0, &start, &end, CachedPath {
            waypoints: vec![start, end],
            distance: 100.0,
            partial: false,
        });
        cache.get(0, &start, &end);
        assert_eq!(cache.hit_count(), 1);
        assert_eq!(cache.miss_count(), 1);
    }
}
```

**Step 3: Update callers — remove `created_at` from CachedPath construction**

In `SentinelNavServer/src/pipeline.rs` and any route handler that creates `CachedPath`, remove the `created_at: Instant::now()` field (moka handles TTL internally).

Search for all `CachedPath {` occurrences and remove `created_at`:
```bash
grep -rn "CachedPath {" SentinelNavServer/src/
```

**Step 4: Run tests**

```bash
cd SentinelNavServer && cargo test
```
Expected: all tests pass

**Step 5: Commit**

```bash
git add SentinelNavServer/Cargo.toml SentinelNavServer/Cargo.lock SentinelNavServer/src/cache.rs SentinelNavServer/src/pipeline.rs
git commit -m "refactor(sentinel-nav-server): replace DashMap cache with moka LRU"
```

---

### Task 9: Upgrade avoidance_mutex to RwLock

**Files:**
- Modify: `SentinelNavServer/crates/detour/src/pool.rs:52,91-98,161-168`

**Step 1: Replace Mutex<()> with RwLock<()>**

```rust
// In pool.rs, change the import:
use parking_lot::{Mutex, RwLock};

// Change the field (line 52):
    avoidance_lock: RwLock<()>,

// Change with_config (line 97):
            avoidance_lock: RwLock::new(()),

// Change avoidance_lock method (line 166-168):
    /// Acquire exclusive write access for avoidance-zone pathfinding.
    pub fn avoidance_lock(&self) -> parking_lot::RwLockWriteGuard<'_, ()> {
        self.avoidance_lock.write()
    }

    /// Acquire shared read access for normal pathfinding.
    /// This ensures avoidance mutations are not happening during the query.
    pub fn pathfind_lock(&self) -> parking_lot::RwLockReadGuard<'_, ()> {
        self.avoidance_lock.read()
    }
```

**Step 2: Add read lock acquisition in route handlers that pathfind**

In `SentinelNavServer/src/pipeline.rs`, at the start of `execute_pathfind` (or wherever the pool is used for normal pathfinding), acquire a read lock:

```rust
// Before the pathfinding query call:
let _pathfind_guard = pool.pathfind_lock();
```

In avoidance handlers (`src/routes/intelligence.rs` path-avoid handler), the existing `pool.avoidance_lock()` call now returns a write guard, which is correct.

**Step 3: Run tests**

```bash
cd SentinelNavServer && cargo test
```
Expected: all tests pass

**Step 4: Commit**

```bash
git add SentinelNavServer/crates/detour/src/pool.rs SentinelNavServer/src/pipeline.rs
git commit -m "fix(sentinel-nav-server): upgrade avoidance lock to RwLock for formal correctness"
```

---

### Task 10: Add loading deduplication in MmapManager

**Files:**
- Modify: `SentinelNavServer/crates/tc-mmap/src/manager.rs`

**Step 1: Add per-map loading locks**

```rust
// Add to MmapManager fields:
    loading_locks: DashMap<u32, Arc<parking_lot::Mutex<()>>>,

// In MmapManager::new(), add:
    loading_locks: DashMap::new(),

// In get_or_load_mesh(), replace the simple check with lock-then-check:
pub fn get_or_load_mesh(&self, map_id: u32) -> Result<Arc<NavMesh>, MmapError> {
    // Fast path: already loaded
    if let Some(mesh) = self.meshes.get(&map_id) {
        return Ok(mesh.clone());
    }

    // Get or create a per-map loading lock
    let lock = self.loading_locks
        .entry(map_id)
        .or_insert_with(|| Arc::new(parking_lot::Mutex::new(())))
        .clone();

    // Serialize loading for this specific map
    let _guard = lock.lock();

    // Re-check after acquiring lock (another thread may have loaded it)
    if let Some(mesh) = self.meshes.get(&map_id) {
        return Ok(mesh.clone());
    }

    // ... rest of loading logic unchanged ...
}
```

**Step 2: Run tests**

```bash
cd SentinelNavServer && cargo test -p tc-mmap
```
Expected: all tests pass

**Step 3: Commit**

```bash
git add SentinelNavServer/crates/tc-mmap/src/manager.rs
git commit -m "fix(sentinel-nav-server): prevent duplicate map loading with per-map locks"
```

---

### Task 11: Add backpressure with try_acquire

**Files:**
- Modify: `SentinelNavServer/src/error.rs` (add Overloaded variant)
- Modify: `SentinelNavServer/src/routes/path.rs` (and other route files)

**Step 1: Add Overloaded error variant**

In `error.rs`, add:
```rust
    /// Server overloaded — too many concurrent requests
    Overloaded,
```

And in the `IntoResponse` impl:
```rust
    AppError::Overloaded => (
        StatusCode::SERVICE_UNAVAILABLE,
        Json(json!({ "success": false, "error": "Server overloaded, try again later" })),
    ),
```

**Step 2: Create a helper function for semaphore acquisition**

In `state.rs` or a new helper, add:
```rust
impl AppState {
    /// Try to acquire a request permit, returning 503 if overloaded.
    pub fn try_acquire_permit(&self) -> Result<tokio::sync::OwnedSemaphorePermit, crate::error::AppError> {
        self.request_semaphore.clone().try_acquire_owned()
            .map_err(|_| crate::error::AppError::Overloaded)
    }
}
```

**Step 3: Replace semaphore usage in route handlers**

In each route handler that uses the semaphore, replace:
```rust
let _permit = state.request_semaphore.acquire().await.unwrap();
```
with:
```rust
let _permit = state.try_acquire_permit()?;
```

**Step 4: Run tests**

```bash
cd SentinelNavServer && cargo test
```

**Step 5: Commit**

```bash
git add SentinelNavServer/src/error.rs SentinelNavServer/src/state.rs SentinelNavServer/src/routes/
git commit -m "feat(sentinel-nav-server): return 503 when overloaded instead of queuing"
```

---

### Task 12: Add graceful shutdown

**Files:**
- Modify: `SentinelNavServer/src/main.rs`

**Step 1: Add tokio signal handling**

```rust
// In main(), replace the final serve call with:
    let listener = tokio::net::TcpListener::bind(addr).await?;

    tracing::info!("Listening on http://{}", addr);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    tracing::info!("Server shutdown complete");
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("Failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => tracing::info!("Received Ctrl+C, shutting down..."),
        _ = terminate => tracing::info!("Received SIGTERM, shutting down..."),
    }
}
```

**Step 2: Run build**

```bash
cd SentinelNavServer && cargo build --release
```

**Step 3: Commit**

```bash
git add SentinelNavServer/src/main.rs
git commit -m "feat(sentinel-nav-server): add graceful shutdown on Ctrl+C and SIGTERM"
```

---

### Task 13: Move pipeline hardcoded constants to config

**Files:**
- Modify: `SentinelNavServer/src/config.rs`
- Modify: `SentinelNavServer/src/pipeline.rs`
- Modify: `SentinelNavServer/config.toml`

**Step 1: Add pipeline config section**

In `config.rs`, add to `PathfindingConfig`:
```rust
    /// Tiered polygon search extents [tight, medium, wide] in yards.
    #[serde(default = "default_search_extents")]
    pub search_extents: [f32; 3],

    /// Max segment length before densification (yards).
    #[serde(default = "default_max_segment_length")]
    pub max_segment_length: f32,

    /// Island recovery retry count.
    #[serde(default = "default_island_retry_count")]
    pub island_retry_count: usize,

    /// Default area costs [ground, water, lava].
    #[serde(default = "default_area_costs")]
    pub default_area_costs: [f32; 3],
```

With defaults:
```rust
fn default_search_extents() -> [f32; 3] { [6.0, 10.0, 50.0] }
fn default_max_segment_length() -> f32 { 3.0 }
fn default_island_retry_count() -> usize { 8 }
fn default_area_costs() -> [f32; 3] { [1.0, 1.5, 100.0] }
```

**Step 2: Thread config through pipeline**

Pass the relevant config values into `execute_pathfind` and `PathfindOptions`. Use the config values instead of hardcoded constants in `pipeline.rs`.

**Step 3: Update config.toml with documented defaults**

```toml
[pathfinding]
default_smoothing = "none"
max_path_length = 2048
query_pool_size = 4
search_extents = [6.0, 10.0, 50.0]
max_segment_length = 3.0
island_retry_count = 8
default_area_costs = [1.0, 1.5, 100.0]
```

**Step 4: Run tests**

```bash
cd SentinelNavServer && cargo test
```

**Step 5: Commit**

```bash
git add SentinelNavServer/src/config.rs SentinelNavServer/src/pipeline.rs SentinelNavServer/config.toml
git commit -m "refactor(sentinel-nav-server): move pipeline constants to config.toml"
```

---

### Task 14: Add request metrics to health endpoint

**Files:**
- Modify: `SentinelNavServer/src/state.rs`
- Modify: `SentinelNavServer/src/routes/health.rs`

**Step 1: Add metrics to AppState**

```rust
use std::sync::atomic::{AtomicU64, Ordering};

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
}
```

Add `pub metrics: Arc<Metrics>` to `AppState` and initialize in `new()`.

**Step 2: Increment counters in route handlers**

Add `state.metrics.total_requests.fetch_add(1, Ordering::Relaxed)` at the start of pathfinding handlers, and increment `failed_requests` on error.

**Step 3: Expose in health endpoint**

Add to the health JSON response:
```rust
"metrics": {
    "total_requests": state.metrics.total_requests.load(Ordering::Relaxed),
    "failed_requests": state.metrics.failed_requests.load(Ordering::Relaxed),
    "cache_hits": state.path_cache.hit_count(),
    "cache_misses": state.path_cache.miss_count(),
}
```

**Step 4: Run tests**

```bash
cd SentinelNavServer && cargo test
```

**Step 5: Commit**

```bash
git add SentinelNavServer/src/state.rs SentinelNavServer/src/routes/health.rs SentinelNavServer/src/routes/path.rs
git commit -m "feat(sentinel-nav-server): add request metrics to health endpoint"
```

---

## Phase D: Tier 3 Client Reliability (Lua)

### Task 15: Add periodic server health check

**Files:**
- Modify: `SentinelNavClient/core/Navigation.lua`
- Modify: `SentinelNavClient/core/Facade.lua` (or wherever Facade:update is)

**Step 1: Add health_check_timer and auto-check in Navigation**

In `Navigation:new()`, add:
```lua
    o._health_check_interval = ServerConfig.health_check_interval or 30
    o._last_health_check = 0
```

Add a method:
```lua
---Periodic health check. Call from Facade:update().
function Navigation:check_health_if_needed()
    if self._health_check_interval <= 0 then return end
    local now = core.time()
    if now - self._last_health_check < self._health_check_interval then return end
    self._last_health_check = now

    self:health_check(function(ok, data, err)
        if not ok then
            if self._is_connected then
                core.log_warning("[NavClient] Server health check failed: " .. (err or "unknown"))
                self._is_connected = false
            end
        else
            if not self._is_connected then
                core.log("[NavClient] Server reconnected")
            end
            self._is_connected = true
        end
    end)
end
```

**Step 2: Call from Facade:update()**

In the Facade's update method, add:
```lua
    self.nav_client:check_health_if_needed()
```

**Step 3: Commit**

```bash
git add SentinelNavClient/core/Navigation.lua SentinelNavClient/core/Facade.lua
git commit -m "feat(sentinel-nav-client): add periodic server health check"
```

---

### Task 16: Add config validation in Movement

**Files:**
- Modify: `SentinelNavClient/core/Movement.lua:165-178`

**Step 1: Add type validation to update_config**

```lua
---Update config values at runtime (e.g., from UI settings)
---@param overrides table Key-value pairs to merge into config
function Movement:update_config(overrides)
    if not overrides then return end
    for k, v in pairs(overrides) do
        -- Only accept values matching the existing config's type
        local existing = self._config[k]
        if existing ~= nil then
            if type(v) == type(existing) then
                self._config[k] = v
            else
                core.log_warning("[Movement] Ignoring config override '"
                    .. k .. "': expected " .. type(existing) .. ", got " .. type(v))
            end
        end
    end
    if not self._config.dynamic_speed then
        simple_movement:set_threshold(self._config.waypoint_tolerance)
        simple_movement:set_final_threshold(self._config.final_tolerance)
    end
end
```

**Step 2: Commit**

```bash
git add SentinelNavClient/core/Movement.lua
git commit -m "fix(sentinel-nav-client): validate config override types in Movement"
```

---

### Task 17: Add approach timeout in BotManager

**Files:**
- Modify: `SentinelGather/core/BotManager.lua:551-579`

**Step 1: Verify existing implementation**

Reading BotManager.lua:551-579, there is already an approach timeout at line 564:
```lua
elseif core.time() - approach_start > Constants.OPERATIONAL.APPROACH_TIMEOUT then
```

This already handles the case where movement stops but we're in APPROACHING. However, it only triggers when `not movement:is_moving()`. Add a guard for when movement was **never started**:

```lua
function BotManager:_process_approaching()
    local movement = self._modules.Movement
    local ctx = self._state_machine:get_context()

    -- Track time in APPROACHING regardless of movement state
    if not ctx.data or not ctx.data.approach_entered_at then
        ctx.data = ctx.data or {}
        ctx.data.approach_entered_at = core.time()
    end

    -- Hard timeout: if we've been in APPROACHING for too long (even if movement is active)
    local hard_timeout = Constants.OPERATIONAL.APPROACH_TIMEOUT * 2.5  -- ~5s
    if core.time() - ctx.data.approach_entered_at > hard_timeout then
        if self._log then
            self._log:warn("Hard timeout in APPROACHING state, returning to TRAVELING")
        end
        local node = ctx.data and ctx.data.target_node
        local scanner = self._modules.NodeScanner
        if node and node.guid and scanner then
            scanner:blacklist_node(node.guid, "Approach hard timeout")
        end
        self._state_machine:transition(STATES.TRAVELING)
        return
    end

    -- Existing soft timeout when movement stops
    if movement and not movement:is_moving() then
        local approach_start = ctx.data.approach_start_time
        if not approach_start then
            ctx.data.approach_start_time = core.time()
        elseif core.time() - approach_start > Constants.OPERATIONAL.APPROACH_TIMEOUT then
            if self._log then
                self._log:warn("Stuck in APPROACHING state, returning to TRAVELING")
            end
            local node = ctx.data and ctx.data.target_node
            local scanner = self._modules.NodeScanner
            if node and node.guid and scanner then
                scanner:blacklist_node(node.guid, "Approach timeout")
            end
            self._state_machine:transition(STATES.TRAVELING)
        end
    end
end
```

**Step 2: Commit**

```bash
git add SentinelGather/core/BotManager.lua
git commit -m "fix(sentinel-gather): add hard timeout for APPROACHING state"
```

---

### Task 18: Waypoint loop wraparound

**Files:**
- Modify: `SentinelGather/modules/ProfileManager.lua`

**Step 1: Find the waypoint advancement logic and add wraparound**

In ProfileManager, after the last waypoint is reached and `loop` is true, reset the index:

```lua
-- In the method that advances to the next waypoint:
function ProfileManager:advance_waypoint()
    self._current_index = self._current_index + 1
    if self._current_index > #self._waypoints then
        if self._profile and self._profile.settings and self._profile.settings.loop then
            self._current_index = 1
            core.log("[ProfileManager] Route complete, looping back to start")
            -- Publish event for stats tracking
            if self._event_bus then
                self._event_bus:publish("ROUTE_COMPLETED", { loops = (self._loop_count or 0) + 1 })
            end
            self._loop_count = (self._loop_count or 0) + 1
        else
            -- No loop — signal route complete
            self._current_index = #self._waypoints  -- clamp to last
            return false  -- no more waypoints
        end
    end
    return true  -- more waypoints available
end
```

**Step 2: Commit**

```bash
git add SentinelGather/modules/ProfileManager.lua
git commit -m "fix(sentinel-gather): add waypoint loop wraparound on route completion"
```

---

### Task 19: Facade validation on access

**Files:**
- Modify: `SentinelGather/core/BotManager.lua:107-129`

**Step 1: Validate facade module references**

```lua
    if _G.SentinelNavClient and _G.SentinelNavClient.facade then
        local facade = _G.SentinelNavClient.facade
        -- Validate that all required modules exist on the facade
        if not facade.nav_client or not facade.movement or not facade.obstacle then
            self._nav_facade_available = false
            self._nav_facade_error = "SentinelNavClient facade is missing required modules"
            if self._log then
                self._log:error(self._nav_facade_error)
            end
            self._event_bus:publish(EVENTS.NAV_UNAVAILABLE, {
                error = self._nav_facade_error,
            })
        else
            self._nav_facade = facade
            self._modules.Navigation = facade.nav_client
            self._modules.Movement   = facade.movement
            self._modules.Obstacle   = facade.obstacle
            self._nav_facade_available = true
            if self._log then
                self._log:debug("Using SentinelNavClient shared facade")
            end
        end
    else
```

**Step 2: Commit**

```bash
git add SentinelGather/core/BotManager.lua
git commit -m "fix(sentinel-gather): validate facade module references on access"
```

---

### Task 20: Disable Start button when nav unavailable

**Files:**
- Modify: `SentinelGather/ui/window.lua` (control bar renderer)

**Step 1: Add nav availability check in Start button rendering**

In the control bar rendering function (the `_before_tabs_fn` hook), find where the Start button is rendered and add a guard:

```lua
-- Before rendering the Start button, check nav availability:
local gather = SentinelGather  -- or however the singleton is accessed
local nav_available = gather and gather.is_nav_available and gather:is_nav_available()

if nav_available then
    -- Render normal green Start button
    if start_btn:render("Start") then
        gather:start()
    end
else
    -- Render disabled Start with tooltip
    core.graphics.text("Nav Server Offline", color.red(200))
end
```

The exact implementation depends on the UI framework API. Check if `BotManager` exposes `is_nav_available()`:
```lua
-- In BotManager, add if missing:
function BotManager:is_nav_available()
    return self._nav_facade_available == true
end
```

**Step 2: Commit**

```bash
git add SentinelGather/ui/window.lua SentinelGather/core/BotManager.lua
git commit -m "feat(sentinel-gather): disable Start button when nav server unavailable"
```

---

## Final Verification

After all tasks:

```bash
# Rust server: build + test + lint
cd SentinelNavServer && cargo build --release && cargo test && cargo clippy -- -W clippy::all

# Check for leftover hardcoded IPs
grep -r "78.31.71.163" SentinelNavClient/ SentinelGather/

# Verify shared config exists
ls config/server.lua

# Verify git log
git log --oneline -25
```

Manual Lua testing (in Sylvannas):
1. Load SentinelNavClient, verify `_G.SentinelNavClient.facade` exists
2. Start gathering while casting — verify deferred move uses navmesh path
3. Verify health check logs appear every 30s
4. Kill SentinelNavServer — verify Start button disables or shows warning
5. Restart SentinelNavServer — verify health check reconnects
6. Test stuck recovery during casting — verify it defers
7. Check `/health` endpoint — verify metrics (total_requests, cache_hits, etc.)
