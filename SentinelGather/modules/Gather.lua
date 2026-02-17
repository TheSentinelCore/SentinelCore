---@class Gather
---@field private _event_bus EventBus
---@field private _state_machine StateMachine
---@field private _node_scanner NodeScanner
---@field private _log Logger|nil
---@field private _timeout number
---@field private _loot_delay_min number
---@field private _loot_delay_max number
---@field private _interaction_range number
---@field private _blacklist_success_duration number
---@field private _blacklist_fail_duration number
---@field private _gather_state string
---@field private _current_node table|nil
---@field private _current_node_guid number|nil
---@field private _gather_start_time number|nil
---@field private _face_time number|nil
---@field private _interact_time number|nil
---@field private _cast_complete_time number|nil
---@field private _loot_delay number|nil
---@field private _items_looted table
---@field private _regather_node table|nil Node data for pending regather
---@field private _regather_time number|nil Time to attempt regather
local Gather = {}
Gather.__index = Gather

-- Import dependencies (relative paths since we're in SentinelGather folder)
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")

local EVENTS = Constants.EVENTS
local STATES = Constants.STATES
local DEFAULT_SETTINGS = Constants.DEFAULT_SETTINGS

-- Internal gathering states (from TDD.md)
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
        return Logger:new("Gather")
    end
    return nil
end

---Create a new Gather instance
---@param event_bus EventBus
---@param state_machine StateMachine
---@param node_scanner NodeScanner
---@param config? table Optional configuration
---@return Gather
function Gather:new(event_bus, state_machine, node_scanner, config)
    local instance = setmetatable({}, Gather)

    instance._event_bus = event_bus
    instance._state_machine = state_machine
    instance._node_scanner = node_scanner
    instance._log = get_logger()

    -- Configuration
    config = config or {}
    instance._timeout = config.gather_timeout or DEFAULT_SETTINGS.gathering.gather_timeout
    instance._loot_delay_min = config.loot_delay_min or 0.05
    instance._loot_delay_max = config.loot_delay_max or 0.15
    instance._interaction_range = config.interaction_range or 5.0
    instance._blacklist_success_duration = config.blacklist_success_duration or DEFAULT_SETTINGS.gathering.blacklist_duration
    instance._blacklist_fail_duration = config.blacklist_fail_duration or 60

    -- State tracking
    instance._gather_state = GATHER_STATES.NONE
    instance._current_node = nil
    instance._current_node_guid = nil
    instance._gather_start_time = nil
    instance._face_time = nil
    instance._interact_time = nil
    instance._cast_complete_time = nil
    instance._loot_delay = nil
    instance._items_looted = {}

    -- Subscribe to events
    instance:_subscribe_events()

    return instance
end

---Subscribe to relevant events
function Gather:_subscribe_events()
    -- Listen for movement completed (arrived at node)
    self._event_bus:subscribe(EVENTS.MOVEMENT_COMPLETED, function(data)
        if self._state_machine:get_state() == STATES.APPROACHING then
            local ctx = self._state_machine:get_context()
            local node = ctx.data and ctx.data.target_node

            if data.success then
                -- We've arrived at a node, start gathering
                if node then
                    self:start_gather(node)
                end
            else
                -- Movement failed - blacklist node and return to traveling
                if self._log then
                    self._log:warn("Failed to reach node: " .. (data.reason or "unknown"))
                end

                -- Blacklist the unreachable node
                if node and node.guid and self._node_scanner then
                    self._node_scanner:blacklist_node(node.guid, data.reason or "Unreachable")
                end

                -- Transition back to traveling
                self._state_machine:transition(STATES.TRAVELING)
            end
        end
    end, 50, false, "Gather")

    -- Listen for combat to interrupt gathering
    self._event_bus:subscribe(EVENTS.COMBAT_ENTERED, function()
        if self:is_gathering() then
            self:_interrupt_gather("Combat entered")
        end
    end, 10, false, "Gather")

    -- Listen for bot stop
    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        self:cancel_gather()
    end, 50, false, "Gather")
end

---Start gathering a node
---@param node table Node data from NodeScanner
---@return boolean started Whether gathering started
function Gather:start_gather(node)
    if self:is_gathering() then
        if self._log then
            self._log:warn("Already gathering, cannot start new gather")
        end
        return false
    end

    if not node or not node.object then
        if self._log then
            self._log:error("Invalid node data")
        end
        return false
    end

    -- Verify node is still valid
    if not node.object:is_valid() then
        if self._log then
            self._log:warn("Node is no longer valid")
        end
        return false
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false
    end

    -- Check distance
    local player_pos = player:get_position()
    local node_pos = node.object:get_position()
    local distance = Helpers.distance_3d(player_pos, node_pos)

    if distance > self._interaction_range then
        if self._log then
            self._log:warn("Too far from node (%.1f yards)", distance)
        end
        return false
    end

    -- Initialize gathering state
    self._current_node = node.object
    self._current_node_guid = node.guid
    self._gather_start_time = core.time()
    self._items_looted = {}

    -- Start with facing
    self._gather_state = GATHER_STATES.FACING
    self._face_time = core.time()

    if self._log then
        self._log:info("Starting gather: %s", node.name or "Unknown")
    end

    -- Transition state machine
    self._state_machine:transition(STATES.GATHERING, {
        node = node,
        started_at = self._gather_start_time
    })

    return true
end

---Update gathering logic (call each tick)
function Gather:update()
    -- Check for pending regather (multi-tap nodes)
    local regather_node_data = self._regather_node
    local regather_time = self._regather_time
    if regather_node_data ~= nil and regather_time ~= nil then
        if core.time() >= regather_time then
            self._regather_node = nil
            self._regather_time = nil

            -- Verify node is still valid and gatherable
            local node_obj = regather_node_data.object
            local node_guid = regather_node_data.guid
            local node_name = regather_node_data.name or "Unknown"
            local node_pos = regather_node_data.position

            if node_obj ~= nil and node_obj:is_valid() then
                if node_obj:can_be_looted() or node_obj:can_be_used() then
                    if self._log then
                        self._log:info("Re-gathering node '%s'", node_name)
                    end
                    -- Build proper node structure for start_gather
                    -- Get fresh position if saved position is nil
                    local regather_node = {
                        object = node_obj,
                        guid = node_guid,
                        name = node_name,
                        position = node_pos or node_obj:get_position()
                    }
                    self:start_gather(regather_node)
                    return
                end
            end

            -- Node no longer valid, blacklist it
            if node_guid ~= nil and self._node_scanner ~= nil then
                self._node_scanner:blacklist_node(node_guid, "depleted")
            end
        end
        return  -- Don't process other states while waiting to regather
    end

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

    -- Process current state
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

---Process facing state
---@param player game_object
function Gather:_process_facing(player)
    local node = self._current_node
    if not node or not node:is_valid() then
        self:_fail_gather("Node despawned")
        return
    end

    local node_pos = node:get_position()
    core.input.look_at(node_pos)

    -- Wait a small random delay before next step
    local face_duration = Helpers.gaussian_random(0.1, 0.3)
    if core.time() - self._face_time > face_duration then
        self._face_time = nil

        -- Check if mounted
        if player:is_mounted() then
            self._gather_state = GATHER_STATES.DISMOUNTING
            core.input.dismount()

            if self._log then
                self._log:debug("Dismounting before gather")
            end
        else
            self._gather_state = GATHER_STATES.INTERACTING
        end
    end
end

---Process dismounting state
---@param player game_object
function Gather:_process_dismounting(player)
    -- Wait until dismounted
    if not player:is_mounted() then
        -- Small delay after dismount
        if not self._dismount_time then
            self._dismount_time = core.time()
        elseif core.time() - self._dismount_time > Helpers.gaussian_random(0.2, 0.4) then
            self._dismount_time = nil
            self._gather_state = GATHER_STATES.INTERACTING
        end
    end
end

---Process interacting state
---@param player game_object
function Gather:_process_interacting(player)
    local node = self._current_node
    if not node or not node:is_valid() then
        self:_fail_gather("Node despawned")
        return
    end

    -- Check distance again
    local player_pos = player:get_position()
    local node_pos = node:get_position()
    local distance = Helpers.distance_3d(player_pos, node_pos)

    if distance > self._interaction_range then
        self:_fail_gather("Too far from node")
        return
    end

    -- Interact with node
    core.input.use_object(node)
    self._interact_time = core.time()

    -- Verify node is still valid after interaction attempt
    if not node or not node:is_valid() then
        -- Node despawned during interaction — could be instant-gather success or despawn
        if self._log then
            self._log:debug("Node disappeared after interaction, treating as success")
        end
        self:_complete_gather()
        return
    end

    self._gather_state = GATHER_STATES.CASTING

    if self._log then
        self._log:debug("Interacting with node")
    end

    -- Publish gather start event (safely get name in case node despawns)
    local node_name = Helpers.safe_name(node)
    self._event_bus:publish(EVENTS.GATHER_START, {
        node = node,
        name = node_name,
        position = node_pos,
        timestamp = core.time()
    })
end

---Process casting state
---@param player game_object
function Gather:_process_casting(player)
    -- Check if we're casting
    if player:is_casting_spell() or player:is_channelling_spell() then
        -- Still casting, publish progress
        self._event_bus:publish(EVENTS.GATHER_PROGRESS, {
            node = self._current_node,
            elapsed = core.time() - self._interact_time
        })
        return
    end

    -- Cast finished or was never started, check for loot window
    if not self._cast_complete_time then
        self._cast_complete_time = core.time()
    end

    -- Wait for loot window to appear
    if core.time() - self._cast_complete_time < Constants.OPERATIONAL.LOOT_WINDOW_TIMEOUT then
        self._gather_state = GATHER_STATES.WAITING_LOOT
    else
        -- No loot window appeared but node may have been gathered
        if not self._current_node or not self._current_node:is_valid() then
            -- Node disappeared, probably successful
            self:_complete_gather()
        else
            self:_fail_gather("No loot window appeared")
        end
    end
end

---Process waiting for loot window state
function Gather:_process_waiting_loot()
    local loot_count = core.game_ui.get_loot_item_count()

    if loot_count and loot_count > 0 then
        self._gather_state = GATHER_STATES.LOOTING
        self._loot_delay = 0

        if self._log then
            self._log:debug("Loot window opened with %d items", loot_count)
        end

        self._event_bus:publish(EVENTS.LOOT_WINDOW_OPENED, {
            item_count = loot_count,
            timestamp = core.time()
        })

        -- Transition state machine to looting
        self._state_machine:transition(STATES.LOOTING)
    elseif core.time() - self._cast_complete_time > 0.5 then
        -- No loot window after 0.5s, consider it a success (auto-looted or already gathered)
        self:_complete_gather()
    end
end

---Process looting state
function Gather:_process_looting()
    local loot_count = core.game_ui.get_loot_item_count()

    if not loot_count or loot_count == 0 then
        -- All looted
        core.input.close_loot()

        self._event_bus:publish(EVENTS.LOOT_WINDOW_CLOSED, {
            items_looted = self._items_looted,
            timestamp = core.time()
        })

        self:_complete_gather()
        return
    end

    -- Loot with small delays for human-like behavior
    self._loot_delay = (self._loot_delay or 0) - core.delta_time()

    if self._loot_delay <= 0 then
        -- Loot first item
        local item_id = core.game_ui.get_loot_item_id(0)
        local item_name = core.game_ui.get_loot_item_name(0)

        core.input.loot_item(0)

        -- Track looted item
        table.insert(self._items_looted, {
            id = item_id,
            name = item_name
        })

        if self._log then
            self._log:debug("Looted: %s", item_name or "Unknown")
        end

        self._event_bus:publish(EVENTS.ITEM_LOOTED, {
            item_id = item_id,
            item_name = item_name,
            timestamp = core.time()
        })

        -- Random delay before next loot (anti-detection)
        self._loot_delay = Helpers.gaussian_random(self._loot_delay_min, self._loot_delay_max)
    end
end

---Complete gathering successfully
function Gather:_complete_gather()
    local node = self._current_node
    local node_guid = self._current_node_guid
    -- Check is_valid() before calling get_name() to avoid "Invalid game object" error
    local node_name = Helpers.safe_name(node)
    local duration = core.time() - self._gather_start_time

    if self._log then
        self._log:info("Gather complete in %.1fs, looted %d items", duration, #self._items_looted)
    end

    self._event_bus:publish(EVENTS.GATHER_SUCCESS, {
        node = node,
        node_guid = node_guid,
        duration = duration,
        items = self._items_looted,
        timestamp = core.time()
    })

    -- Check if node is still valid and can be gathered again (multi-tap nodes like ore veins)
    local node_still_gatherable = false
    if node and node:is_valid() then
        -- Check if node can still be looted/used (meaning it has more resources)
        if node:can_be_looted() or node:can_be_used() then
            node_still_gatherable = true
            if self._log then
                self._log:info("Node '%s' still gatherable, attempting re-gather", node_name)
            end
        end
    end

    -- Only blacklist if node is depleted or despawned
    if not node_still_gatherable then
        if node_guid and self._node_scanner then
            self._node_scanner:blacklist_node(node_guid, "depleted")
        end
        self:_reset_state()
    else
        -- Node still has resources - reset and immediately start another gather
        -- Save node reference before reset (node is valid since we checked above)
        local saved_node = {
            object = node,
            guid = node_guid,
            name = node_name,
            position = (node and node:is_valid()) and node:get_position() or nil
        }

        self:_reset_state()

        -- Small delay before regathering (human-like)
        -- Schedule a re-gather attempt after a brief pause
        self._regather_node = saved_node
        self._regather_time = core.time() + Helpers.gaussian_random(0.3, 0.6)
    end
end

---Fail gathering
---@param reason string Failure reason
function Gather:_fail_gather(reason)
    local node = self._current_node
    local node_guid = self._current_node_guid

    if self._log then
        self._log:warn("Gather failed: %s", reason)
    end

    self._event_bus:publish(EVENTS.GATHER_FAILED, {
        node = node,
        node_guid = node_guid,
        reason = reason,
        timestamp = core.time()
    })

    -- Short blacklist for failed nodes
    if node_guid and self._node_scanner then
        self._node_scanner:blacklist_node(node_guid, reason)
    end

    self:_reset_state()
end

---Interrupt gathering (e.g., combat)
---@param reason string Interrupt reason
function Gather:_interrupt_gather(reason)
    if self._log then
        self._log:warn("Gather interrupted: %s", reason)
    end

    self._event_bus:publish(EVENTS.GATHER_INTERRUPTED, {
        node = self._current_node,
        node_guid = self._current_node_guid,
        reason = reason,
        timestamp = core.time()
    })

    -- Close loot window if open
    local loot_count = core.game_ui.get_loot_item_count()
    if loot_count and loot_count > 0 then
        core.input.close_loot()
    end

    self:_reset_state()
end

---Reset internal state
function Gather:_reset_state()
    self._gather_state = GATHER_STATES.NONE
    self._current_node = nil
    self._current_node_guid = nil
    self._gather_start_time = nil
    self._face_time = nil
    self._dismount_time = nil
    self._interact_time = nil
    self._cast_complete_time = nil
    self._loot_delay = nil
    self._items_looted = {}
end

---Cancel current gather
function Gather:cancel_gather()
    -- Clear any pending regather
    self._regather_node = nil
    self._regather_time = nil

    if self:is_gathering() then
        self:_interrupt_gather("Cancelled")
    end
end

---Check if currently gathering
---@return boolean
function Gather:is_gathering()
    return self._gather_state ~= GATHER_STATES.NONE
end

---Get current gathering state
---@return string
function Gather:get_gather_state()
    return self._gather_state
end

---Get current node being gathered
---@return game_object|nil
function Gather:get_current_node()
    return self._current_node
end

---Get time spent gathering current node
---@return number|nil
function Gather:get_gather_duration()
    if not self._gather_start_time then
        return nil
    end
    return core.time() - self._gather_start_time
end

---Clean up module
function Gather:destroy()
    self:cancel_gather()
    self._event_bus:unsubscribe_owner("Gather")
end

---Run unit tests
---@return table<string, boolean> Test results
function Gather:_test()
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
        get_state = function() return STATES.APPROACHING end,
        get_context = function() return { data = {} } end,
        transition = function() return true end
    }

    local mock_scanner = {
        blacklist_node = function() end
    }

    -- Test 1: Create module
    local module = Gather:new(mock_bus, mock_state, mock_scanner)
    results.create = (module ~= nil)

    -- Test 2: Initial state
    results.initial_not_gathering = not module:is_gathering()
    results.initial_state_none = (module:get_gather_state() == GATHER_STATES.NONE)
    results.initial_no_node = (module:get_current_node() == nil)
    results.initial_no_duration = (module:get_gather_duration() == nil)

    -- Test 3: Reset state
    module._gather_state = GATHER_STATES.CASTING
    module._current_node = {}
    module:_reset_state()
    results.reset_state = (module._gather_state == GATHER_STATES.NONE)
    results.reset_node = (module._current_node == nil)

    -- Test 4: Cancel when not gathering
    module:cancel_gather()  -- Should not error
    results.cancel_idle = true

    -- Test 5: Events subscribed
    results.events_subscribed = (#mock_bus.subscriptions >= 2)

    return results
end

return Gather
