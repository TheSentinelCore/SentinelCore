local vec3 = require("common/geometry/vector_3")
local JSON = require("lib/JSON")

local GrindProfileManager = {}
GrindProfileManager.__index = GrindProfileManager

local DATA_FOLDER = "grindbuddy"
local PROFILE_FOLDER = "grindbuddy/profiles"
local INDEX_FILE = "grindbuddy/profiles/index.json"
local SAMPLE_FILE = "grindbuddy/profiles/example_auto.json"

local function call_method(obj, name, ...)
    if not obj then
        return nil
    end
    local fn = obj[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return result
end

local function copy_vec3(pos)
    return vec3.new(pos.x, pos.y, pos.z)
end

local function copy_points(points)
    local out = {}
    for i, p in ipairs(points or {}) do
        out[i] = copy_vec3(p)
    end
    return out
end

local function to_number(value)
    local n = tonumber(value)
    if not n then
        return nil
    end
    return n
end

local function clamp_int(value, lo, hi)
    local n = math.floor(value or 0)
    if n < lo then
        return lo
    end
    if n > hi then
        return hi
    end
    return n
end

local function resolve_bool(primary, fallback)
    if primary ~= nil then
        return primary == true
    end
    return fallback == true
end

local function decode_json(raw)
    local ok, data = pcall(JSON.decode, raw)
    if not ok then
        return nil, tostring(data)
    end
    if type(data) ~= "table" then
        return nil, "decoded payload is not a table"
    end
    return data, nil
end

local function encode_json(value)
    local raw, err = JSON.encode(value, true)
    if err then
        return nil, err
    end
    return raw, nil
end

local function build_circle_points(anchor_pos, radius, point_count)
    local points = {}
    local r = radius or 35.0
    local count = math.max(4, math.floor(point_count or 8))
    local cx = anchor_pos and anchor_pos.x or 0.0
    local cy = anchor_pos and anchor_pos.y or 0.0
    local cz = anchor_pos and anchor_pos.z or 0.0

    for i = 0, count - 1 do
        local angle = (math.pi * 2.0 / count) * i
        points[#points + 1] = {
            x = cx + (math.cos(angle) * r),
            y = cy + (math.sin(angle) * r),
            z = cz,
        }
    end

    return points
end

local function parse_points(raw_points)
    local points = {}
    if type(raw_points) ~= "table" then
        return points
    end

    for _, p in ipairs(raw_points) do
        if type(p) == "table" then
            local x = to_number(p.x or p[1])
            local y = to_number(p.y or p[2])
            local z = to_number(p.z or p[3])
            if x and y and z then
                points[#points + 1] = vec3.new(x, y, z)
            end
        end
    end

    return points
end

function GrindProfileManager:new(config)
    local instance = setmetatable({}, GrindProfileManager)
    instance._config = {
        default_radius = (config and config.default_radius) or 35.0,
        default_point_count = (config and config.default_point_count) or 8,
    }
    instance._profiles = {}
    instance._profiles_by_id = {}
    instance._profile_descriptors = {}
    instance._active_profile_id = nil
    instance._active_profile = nil
    instance._auto_select = true
    instance._last_detected_map_id = nil
    instance._last_detected_level = nil
    return instance
end

function GrindProfileManager:_register_profile(profile)
    self._profiles[#self._profiles + 1] = profile
    self._profiles_by_id[profile.id] = profile

    local map_label = (profile.map_id and profile.map_id > 0) and (" | Map " .. tostring(profile.map_id)) or ""
    local route_mode = profile.there_and_back and " | There&Back" or " | Loop"
    self._profile_descriptors[#self._profile_descriptors + 1] = {
        index = #self._profiles,
        id = profile.id,
        label = string.format("%s | Lv%d-%d%s%s", profile.label, profile.min_level, profile.max_level, map_label, route_mode),
    }
end

function GrindProfileManager:_reset_profiles()
    self._profiles = {}
    self._profiles_by_id = {}
    self._profile_descriptors = {}
end

function GrindProfileManager:_write_example_files(anchor_pos)
    core.create_data_folder(DATA_FOLDER)
    core.create_data_folder(PROFILE_FOLDER)

    local sample_points = build_circle_points(anchor_pos, self._config.default_radius, self._config.default_point_count)
    local sample_profile = {
        name = "Example Auto Route",
        description = "Generated fallback route. Edit this file with your own points.",
        map_id = 0,
        min_level = 1,
        max_level = 80,
        there_and_back = false,
        points = sample_points,
    }
    local sample_raw, sample_err = encode_json(sample_profile)
    if sample_raw then
        core.create_data_file(SAMPLE_FILE)
        core.write_data_file(SAMPLE_FILE, sample_raw)
    else
        core.log_warning("[GrindBuddy] Failed to encode sample profile: " .. tostring(sample_err))
    end

    local sample_index = {
        profiles = {
            {
                id = "example_auto",
                label = "Example Auto Route",
                file = SAMPLE_FILE,
                enabled = true,
                min_level = 1,
                max_level = 80,
                map_id = 0,
                there_and_back = false,
            },
        },
    }
    local index_raw, index_err = encode_json(sample_index)
    if index_raw then
        core.create_data_file(INDEX_FILE)
        core.write_data_file(INDEX_FILE, index_raw)
    else
        core.log_warning("[GrindBuddy] Failed to encode profile index: " .. tostring(index_err))
    end
end

function GrindProfileManager:_ensure_profile_files(anchor_pos)
    core.create_data_folder(DATA_FOLDER)
    core.create_data_folder(PROFILE_FOLDER)

    local index_raw = core.read_data_file(INDEX_FILE)
    if not index_raw or index_raw == "" then
        self:_write_example_files(anchor_pos)
    end
end

function GrindProfileManager:_load_profile_points(file_path)
    if type(file_path) ~= "string" or file_path == "" then
        return nil, nil, "invalid file path"
    end
    local raw = core.read_data_file(file_path)
    if not raw or raw == "" then
        return nil, nil, "file missing or empty"
    end

    local data, err = decode_json(raw)
    if not data then
        return nil, nil, err
    end

    local source_points = data.points or data.path or data.route or data.waypoints or data
    local points = parse_points(source_points)
    if #points < 2 then
        return nil, nil, "needs at least 2 valid points"
    end

    return points, data, nil
end

function GrindProfileManager:load(anchor_pos)
    local prev_active_id = self._active_profile_id
    self:_reset_profiles()
    self._active_profile = nil
    self._active_profile_id = nil

    self:_ensure_profile_files(anchor_pos)

    local raw = core.read_data_file(INDEX_FILE)
    if not raw or raw == "" then
        core.log_warning("[GrindBuddy] Route profile index is empty")
        return false
    end

    local data, err = decode_json(raw)
    if not data then
        core.log_warning("[GrindBuddy] Failed to parse route profile index: " .. tostring(err))
        return false
    end

    local entries = data.profiles or data.routes or data
    if type(entries) ~= "table" then
        core.log_warning("[GrindBuddy] Route profile index has no profiles array")
        return false
    end

    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local id = tostring(entry.id or entry.name or "")
            if id ~= "" then
                local file_path = entry.file or (PROFILE_FOLDER .. "/" .. id .. ".json")
                local points, file_data, file_err = self:_load_profile_points(file_path)
                if points then
                    local min_level = clamp_int(to_number(entry.min_level) or to_number(file_data.min_level) or 1, 1, 255)
                    local max_level = clamp_int(to_number(entry.max_level) or to_number(file_data.max_level) or min_level, min_level, 255)
                    local map_id = clamp_int(to_number(entry.map_id) or to_number(file_data.map_id) or 0, 0, 99999)
                    local label = tostring(entry.label or file_data.name or id)

                    local profile = {
                        id = id,
                        label = label,
                        file = file_path,
                        enabled = resolve_bool(entry.enabled, resolve_bool(file_data.enabled, true)),
                        min_level = min_level,
                        max_level = max_level,
                        map_id = map_id,
                        there_and_back = resolve_bool(entry.there_and_back, resolve_bool(file_data.there_and_back, false)),
                        points = points,
                    }
                    self:_register_profile(profile)
                else
                    core.log_warning(string.format("[GrindBuddy] Skipping profile '%s': %s", id, tostring(file_err)))
                end
            end
        end
    end

    if prev_active_id and self._profiles_by_id[prev_active_id] then
        self._active_profile_id = prev_active_id
        self._active_profile = self._profiles_by_id[prev_active_id]
    end

    return #self._profiles > 0
end

function GrindProfileManager:get_all_profile_descriptors()
    return self._profile_descriptors
end

function GrindProfileManager:get_profile_index_by_id(profile_id)
    if not profile_id then
        return nil
    end
    for i, profile in ipairs(self._profiles) do
        if profile.id == profile_id then
            return i
        end
    end
    return nil
end

function GrindProfileManager:get_active_profile()
    return self._active_profile
end

function GrindProfileManager:get_active_profile_id()
    return self._active_profile_id
end

function GrindProfileManager:get_active_profile_label()
    if not self._active_profile then
        return "none"
    end
    return tostring(self._active_profile.label)
end

function GrindProfileManager:is_auto_select_enabled()
    return self._auto_select == true
end

function GrindProfileManager:set_auto_select(enabled)
    self._auto_select = enabled == true
end

function GrindProfileManager:set_profile_by_id(profile_id)
    local profile = self._profiles_by_id[profile_id]
    if not profile then
        return false
    end
    self._active_profile_id = profile.id
    self._active_profile = profile
    return true
end

function GrindProfileManager:set_profile_by_index(index)
    local profile = self._profiles[index]
    if not profile then
        return false
    end
    self._active_profile_id = profile.id
    self._active_profile = profile
    return true
end

function GrindProfileManager:get_active_points()
    if not self._active_profile or not self._active_profile.points then
        return {}
    end
    return copy_points(self._active_profile.points)
end

local function profile_matches(profile, map_id, level)
    if not profile or profile.enabled ~= true then
        return false
    end
    if level < profile.min_level or level > profile.max_level then
        return false
    end
    if profile.map_id and profile.map_id > 0 and map_id and map_id > 0 and profile.map_id ~= map_id then
        return false
    end
    return true
end

function GrindProfileManager:detect_default_profile(local_player, map_id)
    local level = call_method(local_player, "get_level") or 1
    local checked_map_id = to_number(map_id) or 0

    self._last_detected_level = level
    self._last_detected_map_id = checked_map_id

    for _, profile in ipairs(self._profiles) do
        if profile_matches(profile, checked_map_id, level) then
            self._active_profile_id = profile.id
            self._active_profile = profile
            return profile.id
        end
    end

    return nil
end

return GrindProfileManager
