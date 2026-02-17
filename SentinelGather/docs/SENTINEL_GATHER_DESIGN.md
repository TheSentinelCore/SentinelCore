# SentinelGather - Gathering Bot Design Document

## Overview

SentinelGather is a herbalism/mining gathering bot built on the Sylvannas API with an event-driven architecture. It navigates predefined routes, detects gathering nodes, and collects resources while avoiding threats.

**Key Principles:**
- Event-driven architecture for loose coupling
- Modular design for easy extension
- Profile-based routes (JSON format)
- Human-like behavior patterns for detection avoidance
- ONLY Sylvannas API - no WoW Lua permitted

---

## Architecture

### Core Philosophy

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SentinelGather                                  │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │ Profile  │──▶│  State   │──▶│  Event   │──▶│    Modules       │ │
│  │ Manager  │   │ Machine  │   │   Bus    │   │                  │ │
│  └──────────┘   └──────────┘   └──────────┘   │ • Scanner        │ │
│       │                             │          │ • Movement       │ │
│       ▼                             │          │ • Gatherer       │ │
│  ┌──────────┐                       │          │ • Combat/Safety  │ │
│  │Navigation│◀──────────────────────┘          │ • Mount          │ │
│  │ Service  │                                  │ • Inventory      │ │
│  └──────────┘                                  └──────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### State Machine

```lua
STATES = {
    IDLE           = "idle",           -- Bot stopped/paused
    LOADING        = "loading",        -- Loading profile
    TRAVELING      = "traveling",      -- Moving along route
    APPROACHING    = "approaching",    -- Moving to detected node
    GATHERING      = "gathering",      -- Interacting with node
    LOOTING        = "looting",        -- Looting window open
    MOUNTING       = "mounting",       -- Mount cast in progress
    COMBAT         = "combat",         -- In combat (flee or fight)
    DEAD           = "dead",           -- Player is dead
    CORPSE_RUN     = "corpse_run",     -- Running back to corpse
    STUCK          = "stuck",          -- Stuck detection triggered
    VENDOR         = "vendor",         -- At vendor (future)
    MAILBOX        = "mailbox",        -- At mailbox (future)
}
```

### Event System

```lua
EVENTS = {
    -- Lifecycle
    BOT_START               = "bot:start",
    BOT_STOP                = "bot:stop",
    BOT_PAUSE               = "bot:pause",
    BOT_RESUME              = "bot:resume",
    TICK                    = "bot:tick",

    -- Profile
    PROFILE_LOAD_REQUEST    = "profile:load_request",
    PROFILE_LOADED          = "profile:loaded",
    PROFILE_LOAD_FAILED     = "profile:load_failed",
    PROFILE_UNLOADED        = "profile:unloaded",
    WAYPOINT_REACHED        = "profile:waypoint_reached",
    HOTSPOT_ENTERED         = "profile:hotspot_entered",
    HOTSPOT_EXITED          = "profile:hotspot_exited",
    ROUTE_COMPLETED         = "profile:route_completed",

    -- Scanning
    NODE_DETECTED           = "scanner:node_detected",
    NODE_LOST               = "scanner:node_lost",
    NODE_BLACKLISTED        = "scanner:node_blacklisted",
    SCAN_COMPLETE           = "scanner:scan_complete",

    -- Gathering
    GATHER_START            = "gather:start",
    GATHER_PROGRESS         = "gather:progress",
    GATHER_SUCCESS          = "gather:success",
    GATHER_FAILED           = "gather:failed",
    GATHER_INTERRUPTED      = "gather:interrupted",
    LOOT_WINDOW_OPENED      = "gather:loot_opened",
    LOOT_WINDOW_CLOSED      = "gather:loot_closed",
    ITEM_LOOTED             = "gather:item_looted",

    -- Movement
    MOVE_TO                 = "movement:move_to",
    MOVEMENT_STARTED        = "movement:started",
    MOVEMENT_COMPLETED      = "movement:completed",
    MOVEMENT_STOPPED        = "movement:stopped",
    MOVEMENT_STUCK          = "movement:stuck",
    MOVEMENT_STOP           = "movement:stop",
    PATH_REQUEST            = "movement:path_request",
    PATH_REQUESTED          = "movement:path_requested",
    PATH_RECEIVED           = "movement:path_received",
    PATH_FAILED             = "movement:path_failed",

    -- Safety
    ENEMY_DETECTED          = "safety:enemy_detected",
    COMBAT_ENTERED          = "safety:combat_entered",
    COMBAT_EXITED           = "safety:combat_exited",
    PLAYER_DIED             = "safety:player_died",
    PLAYER_RESURRECTED      = "safety:player_resurrected",
    THREAT_LEVEL_CHANGED    = "safety:threat_level_changed",

    -- Mount
    MOUNT_REQUESTED         = "mount:requested",
    MOUNT_STARTED           = "mount:started",
    MOUNT_COMPLETED         = "mount:completed",
    MOUNT_FAILED            = "mount:failed",
    DISMOUNT_REQUESTED      = "mount:dismount_requested",

    -- Inventory
    BAGS_FULL               = "inventory:bags_full",

    -- State
    STATE_CHANGED           = "state:changed",
}
```

---

## Profile Format

After evaluating options, **JSON** is recommended for profiles:
- Native Lua parsing available (simple JSON library)
- Human-readable and editable
- Wide tooling support
- Can be generated programmatically

### Profile Schema (v1.0)

```json
{
  "version": "1.0",
  "metadata": {
    "name": "Elwynn Forest Copper/Peacebloom",
    "author": "Username",
    "description": "Starter zone gathering route for copper ore and peacebloom",
    "created": "2025-01-31T00:00:00Z",
    "updated": "2025-01-31T00:00:00Z",
    "game_version": "Retail",
    "estimated_time_minutes": 15
  },
  
  "requirements": {
    "min_skill": {
      "mining": 1,
      "herbalism": 1
    },
    "zone": "Elwynn Forest",
    "map_id": 37,
    "recommended_level": 1,
    "requires_flying": false
  },
  
  "settings": {
    "loop": true,
    "reverse_on_complete": false,
    "node_search_radius": 80,
    "waypoint_tolerance": 3.0,
    "mount_threshold_distance": 40,
    "skip_if_enemies_near": true,
    "enemy_detection_radius": 25,
    "max_node_approach_distance": 100
  },
  
  "filters": {
    "gather_types": ["herb", "ore"],
    "node_whitelist": [],
    "node_blacklist": ["Rich Thorium Vein"],
    "npc_id_blacklist": [1234, 5678]
  },
  
  "waypoints": [
    {
      "id": 1,
      "x": -9465.5,
      "y": 62.8,
      "z": 56.2,
      "type": "path",
      "note": "Start near Goldshire"
    },
    {
      "id": 2,
      "x": -9502.3,
      "y": 58.1,
      "z": 102.7,
      "type": "hotspot",
      "radius": 30,
      "linger_time": 5,
      "note": "Copper spawn cluster"
    },
    {
      "id": 3,
      "x": -9550.0,
      "y": 60.0,
      "z": 150.3,
      "type": "path"
    }
  ],
  
  "blackspots": [
    {
      "x": -9480.0,
      "y": 55.0,
      "z": 80.0,
      "radius": 15,
      "reason": "Elite mob patrol"
    }
  ],
  
  "vendors": [
    {
      "name": "Tomas",
      "npc_id": 295,
      "x": -9456.0,
      "y": 62.0,
      "z": 42.0,
      "type": "repair"
    }
  ],
  
  "mailboxes": [
    {
      "x": -9460.0,
      "y": 62.0,
      "z": 45.0,
      "note": "Goldshire mailbox"
    }
  ]
}
```

### Waypoint Types

| Type | Description |
|------|-------------|
| `path` | Standard navigation waypoint - move through it |
| `hotspot` | Linger here and scan for nodes within radius |
| `vendor` | Vendor location for selling/repairs |
| `mailbox` | Mailbox for sending items |
| `safe` | Safe spot to AFK/wait (no mobs) |
| `flight` | Flight path location |

### Directory Structure

```
scripts_data/
└── gatherbuddy/
    ├── profiles/
    │   ├── retail/
    │   │   ├── eastern_kingdoms/
    │   │   │   ├── elwynn_copper_peacebloom.json
    │   │   │   └── westfall_iron_briarthorn.json
    │   │   └── kalimdor/
    │   │       └── darkshore_copper_silverleaf.json
    │   └── classic/
    │       └── ...
    ├── settings.json
    ├── statistics.json
    └── blacklist.json
```

---

## Module Design

### 1. ProfileManager

```lua
---@class ProfileManager
-- Responsible for loading, validating, and managing gathering profiles
-- 
-- Events Published:
--   PROFILE_LOADED, PROFILE_UNLOADED, WAYPOINT_REACHED, ROUTE_COMPLETED
--
-- Events Subscribed:
--   BOT_START, BOT_STOP
--
-- Key Methods:
--   load_profile(path)      -- Load profile from file
--   validate_profile(data)  -- Validate profile structure
--   get_current_waypoint()  -- Get current target waypoint
--   advance_waypoint()      -- Move to next waypoint
--   get_nearest_waypoint()  -- Find closest waypoint to player
--   is_in_blackspot(pos)    -- Check if position is blacklisted
```

### 2. NodeScanner

```lua
---@class NodeScanner
-- Scans for gathering nodes using object manager
--
-- Events Published:
--   NODE_DETECTED, NODE_LOST, NODE_BLACKLISTED, SCAN_COMPLETE
--
-- Events Subscribed:
--   TICK, WAYPOINT_REACHED
--
-- Key Methods:
--   scan()                    -- Perform node scan
--   get_best_node()           -- Get highest priority node
--   is_node_valid(obj)        -- Validate node is gatherable
--   blacklist_node(obj, ttl)  -- Temporarily blacklist node
--   
-- Node Detection Logic:
--   1. Get all visible objects
--   2. Filter by: can_be_looted() or can_be_used()
--   3. Filter by: name matches herb/ore patterns
--   4. Filter by: within search radius
--   5. Filter by: not in blackspot
--   6. Filter by: not blacklisted
--   7. Sort by distance
```

### 3. GatherModule

```lua
---@class GatherModule
-- Handles the actual gathering interaction
--
-- Events Published:
--   GATHER_START, GATHER_SUCCESS, GATHER_FAILED, 
--   GATHER_INTERRUPTED, LOOT_WINDOW_OPENED, LOOT_WINDOW_CLOSED
--
-- Events Subscribed:
--   NODE_DETECTED, MOVEMENT_COMPLETED
--
-- Key Methods:
--   start_gather(node)    -- Begin gathering node
--   process_loot()        -- Handle loot window
--   is_gathering()        -- Check if currently gathering
--   cancel_gather()       -- Cancel current gather
--
-- Gathering Flow:
--   1. Face node (core.input.look_at)
--   2. Dismount if mounted
--   3. Use object (core.input.use_object)
--   4. Wait for cast/channel
--   5. Handle loot window
--   6. Blacklist node temporarily
```

### 4. MovementModule

```lua
---@class MovementModule
-- Handles all movement using simple_movement + navigation service
--
-- Events Published:
--   MOVEMENT_STARTED, MOVEMENT_COMPLETED, MOVEMENT_STUCK, 
--   PATH_REQUESTED, PATH_RECEIVED
--
-- Events Subscribed:
--   MOVE_TO, NODE_DETECTED, WAYPOINT_REACHED
--
-- Key Methods:
--   move_to(position)          -- Move to position
--   navigate_to(position)      -- Request path from nav service
--   stop()                     -- Stop movement
--   is_moving()                -- Check movement state
--   get_stuck_count()          -- Get consecutive stuck count
--   
-- Stuck Detection:
--   - Track position every N seconds
--   - If distance moved < threshold, increment stuck counter
--   - After N stuck counts, try unstuck behaviors:
--     1. Jump
--     2. Strafe random direction
--     3. Move backward
--     4. Request new path
--     5. Skip to next waypoint
```

### 5. MountModule

```lua
---@class MountModule
-- Handles mounting/dismounting logic
--
-- Events Published:
--   MOUNT_STARTED, MOUNT_COMPLETED, MOUNT_FAILED, DISMOUNT_REQUESTED
--
-- Events Subscribed:
--   MOVEMENT_STARTED, GATHER_START, COMBAT_ENTERED
--
-- Key Methods:
--   mount()                -- Start mounting
--   dismount()             -- Dismount
--   should_mount(distance) -- Check if should mount for distance
--   is_mounted()           -- Check mount status
--   get_preferred_mount()  -- Get mount index to use
--
-- Mount Logic:
--   - Mount if travel distance > threshold (default 40 yards)
--   - Dismount automatically when approaching node
--   - Handle mount cast interrupts
--   - Support ground vs flying mount selection
```

### 6. SafetyModule

```lua
---@class SafetyModule
-- Handles combat detection, death, and threat avoidance
--
-- Events Published:
--   ENEMY_DETECTED, COMBAT_ENTERED, COMBAT_EXITED,
--   PLAYER_DIED, PLAYER_RESURRECTED, THREAT_LEVEL_CHANGED
--
-- Events Subscribed:
--   TICK, GATHER_START
--
-- Key Methods:
--   scan_threats(radius)     -- Scan for nearby enemies
--   get_threat_level()       -- Get current threat level (0-3)
--   is_safe_to_gather()      -- Check if safe to gather
--   handle_death()           -- Handle player death
--   handle_corpse_run()      -- Navigate to corpse
--
-- Threat Levels:
--   0 = Safe (no enemies)
--   1 = Caution (enemies nearby but not aggro)
--   2 = Danger (enemies very close)
--   3 = Combat (in combat)
```

### 7. InventoryModule

```lua
---@class InventoryModule
-- Tracks inventory state and bag space
--
-- Events Published:
--   BAGS_FULL, ITEM_LOOTED
--
-- Events Subscribed:
--   LOOT_WINDOW_CLOSED, TICK
--
-- Key Methods:
--   get_free_slots()       -- Count free bag slots
--   is_bags_full()         -- Check if bags are full
--   get_item_count(id)     -- Count specific item
--   should_vendor()        -- Check if should go vendor
```

### 8. StatisticsModule

```lua
---@class StatisticsModule  
-- Tracks gathering statistics and session data
--
-- Events Subscribed:
--   GATHER_SUCCESS, GATHER_FAILED, ITEM_LOOTED, BOT_START, BOT_STOP
--
-- Tracked Stats:
--   - Session start time
--   - Total nodes gathered
--   - Nodes per hour
--   - Items looted (by type)
--   - Distance traveled
--   - Deaths
--   - Time spent in combat
--   - Gold earned (estimated)
```

---

## Feature Suggestions

### Core Features (MVP)

1. **Profile System**
   - Load/save JSON profiles
   - Profile validation
   - Multiple profiles per zone

2. **Node Detection**
   - Herb detection
   - Ore detection
   - Configurable search radius
   - Node name filtering

3. **Navigation**
   - Integration with navigation service
   - Waypoint following
   - Hotspot lingering
   - Blackspot avoidance

4. **Gathering**
   - Automatic node interaction
   - Loot handling
   - Cast bar detection
   - Interrupt recovery

5. **Safety**
   - Enemy detection
   - Combat state handling
   - Death recovery (corpse run)

6. **Mount Handling**
   - Auto-mount for travel
   - Auto-dismount for gathering
   - Mount preference settings

### Enhanced Features (Phase 2)

7. **Smart Pathing**
   - Dynamic route deviation for nearby nodes
   - Return to route after detour
   - Maximum detour distance setting

8. **Vendor Integration**
   - Auto-vendor when bags full
   - Repair support
   - Configurable items to sell

9. **Mailbox Integration**
   - Auto-mail items to alt
   - Keep X of item, mail rest

10. **Anti-Detection**
    - Random delays between actions
    - Human-like movement patterns
    - Occasional pauses
    - Varying gather speeds

11. **Multi-Character Support**
    - Per-character settings
    - Skill level tracking
    - Character-specific profiles

12. **Profile Recording**
    - Record mode to create profiles
    - Click-to-add waypoints
    - Auto-detect node locations for hotspots

### Advanced Features (Phase 3)

13. **Competition Handling**
    - Detect other players at nodes
    - Skip contested nodes
    - Optional blacklist players

14. **Flight Support**
    - 3D pathing for flying
    - Altitude management
    - Dragonriding support

15. **Zone Transitions**
    - Multi-zone profiles
    - Flight path usage
    - Portal/teleport handling

16. **Economy Integration**
    - Track item values (AH prices)
    - Prioritize valuable nodes
    - Profit tracking

17. **Fishing Support**
    - Fishing node detection
    - Pool fishing
    - Open water fishing

18. **Treasure/Rare Detection**
    - Detect treasure chests
    - Detect rare mobs
    - Optional engagement

---

## Sylvannas API Usage Map

### Object Detection
```lua
-- Get all game objects
local objects = core.object_manager.get_all_objects()
-- or visible only
local visible = core.object_manager.get_visible_objects()

-- Filter for gatherable nodes
for _, obj in ipairs(objects) do
    if obj:is_valid() and (obj:can_be_looted() or obj:can_be_used()) then
        local name = obj:get_name()
        local pos = obj:get_position()
        -- Check if it's a node we want
    end
end
```

### Node Interaction
```lua
-- Approach and gather
core.input.use_object(node)

-- Wait for loot window
local loot_count = core.game_ui.get_loot_item_count()
if loot_count > 0 then
    for i = 0, loot_count - 1 do
        core.input.loot_item(i)
    end
    core.input.close_loot()
end
```

### Movement
```lua
---@type simple_movement
local movement = require("common/utility/simple_movement")

-- Navigate to position
movement:move_to_position(target_pos)

-- Or use waypoint system
movement:navigate(waypoints)

-- Process each tick
movement:process()
```

### Safety Checks
```lua
---@type unit_helper
local unit_helper = require("common/utility/unit_helper")

-- Get enemies near point
local enemies = unit_helper:get_enemy_list_around(player_pos, 30, true, false, false, false)

-- Check player state
local player = core.object_manager.get_local_player()
local is_dead = player:is_dead()
local is_combat = player:is_in_combat()
local is_mounted = player:is_mounted()
```

### Mount Control
```lua
-- Mount up
core.input.mount(mount_index)

-- Dismount
core.input.dismount()

-- Check state
local player = core.object_manager.get_local_player()
local mounted = player:is_mounted()
```

### File I/O (Profiles)
```lua
-- Read profile
local json_str = core.read_data_file("gatherbuddy/profiles/retail/elwynn.json")

-- Write profile
core.create_data_folder("gatherbuddy/profiles")
core.create_data_file("gatherbuddy/profiles/my_profile.json")
core.write_data_file("gatherbuddy/profiles/my_profile.json", json_content)
```

---

## Settings Schema

```json
{
  "general": {
    "enabled": true,
    "debug_mode": false,
    "log_level": "info"
  },
  
  "movement": {
    "mount_threshold": 40,
    "preferred_mount_index": 1,
    "use_flying": true,
    "stuck_threshold_seconds": 3,
    "stuck_distance_threshold": 2
  },
  
  "gathering": {
    "node_search_radius": 80,
    "max_detour_distance": 100,
    "gather_timeout_seconds": 10,
    "loot_delay_ms": 100
  },
  
  "safety": {
    "enemy_scan_radius": 30,
    "skip_if_enemies_near": true,
    "flee_on_combat": false,
    "min_health_percent": 30
  },
  
  "anti_detection": {
    "enabled": true,
    "min_action_delay_ms": 100,
    "max_action_delay_ms": 500,
    "random_pauses": true,
    "pause_chance": 0.05,
    "pause_duration_min_sec": 2,
    "pause_duration_max_sec": 8
  },
  
  "inventory": {
    "min_free_slots": 2,
    "auto_vendor": false,
    "auto_mail": false,
    "mail_recipient": ""
  },
  
  "ui": {
    "show_overlay": true,
    "show_statistics": true,
    "show_minimap_markers": true
  }
}
```

---

## Implementation Priority

### Phase 1: Core Loop (MVP)
1. EventBus (port from BG_Bot)
2. ProfileManager (JSON loading/validation)
3. NodeScanner (basic detection)
4. MovementModule (simple_movement integration)
5. GatherModule (basic gathering)
6. MountModule (basic mount/dismount)
7. SafetyModule (death handling only)
8. Basic UI (start/stop, profile select)

### Phase 2: Robustness
1. Navigation service integration
2. Stuck detection & recovery
3. Combat handling
4. Enemy avoidance
5. Statistics tracking
6. Settings persistence

### Phase 3: Polish
1. Vendor integration
2. Mailbox integration
3. Profile recording
4. Anti-detection features
5. Advanced UI (statistics, overlay)

---

## Node Name Patterns

### Herbs (Examples)
```lua
local HERB_PATTERNS = {
    -- Classic
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal",
    "Briarthorn", "Stranglekelp", "Bruiseweed", "Wild Steelbloom",
    "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf",
    "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom",
    "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed",
    "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil",
    "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
    -- Retail (partial)
    "Hochenblume", "Saxifrage", "Bubble Poppy",
    -- Add more as needed
}
```

### Ores (Examples)
```lua
local ORE_PATTERNS = {
    -- Classic
    "Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit",
    "Gold Vein", "Mithril Deposit", "Truesilver Deposit",
    "Small Thorium Vein", "Rich Thorium Vein",
    -- Retail (partial)
    "Serevite Deposit", "Draconium Deposit",
    -- Add more as needed
}
```

---

## File Structure

```
SentinelGather/
├── init.lua                    -- Entry point
├── main.lua                    -- Main registration
├── CLAUDE.md                   -- AI guidance
│
├── core/
│   ├── EventBus.lua           -- Event system
│   ├── StateMachine.lua       -- State management
│   ├── Constants.lua          -- Events, states, configs
│   └── BotManager.lua         -- Lifecycle management
│
├── modules/
│   ├── ProfileManager.lua     -- Profile loading
│   ├── NodeScanner.lua        -- Node detection
│   ├── GatherModule.lua       -- Gathering logic
│   ├── MovementModule.lua     -- Movement handling
│   ├── MountModule.lua        -- Mount control
│   ├── SafetyModule.lua       -- Combat/death
│   ├── InventoryModule.lua    -- Bag management
│   └── StatisticsModule.lua   -- Stats tracking
│
├── ui/
│   ├── MainWindow.lua         -- Main control window
│   ├── ProfileSelector.lua    -- Profile dropdown
│   ├── StatisticsPanel.lua    -- Stats display
│   └── SettingsPanel.lua      -- Settings UI
│
├── data/
│   ├── Herbs.lua              -- Herb name database
│   ├── Ores.lua               -- Ore name database
│   └── NodeDatabase.lua       -- Combined node info
│
└── utils/
    ├── JSON.lua               -- JSON parser
    ├── Logger.lua             -- Logging utility
    └── Timer.lua              -- Timer utilities
```

---

## Next Steps

1. **Review this design** - Confirm architecture decisions
2. **Port EventBus** - Adapt from BG_Bot
3. **Implement JSON parser** - For profile loading
4. **Create ProfileManager** - Load and validate profiles
5. **Implement NodeScanner** - Basic node detection
6. **Create test profile** - Simple route for testing
7. **Build core loop** - State machine + tick processing
8. **Add UI** - Basic start/stop controls
