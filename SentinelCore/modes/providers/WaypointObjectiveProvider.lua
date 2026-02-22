local Helpers = require("lib/Helpers")
local ErrorCodes = require("events/ErrorCodes")

---@private
---@param value any
---@return number
local function to_number(value)
    return tonumber(value) or 0
end

---@private
---@param waypoint any
---@return boolean
local function is_valid_waypoint(waypoint)
    if type(waypoint) ~= "table" then
        return false
    end
    local x = tonumber(waypoint.x)
    local y = tonumber(waypoint.y)
    local z = tonumber(waypoint.z)
    return x ~= nil and y ~= nil and z ~= nil
end

---@private
---@param waypoint table
---@return vec3
local function normalize_waypoint(waypoint)
    return {
        x = to_number(waypoint.x),
        y = to_number(waypoint.y),
        z = to_number(waypoint.z),
    }
end

---@class WaypointObjectiveProvider
---@field private _mode_id string
---@field private _queue_key string
---@field private _index_key string
---@field private _loop_key string
---@field private _default_loop boolean
---@field private _arrive_distance number
---@field private _reissue_secs number
---@field private _timeout_secs number
local WaypointObjectiveProvider = {}
WaypointObjectiveProvider.__index = WaypointObjectiveProvider

---@param opts table
---@return WaypointObjectiveProvider
function WaypointObjectiveProvider:new(opts)
    opts = opts or {}
    local mode_id = tostring(opts.mode_id or "mode")

    local o = setmetatable({}, WaypointObjectiveProvider)
    o._mode_id = mode_id
    o._queue_key = tostring(opts.queue_key or ("objective." .. mode_id .. ".queue"))
    o._index_key = tostring(opts.index_key or ("objective." .. mode_id .. ".queue_index"))
    o._loop_key = tostring(opts.loop_key or ("objective." .. mode_id .. ".loop"))
    o._default_loop = opts.default_loop == true
    o._arrive_distance = tonumber(opts.arrive_distance) or 5.0
    o._reissue_secs = tonumber(opts.reissue_secs) or 1.5
    o._timeout_secs = tonumber(opts.timeout_secs) or 90.0
    return o
end

---@return string
function WaypointObjectiveProvider:id()
    return string.format("%s.waypoint", self._mode_id)
end

---@private
---@param bb Blackboard
---@param queue table
---@param start_index number
---@return number|nil
function WaypointObjectiveProvider:_find_next_valid_index(bb, queue, start_index)
    if type(queue) ~= "table" or #queue < 1 then
        return nil
    end

    start_index = math.max(1, math.floor(tonumber(start_index) or 1))
    for i = start_index, #queue do
        if is_valid_waypoint(queue[i]) then
            return i
        end
    end

    local loop_enabled = bb:get(self._loop_key, self._default_loop) == true
    if loop_enabled then
        for i = 1, start_index - 1 do
            if is_valid_waypoint(queue[i]) then
                return i
            end
        end
    end

    return nil
end

---@param ctx table
---@return boolean
function WaypointObjectiveProvider:has_work(ctx)
    local bb = ctx and ctx.blackboard
    if not bb or type(bb.get) ~= "function" then
        return false
    end

    local queue = bb:get(self._queue_key)
    if type(queue) ~= "table" or #queue < 1 then
        return false
    end

    local start_index = tonumber(bb:get(self._index_key, 1)) or 1
    return self:_find_next_valid_index(bb, queue, start_index) ~= nil
end

---@param ctx table
---@return table|nil
---@return string|nil
function WaypointObjectiveProvider:acquire(ctx)
    local bb = ctx and ctx.blackboard
    if not bb or type(bb.get) ~= "function" or type(bb.set) ~= "function" then
        return nil, ErrorCodes.OBJECTIVE_PROVIDER_INVALID
    end

    local queue = bb:get(self._queue_key)
    if type(queue) ~= "table" or #queue < 1 then
        return nil, ErrorCodes.OBJECTIVE_NONE_AVAILABLE
    end

    local start_index = tonumber(bb:get(self._index_key, 1)) or 1
    local index = self:_find_next_valid_index(bb, queue, start_index)
    if not index then
        return nil, ErrorCodes.OBJECTIVE_NONE_AVAILABLE
    end

    if index ~= start_index then
        bb:set(self._index_key, index)
    end

    local waypoint = queue[index]
    local destination = normalize_waypoint(waypoint)
    local now = tonumber(ctx and ctx.now) or ((core and core.time and core.time()) or 0)
    local label = waypoint.label
    if type(label) ~= "string" or label == "" then
        label = string.format("%s waypoint %d/%d", self._mode_id, index, #queue)
    end

    return {
        id = string.format("%s-%d-%d", self._mode_id, index, math.floor(now * 1000)),
        kind = "move",
        label = label,
        index = index,
        queue_size = #queue,
        destination = destination,
        arrive_distance = tonumber(waypoint.arrive_distance) or self._arrive_distance,
        reissue_secs = tonumber(waypoint.reissue_secs) or self._reissue_secs,
        timeout_secs = tonumber(waypoint.timeout_secs) or self._timeout_secs,
    }, nil
end

---@private
---@param objective table
---@param services table|nil
---@param now number
---@return boolean
---@return string|nil
function WaypointObjectiveProvider:_issue_move(objective, services, now)
    local navigation = services and services.navigation
    if not navigation or type(navigation.move_to) ~= "function" then
        return false, ErrorCodes.DEP_NAVCLIENT_MISSING
    end

    objective._move_pending = true
    objective._last_move_issue_at = now
    navigation:move_to(objective.destination, function(ok, error_code)
        objective._move_pending = false
        objective._move_result_ok = ok == true
        objective._move_error = ok and nil or (error_code or ErrorCodes.NAV_MOVE_FAILED)
    end)

    return true, nil
end

---@param objective table
---@param ctx table
---@return string
---@return table|nil
function WaypointObjectiveProvider:tick(objective, ctx)
    if type(objective) ~= "table" or type(objective.destination) ~= "table" then
        return "failure", { error_code = ErrorCodes.OBJECTIVE_EXECUTION_FAILED }
    end

    local bb = ctx and ctx.blackboard
    if not bb or type(bb.get) ~= "function" or type(bb.set) ~= "function" then
        return "failure", { error_code = ErrorCodes.OBJECTIVE_PROVIDER_INVALID }
    end

    local now = tonumber(ctx.now) or ((core and core.time and core.time()) or 0)
    objective._started_at = objective._started_at or now

    local player_pos = bb:get("player.position")
    local dist = Helpers.distance_3d(player_pos, objective.destination)
    local arrive_distance = tonumber(objective.arrive_distance) or self._arrive_distance
    if dist <= arrive_distance then
        local queue = bb:get(self._queue_key) or {}
        local next_index = (tonumber(objective.index) or 1) + 1
        local loop_enabled = bb:get(self._loop_key, self._default_loop) == true
        if next_index > #queue then
            next_index = loop_enabled and 1 or (#queue + 1)
        end
        bb:set(self._index_key, next_index)

        return "success", {
            distance = dist,
            next_index = next_index,
        }
    end

    if objective._move_result_ok == false and objective._move_error then
        return "failure", {
            error_code = objective._move_error,
            distance = dist,
        }
    end

    local timeout_secs = tonumber(objective.timeout_secs) or self._timeout_secs
    if timeout_secs > 0 and (now - objective._started_at) > timeout_secs then
        return "failure", {
            error_code = ErrorCodes.ACTION_TIMEOUT,
            distance = dist,
        }
    end

    local reissue_secs = tonumber(objective.reissue_secs) or self._reissue_secs
    if objective._last_move_issue_at == nil or (now - objective._last_move_issue_at) >= reissue_secs then
        local issued, issue_err = self:_issue_move(objective, ctx.services, now)
        if not issued then
            return "failure", {
                error_code = issue_err or ErrorCodes.NAV_MOVE_FAILED,
                distance = dist,
            }
        end
    end

    return "running", {
        distance = dist,
    }
end

---@param objective table
---@param ctx table
---@param reason string
function WaypointObjectiveProvider:abort(objective, ctx, reason)
    objective._move_pending = false
end

---@param ctx table
function WaypointObjectiveProvider:on_mode_enter(ctx)
    local bb = ctx and ctx.blackboard
    if not bb or type(bb.get) ~= "function" or type(bb.set) ~= "function" then
        return
    end

    local queue = bb:get(self._queue_key)
    if type(queue) ~= "table" or #queue < 1 then
        return
    end

    local index = tonumber(bb:get(self._index_key, 1)) or 1
    if index < 1 or index > (#queue + 1) then
        bb:set(self._index_key, 1)
    end
end

return WaypointObjectiveProvider
