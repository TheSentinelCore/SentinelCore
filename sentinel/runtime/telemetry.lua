-- sentinel/runtime/telemetry.lua
-- Records execution metrics for analysis.
-- Subscribes to runtime engine events for auto-recording.
-- Data stored in blackboard at module.runtime.telemetry.
-- Persisted to sentinel/analytics/<profile_id>.json

local Telemetry = {}
Telemetry.__index = Telemetry

local ANALYTICS_DIR = "sentinel/analytics"

---Create a new Telemetry recorder
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@return table Telemetry instance
function Telemetry:new(blackboard, event_bus)
    local o = setmetatable({}, Telemetry)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._subscriptions = {}
    o._start_time = nil
    o._active = false
    o._profile_id = nil
    return o
end

---Initialize blackboard storage structure
function Telemetry:_init_storage()
    local existing = self._blackboard:get("module.runtime.telemetry")
    if not existing then
        self._blackboard:set("module.runtime.telemetry", {
            profile_id = nil,
            start_time = nil,
            current_session = {
                actions = {},
                operations = {},
                actions_by_type = {},
            },
            all_time = {
                deaths = 0,
                xp_gained = 0,
                gold_spent = 0,
            },
        })
    end
end

---Get the telemetry data from blackboard
---@return table
function Telemetry:_get_data()
    local data = self._blackboard:get("module.runtime.telemetry")
    if not data then
        self:_init_storage()
        data = self._blackboard:get("module.runtime.telemetry")
    end
    return data
end

---Save telemetry data back to blackboard
---@param data table
function Telemetry:_set_data(data)
    self._blackboard:set("module.runtime.telemetry", data)
end

---Start a telemetry session. Subscribes to runtime events.
---@param profile_id string|nil Optional profile identifier
function Telemetry:start(profile_id)
    if self._active then
        return -- already started
    end

    self:_init_storage()
    local data = self:_get_data()
    data.profile_id = profile_id or data.profile_id
    data.start_time = self:_get_time()
    data.current_session = {
        actions = {},
        operations = {},
        actions_by_type = {},
    }
    self._start_time = data.start_time
    self._profile_id = data.profile_id or profile_id
    self:_set_data(data)

    self:_subscribe()
    self._active = true

    if self._event_bus then
        self._event_bus:publish("telemetry_started", {
            profile_id = self._profile_id,
        })
    end
end

---Stop the telemetry session and unsubscribe from events.
---@param save boolean|nil Whether to persist via save() after stopping
function Telemetry:stop(save)
    if not self._active then
        return
    end

    self:_unsubscribe()
    self._active = false

    if self._event_bus then
        self._event_bus:publish("telemetry_stopped", {
            profile_id = self._profile_id,
            duration_ms = self:_get_time() - (self._start_time or 0),
        })
    end

    if save then
        self:save(self._profile_id)
    end
end

---Record an action execution result
---@param action_id string
---@param action_type string
---@param duration_ms number
---@param success boolean
---@param retry_count number|nil
---@param error_message string|nil
function Telemetry:record_action(action_id, action_type, duration_ms, success, retry_count, error_message)
    local data = self:_get_data()
    local entry = {
        action_id = tostring(action_id),
        action_type = tostring(action_type),
        duration_ms = duration_ms or 0,
        success = success ~= false,
        retry_count = retry_count or 0,
        error_message = error_message or nil,
        timestamp = self:_get_time(),
    }
    table.insert(data.current_session.actions, entry)

    -- Track by action type
    data.current_session.actions_by_type[tostring(action_type)] =
        (data.current_session.actions_by_type[tostring(action_type)] or 0) + 1

    self:_set_data(data)
end

---Record an operation summary
---@param operation_id string
---@param duration_ms number
---@param actions_completed number
---@param actions_failed number
---@param deaths number|nil
function Telemetry:record_operation(operation_id, duration_ms, actions_completed, actions_failed, deaths)
    local data = self:_get_data()
    local entry = {
        operation_id = tostring(operation_id),
        duration_ms = duration_ms or 0,
        actions_completed = actions_completed or 0,
        actions_failed = actions_failed or 0,
        deaths = deaths or 0,
        timestamp = self:_get_time(),
    }
    table.insert(data.current_session.operations, entry)
    self:_set_data(data)
end

---Record a death event
---@param position table|nil Position { x, y, z }
---@param killer string|nil Killer name or GUID
function Telemetry:record_death(position, killer)
    local data = self:_get_data()
    data.all_time.deaths = data.all_time.deaths + 1

    -- Also record as a death entry in current session if we want to persist kills
    if not data.current_session.deaths then
        data.current_session.deaths = {}
    end
    table.insert(data.current_session.deaths, {
        position = position,
        killer = killer,
        timestamp = self:_get_time(),
    })

    self:_set_data(data)
end

---Record XP gained
---@param amount number
function Telemetry:record_xp_gained(amount)
    local data = self:_get_data()
    data.all_time.xp_gained = (data.all_time.xp_gained or 0) + (amount or 0)
    self:_set_data(data)
end

---Record gold spent
---@param amount number
function Telemetry:record_gold_spent(amount)
    local data = self:_get_data()
    data.all_time.gold_spent = (data.all_time.gold_spent or 0) + (amount or 0)
    self:_set_data(data)
end

---Get an aggregated summary of telemetry data
---@param profile_id string|nil Optional profile filter
---@return table Summary metrics
function Telemetry:get_summary(profile_id)
    local data = self:_get_data()
    local actions = data.current_session.actions or {}
    local operations = data.current_session.operations or {}

    local total_actions = #actions
    local succeeded_actions = 0
    local failed_actions = 0
    local total_action_duration = 0
    local ops_completed = 0
    local ops_failed = 0
    local ops_skipped = 0
    local total_op_duration = 0

    for _, op in ipairs(operations) do
        total_op_duration = total_op_duration + (op.duration_ms or 0)
        if op.actions_failed and op.actions_failed > 0 then
            ops_failed = ops_failed + 1
        else
            ops_completed = ops_completed + 1
        end
    end

    for _, act in ipairs(actions) do
        total_action_duration = total_action_duration + (act.duration_ms or 0)
        if act.success then
            succeeded_actions = succeeded_actions + 1
        else
            failed_actions = failed_actions + 1
        end
    end

    local completion_rate = total_actions > 0 and (succeeded_actions / total_actions) or 1.0

    return {
        profile_id = profile_id or data.profile_id,
        total_duration_ms = total_action_duration,
        operations_completed = ops_completed,
        operations_failed = ops_failed,
        operations_skipped = ops_skipped,
        completion_rate = completion_rate,
        total_xp = data.all_time.xp_gained or 0,
        total_gold_spent = data.all_time.gold_spent or 0,
        total_deaths = data.all_time.deaths or 0,
        total_actions = total_actions,
        succeeded_actions = succeeded_actions,
        failed_actions = failed_actions,
        actions_by_type = data.current_session.actions_by_type or {},
    }
end

---Get the ordered timeline of action metrics for a specific operation
---@param operation_id string
---@return table Ordered list of action metrics
function Telemetry:get_operation_timeline(operation_id)
    local data = self:_get_data()
    local actions = data.current_session.actions or {}
    local timeline = {}
    local op_str = tostring(operation_id)

    -- Actions don't carry operation_id directly, so we look at the contiguous
    -- ranges between operation records. For simplicity, return all actions
    -- that fall within the timestamp range of the given operation.
    -- A more precise implementation would tag actions with op_id.
    --
    -- For now, we return actions that have matching operation context stored
    -- in the action entry's metadata.

    for _, act in ipairs(actions) do
        if act.operation_id == op_str then
            table.insert(timeline, act)
        end
    end

    -- If no actions tagged with operation_id, return all actions (ordered by timestamp)
    if #timeline == 0 and #actions > 0 then
        -- Sort by timestamp for determinstic order
        table.sort(actions, function(a, b)
            return (a.timestamp or 0) < (b.timestamp or 0)
        end)
        return actions
    end

    -- Sort by timestamp
    table.sort(timeline, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)

    return timeline
end

---Save telemetry data to disk
---@param profile_id string|nil Profile identifier (uses stored profile_id if nil)
---@return boolean success
---@return string|nil error
function Telemetry:save(profile_id)
    profile_id = profile_id or self._profile_id
    if not profile_id then
        return false, "no profile_id provided"
    end

    local data = self:_get_data()
    local payload = {
        profile_id = profile_id,
        saved_at = self:_get_time(),
        session = data.current_session,
        all_time = data.all_time,
    }

    local json_str = self:_encode(payload)
    if not json_str then
        return false, "failed to encode telemetry data"
    end

    local path = ANALYTICS_DIR .. "/" .. tostring(profile_id) .. ".json"

    -- Use core.write_data_file for persistence
    if core and core.write_data_file then
        local ok, err = pcall(core.write_data_file, path, json_str)
        if not ok then
            return false, tostring(err)
        end
        return true, nil
    end

    -- Fallback: store in blackboard for environments without file I/O
    self._blackboard:set("module.runtime.telemetry_saved", {
        path = path,
        data = payload,
        saved_at = self:_get_time(),
    })
    return true, nil
end

---Load telemetry data from disk
---@param profile_id string Profile identifier
---@return table|nil Loaded data
---@return string|nil error
function Telemetry:load(profile_id)
    if not profile_id then
        return nil, "no profile_id provided"
    end

    local path = ANALYTICS_DIR .. "/" .. tostring(profile_id) .. ".json"

    if core and core.read_data_file then
        local content, err = core.read_data_file(path)
        if not content then
            return nil, err or "file not found"
        end
        local data, parse_err = self:_decode(content)
        if parse_err then
            return nil, parse_err
        end

        -- Merge into current blackboard data
        local existing = self:_get_data()
        if data.session then
            existing.current_session = data.session
        end
        if data.all_time then
            existing.all_time = data.all_time
        end
        existing.profile_id = profile_id
        self:_set_data(existing)

        return data, nil
    end

    -- Fallback: check blackboard for saved data
    local saved = self._blackboard:get("module.runtime.telemetry_saved")
    if saved and saved.path == path then
        local existing = self:_get_data()
        if saved.data and saved.data.session then
            existing.current_session = saved.data.session
        end
        if saved.data and saved.data.all_time then
            existing.all_time = saved.data.all_time
        end
        existing.profile_id = profile_id
        self:_set_data(existing)
        return saved.data, nil
    end

    return nil, "core.read_data_file not available and no cached data"
end

-- ============================================================================
-- Event Bus Subscriptions
-- ============================================================================

---Subscribe to runtime engine events for auto-recording
function Telemetry:_subscribe()
    if not self._event_bus then
        return
    end

    local subs = self._subscriptions

    -- Action succeeded
    subs.action_succeeded = self._event_bus:subscribe("action_succeeded", function(payload)
        self:record_action(
            payload.action_id or "unknown",
            payload.action_type or "unknown",
            0,     -- duration tracked via separate mechanism
            true,
            0
        )
    end)

    -- Action failed
    subs.action_failed = self._event_bus:subscribe("action_failed", function(payload)
        self:record_action(
            payload.action_id or payload.action_type or "unknown",
            payload.action_type or "unknown",
            0,
            false,
            payload.retry_count or 0,
            payload.error
        )
    end)

    -- Operation completed
    subs.operation_completed = self._event_bus:subscribe("operation_completed", function(payload)
        self:record_operation(
            payload.op_id or "unknown",
            payload.duration_ms or 0,
            payload.actions_completed or 0,
            0
        )
    end)

    -- Operation failed
    subs.operation_failed = self._event_bus:subscribe("operation_failed", function(payload)
        self:record_operation(
            payload.op_id or "unknown",
            payload.duration_ms or 0,
            payload.actions_completed or 0,
            payload.actions_failed or 1,
            payload.deaths or 0
        )
    end)

    -- Death events (from death_sensor or runtime engine)
    subs.player_died = self._event_bus:subscribe("player_died", function(payload)
        self:record_death(payload.position, payload.killer)
    end)

    -- XP gain events
    subs.xp_gained = self._event_bus:subscribe("xp_gained", function(payload)
        self:record_xp_gained(payload.amount or 0)
    end)

    -- Gold spent events
    subs.gold_spent = self._event_bus:subscribe("gold_spent", function(payload)
        self:record_gold_spent(payload.amount or 0)
    end)

    -- Engine completed
    subs.engine_completed = self._event_bus:subscribe("engine_completed", function(payload)
        if self._active then
            self:stop(true)
        end
    end)
end

---Unsubscribe from all events
function Telemetry:_unsubscribe()
    if not self._event_bus then
        return
    end

    for token, _ in pairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
end

-- ============================================================================
-- Utility Helpers
-- ============================================================================

---Get current time in milliseconds
---@return number
function Telemetry:_get_time()
    if core and core.game_time then
        return core.game_time()
    end
    return os.clock() * 1000
end

---Encode a Lua table to JSON string
---@param data table
---@return string|nil
function Telemetry:_encode(data)
    if not data then
        return nil
    end
    if JSON and JSON.encode then
        local ok, result = pcall(JSON.encode, data)
        if ok then
            return result
        end
    end
    -- Simple fallback encoder
    local function serialize(val, indent)
        indent = indent or ""
        local t = type(val)
        if t == "string" then
            return string.format("%q", val)
        elseif t == "number" then
            return tostring(val)
        elseif t == "boolean" then
            return tostring(val)
        elseif t == "nil" then
            return "null"
        elseif t == "table" then
            local parts = {}
            local is_array = true
            local max_key = 0
            for k, v in pairs(val) do
                if type(k) ~= "number" then is_array = false end
                if type(k) == "number" and k > max_key then max_key = k end
            end
            if is_array and max_key == #val then
                for i, v in ipairs(val) do
                    table.insert(parts, serialize(v, indent .. "  "))
                end
                return "[" .. table.concat(parts, ", ") .. "]"
            else
                for k, v in pairs(val) do
                    table.insert(parts, string.format("%s%q: %s", indent .. "  ", k, serialize(v, indent .. "  ")))
                end
                return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
            end
        end
        return tostring(val)
    end
    return serialize(data)
end

---Decode a JSON string to a Lua table
---@param str string
---@return table|nil
---@return string|nil
function Telemetry:_decode(str)
    if not str or str == "" then
        return nil, "empty string"
    end
    if JSON and JSON.decode then
        local ok, result = pcall(JSON.decode, str)
        if ok then
            return result, nil
        end
        return nil, tostring(result)
    end
    -- Simple fallback: try loadstring
    local ok, result = pcall(function()
        return assert(loadstring("return " .. str))()
    end)
    if ok then
        return result, nil
    end
    return nil, "failed to parse JSON"
end

return Telemetry
