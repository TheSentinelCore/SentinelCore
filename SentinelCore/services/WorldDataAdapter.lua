local JSON = require("lib/JSON")
local ErrorCodes = require("events/ErrorCodes")
local Events = require("events/Events")
local FactionResolver = require("lib/FactionResolver")
local get_now = require("lib/TimeHelper").get_now

---@class WorldDataAdapter
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _healthy boolean
---@field private _last_health_check number
---@field private _last_dataset_check number
---@field private _pending_requests number
local WorldDataAdapter = {}
WorldDataAdapter.__index = WorldDataAdapter

---@private
---@param value any
---@return string|nil
local function normalize_vendor_faction_filter(value)
    return FactionResolver.resolve_team(value)
end

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@return WorldDataAdapter
function WorldDataAdapter:new(event_bus, blackboard, cfg)
    local o = setmetatable({}, WorldDataAdapter)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._healthy = false
    o._last_health_check = 0
    o._last_dataset_check = 0
    o._pending_requests = 0
    return o
end

---@private
---@param value string
---@return string
local function url_encode(value)
    if value == nil then
        return ""
    end
    value = tostring(value)
    value = value:gsub("\n", "\r\n")
    value = value:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return value
end

---@private
---@param path string
---@param params? table
---@return string
function WorldDataAdapter:_build_url(path, params)
    local base = self._cfg.base_url or "http://127.0.0.1:48100"
    local url = base .. path
    if not params then
        return url
    end

    local query = {}
    for key, value in pairs(params) do
        if value ~= nil then
            query[#query + 1] = url_encode(key) .. "=" .. url_encode(value)
        end
    end

    if #query > 0 then
        table.sort(query)
        url = url .. "?" .. table.concat(query, "&")
    end
    return url
end

---@private
---@param http_code number
---@param body string
---@return string
function WorldDataAdapter:_map_http_error(http_code, body)
    local parsed, _ = JSON.decode(body or "")
    if parsed and parsed.error and parsed.error.code then
        return parsed.error.code
    end

    if http_code == 0 then
        return ErrorCodes.DEP_WORLDDATA_UNAVAILABLE
    end
    if http_code == 404 then
        return ErrorCodes.MAP_NOT_SUPPORTED
    end
    if http_code >= 400 and http_code < 500 then
        return ErrorCodes.INVALID_PARAMS
    end
    return ErrorCodes.INTERNAL_ERROR
end

---@private
---@param path string
---@param params table|nil
---@param callback fun(ok: boolean, data: table|nil, error_code: string|nil)
---@param attempt? number
function WorldDataAdapter:_request(path, params, callback, attempt)
    attempt = attempt or 0

    if not core or not core.http_get then
        callback(false, nil, ErrorCodes.DEP_WORLDDATA_UNAVAILABLE)
        return
    end

    local url = self:_build_url(path, params)
    self._pending_requests = self._pending_requests + 1

    core.http_get(url, function(code, _, response)
        self._pending_requests = math.max(0, self._pending_requests - 1)

        if code == 200 then
            local parsed, err = JSON.decode(response or "")
            if not parsed then
                callback(false, nil, ErrorCodes.INTERNAL_ERROR)
                return
            end

            if parsed.success == false and parsed.error and parsed.error.code then
                callback(false, nil, parsed.error.code)
                return
            end

            callback(true, parsed, nil)
            return
        end

        local retryable = (code == 0 or code == 500 or code == 502 or code == 503 or code == 504)
        local max_retries = tonumber(self._cfg.max_retries) or 2

        if retryable and attempt < max_retries then
            -- No timer primitive available; retry immediately.
            self:_request(path, params, callback, attempt + 1)
            return
        end

        callback(false, nil, self:_map_http_error(code, response or ""))
    end)
end

---@return boolean
function WorldDataAdapter:is_healthy()
    return self._healthy == true
end

---@param callback fun(ok: boolean, error_code: string|nil)
function WorldDataAdapter:health_check(callback)
    self:_request(self._cfg.health_endpoint or "/health", nil, function(ok, data, error_code)
        if not ok then
            self._healthy = false
            callback(false, error_code or ErrorCodes.DEP_WORLDDATA_UNAVAILABLE)
            return
        end

        if type(data) == "table" and data.status and tostring(data.status):lower() ~= "ok" then
            self._healthy = false
            callback(false, ErrorCodes.DEP_WORLDDATA_UNAVAILABLE)
            return
        end

        self._healthy = true
        callback(true, nil)
    end)
end

---@param callback fun(ok: boolean, error_code: string|nil)
function WorldDataAdapter:dataset_check(callback)
    self:_request((self._cfg.api_version_prefix or "/api/v1") .. "/meta/dataset", nil, function(ok, data, error_code)
        if not ok then
            callback(false, error_code)
            return
        end

        local expected_game = tostring(self._cfg.expected_game_version or "tbc")
        local expected_source = tostring(self._cfg.expected_source or "cmangos")

        if tostring(data.game_version or ""):lower() ~= expected_game
            or tostring(data.source or ""):lower() ~= expected_source then
            callback(false, ErrorCodes.DEP_WORLDDATA_DATASET_MISMATCH)
            return
        end

        callback(true, nil)
    end)
end

---@param runtime_ctx table
---@param callback fun(ok: boolean, canonical_ctx: table|nil, error_code: string|nil)
function WorldDataAdapter:resolve_context(runtime_ctx, callback)
    if not runtime_ctx then
        callback(false, nil, ErrorCodes.CTX_UNRESOLVED)
        return
    end

    local pos = runtime_ctx.position or {}
    local path = (self._cfg.api_version_prefix or "/api/v1") .. "/context/resolve"
    local params = {
        ui_map_id = runtime_ctx.ui_map_id,
        x = pos.x,
        y = pos.y,
        z = pos.z,
        instance_type = runtime_ctx.instance_type,
    }

    self._event_bus:emit(Events.CONTEXT_RESOLVE_STARTED, {
        timestamp = get_now(),
        request = params,
    })

    self:_request(path, params, function(ok, data, error_code)
        if not ok then
            local mapped = error_code
            if mapped ~= ErrorCodes.CTX_UNRESOLVED and mapped ~= ErrorCodes.CTX_LOW_CONFIDENCE then
                mapped = ErrorCodes.CTX_UNRESOLVED
            end
            self._event_bus:emit(Events.CONTEXT_FAILED, {
                timestamp = get_now(),
                error_code = mapped,
            })
            callback(false, nil, mapped)
            return
        end

        local resolved = data.resolved == true
        local ambiguous = data.ambiguous == true
        local confidence = tonumber(data.diagnostic_confidence) or 1.0
        local min_conf = tonumber(self._cfg.min_confidence) or 0.60

        if not resolved then
            self._event_bus:emit(Events.CONTEXT_FAILED, {
                timestamp = get_now(),
                error_code = ErrorCodes.CTX_UNRESOLVED,
            })
            callback(false, nil, ErrorCodes.CTX_UNRESOLVED)
            return
        end

        if ambiguous or confidence < min_conf then
            self._event_bus:emit(Events.CONTEXT_FAILED, {
                timestamp = get_now(),
                error_code = ErrorCodes.CTX_LOW_CONFIDENCE,
            })
            callback(false, nil, ErrorCodes.CTX_LOW_CONFIDENCE)
            return
        end

        local canonical = {
            map_id = tonumber(data.canonical_map_id) or 0,
            zone_id = tonumber(data.zone_id) or 0,
            area_id = tonumber(data.area_id) or 0,
            resolved = true,
            confidence = confidence,
        }

        self._event_bus:emit(Events.CONTEXT_RESOLVED, {
            timestamp = get_now(),
            context = canonical,
        })

        callback(true, canonical, nil)
    end)
end

---@param canonical_ctx table
---@param opts table|nil
---@param callback fun(ok: boolean, vendors: table|nil, error_code: string|nil)
function WorldDataAdapter:get_nearby_vendors(canonical_ctx, opts, callback)
    if not canonical_ctx or not canonical_ctx.map_id then
        callback(false, nil, ErrorCodes.CTX_UNRESOLVED)
        return
    end

    opts = opts or {}
    local pos = opts.position or self._blackboard:get("player.position") or {}
    local path = string.format("%s/maps/%d/vendors/nearby", self._cfg.api_version_prefix or "/api/v1", tonumber(canonical_ctx.map_id) or 0)
    local faction_filter = normalize_vendor_faction_filter(opts.faction)

    local params = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = opts.radius,
        require_sell = opts.require_sell,
        require_repair = opts.require_repair,
        faction = faction_filter,
    }

    self:_request(path, params, function(ok, data, error_code)
        if not ok then
            callback(false, nil, error_code or ErrorCodes.VENDOR_FETCH_FAILED)
            return
        end

        local vendors = data.vendors or data.items
        if type(vendors) ~= "table" then
            callback(false, nil, ErrorCodes.VENDOR_FETCH_FAILED)
            return
        end

        callback(true, vendors, nil)
    end)
end

---@param now number
function WorldDataAdapter:update(now)
    now = now or (get_now())

    local health_interval = tonumber(self._cfg.health_interval or 5.0) or 5.0
    if now - self._last_health_check >= health_interval then
        self._last_health_check = now
        self:health_check(function(ok)
            self._blackboard:set("deps.world_data.healthy", ok)
        end)
    end

    local dataset_interval = tonumber(self._cfg.dataset_check_interval or 30.0) or 30.0
    if now - self._last_dataset_check >= dataset_interval then
        self._last_dataset_check = now
        self:dataset_check(function(ok, error_code)
            self._blackboard:set("deps.world_data.dataset_ok", ok)
            if not ok then
                self._blackboard:set("deps.world_data.dataset_error", error_code)
            else
                self._blackboard:clear("deps.world_data.dataset_error")
            end
        end)
    end
end

---@return number
function WorldDataAdapter:get_pending_requests()
    return self._pending_requests
end

return WorldDataAdapter
