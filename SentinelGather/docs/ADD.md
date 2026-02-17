# GatherBuddy - Architecture Design Document (ADD)

**Version:** 1.0  
**Date:** January 31, 2025  
**Author:** Alex  
**Status:** Draft  

---

## 1. Introduction

### 1.1 Purpose

This document describes the high-level architecture of GatherBuddy, a gathering automation bot for World of Warcraft built on the Sylvannas API framework.

### 1.2 Scope

This document covers:
- System overview and context
- Component architecture
- Data flow and communication patterns
- Integration points
- Deployment architecture

### 1.3 Definitions

| Term | Definition |
|------|------------|
| Sylvannas API | The game automation framework providing access to WoW internals |
| Navigation Service | Rust-based REST API for pathfinding using MMAP data |
| EventBus | Pub/sub messaging system for component communication |
| StateMachine | Finite state machine managing bot behavior states |

---

## 2. System Overview

### 2.1 Context Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           World of Warcraft                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   Game      │  │   Object    │  │   Input     │  │   Graphics  │    │
│  │   State     │  │   Manager   │  │   System    │  │   System    │    │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
│         │                │                │                │            │
└─────────┼────────────────┼────────────────┼────────────────┼────────────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Sylvannas API Layer                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  core.object_manager  │  core.input  │  core.graphics  │  ...   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            GatherBuddy                                   │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                         BotManager                              │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │    │
│  │  │ EventBus │  │  State   │  │  Module  │  │  Tick    │       │    │
│  │  │          │  │ Machine  │  │  Loader  │  │  Loop    │       │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                    │                                    │
│                                    ▼                                    │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                          Modules                                │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │    │
│  │  │ Profile  │  │   Node   │  │  Gather  │  │ Movement │       │    │
│  │  │ Manager  │  │ Scanner  │  │  Module  │  │  Module  │       │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │    │
│  │  │  Mount   │  │  Safety  │  │Inventory │  │   Nav    │       │    │
│  │  │  Module  │  │  Module  │  │  Module  │  │  Client  │       │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                    │                                    │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Navigation Service                               │
│                        (Rust REST API @ :3000)                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                     │
│  │  Pathfind   │  │   Height    │  │   Raycast   │                     │
│  │   /find_path│  │   /height   │  │   /raycast  │                     │
│  └─────────────┘  └─────────────┘  └─────────────┘                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 System Boundaries

**In Scope:**
- Lua bot logic running within Sylvannas framework
- Navigation service communication
- Profile file management
- UI rendering within game overlay

**Out of Scope:**
- WoW client modifications
- Network packet manipulation
- Memory editing

---

## 3. Architecture Principles

### 3.1 Design Principles

| Principle | Description | Rationale |
|-----------|-------------|-----------|
| Event-Driven | Components communicate via events, not direct calls | Loose coupling, testability |
| State Machine | Single source of truth for bot state | Predictable behavior, easier debugging |
| Modular | Each module has single responsibility | Maintainability, extensibility |
| Defensive | Validate all inputs, handle failures gracefully | Robustness in game environment |
| Observable | Comprehensive logging and statistics | Debugging, optimization |

### 3.2 Constraints

| ID | Constraint | Impact |
|----|------------|--------|
| C1 | Sylvannas API only | Cannot use WoW Lua API functions |
| C2 | Single-threaded Lua | Must handle async HTTP callbacks |
| C3 | No persistent storage beyond files | Use JSON files for configuration |
| C4 | Sandboxed file access | Only scripts_data/ directory |

---

## 4. Component Architecture

### 4.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         BotManager                               │
│                                                                  │
│  Responsibilities:                                               │
│  - Initialize all modules                                        │
│  - Manage tick loop                                              │
│  - Handle lifecycle (start/stop/pause)                          │
│  - Coordinate state transitions                                  │
│                                                                  │
│  Dependencies: EventBus, StateMachine, All Modules              │
└─────────────────────────────────────────────────────────────────┘
          │
          │ owns
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                          EventBus                                │
│                                                                  │
│  Responsibilities:                                               │
│  - Manage event subscriptions                                    │
│  - Dispatch events to subscribers                                │
│  - Support event filtering                                       │
│                                                                  │
│  Interface:                                                      │
│  - subscribe(event, callback) → subscription_id                  │
│  - unsubscribe(subscription_id)                                  │
│  - publish(event, data)                                          │
└─────────────────────────────────────────────────────────────────┘
          │
          │ uses
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                        StateMachine                              │
│                                                                  │
│  Responsibilities:                                               │
│  - Track current state                                           │
│  - Validate state transitions                                    │
│  - Store state-specific data                                     │
│  - Emit STATE_CHANGED events                                     │
│                                                                  │
│  States: IDLE, LOADING, TRAVELING, SCANNING, APPROACHING,       │
│          GATHERING, LOOTING, MOUNTING, COMBAT, FLEEING,         │
│          DEAD, CORPSE_RUN, STUCK                                │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Module Specifications

#### 4.2.1 ProfileManager

```
┌─────────────────────────────────────────────────────────────────┐
│                       ProfileManager                             │
├─────────────────────────────────────────────────────────────────┤
│ Purpose: Load, validate, and manage gathering profiles          │
├─────────────────────────────────────────────────────────────────┤
│ State:                                                          │
│   - current_profile: Profile | nil                              │
│   - current_waypoint_index: number                              │
│   - available_profiles: string[]                                │
├─────────────────────────────────────────────────────────────────┤
│ Events Subscribed:                                              │
│   - PROFILE_LOAD_REQUEST                                        │
│   - BOT_START, BOT_STOP                                         │
│   - MOVEMENT_COMPLETED (to advance waypoint)                    │
├─────────────────────────────────────────────────────────────────┤
│ Events Published:                                               │
│   - PROFILE_LOADED, PROFILE_LOAD_FAILED                         │
│   - WAYPOINT_REACHED, HOTSPOT_ENTERED, HOTSPOT_EXITED          │
│   - ROUTE_COMPLETED                                             │
├─────────────────────────────────────────────────────────────────┤
│ Methods:                                                        │
│   - load_profile(path: string): boolean                         │
│   - validate_profile(data: table): boolean, string[]            │
│   - get_current_waypoint(): Waypoint                            │
│   - advance_waypoint(): Waypoint                                │
│   - get_nearest_waypoint(pos: vec3): Waypoint                   │
│   - is_in_blackspot(pos: vec3): boolean                         │
│   - list_available_profiles(): string[]                         │
└─────────────────────────────────────────────────────────────────┘
```

#### 4.2.2 NodeScanner

```
┌─────────────────────────────────────────────────────────────────┐
│                        NodeScanner                               │
├─────────────────────────────────────────────────────────────────┤
│ Purpose: Detect gatherable nodes in the game world              │
├─────────────────────────────────────────────────────────────────┤
│ State:                                                          │
│   - scan_radius: number (from profile settings)                 │
│   - node_blacklist: {[guid]: expire_time}                       │
│   - detected_nodes: game_object[]                               │
│   - target_node: game_object | nil                              │
├─────────────────────────────────────────────────────────────────┤
│ Events Subscribed:                                              │
│   - TICK                                                        │
│   - PROFILE_LOADED (to get scan radius)                         │
│   - GATHER_SUCCESS, GATHER_FAILED (to blacklist)                │
├─────────────────────────────────────────────────────────────────┤
│ Events Published:                                               │
│   - NODE_DETECTED                                               │
│   - NODE_LOST                                                   │
│   - NODE_BLACKLISTED                                            │
│   - NO_NODES_FOUND                                              │
├─────────────────────────────────────────────────────────────────┤
│ Methods:                                                        │
│   - scan(): game_object[]                                       │
│   - is_valid_node(obj: game_object): boolean                    │
│   - matches_node_pattern(name: string): boolean, string         │
│   - get_best_node(): game_object | nil                          │
│   - blacklist_node(obj: game_object, duration: number)          │
│   - is_blacklisted(obj: game_object): boolean                   │
└─────────────────────────────────────────────────────────────────┘
```

#### 4.2.3 GatherModule

```
┌─────────────────────────────────────────────────────────────────┐
│                        GatherModule                              │
├─────────────────────────────────────────────────────────────────┤
│ Purpose: Handle node interaction and looting                    │
├─────────────────────────────────────────────────────────────────┤
│ State:                                                          │
│   - current_node: game_object | nil                             │
│   - gather_start_time: number                                   │
│   - gather_timeout: number                                      │
│   - is_looting: boolean                                         │
├─────────────────────────────────────────────────────────────────┤
│ Events Subscribed:                                              │
│   - MOVEMENT_COMPLETED (when approaching node)                  │
│   - TICK                                                        │
│   - STATE_CHANGED                                               │
├─────────────────────────────────────────────────────────────────┤
│ Events Published:                                               │
│   - GATHER_START                                                │
│   - GATHER_SUCCESS, GATHER_FAILED, GATHER_INTERRUPTED          │
│   - LOOT_OPENED, LOOT_ITEM, LOOT_CLOSED                        │
│   - DISMOUNT_REQUEST                                            │
├─────────────────────────────────────────────────────────────────┤
│ Methods:                                                        │
│   - start_gather(node: game_object)                             │
│   - process_gathering(): GatherState                            │
│   - process_looting(): boolean                                  │
│   - cancel_gather()                                             │
│   - is_player_casting(): boolean                                │
└─────────────────────────────────────────────────────────────────┘
```

#### 4.2.4 MovementModule

```
┌─────────────────────────────────────────────────────────────────┐
│                       MovementModule                             │
├─────────────────────────────────────────────────────────────────┤
│ Purpose: Navigate using simple_movement and nav service         │
├─────────────────────────────────────────────────────────────────┤
│ State:                                                          │
│   - movement: simple_movement instance                          │
│   - current_path: vec3[]                                        │
│   - target_position: vec3 | nil                                 │
│   - last_position: vec3                                         │
│   - last_position_time: number                                  │
│   - stuck_count: number                                         │
├─────────────────────────────────────────────────────────────────┤
│ Events Subscribed:                                              │
│   - MOVE_TO_POSITION, MOVE_TO_WAYPOINT                         │
│   - PATH_RECEIVED                                               │
│   - TICK                                                        │
│   - STATE_CHANGED                                               │
├─────────────────────────────────────────────────────────────────┤
│ Events Published:                                               │
│   - PATH_REQUEST                                                │
│   - MOVEMENT_STARTED, MOVEMENT_PROGRESS, MOVEMENT_COMPLETED    │
│   - MOVEMENT_CANCELLED                                          │
│   - STUCK_DETECTED                                              │
├─────────────────────────────────────────────────────────────────┤
│ Methods:                                                        │
│   - move_to(position: vec3, use_pathfinding: boolean)          │
│   - stop()                                                      │
│   - update(dt: number)                                          │
│   - check_stuck(): boolean                                      │
│   - attempt_unstuck(): boolean                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 4.2.5 SafetyModule

```
┌─────────────────────────────────────────────────────────────────┐
│                        SafetyModule                              │
├─────────────────────────────────────────────────────────────────┤
│ Purpose: Monitor threats and handle combat/death                │
├─────────────────────────────────────────────────────────────────┤
│ State:                                                          │
│   - threat_level: number (0-3)                                  │
│   - nearby_enemies: game_object[]                               │
│   - last_health: number                                         │
│   - death_time: number | nil                                    │
│   - corpse_position: vec3 | nil                                 │
├─────────────────────────────────────────────────────────────────┤
│ Events Subscribed:                                              │
│   - TICK                                                        │
│   - GATHER_START (to check safety)                              │
├─────────────────────────────────────────────────────────────────┤
│ Events Published:                                               │
│   - ENEMY_DETECTED, ENEMY_LOST                                  │
│   - THREAT_LEVEL_CHANGED                                        │
│   - COMBAT_ENTER, COMBAT_EXIT                                   │
│   - HEALTH_LOW                                                  │
│   - PLAYER_DIED, SPIRIT_RELEASED, RESURRECTED                  │
├─────────────────────────────────────────────────────────────────┤
│ Methods:                                                        │
│   - scan_threats(): game_object[]                               │
│   - calculate_threat_level(): number                            │
│   - is_safe_to_gather(): boolean                                │
│   - handle_death()                                              │
│   - handle_corpse_run()                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Data Architecture

### 5.1 Profile Data Model

```lua
---@class Profile
---@field version string
---@field metadata ProfileMetadata
---@field requirements ProfileRequirements
---@field settings ProfileSettings
---@field waypoints Waypoint[]
---@field blackspots Blackspot[]
---@field vendors Vendor[]
---@field mailboxes Mailbox[]

---@class Waypoint
---@field id number
---@field x number
---@field y number
---@field z number
---@field type "path"|"hotspot"|"vendor"|"mailbox"|"safe"
---@field radius number|nil        -- For hotspots
---@field linger_time number|nil   -- For hotspots
---@field note string|nil

---@class Blackspot
---@field x number
---@field y number
---@field z number
---@field radius number
---@field reason string|nil
```

### 5.2 Settings Data Model

```lua
---@class Settings
---@field general GeneralSettings
---@field movement MovementSettings
---@field gathering GatheringSettings
---@field safety SafetySettings
---@field anti_detection AntiDetectionSettings
---@field ui UISettings

---@class GeneralSettings
---@field enabled boolean
---@field debug_mode boolean
---@field log_level "debug"|"info"|"warning"|"error"

---@class MovementSettings
---@field mount_threshold number        -- Distance to trigger mount (default 40)
---@field dismount_distance number      -- Distance to dismount before node (default 8)
---@field preferred_mount_index number  -- Mount collection index
---@field stuck_threshold_seconds number
---@field stuck_distance_threshold number
```

### 5.3 State Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Profile   │────▶│ StateMachine│────▶│   Modules   │
│    JSON     │     │   State     │     │   Actions   │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Waypoints  │     │  Current    │     │  Game API   │
│  Blackspots │     │  State +    │     │  Calls      │
│  Settings   │     │  Context    │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

---

## 6. Integration Architecture

### 6.1 Navigation Service Integration

```
┌─────────────────┐                    ┌─────────────────┐
│  GatherBuddy    │                    │ Navigation Svc  │
│                 │                    │                 │
│ NavigationClient│───HTTP GET────────▶│ /find_path     │
│                 │◀──JSON Response────│                 │
│                 │                    │                 │
│                 │───HTTP GET────────▶│ /height        │
│                 │◀──JSON Response────│                 │
└─────────────────┘                    └─────────────────┘

Request: GET /api/v1/pathfinding/find_path?
    map={map_id}&
    start_x={x}&start_y={y}&start_z={z}&
    end_x={x}&end_y={y}&end_z={z}&
    smooth=true

Response: {
    "success": true,
    "path": [
        {"x": 123.4, "y": 56.7, "z": 89.0},
        ...
    ],
    "distance": 234.5,
    "computation_time_ms": 12
}
```

### 6.2 Sylvannas API Integration

```lua
-- Callback Registration (init.lua)
core.register_on_update_callback(function()
    BotManager:update(core.delta_time())
end)

core.register_on_render_callback(function()
    BotManager:render()
end)

core.register_on_render_menu_callback(function()
    UI:render_menu()
end)

-- Object Manager Access (NodeScanner)
local objects = core.object_manager.get_all_objects()
for _, obj in ipairs(objects) do
    if obj:is_valid() and obj:can_be_used() then
        -- Process potential node
    end
end

-- Input Actions (GatherModule)
core.input.look_at(node:get_position())
core.input.use_object(node)

-- Loot Processing
local count = core.game_ui.get_loot_item_count()
for i = 0, count - 1 do
    core.input.loot_item(i)
end
core.input.close_loot()
```

---

## 7. Error Handling Architecture

### 7.1 Error Categories

| Category | Examples | Handling Strategy |
|----------|----------|-------------------|
| Transient | HTTP timeout, node despawned | Retry with backoff |
| Recoverable | Stuck, combat | State transition to recovery |
| Fatal | Invalid profile, missing API | Stop bot, notify user |
| Ignorable | Loot window empty | Log and continue |

### 7.2 Recovery Strategies

```
┌─────────────────────────────────────────────────────────────────┐
│                      Error Recovery Flow                         │
└─────────────────────────────────────────────────────────────────┘

Stuck Detection:
  1. Jump → Check movement → Success? Resume : Continue
  2. Strafe random direction → Check → Success? Resume : Continue
  3. Move backward → Check → Success? Resume : Continue
  4. Request new path → Success? Resume : Continue
  5. Skip to next waypoint → Resume

Gather Failure:
  1. Check if node still exists → No? Blacklist, continue route
  2. Check if in combat → Yes? Handle combat first
  3. Check if interrupted → Yes? Wait, retry (max 3)
  4. Timeout → Blacklist node, continue route

Death Recovery:
  1. Wait configurable delay (appear AFK)
  2. Release spirit
  3. Navigate ghost to corpse (using nav service)
  4. Resurrect at corpse
  5. Wait for resurrection sickness (if any)
  6. Resume from nearest waypoint
```

---

## 8. Security Considerations

### 8.1 Anti-Detection Measures

| Measure | Implementation |
|---------|----------------|
| Timing Variance | Gaussian distribution for all delays |
| Path Deviation | 5-15% random offset from navmesh path |
| Random Pauses | 2-8 second pauses every 30-90 seconds |
| Gathering Order | Weighted random, not always nearest |
| Competition Skip | Skip nodes when other players present |
| Session Limits | Configurable max session duration |

### 8.2 Data Protection

- No sensitive data stored (no passwords, tokens)
- Profile files are user-created, not downloaded
- Statistics stored locally only
- No network communication except to local nav service

---

## 9. Deployment Architecture

### 9.1 File Layout

```
scripts_data/
└── gatherbuddy/
    ├── profiles/
    │   ├── retail/
    │   │   └── zone_name_route.json
    │   └── classic/
    │       └── zone_name_route.json
    ├── settings.json
    ├── statistics.json
    └── logs/
        └── session_YYYYMMDD_HHMMSS.log
```

### 9.2 Startup Sequence

```
1. Sylvannas loads GatherBuddy/init.lua
2. init.lua requires main.lua
3. main.lua initializes:
   a. Logger
   b. Settings (load from file)
   c. EventBus
   d. StateMachine
   e. All Modules (in dependency order)
   f. BotManager
   g. UI
4. Register callbacks with core.*
5. Bot enters IDLE state, awaiting user input
```

---

## 10. Appendix

### 10.1 State Transition Matrix

| From \ To | IDLE | LOADING | TRAVELING | SCANNING | APPROACHING | GATHERING | LOOTING | MOUNTING | COMBAT | DEAD |
|-----------|------|---------|-----------|----------|-------------|-----------|---------|----------|--------|------|
| IDLE | - | ✓ | - | - | - | - | - | - | - | - |
| LOADING | ✓ | - | ✓ | - | - | - | - | - | - | - |
| TRAVELING | ✓ | - | - | ✓ | ✓ | - | - | ✓ | ✓ | ✓ |
| SCANNING | ✓ | - | ✓ | - | ✓ | - | - | - | ✓ | ✓ |
| APPROACHING | ✓ | - | ✓ | - | - | ✓ | - | - | ✓ | ✓ |
| GATHERING | ✓ | - | - | - | - | - | ✓ | - | ✓ | ✓ |
| LOOTING | ✓ | - | ✓ | - | - | - | - | ✓ | ✓ | ✓ |
| MOUNTING | ✓ | - | ✓ | - | - | - | - | - | ✓ | ✓ |
| COMBAT | ✓ | - | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | ✓ |
| DEAD | - | - | - | - | - | - | - | - | - | - |

### 10.2 Related Documents

- PRD.md - Product requirements
- TDD.md - Technical design details
- IMPLEMENTATION_TICKETS.md - Development tasks
- CLAUDE.md - Claude Code reference

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-31 | Alex | Initial draft |
