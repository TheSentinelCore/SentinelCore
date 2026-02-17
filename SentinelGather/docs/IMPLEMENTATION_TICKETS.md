# SentinelGather - Implementation Tickets

**Version:** 1.0  
**Date:** January 31, 2025  
**Total Estimated Effort:** 14 days  

---

## Ticket Format

Each ticket follows this format:
- **ID**: Unique identifier (SG-XXX)
- **Title**: Brief description
- **Priority**: P0 (Critical), P1 (High), P2 (Medium), P3 (Low)
- **Estimate**: Story points or hours
- **Dependencies**: Other tickets that must complete first
- **Acceptance Criteria**: How to verify completion

---

## Epic 1: Foundation (Days 1-2)

### SG-001: Implement JSON Parser
**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** None  
**File:** `utils/JSON.lua`

**Description:**
Create a pure-Lua JSON parser/encoder that doesn't rely on external libraries.

**Acceptance Criteria:**
- [ ] `JSON.decode(string)` parses valid JSON into Lua tables
- [ ] `JSON.encode(table)` converts Lua tables to JSON strings
- [ ] Handles strings, numbers, booleans, null, arrays, objects
- [ ] Handles escape sequences in strings (`\n`, `\t`, `\"`, `\\`)
- [ ] Throws descriptive errors for invalid JSON
- [ ] Unit tests pass

**Implementation Notes:**
- Use recursive descent parser
- Handle both array and object table types in encode

---

### SG-002: Implement Logger Utility
**Priority:** P0  
**Estimate:** 1 hour  
**Dependencies:** None  
**File:** `utils/Logger.lua`

**Description:**
Create a logging wrapper around `core.log` with log levels and formatting.

**Acceptance Criteria:**
- [ ] Supports log levels: DEBUG, INFO, WARNING, ERROR
- [ ] Configurable minimum log level
- [ ] Formats messages with timestamp and module name
- [ ] `Logger:debug()`, `Logger:info()`, `Logger:warn()`, `Logger:error()` methods
- [ ] Can create named logger instances per module

**Implementation Notes:**
```lua
local log = Logger:new("NodeScanner")
log:debug("Scanning...")
-- Output: [12.345] [DEBUG] [NodeScanner] Scanning...
```

---

### SG-003: Implement Helper Utilities
**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** None  
**File:** `utils/Helpers.lua`

**Description:**
Create utility functions used across the codebase.

**Acceptance Criteria:**
- [ ] `gaussian_random(min, max)` - Gaussian distribution random
- [ ] `add_variance(value, percent)` - Add ±percent variance
- [ ] `distance_3d(pos1, pos2)` - Calculate 3D distance
- [ ] `distance_2d(pos1, pos2)` - Calculate 2D distance (ignoring Y)
- [ ] `lerp(a, b, t)` - Linear interpolation
- [ ] `clamp(value, min, max)` - Clamp value to range
- [ ] `deep_copy(table)` - Deep copy a table
- [ ] `table_contains(table, value)` - Check if table contains value

**Implementation Notes:**
- Use Box-Muller transform for gaussian random

---

### SG-004: Define Constants
**Priority:** P0  
**Estimate:** 1 hour  
**Dependencies:** None  
**File:** `core/Constants.lua`

**Description:**
Define all constants used throughout the application.

**Acceptance Criteria:**
- [ ] `STATES` table with all state names
- [ ] `EVENTS` table with all event names
- [ ] `GATHER_TYPES` - herb, ore
- [ ] `WAYPOINT_TYPES` - path, hotspot, vendor, mailbox, safe
- [ ] `THREAT_LEVELS` - safe, caution, danger, combat
- [ ] `DEFAULT_SETTINGS` - All default configuration values
- [ ] All constants are immutable (return frozen tables)

---

### SG-005: Implement EventBus
**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** SG-002  
**File:** `core/EventBus.lua`

**Description:**
Implement pub/sub event system for inter-module communication.

**Acceptance Criteria:**
- [ ] `subscribe(event, callback, priority?, once?)` returns subscription ID
- [ ] `unsubscribe(subscription_id)` removes subscription
- [ ] `publish(event, data)` calls all subscribers
- [ ] Subscribers called in priority order (lower = first)
- [ ] `once()` shorthand for one-time subscriptions
- [ ] Errors in callbacks don't break other subscribers
- [ ] Callbacks receive data parameter
- [ ] Can have multiple subscribers per event
- [ ] Unit tests pass

**Implementation Notes:**
- Store subscriptions by event name for O(1) lookup
- Wrap callback calls in pcall for error isolation

---

### SG-006: Implement StateMachine
**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** SG-004, SG-005  
**File:** `core/StateMachine.lua`

**Description:**
Implement finite state machine with transition validation.

**Acceptance Criteria:**
- [ ] `new(event_bus, initial_state)` constructor
- [ ] `transition(new_state, data?)` changes state if valid
- [ ] `can_transition(new_state)` checks if transition is valid
- [ ] `get_state()` returns current state
- [ ] `get_context()` returns state context (entered_at, data, previous)
- [ ] `get_time_in_state()` returns seconds in current state
- [ ] Publishes STATE_CHANGED event on transition
- [ ] Invalid transitions are rejected with warning log
- [ ] All valid transitions from ADD are implemented
- [ ] Unit tests pass

---

## Epic 2: Core Systems (Days 3-5)

### SG-007: Implement Node Patterns Database
**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** None  
**File:** `data/Nodes.lua`

**Description:**
Create database of herb and ore node name patterns.

**Acceptance Criteria:**
- [ ] `HERBS` table with all herb names (Classic, TBC, WotLK, Retail)
- [ ] `ORES` table with all ore names
- [ ] `is_herb(name)` function returns boolean
- [ ] `is_ore(name)` function returns boolean
- [ ] `get_node_type(name)` returns "herb", "ore", or nil
- [ ] Patterns use partial matching (contains, not exact)
- [ ] At least 50 herbs and 30 ores defined

---

### SG-008: Implement Settings System
**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** SG-001, SG-004  
**File:** `data/Settings.lua`

**Description:**
Settings management with persistence to JSON file.

**Acceptance Criteria:**
- [ ] `load()` loads settings from `scripts_data/sentinel_gather/settings.json`
- [ ] `save()` saves current settings to file
- [ ] `get(path)` gets nested setting (e.g., "movement.mount_threshold")
- [ ] `set(path, value)` sets nested setting
- [ ] `reset()` resets to DEFAULT_SETTINGS
- [ ] Creates settings file if doesn't exist
- [ ] Validates settings against schema
- [ ] Settings survive session restart

---

### SG-009: Implement ProfileManager
**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** SG-001, SG-005  
**File:** `modules/ProfileManager.lua`

**Description:**
Load, validate, and manage gathering profiles.

**Acceptance Criteria:**
- [ ] `load_profile(path)` loads and validates profile JSON
- [ ] `validate_profile(data)` returns (valid, errors[])
- [ ] `get_current_waypoint()` returns current waypoint
- [ ] `advance_waypoint()` moves to next waypoint
- [ ] `get_nearest_waypoint(pos)` finds closest waypoint
- [ ] `is_in_blackspot(pos)` checks if position is blacklisted
- [ ] `list_available_profiles()` scans profiles directory
- [ ] `unload_profile()` clears current profile
- [ ] Publishes PROFILE_LOADED, PROFILE_LOAD_FAILED events
- [ ] Publishes WAYPOINT_REACHED, HOTSPOT_ENTERED events
- [ ] Handles loop setting (restart at beginning)
- [ ] Validates required fields: version, waypoints, map_id

---

### SG-010: Implement NavigationClient
**Priority:** P0  
**Estimate:** 3 hours  
**Dependencies:** SG-001, SG-005  
**File:** `modules/NavigationClient.lua`

**Description:**
HTTP client for communicating with navigation service.

**Acceptance Criteria:**
- [ ] `find_path(start, end, callback)` requests path
- [ ] `get_height(x, z, callback)` gets terrain height
- [ ] Handles HTTP errors gracefully
- [ ] Implements retry logic (3 retries, 500ms delay)
- [ ] Parses JSON response into vec3 array
- [ ] Publishes PATH_REQUEST, PATH_RECEIVED, PATH_FAILED events
- [ ] Configurable base URL (default localhost:3000)
- [ ] Timeout handling

---

### SG-011: Implement BotManager
**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** SG-005, SG-006, SG-009  
**File:** `core/BotManager.lua`

**Description:**
Central manager that coordinates all modules and tick loop.

**Acceptance Criteria:**
- [ ] `new()` initializes all subsystems
- [ ] `start()` begins bot operation
- [ ] `stop()` stops bot cleanly
- [ ] `pause()` / `resume()` toggle pause state
- [ ] `update(dt)` main tick function
- [ ] `render()` graphics update function
- [ ] Loads modules in correct dependency order
- [ ] Publishes BOT_START, BOT_STOP, TICK events
- [ ] Handles state-based update routing
- [ ] Error handling doesn't crash entire bot

---

## Epic 3: Movement (Days 6-7)

### SG-012: Implement MovementModule
**Priority:** P0  
**Estimate:** 5 hours  
**Dependencies:** SG-005, SG-010  
**File:** `modules/MovementModule.lua`

**Description:**
Handle all movement using simple_movement and nav service.

**Acceptance Criteria:**
- [ ] `move_to(position, use_pathfinding)` starts movement
- [ ] `stop()` stops all movement
- [ ] `is_moving()` returns current movement state
- [ ] Uses `simple_movement` module for actual movement
- [ ] Requests paths from NavigationClient when needed
- [ ] Implements path deviation for anti-detection (5-15%)
- [ ] Publishes MOVEMENT_STARTED, MOVEMENT_COMPLETED events
- [ ] Subscribes to MOVE_TO_POSITION, MOVE_TO_WAYPOINT events
- [ ] Handles path received callback properly
- [ ] Integrates with waypoint tolerance setting

---

### SG-013: Implement Stuck Detection
**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** SG-012  
**File:** `modules/MovementModule.lua` (extension)

**Description:**
Detect and recover from stuck situations.

**Acceptance Criteria:**
- [ ] `check_stuck()` detects lack of movement progress
- [ ] Checks every 2 seconds, requires 1.5 yard minimum movement
- [ ] `attempt_unstuck()` tries recovery strategies in order
- [ ] Strategies: jump, strafe left, strafe right, backward, repath, skip
- [ ] Publishes STUCK_DETECTED, UNSTUCK_ATTEMPT events
- [ ] Max 5 attempts before giving up
- [ ] Resets stuck counter on successful movement
- [ ] Transitions to STUCK state when detected

---

## Epic 4: Gathering (Days 8-10)

### SG-014: Implement NodeScanner
**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** SG-005, SG-007, SG-009  
**File:** `modules/NodeScanner.lua`

**Description:**
Detect gatherable nodes in the game world.

**Acceptance Criteria:**
- [ ] `scan()` returns array of detected nodes
- [ ] Filters by `can_be_looted()` or `can_be_used()`
- [ ] Matches names against herb/ore patterns
- [ ] Filters by search radius (from profile settings)
- [ ] Filters by blackspot exclusion
- [ ] Maintains temporary blacklist for gathered nodes
- [ ] `get_best_node()` returns highest priority candidate
- [ ] `blacklist_node(obj, duration)` adds to blacklist
- [ ] `is_blacklisted(obj)` checks blacklist
- [ ] Publishes NODE_DETECTED, NODE_LOST, NO_NODES_FOUND events
- [ ] Sorts candidates with randomization for anti-detection

---

### SG-015: Implement GatherModule
**Priority:** P0  
**Estimate:** 5 hours  
**Dependencies:** SG-005, SG-014  
**File:** `modules/GatherModule.lua`

**Description:**
Handle node interaction and loot collection.

**Acceptance Criteria:**
- [ ] `start_gather(node)` begins gathering process
- [ ] Internal state machine: FACING → DISMOUNTING → INTERACTING → CASTING → LOOTING
- [ ] Faces node before interacting
- [ ] Dismounts if mounted
- [ ] Uses `core.input.use_object()` to interact
- [ ] Detects cast completion via `is_casting_spell()`
- [ ] Processes loot window with `get_loot_item_count()`, `loot_item()`
- [ ] Closes loot window when done
- [ ] Handles timeout (configurable, default 10s)
- [ ] Publishes GATHER_START, GATHER_SUCCESS, GATHER_FAILED events
- [ ] Publishes LOOT_OPENED, LOOT_ITEM, LOOT_CLOSED events
- [ ] Blacklists node after gather (success or fail)

---

### SG-016: Implement MountModule
**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** SG-005  
**File:** `modules/MountModule.lua`

**Description:**
Handle mounting and dismounting logic.

**Acceptance Criteria:**
- [ ] `mount()` starts mount process
- [ ] `dismount()` dismounts immediately
- [ ] `should_mount(distance)` checks if should mount for distance
- [ ] `is_mounted()` returns current mount state
- [ ] Uses configurable mount threshold (default 40 yards)
- [ ] Uses configurable mount index
- [ ] Detects mount cast completion
- [ ] Handles mount interruption (combat, etc.)
- [ ] Publishes MOUNT_START, MOUNT_SUCCESS, MOUNT_FAILED events
- [ ] Subscribes to DISMOUNT_REQUEST event

---

## Epic 5: Safety (Days 11-12)

### SG-017: Implement SafetyModule - Enemy Detection
**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** SG-005  
**File:** `modules/SafetyModule.lua`

**Description:**
Monitor for nearby enemies and threat levels.

**Acceptance Criteria:**
- [ ] `scan_threats()` returns nearby enemy list
- [ ] Uses `unit_helper:get_enemy_list_around()`
- [ ] `calculate_threat_level()` returns 0-3 threat level
- [ ] `is_safe_to_gather()` combines threat + distance check
- [ ] Configurable enemy detection radius
- [ ] Publishes ENEMY_DETECTED, ENEMY_LOST events
- [ ] Publishes THREAT_LEVEL_CHANGED when level changes
- [ ] Tracks nearest enemy distance

---

### SG-018: Implement SafetyModule - Combat Handling
**Priority:** P1  
**Estimate:** 3 hours  
**Dependencies:** SG-017  
**File:** `modules/SafetyModule.lua` (extension)

**Description:**
Handle combat state transitions.

**Acceptance Criteria:**
- [ ] Detects combat enter via `is_in_combat()`
- [ ] Detects combat exit
- [ ] Publishes COMBAT_ENTER, COMBAT_EXIT events
- [ ] Tracks health for emergency flee
- [ ] Publishes HEALTH_LOW when below threshold (30%)
- [ ] Stores pre-combat state for return after combat
- [ ] Supports flee behavior (run to safe waypoint)

---

### SG-019: Implement SafetyModule - Death Recovery
**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** SG-017, SG-012  
**File:** `modules/SafetyModule.lua` (extension)

**Description:**
Handle player death and corpse run.

**Acceptance Criteria:**
- [ ] Detects death via `is_dead()`
- [ ] Configurable delay before spirit release (appear AFK)
- [ ] Uses `core.input.release_spirit()` to release
- [ ] Detects ghost state via `is_ghost()`
- [ ] Stores corpse position at death
- [ ] Navigates ghost to corpse using MovementModule
- [ ] Uses `core.input.resurrect_corpse()` to resurrect
- [ ] Resumes from nearest waypoint after resurrection
- [ ] Publishes PLAYER_DIED, SPIRIT_RELEASED, RESURRECTED events

---

### SG-020: Implement InventoryModule
**Priority:** P2  
**Estimate:** 2 hours  
**Dependencies:** SG-005  
**File:** `modules/InventoryModule.lua`

**Description:**
Track inventory and bag space.

**Acceptance Criteria:**
- [ ] `get_free_slots()` counts empty bag slots
- [ ] `is_bags_full()` returns true if below threshold
- [ ] Uses `core.inventory.get_items_in_bag()` for each bag
- [ ] Configurable minimum free slots threshold (default 2)
- [ ] Publishes BAGS_FULL when threshold reached
- [ ] Publishes BAGS_UPDATED periodically
- [ ] Tracks items added via LOOT_ITEM events

---

## Epic 6: UI & Polish (Days 13-14)

### SG-021: Implement Main Control Window
**Priority:** P0  
**Estimate:** 4 hours  
**Dependencies:** SG-011  
**File:** `ui/MainWindow.lua`

**Description:**
Create control panel UI for bot operation.

**Acceptance Criteria:**
- [ ] Renders in `on_render_menu_callback`
- [ ] Start/Stop button
- [ ] Pause/Resume button
- [ ] Profile dropdown selector
- [ ] Current state display
- [ ] Current waypoint display
- [ ] Nodes gathered counter
- [ ] Session time display
- [ ] Error/warning message area
- [ ] Collapsible/minimizable window

---

### SG-022: Implement Statistics Display
**Priority:** P2  
**Estimate:** 2 hours  
**Dependencies:** SG-021  
**File:** `ui/MainWindow.lua` (extension)

**Description:**
Add statistics panel to UI.

**Acceptance Criteria:**
- [ ] Total nodes gathered (session)
- [ ] Nodes per hour calculation
- [ ] Distance traveled
- [ ] Deaths this session
- [ ] Time in each state (pie chart optional)
- [ ] Items looted by name

---

### SG-023: Implement Random Pause System
**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** SG-003, SG-011  
**File:** `core/BotManager.lua` (extension)

**Description:**
Add human-like random pauses during operation.

**Acceptance Criteria:**
- [ ] Random pauses occur every 30-90 seconds
- [ ] Pause duration 2-8 seconds (gaussian)
- [ ] Configurable pause chance (default 3%)
- [ ] Pauses movement and actions
- [ ] Doesn't pause during critical operations (gathering cast)
- [ ] Visual indicator in UI when paused

---

### SG-024: Implement Jump System
**Priority:** P2  
**Estimate:** 1 hour  
**Dependencies:** SG-012  
**File:** `modules/MovementModule.lua` (extension)

**Description:**
Add random jumps during movement.

**Acceptance Criteria:**
- [ ] Random jumps every 45-120 seconds while moving
- [ ] Uses `core.input.jump()`
- [ ] Configurable via settings
- [ ] Doesn't jump during gathering or mounting

---

### SG-025: Create Entry Points
**Priority:** P0  
**Estimate:** 2 hours  
**Dependencies:** All modules  
**Files:** `init.lua`, `main.lua`

**Description:**
Create the entry point files that wire everything together.

**Acceptance Criteria:**
- [ ] `init.lua` is the Sylvannas entry point
- [ ] `main.lua` loads all modules in order
- [ ] Registers `on_update_callback` for tick loop
- [ ] Registers `on_render_callback` for graphics
- [ ] Registers `on_render_menu_callback` for UI
- [ ] Proper error handling for missing modules
- [ ] Clean startup logging

---

### SG-026: Create Example Profiles
**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** SG-009  
**Files:** `scripts_data/sentinel_gather/profiles/`

**Description:**
Create sample profiles for testing.

**Acceptance Criteria:**
- [ ] Elwynn Forest - Copper/Peacebloom route
- [ ] Durotar - Copper/Peacebloom route  
- [ ] At least 10 waypoints each
- [ ] At least 2 hotspots each
- [ ] At least 1 blackspot each
- [ ] Valid JSON that passes validation
- [ ] Includes all required fields

---

### SG-027: Documentation & README
**Priority:** P1  
**Estimate:** 2 hours  
**Dependencies:** All  
**Files:** `README.md`, `CHANGELOG.md`

**Description:**
Create user documentation.

**Acceptance Criteria:**
- [ ] README with installation instructions
- [ ] Quick start guide
- [ ] Profile creation guide
- [ ] Settings reference
- [ ] Troubleshooting section
- [ ] CHANGELOG with version history

---

## Dependency Graph

```
SG-001 (JSON) ─────────────────────────────────────────┐
SG-002 (Logger) ───────────────────────────────────────┤
SG-003 (Helpers) ──────────────────────────────────────┤
SG-004 (Constants) ────────────────────────────────────┤
                                                       ▼
                                              SG-005 (EventBus)
                                                       │
                    ┌──────────────────┬───────────────┼───────────────┬──────────────────┐
                    ▼                  ▼               ▼               ▼                  ▼
            SG-006 (StateMachine) SG-007 (Nodes) SG-008 (Settings) SG-010 (NavClient) SG-014 (Scanner)
                    │                                  │               │                  │
                    ▼                                  ▼               ▼                  ▼
            SG-011 (BotManager) ◀────────────── SG-009 (Profile)     SG-012 (Movement)  SG-015 (Gather)
                    │                                                  │                  │
                    ▼                                                  ▼                  ▼
            SG-021 (UI) ◀─────────────────────────────────── SG-013 (Stuck) ◀─── SG-016 (Mount)
                    │
                    ▼
            SG-022 (Stats), SG-023 (Pause), SG-024 (Jump)
                    │
                    ▼
            SG-025 (Entry Points)
                    │
                    ▼
            SG-026 (Profiles), SG-027 (Docs)
```

---

## Sprint Planning

### Sprint 1 (Days 1-5): Foundation + Core
| Ticket | Points | Assignee |
|--------|--------|----------|
| SG-001 | 2 | - |
| SG-002 | 1 | - |
| SG-003 | 2 | - |
| SG-004 | 1 | - |
| SG-005 | 3 | - |
| SG-006 | 3 | - |
| SG-007 | 2 | - |
| SG-008 | 2 | - |
| SG-009 | 4 | - |
| SG-010 | 3 | - |
| SG-011 | 4 | - |
| **Total** | **27** | |

### Sprint 2 (Days 6-10): Movement + Gathering
| Ticket | Points | Assignee |
|--------|--------|----------|
| SG-012 | 5 | - |
| SG-013 | 3 | - |
| SG-014 | 4 | - |
| SG-015 | 5 | - |
| SG-016 | 3 | - |
| **Total** | **20** | |

### Sprint 3 (Days 11-14): Safety + Polish
| Ticket | Points | Assignee |
|--------|--------|----------|
| SG-017 | 3 | - |
| SG-018 | 3 | - |
| SG-019 | 4 | - |
| SG-020 | 2 | - |
| SG-021 | 4 | - |
| SG-022 | 2 | - |
| SG-023 | 2 | - |
| SG-024 | 1 | - |
| SG-025 | 2 | - |
| SG-026 | 2 | - |
| SG-027 | 2 | - |
| **Total** | **27** | |

---

## Verification Checklist

After each ticket, verify:
- [ ] Code follows module template pattern
- [ ] No WoW Lua API calls (grep test)
- [ ] All game_objects validated with is_valid()
- [ ] get_local_player() returns nil-checked
- [ ] Events use correct names from Constants
- [ ] Error handling with pcall where needed
- [ ] Logging at appropriate levels
- [ ] Module cleanup in destroy() method

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-31 | Alex | Initial draft |
