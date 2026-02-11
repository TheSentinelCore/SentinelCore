---@class Statistics
---@field private _event_bus EventBus
---@field private _log Logger|nil
---@field private _last_save_time number
local Statistics = {}
Statistics.__index = Statistics

-- Import dependencies (relative paths since we're in GatherBuddy folder)
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")
local JSON = require("lib/JSON")

local EVENTS = Constants.EVENTS

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
        return Logger:new("Statistics")
    end
    return nil
end

---Create a new Statistics instance
---@param event_bus EventBus
---@param config? table Optional configuration
---@return Statistics
function Statistics:new(event_bus, config)
    local instance = setmetatable({}, Statistics)

    instance._event_bus = event_bus
    instance._log = get_logger()

    -- Session statistics
    instance._session = {
        start_time = nil,
        end_time = nil,
        active = false,

        -- Gathering stats
        nodes_gathered = 0,
        nodes_failed = 0,
        herbs_gathered = 0,
        ores_gathered = 0,

        -- Items
        items_looted = {},  -- {item_name = count}
        total_items = 0,

        -- Movement
        distance_traveled = 0,
        waypoints_reached = 0,

        -- Combat/Safety
        deaths = 0,
        combat_entries = 0,
        time_in_combat = 0,

        -- Errors
        stuck_count = 0
    }

    -- Position tracking for distance
    instance._last_position = nil
    instance._last_position_time = 0
    instance._position_track_interval = 1.0  -- seconds

    -- Combat time tracking
    instance._combat_start_time = nil

    -- Auto-save tracking
    instance._last_save_time = 0

    -- Subscribe to events
    instance:_subscribe_events()

    -- Load persisted statistics from disk
    instance:load()

    return instance
end

---Subscribe to relevant events
function Statistics:_subscribe_events()
    -- Session lifecycle
    self._event_bus:subscribe(EVENTS.BOT_START, function()
        self:start_session()
    end, 50, false, "Statistics")

    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        self:save()
        self:end_session()
    end, 50, false, "Statistics")

    -- Gathering events
    self._event_bus:subscribe(EVENTS.GATHER_SUCCESS, function(data)
        self._session.nodes_gathered = self._session.nodes_gathered + 1

        -- Determine node type
        if data.node and data.node.node_type then
            if data.node.node_type == "herb" then
                self._session.herbs_gathered = self._session.herbs_gathered + 1
            elseif data.node.node_type == "ore" then
                self._session.ores_gathered = self._session.ores_gathered + 1
            end
        end
    end, 50, false, "Statistics")

    self._event_bus:subscribe(EVENTS.GATHER_FAILED, function()
        self._session.nodes_failed = self._session.nodes_failed + 1
    end, 50, false, "Statistics")

    -- Item looting
    self._event_bus:subscribe(EVENTS.ITEM_LOOTED, function(data)
        local name = data.item_name or "Unknown"
        self._session.items_looted[name] = (self._session.items_looted[name] or 0) + 1
        self._session.total_items = self._session.total_items + 1
    end, 50, false, "Statistics")

    -- Waypoints
    self._event_bus:subscribe(EVENTS.WAYPOINT_REACHED, function()
        self._session.waypoints_reached = self._session.waypoints_reached + 1
    end, 50, false, "Statistics")

    -- Combat
    self._event_bus:subscribe(EVENTS.COMBAT_ENTERED, function()
        self._session.combat_entries = self._session.combat_entries + 1
        self._combat_start_time = core.time()
    end, 50, false, "Statistics")

    self._event_bus:subscribe(EVENTS.COMBAT_EXITED, function()
        if self._combat_start_time then
            self._session.time_in_combat = self._session.time_in_combat +
                (core.time() - self._combat_start_time)
            self._combat_start_time = nil
        end
    end, 50, false, "Statistics")

    -- Death
    self._event_bus:subscribe(EVENTS.PLAYER_DIED, function()
        self._session.deaths = self._session.deaths + 1
    end, 50, false, "Statistics")

    -- Stuck
    self._event_bus:subscribe(EVENTS.MOVEMENT_STUCK, function()
        self._session.stuck_count = self._session.stuck_count + 1
    end, 50, false, "Statistics")
end

---Update statistics (call each tick)
function Statistics:update()
    if not self._session.active then
        return
    end

    -- Track distance traveled
    local now = core.time()
    if now - self._last_position_time >= self._position_track_interval then
        self:_track_distance()
        self._last_position_time = now
    end

    -- Auto-save every 60 seconds
    if self._session.active and now - self._last_save_time >= 60 then
        self:save()
        self._last_save_time = now
    end
end

---Track distance traveled
function Statistics:_track_distance()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    local pos = player:get_position()
    if not pos then
        return
    end

    if self._last_position then
        local distance = Helpers.distance_3d(self._last_position, pos)
        -- Only count significant movement (ignore tiny jitter)
        if distance > 0.5 and distance < 100 then
            self._session.distance_traveled = self._session.distance_traveled + distance
        end
    end

    self._last_position = {
        x = pos.x,
        y = pos.y,
        z = pos.z
    }
end

---Start a new session
function Statistics:start_session()
    self:_reset_session()
    self._session.start_time = core.time()
    self._session.active = true

    if self._log then
        self._log:info("Session started")
    end
end

---End the current session
function Statistics:end_session()
    if not self._session.active then
        return
    end

    self._session.end_time = core.time()
    self._session.active = false

    -- Finalize combat time if still in combat
    if self._combat_start_time then
        self._session.time_in_combat = self._session.time_in_combat +
            (core.time() - self._combat_start_time)
        self._combat_start_time = nil
    end

    if self._log then
        self._log:info("Session ended - Duration: %s, Nodes: %d, Items: %d",
            Helpers.format_time(self:get_session_duration()),
            self._session.nodes_gathered,
            self._session.total_items)
    end
end

---Reset session statistics
function Statistics:_reset_session()
    self._session = {
        start_time = nil,
        end_time = nil,
        active = false,
        nodes_gathered = 0,
        nodes_failed = 0,
        herbs_gathered = 0,
        ores_gathered = 0,
        items_looted = {},
        total_items = 0,
        distance_traveled = 0,
        waypoints_reached = 0,
        deaths = 0,
        combat_entries = 0,
        time_in_combat = 0,
        stuck_count = 0
    }

    self._last_position = nil
    self._combat_start_time = nil
end

---Get session duration in seconds
---@return number
function Statistics:get_session_duration()
    if not self._session.start_time then
        return 0
    end

    local end_time = self._session.end_time or core.time()
    return end_time - self._session.start_time
end

---Get nodes per hour rate
---@return number
function Statistics:get_nodes_per_hour()
    local duration = self:get_session_duration()
    if duration < 1 then
        return 0
    end

    local hours = duration / 3600
    return self._session.nodes_gathered / hours
end

---Get items per hour rate
---@return number
function Statistics:get_items_per_hour()
    local duration = self:get_session_duration()
    if duration < 1 then
        return 0
    end

    local hours = duration / 3600
    return self._session.total_items / hours
end

---Get all session statistics
---@return table
function Statistics:get_stats()
    local stats = Helpers.deep_copy(self._session)

    -- Add calculated values
    stats.duration = self:get_session_duration()
    stats.duration_formatted = Helpers.format_time(stats.duration)
    stats.nodes_per_hour = self:get_nodes_per_hour()
    stats.items_per_hour = self:get_items_per_hour()
    stats.success_rate = self:get_success_rate()

    return stats
end

---Get success rate (successful gathers / total attempts)
---@return number percentage (0-100)
function Statistics:get_success_rate()
    local total = self._session.nodes_gathered + self._session.nodes_failed
    if total == 0 then
        return 100
    end
    return (self._session.nodes_gathered / total) * 100
end

---Get total nodes gathered
---@return number
function Statistics:get_nodes_gathered()
    return self._session.nodes_gathered
end

---Get total items looted
---@return number
function Statistics:get_items_looted()
    return self._session.total_items
end

---Get distance traveled
---@return number yards
function Statistics:get_distance_traveled()
    return self._session.distance_traveled
end

---Get death count
---@return number
function Statistics:get_deaths()
    return self._session.deaths
end

---Get combat entries
---@return number
function Statistics:get_combat_entries()
    return self._session.combat_entries
end

---Get time spent in combat
---@return number seconds
function Statistics:get_time_in_combat()
    local time = self._session.time_in_combat

    -- Add current combat time if in combat
    if self._combat_start_time then
        time = time + (core.time() - self._combat_start_time)
    end

    return time
end

---Get items looted breakdown
---@return table<string, number>
function Statistics:get_items_breakdown()
    return Helpers.deep_copy(self._session.items_looted)
end

---Check if session is active
---@return boolean
function Statistics:is_active()
    return self._session.active
end

---Get formatted summary string
---@return string
function Statistics:get_summary()
    local stats = self:get_stats()

    local lines = {
        string.format("Session Duration: %s", stats.duration_formatted),
        string.format("Nodes Gathered: %d (%.1f/hr)", stats.nodes_gathered, stats.nodes_per_hour),
        string.format("  Herbs: %d | Ores: %d", self._session.herbs_gathered, self._session.ores_gathered),
        string.format("Items Looted: %d (%.1f/hr)", stats.total_items, stats.items_per_hour),
        string.format("Success Rate: %.1f%%", stats.success_rate),
        string.format("Distance: %.0f yards", stats.distance_traveled),
        string.format("Deaths: %d | Combat: %d", stats.deaths, stats.combat_entries)
    }

    return table.concat(lines, "\n")
end

local STATS_FILE = "gatherbuddy/statistics.json"

---Save session statistics to disk
function Statistics:save()
    local data = Helpers.deep_copy(self._session)
    data.saved_at = core.time()
    local json_str = JSON.encode(data)
    core.write_data_file(STATS_FILE, json_str)
    if self._log then
        self._log:debug("Statistics saved to disk")
    end
end

---Load session statistics from disk
function Statistics:load()
    local json_str = core.read_data_file(STATS_FILE)
    if not json_str or json_str == "" then return end

    local ok, data = pcall(JSON.decode, json_str)
    if not ok or not data then return end

    -- Restore numeric fields
    for k, v in pairs(data) do
        if self._session[k] ~= nil and k ~= "items_looted" then
            self._session[k] = v
        end
    end
    -- Restore items_looted table
    if data.items_looted then
        self._session.items_looted = data.items_looted
    end

    if self._log then
        self._log:debug("Statistics loaded from disk (gathered: %d)", self._session.nodes_gathered or 0)
    end
end

---Clean up module
function Statistics:destroy()
    self:end_session()
    self._event_bus:unsubscribe_owner("Statistics")
end

---Run unit tests
---@return table<string, boolean> Test results
function Statistics:_test()
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

    -- Test 1: Create module
    local module = Statistics:new(mock_bus)
    results.create = (module ~= nil)

    -- Test 2: Initial state
    results.initial_not_active = not module:is_active()
    results.initial_no_nodes = (module:get_nodes_gathered() == 0)
    results.initial_no_items = (module:get_items_looted() == 0)

    -- Test 3: Start session
    module:start_session()
    results.session_active = module:is_active()
    results.session_has_start = (module._session.start_time ~= nil)

    -- Test 4: Simulate stats
    module._session.nodes_gathered = 10
    module._session.nodes_failed = 2
    module._session.total_items = 25

    results.nodes_count = (module:get_nodes_gathered() == 10)
    results.items_count = (module:get_items_looted() == 25)
    results.success_rate = (math.abs(module:get_success_rate() - 83.33) < 1)

    -- Test 5: End session
    module:end_session()
    results.session_ended = not module:is_active()
    results.session_has_end = (module._session.end_time ~= nil)

    -- Test 6: Reset
    module:_reset_session()
    results.reset_nodes = (module:get_nodes_gathered() == 0)
    results.reset_items = (module:get_items_looted() == 0)

    -- Test 7: Get stats
    module:start_session()
    local stats = module:get_stats()
    results.stats_table = (type(stats) == "table")
    results.stats_has_duration = (stats.duration ~= nil)
    module:end_session()

    -- Test 8: Get summary
    local summary = module:get_summary()
    results.summary_string = (type(summary) == "string" and #summary > 0)

    -- Test 9: Events subscribed
    results.events_subscribed = (#mock_bus.subscriptions >= 6)

    return results
end

return Statistics
