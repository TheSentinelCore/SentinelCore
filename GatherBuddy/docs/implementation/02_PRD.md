# Product Requirements Document: GatherBuddy Movement & Navigation Client v2

**Version:** 2.0
**Date:** February 5, 2026
**Author:** Alex (Team Lead, GatherBuddy)
**Status:** Ready for Implementation

---

## 1. Executive Summary

Rewrite the Movement and Navigation Client modules for GatherBuddy from scratch. The current implementation (MovementModule.lua at 1420 lines, NavigationClient.lua at 775 lines) has grown organically with excessive coupling to external systems (EventBus, StateMachine, ProfileManager, Settings module). The rewrite targets a clean, self-contained, minimal-dependency architecture where the navigation server handles all pathfinding intelligence and the client modules are thin, focused layers.

**Goals:**
- Reduce combined codebase from ~2200 lines to ~800-900 lines
- Eliminate dependencies on EventBus, StateMachine, ProfileManager, Settings
- Make modules independently testable and reusable
- Improve stuck detection reliability
- Simplify the mental model: NavigationClient talks to server, MovementModule moves the character

---

## 2. Problem Statement

### Current Pain Points

1. **Excessive coupling** — MovementModule depends on EventBus (6 event subscriptions), StateMachine (state checks for casting/mounting), ProfileManager (continent ID lookup), Settings module (15+ settings lookups), and Logger (lazy-loaded). This makes the module impossible to test or reuse independently.

2. **Bloated state management** — 40+ instance fields tracking route state, iterative pathfinding, corridor widths, pending paths, restart counts, unstuck strategies. Most of this complexity exists because the module tries to handle every edge case inline.

3. **Mixed concerns** — MovementModule handles pathfinding requests, locomotion, stuck detection, path validation, route planning, deferred movement, iterative partial paths, and event publishing all in one class.

4. **Fragile async handling** — The `self_ref` pattern for capturing `self` in async callbacks is used everywhere and is error-prone. Some callbacks reference state that may have changed between request and response.

5. **Redundant path following** — The module re-implements waypoint following logic that `simple_movement` already provides. It tracks `_path_index` and does per-waypoint `move_to_position` calls instead of using `simple_movement:navigate()` which handles the full waypoint list.

---

## 3. Requirements

### 3.1 NavigationClient

#### 3.1.1 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| NC-1 | Provide typed methods for all NavBuddy REST endpoints | Must |
| NC-2 | Convert JSON path arrays to vec3[] automatically | Must |
| NC-3 | Retry failed requests with exponential backoff (max 3) | Must |
| NC-4 | Track connection health (consecutive failures, last success time) | Must |
| NC-5 | Accept configurable base URL and retry count | Must |
| NC-6 | Include inline JSON decoder (no external dependency) | Must |
| NC-7 | Properly format float params (no trailing zeros) | Should |
| NC-8 | Log request failures with endpoint and error code | Should |
| NC-9 | Automatically use `core.get_map_id()` when map_id not provided | Must |
| NC-10 | Support all endpoint options as typed opts tables | Should |

#### 3.1.2 Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NC-NF1 | Module size | ≤ 350 lines |
| NC-NF2 | Zero external dependencies (beyond core, vec3) | Required |
| NC-NF3 | Full LuaDoc type annotations | Required |
| NC-NF4 | Memory: no per-request allocations beyond callback closures | Target |

#### 3.1.3 API Surface

```lua
-- Constructor
NavigationClient:new(config?) → NavigationClient

-- Core pathfinding
NavigationClient:find_path(start, dest, callback, opts?)
NavigationClient:find_route_tsp(nodes, callback, opts?)
NavigationClient:find_route_multi(stops, callback, opts?)
NavigationClient:check_path(current_pos, waypoints, callback, opts?)
NavigationClient:find_path_corridor(start, dest, callback, opts?)

-- Spatial queries
NavigationClient:raycast(start, dest, callback, opts?)
NavigationClient:get_height(pos, callback, opts?)
NavigationClient:random_point(callback, opts?)

-- Tactical
NavigationClient:flee(player_pos, threats, callback, opts?)
NavigationClient:kite(player_pos, target_pos, callback, opts?)

-- Health & status
NavigationClient:health_check(callback)
NavigationClient:is_available() → boolean
NavigationClient:get_consecutive_failures() → number
NavigationClient:reset()
```

#### 3.1.4 Callback Contract

All API methods use consistent callback signatures:

```lua
---@param success boolean
---@param data table|nil   -- Endpoint-specific response data
---@param error string|nil -- Human-readable error message
callback(success, data, error)
```

Path-returning endpoints always include `data.waypoints` as `vec3[]`.

### 3.2 MovementModule

#### 3.2.1 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| MM-1 | Move player to single target using navmesh pathfinding | Must |
| MM-2 | Plan and follow TSP-optimized multi-node routes | Must |
| MM-3 | Detect stuck state and attempt recovery | Must |
| MM-4 | Validate active path periodically via raycast check | Should |
| MM-5 | Defer movement start when player is casting/channeling | Must |
| MM-6 | Handle partial paths via iterative re-pathing | Should |
| MM-7 | Provide progress info (state, index, count, distance) | Must |
| MM-8 | Support direct movement without pathfinding (short range) | Should |
| MM-9 | Replan route with remaining unvisited nodes | Must |
| MM-10 | Stop all movement cleanly on demand | Must |
| MM-11 | Call `simple_movement:process()` every frame in update | Must |
| MM-12 | Use `simple_movement:navigate()` for full path following | Must |

#### 3.2.2 State Machine

```
IDLE ──────────→ REQUESTING_PATH (move_to / plan_route called)
                      │
                      ├─ success ──→ MOVING
                      │                 │
                      │                 ├─ waypoints done ──→ ARRIVED
                      │                 ├─ stuck detected ──→ STUCK
                      │                 └─ stop() called ───→ IDLE
                      │
                      └─ failure ──→ FAILED
                                       │
                                       └─ stop() ──→ IDLE

STUCK ─── recovery success ──→ MOVING (repath)
      └── max attempts ───────→ FAILED

ARRIVED ─── (auto or manual) ──→ IDLE
        └── next route leg ────→ REQUESTING_PATH
```

#### 3.2.3 Stuck Recovery Strategies

Applied in rotation, one per stuck detection cycle:

| Attempt | Strategy | Action |
|---------|----------|--------|
| 1 | Jump | `core.input.jump()` |
| 2 | Strafe + Jump | Random strafe direction + jump |
| 3 | Backup + Jump | Move backward 1s, then jump forward |
| 4 | Repath | Request fresh path from current position |
| 5 | Fail | Give up, transition to FAILED state |

#### 3.2.4 Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| MM-NF1 | Module size | ≤ 600 lines |
| MM-NF2 | Dependencies: only NavigationClient, simple_movement, vec3, enums | Required |
| MM-NF3 | update() frame budget | < 0.1ms typical |
| MM-NF4 | Full LuaDoc type annotations | Required |
| MM-NF5 | No global variable leaks | Required |

#### 3.2.5 Configuration Defaults

```lua
{
    waypoint_tolerance   = 3.0,     -- yards: skip to next waypoint
    final_tolerance      = 1.5,     -- yards: consider destination reached
    stuck_check_interval = 2.0,     -- seconds between stuck checks
    stuck_distance_min   = 1.0,     -- yards: must move this much per interval
    max_stuck_attempts   = 5,       -- before transitioning to FAILED
    path_check_interval  = 8.0,     -- seconds between path revalidation
    smoothing            = "chaikin", -- default smoothing algorithm
    optimize             = true,     -- string-pulling enabled
    anti_detection        = false,   -- use /path-random
    max_deviation        = 3.0,      -- yards for anti-detection deviation
    allow_partial        = true,     -- accept partial paths
}
```

---

## 4. Out of Scope

- **Flying movement** — simple_movement has flying as WIP, not ready
- **Combat avoidance** — Handled by separate CombatModule
- **Mount/dismount logic** — Handled by calling code before move_to
- **Profile loading** — Calling code provides map_id and node positions
- **GUI/overlay** — Separate overlay module reads MovementModule state
- **Persistent settings** — Calling code passes config at construction time

---

## 5. Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Combined lines of code | ~2200 | ≤ 900 |
| External dependencies | 6 (EventBus, StateMachine, etc.) | 0 (beyond Sylvannas core) |
| Instance fields (MovementModule) | 40+ | ≤ 20 |
| Time to understand module | ~30 min | ~10 min |
| Stuck recovery success rate | ~60% | ~80% |
| Path request to first movement frame | ~500ms | ≤ 300ms |

---

## 6. Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Inline JSON decoder bugs | Path data corruption | Only handle NavBuddy's simple JSON schema; pcall wrap |
| Async callback state mismatch | Stale movement commands | Check `_state` at callback entry; ignore if state changed |
| simple_movement behavior changes | Movement breaks | Pin to known-good simple_movement API; use only documented methods |
| NavBuddy server not running | All pathfinding fails | Graceful fallback: log error, callback with failure, allow direct movement |
| Player teleported during movement | Stuck detection false positive | Compare distance to destination, not just incremental movement |

---

## 7. Integration Points

### How GatherBuddy calls MovementModule:

```lua
-- In GatherBuddy's main on_update callback:
local nav_client = NavigationClient:new({ base_url = "http://localhost:47110" })
local movement = MovementModule:new(nav_client, { anti_detection = true })

-- Move to a gathering node
movement:move_to(node_position, function(success, reason)
    if success then
        -- Start gathering interaction
    else
        core.log_warning("[GatherBuddy] Movement failed: " .. (reason or "unknown"))
    end
end)

-- Every frame in on_update:
movement:update()

-- Plan a full gathering route
movement:plan_route(node_positions, function(success, reason)
    if success then
        core.log("[GatherBuddy] Route started")
    end
end)

-- Stop everything
movement:stop()
```
