# Implementation Tickets — Movement & Navigation Client Rewrite

All tickets reference the PRD (02_PRD.md) and Claude Code Prompt (01_CLAUDE_CODE_PROMPT.md).

---

## TICKET-001: Inline JSON Decoder

**Type:** Foundation
**Priority:** P0 — Blocker for all other tickets
**Estimate:** 30 min
**File:** NavigationClient.lua (top of file)

### Description
Implement a minimal JSON decoder function that handles NavBuddy's response format. No external dependency allowed.

### Acceptance Criteria
- [ ] `json_decode(str)` → table, parses objects, arrays, strings, numbers, booleans, null
- [ ] Handles nested objects (e.g., `{ "path": [{"x": 1.0, "y": 2.0, "z": 3.0}] }`)
- [ ] Returns `nil, error_message` on malformed JSON
- [ ] Handles negative numbers and scientific notation
- [ ] Handles escaped strings (`\"`, `\\`)
- [ ] ≤ 60 lines of code
- [ ] All calls wrapped in pcall by callers
- [ ] Local scope (not exported)

### Technical Notes
- NavBuddy responses are simple: flat objects with arrays of `{x,y,z}` point objects
- No need to handle: unicode escapes, deeply nested structures, streaming
- Test with: `json_decode('{"success":true,"path":[{"x":1.5,"y":-2.3,"z":100.0}],"distance":42.7}')

---

## TICKET-002: NavigationClient — Core Infrastructure

**Type:** Feature
**Priority:** P0 — Blocker
**Estimate:** 1 hour
**File:** NavigationClient.lua
**Depends on:** TICKET-001

### Description
Implement the NavigationClient class skeleton with URL builder, HTTP retry logic, and connection health tracking.

### Acceptance Criteria
- [ ] `NavigationClient:new(config?)` constructor with `base_url` and `max_retries` config
- [ ] `_build_url(endpoint, params)` — builds full GET URL from table
- [ ] `_request(url, callback, retries?)` — async HTTP GET with exponential backoff retry
- [ ] Connection state tracking: `_is_connected`, `_consecutive_failures`, `_last_success_time`
- [ ] `is_available()`, `get_consecutive_failures()`, `reset()` public methods
- [ ] Only retries on HTTP 0/500/502/503/504
- [ ] Logs failures with `core.log_error("[NavClient] ...")`
- [ ] Logs retries with `core.log_warning("[NavClient] ...")`
- [ ] Float formatting uses `string.format("%g", num)` — no trailing zeros

### Technical Notes
```lua
-- URL builder example output:
-- "http://localhost:47110/api/v1/path?map_id=0&start_x=100&start_y=200&start_z=30"
-- Booleans as "true"/"false" strings in URL params
```

---

## TICKET-003: NavigationClient — Core Pathfinding Methods

**Type:** Feature
**Priority:** P0 — Blocker
**Estimate:** 1.5 hours
**File:** NavigationClient.lua
**Depends on:** TICKET-002

### Description
Implement the primary pathfinding API methods.

### Acceptance Criteria
- [ ] `find_path(start, dest, callback, opts?)` — supports opts: `smoothing`, `optimize`, `anti_detection`, `max_deviation`, `filter_ground/water/lava`, `smooth_iterations/samples/ratio`, `allow_partial`, `z_extent`, `map_id`
- [ ] `find_route_tsp(nodes, callback, opts?)` — nodes as vec3[], converts to semicolon-separated stops. Supports opts: `start_pos` (vec3), `return_to_start`, `weights`
- [ ] `find_route_multi(stops, callback, opts?)` — ordered multi-stop
- [ ] `check_path(current_pos, waypoints, callback, opts?)` — waypoints as vec3[], converts to semicolon format
- [ ] `find_path_corridor(start, dest, callback, opts?)` — includes `corridor_widths` in response
- [ ] All methods convert `response.path[]` to `vec3[]` using `vec3.new(pt.x, pt.y, pt.z)`
- [ ] All methods use `core.get_map_id()` as fallback when `opts.map_id` is nil
- [ ] All methods validate inputs (start/dest not nil) before making request
- [ ] All callbacks follow `(success, data, error)` contract

### Response Data Shapes
```lua
-- find_path callback data:
{ waypoints = vec3[], distance = number, partial = boolean, computation_time_ms = number }

-- find_route_tsp callback data:
{ waypoints = vec3[], visit_order = number[], leg_boundaries = number[],
  leg_distances = number[], total_distance = number }

-- check_path callback data:
{ valid = boolean, first_invalid_segment = number|nil, player_on_navmesh = boolean }

-- find_path_corridor callback data:
{ waypoints = vec3[], corridor_widths = number[], distance = number }
```

---

## TICKET-004: NavigationClient — Spatial & Tactical Methods

**Type:** Feature
**Priority:** P1 — High
**Estimate:** 45 min
**File:** NavigationClient.lua
**Depends on:** TICKET-002

### Description
Implement spatial query and tactical endpoint methods.

### Acceptance Criteria
- [ ] `raycast(start, dest, callback, opts?)` → `{ hit, hit_position (vec3), t, normal (vec3) }`
- [ ] `get_height(pos, callback, opts?)` → `{ height = number }`
- [ ] `random_point(callback, opts?)` → `{ point = vec3 }` with optional center+radius
- [ ] `flee(player_pos, threats, callback, opts?)` — threats as vec3[], converts to semicolons. `{ waypoints, flee_direction, distance_from_threats }`
- [ ] `kite(player_pos, target_pos, callback, opts?)` — `{ waypoints, arc_length }`
- [ ] `health_check(callback)` → `{ status, uptime_secs, loaded_maps }`

---

## TICKET-005: MovementModule — Core Infrastructure

**Type:** Feature
**Priority:** P0 — Blocker
**Estimate:** 1 hour
**File:** MovementModule.lua
**Depends on:** TICKET-003

### Description
Implement the MovementModule class skeleton with state machine, constructor, and frame update loop.

### Acceptance Criteria
- [ ] `MovementModule:new(nav_client, config?)` constructor
- [ ] State field: `_state` ∈ `{"idle", "requesting_path", "moving", "stuck", "arrived", "failed"}`
- [ ] `_set_state(new_state)` with logging
- [ ] Config with all defaults from PRD §3.2.5
- [ ] `update()` method that:
  - Returns immediately if `_state == "idle"` or `_state == "arrived"` or `_state == "failed"`
  - Checks for deferred movement (pending path while casting ended)
  - Calls `simple_movement:process()` when `_state == "moving"`
  - Checks arrival condition (simple_movement reports done OR close enough to destination)
  - Runs stuck detection on interval
- [ ] `stop()` — stops simple_movement, resets to idle, clears all path state
- [ ] `is_moving()`, `get_state()`, `get_progress()`, `get_current_path()`
- [ ] Instance fields ≤ 20 total

### State Transitions
```lua
-- Log format:
core.log("[Movement] State: idle → requesting_path")
```

---

## TICKET-006: MovementModule — Single-Target Movement

**Type:** Feature
**Priority:** P0 — Blocker
**Estimate:** 1.5 hours
**File:** MovementModule.lua
**Depends on:** TICKET-005

### Description
Implement `move_to()` for pathfinding to a single destination.

### Acceptance Criteria
- [ ] `move_to(target, callback?, opts?)` validates player exists, is alive, target not nil
- [ ] Transitions to `requesting_path`, calls `nav_client:find_path()`
- [ ] On path success: feeds waypoints to `simple_movement:navigate()`, transitions to `moving`
- [ ] On path failure: transitions to `failed`, calls callback
- [ ] Handles async callback state mismatch (check `_state` is still `requesting_path` in callback)
- [ ] Defers movement if player is casting/channeling — stores pending and starts in `update()`
- [ ] Supports `opts.use_navmesh = false` for direct movement (skips pathfinding)
- [ ] Handles partial paths: if `data.partial`, store final destination, enter iterative mode
- [ ] Iterative re-pathing: when reaching partial path end, request new path to final destination (max 5 iterations)
- [ ] Configures `simple_movement` thresholds/smoothing before starting

### Integration with simple_movement
```lua
-- Configure simple_movement for this path
simple_movement:set_threshold(self._config.waypoint_tolerance)
simple_movement:set_final_threshold(self._config.final_tolerance)
simple_movement:set_smoothing_enabled(true)
simple_movement:set_use_look_at(true)

-- Feed full path
simple_movement:navigate(waypoints)
```

---

## TICKET-007: MovementModule — Stuck Detection & Recovery

**Type:** Feature
**Priority:** P0 — Critical for bot reliability
**Estimate:** 1 hour
**File:** MovementModule.lua
**Depends on:** TICKET-006

### Description
Implement stuck detection and multi-strategy recovery.

### Acceptance Criteria
- [ ] Every `stuck_check_interval` seconds (while `_state == "moving"`):
  - Compare `player:get_position()` to `_last_check_position`
  - If distance moved < `stuck_distance_min` AND `simple_movement:is_moving()`:
    - Increment `_stuck_count`
    - Apply recovery strategy based on count
  - Else: reset `_stuck_count` to 0, update checkpoint
- [ ] Recovery strategies (applied in order per `_stuck_count`):
  1. Jump — `core.input.jump()`
  2. Random strafe + jump — strafe left or right for 0.5s, then jump
  3. Backward + jump — move backward for 1.0s, stop, jump
  4. Repath — request fresh path from current position to destination
  5. Fail — transition to `failed`, callback with "Stuck: max attempts exceeded"
- [ ] Strategy 2/3 use timed sequences (track via `_unstuck_action_timer` and `_unstuck_action_phase`)
- [ ] Repath (strategy 4) calls `move_to()` internally to destination
- [ ] Log each stuck detection and strategy with `core.log_warning("[Movement] Stuck #N, trying: ...")`
- [ ] Don't false-positive during casting/channeling (skip stuck check if casting)

### Edge Cases
- Player teleported (e.g., by game event): large position change should reset stuck counter
- Player manually moved: reset stuck counter
- Stuck during repath callback: don't double-trigger

---

## TICKET-008: MovementModule — Route Mode (TSP)

**Type:** Feature
**Priority:** P1 — High
**Estimate:** 1.5 hours
**File:** MovementModule.lua
**Depends on:** TICKET-006

### Description
Implement TSP route planning and multi-leg following.

### Acceptance Criteria
- [ ] `plan_route(nodes, callback?, opts?)` — nodes as vec3[], minimum 2
- [ ] Calls `nav_client:find_route_tsp()` with player position as start
- [ ] On success: stores route data (waypoints, visit_order, leg_boundaries, leg_distances)
- [ ] Feeds full path to `simple_movement:navigate()`
- [ ] Tracks current leg via `_current_leg` index
- [ ] In `update()`: check if path progress has crossed a leg boundary → advance `_current_leg`
- [ ] When route completes: transition to `arrived`, callback with success
- [ ] `replan(reason?)`:
  - Collect remaining unvisited node positions using `_visit_order` and `_current_leg`
  - Stop current movement
  - Call `plan_route()` with remaining nodes
  - Log reason
- [ ] `get_progress()` returns route-specific data:
  ```lua
  { state = "moving", path_index = N, path_count = M, destination = vec3,
    distance_remaining = D, current_leg = L, total_legs = T,
    route_mode = true }
  ```
- [ ] Callback receives leg completion events:
  ```lua
  callback(true, { type = "leg_complete", leg = N, total = T })  -- per leg
  callback(true, { type = "route_complete" })  -- final
  ```

### Implementation Notes
- `leg_boundaries` from NavBuddy are indices into the full path array marking where each leg starts
- `visit_order` is 0-indexed from the Rust server; convert to 1-indexed for Lua

---

## TICKET-009: MovementModule — Path Validation

**Type:** Feature
**Priority:** P2 — Medium
**Estimate:** 30 min
**File:** MovementModule.lua
**Depends on:** TICKET-006

### Description
Periodically validate the remaining path to detect if it has become invalid (e.g., dynamic obstacles).

### Acceptance Criteria
- [ ] Every `path_check_interval` seconds while `_state == "moving"`:
  - Get remaining waypoints from `simple_movement:get_remaining_waypoints()`
  - Call `nav_client:check_path()` with current player position and remaining waypoints
  - If path is invalid: request fresh path to destination (repath)
- [ ] Don't trigger repath if one is already pending (`_path_check_pending` flag)
- [ ] Don't validate if remaining path is very short (< 3 waypoints)
- [ ] Log path invalidation with `core.log_warning("[Movement] Path invalid at segment N, repathing")`

---

## TICKET-010: Integration Test & Verification

**Type:** QA
**Priority:** P0
**Estimate:** 30 min
**Depends on:** All previous tickets

### Description
Verify the completed modules against all constraints and quality requirements.

### Verification Checklist
- [ ] `grep -r "C_Map\|UnitPosition\|GetPlayerMapPosition\|SetFacing\|MoveForwardStart" NavigationClient.lua MovementModule.lua` returns nothing
- [ ] All `simple_movement` calls use colon syntax (`:`)
- [ ] All public methods have `---@param` and `---@return` annotations
- [ ] No global variables (all `local` or on class table)
- [ ] Both files end with `return ClassName`
- [ ] NavigationClient ≤ 350 lines
- [ ] MovementModule ≤ 600 lines
- [ ] Combined ≤ 900 lines
- [ ] Instance fields count (MovementModule) ≤ 20
- [ ] All `core.http_get` callbacks handle `code ~= 200`
- [ ] All `pcall(json_decode, ...)` results checked before use
- [ ] `player` nil-checked before every `player:*` call
- [ ] `update()` calls `simple_movement:process()` exactly once per frame
- [ ] `stop()` calls `simple_movement:stop()` and resets all state
- [ ] Log messages prefixed with `[NavClient]` or `[Movement]`
- [ ] No deeply nested conditionals (max 3 levels)

### Smoke Test Scenario
```lua
-- This should work end-to-end:
local nc = NavigationClient:new()
local mm = MovementModule:new(nc)

-- Health check
nc:health_check(function(success, data, err)
    core.log("[Test] NavBuddy health: " .. tostring(success))
end)

-- Single move
mm:move_to(vec3.new(100, 200, 30), function(success, info)
    core.log("[Test] Move complete: " .. tostring(success))
end)

-- In on_update callback:
mm:update()

-- Check state
core.log("[Test] State: " .. mm:get_state())
core.log("[Test] Moving: " .. tostring(mm:is_moving()))
```

---

## Ticket Dependency Graph

```
TICKET-001 (JSON Decoder)
    │
    ▼
TICKET-002 (NavClient Infrastructure)
    │
    ├──────────────────┐
    ▼                  ▼
TICKET-003           TICKET-004
(Core Pathfinding)   (Spatial & Tactical)
    │
    ▼
TICKET-005 (MovementModule Infrastructure)
    │
    ├──────────────────┬─────────────────┐
    ▼                  ▼                 ▼
TICKET-006           TICKET-008        TICKET-009
(Single Movement)    (Route Mode)      (Path Validation)
    │
    ▼
TICKET-007 (Stuck Detection)
    │
    ▼
TICKET-010 (Verification)
```

---

## Estimated Total Effort

| Ticket | Estimate |
|--------|----------|
| 001 — JSON Decoder | 30 min |
| 002 — NavClient Core | 1 hour |
| 003 — Core Pathfinding | 1.5 hours |
| 004 — Spatial & Tactical | 45 min |
| 005 — MovementModule Core | 1 hour |
| 006 — Single Movement | 1.5 hours |
| 007 — Stuck Detection | 1 hour |
| 008 — Route Mode | 1.5 hours |
| 009 — Path Validation | 30 min |
| 010 — Verification | 30 min |
| **Total** | **~9 hours** |
