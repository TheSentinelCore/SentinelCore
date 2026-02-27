---@class NavigationService
---HTTP client for the SentinelNavServer pathfinding REST API.
---Ported from core/Navigation.lua with EventBus/Blackboard integration.
---@field _event_bus EventBus
---@field _bb Blackboard
---@field _base_url string
---@field _max_retries number
---@field _game string|nil
local NavigationService = {}
NavigationService.__index = NavigationService

local JSON = require("lib/JSON")
local izi = require("common/izi_sdk")
local Events = require("events/Events")

local _vec3_ctor_checked = false
local _vec3_ctor = nil
local _vec3_fallback_mt = nil

local function resolve_vec3_ctor()
    if _vec3_ctor_checked then
        return _vec3_ctor
    end
    _vec3_ctor_checked = true

    local global_vec3 = rawget(_G, "vec3")
    if type(global_vec3) == "table" and type(global_vec3.new) == "function" then
        _vec3_ctor = global_vec3.new
        return _vec3_ctor
    end

    local ok, vec3_mod = pcall(require, "common/geometry/vector_3")
    if ok and type(vec3_mod) == "table" and type(vec3_mod.new) == "function" then
        _vec3_ctor = vec3_mod.new
    end
    return _vec3_ctor
end

local function fallback_vec3(x, y, z)
    if not _vec3_fallback_mt then
        _vec3_fallback_mt = {
            __index = {
                dist_to = function(self, other)
                    local dx = (other.x or 0) - (self.x or 0)
                    local dy = (other.y or 0) - (self.y or 0)
                    local dz = (other.z or 0) - (self.z or 0)
                    return math.sqrt(dx * dx + dy * dy + dz * dz)
                end,
                dist_to_ignore_z = function(self, other)
                    local dx = (other.x or 0) - (self.x or 0)
                    local dy = (other.y or 0) - (self.y or 0)
                    return math.sqrt(dx * dx + dy * dy)
                end,
                clone = function(self)
                    return fallback_vec3(self.x, self.y, self.z)
                end,
            },
        }
    end
    return setmetatable({
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        z = tonumber(z) or 0,
    }, _vec3_fallback_mt)
end

local function to_vec3(pos)
    if not pos then
        return nil
    end

    if type(pos) ~= "table" then
        return pos
    end

    if type(pos.dist_to) == "function" then
        return pos
    end

    local x = pos.x or pos[1]
    local y = pos.y or pos[2]
    local z = pos.z or pos[3]
    local ctor = resolve_vec3_ctor()
    if ctor then
        local ok, out = pcall(ctor, x, y, z)
        if ok and out then
            return out
        end
    end
    return fallback_vec3(x, y, z)
end

-- ============================================================================
-- Lookup Tables (verbatim from Navigation.lua)
-- ============================================================================

--- UiMapID -> SentinelNavServer continent ID (Map.dbc MapID)
--- 0 = Eastern Kingdoms, 1 = Kalimdor, 530 = Outland, 571 = Northrend
local UI_MAP_TO_CONTINENT = {
    -- Eastern Kingdoms (0)
    [124] = 0,
    [220] = 0,
    [225] = 0,
    [226] = 0,
    [227] = 0,
    [228] = 0,
    [229] = 0,
    [230] = 0,
    [231] = 0,
    [232] = 0,
    [233] = 0,
    [242] = 0,
    [243] = 0,
    [250] = 0,
    [251] = 0,
    [252] = 0,
    [253] = 0,
    [254] = 0,
    [255] = 0,
    [287] = 0,
    [288] = 0,
    [289] = 0,
    [290] = 0,
    [291] = 0,
    [292] = 0,
    [302] = 0,
    [303] = 0,
    [304] = 0,
    [305] = 0,
    [306] = 0,
    [307] = 0,
    [308] = 0,
    [309] = 0,
    [310] = 0,
    [311] = 0,
    [312] = 0,
    [313] = 0,
    [314] = 0,
    [315] = 0,
    [316] = 0,
    [317] = 0,
    [318] = 0,
    [333] = 0,
    [335] = 0,
    [336] = 0,
    [337] = 0,
    [350] = 0,
    [351] = 0,
    [352] = 0,
    [353] = 0,
    [354] = 0,
    [355] = 0,
    [356] = 0,
    [357] = 0,
    [358] = 0,
    [359] = 0,
    [360] = 0,
    [361] = 0,
    [362] = 0,
    [363] = 0,
    [364] = 0,
    [365] = 0,
    [366] = 0,
    [1415] = 0,
    [1416] = 0,
    [1417] = 0,
    [1418] = 0,
    [1419] = 0,
    [1420] = 0,
    [1421] = 0,
    [1422] = 0,
    [1423] = 0,
    [1424] = 0,
    [1425] = 0,
    [1426] = 0,
    [1427] = 0,
    [1428] = 0,
    [1429] = 0,
    [1430] = 0,
    [1431] = 0,
    [1432] = 0,
    [1433] = 0,
    [1434] = 0,
    [1435] = 0,
    [1436] = 0,
    [1437] = 0,
    [1453] = 0,
    [1458] = 0,
    [1463] = 0,
    [1941] = 0,
    [1942] = 0,
    [1954] = 0,
    [1957] = 0,
    -- Kalimdor (1)
    [130] = 1,
    [131] = 1,
    [213] = 1,
    [219] = 1,
    [221] = 1,
    [222] = 1,
    [223] = 1,
    [234] = 1,
    [235] = 1,
    [236] = 1,
    [237] = 1,
    [238] = 1,
    [239] = 1,
    [240] = 1,
    [247] = 1,
    [248] = 1,
    [273] = 1,
    [274] = 1,
    [279] = 1,
    [280] = 1,
    [281] = 1,
    [300] = 1,
    [301] = 1,
    [319] = 1,
    [320] = 1,
    [321] = 1,
    [329] = 1,
    [1411] = 1,
    [1412] = 1,
    [1413] = 1,
    [1414] = 1,
    [1438] = 1,
    [1439] = 1,
    [1440] = 1,
    [1441] = 1,
    [1442] = 1,
    [1443] = 1,
    [1444] = 1,
    [1445] = 1,
    [1446] = 1,
    [1447] = 1,
    [1448] = 1,
    [1449] = 1,
    [1450] = 1,
    [1451] = 1,
    [1452] = 1,
    [1454] = 1,
    [1455] = 1,
    [1456] = 1,
    [1457] = 1,
    [1464] = 1,
    [1943] = 1,
    [1947] = 1,
    [1950] = 1,
    -- Outland (530)
    [246] = 530,
    [256] = 530,
    [257] = 530,
    [258] = 530,
    [259] = 530,
    [260] = 530,
    [261] = 530,
    [262] = 530,
    [263] = 530,
    [264] = 530,
    [265] = 530,
    [266] = 530,
    [267] = 530,
    [268] = 530,
    [269] = 530,
    [270] = 530,
    [271] = 530,
    [272] = 530,
    [330] = 530,
    [331] = 530,
    [332] = 530,
    [334] = 530,
    [339] = 530,
    [347] = 530,
    [987] = 530,
    [1554] = 530,
    [1555] = 530,
    [1956] = 530,
    [1944] = 530,
    [1945] = 530,
    [1946] = 530,
    [1948] = 530,
    [1949] = 530,
    [1951] = 530,
    [1952] = 530,
    [1953] = 530,
    [1955] = 530,
    -- Northrend (571)
    [113] = 571,
    [114] = 571,
    [115] = 571,
    [116] = 571,
    [117] = 571,
    [118] = 571,
    [119] = 571,
    [120] = 571,
    [121] = 571,
    [123] = 571,
    [125] = 571,
    [126] = 571,
    [127] = 571,
    [128] = 571,
    [129] = 571,
    [132] = 571,
    [133] = 571,
    [134] = 571,
    [135] = 571,
    [136] = 571,
    [137] = 571,
    [138] = 571,
    [139] = 571,
    [140] = 571,
    [141] = 571,
    [142] = 571,
    [143] = 571,
    [144] = 571,
    [145] = 571,
    [146] = 571,
    [147] = 571,
    [148] = 571,
    [149] = 571,
    [150] = 571,
    [151] = 571,
    [152] = 571,
    [153] = 571,
    [154] = 571,
    [155] = 571,
    [156] = 571,
    [157] = 571,
    [158] = 571,
    [159] = 571,
    [160] = 571,
    [161] = 571,
    [162] = 571,
    [163] = 571,
    [164] = 571,
    [165] = 571,
    [166] = 571,
    [167] = 571,
    [168] = 571,
    [169] = 571,
    [170] = 571,
    [171] = 571,
    [172] = 571,
    [173] = 571,
    [183] = 571,
    [184] = 571,
    [185] = 571,
    [186] = 571,
    [187] = 571,
    [188] = 571,
    [189] = 571,
    [190] = 571,
    [191] = 571,
    [192] = 571,
    [193] = 571,
    [200] = 571,
    [988] = 571,
    [1375] = 571,
}

--- Indoor (dungeon/raid) UiMapIDs
local INDOOR_UI_MAPS = {
    -- Eastern Kingdoms dungeons/raids
    [220] = true,
    [225] = true,
    [226] = true,
    [227] = true,
    [228] = true,
    [229] = true,
    [230] = true,
    [231] = true,
    [232] = true,
    [233] = true,
    [242] = true,
    [243] = true,
    [250] = true,
    [251] = true,
    [252] = true,
    [253] = true,
    [254] = true,
    [255] = true,
    [287] = true,
    [288] = true,
    [289] = true,
    [290] = true,
    [291] = true,
    [292] = true,
    [302] = true,
    [303] = true,
    [304] = true,
    [305] = true,
    [306] = true,
    [307] = true,
    [308] = true,
    [309] = true,
    [310] = true,
    [311] = true,
    [312] = true,
    [313] = true,
    [314] = true,
    [315] = true,
    [316] = true,
    [317] = true,
    [318] = true,
    [333] = true,
    [335] = true,
    [336] = true,
    [337] = true,
    [350] = true,
    [351] = true,
    [352] = true,
    [353] = true,
    [354] = true,
    [355] = true,
    [356] = true,
    [357] = true,
    [358] = true,
    [359] = true,
    [360] = true,
    [361] = true,
    [362] = true,
    [363] = true,
    [364] = true,
    [365] = true,
    [366] = true,
    [1463] = true,
    -- Kalimdor dungeons/raids
    [130] = true,
    [131] = true,
    [213] = true,
    [219] = true,
    [221] = true,
    [222] = true,
    [223] = true,
    [234] = true,
    [235] = true,
    [236] = true,
    [237] = true,
    [238] = true,
    [239] = true,
    [240] = true,
    [247] = true,
    [248] = true,
    [273] = true,
    [274] = true,
    [279] = true,
    [280] = true,
    [281] = true,
    [300] = true,
    [301] = true,
    [319] = true,
    [320] = true,
    [321] = true,
    [329] = true,
    -- Outland dungeons/raids
    [246] = true,
    [256] = true,
    [257] = true,
    [258] = true,
    [259] = true,
    [260] = true,
    [261] = true,
    [262] = true,
    [263] = true,
    [264] = true,
    [265] = true,
    [266] = true,
    [267] = true,
    [268] = true,
    [269] = true,
    [270] = true,
    [271] = true,
    [272] = true,
    [330] = true,
    [331] = true,
    [332] = true,
    [334] = true,
    [339] = true,
    [347] = true,
    [1554] = true,
    [1555] = true,
    -- Northrend dungeons/raids
    [129] = true,
    [132] = true,
    [133] = true,
    [134] = true,
    [135] = true,
    [136] = true,
    [137] = true,
    [138] = true,
    [139] = true,
    [140] = true,
    [141] = true,
    [142] = true,
    [143] = true,
    [144] = true,
    [145] = true,
    [146] = true,
    [147] = true,
    [148] = true,
    [149] = true,
    [150] = true,
    [151] = true,
    [152] = true,
    [153] = true,
    [154] = true,
    [155] = true,
    [156] = true,
    [157] = true,
    [158] = true,
    [159] = true,
    [160] = true,
    [161] = true,
    [162] = true,
    [163] = true,
    [164] = true,
    [165] = true,
    [166] = true,
    [167] = true,
    [168] = true,
    [169] = true,
    [171] = true,
    [172] = true,
    [173] = true,
    [183] = true,
    [184] = true,
    [185] = true,
    [186] = true,
    [187] = true,
    [188] = true,
    [189] = true,
    [190] = true,
    [191] = true,
    [192] = true,
    [193] = true,
    [200] = true,
    [1375] = true,
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

---Convert response path array to vec3-compatible points.
---@param data table Response data with optional .path field
---@return table[]
local function extract_waypoints(data)
    local waypoints = {}
    if data.path then
        for i = 1, #data.path do
            local pt = data.path[i]
            waypoints[#waypoints + 1] = to_vec3(pt)
        end
    end
    return waypoints
end

---Format vec3[] as semicolon-separated "x,y,z;x,y,z" string
---@param points table[]
---@return string
local function format_points(points)
    local parts = {}
    for i = 1, #points do
        local p = points[i]
        parts[#parts + 1] = string.format("%g,%g,%g", p.x, p.y, p.z)
    end
    return table.concat(parts, ";")
end

---Serialize avoidance zones into params.avoid
---@param params table
---@param zones table[]|nil
local function apply_avoid_zones(params, zones)
    if not zones or #zones == 0 then return end
    local parts = {}
    for _, zone in ipairs(zones) do
        parts[#parts + 1] = string.format(
            "%g,%g,%g,%g,%g", zone.x, zone.y, zone.z, zone.radius, zone.cost)
    end
    params.avoid = table.concat(parts, ";")
end

---Resolve physical map ID for navigation (mmap file lookup).
---Uses core.get_instance_id() which returns the server's physical map ID directly,
---avoiding the need for UiMapID-to-continent translation tables.
---@return number
local function get_continent_id()
    return core.get_instance_id()
end

---Check if current UiMapID is indoor
---@return boolean
local function is_indoor()
    local ui_map_id = core.get_map_id()
    return ui_map_id ~= nil and INDOOR_UI_MAPS[ui_map_id] == true
end

---Invoke consumer callback safely; callback errors must not break nav loop.
---@param callback function|nil
---@param success boolean
---@param data table|nil
---@param err string|nil
local function invoke_callback(callback, success, data, err)
    if not callback then
        return
    end
    local ok, callback_err = pcall(callback, success, data, err)
    if not ok and core and core.log_error then
        core.log_error("[NavigationService] Callback error: " .. tostring(callback_err))
    end
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param event_bus EventBus
---@param blackboard Blackboard
---@param config? table { base_url?, max_retries? }
---@return NavigationService
function NavigationService:new(event_bus, blackboard, config)
    local o = setmetatable({}, self)
    o._event_bus = event_bus
    o._bb = blackboard

    local ok_cfg, ServerConfig = pcall(require, "config/server")
    if not ok_cfg then ServerConfig = { base_url = "http://127.0.0.1:47110", max_retries = 3 } end

    o._base_url = (config and config.base_url) or ServerConfig.base_url
    o._max_retries = (config and config.max_retries) or ServerConfig.max_retries
    o._game = (config and config.game) or ServerConfig.game

    o._bb:set("server.connected", false)
    o._bb:set("server.failures", 0)
    o._bb:set("server.last_success", 0)

    return o
end

-- ============================================================================
-- Infrastructure
-- ============================================================================

---Build full URL from endpoint and parameter table
---@param endpoint string e.g. "/api/v1/path"
---@param params? table key-value pairs
---@return string
function NavigationService:_build_url(endpoint, params)
    local url = self._base_url .. endpoint
    -- Inject game identifier from config if set and not already in params
    local game = self._game
    if game and (not params or not params.game) then
        params = params or {}
        params.game = game
    end
    if not params or next(params) == nil then return url end

    local parts = {}
    for k, v in pairs(params) do
        if type(v) == "table" then
            for _, item in ipairs(v) do
                parts[#parts + 1] = k .. "=" .. tostring(item)
            end
        else
            local val
            if type(v) == "number" then
                val = string.format("%g", v)
            elseif type(v) == "boolean" then
                val = v and "true" or "false"
            else
                val = tostring(v)
            end
            parts[#parts + 1] = k .. "=" .. val
        end
    end
    return url .. "?" .. table.concat(parts, "&")
end

---Async HTTP GET with exponential-backoff retry
---@param url string
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param attempt? number
function NavigationService:_request(url, callback, attempt)
    attempt = attempt or 1

    local function finalize_transport_failure(code, err_msg, disconnect_reason)
        local failures = self._bb:get("server.failures", 0) + 1
        self._bb:set("server.failures", failures)

        if failures >= 3 then
            local was_connected = self._bb:get("server.connected", false)
            self._bb:set("server.connected", false)
            if was_connected then
                self._event_bus:emit(Events.SERVER_DISCONNECTED, {
                    reason = disconnect_reason or err_msg or ("HTTP " .. tostring(code)),
                })
            end
        end

        self._event_bus:emit(Events.SERVER_ERROR, {
            error = err_msg,
            failures = failures,
            code = code,
            url = url,
        })
        invoke_callback(callback, false, nil, err_msg)
    end

    core.http_get(url, function(code, content_type, response, headers)
        -- Success path
        if code == 200 then
            local ok, data = pcall(JSON.decode, response)
            if not ok or not data then
                finalize_transport_failure(code, "JSON parse error", "JSON parse error")
                return
            end

            local was_connected = self._bb:get("server.connected", false)
            self._bb:set("server.connected", true)
            self._bb:set("server.failures", 0)
            self._bb:set("server.last_success", core.time())

            if not was_connected then
                self._event_bus:emit(Events.SERVER_CONNECTED, {})
            end

            if data.success == false then
                local msg = data.error or "Server returned success=false"
                self._event_bus:emit(Events.SERVER_ERROR, {
                    error = msg,
                    failures = 0,
                    code = code,
                    url = url,
                    domain_error = true,
                })
                invoke_callback(callback, false, nil, msg)
                return
            end

            invoke_callback(callback, true, data, nil)
            return
        end

        -- Retryable?
        local retryable = (code == 0 or code == 500 or code == 502
            or code == 503 or code == 504)

        if retryable and attempt < self._max_retries then
            local delay_secs = 0.5 * (2 ^ (attempt - 1))
            self._event_bus:emit(Events.SERVER_RETRY, {
                code = code,
                attempt = attempt,
                next_attempt = attempt + 1,
                max_retries = self._max_retries,
                delay_secs = delay_secs,
                url = url,
            })
            izi.after(delay_secs, function()
                self:_request(url, callback, attempt + 1)
            end)
            return
        end

        local err_msg = "HTTP " .. tostring(code)
        if response and response ~= "" then
            local ok_parse, err_data = pcall(JSON.decode, response)
            if ok_parse and err_data and err_data.error then
                err_msg = err_msg .. ": " .. err_data.error
            end
        end
        finalize_transport_failure(code, err_msg, err_msg)
    end)
end

-- ============================================================================
-- Availability
-- ============================================================================

function NavigationService:is_available()
    return self._bb:get("server.connected", false)
end

function NavigationService:get_consecutive_failures()
    return self._bb:get("server.failures", 0)
end

function NavigationService:reset()
    self._bb:set("server.connected", false)
    self._bb:set("server.failures", 0)
    self._bb:set("server.last_success", 0)
end

-- ============================================================================
-- Core Pathfinding
-- ============================================================================

---Request a path between two points
---@param start_pos table {x, y, z}
---@param dest table {x, y, z}
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:find_path(start_pos, dest, callback, opts)
    if not start_pos or not dest then
        invoke_callback(callback, false, nil, "Missing start or dest")
        return
    end
    opts = opts or {}
    local endpoint = opts.anti_detection and "/api/v1/path-random" or "/api/v1/path"
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x,
        start_y = start_pos.y,
        start_z = start_pos.z,
        end_x = dest.x,
        end_y = dest.y,
        end_z = dest.z,
    }
    if opts.optimize ~= nil then params.optimize = opts.optimize end
    if opts.max_deviation then params.max_deviation = opts.max_deviation end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end

    self:_request(self:_build_url(endpoint, params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        local wps = extract_waypoints(data)
        if #wps == 0 then
            invoke_callback(callback, false, nil, "Empty path")
            return
        end
        invoke_callback(callback, true, {
            waypoints = wps,
            distance = data.distance or 0,
            partial = data.partial or false,
            computation_time_ms = data.computation_time_ms or 0,
        }, nil)
    end)
end

---Plan TSP-optimized route through multiple nodes
---@param nodes table[] At least 2 node positions
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:find_route_tsp(nodes, callback, opts)
    if not nodes or #nodes < 2 then
        invoke_callback(callback, false, nil, "Need at least 2 nodes")
        return
    end
    opts = opts or {}
    local start_pos = opts.start_pos
    if not start_pos then
        local player = core.object_manager.get_local_player()
        if player and player:is_valid() then
            start_pos = player:get_position()
        else
            invoke_callback(callback, false, nil, "No start position")
            return
        end
    end
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x,
        start_y = start_pos.y,
        start_z = start_pos.z,
        points = format_points(nodes),
    }
    if opts.return_to_start then params.return_to_start = true end
    if opts.weights then
        if type(opts.weights) == "table" then
            local wparts = {}
            for i = 1, #opts.weights do wparts[i] = string.format("%g", opts.weights[i]) end
            params.weights = table.concat(wparts, ";")
        else
            params.weights = opts.weights
        end
    end
    if opts.optimize ~= nil then params.optimize = opts.optimize end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end
    apply_avoid_zones(params, opts.avoid_zones)

    self:_request(self:_build_url("/api/v1/path-tsp", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        local visit_order = {}
        if data.visit_order then
            for i = 1, #data.visit_order do
                visit_order[#visit_order + 1] = data.visit_order[i] + 1
            end
        end
        invoke_callback(callback, true, {
            waypoints = extract_waypoints(data),
            visit_order = visit_order,
            leg_boundaries = data.leg_boundaries or {},
            leg_distances = data.leg_distances or {},
            total_distance = data.total_distance or 0,
        }, nil)
    end)
end

---Plan ordered multi-stop route
---@param stops table[]
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:find_route_multi(stops, callback, opts)
    if not stops or #stops < 2 then
        invoke_callback(callback, false, nil, "Need at least 2 stops")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        stops = format_points(stops),
    }
    if opts.optimize ~= nil then params.optimize = opts.optimize end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end
    apply_avoid_zones(params, opts.avoid_zones)

    self:_request(self:_build_url("/api/v1/path-multi", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            waypoints = extract_waypoints(data),
            leg_boundaries = data.leg_boundaries or {},
            leg_distances = data.leg_distances or {},
            total_distance = data.total_distance or 0,
        }, nil)
    end)
end

---Validate remaining path
---@param current_pos table
---@param waypoints table[]
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:check_path(current_pos, waypoints, callback, opts)
    if not current_pos or not waypoints or #waypoints == 0 then
        invoke_callback(callback, false, nil, "Missing pos or waypoints")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        current_x = current_pos.x,
        current_y = current_pos.y,
        current_z = current_pos.z,
        waypoints = format_points(waypoints),
    }
    if opts.max_check then params.max_check = opts.max_check end

    self:_request(self:_build_url("/api/v1/path/check", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            valid = data.valid or false,
            first_invalid_segment = data.first_invalid_segment,
            player_on_navmesh = data.player_on_navmesh or false,
        }, nil)
    end)
end

---Request path with corridor widths
---@param start_pos table
---@param dest table
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:find_path_corridor(start_pos, dest, callback, opts)
    if not start_pos or not dest then
        invoke_callback(callback, false, nil, "Missing start or dest")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x,
        start_y = start_pos.y,
        start_z = start_pos.z,
        end_x = dest.x,
        end_y = dest.y,
        end_z = dest.z,
    }
    if opts.probe_distance then params.probe_distance = opts.probe_distance end
    if opts.optimize ~= nil then params.optimize = opts.optimize end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end
    apply_avoid_zones(params, opts.avoid_zones)

    self:_request(self:_build_url("/api/v1/path/corridor", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        local wps = extract_waypoints(data)
        if #wps == 0 then
            invoke_callback(callback, false, nil, "Empty path")
            return
        end
        invoke_callback(callback, true, {
            waypoints = wps,
            corridor_widths = data.corridor_widths or {},
            distance = data.distance or 0,
            partial = data.partial or false,
            computation_time_ms = data.computation_time_ms or 0,
        }, nil)
    end)
end

-- ============================================================================
-- Avoidance Pathfinding
-- ============================================================================

---Request a path with avoidance zones (falls back to find_path if no zones)
---@param start_pos table
---@param dest table
---@param avoid_zones table[]
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:find_path_avoid(start_pos, dest, avoid_zones, callback, opts)
    if not avoid_zones or #avoid_zones == 0 then
        return self:find_path(start_pos, dest, callback, opts)
    end
    if not start_pos or not dest then
        invoke_callback(callback, false, nil, "Missing start or dest")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x,
        start_y = start_pos.y,
        start_z = start_pos.z,
        end_x = dest.x,
        end_y = dest.y,
        end_z = dest.z,
    }
    if opts.optimize ~= nil then params.optimize = opts.optimize end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end
    apply_avoid_zones(params, avoid_zones)

    self:_request(self:_build_url("/api/v1/path-avoid", params), function(ok, data, err)
        if not ok then
            -- Fall back to regular pathfinding
            return self:find_path(start_pos, dest, callback, opts)
        end
        local wps = extract_waypoints(data)
        if #wps == 0 then
            invoke_callback(callback, false, nil, "Empty path")
            return
        end
        invoke_callback(callback, true, {
            waypoints = wps,
            distance = data.distance or 0,
            partial = data.partial or false,
            computation_time_ms = data.computation_time_ms or 0,
        }, nil)
    end)
end

-- ============================================================================
-- Spatial Queries
-- ============================================================================

---Raycast between two points on the navmesh
---@param start_pos table
---@param dest table
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:raycast(start_pos, dest, callback, opts)
    if not start_pos or not dest then
        invoke_callback(callback, false, nil, "Missing start or dest")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x,
        start_y = start_pos.y,
        start_z = start_pos.z,
        end_x = dest.x,
        end_y = dest.y,
        end_z = dest.z,
    }
    self:_request(self:_build_url("/api/v1/raycast", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            hit = data.hit or false,
            t = data.t or 1.0,
        }, nil)
    end)
end

---Get navmesh height at position
---@param pos table
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:get_height(pos, callback, opts)
    if not pos then
        invoke_callback(callback, false, nil, "Missing position")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        x = pos.x,
        y = pos.y,
        z = pos.z,
    }
    self:_request(self:_build_url("/api/v1/height", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, { height = data.height }, nil)
    end)
end

---Get all navmesh heights at XY position (multi-layer)
---@param pos table
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:get_all_heights(pos, callback, opts)
    if not pos then
        invoke_callback(callback, false, nil, "Missing position")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        x = pos.x,
        y = pos.y,
    }
    if pos.z then params.z = pos.z end
    if opts.xy_extent then params.xy_extent = opts.xy_extent end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.max_polys then params.max_polys = opts.max_polys end
    if opts.cluster_tolerance then params.cluster_tolerance = opts.cluster_tolerance end
    if opts.filter_unreachable then params.filter_unreachable = true end
    if opts.from_pos then
        params.from_x = opts.from_pos.x
        params.from_y = opts.from_pos.y
        params.from_z = opts.from_pos.z
    end

    self:_request(self:_build_url("/api/v1/heights", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            heights = data.heights or {},
            count = data.count or 0,
        }, nil)
    end)
end

---Get random point on navmesh
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:random_point(callback, opts)
    opts = opts or {}
    local params = { map_id = opts.map_id or get_continent_id() }
    if opts.center and opts.radius then
        params.center_x = opts.center.x
        params.center_y = opts.center.y
        params.center_z = opts.center.z
        params.radius = opts.radius
    end
    self:_request(self:_build_url("/api/v1/random", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, { point = to_vec3({ x = data.x, y = data.y, z = data.z }) }, nil)
    end)
end

-- ============================================================================
-- Tactical
-- ============================================================================

---Calculate flee path away from threats
---@param player_pos table
---@param threats table[]
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:flee(player_pos, threats, callback, opts)
    if not player_pos or not threats or #threats == 0 then
        invoke_callback(callback, false, nil, "Missing player_pos or threats")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        player_x = player_pos.x,
        player_y = player_pos.y,
        player_z = player_pos.z,
        threats = format_points(threats),
    }
    if opts.flee_distance then params.flee_distance = opts.flee_distance end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end
    apply_avoid_zones(params, opts.avoid_zones)

    self:_request(self:_build_url("/api/v1/tactical/flee", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            waypoints = extract_waypoints(data),
            distance = data.distance or 0,
            min_threat_distance = data.min_threat_distance or 0,
        }, nil)
    end)
end

---Calculate kite path around a target
---@param player_pos table
---@param target_pos table
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table
function NavigationService:kite(player_pos, target_pos, callback, opts)
    if not player_pos or not target_pos then
        invoke_callback(callback, false, nil, "Missing player_pos or target_pos")
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        player_x = player_pos.x,
        player_y = player_pos.y,
        player_z = player_pos.z,
        target_x = target_pos.x,
        target_y = target_pos.y,
        target_z = target_pos.z,
    }
    params.kite_radius = opts.kite_radius or 8.0
    if opts.arc_degrees then params.arc_degrees = opts.arc_degrees end
    if opts.direction then params.direction = opts.direction end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end
    if opts.string_pull_deviation then params.string_pull_deviation = opts.string_pull_deviation end
    if opts.string_pull_heading then params.string_pull_heading = opts.string_pull_heading end
    if opts.string_pull_wall_dist then params.string_pull_wall_dist = opts.string_pull_wall_dist end
    if opts.densify_segment_length then params.densify_segment_length = opts.densify_segment_length end

    self:_request(self:_build_url("/api/v1/tactical/kite", params), function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            waypoints = extract_waypoints(data),
            waypoint_count = data.waypoint_count or 0,
        }, nil)
    end)
end

-- ============================================================================
-- Health
-- ============================================================================

---Check server health
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
function NavigationService:health_check(callback)
    self:_request(self._base_url .. "/health", function(ok, data, err)
        if not ok then
            invoke_callback(callback, false, nil, err)
            return
        end
        invoke_callback(callback, true, {
            status = data.status,
            version = data.version,
            uptime_secs = data.uptime_secs,
            loaded_maps = data.loaded_maps,
        }, nil)
    end)
end

-- ============================================================================
-- Static / Utility
-- ============================================================================

function NavigationService.is_indoor()
    return is_indoor()
end

function NavigationService.get_continent_id()
    return get_continent_id()
end

-- ============================================================================
-- Config
-- ============================================================================

function NavigationService:update_config(overrides)
    if not overrides then return end
    if overrides.base_url then self._base_url = overrides.base_url end
    if overrides.max_retries then self._max_retries = overrides.max_retries end
    if overrides.game ~= nil then self._game = overrides.game end
end

-- ============================================================================
-- Tests
-- ============================================================================

function NavigationService._test()
    local results = {}

    -- Test extract_waypoints
    local data_nil = extract_waypoints({})
    results["extract_nil"] = (#data_nil == 0)

    local data_valid = extract_waypoints({ path = { { x = 1, y = 2, z = 3 }, { x = 4, y = 5, z = 6 } } })
    results["extract_valid_count"] = (#data_valid == 2)
    results["extract_valid_x"] = (data_valid[1].x == 1)
    results["extract_valid_z"] = (data_valid[2].z == 6)
    results["extract_vec3_compat"] = (type(data_valid[1].dist_to) == "function")

    -- Test format_points
    local fmt = format_points({ { x = 1.5, y = 2.5, z = 3.5 } })
    results["format_single"] = (fmt == "1.5,2.5,3.5")

    local fmt2 = format_points({ { x = 1, y = 2, z = 3 }, { x = 4, y = 5, z = 6 } })
    results["format_multi"] = (fmt2 == "1,2,3;4,5,6")

    -- Test apply_avoid_zones
    local p = {}
    apply_avoid_zones(p, nil)
    results["avoid_nil"] = (p.avoid == nil)

    local p2 = {}
    apply_avoid_zones(p2, { { x = 10, y = 20, z = 30, radius = 5, cost = 100 } })
    results["avoid_one"] = (p2.avoid == "10,20,30,5,100")

    -- Test _build_url
    local mock_svc = setmetatable({
        _base_url = "http://127.0.0.1:47110",
    }, NavigationService)

    results["url_no_params"] = (mock_svc:_build_url("/health") == "http://127.0.0.1:47110/health")
    results["url_nil_params"] = (mock_svc:_build_url("/health", nil) == "http://127.0.0.1:47110/health")

    local url = mock_svc:_build_url("/api/v1/path", { map_id = 0 })
    results["url_with_params"] = (url:find("map_id=0") ~= nil)

    -- Test lookup tables
    results["lookup_ek"] = (UI_MAP_TO_CONTINENT[1453] == 0)
    results["lookup_kal"] = (UI_MAP_TO_CONTINENT[1411] == 1)
    results["lookup_outland"] = (UI_MAP_TO_CONTINENT[1944] == 530)
    results["lookup_northrend"] = (UI_MAP_TO_CONTINENT[113] == 571)
    results["lookup_unknown"] = (UI_MAP_TO_CONTINENT[9999] == nil)

    results["indoor_true"] = (INDOOR_UI_MAPS[220] == true)
    results["indoor_false"] = (INDOOR_UI_MAPS[1453] == nil)

    return results
end

return NavigationService
