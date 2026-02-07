# GatherBuddy - Technical Design Document (TDD)

**Version:** 1.0  
**Date:** January 31, 2025  
**Author:** Alex  
**Status:** Draft  

---

## 1. Introduction

This document provides detailed technical specifications for implementing GatherBuddy. It covers data structures, algorithms, API contracts, and implementation details.

---

## 2. Core Systems Implementation

### 2.1 EventBus

#### 2.1.1 Data Structures

```lua
---@class Subscription
---@field id number Unique subscription ID
---@field event string Event name
---@field callback function Callback function
---@field priority number Execution priority (lower = first)
---@field once boolean If true, unsubscribe after first call

---@class EventBus
---@field private _subscriptions table<string, Subscription[]>
---@field private _next_id number
```

#### 2.1.2 Implementation

```lua
local EventBus = {}
EventBus.__index = EventBus

function EventBus:new()
    local instance = setmetatable({}, EventBus)
    instance._subscriptions = {}
    instance._next_id = 1
    return instance
end

---@param event string
---@param callback function
---@param priority? number Default 100
---@param once? boolean Default false
---@return number subscription_id
function EventBus:subscribe(event, callback, priority, once)
    if not self._subscriptions[event] then
        self._subscriptions[event] = {}
    end
    
    local id = self._next_id
    self._next_id = self._next_id + 1
    
    local subscription = {
        id = id,
        event = event,
        callback = callback,
        priority = priority or 100,
        once = once or false
    }
    
    table.insert(self._subscriptions[event], subscription)
    
    -- Sort by priority
    table.sort(self._subscriptions[event], function(a, b)
        return a.priority < b.priority
    end)
    
    return id
end

---@param subscription_id number
function EventBus:unsubscribe(subscription_id)
    for event, subs in pairs(self._subscriptions) do
        for i, sub in ipairs(subs) do
            if sub.id == subscription_id then
                table.remove(subs, i)
                return true
            end
        end
    end
    return false
end

---@param event string
---@param data? table
function EventBus:publish(event, data)
    local subs = self._subscriptions[event]
    if not subs then return end
    
    local to_remove = {}
    
    for i, sub in ipairs(subs) do
        local success, err = pcall(sub.callback, data)
        if not success then
            core.log_error("[EventBus] Error in " .. event .. ": " .. tostring(err))
        end
        
        if sub.once then
            table.insert(to_remove, i)
        end
    end
    
    -- Remove one-time subscriptions (reverse order)
    for i = #to_remove, 1, -1 do
        table.remove(subs, to_remove[i])
    end
end

---@param event string
---@param callback function
---@return number subscription_id
function EventBus:once(event, callback)
    return self:subscribe(event, callback, 100, true)
end

return EventBus
```

### 2.2 StateMachine

#### 2.2.1 Data Structures

```lua
---@class StateContext
---@field entered_at number Timestamp when state was entered
---@field data table State-specific data
---@field previous_state string|nil Previous state name

---@class StateMachine
---@field private _current_state string
---@field private _context StateContext
---@field private _transitions table<string, string[]>
---@field private _event_bus EventBus
```

#### 2.2.2 State Transitions Table

```lua
local VALID_TRANSITIONS = {
    [STATES.IDLE] = {
        STATES.LOADING
    },
    [STATES.LOADING] = {
        STATES.IDLE,
        STATES.TRAVELING
    },
    [STATES.TRAVELING] = {
        STATES.IDLE,
        STATES.SCANNING,
        STATES.APPROACHING,
        STATES.MOUNTING,
        STATES.COMBAT,
        STATES.DEAD,
        STATES.STUCK
    },
    [STATES.SCANNING] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.APPROACHING,
        STATES.COMBAT,
        STATES.DEAD
    },
    [STATES.APPROACHING] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.GATHERING,
        STATES.COMBAT,
        STATES.DEAD,
        STATES.STUCK
    },
    [STATES.GATHERING] = {
        STATES.IDLE,
        STATES.LOOTING,
        STATES.TRAVELING,  -- If gather fails
        STATES.COMBAT,
        STATES.DEAD
    },
    [STATES.LOOTING] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.MOUNTING,
        STATES.SCANNING,
        STATES.COMBAT,
        STATES.DEAD
    },
    [STATES.MOUNTING] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.COMBAT,
        STATES.DEAD
    },
    [STATES.COMBAT] = {
        STATES.IDLE,
        STATES.FLEEING,
        STATES.DEAD,
        -- Return to previous state on combat exit
        STATES.TRAVELING,
        STATES.SCANNING,
        STATES.APPROACHING,
        STATES.GATHERING,
        STATES.LOOTING,
        STATES.MOUNTING
    },
    [STATES.FLEEING] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.COMBAT,
        STATES.DEAD
    },
    [STATES.DEAD] = {
        STATES.CORPSE_RUN
    },
    [STATES.CORPSE_RUN] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.DEAD  -- Died again as ghost (shouldn't happen)
    },
    [STATES.STUCK] = {
        STATES.IDLE,
        STATES.TRAVELING,
        STATES.APPROACHING
    }
}
```

#### 2.2.3 Implementation

```lua
function StateMachine:transition(new_state, data)
    if not self:can_transition(new_state) then
        core.log_warning("[StateMachine] Invalid transition: " .. 
            self._current_state .. " -> " .. new_state)
        return false
    end
    
    local previous = self._current_state
    
    self._context = {
        entered_at = core.time(),
        data = data or {},
        previous_state = previous
    }
    
    self._current_state = new_state
    
    self._event_bus:publish(EVENTS.STATE_CHANGED, {
        from = previous,
        to = new_state,
        context = self._context
    })
    
    core.log("[StateMachine] " .. previous .. " -> " .. new_state)
    
    return true
end

function StateMachine:can_transition(new_state)
    local valid = VALID_TRANSITIONS[self._current_state]
    if not valid then return false end
    
    for _, state in ipairs(valid) do
        if state == new_state then
            return true
        end
    end
    
    return false
end

function StateMachine:get_time_in_state()
    return core.time() - self._context.entered_at
end
```

---

## 3. Module Implementations

### 3.1 NodeScanner

#### 3.1.1 Node Detection Algorithm

```lua
function NodeScanner:scan()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return {}
    end
    
    local player_pos = player:get_position()
    if not player_pos then return {} end
    
    local objects = core.object_manager.get_all_objects()
    local candidates = {}
    
    for _, obj in ipairs(objects) do
        -- Validate object
        if not obj or not obj:is_valid() then
            goto continue
        end
        
        -- Check if gatherable
        if not (obj:can_be_looted() or obj:can_be_used()) then
            goto continue
        end
        
        -- Check name pattern
        local name = obj:get_name()
        if not name then goto continue end
        
        local is_node, node_type = self:matches_node_pattern(name)
        if not is_node then goto continue end
        
        -- Check distance
        local pos = obj:get_position()
        if not pos then goto continue end
        
        local distance = self:calculate_distance(player_pos, pos)
        if distance > self._scan_radius then
            goto continue
        end
        
        -- Check blacklist
        if self:is_blacklisted(obj) then
            goto continue
        end
        
        -- Check blackspots
        if self._profile_manager:is_in_blackspot(pos) then
            goto continue
        end
        
        -- Add to candidates
        table.insert(candidates, {
            object = obj,
            name = name,
            type = node_type,
            position = pos,
            distance = distance
        })
        
        ::continue::
    end
    
    -- Sort by distance (with some randomization for anti-detection)
    self:sort_candidates(candidates)
    
    self._detected_nodes = candidates
    return candidates
end

function NodeScanner:matches_node_pattern(name)
    -- Check herbs
    for _, pattern in ipairs(NODE_PATTERNS.HERBS) do
        if name:find(pattern) then
            return true, "herb"
        end
    end
    
    -- Check ores
    for _, pattern in ipairs(NODE_PATTERNS.ORES) do
        if name:find(pattern) then
            return true, "ore"
        end
    end
    
    return false, nil
end

function NodeScanner:sort_candidates(candidates)
    -- Add randomization weight (±15%)
    for _, c in ipairs(candidates) do
        local variance = 1 + (math.random() - 0.5) * 0.3
        c.sort_distance = c.distance * variance
    end
    
    table.sort(candidates, function(a, b)
        return a.sort_distance < b.sort_distance
    end)
end
```

#### 3.1.2 Node Patterns Database

```lua
-- data/Nodes.lua
local NODE_PATTERNS = {
    HERBS = {
        -- Classic Era
        "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal",
        "Briarthorn", "Stranglekelp", "Bruiseweed", "Wild Steelbloom",
        "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf",
        "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom",
        "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed",
        "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil",
        "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
        
        -- TBC
        "Felweed", "Dreaming Glory", "Terocone", "Ragveil",
        "Flame Cap", "Ancient Lichen", "Netherbloom", "Nightmare Vine",
        "Mana Thistle", "Fel Lotus",
        
        -- WotLK
        "Goldclover", "Firethorn", "Tiger Lily", "Talandra's Rose",
        "Adder's Tongue", "Frozen Herb", "Lichbloom", "Icethorn",
        "Frost Lotus",
        
        -- Retail (sample)
        "Hochenblume", "Saxifrage", "Bubble Poppy", "Writhebark",
    },
    
    ORES = {
        -- Classic Era
        "Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit",
        "Gold Vein", "Mithril Deposit", "Truesilver Deposit",
        "Small Thorium Vein", "Rich Thorium Vein", "Dark Iron Deposit",
        
        -- TBC
        "Fel Iron Deposit", "Adamantite Deposit", "Rich Adamantite",
        "Khorium Vein", "Nethercite Deposit",
        
        -- WotLK
        "Cobalt Deposit", "Rich Cobalt", "Saronite Deposit",
        "Rich Saronite", "Titanium Vein",
        
        -- Retail (sample)
        "Serevite Deposit", "Draconium Deposit", "Khaz'gorite Deposit",
    }
}

return NODE_PATTERNS
```

### 3.2 GatherModule

#### 3.2.1 Gathering State Machine

```lua
local GATHER_STATES = {
    NONE = "none",
    FACING = "facing",
    DISMOUNTING = "dismounting",
    APPROACHING_FINAL = "approaching_final",
    INTERACTING = "interacting",
    CASTING = "casting",
    WAITING_LOOT = "waiting_loot",
    LOOTING = "looting",
    COMPLETE = "complete",
    FAILED = "failed"
}

function GatherModule:update(dt)
    if self._gather_state == GATHER_STATES.NONE then
        return
    end
    
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        self:_fail_gather("Invalid player")
        return
    end
    
    -- Check timeout
    if core.time() - self._gather_start_time > self._timeout then
        self:_fail_gather("Timeout")
        return
    end
    
    -- State-specific processing
    if self._gather_state == GATHER_STATES.FACING then
        self:_process_facing(player)
    elseif self._gather_state == GATHER_STATES.DISMOUNTING then
        self:_process_dismounting(player)
    elseif self._gather_state == GATHER_STATES.INTERACTING then
        self:_process_interacting(player)
    elseif self._gather_state == GATHER_STATES.CASTING then
        self:_process_casting(player)
    elseif self._gather_state == GATHER_STATES.WAITING_LOOT then
        self:_process_waiting_loot()
    elseif self._gather_state == GATHER_STATES.LOOTING then
        self:_process_looting()
    end
end

function GatherModule:_process_facing(player)
    local node = self._current_node
    if not node or not node:is_valid() then
        self:_fail_gather("Node despawned")
        return
    end
    
    local node_pos = node:get_position()
    core.input.look_at(node_pos)
    
    -- Wait a small random delay before next step
    self._face_time = self._face_time or core.time()
    if core.time() - self._face_time > gaussian_random(0.1, 0.3) then
        self._face_time = nil
        
        -- Check if mounted
        if player:is_mounted() then
            self._gather_state = GATHER_STATES.DISMOUNTING
            core.input.dismount()
        else
            self._gather_state = GATHER_STATES.INTERACTING
        end
    end
end

function GatherModule:_process_interacting(player)
    local node = self._current_node
    if not node or not node:is_valid() then
        self:_fail_gather("Node despawned")
        return
    end
    
    -- Check distance
    local player_pos = player:get_position()
    local node_pos = node:get_position()
    local distance = player_pos:dist(node_pos)
    
    if distance > 5 then  -- Too far, need to get closer
        self:_fail_gather("Too far from node")
        return
    end
    
    -- Interact with node
    core.input.use_object(node)
    self._interact_time = core.time()
    self._gather_state = GATHER_STATES.CASTING
    
    self._event_bus:publish(EVENTS.GATHER_START, {
        node = node,
        name = node:get_name(),
        position = node_pos
    })
end

function GatherModule:_process_casting(player)
    -- Check if we're casting
    if player:is_casting_spell() or player:is_channelling_spell() then
        -- Still casting, publish progress
        self._event_bus:publish(EVENTS.GATHER_PROGRESS, {
            node = self._current_node,
            elapsed = core.time() - self._interact_time
        })
        return
    end
    
    -- Cast finished, check for loot window
    local wait_start = self._cast_complete_time or core.time()
    self._cast_complete_time = self._cast_complete_time or core.time()
    
    -- Wait up to 0.5s for loot window
    if core.time() - wait_start < 0.5 then
        self._gather_state = GATHER_STATES.WAITING_LOOT
    else
        self:_fail_gather("No loot window appeared")
    end
end

function GatherModule:_process_waiting_loot()
    local loot_count = core.game_ui.get_loot_item_count()
    
    if loot_count > 0 then
        self._gather_state = GATHER_STATES.LOOTING
        self._event_bus:publish(EVENTS.LOOT_OPENED, {
            item_count = loot_count
        })
    elseif core.time() - self._cast_complete_time > 0.5 then
        -- No loot window after 0.5s, consider it a success (already looted)
        self:_complete_gather()
    end
end

function GatherModule:_process_looting()
    local loot_count = core.game_ui.get_loot_item_count()
    
    if loot_count == 0 then
        -- All looted
        core.input.close_loot()
        self._event_bus:publish(EVENTS.LOOT_CLOSED, {})
        self:_complete_gather()
        return
    end
    
    -- Loot with small delays
    self._loot_delay = self._loot_delay or 0
    self._loot_delay = self._loot_delay - core.delta_time()
    
    if self._loot_delay <= 0 then
        -- Loot first item
        local item_id = core.game_ui.get_loot_item_id(0)
        local item_name = core.game_ui.get_loot_item_name(0)
        
        core.input.loot_item(0)
        
        self._event_bus:publish(EVENTS.LOOT_ITEM, {
            item_id = item_id,
            item_name = item_name
        })
        
        -- Random delay before next loot
        self._loot_delay = gaussian_random(0.05, 0.15)
    end
end

function GatherModule:_complete_gather()
    local node = self._current_node
    
    self._event_bus:publish(EVENTS.GATHER_SUCCESS, {
        node = node,
        duration = core.time() - self._gather_start_time
    })
    
    -- Blacklist node temporarily
    if node and node:is_valid() then
        self._node_scanner:blacklist_node(node, 300)  -- 5 minutes
    end
    
    self:_reset_state()
end

function GatherModule:_fail_gather(reason)
    self._event_bus:publish(EVENTS.GATHER_FAILED, {
        node = self._current_node,
        reason = reason
    })
    
    -- Short blacklist for failed nodes
    if self._current_node and self._current_node:is_valid() then
        self._node_scanner:blacklist_node(self._current_node, 60)
    end
    
    self:_reset_state()
end

function GatherModule:_reset_state()
    self._gather_state = GATHER_STATES.NONE
    self._current_node = nil
    self._gather_start_time = nil
    self._face_time = nil
    self._interact_time = nil
    self._cast_complete_time = nil
    self._loot_delay = nil
end
```

### 3.3 MovementModule

#### 3.3.1 Stuck Detection Algorithm

```lua
local STUCK_CONFIG = {
    CHECK_INTERVAL = 2.0,        -- Check every 2 seconds
    MIN_DISTANCE = 1.5,          -- Must move at least 1.5 yards
    MAX_STUCK_COUNT = 5,         -- Max attempts before giving up
    UNSTUCK_STRATEGIES = {
        "jump",
        "strafe_left",
        "strafe_right",
        "backward",
        "repath",
        "skip_waypoint"
    }
}

function MovementModule:check_stuck()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return false end
    
    local current_pos = player:get_position()
    local current_time = core.time()
    
    -- Initialize tracking
    if not self._last_stuck_check_time then
        self._last_stuck_check_time = current_time
        self._last_stuck_check_pos = current_pos
        return false
    end
    
    -- Only check periodically
    if current_time - self._last_stuck_check_time < STUCK_CONFIG.CHECK_INTERVAL then
        return false
    end
    
    -- Calculate distance moved
    local distance_moved = current_pos:dist(self._last_stuck_check_pos)
    
    -- Update tracking
    self._last_stuck_check_time = current_time
    self._last_stuck_check_pos = current_pos
    
    -- Check if stuck
    if distance_moved < STUCK_CONFIG.MIN_DISTANCE and self._movement:is_moving() then
        self._stuck_count = (self._stuck_count or 0) + 1
        
        if self._stuck_count >= 2 then
            self._event_bus:publish(EVENTS.STUCK_DETECTED, {
                position = current_pos,
                stuck_count = self._stuck_count
            })
            return true
        end
    else
        -- Reset if we moved
        self._stuck_count = 0
    end
    
    return false
end

function MovementModule:attempt_unstuck()
    local strategy_index = math.min(self._stuck_count, #STUCK_CONFIG.UNSTUCK_STRATEGIES)
    local strategy = STUCK_CONFIG.UNSTUCK_STRATEGIES[strategy_index]
    
    self._event_bus:publish(EVENTS.UNSTUCK_ATTEMPT, {
        strategy = strategy,
        attempt = self._stuck_count
    })
    
    if strategy == "jump" then
        core.input.jump()
        return self:_wait_and_check(0.5)
        
    elseif strategy == "strafe_left" then
        self._movement:strafe("left")
        return self:_wait_and_check(1.0, function()
            self._movement:strafe(nil)
        end)
        
    elseif strategy == "strafe_right" then
        self._movement:strafe("right")
        return self:_wait_and_check(1.0, function()
            self._movement:strafe(nil)
        end)
        
    elseif strategy == "backward" then
        core.input.move_backward_start()
        return self:_wait_and_check(1.5, function()
            core.input.move_backward_stop()
        end)
        
    elseif strategy == "repath" then
        -- Request new path from nav service
        self:_request_new_path()
        return true
        
    elseif strategy == "skip_waypoint" then
        -- Give up on current waypoint
        self._event_bus:publish(EVENTS.UNSTUCK_FAILED, {
            reason = "Max attempts reached, skipping waypoint"
        })
        self._stuck_count = 0
        return false
    end
    
    return false
end
```

### 3.4 NavigationClient

#### 3.4.1 HTTP Request Handler

```lua
local NAV_CONFIG = {
    BASE_URL = "http://localhost:3000",
    TIMEOUT_MS = 5000,
    RETRY_COUNT = 3,
    RETRY_DELAY_MS = 500
}

function NavigationClient:find_path(start_pos, end_pos, callback)
    local map_id = core.get_map_id()
    
    local url = string.format(
        "%s/api/v1/pathfinding/find_path?map=%d&start_x=%.2f&start_y=%.2f&start_z=%.2f&end_x=%.2f&end_y=%.2f&end_z=%.2f&smooth=true",
        NAV_CONFIG.BASE_URL,
        map_id,
        start_pos.x, start_pos.y, start_pos.z,
        end_pos.x, end_pos.y, end_pos.z
    )
    
    self:_request_with_retry(url, callback, NAV_CONFIG.RETRY_COUNT)
end

function NavigationClient:_request_with_retry(url, callback, retries_left)
    local request_id = self._next_request_id
    self._next_request_id = self._next_request_id + 1
    
    self._pending_requests[request_id] = {
        url = url,
        callback = callback,
        retries_left = retries_left,
        started_at = core.time()
    }
    
    core.http_get(url, function(code, content_type, body, headers)
        local request = self._pending_requests[request_id]
        if not request then return end  -- Cancelled
        
        self._pending_requests[request_id] = nil
        
        if code == 200 and body then
            local success, result = pcall(function()
                return self._json:decode(body)
            end)
            
            if success and result and result.success then
                callback(true, self:_parse_path(result.path))
            else
                self:_handle_failure(request, "Invalid response")
            end
        else
            self:_handle_failure(request, "HTTP " .. tostring(code))
        end
    end)
end

function NavigationClient:_handle_failure(request, reason)
    if request.retries_left > 0 then
        -- Retry after delay
        local retry_url = request.url
        local retry_callback = request.callback
        local retry_count = request.retries_left - 1
        
        -- Schedule retry (using a simple delay mechanism)
        self._retry_queue[#self._retry_queue + 1] = {
            time = core.time() + (NAV_CONFIG.RETRY_DELAY_MS / 1000),
            fn = function()
                self:_request_with_retry(retry_url, retry_callback, retry_count)
            end
        }
    else
        -- All retries exhausted
        request.callback(false, nil, reason)
    end
end

function NavigationClient:_parse_path(raw_path)
    local path = {}
    for _, point in ipairs(raw_path) do
        table.insert(path, vec3.new(point.x, point.y, point.z))
    end
    return path
end
```

---

## 4. Anti-Detection Implementation

### 4.1 Gaussian Random Distribution

```lua
-- utils/Helpers.lua
local Helpers = {}

---@param min number
---@param max number
---@return number
function Helpers.gaussian_random(min, max)
    -- Box-Muller transform for gaussian distribution
    local u1 = math.random()
    local u2 = math.random()
    
    -- Avoid log(0)
    while u1 == 0 do u1 = math.random() end
    
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    
    local mean = (min + max) / 2
    local stddev = (max - min) / 6  -- 99.7% within range
    
    local result = mean + z * stddev
    return math.max(min, math.min(max, result))
end

---@param base_delay number
---@param variance_percent number (0-1)
---@return number
function Helpers.add_variance(base_delay, variance_percent)
    local variance = base_delay * variance_percent
    return Helpers.gaussian_random(base_delay - variance, base_delay + variance)
end

return Helpers
```

### 4.2 Path Deviation

```lua
function MovementModule:apply_path_deviation(path, deviation_percent)
    if #path < 2 then return path end
    
    local deviated_path = {}
    
    -- First and last points remain unchanged
    deviated_path[1] = path[1]
    
    for i = 2, #path - 1 do
        local point = path[i]
        local prev = path[i - 1]
        local next_point = path[i + 1]
        
        -- Calculate perpendicular direction
        local dir = {
            x = next_point.x - prev.x,
            z = next_point.z - prev.z
        }
        local len = math.sqrt(dir.x * dir.x + dir.z * dir.z)
        
        if len > 0.01 then
            -- Perpendicular vector
            local perp = {
                x = -dir.z / len,
                z = dir.x / len
            }
            
            -- Random deviation
            local max_deviation = len * deviation_percent
            local deviation = Helpers.gaussian_random(-max_deviation, max_deviation)
            
            deviated_path[i] = vec3.new(
                point.x + perp.x * deviation,
                point.y,  -- Keep Y unchanged
                point.z + perp.z * deviation
            )
        else
            deviated_path[i] = point
        end
    end
    
    deviated_path[#path] = path[#path]
    
    return deviated_path
end
```

### 4.3 Random Pause System

```lua
local PauseSystem = {}

local PAUSE_CONFIG = {
    MIN_INTERVAL = 30,   -- Minimum seconds between pauses
    MAX_INTERVAL = 90,   -- Maximum seconds between pauses
    MIN_DURATION = 2,    -- Minimum pause duration
    MAX_DURATION = 8,    -- Maximum pause duration
    CHANCE = 0.03        -- 3% chance per check
}

function PauseSystem:new()
    local instance = {
        last_pause_time = 0,
        next_pause_check = 0,
        is_paused = false,
        pause_end_time = 0
    }
    setmetatable(instance, { __index = PauseSystem })
    return instance
end

function PauseSystem:should_pause()
    local now = core.time()
    
    -- Don't pause too frequently
    if now - self.last_pause_time < PAUSE_CONFIG.MIN_INTERVAL then
        return false
    end
    
    -- Check periodically
    if now < self.next_pause_check then
        return false
    end
    
    self.next_pause_check = now + 1  -- Check every second
    
    -- Random chance
    if math.random() < PAUSE_CONFIG.CHANCE then
        self.last_pause_time = now
        return true
    end
    
    return false
end

function PauseSystem:get_pause_duration()
    return Helpers.gaussian_random(
        PAUSE_CONFIG.MIN_DURATION,
        PAUSE_CONFIG.MAX_DURATION
    )
end

return PauseSystem
```

---

## 5. JSON Parser Implementation

```lua
-- utils/JSON.lua
-- Minimal JSON parser for Lua (no external dependencies)

local JSON = {}

function JSON.decode(str)
    local pos = 1
    
    local function skip_whitespace()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end
    
    local function parse_value()
        skip_whitespace()
        local c = str:sub(pos, pos)
        
        if c == '"' then
            return parse_string()
        elseif c == '{' then
            return parse_object()
        elseif c == '[' then
            return parse_array()
        elseif c == 't' then
            pos = pos + 4
            return true
        elseif c == 'f' then
            pos = pos + 5
            return false
        elseif c == 'n' then
            pos = pos + 4
            return nil
        else
            return parse_number()
        end
    end
    
    local function parse_string()
        pos = pos + 1  -- Skip opening quote
        local start = pos
        local result = ""
        
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return result
            elseif c == '\\' then
                pos = pos + 1
                local escape = str:sub(pos, pos)
                if escape == 'n' then result = result .. '\n'
                elseif escape == 't' then result = result .. '\t'
                elseif escape == 'r' then result = result .. '\r'
                elseif escape == '"' then result = result .. '"'
                elseif escape == '\\' then result = result .. '\\'
                end
                pos = pos + 1
            else
                result = result .. c
                pos = pos + 1
            end
        end
        
        error("Unterminated string")
    end
    
    local function parse_number()
        local start = pos
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c:match('[%d%.%-+eE]') then
                pos = pos + 1
            else
                break
            end
        end
        return tonumber(str:sub(start, pos - 1))
    end
    
    local function parse_object()
        pos = pos + 1  -- Skip {
        local obj = {}
        
        skip_whitespace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        
        while true do
            skip_whitespace()
            local key = parse_string()
            skip_whitespace()
            pos = pos + 1  -- Skip :
            obj[key] = parse_value()
            skip_whitespace()
            
            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c == ',' then
                pos = pos + 1
            end
        end
    end
    
    local function parse_array()
        pos = pos + 1  -- Skip [
        local arr = {}
        
        skip_whitespace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        
        while true do
            table.insert(arr, parse_value())
            skip_whitespace()
            
            local c = str:sub(pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c == ',' then
                pos = pos + 1
            end
        end
    end
    
    return parse_value()
end

function JSON.encode(value)
    local t = type(value)
    
    if t == 'nil' then
        return 'null'
    elseif t == 'boolean' then
        return value and 'true' or 'false'
    elseif t == 'number' then
        return tostring(value)
    elseif t == 'string' then
        return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\t', '\\t') .. '"'
    elseif t == 'table' then
        -- Check if array
        local is_array = true
        local max_index = 0
        for k, v in pairs(value) do
            if type(k) ~= 'number' or k < 1 or math.floor(k) ~= k then
                is_array = false
                break
            end
            max_index = math.max(max_index, k)
        end
        is_array = is_array and max_index == #value
        
        if is_array then
            local parts = {}
            for i, v in ipairs(value) do
                parts[i] = JSON.encode(v)
            end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            local parts = {}
            for k, v in pairs(value) do
                table.insert(parts, JSON.encode(tostring(k)) .. ':' .. JSON.encode(v))
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    
    error("Cannot encode type: " .. t)
end

return JSON
```

---

## 6. Error Codes

| Code | Name | Description |
|------|------|-------------|
| E001 | INVALID_PROFILE | Profile JSON is malformed or missing required fields |
| E002 | PROFILE_NOT_FOUND | Profile file doesn't exist |
| E003 | NAV_SERVICE_UNREACHABLE | Cannot connect to navigation service |
| E004 | PATH_NOT_FOUND | Navigation service couldn't find a path |
| E005 | NODE_DESPAWNED | Target node disappeared during approach |
| E006 | GATHER_TIMEOUT | Gathering took too long |
| E007 | STUCK_UNRECOVERABLE | All unstuck strategies failed |
| E008 | INVALID_GAME_STATE | Player object invalid or game not ready |

---

## 7. Testing Strategy

### 7.1 Unit Tests (Manual Verification)

```lua
-- Test EventBus
local function test_event_bus()
    local bus = EventBus:new()
    local received = false
    
    bus:subscribe("test", function(data)
        received = data.value
    end)
    
    bus:publish("test", { value = true })
    
    assert(received == true, "EventBus failed")
    core.log("[TEST] EventBus: PASS")
end

-- Test JSON
local function test_json()
    local obj = { name = "test", value = 123, nested = { a = 1 } }
    local encoded = JSON.encode(obj)
    local decoded = JSON.decode(encoded)
    
    assert(decoded.name == "test", "JSON name mismatch")
    assert(decoded.value == 123, "JSON value mismatch")
    assert(decoded.nested.a == 1, "JSON nested mismatch")
    core.log("[TEST] JSON: PASS")
end

-- Test Gaussian Random
local function test_gaussian()
    local samples = {}
    for i = 1, 1000 do
        samples[i] = Helpers.gaussian_random(0, 100)
    end
    
    local sum = 0
    for _, v in ipairs(samples) do sum = sum + v end
    local mean = sum / #samples
    
    -- Mean should be close to 50
    assert(mean > 40 and mean < 60, "Gaussian mean outside expected range")
    core.log("[TEST] Gaussian: PASS (mean=" .. mean .. ")")
end
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-31 | Alex | Initial draft |
