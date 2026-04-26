# CLAUDE.md - SentinelNavClient

> Shared navigation client singleton consumed by SentinelGather, SentinelCore, and other Lua plugins.

## Quick Reference

```bash
# No build step — Lua loaded at runtime by Sylvannas
# Accessed globally via _G.SentinelNavClient.client
```

## Architecture Overview

```
main.lua (Plugin entry point, v0.0.6)
    ↓
init.lua (Singleton factory → _G.SentinelNavClient)
    ↓
Client.lua (Facade, ~900 lines)
    ├─ EventBus         (Priority-based pub/sub with glob patterns)
    ├─ Blackboard       (Key-value state store with watchers)
    ├─ StateMachine     (3-level hierarchical state machine)
    ├─ Sensors          (Polls player state each frame)
    ├─ ConsoleLogger    (EventBus-driven logging adapter)
    ├─ Services
    │   ├─ NavigationService    (HTTP client → SentinelNavServer)
    │   ├─ MovementService      (simple_movement wrapper)
    │   ├─ ObstacleService      (Obstacle detection & avoidance zones)
    │   └─ PathValidationService (Path corridor validation)
    └─ NavigationTree   (Behavior tree for path following)
```

## Project Structure

```
SentinelNavClient/
├── header.lua                      # Plugin metadata (v0.0.6)
├── init.lua                        # Singleton factory
├── main.lua                        # Entry point, Sylvannas callbacks
├── config/
│   └── server.lua                  # Server connection defaults (127.0.0.1:47110)
├── core/
│   ├── Client.lua                  # Main facade (~900 lines)
│   ├── Blackboard.lua              # Key-value store with watchers + EventBus integration
│   ├── StateMachine.lua            # 3-level HSM (idle/navigating/arrived/failed)
│   ├── Sensors.lua                 # Player state polling (position, speed, casting, mounted)
│   ├── ConsoleLogger.lua           # Logging adapter (respects log_severity)
│   └── Defaults.lua                # Single source of truth for all config (83+ keys)
├── events/
│   ├── EventBus.lua                # Priority-based event system with glob patterns
│   └── Events.lua                  # Event constants (nav.state_changed, nav.stuck_*, etc.)
├── services/
│   ├── NavigationService.lua       # HTTP client for SentinelNavServer (find_path, raycast, etc.)
│   ├── MovementService.lua         # simple_movement wrapper (navigate, stop, strafe)
│   ├── ObstacleService.lua         # 3-ray raycast probing, FIFO avoidance zones (TTL 120s)
│   └── PathValidationService.lua   # Corridor deviation detection
├── behaviors/
│   ├── actions/                    # 11 BT action nodes
│   │   ├── AdvanceWaypoint.lua, ApplyDynamicSpeed.lua, Jump.lua
│   │   ├── ProbeForObstacle.lua, AddAvoidanceZone.lua
│   │   ├── RequestPath.lua, Repath.lua, SoftRepath.lua
│   │   ├── ValidatePath.lua, Strafe.lua, MoveBackward.lua
│   ├── conditions/                 # 5 BT condition nodes
│   │   ├── HasPath.lua, HasReachedWaypoint.lua, IsCasting.lua
│   │   ├── IsDeviated.lua, IsStuck.lua
│   └── trees/
│       ├── NavigationTree.lua      # Main navigation BT (~250 lines)
│       └── StuckRecoveryTree.lua   # 5-stage escalating recovery
├── lib/
│   ├── AstroUI.lua                 # UI framework
│   ├── BehaviorTree.lua            # BT engine (Sequence, ReactiveSequence, Selector, Parallel, etc.)
│   ├── Helpers.lua, JSON.lua
├── ui/
│   ├── window.lua                  # UI orchestrator, config sync to Blackboard
│   ├── Visualizer.lua              # 3D overlay rendering
│   └── tabs/                       # debug_tab, movement_tab, obstacles_tab, pathfinding_tab
└── docs/
    ├── API.md                      # Comprehensive consumer API documentation
    └── README.md
```

## Client Public API

```lua
local client = _G.SentinelNavClient.client

-- Movement commands
client:move_to(target, callback?, opts?)       -- Main movement (pathfind + follow)
client:move_direct(target, callback?)          -- Single-waypoint direct move
client:follow_path(waypoints, callback?, opts?) -- Follow precomputed path
client:plan_route(nodes, callback?, opts?)     -- TSP planning only
client:start_route(nodes, callback?, opts?)    -- TSP plan + auto-execute
client:replan(reason?)                         -- Re-request path
client:stop()                                  -- Cancel navigation

-- State queries
client:get_state()         -- "idle"|"navigating"|"arrived"|"failed"
client:get_full_state()    -- Hierarchical dot-joined (e.g. "navigating.following_path")
client:is_moving()         -- True only in navigating state
client:get_progress()      -- { percent, current, total }
```

## Hierarchical State Machine

```
Level 1: idle → navigating → arrived | failed
Level 2 (nav): awaiting_path → following_path → recovering → repathing → deferred
Level 3 (recovery): jumping → probing → strafing → backtracking
```

## NavigationTree Behavior

Root selector with:
1. Casting deferral (pause while spell casting)
2. Path ensuring (RequestPath if none)
3. Normal follow (ReactiveSequence with guards)
4. Deviation handling (SoftRepath with budget)
5. Stuck recovery (5-stage escalation: Jump → Probe+Repath → Strafe+Jump → Backward+Jump → Zone+Repath)

## Key Patterns

- **Singleton**: One Client per game session, shared across all consumers
- **Blackboard watchers**: Local callbacks + EventBus `bb.<key>` events on changes
- **EventBus**: Priority-based, glob patterns (e.g. `nav.*`), owner-based cleanup
- **Config ownership**: SentinelNavClient UI owns all tuning; consumers should not write config
- **Defaults.lua**: Single source of truth for all 83+ config keys with ranges
- **Server connection**: `http://127.0.0.1:47110` (SentinelNavServer)
