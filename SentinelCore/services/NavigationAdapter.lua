local ErrorCodes = require("events/ErrorCodes")

---@class NavigationAdapter
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _client table|nil
---@field private _last_health_ok boolean
local NavigationAdapter = {}
NavigationAdapter.__index = NavigationAdapter

---@param event_bus EventBus
---@param blackboard Blackboard
---@return NavigationAdapter
function NavigationAdapter:new(event_bus, blackboard)
    local o = setmetatable({}, NavigationAdapter)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._client = nil
    o._last_health_ok = false
    return o
end

---@private
function NavigationAdapter:_resolve_client()
    local global_client = _G and _G.SentinelNavClient and _G.SentinelNavClient.client or nil
    if global_client ~= self._client then
        self._client = global_client
    end
    return self._client
end

---@return table|nil
function NavigationAdapter:get_client()
    return self:_resolve_client()
end

---@return boolean
---@return string|nil
function NavigationAdapter:is_available()
    local client = self:_resolve_client()
    if not client then
        return false, ErrorCodes.DEP_NAVCLIENT_MISSING
    end
    return true, nil
end

---@return boolean
function NavigationAdapter:is_server_available()
    local client = self:_resolve_client()
    if not client or type(client.is_server_available) ~= "function" then
        return false
    end

    local ok, value = pcall(client.is_server_available, client)
    if not ok then
        return false
    end
    return value == true
end

---@param callback fun(ok: boolean, error_code: string|nil)
function NavigationAdapter:health_check(callback)
    local client = self:_resolve_client()
    if not client or type(client.health_check) ~= "function" then
        callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING)
        return
    end

    client:health_check(function(ok)
        self._last_health_ok = ok == true
        if not ok then
            callback(false, ErrorCodes.DEP_NAVCLIENT_UNHEALTHY)
            return
        end
        callback(true, nil)
    end)
end

---@param destination vec3
---@param callback? fun(ok: boolean, error_code: string|nil, detail: table|nil)
function NavigationAdapter:move_to(destination, callback)
    local client = self:_resolve_client()
    if not client or type(client.move_to) ~= "function" then
        if callback then
            callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING, nil)
        end
        return
    end

    client:move_to(destination, function(ok, reason, detail)
        if callback then
            if ok then
                callback(true, nil, detail)
            else
                callback(false, reason or ErrorCodes.NAV_MOVE_FAILED, detail)
            end
        end
    end)
end

function NavigationAdapter:stop()
    local client = self:_resolve_client()
    if client and type(client.stop) == "function" then
        pcall(client.stop, client)
    end
end

---@param target vec3
---@param callback fun(reachable: boolean, error_code: string|nil, distance: number|nil)
function NavigationAdapter:validate_destination(target, callback)
    local client = self:_resolve_client()
    if not client then
        callback(false, ErrorCodes.DEP_NAVCLIENT_MISSING, nil)
        return
    end

    if type(client.validate_destination) == "function" then
        client:validate_destination(target, function(reachable, reason, distance)
            if reachable then
                callback(true, nil, distance)
            else
                callback(false, reason or ErrorCodes.NAV_MOVE_FAILED, nil)
            end
        end)
        return
    end

    callback(false, ErrorCodes.DEP_NAVCLIENT_UNHEALTHY, nil)
end

---@param from vec3
---@param to vec3
---@param callback fun(ok: boolean, cost: number|nil, error_code: string|nil)
function NavigationAdapter:estimate_path_cost(from, to, callback)
    local client = self:_resolve_client()
    if not client then
        callback(false, nil, ErrorCodes.DEP_NAVCLIENT_MISSING)
        return
    end

    if client.nav_client and type(client.nav_client.find_path) == "function" then
        client.nav_client:find_path(from, to, function(ok, data, err)
            if ok and data and data.waypoints and #data.waypoints > 0 then
                callback(true, tonumber(data.distance) or 0, nil)
            else
                callback(false, nil, err or ErrorCodes.NAV_MOVE_FAILED)
            end
        end)
        return
    end

    -- Fallback: validation API gives best-effort distance.
    self:validate_destination(to, function(reachable, reason, distance)
        if reachable then
            callback(true, tonumber(distance) or 0, nil)
        else
            callback(false, nil, reason or ErrorCodes.NAV_MOVE_FAILED)
        end
    end)
end

---@return boolean
function NavigationAdapter:get_last_health_status()
    return self._last_health_ok == true
end

function NavigationAdapter:update()
    self:_resolve_client()
    self._blackboard:set("deps.nav.available", self._client ~= nil)
    self._blackboard:set("deps.nav.server_available", self:is_server_available())
end

return NavigationAdapter
