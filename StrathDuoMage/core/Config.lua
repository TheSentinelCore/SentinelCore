local Config = {}
Config.__index = Config

local DEFAULTS = {
    role = "leader", -- leader or follower
    loop_interval = 0.05,
    sync = {
        file = "StrathDuoMage/state/duo_sync.v1.json",
        stale_secs = 2.0,
        write_interval = 0.20,
    },
    targeting = {
        scan_radius = 55.0,
        pull_range = 30.0,
        aoe_enemy_threshold = 3,
        npc_whitelist = {},
        npc_blacklist = {},
    },
    combat = {
        kite_min_range = 12.0,
        kite_ideal_range = 23.0,
        emergency_nova_health_pct = 0.50,
        frostbolt_rank_ids = { 27071, 25304, 10181, 10180, 8408 },
        blizzard_rank_ids = { 27085, 10187, 10186, 10185, 42208 },
        cone_of_cold_rank_ids = { 27087, 10161, 10160, 10159, 120 },
        frost_nova_rank_ids = { 27088, 10230, 10229, 6131, 122 },
        arcane_explosion_rank_ids = { 27082, 10202, 10201, 10200, 1449 },
        ice_barrier_rank_ids = { 13033, 13032, 13031, 11426 },
        blink_rank_ids = { 1953 },
    },
    route = {
        loop = true,
        point_reach_tolerance = 2.0,
        point_timeout_secs = 4.0,
        collect_timeout_secs = 18.0,
        min_enemy_count_for_aoe = 8,
        default_focus_radius = 18.0,
        blizzard_strategy = "cluster_centroid", -- cluster_centroid or lane_midpoint
        blizzard_scan_radius = 40.0,
        clamp_blizzard_to_lane = true,
        blizzard_lead_distance = 2.0,
        blizzard_smoothing_alpha = 0.35,
        segments = {},
    },
    record = {
        autosave_secs = 8.0,
        min_point_spacing = 1.5,
        default_profile_path = "StrathDuoMage/profiles/strath_duo_default.json",
        template_profile_path = "StrathDuoMage/profiles/strath_duo_anniversary_template.json",
        default_focus_radius = 18.0,
    },
    farm = {
        enable_vendor = true,
        min_free_slots = 2,
        loot_enabled = true,
    },
    telemetry = {
        snapshot_interval = 1.0,
        report_interval = 10.0,
    },
    profile = {
        name = "strath_duo_default",
    },
}

local function deep_copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[deep_copy(k)] = deep_copy(x)
    end
    return out
end

local function is_array(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local n = #tbl
    if n == 0 then
        return false
    end
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false
        end
    end
    return true
end

local function deep_merge(dst, src)
    if type(src) ~= "table" then
        return dst
    end
    for k, v in pairs(src) do
        local dst_value = dst[k]
        local replace_array = type(v) == "table" and (is_array(v) or (next(v) == nil and is_array(dst_value)))
        if replace_array then
            dst[k] = deep_copy(v)
        elseif type(v) == "table" and type(dst_value) == "table" then
            deep_merge(dst_value, v)
        else
            dst[k] = deep_copy(v)
        end
    end
    return dst
end

---@param opts? table
---@return table
function Config:build(opts)
    local cfg = deep_copy(DEFAULTS)
    if type(opts) == "table" then
        deep_merge(cfg, opts)
    end
    return cfg
end

---@param cfg table
---@param path string
---@return boolean
---@return string|nil
function Config:load_profile_file(cfg, path)
    local content = nil
    if core and type(core.read_data_file) == "function" then
        content = core.read_data_file(path)
    end

    if (not content or content == "") and io and io.open then
        local f = io.open(path, "r")
        if f then
            content = f:read("*a")
            f:close()
        end
    end

    if not content or content == "" then
        return false, "profile file missing"
    end

    local ok_json, JSON = pcall(require, "lib/JSON")
    if not ok_json or not JSON or type(JSON.decode) ~= "function" then
        return false, "JSON decoder unavailable"
    end

    local parsed, err = JSON.decode(content)
    if type(parsed) ~= "table" then
        return false, tostring(err or "profile parse failed")
    end

    deep_merge(cfg, parsed)
    return true, nil
end

return setmetatable({}, Config)
