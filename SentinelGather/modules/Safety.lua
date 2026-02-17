---@class Safety
---@field private _event_bus EventBus
---@field private _state_machine StateMachine
---@field private _log Logger|nil
local Safety = {}
Safety.__index = Safety

-- Import dependencies (relative paths since we're in SentinelGather folder)
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")

local EVENTS = Constants.EVENTS
local STATES = Constants.STATES
local DEFAULT_SETTINGS = Constants.DEFAULT_SETTINGS
local THREAT_LEVELS = Constants.THREAT_LEVELS

-- Import unit_helper for enemy detection
local unit_helper = require("common/utility/unit_helper")

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("Safety")
    end
    return nil
end

---Create a new Safety instance
---@param event_bus EventBus
---@param state_machine StateMachine
---@param config? table Optional configuration
---@return Safety
function Safety:new(event_bus, state_machine, config)
    local instance = setmetatable({}, Safety)

    instance._event_bus = event_bus
    instance._state_machine = state_machine
    instance._log = get_logger()

    -- Configuration
    config = config or {}
    instance._enemy_scan_radius = config.enemy_scan_radius or DEFAULT_SETTINGS.safety.enemy_scan_radius
    instance._flee_health_threshold = config.flee_health_threshold or DEFAULT_SETTINGS.safety.flee_health_threshold
    instance._skip_if_enemies_near = config.skip_if_enemies_near
    if instance._skip_if_enemies_near == nil then
        instance._skip_if_enemies_near = DEFAULT_SETTINGS.safety.skip_if_enemies_near
    end
    instance._flee_on_combat = config.flee_on_combat or DEFAULT_SETTINGS.safety.flee_on_combat
    instance._scan_interval = config.scan_interval or 0.5  -- seconds

    -- State tracking
    instance._current_threat_level = THREAT_LEVELS.SAFE
    instance._nearby_enemies = {}
    instance._last_scan_time = 0
    instance._was_in_combat = false
    instance._was_dead = false
    instance._corpse_position = nil
    instance._death_time = nil

    -- Subscribe to events
    instance:_subscribe_events()

    return instance
end

---Subscribe to relevant events
function Safety:_subscribe_events()
    -- Bot stop
    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        self:_reset_state()
    end, 50, false, "Safety")
end

---Update safety checks (call each tick)
function Safety:update()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    -- Check death state
    self:_check_death_state(player)

    -- Check combat state
    self:_check_combat_state(player)

    -- Scan for threats periodically
    local now = core.time()
    if now - self._last_scan_time >= self._scan_interval then
        self:_scan_threats(player)
        self._last_scan_time = now
    end

    -- Check health for flee
    self:_check_health(player)
end

---Check and handle death state
---@param player game_object
function Safety:_check_death_state(player)
    local is_dead = player:is_dead()
    local is_ghost = player:is_ghost()

    if is_dead and not self._was_dead then
        -- Just died
        self._was_dead = true
        self._death_time = core.time()

        -- Store corpse position (current position when dead, or need to find it)
        local pos = player:get_position()
        self._corpse_position = {
            x = pos.x,
            y = pos.y,
            z = pos.z
        }

        if self._log then
            self._log:warn("Player died!")
        end

        self._state_machine:transition(STATES.DEAD, {
            death_time = self._death_time,
            corpse_position = self._corpse_position
        })

        self._event_bus:publish(EVENTS.PLAYER_DIED, {
            position = self._corpse_position,
            timestamp = self._death_time
        })

    elseif is_ghost and self._was_dead then
        -- Released spirit, start corpse run
        if self._state_machine:get_state() == STATES.DEAD then
            self._state_machine:transition(STATES.CORPSE_RUN, {
                corpse_position = self._corpse_position,
                started_at = core.time()
            })

            if self._log then
                self._log:info("Starting corpse run")
            end
        end

    elseif not is_dead and not is_ghost and self._was_dead then
        -- Resurrected
        self._was_dead = false
        self._death_time = nil
        self._corpse_position = nil

        if self._log then
            self._log:info("Player resurrected")
        end

        self._event_bus:publish(EVENTS.PLAYER_RESURRECTED, {
            timestamp = core.time()
        })

        -- Return to idle (will resume normal operation)
        if self._state_machine:get_state() == STATES.CORPSE_RUN or
           self._state_machine:get_state() == STATES.DEAD then
            self._state_machine:transition(STATES.IDLE)
        end
    end
end

---Check and handle combat state
---@param player game_object
function Safety:_check_combat_state(player)
    local is_in_combat = player:is_in_combat()

    if is_in_combat and not self._was_in_combat then
        -- Entered combat
        self._was_in_combat = true

        if self._log then
            self._log:warn("Entered combat!")
        end

        -- Update threat level
        self._current_threat_level = THREAT_LEVELS.COMBAT

        -- Transition to combat state
        local previous_state = self._state_machine:get_state()
        self._state_machine:transition(STATES.COMBAT, {
            previous_state = previous_state,
            entered_at = core.time()
        })

        self._event_bus:publish(EVENTS.COMBAT_ENTERED, {
            previous_state = previous_state,
            timestamp = core.time()
        })

        -- Publish threat level change
        self._event_bus:publish(EVENTS.THREAT_LEVEL_CHANGED, {
            level = THREAT_LEVELS.COMBAT,
            previous_level = THREAT_LEVELS.SAFE,
            timestamp = core.time()
        })

    elseif not is_in_combat and self._was_in_combat then
        -- Exited combat
        self._was_in_combat = false

        if self._log then
            self._log:info("Exited combat")
        end

        -- Get previous state from context
        local ctx = self._state_machine:get_context()
        local ctx_data = ctx and ctx.data or {}
        local return_state = ctx_data.previous_state or STATES.IDLE

        self._event_bus:publish(EVENTS.COMBAT_EXITED, {
            duration = core.time() - (ctx_data.entered_at or core.time()),
            timestamp = core.time()
        })

        -- Update threat level based on nearby enemies
        self:_update_threat_level()

        -- Return to previous state or idle
        if self._state_machine:get_state() == STATES.COMBAT then
            self._state_machine:transition(return_state)
        end
    end
end

---Scan for nearby threats
---@param player game_object
function Safety:_scan_threats(player)
    local player_pos = player:get_position()

    -- Use unit_helper to get enemies
    local enemies = unit_helper:get_enemy_list_around(
        player_pos,
        self._enemy_scan_radius,
        true,   -- include_out_of_combat
        false,  -- include_blacklist
        false,  -- players_only
        false   -- include_dead
    )

    local previous_count = #self._nearby_enemies
    self._nearby_enemies = enemies or {}
    local current_count = #self._nearby_enemies

    -- Publish enemy detected if new enemies appeared
    if current_count > 0 and current_count > previous_count then
        self._event_bus:publish(EVENTS.ENEMY_DETECTED, {
            count = current_count,
            enemies = self._nearby_enemies,
            timestamp = core.time()
        })
    end

    -- Update threat level
    self:_update_threat_level()
end

---Update threat level based on current situation
function Safety:_update_threat_level()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    local previous_level = self._current_threat_level
    local new_level = THREAT_LEVELS.SAFE

    if player:is_in_combat() then
        new_level = THREAT_LEVELS.COMBAT
    elseif #self._nearby_enemies > 0 then
        -- Check distance to nearest enemy
        local player_pos = player:get_position()
        local min_distance = math.huge

        for _, enemy in ipairs(self._nearby_enemies) do
            if enemy and enemy:is_valid() then
                local enemy_pos = enemy:get_position()
                if enemy_pos then
                    local dist = Helpers.distance_3d(player_pos, enemy_pos)
                    min_distance = math.min(min_distance, dist)
                end
            end
        end

        if min_distance < Constants.OPERATIONAL.THREAT_DISTANCE_DANGER then
            new_level = THREAT_LEVELS.DANGER
        elseif min_distance < Constants.OPERATIONAL.THREAT_DISTANCE_CAUTION then
            new_level = THREAT_LEVELS.CAUTION
        end
    end

    if new_level ~= previous_level then
        self._current_threat_level = new_level

        if self._log then
            self._log:debug("Threat level changed: %d -> %d", previous_level, new_level)
        end

        self._event_bus:publish(EVENTS.THREAT_LEVEL_CHANGED, {
            level = new_level,
            previous_level = previous_level,
            enemy_count = #self._nearby_enemies,
            timestamp = core.time()
        })
    end
end

---Check health and trigger flee if needed
---@param player game_object
function Safety:_check_health(player)
    if not self._flee_on_combat then
        return
    end

    local health = player:get_health()
    local max_health = player:get_max_health()

    if not health or not max_health or max_health == 0 then
        return
    end

    local health_percent = (health / max_health) * 100

    if health_percent <= self._flee_health_threshold and player:is_in_combat() then
        if self._state_machine:get_state() ~= STATES.FLEEING then
            if self._log then
                self._log:warn("Health low (%.0f%%), fleeing!", health_percent)
            end

            self._state_machine:transition(STATES.FLEEING, {
                health_percent = health_percent,
                started_at = core.time()
            })
        end
    end
end

---Check if it's safe to gather (no nearby threats)
---@return boolean
function Safety:is_safe_to_gather()
    if not self._skip_if_enemies_near then
        return true
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false
    end

    -- Not safe if in combat
    if player:is_in_combat() then
        return false
    end

    -- Not safe if dead
    if player:is_dead() or player:is_ghost() then
        return false
    end

    -- Check threat level
    return self._current_threat_level <= THREAT_LEVELS.CAUTION
end

---Get current threat level
---@return number
function Safety:get_threat_level()
    return self._current_threat_level
end

---Get nearby enemies
---@return table[]
function Safety:get_nearby_enemies()
    return self._nearby_enemies
end

---Get enemy count
---@return number
function Safety:get_enemy_count()
    return #self._nearby_enemies
end

---Check if player is dead
---@return boolean
function Safety:is_dead()
    return self._was_dead
end

---Get corpse position (if dead)
---@return table|nil
function Safety:get_corpse_position()
    return self._corpse_position
end

---Handle death (release spirit)
function Safety:release_spirit()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    if player:is_dead() and not player:is_ghost() then
        if self._log then
            self._log:info("Releasing spirit")
        end
        core.input.release_spirit()
    end
end

---Resurrect at corpse
function Safety:resurrect()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    if player:is_ghost() then
        if self._log then
            self._log:info("Resurrecting at corpse")
        end
        core.input.resurrect_corpse()
    end
end

---Set enemy scan radius
---@param radius number Scan radius in yards
function Safety:set_scan_radius(radius)
    self._enemy_scan_radius = Helpers.clamp(radius, 5, 100)
end

---Get enemy scan radius
---@return number
function Safety:get_scan_radius()
    return self._enemy_scan_radius
end

---Set flee health threshold
---@param percent number Health percent (1-100)
function Safety:set_flee_threshold(percent)
    self._flee_health_threshold = Helpers.clamp(percent, 1, 100)
end

---Reset internal state
function Safety:_reset_state()
    self._current_threat_level = THREAT_LEVELS.SAFE
    self._nearby_enemies = {}
    self._was_in_combat = false
    self._was_dead = false
    self._corpse_position = nil
    self._death_time = nil
end

---Clean up module
function Safety:destroy()
    self:_reset_state()
    self._event_bus:unsubscribe_owner("Safety")
end

---Run unit tests
---@return table<string, boolean> Test results
function Safety:_test()
    local results = {}

    -- Create mock dependencies
    local mock_bus = {
        events = {},
        subscriptions = {},
        publish = function(self, event, data)
            table.insert(self.events, { event = event, data = data })
        end,
        subscribe = function(self, event, callback, priority, once, owner)
            table.insert(self.subscriptions, { event = event, owner = owner })
            return #self.subscriptions
        end,
        unsubscribe_owner = function() end
    }

    local mock_state = {
        _state = STATES.IDLE,
        get_state = function(self) return self._state end,
        get_context = function() return { data = {} } end,
        transition = function(self, state) self._state = state return true end
    }

    -- Test 1: Create module
    local module = Safety:new(mock_bus, mock_state)
    results.create = (module ~= nil)

    -- Test 2: Initial state
    results.initial_threat_safe = (module:get_threat_level() == THREAT_LEVELS.SAFE)
    results.initial_no_enemies = (module:get_enemy_count() == 0)
    results.initial_not_dead = not module:is_dead()
    results.initial_no_corpse = (module:get_corpse_position() == nil)

    -- Test 3: Set scan radius
    module:set_scan_radius(50)
    results.set_radius = (module:get_scan_radius() == 50)

    -- Test 4: Clamp scan radius
    module:set_scan_radius(200)
    results.clamp_radius = (module:get_scan_radius() == 100)

    -- Test 5: Set flee threshold
    module:set_flee_threshold(25)
    results.set_threshold = (module._flee_health_threshold == 25)

    -- Test 6: Reset state
    module._current_threat_level = THREAT_LEVELS.COMBAT
    module._was_dead = true
    module:_reset_state()
    results.reset_threat = (module:get_threat_level() == THREAT_LEVELS.SAFE)
    results.reset_dead = not module:is_dead()

    -- Test 7: Is safe to gather (default)
    -- With no player, should return false
    results.safe_check_method = (type(module.is_safe_to_gather) == "function")

    -- Test 8: Events subscribed
    results.events_subscribed = (#mock_bus.subscriptions >= 1)

    return results
end

return Safety
