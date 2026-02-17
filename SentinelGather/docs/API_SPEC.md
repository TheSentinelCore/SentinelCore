# GatherBuddy - API Specification

**Version:** 1.0  
**Date:** January 31, 2025  

---

## 1. Event API

### 1.1 Event Data Contracts

All events follow the pattern: `module:action`

#### Lifecycle Events

```lua
-- BOT_START
-- Published when bot starts operation
{
    timestamp = number,      -- core.time()
    profile = string|nil     -- Profile name if loaded
}

-- BOT_STOP
{
    timestamp = number,
    reason = string          -- "user", "error", "bags_full"
}

-- BOT_PAUSE / BOT_RESUME
{
    timestamp = number
}

-- TICK
-- Published every frame
{
    dt = number,             -- Delta time (core.delta_time())
    tick_count = number      -- Total ticks since start
}
```

#### Profile Events

```lua
-- PROFILE_LOAD_REQUEST
{
    path = string            -- Profile file path
}

-- PROFILE_LOADED
{
    name = string,           -- Profile name
    path = string,           -- File path
    waypoint_count = number, -- Total waypoints
    map_id = number          -- Required map ID
}

-- PROFILE_LOAD_FAILED
{
    path = string,
    errors = string[]        -- Validation errors
}

-- WAYPOINT_REACHED
{
    waypoint = Waypoint,     -- Full waypoint data
    index = number,          -- Waypoint index
    is_last = boolean        -- Is final waypoint
}

-- HOTSPOT_ENTERED
{
    waypoint = Waypoint,
    radius = number,
    linger_time = number
}

-- HOTSPOT_EXITED
{
    waypoint = Waypoint,
    time_spent = number      -- Seconds in hotspot
}

-- ROUTE_COMPLETED
{
    total_time = number,     -- Seconds to complete route
    loops_completed = number
}
```

#### Scanner Events

```lua
-- SCAN_START
{
    radius = number,
    position = vec3          -- Scan center
}

-- NODE_DETECTED
{
    node = game_object,      -- The node object
    name = string,           -- Node name
    type = "herb"|"ore",
    position = vec3,
    distance = number
}

-- NODE_LOST
{
    node = game_object,
    reason = string          -- "despawned", "out_of_range", "blacklisted"
}

-- NODE_BLACKLISTED
{
    node = game_object,
    duration = number,       -- Blacklist duration in seconds
    reason = string          -- "gathered", "failed", "manual"
}

-- NO_NODES_FOUND
{
    scan_radius = number,
    position = vec3
}
```

#### Gathering Events

```lua
-- GATHER_START
{
    node = game_object,
    name = string,
    position = vec3,
    type = "herb"|"ore"
}

-- GATHER_PROGRESS
{
    node = game_object,
    elapsed = number,        -- Seconds since start
    is_casting = boolean
}

-- GATHER_SUCCESS
{
    node = game_object,
    duration = number,       -- Total gather time
    items_looted = number
}

-- GATHER_FAILED
{
    node = game_object,
    reason = string,         -- "timeout", "interrupted", "despawned"
    duration = number
}

-- GATHER_INTERRUPTED
{
    node = game_object,
    reason = string          -- "combat", "moved", "cancelled"
}

-- LOOT_OPENED
{
    item_count = number
}

-- LOOT_ITEM
{
    item_id = number,
    item_name = string,
    is_gold = boolean,
    quantity = number|nil
}

-- LOOT_CLOSED
{
    items_looted = number,
    total_time = number
}
```

#### Movement Events

```lua
-- MOVE_TO_POSITION
{
    position = vec3,
    use_pathfinding = boolean
}

-- MOVE_TO_WAYPOINT
{
    waypoint = Waypoint,
    index = number
}

-- MOVEMENT_STARTED
{
    target = vec3,
    distance = number,
    using_mount = boolean
}

-- MOVEMENT_PROGRESS
{
    current = vec3,
    target = vec3,
    distance_remaining = number,
    percent_complete = number
}

-- MOVEMENT_COMPLETED
{
    target = vec3,
    total_time = number,
    total_distance = number
}

-- MOVEMENT_CANCELLED
{
    reason = string          -- "user", "new_target", "combat"
}

-- PATH_REQUEST
{
    start = vec3,
    destination = vec3,
    map_id = number
}

-- PATH_RECEIVED
{
    path = vec3[],           -- Waypoints
    distance = number,
    computation_time_ms = number
}

-- PATH_FAILED
{
    reason = string,         -- "no_path", "timeout", "service_down"
    start = vec3,
    destination = vec3
}

-- STUCK_DETECTED
{
    position = vec3,
    stuck_count = number,    -- Consecutive stuck detections
    time_stuck = number
}

-- UNSTUCK_ATTEMPT
{
    strategy = string,       -- "jump", "strafe_left", etc.
    attempt = number
}

-- UNSTUCK_SUCCESS
{
    strategy = string,
    attempts = number
}

-- UNSTUCK_FAILED
{
    reason = string,
    total_attempts = number
}
```

#### Mount Events

```lua
-- MOUNT_REQUEST
{
    reason = string          -- "distance", "manual"
}

-- MOUNT_START
{
    mount_index = number
}

-- MOUNT_SUCCESS
{
    mount_time = number
}

-- MOUNT_FAILED
{
    reason = string          -- "interrupted", "combat", "indoor"
}

-- DISMOUNT_REQUEST
{
    reason = string          -- "gather", "combat", "manual"
}

-- DISMOUNT_COMPLETE
{}
```

#### Safety Events

```lua
-- ENEMY_DETECTED
{
    enemy = game_object,
    name = string,
    distance = number,
    is_elite = boolean,
    level = number
}

-- ENEMY_LOST
{
    enemy = game_object,
    reason = string          -- "dead", "out_of_range", "despawned"
}

-- THREAT_LEVEL_CHANGED
{
    previous = number,       -- 0-3
    current = number,
    enemies_count = number,
    nearest_distance = number
}

-- COMBAT_ENTER
{
    enemy = game_object|nil, -- May be nil if unknown attacker
    was_gathering = boolean
}

-- COMBAT_EXIT
{
    duration = number,
    health_remaining = number
}

-- HEALTH_LOW
{
    current_percent = number,
    threshold = number
}

-- PLAYER_DIED
{
    position = vec3,
    cause = string|nil       -- Enemy name if known
}

-- SPIRIT_RELEASED
{
    death_position = vec3,
    graveyard_position = vec3
}

-- CORPSE_REACHED
{
    distance_traveled = number
}

-- RESURRECTED
{
    at_corpse = boolean,
    sickness = boolean       -- Resurrection sickness applied
}
```

#### Inventory Events

```lua
-- BAGS_UPDATED
{
    free_slots = number,
    total_slots = number
}

-- BAGS_FULL
{
    free_slots = number,
    threshold = number
}

-- ITEM_ADDED
{
    item_id = number,
    item_name = string,
    quantity = number,
    bag = number,
    slot = number
}
```

#### State Events

```lua
-- STATE_CHANGED
{
    from = string,           -- Previous state
    to = string,             -- New state
    context = {
        entered_at = number,
        data = table,        -- State-specific data
        previous_state = string|nil
    }
}
```

---

## 2. Module Interfaces

### 2.1 EventBus

```lua
---@class EventBus
local EventBus = {}

---@param event string Event name
---@param callback function(data: table)
---@param priority? number Lower = earlier (default 100)
---@param once? boolean Unsubscribe after first call
---@return number subscription_id
function EventBus:subscribe(event, callback, priority, once) end

---@param subscription_id number
---@return boolean success
function EventBus:unsubscribe(subscription_id) end

---@param event string
---@param data? table
function EventBus:publish(event, data) end

---@param event string
---@param callback function
---@return number subscription_id
function EventBus:once(event, callback) end
```

### 2.2 StateMachine

```lua
---@class StateMachine
local StateMachine = {}

---@param event_bus EventBus
---@param initial_state string
---@return StateMachine
function StateMachine:new(event_bus, initial_state) end

---@param new_state string
---@param data? table State-specific data
---@return boolean success
function StateMachine:transition(new_state, data) end

---@param new_state string
---@return boolean can_transition
function StateMachine:can_transition(new_state) end

---@return string current_state
function StateMachine:get_state() end

---@return StateContext
function StateMachine:get_context() end

---@return number seconds_in_state
function StateMachine:get_time_in_state() end
```

### 2.3 ProfileManager

```lua
---@class ProfileManager
local ProfileManager = {}

---@param path string Profile file path
---@return boolean success
function ProfileManager:load_profile(path) end

---@param data table Profile data
---@return boolean valid, string[] errors
function ProfileManager:validate_profile(data) end

---@return Profile|nil
function ProfileManager:get_current_profile() end

---@return Waypoint|nil
function ProfileManager:get_current_waypoint() end

---@return Waypoint|nil next_waypoint
function ProfileManager:advance_waypoint() end

---@param pos vec3
---@return Waypoint|nil
function ProfileManager:get_nearest_waypoint(pos) end

---@param pos vec3
---@return boolean
function ProfileManager:is_in_blackspot(pos) end

---@return string[] profile_paths
function ProfileManager:list_available_profiles() end

function ProfileManager:unload_profile() end
```

### 2.4 NodeScanner

```lua
---@class NodeScanner
local NodeScanner = {}

---@return NodeCandidate[]
function NodeScanner:scan() end

---@param obj game_object
---@return boolean is_node, string|nil node_type
function NodeScanner:is_valid_node(obj) end

---@return NodeCandidate|nil
function NodeScanner:get_best_node() end

---@param obj game_object
---@param duration number Seconds
function NodeScanner:blacklist_node(obj, duration) end

---@param obj game_object
---@return boolean
function NodeScanner:is_blacklisted(obj) end

---@return NodeCandidate[]
function NodeScanner:get_detected_nodes() end
```

### 2.5 GatherModule

```lua
---@class GatherModule
local GatherModule = {}

---@param node game_object
function GatherModule:start_gather(node) end

---@return boolean is_gathering
function GatherModule:is_gathering() end

function GatherModule:cancel_gather() end

---@return string|nil current_state
function GatherModule:get_gather_state() end
```

### 2.6 MovementModule

```lua
---@class MovementModule
local MovementModule = {}

---@param position vec3
---@param use_pathfinding? boolean Default true
function MovementModule:move_to(position, use_pathfinding) end

function MovementModule:stop() end

---@return boolean
function MovementModule:is_moving() end

---@return vec3|nil
function MovementModule:get_target() end

---@return number
function MovementModule:get_distance_remaining() end

---@return boolean
function MovementModule:check_stuck() end

---@return boolean success
function MovementModule:attempt_unstuck() end
```

### 2.7 NavigationClient

```lua
---@class NavigationClient
local NavigationClient = {}

---@param start_pos vec3
---@param end_pos vec3
---@param callback function(success: boolean, path: vec3[]|nil, error: string|nil)
function NavigationClient:find_path(start_pos, end_pos, callback) end

---@param x number
---@param z number
---@param callback function(success: boolean, height: number|nil)
function NavigationClient:get_height(x, z, callback) end

---@return boolean
function NavigationClient:is_available() end
```

### 2.8 MountModule

```lua
---@class MountModule
local MountModule = {}

function MountModule:mount() end

function MountModule:dismount() end

---@param distance number
---@return boolean
function MountModule:should_mount(distance) end

---@return boolean
function MountModule:is_mounted() end

---@return boolean
function MountModule:is_mount_casting() end
```

### 2.9 SafetyModule

```lua
---@class SafetyModule
local SafetyModule = {}

---@return game_object[]
function SafetyModule:scan_threats() end

---@return number 0=safe, 1=caution, 2=danger, 3=combat
function SafetyModule:get_threat_level() end

---@return boolean
function SafetyModule:is_safe_to_gather() end

---@return boolean
function SafetyModule:is_in_combat() end

---@return boolean
function SafetyModule:is_dead() end

---@return boolean
function SafetyModule:is_ghost() end

function SafetyModule:handle_death() end

function SafetyModule:handle_corpse_run() end
```

### 2.10 InventoryModule

```lua
---@class InventoryModule
local InventoryModule = {}

---@return number
function InventoryModule:get_free_slots() end

---@return number
function InventoryModule:get_total_slots() end

---@return boolean
function InventoryModule:is_bags_full() end
```

---

## 3. Data Types

### 3.1 Profile Types

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

---@class ProfileMetadata
---@field name string
---@field author string|nil
---@field description string|nil
---@field game_version "Classic"|"Retail"
---@field estimated_time_minutes number|nil

---@class ProfileRequirements
---@field min_skill {mining: number, herbalism: number}
---@field zone string
---@field map_id number
---@field requires_flying boolean

---@class ProfileSettings
---@field loop boolean
---@field reverse_on_complete boolean|nil
---@field node_search_radius number
---@field waypoint_tolerance number
---@field mount_threshold_distance number
---@field skip_if_enemies_near boolean
---@field enemy_detection_radius number

---@class Waypoint
---@field id number
---@field x number
---@field y number
---@field z number
---@field type "path"|"hotspot"|"vendor"|"mailbox"|"safe"
---@field radius number|nil
---@field linger_time number|nil
---@field note string|nil

---@class Blackspot
---@field x number
---@field y number
---@field z number
---@field radius number
---@field reason string|nil
```

### 3.2 Internal Types

```lua
---@class NodeCandidate
---@field object game_object
---@field name string
---@field type "herb"|"ore"
---@field position vec3
---@field distance number
---@field sort_distance number -- With randomization applied

---@class StateContext
---@field entered_at number
---@field data table
---@field previous_state string|nil

---@class Subscription
---@field id number
---@field event string
---@field callback function
---@field priority number
---@field once boolean
```

---

## 4. Configuration Schema

### 4.1 Settings File (`settings.json`)

```json
{
  "general": {
    "enabled": true,
    "debug_mode": false,
    "log_level": "info"
  },
  "movement": {
    "mount_threshold": 40,
    "dismount_distance": 8,
    "preferred_mount_index": 1,
    "stuck_check_interval": 2.0,
    "stuck_distance_threshold": 1.5,
    "max_stuck_attempts": 5,
    "path_deviation_percent": 0.10
  },
  "gathering": {
    "node_search_radius": 80,
    "gather_timeout": 10,
    "loot_delay_min": 0.05,
    "loot_delay_max": 0.15,
    "node_blacklist_duration": 300,
    "failed_node_blacklist_duration": 60
  },
  "safety": {
    "enemy_scan_radius": 30,
    "skip_if_enemies_near": true,
    "flee_health_threshold": 30,
    "death_release_delay_min": 3,
    "death_release_delay_max": 10
  },
  "anti_detection": {
    "enabled": true,
    "random_pause_enabled": true,
    "random_pause_interval_min": 30,
    "random_pause_interval_max": 90,
    "random_pause_duration_min": 2,
    "random_pause_duration_max": 8,
    "random_pause_chance": 0.03,
    "random_jump_enabled": true,
    "random_jump_interval_min": 45,
    "random_jump_interval_max": 120,
    "gather_order_randomization": true
  },
  "inventory": {
    "min_free_slots": 2
  },
  "ui": {
    "show_overlay": true,
    "show_statistics": true,
    "window_position": { "x": 100, "y": 100 }
  }
}
```

---

## 5. HTTP API (Navigation Service)

### 5.1 Find Path

**Request:**
```
GET /api/v1/pathfinding/find_path?
    map={map_id}&
    start_x={x}&start_y={y}&start_z={z}&
    end_x={x}&end_y={y}&end_z={z}&
    smooth=true
```

**Response (Success):**
```json
{
    "success": true,
    "path": [
        {"x": 123.45, "y": 67.89, "z": 101.23},
        {"x": 124.56, "y": 68.90, "z": 102.34}
    ],
    "distance": 234.56,
    "computation_time_ms": 12
}
```

**Response (Error):**
```json
{
    "success": false,
    "error": "No path found",
    "code": "PATH_NOT_FOUND"
}
```

### 5.2 Get Height

**Request:**
```
GET /api/v1/spatial/height?map={map_id}&x={x}&z={z}
```

**Response:**
```json
{
    "success": true,
    "height": 67.89
}
```

### 5.3 Health Check

**Request:**
```
GET /health
```

**Response:**
```json
{
    "status": "healthy",
    "version": "1.0.0",
    "maps_loaded": 5
}
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-31 | Alex | Initial draft |
