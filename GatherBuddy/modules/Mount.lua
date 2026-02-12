---@class Mount
---@field private _event_bus EventBus
---@field private _state_machine StateMachine
---@field private _log Logger|nil
local Mount = {}
Mount.__index = Mount

-- Import dependencies (relative paths since we're in GatherBuddy folder)
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")

local EVENTS = Constants.EVENTS
local STATES = Constants.STATES
local DEFAULT_SETTINGS = Constants.DEFAULT_SETTINGS

-- Mount states
local MOUNT_STATES = {
    NONE = "none",
    MOUNTING = "mounting",
    MOUNTED = "mounted",
    DISMOUNTING = "dismounting"
}

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
        return Logger:new("Mount")
    end
    return nil
end

---Create a new Mount instance
---@param event_bus EventBus
---@param state_machine StateMachine
---@param config? table Optional configuration
---@return Mount
function Mount:new(event_bus, state_machine, config)
    local instance = setmetatable({}, Mount)

    instance._event_bus = event_bus
    instance._state_machine = state_machine
    instance._log = get_logger()

    -- Configuration
    config = config or {}
    instance._mount_threshold = config.mount_threshold or DEFAULT_SETTINGS.movement.mount_threshold
    instance._preferred_mount_index = config.preferred_mount_index or 1
    instance._use_flying = config.use_flying ~= false
    instance._mount_cast_time = config.mount_cast_time or 1.5  -- seconds

    -- State tracking
    instance._mount_state = MOUNT_STATES.NONE
    instance._mount_start_time = nil
    instance._mount_timeout = 5.0  -- seconds

    -- Subscribe to events
    instance:_subscribe_events()

    return instance
end

---Subscribe to relevant events
function Mount:_subscribe_events()
    -- Auto-mount when starting long distance travel
    self._event_bus:subscribe(EVENTS.MOVEMENT_STARTED, function(data)
        if data.destination then
            self:_check_auto_mount(data.destination)
        end
    end, 50, false, "Mount")

    -- Auto-dismount before gathering
    self._event_bus:subscribe(EVENTS.GATHER_START, function()
        if self:is_mounted() then
            self:dismount()
        end
    end, 10, false, "Mount")

    -- Dismount on combat
    self._event_bus:subscribe(EVENTS.COMBAT_ENTERED, function()
        if self:is_mounted() then
            self:dismount()
        end
    end, 10, false, "Mount")

    -- Handle mount request event
    self._event_bus:subscribe(EVENTS.MOUNT_REQUESTED, function(data)
        self:mount(data and data.mount_index)
    end, 50, false, "Mount")

    -- Handle dismount request event
    self._event_bus:subscribe(EVENTS.DISMOUNT_REQUESTED, function()
        self:dismount()
    end, 50, false, "Mount")

    -- Bot stop
    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        self:_reset_state()
    end, 50, false, "Mount")
end

---Check if should auto-mount for distance
---@param destination vec3|table Target destination
function Mount:_check_auto_mount(destination)
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    -- Don't mount if already mounted
    if player:is_mounted() then
        return
    end

    -- Don't mount if in combat
    if player:is_in_combat() then
        return
    end

    -- Don't mount indoors
    if player:is_indoors() then
        return
    end

    -- Check distance
    local player_pos = player:get_position()
    local distance = Helpers.distance_3d(player_pos, destination)

    if distance >= self._mount_threshold then
        if self._log then
            self._log:debug("Auto-mounting for %.0f yard travel", distance)
        end
        self:mount()
    end
end

---Start mounting
---@param mount_index? number Optional specific mount index
---@return boolean started Whether mount was initiated
function Mount:mount(mount_index)
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false
    end

    -- Only allow mounting from valid states (TRAVELING or IDLE)
    local current_state = self._state_machine:get_state()
    if current_state ~= STATES.TRAVELING and current_state ~= STATES.IDLE then
        if self._log then
            self._log:debug("Cannot mount from state: %s", tostring(current_state))
        end
        return false
    end

    -- Already mounted
    if player:is_mounted() then
        if self._log then
            self._log:debug("Already mounted")
        end
        return false
    end

    -- Can't mount in combat
    if player:is_in_combat() then
        if self._log then
            self._log:warn("Cannot mount while in combat")
        end
        self._event_bus:publish(EVENTS.MOUNT_FAILED, {
            reason = "In combat",
            timestamp = core.time()
        })
        return false
    end

    -- Can't mount indoors
    if player:is_indoors() then
        if self._log then
            self._log:debug("Cannot mount indoors")
        end
        self._event_bus:publish(EVENTS.MOUNT_FAILED, {
            reason = "Indoors",
            timestamp = core.time()
        })
        return false
    end

    -- Can't mount while moving
    if player:is_moving() then
        if self._log then
            self._log:debug("Stopping movement before mounting")
        end
        -- Movement will need to stop first
    end

    -- Determine mount index
    local idx = mount_index or self._preferred_mount_index

    -- Validate mount index
    local mount_count = core.spell_book.get_mount_count()
    if mount_count and (idx < 1 or idx > mount_count) then
        if self._log then
            self._log:error("Invalid mount index %d (available: %d)", idx, mount_count)
        end
        self._event_bus:publish(EVENTS.MOUNT_FAILED, {
            reason = "invalid_index",
            mount_index = idx,
            available = mount_count,
            timestamp = core.time()
        })
        self._mount_state = MOUNT_STATES.NONE
        return false
    end

    -- Start mounting
    self._mount_state = MOUNT_STATES.MOUNTING
    self._mount_start_time = core.time()

    -- Transition state machine
    self._state_machine:transition(STATES.MOUNTING, {
        mount_index = idx,
        started_at = self._mount_start_time
    })

    if self._log then
        self._log:info("Mounting (index %d)", idx)
    end

    -- Issue mount command
    core.input.mount(idx)

    self._event_bus:publish(EVENTS.MOUNT_STARTED, {
        mount_index = idx,
        timestamp = core.time()
    })

    return true
end

---Dismount
---@return boolean started Whether dismount was initiated
function Mount:dismount()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false
    end

    -- Not mounted
    if not player:is_mounted() then
        if self._log then
            self._log:debug("Not mounted")
        end
        return false
    end

    self._mount_state = MOUNT_STATES.DISMOUNTING

    if self._log then
        self._log:debug("Dismounting")
    end

    core.input.dismount()

    return true
end

---Update mount state (call each tick)
function Mount:update()
    if self._mount_state == MOUNT_STATES.NONE then
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        self:_reset_state()
        return
    end

    if self._mount_state == MOUNT_STATES.MOUNTING then
        self:_process_mounting(player)
    elseif self._mount_state == MOUNT_STATES.DISMOUNTING then
        self:_process_dismounting(player)
    end
end

---Process mounting state
---@param player game_object
function Mount:_process_mounting(player)
    -- Check if now mounted
    if player:is_mounted() then
        if self._log then
            self._log:info("Mount complete")
        end

        self._mount_state = MOUNT_STATES.MOUNTED

        self._event_bus:publish(EVENTS.MOUNT_COMPLETED, {
            duration = core.time() - self._mount_start_time,
            timestamp = core.time()
        })

        -- Transition state machine back to TRAVELING
        self._state_machine:transition(STATES.TRAVELING)

        self:_reset_state()
        return
    end

    -- Check timeout
    if core.time() - self._mount_start_time > self._mount_timeout then
        if self._log then
            self._log:warn("Mount timed out")
        end

        self._event_bus:publish(EVENTS.MOUNT_FAILED, {
            reason = "Timeout",
            timestamp = core.time()
        })

        -- Transition back to TRAVELING on failure
        self._state_machine:transition(STATES.TRAVELING)

        self:_reset_state()
        return
    end

    -- Check if combat interrupted
    if player:is_in_combat() then
        if self._log then
            self._log:warn("Mount interrupted by combat")
        end

        self._event_bus:publish(EVENTS.MOUNT_FAILED, {
            reason = "Combat",
            timestamp = core.time()
        })

        -- Transition to COMBAT state
        self._state_machine:transition(STATES.COMBAT)

        self:_reset_state()
        return
    end

    -- Still mounting (casting)
    if player:is_casting_spell() then
        -- Mount cast in progress
        return
    end

    -- Not casting but not mounted either - might need to retry
    local elapsed = core.time() - self._mount_start_time
    if elapsed > self._mount_cast_time + 0.5 then
        -- Cast should have completed by now, something went wrong
        if self._log then
            self._log:warn("Mount cast did not complete")
        end

        self._event_bus:publish(EVENTS.MOUNT_FAILED, {
            reason = "Cast failed",
            timestamp = core.time()
        })

        -- Transition back to TRAVELING on failure
        self._state_machine:transition(STATES.TRAVELING)

        self:_reset_state()
    end
end

---Process dismounting state
---@param player game_object
function Mount:_process_dismounting(player)
    if not player:is_mounted() then
        if self._log then
            self._log:debug("Dismount complete")
        end
        self:_reset_state()
    end
end

---Reset internal state
function Mount:_reset_state()
    self._mount_state = MOUNT_STATES.NONE
    self._mount_start_time = nil
end

---Check if player is currently mounted
---@return boolean
function Mount:is_mounted()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false
    end
    return player:is_mounted()
end

---Check if currently in mount/dismount process
---@return boolean
function Mount:is_mounting()
    return self._mount_state == MOUNT_STATES.MOUNTING
end

---Check if should mount for a given distance
---@param distance number Distance in yards
---@return boolean
function Mount:should_mount(distance)
    if not distance then
        return false
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false
    end

    -- Already mounted
    if player:is_mounted() then
        return false
    end

    -- In combat
    if player:is_in_combat() then
        return false
    end

    -- Indoors
    if player:is_indoors() then
        return false
    end

    return distance >= self._mount_threshold
end

---Set mount threshold
---@param threshold number Distance in yards
function Mount:set_mount_threshold(threshold)
    self._mount_threshold = Helpers.clamp(threshold, 0, 500)
end

---Get mount threshold
---@return number
function Mount:get_mount_threshold()
    return self._mount_threshold
end

---Set preferred mount index
---@param index number Mount index
function Mount:set_preferred_mount(index)
    self._preferred_mount_index = index
end

---Get preferred mount index
---@return number
function Mount:get_preferred_mount()
    return self._preferred_mount_index
end

---Clean up module
function Mount:destroy()
    self:_reset_state()
    self._event_bus:unsubscribe_owner("Mount")
end

---Run unit tests
---@return table<string, boolean> Test results
function Mount:_test()
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
        get_state = function() return STATES.TRAVELING end,
        transition = function() return true end
    }

    -- Test 1: Create module
    local module = Mount:new(mock_bus, mock_state)
    results.create = (module ~= nil)

    -- Test 2: Initial state
    results.initial_not_mounting = not module:is_mounting()

    -- Test 3: Set threshold
    module:set_mount_threshold(50)
    results.set_threshold = (module:get_mount_threshold() == 50)

    -- Test 4: Clamp threshold
    module:set_mount_threshold(600)
    results.clamp_threshold = (module:get_mount_threshold() == 500)

    -- Test 5: Set preferred mount
    module:set_preferred_mount(3)
    results.set_mount = (module:get_preferred_mount() == 3)

    -- Test 6: Should mount logic
    module:set_mount_threshold(40)
    -- Note: These would need real player object, just test the method exists
    results.should_mount_method = (type(module.should_mount) == "function")

    -- Test 7: Reset state
    module._mount_state = MOUNT_STATES.MOUNTING
    module:_reset_state()
    results.reset_state = (module._mount_state == MOUNT_STATES.NONE)

    -- Test 8: Events subscribed
    results.events_subscribed = (#mock_bus.subscriptions >= 4)

    return results
end

return Mount
