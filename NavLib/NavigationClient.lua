-- NavigationClient.lua
-- Thin HTTP client for the NavBuddy pathfinding REST API
-- Zero external dependencies beyond Sylvannas core + izi SDK + existing JSON

local vec3 = require("common/geometry/vector_3")
local izi = require("common/izi_sdk")
local JSON = require("JSON")

-- Helpers ----------------------------------------------------------------

---Convert response path array to vec3[]
---@param data table Response data with optional .path field
---@return vec3[]
local function extract_waypoints(data)
    local waypoints = {}
    if data.path then
        for i = 1, #data.path do
            local pt = data.path[i]
            waypoints[#waypoints + 1] = vec3.new(pt.x, pt.y, pt.z)
        end
    end
    return waypoints
end

---Format vec3[] as semicolon-separated "x,y,z;x,y,z" string
---@param points vec3[]
---@return string
local function format_points(points)
    local parts = {}
    for i = 1, #points do
        local p = points[i]
        parts[#parts + 1] = string.format("%g,%g,%g", p.x, p.y, p.z)
    end
    return table.concat(parts, ";")
end

-- UiMapID → NavBuddy continent ID (Map.dbc MapID) -----------------------
-- Source: WotLK 3.3.5 UiMapID data
-- 0 = Eastern Kingdoms, 1 = Kalimdor, 530 = Outland, 571 = Northrend
local UI_MAP_TO_CONTINENT = {
    -- Eastern Kingdoms (0)
    [124] = 0,
    [220] = 0, [225] = 0, [226] = 0, [227] = 0, [228] = 0, [229] = 0,
    [230] = 0, [231] = 0, [232] = 0, [233] = 0, [242] = 0, [243] = 0,
    [250] = 0, [251] = 0, [252] = 0, [253] = 0, [254] = 0, [255] = 0,
    [287] = 0, [288] = 0, [289] = 0, [290] = 0, [291] = 0, [292] = 0,
    [302] = 0, [303] = 0, [304] = 0, [305] = 0,
    [306] = 0, [307] = 0, [308] = 0, [309] = 0,
    [310] = 0, [311] = 0, [312] = 0, [313] = 0, [314] = 0, [315] = 0, [316] = 0,
    [317] = 0, [318] = 0, [333] = 0, [335] = 0, [336] = 0, [337] = 0,
    [350] = 0, [351] = 0, [352] = 0, [353] = 0, [354] = 0, [355] = 0,
    [356] = 0, [357] = 0, [358] = 0, [359] = 0, [360] = 0, [361] = 0,
    [362] = 0, [363] = 0, [364] = 0, [365] = 0, [366] = 0,
    [1415] = 0, [1416] = 0, [1417] = 0, [1418] = 0, [1419] = 0,
    [1420] = 0, [1421] = 0, [1422] = 0, [1423] = 0, [1424] = 0,
    [1425] = 0, [1426] = 0, [1427] = 0, [1428] = 0, [1429] = 0,
    [1430] = 0, [1431] = 0, [1432] = 0, [1433] = 0, [1434] = 0,
    [1435] = 0, [1436] = 0, [1437] = 0, [1453] = 0, [1458] = 0,
    [1463] = 0, [1941] = 0, [1942] = 0, [1954] = 0, [1957] = 0,
    -- Kalimdor (1)
    [130] = 1, [131] = 1, [213] = 1, [219] = 1,
    [221] = 1, [222] = 1, [223] = 1,
    [234] = 1, [235] = 1, [236] = 1, [237] = 1, [238] = 1, [239] = 1, [240] = 1,
    [247] = 1, [248] = 1, [273] = 1, [274] = 1, [279] = 1, [280] = 1, [281] = 1,
    [300] = 1, [301] = 1, [319] = 1, [320] = 1, [321] = 1, [329] = 1,
    [1411] = 1, [1412] = 1, [1413] = 1, [1414] = 1,
    [1438] = 1, [1439] = 1, [1440] = 1, [1441] = 1, [1442] = 1,
    [1443] = 1, [1444] = 1, [1445] = 1, [1446] = 1, [1447] = 1,
    [1448] = 1, [1449] = 1, [1450] = 1, [1451] = 1, [1452] = 1,
    [1454] = 1, [1455] = 1, [1456] = 1, [1457] = 1, [1464] = 1,
    [1943] = 1, [1947] = 1, [1950] = 1,
    -- Outland (530)
    [246] = 530, [256] = 530, [257] = 530, [258] = 530, [259] = 530,
    [260] = 530, [261] = 530, [262] = 530, [263] = 530, [264] = 530,
    [265] = 530, [266] = 530, [267] = 530, [268] = 530, [269] = 530,
    [270] = 530, [271] = 530, [272] = 530,
    [330] = 530, [331] = 530, [332] = 530, [334] = 530, [339] = 530, [347] = 530,
    [987] = 530, [1554] = 530, [1555] = 530, [1956] = 530,
    [1944] = 530, [1945] = 530, [1946] = 530, [1948] = 530, [1949] = 530,
    [1951] = 530, [1952] = 530, [1953] = 530, [1955] = 530,
    -- Northrend (571)
    [113] = 571, [114] = 571, [115] = 571, [116] = 571, [117] = 571,
    [118] = 571, [119] = 571, [120] = 571, [121] = 571, [123] = 571,
    [125] = 571, [126] = 571, [127] = 571, [128] = 571, [129] = 571,
    [132] = 571, [133] = 571, [134] = 571, [135] = 571,
    [136] = 571, [137] = 571, [138] = 571, [139] = 571, [140] = 571,
    [141] = 571, [142] = 571, [143] = 571, [144] = 571, [145] = 571, [146] = 571,
    [147] = 571, [148] = 571, [149] = 571, [150] = 571, [151] = 571, [152] = 571,
    [153] = 571, [154] = 571, [155] = 571, [156] = 571, [157] = 571,
    [158] = 571, [159] = 571, [160] = 571, [161] = 571,
    [162] = 571, [163] = 571, [164] = 571, [165] = 571, [166] = 571, [167] = 571,
    [168] = 571, [169] = 571, [170] = 571, [171] = 571, [172] = 571, [173] = 571,
    [183] = 571, [184] = 571, [185] = 571,
    [186] = 571, [187] = 571, [188] = 571, [189] = 571, [190] = 571,
    [191] = 571, [192] = 571, [193] = 571, [200] = 571,
    [988] = 571, [1375] = 571,
}

--- Indoor (dungeon/raid) UiMapIDs — subset of UI_MAP_TO_CONTINENT
--- Used for corridor pathfinding and anti-detection suppression
local INDOOR_UI_MAPS = {
    -- Eastern Kingdoms dungeons/raids
    [220] = true, [225] = true, [226] = true, [227] = true, [228] = true, [229] = true,
    [230] = true, [231] = true, [232] = true, [233] = true, [242] = true, [243] = true,
    [250] = true, [251] = true, [252] = true, [253] = true, [254] = true, [255] = true,
    [287] = true, [288] = true, [289] = true, [290] = true, [291] = true, [292] = true,
    [302] = true, [303] = true, [304] = true, [305] = true,
    [306] = true, [307] = true, [308] = true, [309] = true,
    [310] = true, [311] = true, [312] = true, [313] = true, [314] = true, [315] = true, [316] = true,
    [317] = true, [318] = true, [333] = true, [335] = true, [336] = true, [337] = true,
    [350] = true, [351] = true, [352] = true, [353] = true, [354] = true, [355] = true,
    [356] = true, [357] = true, [358] = true, [359] = true, [360] = true, [361] = true,
    [362] = true, [363] = true, [364] = true, [365] = true, [366] = true,
    [1463] = true,
    -- Kalimdor dungeons/raids
    [130] = true, [131] = true, [213] = true, [219] = true,
    [221] = true, [222] = true, [223] = true,
    [234] = true, [235] = true, [236] = true, [237] = true, [238] = true, [239] = true, [240] = true,
    [247] = true, [248] = true, [273] = true, [274] = true, [279] = true, [280] = true, [281] = true,
    [300] = true, [301] = true, [319] = true, [320] = true, [321] = true, [329] = true,
    -- Outland dungeons/raids
    [246] = true, [256] = true, [257] = true, [258] = true, [259] = true,
    [260] = true, [261] = true, [262] = true, [263] = true, [264] = true,
    [265] = true, [266] = true, [267] = true, [268] = true, [269] = true,
    [270] = true, [271] = true, [272] = true,
    [330] = true, [331] = true, [332] = true, [334] = true, [339] = true, [347] = true,
    [1554] = true, [1555] = true,
    -- Northrend dungeons/raids
    [129] = true, [132] = true, [133] = true, [134] = true, [135] = true,
    [136] = true, [137] = true, [138] = true, [139] = true, [140] = true,
    [141] = true, [142] = true, [143] = true, [144] = true, [145] = true, [146] = true,
    [147] = true, [148] = true, [149] = true, [150] = true, [151] = true, [152] = true,
    [153] = true, [154] = true, [155] = true, [156] = true, [157] = true,
    [158] = true, [159] = true, [160] = true, [161] = true,
    [162] = true, [163] = true, [164] = true, [165] = true, [166] = true, [167] = true,
    [168] = true, [169] = true, [171] = true, [172] = true, [173] = true,
    [183] = true, [184] = true, [185] = true,
    [186] = true, [187] = true, [188] = true, [189] = true, [190] = true,
    [191] = true, [192] = true, [193] = true, [200] = true,
    [1375] = true,
}

---Resolve current UiMapID to NavBuddy continent ID
---@return number continent_id (0=EK, 1=Kalimdor, 530=Outland, 571=Northrend)
local function get_continent_id()
    local ui_map_id = core.get_map_id()
    if ui_map_id then
        local continent = UI_MAP_TO_CONTINENT[ui_map_id]
        if continent then return continent end
        core.log_warning("[NavClient] Unknown UiMapID: " .. tostring(ui_map_id) .. ", defaulting to 0")
    end
    return 0
end

---Check if the current UiMapID corresponds to an indoor (dungeon/raid) zone
---@return boolean
local function is_indoor()
    local ui_map_id = core.get_map_id()
    return ui_map_id ~= nil and INDOOR_UI_MAPS[ui_map_id] == true
end

-- Class ------------------------------------------------------------------

---@class NavigationClient
---@field private _base_url string
---@field private _max_retries number
---@field private _is_connected boolean
---@field private _consecutive_failures number
---@field private _last_success_time number
local NavigationClient = {}
NavigationClient.__index = NavigationClient

---Create a new NavigationClient
---@param config? table { base_url?: string, max_retries?: number }
---@return NavigationClient
function NavigationClient:new(config)
    config = config or {}
    local o = setmetatable({}, NavigationClient)
    o._base_url = config.base_url or "http://localhost:47110"
    o._max_retries = config.max_retries or 3
    o._is_connected = false
    o._consecutive_failures = 0
    o._last_success_time = 0
    return o
end

-- Infrastructure ---------------------------------------------------------

---Build full URL from endpoint and parameter table
---@param endpoint string e.g. "/api/v1/path"
---@param params? table key-value pairs
---@return string
function NavigationClient:_build_url(endpoint, params)
    local url = self._base_url .. endpoint
    if not params or next(params) == nil then return url end

    local parts = {}
    for k, v in pairs(params) do
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
    return url .. "?" .. table.concat(parts, "&")
end

---Async HTTP GET with exponential-backoff retry
---@param url string Full URL
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param attempt? number Current attempt (1-based, internal)
function NavigationClient:_request(url, callback, attempt)
    attempt = attempt or 1

    core.http_get(url, function(code, content_type, response, headers)
        -- Success path
        if code == 200 then
            self._is_connected = true
            self._consecutive_failures = 0
            self._last_success_time = core.time()

            local ok, data = pcall(JSON.decode, response)
            if not ok or not data then
                core.log_error("[NavClient] JSON parse failed")
                if callback then callback(false, nil, "JSON parse error") end
                return
            end

            if data.success == false then
                local msg = data.error or "Server returned success=false"
                core.log_error("[NavClient] " .. msg)
                if callback then callback(false, nil, msg) end
                return
            end

            if callback then callback(true, data, nil) end
            return
        end

        -- Retryable?
        local retryable = (code == 0 or code == 500 or code == 502
                           or code == 503 or code == 504)

        if retryable and attempt < self._max_retries then
            local delay_secs = 0.5 * (2 ^ (attempt - 1))
            core.log_warning("[NavClient] HTTP " .. tostring(code)
                .. ", retry " .. (attempt + 1) .. "/" .. self._max_retries)
            izi.after(delay_secs, function()
                self:_request(url, callback, attempt + 1)
            end)
            return
        end

        -- Final failure
        self._consecutive_failures = self._consecutive_failures + 1
        if self._consecutive_failures >= 3 then
            self._is_connected = false
        end
        core.log_error("[NavClient] Request failed: HTTP " .. tostring(code))
        if callback then callback(false, nil, "HTTP " .. tostring(code)) end
    end)
end

---Check if NavBuddy appears connected
---@return boolean
function NavigationClient:is_available()
    return self._is_connected
end

---Get consecutive failure count
---@return number
function NavigationClient:get_consecutive_failures()
    return self._consecutive_failures
end

---Reset connection state
function NavigationClient:reset()
    self._is_connected = false
    self._consecutive_failures = 0
    self._last_success_time = 0
end

-- Core Pathfinding -------------------------------------------------------

---Request a path between two points
---@param start_pos vec3 Starting position
---@param dest vec3 Destination position
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { smoothing?, optimize?, anti_detection?, max_deviation?, smooth_iterations?, smooth_samples?, smooth_ratio?, filter_ground?, filter_water?, filter_lava?, allow_partial?, z_extent?, map_id? }
function NavigationClient:find_path(start_pos, dest, callback, opts)
    if not start_pos or not dest then
        if callback then callback(false, nil, "Missing start or dest") end
        return
    end
    opts = opts or {}
    local endpoint = opts.anti_detection and "/api/v1/path-random" or "/api/v1/path"
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x, start_y = start_pos.y, start_z = start_pos.z,
        end_x = dest.x, end_y = dest.y, end_z = dest.z,
    }
    if opts.smoothing then params.smoothing = opts.smoothing end
    if opts.optimize then params.optimize = true end
    if opts.max_deviation then params.max_deviation = opts.max_deviation end
    if opts.smooth_iterations then params.smooth_iterations = opts.smooth_iterations end
    if opts.smooth_samples then params.smooth_samples = opts.smooth_samples end
    if opts.smooth_ratio then params.smooth_ratio = opts.smooth_ratio end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end

    self:_request(self:_build_url(endpoint, params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        local wps = extract_waypoints(data)
        if #wps == 0 then
            if callback then callback(false, nil, "Empty path") end
            return
        end
        callback(true, {
            waypoints = wps,
            distance = data.distance or 0,
            partial = data.partial or false,
            computation_time_ms = data.computation_time_ms or 0,
        }, nil)
    end)
end

---Plan TSP-optimized route through multiple nodes
---@param nodes vec3[] At least 2 node positions
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id?, start_pos?: vec3, return_to_start?, weights? }
function NavigationClient:find_route_tsp(nodes, callback, opts)
    if not nodes or #nodes < 2 then
        if callback then callback(false, nil, "Need at least 2 nodes") end
        return
    end
    opts = opts or {}
    local start_pos = opts.start_pos
    if not start_pos then
        local player = core.object_manager.get_local_player()
        if player and player:is_valid() then
            start_pos = player:get_position()
        else
            if callback then callback(false, nil, "No start position") end
            return
        end
    end
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x, start_y = start_pos.y, start_z = start_pos.z,
        points = format_points(nodes),
    }
    if opts.return_to_start then params.return_to_start = true end
    if opts.weights then params.weights = opts.weights end

    self:_request(self:_build_url("/api/v1/path-tsp", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        -- Convert visit_order from 0-indexed (Rust) to 1-indexed (Lua)
        local visit_order = {}
        if data.visit_order then
            for i = 1, #data.visit_order do
                visit_order[#visit_order + 1] = data.visit_order[i] + 1
            end
        end
        callback(true, {
            waypoints = extract_waypoints(data),
            visit_order = visit_order,
            leg_boundaries = data.leg_boundaries or {},
            leg_distances = data.leg_distances or {},
            total_distance = data.total_distance or 0,
        }, nil)
    end)
end

---Plan ordered multi-stop route
---@param stops vec3[] Ordered stop positions (at least 2)
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id? }
function NavigationClient:find_route_multi(stops, callback, opts)
    if not stops or #stops < 2 then
        if callback then callback(false, nil, "Need at least 2 stops") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        stops = format_points(stops),
    }
    self:_request(self:_build_url("/api/v1/path-multi", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, {
            waypoints = extract_waypoints(data),
            leg_boundaries = data.leg_boundaries or {},
            leg_distances = data.leg_distances or {},
            total_distance = data.total_distance or 0,
        }, nil)
    end)
end

---Validate remaining path
---@param current_pos vec3 Current player position
---@param waypoints vec3[] Remaining waypoints
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id?, max_check? }
function NavigationClient:check_path(current_pos, waypoints, callback, opts)
    if not current_pos or not waypoints or #waypoints == 0 then
        if callback then callback(false, nil, "Missing pos or waypoints") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        current_x = current_pos.x, current_y = current_pos.y, current_z = current_pos.z,
        waypoints = format_points(waypoints),
    }
    if opts.max_check then params.max_check = opts.max_check end

    self:_request(self:_build_url("/api/v1/path/check", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, {
            valid = data.valid or false,
            first_invalid_segment = data.first_invalid_segment,
            player_on_navmesh = data.player_on_navmesh or false,
        }, nil)
    end)
end

---Request path with corridor widths
---@param start_pos vec3
---@param dest vec3
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id?, probe_distance?, smoothing?, optimize?, smooth_iterations?, smooth_samples?, smooth_ratio?, min_corner_angle?, keep_originals?, filter_ground?, filter_water?, filter_lava?, allow_partial?, z_extent? }
function NavigationClient:find_path_corridor(start_pos, dest, callback, opts)
    if not start_pos or not dest then
        if callback then callback(false, nil, "Missing start or dest") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x, start_y = start_pos.y, start_z = start_pos.z,
        end_x = dest.x, end_y = dest.y, end_z = dest.z,
    }
    if opts.probe_distance then params.probe_distance = opts.probe_distance end
    if opts.smoothing then params.smoothing = opts.smoothing end
    if opts.optimize then params.optimize = true end
    if opts.smooth_iterations then params.smooth_iterations = opts.smooth_iterations end
    if opts.smooth_samples then params.smooth_samples = opts.smooth_samples end
    if opts.smooth_ratio then params.smooth_ratio = opts.smooth_ratio end
    if opts.min_corner_angle then params.min_corner_angle = opts.min_corner_angle end
    if opts.keep_originals ~= nil then params.keep_originals = opts.keep_originals end
    if opts.filter_ground then params.filter_ground = opts.filter_ground end
    if opts.filter_water then params.filter_water = opts.filter_water end
    if opts.filter_lava then params.filter_lava = opts.filter_lava end
    if opts.allow_partial then params.allow_partial = true end
    if opts.z_extent then params.z_extent = opts.z_extent end
    if opts.wall_clearance and opts.wall_clearance > 0 then params.wall_clearance = opts.wall_clearance end

    self:_request(self:_build_url("/api/v1/path/corridor", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        local wps = extract_waypoints(data)
        if #wps == 0 then
            if callback then callback(false, nil, "Empty path") end
            return
        end
        callback(true, {
            waypoints = wps,
            corridor_widths = data.corridor_widths or {},
            distance = data.distance or 0,
            partial = data.partial or false,
            computation_time_ms = data.computation_time_ms or 0,
        }, nil)
    end)
end

-- Spatial Queries --------------------------------------------------------

---Raycast between two points on the navmesh
---@param start_pos vec3
---@param dest vec3
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id? }
function NavigationClient:raycast(start_pos, dest, callback, opts)
    if not start_pos or not dest then
        if callback then callback(false, nil, "Missing start or dest") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        start_x = start_pos.x, start_y = start_pos.y, start_z = start_pos.z,
        end_x = dest.x, end_y = dest.y, end_z = dest.z,
    }
    self:_request(self:_build_url("/api/v1/raycast", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        local hit_pos = nil
        if data.hit then
            hit_pos = vec3.new(data.hit_x or 0, data.hit_y or 0, data.hit_z or 0)
        end
        callback(true, {
            hit = data.hit or false,
            hit_position = hit_pos,
            t = data.t or 1.0,
            normal = vec3.new(data.normal_x or 0, data.normal_y or 0, data.normal_z or 0),
        }, nil)
    end)
end

---Get navmesh height at position
---@param pos vec3
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id? }
function NavigationClient:get_height(pos, callback, opts)
    if not pos then
        if callback then callback(false, nil, "Missing position") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        x = pos.x, y = pos.y, z = pos.z,
    }
    self:_request(self:_build_url("/api/v1/height", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, { height = data.height }, nil)
    end)
end

---Get random point on navmesh
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id?, center?: vec3, radius?: number }
function NavigationClient:random_point(callback, opts)
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
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, { point = vec3.new(data.x, data.y, data.z) }, nil)
    end)
end

-- Tactical ---------------------------------------------------------------

---Calculate flee path away from threats
---@param player_pos vec3
---@param threats vec3[] Threat positions
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id?, flee_distance?: number }
function NavigationClient:flee(player_pos, threats, callback, opts)
    if not player_pos or not threats or #threats == 0 then
        if callback then callback(false, nil, "Missing player_pos or threats") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        player_x = player_pos.x, player_y = player_pos.y, player_z = player_pos.z,
        threats = format_points(threats),
    }
    if opts.flee_distance then params.flee_distance = opts.flee_distance end

    self:_request(self:_build_url("/api/v1/tactical/flee", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, {
            waypoints = extract_waypoints(data),
            flee_direction = data.flee_direction,
            distance_from_threats = data.distance_from_threats or 0,
        }, nil)
    end)
end

---Calculate kite path around a target
---@param player_pos vec3
---@param target_pos vec3
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
---@param opts? table { map_id?, kite_radius?, arc_degrees?, direction?: string }
function NavigationClient:kite(player_pos, target_pos, callback, opts)
    if not player_pos or not target_pos then
        if callback then callback(false, nil, "Missing player_pos or target_pos") end
        return
    end
    opts = opts or {}
    local params = {
        map_id = opts.map_id or get_continent_id(),
        player_x = player_pos.x, player_y = player_pos.y, player_z = player_pos.z,
        target_x = target_pos.x, target_y = target_pos.y, target_z = target_pos.z,
    }
    if opts.kite_radius then params.kite_radius = opts.kite_radius end
    if opts.arc_degrees then params.arc_degrees = opts.arc_degrees end
    if opts.direction then params.direction = opts.direction end

    self:_request(self:_build_url("/api/v1/tactical/kite", params), function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, {
            waypoints = extract_waypoints(data),
            arc_length = data.arc_length or 0,
        }, nil)
    end)
end

-- Health -----------------------------------------------------------------

---Check NavBuddy server health
---@param callback fun(success: boolean, data: table|nil, error: string|nil)
function NavigationClient:health_check(callback)
    self:_request(self._base_url .. "/health", function(ok, data, err)
        if not ok then
            if callback then callback(false, nil, err) end
            return
        end
        callback(true, {
            status = data.status,
            version = data.version,
            uptime_secs = data.uptime_secs,
            loaded_maps = data.loaded_maps,
        }, nil)
    end)
end

---Check if the player is currently in an indoor (dungeon/raid) zone
---Static utility — does not require a NavigationClient instance
---@return boolean
function NavigationClient.is_indoor()
    return is_indoor()
end

return NavigationClient
