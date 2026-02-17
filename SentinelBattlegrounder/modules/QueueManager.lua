local vec3 = require("common/geometry/vector_3")
local CombatManager = require("modules/CombatManager")
local BGData = require("modules/BGData")
local BGScenarioManager = require("modules/BGScenarioManager")

local QueueManager = {}
QueueManager.__index = QueueManager

local CITY_STORMWIND = BGData.CITY_STORMWIND
local CITY_ORGRIMMAR = BGData.CITY_ORGRIMMAR
local CITY_ANCHORS = BGData.CITY_ANCHORS
local BG_QUEUE_ANCHORS = BGData.BG_QUEUE_ANCHORS
local PREFERRED_BATTLEMASTERS = BGData.PREFERRED_BATTLEMASTERS or {}

local BG_ALTERAC = BGData.BG_ALTERAC
local BG_WARSONG = BGData.BG_WARSONG
local BG_ARATHI = BGData.BG_ARATHI
local BG_EOTS = BGData.BG_EOTS
local MULTIQUEUE_BG_ORDER = { BG_ALTERAC, BG_WARSONG, BG_ARATHI }

local PLAYER_FACTION_ALLIANCE = BGData.PLAYER_FACTION_ALLIANCE
local PLAYER_FACTION_HORDE = BGData.PLAYER_FACTION_HORDE
local PLAYER_FACTION_UNKNOWN = BGData.PLAYER_FACTION_UNKNOWN

local ALLIANCE_FACTION_IDS = BGData.ALLIANCE_FACTION_IDS
local HORDE_FACTION_IDS = BGData.HORDE_FACTION_IDS

local ROLE_FLAGS_NONE = 0
local ROLE_NORMAL = "normal"
local ROLE_DEF_LAST_GY = "def_last_gy"

local AV_LAST_GY_BY_CITY = BGData.AV_LAST_GY_BY_CITY
local BG_DATA = BGData.BG_DATA
local BG_OPTIONS = BGData.BG_OPTIONS
local BG_KEY_ORDER = BGData.BG_KEY_ORDER
local detect_bg_key_from_map_name = BGData.detect_bg_key_from_map_name
local SETTINGS_FOLDER = "bgbuddy"
local SETTINGS_FILE = "bgbuddy/settings.cfg"

local function status_is_busy(status)
    return status == "queued" or status == "confirm" or status == "active"
end

local function now_time()
    return core.time()
end

local function random_between(min_value, max_value)
    return min_value + ((max_value - min_value) * math.random())
end

local function safe_call_number(obj, method_name)
    if not obj then
        return nil
    end
    local method = obj[method_name]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, obj)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function safe_relation(local_player, obj, method_name)
    if not local_player or not obj then
        return false
    end

    local method = local_player[method_name]
    if type(method) ~= "function" then
        return false
    end

    local ok, value = pcall(method, local_player, obj)
    return ok and value == true
end

local function current_map_id()
    local ok, map_id = pcall(function()
        return core.get_map_id()
    end)
    if ok and type(map_id) == "number" then
        return map_id
    end
    return nil
end

local function is_clearly_other_continent(current_map, preferred_map)
    if type(current_map) ~= "number" or type(preferred_map) ~= "number" then
        return false
    end
    if current_map == preferred_map then
        return false
    end

    -- Trinity/TBC classic continent ids:
    -- 0 = Eastern Kingdoms, 1 = Kalimdor.
    -- Only hard-block when we can confidently tell we are on the opposite continent.
    if preferred_map == 0 and current_map == 1 then
        return true
    end
    if preferred_map == 1 and current_map == 0 then
        return true
    end

    return false
end

local _random_seeded = false
local function build_runtime_seed()
    local seed = 0
    local ok_time, runtime = pcall(function() return core.time() end)
    if ok_time and type(runtime) == "number" then
        seed = math.floor(runtime * 1000000)
    end

    local ptr = tostring({})
    local hex = string.match(ptr, "0x(%x+)") or string.match(ptr, ":(%x+)$")
    if hex then
        for i = 1, #hex do
            local nibble = tonumber(string.sub(hex, i, i), 16) or 0
            seed = ((seed * 16) + nibble) % 2147483647
        end
    end

    if seed <= 0 then
        seed = 1
    end
    return seed
end

local function ensure_random_seed()
    if _random_seeded then
        return
    end

    local seed = build_runtime_seed()
    math.randomseed(seed)
    -- Burn first values to avoid weak first draws in some Lua runtimes.
    math.random()
    math.random()
    _random_seeded = true
end

local CITY_DETECT_RADIUS = 2500.0
local CITY_DETECT_MARGIN = 300.0
local WSG_SCAN_RADIUS = 85.0
local WSG_CHASE_RANGE = 13.0
local WSG_FOLLOW_ALLY_RADIUS = 65.0
local WSG_FOLLOW_MOVE_MIN = 14.0
local AB_SCAN_RADIUS = 85.0
local AB_ENGAGE_RANGE = 13.0
local AB_FOLLOW_ALLY_RADIUS = 65.0
local AB_FOLLOW_MOVE_MIN = 14.0

local function distance_3d(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function safe_lower_name(obj)
    local ok, name = pcall(function() return obj:get_name() end)
    if ok and name then
        return string.lower(name)
    end
    return ""
end

local function string_contains(text, fragment)
    return string.find(text, fragment, 1, true) ~= nil
end

local function bool_to_str(v)
    return v and "true" or "false"
end

local function str_to_bool(v)
    if v == "true" then
        return true
    end
    if v == "false" then
        return false
    end
    return nil
end

local function parse_vec3(value)
    if type(value) ~= "string" then
        return nil
    end

    local x, y, z = value:match("^%s*([%-%.%d]+),([%-%.%d]+),([%-%.%d]+)%s*$")
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)
    if not x or not y or not z then
        return nil
    end
    return vec3.new(x, y, z)
end

local function vec3_to_str(v)
    if not v then
        return nil
    end
    return string.format("%.3f,%.3f,%.3f", v.x or 0, v.y or 0, v.z or 0)
end

local function bg_name_match(name, bg_key)
    if name == "" then
        return false
    end

    if bg_key == BG_ALTERAC then
        if string_contains(name, "alterac") then
            return true
        end
        if string_contains(name, "battlemaster") and string_contains(name, "valley") then
            return true
        end
        if string_contains(name, "maitre de guerre") and string_contains(name, "alterac") then
            return true
        end
        return false
    end

    if bg_key == BG_WARSONG then
        return string_contains(name, "warsong")
            or string_contains(name, "gulch")
            or string_contains(name, "goulet")
            or string_contains(name, "chanteguerre")
    end

    if bg_key == BG_ARATHI then
        return string_contains(name, "arathi")
            or string_contains(name, "bassin")
            or (string_contains(name, "battlemaster") and string_contains(name, "basin"))
    end

    if bg_key == BG_EOTS then
        if string_contains(name, "cyclone") or string_contains(name, "oeil") then
            return true
        end
        if string_contains(name, "eye") and string_contains(name, "storm") then
            return true
        end
        if string_contains(name, "maitre de guerre") and string_contains(name, "tempete") then
            return true
        end
        return false
    end

    return false
end

local function is_bg_battlemaster(obj, bg_key)
    if not obj or not obj:is_valid() or not obj:is_unit() or obj:is_player() then
        return false, "none"
    end

    local bg = BG_DATA[bg_key] or BG_DATA[BG_ALTERAC]
    local npc_id = obj:get_npc_id()
    if npc_id and bg.entries[npc_id] then
        return true, "npc_id"
    end

    local name = safe_lower_name(obj)
    if bg_name_match(name, bg.key) then
        return true, "name"
    end
    return false, "none"
end

function QueueManager:new()
    local o = setmetatable({}, QueueManager)
    ensure_random_seed()

    o._running = false
    o._city = CITY_STORMWIND
    o._status_text = "Idle"

    o._last_queue_time = 0
    o._last_interact_time = 0
    o._last_move_order_time = 0

    o._search_radius = 85.0
    o._interact_range = 5.5
    o._queue_cooldown_min = 3.4
    o._queue_cooldown_max = 5.2
    o._interact_cooldown_min = 1.5
    o._interact_cooldown_max = 2.7
    o._move_order_cooldown_min = 1.1
    o._move_order_cooldown_max = 1.9
    o._banner_interact_cooldown_min = 1.7
    o._banner_interact_cooldown_max = 2.9
    o._release_spirit_cooldown_min = 2.6
    o._release_spirit_cooldown_max = 4.2
    o._release_spirit_first_delay_min = 1.0
    o._release_spirit_first_delay_max = 2.8
    o._queue_cooldown = random_between(o._queue_cooldown_min, o._queue_cooldown_max)
    o._interact_cooldown = random_between(o._interact_cooldown_min, o._interact_cooldown_max)
    o._move_order_cooldown = random_between(o._move_order_cooldown_min, o._move_order_cooldown_max)
    o._banner_interact_cooldown = random_between(o._banner_interact_cooldown_min, o._banner_interact_cooldown_max)
    o._release_spirit_cooldown = random_between(o._release_spirit_cooldown_min, o._release_spirit_cooldown_max)
    o._debug_enabled = true
    o._debug_min_interval = 3.0
    o._debug_last_by_key = {}

    o._nav = nil
    o._scenario_manager = BGScenarioManager:new()
    o._bg_role = ROLE_NORMAL
    o._selected_bg = BG_ALTERAC
    o._multi_queue_enabled = false
    o._multi_queue_index = 1
    o._multi_queue_flags = {
        [BG_ALTERAC] = true,
        [BG_WARSONG] = true,
        [BG_ARATHI] = true,
    }
    o._active_bg_key = BG_ALTERAC
    o._active_scenario_id = "none"
    o._auto_faction = true
    o._detected_faction = PLAYER_FACTION_UNKNOWN
    o._last_banner_interact_time = 0
    o._last_release_spirit_time = 0
    o._pending_release_spirit_time = 0
    o._was_dead_last_tick = false
    o._last_action = "init"
    o._diag = {
        last_scan_bg = BG_ALTERAC,
        scanned_count = 0,
        matched_count = 0,
        last_match_type = "none",
        last_match_npc_id = 0,
        last_match_name = "",
        last_match_distance = 0,
        last_stuck_recover_time = 0,
        active_bg_source = "none",
        faction_source = "init",
        queue_target_count = 1,
        slot1_status = "none",
        slot2_status = "none",
        slot3_status = "none",
    }
    o._stuck_progress_pos = nil
    o._stuck_last_progress_time = 0
    o._stuck_move_threshold = 1.5
    o._stuck_timeout = 8.0
    o._combat = CombatManager:new()
    o:_load_settings()
    o:_ensure_nav()

    return o
end

function QueueManager:_debug_log(key, message, min_interval)
    if not self._debug_enabled then
        return
    end

    local interval = min_interval or self._debug_min_interval
    local now = now_time()
    local last = self._debug_last_by_key[key] or 0
    if now - last < interval then
        return
    end

    self._debug_last_by_key[key] = now
    core.log("[BgBuddy][DBG] " .. message)
end

function QueueManager:set_bg_role(role)
    if role == ROLE_NORMAL or role == ROLE_DEF_LAST_GY then
        self._bg_role = role
        self._status_text = "BG role set to " .. role
        core.log("[BgBuddy] BG role set to " .. role)
        self:_save_settings()
    end
end

function QueueManager:get_bg_role()
    return self._bg_role
end

function QueueManager:set_selected_bg(bg_key)
    if BG_DATA[bg_key] then
        self._selected_bg = bg_key
        self._status_text = "Queue BG set to " .. BG_DATA[bg_key].label
        core.log("[BgBuddy] Queue BG set to " .. BG_DATA[bg_key].label)
        self:_save_settings()
    end
end

function QueueManager:get_selected_bg()
    return self._selected_bg
end

function QueueManager:set_multi_queue_enabled(enabled)
    self._multi_queue_enabled = enabled == true
    self._multi_queue_index = 1
    if self._multi_queue_enabled then
        self:_ensure_multi_queue_minimum()
    end
    if self._multi_queue_enabled then
        self._status_text = "Multi-queue enabled"
        core.log("[BgBuddy] Multi-queue enabled (Alterac/Warsong/Arathi)")
    else
        self._status_text = "Multi-queue disabled"
        core.log("[BgBuddy] Multi-queue disabled")
    end
    self:_save_settings()
end

function QueueManager:get_multi_queue_enabled()
    return self._multi_queue_enabled == true
end

function QueueManager:_ensure_multi_queue_minimum()
    local list = self:_get_multi_queue_list()
    if #list > 0 then
        return
    end

    local fallback = self._selected_bg
    if fallback ~= BG_ALTERAC and fallback ~= BG_WARSONG and fallback ~= BG_ARATHI then
        fallback = BG_ALTERAC
    end

    self._multi_queue_flags[fallback] = true
    local bg = self:_get_bg_data(fallback)
    core.log("[BgBuddy] Multi-queue requires at least one BG. Re-enabled " .. tostring(bg.label))
end

function QueueManager:set_multi_queue_bg_enabled(bg_key, enabled)
    if bg_key ~= BG_ALTERAC and bg_key ~= BG_WARSONG and bg_key ~= BG_ARATHI then
        return
    end
    self._multi_queue_flags[bg_key] = enabled == true
    if self._multi_queue_enabled then
        self:_ensure_multi_queue_minimum()
    end
    self._multi_queue_index = 1
    self:_save_settings()
end

function QueueManager:get_multi_queue_bg_enabled(bg_key)
    if bg_key ~= BG_ALTERAC and bg_key ~= BG_WARSONG and bg_key ~= BG_ARATHI then
        return false
    end
    return self._multi_queue_flags[bg_key] == true
end

function QueueManager:get_bg_options()
    return BG_OPTIONS
end

function QueueManager:set_auto_faction(enabled)
    self._auto_faction = enabled == true
    if self._auto_faction then
        self._status_text = "Auto faction enabled"
        core.log("[BgBuddy] Auto faction enabled")
    else
        self._status_text = "Auto faction disabled"
        core.log("[BgBuddy] Auto faction disabled")
    end
    self:_save_settings()
end

function QueueManager:get_auto_faction()
    return self._auto_faction
end

function QueueManager:get_detected_faction()
    return self._detected_faction
end

function QueueManager:set_debug_enabled(enabled)
    self._debug_enabled = enabled == true
    core.log("[BgBuddy] Debug " .. (self._debug_enabled and "enabled" or "disabled"))
    self:_save_settings()
end

function QueueManager:get_debug_enabled()
    return self._debug_enabled
end

function QueueManager:set_combat_enabled(enabled)
    if self._combat and self._combat.set_enabled then
        self._combat:set_enabled(enabled)
        core.log("[BgBuddy] Combat " .. (enabled and "enabled" or "disabled"))
        self:_save_settings()
    end
end

function QueueManager:get_combat_enabled()
    if self._combat and self._combat.get_enabled then
        return self._combat:get_enabled()
    end
    return false
end

function QueueManager:set_rotation_class(class_key)
    if self._combat and self._combat.set_rotation_class then
        if self._combat:set_rotation_class(class_key) then
            core.log("[BgBuddy] Rotation class set to " .. tostring(class_key))
            self:_save_settings()
        end
    end
end

function QueueManager:get_rotation_class()
    if self._combat and self._combat.get_rotation_class then
        return self._combat:get_rotation_class()
    end
    return "warlock"
end

function QueueManager:get_rotation_class_options()
    if self._combat and self._combat.get_rotation_options then
        return self._combat:get_rotation_options()
    end
    return { "Warlock (Demo)" }
end

function QueueManager:_ensure_nav()
    if self._nav then
        return true
    end

    if not _G.NavLib or not _G.NavLib.create then
        self._status_text = "NavLib not loaded"
        return false
    end

    self._nav = _G.NavLib.create({})
    return self._nav ~= nil
end

function QueueManager:start()
    self._running = true
    self._stuck_progress_pos = nil
    self._stuck_last_progress_time = now_time()
    self._multi_queue_index = 1
    self._active_bg_key = self:_get_queue_target_bg_key()
    self._active_scenario_id = "none"
    if self._multi_queue_enabled then
        self._status_text = "Running (multi-queue AV/WSG/AB)"
    else
        self._status_text = "Running (" .. self:_get_selected_bg_data().label .. ")"
    end
    core.log("[BgBuddy] Started")
end

function QueueManager:stop()
    self._running = false
    if self._nav then
        self._nav:stop()
    end
    self._stuck_progress_pos = nil
    self._stuck_last_progress_time = 0
    self._active_scenario_id = "none"
    self._status_text = "Stopped"
    core.log("[BgBuddy] Stopped")
end

function QueueManager:set_city(city)
    if city == CITY_STORMWIND or city == CITY_ORGRIMMAR then
        self._city = city
        self._auto_faction = false
        self._detected_faction = (city == CITY_STORMWIND) and PLAYER_FACTION_ALLIANCE or PLAYER_FACTION_HORDE
        self._status_text = "City set to " .. city
        core.log("[BgBuddy] City set to " .. city)
        self:_save_settings()
    end
end

function QueueManager:set_anchor_from_player(city)
    if city ~= CITY_STORMWIND and city ~= CITY_ORGRIMMAR then
        return false
    end

    local local_player = core.object_manager.get_local_player()
    if not local_player or not local_player:is_valid() then
        self._status_text = "Cannot set anchor: player unavailable"
        return false
    end

    local pos = local_player:get_position()
    CITY_ANCHORS[city] = vec3.new(pos.x, pos.y, pos.z)
    self._status_text = string.format(
        "Anchor %s set to %.2f %.2f %.2f",
        city,
        pos.x,
        pos.y,
        pos.z
    )
    core.log(string.format(
        "[BgBuddy] Anchor %s updated to (%.2f, %.2f, %.2f)",
        city,
        pos.x,
        pos.y,
        pos.z
    ))
    self:_save_settings()
    return true
end

function QueueManager:set_bg_anchor_from_player(city, bg_key)
    if city ~= CITY_STORMWIND and city ~= CITY_ORGRIMMAR then
        return false
    end
    if not BG_DATA[bg_key] then
        return false
    end

    local local_player = core.object_manager.get_local_player()
    if not local_player or not local_player:is_valid() then
        self._status_text = "Cannot set BG anchor: player unavailable"
        return false
    end

    BG_QUEUE_ANCHORS[city] = BG_QUEUE_ANCHORS[city] or {}

    local pos = local_player:get_position()
    BG_QUEUE_ANCHORS[city][bg_key] = vec3.new(pos.x, pos.y, pos.z)
    self._status_text = string.format(
        "BG anchor %s/%s set to %.2f %.2f %.2f",
        city,
        bg_key,
        pos.x,
        pos.y,
        pos.z
    )
    core.log(string.format(
        "[BgBuddy] BG anchor %s/%s updated to (%.2f, %.2f, %.2f)",
        city,
        bg_key,
        pos.x,
        pos.y,
        pos.z
    ))
    self:_save_settings()
    return true
end

function QueueManager:get_city()
    return self._city
end

function QueueManager:is_running()
    return self._running
end

function QueueManager:get_status_text()
    return self._status_text
end

function QueueManager:_save_settings()
    local lines = {}
    local function push(key, value)
        if key and value ~= nil then
            lines[#lines + 1] = tostring(key) .. "=" .. tostring(value)
        end
    end

    push("city", self._city)
    push("auto_faction", bool_to_str(self._auto_faction == true))
    push("selected_bg", self._selected_bg)
    push("bg_role", self._bg_role)
    push("multi_queue_enabled", bool_to_str(self._multi_queue_enabled == true))
    push("multi_queue.alterac", bool_to_str(self._multi_queue_flags[BG_ALTERAC] == true))
    push("multi_queue.warsong", bool_to_str(self._multi_queue_flags[BG_WARSONG] == true))
    push("multi_queue.arathi", bool_to_str(self._multi_queue_flags[BG_ARATHI] == true))
    push("debug_enabled", bool_to_str(self._debug_enabled == true))

    if self._combat and self._combat.get_enabled then
        push("combat_enabled", bool_to_str(self._combat:get_enabled() == true))
    end
    if self._combat and self._combat.get_rotation_class then
        push("rotation_class", self._combat:get_rotation_class())
    end

    for _, city in ipairs({ CITY_STORMWIND, CITY_ORGRIMMAR }) do
        local city_anchor = CITY_ANCHORS[city]
        push("anchor." .. city, vec3_to_str(city_anchor))

        local by_city = BG_QUEUE_ANCHORS[city] or {}
        for _, bg_key in ipairs(BG_KEY_ORDER or {}) do
            push("bg_anchor." .. city .. "." .. bg_key, vec3_to_str(by_city[bg_key]))
        end
    end

    local payload = table.concat(lines, "\n")
    pcall(function()
        core.create_data_folder(SETTINGS_FOLDER)
        core.create_data_file(SETTINGS_FILE)
        core.write_data_file(SETTINGS_FILE, payload)
    end)
end

function QueueManager:_load_settings()
    local raw = core.read_data_file(SETTINGS_FILE)
    if not raw or raw == "" then
        return
    end

    local kv = {}
    for line in string.gmatch(raw, "[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not string.sub(trimmed, 1, 1):match("[#;]") then
            local key, value = trimmed:match("^([^=]+)=(.*)$")
            if key and value then
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")
                kv[key] = value
            end
        end
    end

    if kv.city == CITY_STORMWIND or kv.city == CITY_ORGRIMMAR then
        self._city = kv.city
    end

    local auto_faction = str_to_bool(kv.auto_faction)
    if auto_faction ~= nil then
        self._auto_faction = auto_faction
    end

    if kv.selected_bg and BG_DATA[kv.selected_bg] then
        self._selected_bg = kv.selected_bg
    end

    if kv.bg_role == ROLE_NORMAL or kv.bg_role == ROLE_DEF_LAST_GY then
        self._bg_role = kv.bg_role
    end

    local multi_queue_enabled = str_to_bool(kv.multi_queue_enabled)
    if multi_queue_enabled ~= nil then
        self._multi_queue_enabled = multi_queue_enabled
    end

    local mq_alterac = str_to_bool(kv["multi_queue.alterac"])
    if mq_alterac ~= nil then
        self._multi_queue_flags[BG_ALTERAC] = mq_alterac
    end

    local mq_warsong = str_to_bool(kv["multi_queue.warsong"])
    if mq_warsong ~= nil then
        self._multi_queue_flags[BG_WARSONG] = mq_warsong
    end

    local mq_arathi = str_to_bool(kv["multi_queue.arathi"])
    if mq_arathi ~= nil then
        self._multi_queue_flags[BG_ARATHI] = mq_arathi
    end

    if self._multi_queue_enabled then
        self:_ensure_multi_queue_minimum()
    end

    local debug_enabled = str_to_bool(kv.debug_enabled)
    if debug_enabled ~= nil then
        self._debug_enabled = debug_enabled
    end

    if self._combat and self._combat.set_enabled then
        local combat_enabled = str_to_bool(kv.combat_enabled)
        if combat_enabled ~= nil then
            self._combat:set_enabled(combat_enabled)
        end
    end

    if self._combat and self._combat.set_rotation_class and kv.rotation_class then
        self._combat:set_rotation_class(kv.rotation_class)
    end

    for _, city in ipairs({ CITY_STORMWIND, CITY_ORGRIMMAR }) do
        local city_anchor = parse_vec3(kv["anchor." .. city])
        if city_anchor then
            CITY_ANCHORS[city] = city_anchor
        end

        BG_QUEUE_ANCHORS[city] = BG_QUEUE_ANCHORS[city] or {}
        for _, bg_key in ipairs(BG_KEY_ORDER or {}) do
            local bg_anchor = parse_vec3(kv["bg_anchor." .. city .. "." .. bg_key])
            if bg_anchor then
                BG_QUEUE_ANCHORS[city][bg_key] = bg_anchor
            end
        end
    end
end

function QueueManager:get_debug_snapshot()
    local bg = self:_get_selected_bg_data()
    local active_bg = self:_get_bg_data(self._active_bg_key)
    local d = self._diag or {}
    local active_anchor = self:_get_queue_anchor(bg.key, self._city)
    return {
        selected_bg = bg.key,
        selected_bg_label = bg.label,
        multi_queue_enabled = self._multi_queue_enabled == true,
        multi_queue_alterac = self._multi_queue_flags[BG_ALTERAC] == true,
        multi_queue_warsong = self._multi_queue_flags[BG_WARSONG] == true,
        multi_queue_arathi = self._multi_queue_flags[BG_ARATHI] == true,
        queue_target_count = d.queue_target_count or 1,
        slot1_status = d.slot1_status or "none",
        slot2_status = d.slot2_status or "none",
        slot3_status = d.slot3_status or "none",
        active_bg = active_bg.key,
        active_bg_label = active_bg.label,
        active_bg_source = d.active_bg_source or "none",
        active_scenario_id = self._active_scenario_id or "none",
        queue_id = bg.queue_id,
        city = self._city,
        auto_faction = self._auto_faction,
        debug_enabled = self._debug_enabled,
        detected_faction = self._detected_faction,
        faction_source = d.faction_source or "none",
        status = self._status_text,
        last_action = self._last_action,
        scanned_count = d.scanned_count or 0,
        matched_count = d.matched_count or 0,
        last_match_type = d.last_match_type or "none",
        last_match_npc_id = d.last_match_npc_id or 0,
        last_match_name = d.last_match_name or "",
        last_match_distance = d.last_match_distance or 0,
        last_stuck_recover_time = d.last_stuck_recover_time or 0,
        active_anchor_x = active_anchor.x or 0,
        active_anchor_y = active_anchor.y or 0,
        active_anchor_z = active_anchor.z or 0,
    }
end

function QueueManager:_set_action(action)
    if self._last_action ~= action then
        self:_debug_log("action_transition", string.format("Action %s -> %s", tostring(self._last_action), tostring(action)), 0.5)
    end
    self._last_action = action
end

function QueueManager:_get_queue_anchor(bg_key, city)
    local by_city = BG_QUEUE_ANCHORS[city]
    if by_city and by_city[bg_key] then
        return by_city[bg_key]
    end
    return CITY_ANCHORS[city] or CITY_ANCHORS[CITY_STORMWIND]
end

function QueueManager:_get_preferred_battlemaster(city, bg_key)
    local by_city = PREFERRED_BATTLEMASTERS[city]
    if by_city then
        return by_city[bg_key]
    end
    return nil
end

function QueueManager:_preferred_name_match(obj, wanted_name)
    if not wanted_name or wanted_name == "" then
        return false
    end

    local obj_name = safe_lower_name(obj)
    if obj_name == "" then
        return false
    end

    return string_contains(obj_name, string.lower(wanted_name))
end

function QueueManager:_find_preferred_battlemaster(local_player, preferred)
    if not preferred then
        return nil, nil
    end

    local objects = core.object_manager.get_all_objects()
    local my_pos = local_player:get_position()
    local best = nil
    local best_dist = 99999.0

    for _, obj in ipairs(objects) do
        if obj and obj:is_valid() and obj:is_unit() and not obj:is_player() then
            local npc_id = obj:get_npc_id()
            local is_match = (preferred.npc_id and npc_id == preferred.npc_id)
                or self:_preferred_name_match(obj, preferred.name)
            if is_match then
                local dist = distance_3d(my_pos, obj:get_position())
                if dist < best_dist then
                    best = obj
                    best_dist = dist
                end
            end
        end
    end

    return best, best_dist
end

function QueueManager:_is_nav_actively_moving()
    if not self._nav then
        return false
    end

    local ok_moving, moving = pcall(function()
        if self._nav.is_moving then
            return self._nav:is_moving()
        end
        return nil
    end)
    if ok_moving and moving == true then
        return true
    end

    local ok_state, state = pcall(function()
        if self._nav.get_state then
            return self._nav:get_state()
        end
        return nil
    end)
    if ok_state and (state == "moving" or state == "requesting_path") then
        return true
    end

    return false
end

function QueueManager:_tick_stuck(local_player)
    if not self._running or not self._nav then
        return
    end

    local now = now_time()
    if not self:_is_nav_actively_moving() then
        local idle_pos = local_player:get_position()
        self._stuck_progress_pos = vec3.new(idle_pos.x, idle_pos.y, idle_pos.z)
        self._stuck_last_progress_time = now
        return
    end

    local pos = local_player:get_position()
    if not self._stuck_progress_pos then
        self._stuck_progress_pos = vec3.new(pos.x, pos.y, pos.z)
        self._stuck_last_progress_time = now
        return
    end

    local moved = distance_3d(pos, self._stuck_progress_pos)
    if moved >= self._stuck_move_threshold then
        self._stuck_progress_pos = vec3.new(pos.x, pos.y, pos.z)
        self._stuck_last_progress_time = now
        return
    end

    if now - self._stuck_last_progress_time < self._stuck_timeout then
        return
    end

    self._stuck_progress_pos = vec3.new(pos.x, pos.y, pos.z)
    self._stuck_last_progress_time = now
    self._last_move_order_time = 0
    if self._nav.stop then
        self._nav:stop()
    end
    core.input.jump()
    self._diag.last_stuck_recover_time = now
    self:_debug_log("queue_stuck", "Queue stuck recovery triggered (stop + jump)", 2.0)
end

function QueueManager:_get_selected_bg_data()
    return self:_get_bg_data(self._selected_bg)
end

function QueueManager:_get_multi_queue_list()
    local list = {}
    for _, bg_key in ipairs(MULTIQUEUE_BG_ORDER) do
        if self._multi_queue_flags[bg_key] == true then
            list[#list + 1] = bg_key
        end
    end
    return list
end

function QueueManager:_get_target_queue_count()
    if not self._multi_queue_enabled then
        return 1
    end
    local list = self:_get_multi_queue_list()
    local count = #list
    if count < 1 then
        return 1
    end
    if count > 3 then
        return 3
    end
    return count
end

function QueueManager:_get_queue_target_bg_key()
    if not self._multi_queue_enabled then
        return self._selected_bg
    end

    local list = self:_get_multi_queue_list()
    if #list == 0 then
        return self._selected_bg
    end

    if self._multi_queue_index < 1 or self._multi_queue_index > #list then
        self._multi_queue_index = 1
    end

    return list[self._multi_queue_index]
end

function QueueManager:_advance_queue_target(last_bg_key)
    if not self._multi_queue_enabled then
        return
    end

    local list = self:_get_multi_queue_list()
    if #list <= 1 then
        self._multi_queue_index = 1
        return
    end

    local idx = 1
    for i, bg_key in ipairs(list) do
        if bg_key == last_bg_key then
            idx = i
            break
        end
    end

    self._multi_queue_index = (idx % #list) + 1
end

function QueueManager:_get_queue_target_bg_data()
    return self:_get_bg_data(self:_get_queue_target_bg_key())
end

function QueueManager:_get_bg_data(bg_key)
    return BG_DATA[bg_key] or BG_DATA[BG_ALTERAC]
end

function QueueManager:_detect_active_bg_key(_local_player)
    local key_from_map = nil
    if detect_bg_key_from_map_name then
        key_from_map = detect_bg_key_from_map_name(core.get_map_name())
    end
    if key_from_map and BG_DATA[key_from_map] then
        return key_from_map, "map_name"
    end
    return self._selected_bg, "selected_bg_fallback"
end

function QueueManager:_resolve_active_scenario(active_bg_key)
    if not self._scenario_manager or not self._scenario_manager.resolve then
        return nil
    end
    return self._scenario_manager:resolve(active_bg_key, self._bg_role)
end

function QueueManager:_run_active_scenario(local_player)
    local active_bg_key, source = self:_detect_active_bg_key(local_player)
    self._active_bg_key = active_bg_key
    self._diag.active_bg_source = source

    local bg = self:_get_bg_data(active_bg_key)
    local scenario = self:_resolve_active_scenario(active_bg_key)
    if not scenario or not scenario.runner then
        self._active_scenario_id = "none"
        self:_set_action("bg_idle")
        self._status_text = string.format(
            "In battleground (%s, role %s has no scenario)",
            bg.label,
            self._bg_role
        )
        return
    end

    self._active_scenario_id = scenario.id or "unnamed"
    local runner = self[scenario.runner]
    if type(runner) ~= "function" then
        self:_set_action("bg_scenario_runner_missing")
        self:_debug_log(
            "scenario_runner_missing",
            string.format("Missing runner %s for scenario %s", tostring(scenario.runner), tostring(self._active_scenario_id)),
            3.0
        )
        self._status_text = "Missing scenario runner: " .. tostring(scenario.runner)
        return
    end

    self:_debug_log(
        "scenario_active",
        string.format("Running scenario %s in %s (source=%s)", self._active_scenario_id, bg.label, source),
        4.0
    )
    runner(self, local_player)
end

function QueueManager:_detect_player_faction(local_player)
    local faction_id = safe_call_number(local_player, "get_faction_id")
    if faction_id and ALLIANCE_FACTION_IDS[faction_id] then
        return PLAYER_FACTION_ALLIANCE, "faction_id:" .. tostring(faction_id)
    end
    if faction_id and HORDE_FACTION_IDS[faction_id] then
        return PLAYER_FACTION_HORDE, "faction_id:" .. tostring(faction_id)
    end

    local map_name = string.lower(tostring(core.get_map_name() or ""))
    if string_contains(map_name, "stormwind")
        or string_contains(map_name, "hurlevent")
        or string_contains(map_name, "alliance")
    then
        return PLAYER_FACTION_ALLIANCE, "map_name"
    end
    if string_contains(map_name, "orgrimmar")
        or string_contains(map_name, "orgrimar")
        or string_contains(map_name, "horde")
    then
        return PLAYER_FACTION_HORDE, "map_name"
    end

    if self:_is_in_bg_or_busy() and self._detected_faction ~= PLAYER_FACTION_UNKNOWN then
        return self._detected_faction, "sticky_bg"
    end

    local my_pos = local_player:get_position()
    local dist_sw = distance_3d(my_pos, CITY_ANCHORS[CITY_STORMWIND])
    local dist_org = distance_3d(my_pos, CITY_ANCHORS[CITY_ORGRIMMAR])
    local near_city = (dist_sw <= CITY_DETECT_RADIUS) or (dist_org <= CITY_DETECT_RADIUS)
    if near_city and math.abs(dist_sw - dist_org) >= CITY_DETECT_MARGIN then
        if dist_sw < dist_org then
            return PLAYER_FACTION_ALLIANCE, "city_distance"
        end
        return PLAYER_FACTION_HORDE, "city_distance"
    end

    if self._detected_faction ~= PLAYER_FACTION_UNKNOWN then
        return self._detected_faction, "sticky_prev"
    end

    if self._city == CITY_STORMWIND then
        return PLAYER_FACTION_ALLIANCE, "city_setting"
    end
    if self._city == CITY_ORGRIMMAR then
        return PLAYER_FACTION_HORDE, "city_setting"
    end

    return PLAYER_FACTION_UNKNOWN, "unknown"
end

function QueueManager:_update_city_from_faction(local_player)
    local faction, source = self:_detect_player_faction(local_player)
    if self._detected_faction ~= faction then
        self:_debug_log(
            "faction_detect",
            string.format(
                "Faction %s -> %s (source=%s)",
                tostring(self._detected_faction),
                tostring(faction),
                tostring(source)
            ),
            1.0
        )
    end
    self._detected_faction = faction
    self._diag.faction_source = source or "none"

    if not self._auto_faction then
        return
    end

    if faction == PLAYER_FACTION_UNKNOWN then
        return
    end

    local wanted_city = (faction == PLAYER_FACTION_ALLIANCE) and CITY_STORMWIND or CITY_ORGRIMMAR
    if self._city ~= wanted_city then
        self._city = wanted_city
        self:_debug_log("auto_city", "Auto faction switched city anchor to " .. wanted_city, 5.0)
        self:_save_settings()
    end
end

function QueueManager:_accept_if_called()
    for i = 1, 3 do
        local status = core.game_ui.get_battlefield_status(i)
        if status == "confirm" then
            self:_set_action("accept_popup")
            core.input.accept_battlefield_port(i, true)
            self._status_text = "Accepting battleground popup"
            return true
        end
    end
    return false
end

function QueueManager:_try_release_spirit()
    local local_player = core.object_manager.get_local_player()
    if not local_player or not local_player:is_valid() or not local_player:is_dead() then
        return false
    end
    if local_player.is_ghost and local_player:is_ghost() then
        self._pending_release_spirit_time = 0
        return false
    end

    local now = now_time()
    if self._pending_release_spirit_time > 0 and now < self._pending_release_spirit_time then
        return false
    end
    if now - self._last_release_spirit_time < self._release_spirit_cooldown then
        return false
    end

    self._last_release_spirit_time = now
    local ok = pcall(function()
        core.input.release_spirit()
    end)
    if ok then
        self._release_spirit_cooldown = random_between(self._release_spirit_cooldown_min, self._release_spirit_cooldown_max)
        self._pending_release_spirit_time = 0
        self:_set_action("release_spirit")
        self:_debug_log("release_spirit", "Released spirit in battleground", 1.0)
        self._status_text = "Released spirit, waiting graveyard rez"
        return true
    end

    self:_debug_log("release_spirit_fail", "release_spirit call failed", 2.0)
    return false
end

function QueueManager:_is_in_bg_or_busy()
    local bg_state = core.game_ui.get_battlefield_state()
    if bg_state and bg_state >= 2 then
        return true
    end

    for i = 1, 3 do
        local status = core.game_ui.get_battlefield_status(i)
        if status_is_busy(status) then
            return true
        end
    end
    return false
end

function QueueManager:_is_in_active_battleground()
    local bg_state = core.game_ui.get_battlefield_state()
    if bg_state and bg_state >= 2 then
        return true
    end

    for i = 1, 3 do
        if core.game_ui.get_battlefield_status(i) == "active" then
            return true
        end
    end
    return false
end

function QueueManager:_get_queue_slot_statuses()
    local slots = { "none", "none", "none" }
    for i = 1, 3 do
        local status = core.game_ui.get_battlefield_status(i)
        if type(status) ~= "string" or status == "" then
            status = "none"
        end
        slots[i] = status
    end
    return slots
end

function QueueManager:_get_queue_status_counts()
    local queued = 0
    local confirm = 0
    local active = 0

    local slots = self:_get_queue_slot_statuses()
    for i = 1, 3 do
        local status = slots[i]
        if status == "queued" then
            queued = queued + 1
        elseif status == "confirm" then
            confirm = confirm + 1
        elseif status == "active" then
            active = active + 1
        end
    end

    return queued, confirm, active, slots
end

function QueueManager:_safe_object_name(obj)
    local ok, name = pcall(function() return obj:get_name() end)
    if ok and name then
        return string.lower(name)
    end
    return ""
end

function QueueManager:_is_capture_banner_object(obj)
    if not obj or not obj:is_valid() then
        return false
    end
    if obj:is_unit() or obj:is_player() then
        return false
    end

    local name = self:_safe_object_name(obj)
    if name == "" then
        return false
    end

    return string.find(name, "banner", 1, true)
        or string.find(name, "flag", 1, true)
        or string.find(name, "banni", 1, true)
end

function QueueManager:_find_nearest_banner_near(pos, max_dist)
    local objects = core.object_manager.get_all_objects()
    local best = nil
    local best_dist = max_dist + 1.0

    for _, obj in ipairs(objects) do
        if self:_is_capture_banner_object(obj) then
            local obj_pos = obj:get_position()
            local dist = distance_3d(pos, obj_pos)
            if dist <= max_dist and dist < best_dist then
                best = obj
                best_dist = dist
            end
        end
    end

    return best, best_dist
end

function QueueManager:_banner_needs_tag(banner)
    local name = self:_safe_object_name(banner)
    if name == "" then
        -- Unknown names are treated as contestable to keep behavior simple.
        return true
    end

    local is_alliance_side = self._city == CITY_STORMWIND
    if self._detected_faction == PLAYER_FACTION_ALLIANCE then
        is_alliance_side = true
    elseif self._detected_faction == PLAYER_FACTION_HORDE then
        is_alliance_side = false
    end
    local looks_alliance = string.find(name, "alliance", 1, true)
        or string.find(name, "stormpike", 1, true)
    local looks_horde = string.find(name, "horde", 1, true)
        or string.find(name, "frostwolf", 1, true)

    if is_alliance_side then
        if looks_alliance and not looks_horde then
            return false
        end
        return true
    end

    if looks_horde and not looks_alliance then
        return false
    end
    return true
end

function QueueManager:_defend_last_gy(local_player)
    local faction_city = self._city
    if self._detected_faction == PLAYER_FACTION_ALLIANCE then
        faction_city = CITY_STORMWIND
    elseif self._detected_faction == PLAYER_FACTION_HORDE then
        faction_city = CITY_ORGRIMMAR
    end
    local gy_pos = AV_LAST_GY_BY_CITY[faction_city] or AV_LAST_GY_BY_CITY[CITY_STORMWIND]
    local my_pos = local_player:get_position()
    local dist_to_gy = distance_3d(my_pos, gy_pos)

    if dist_to_gy > 25.0 then
        self:_set_action("def_move_last_gy")
        self:_debug_log("def_move_gy", string.format("DEF moving to last GY (%.1f yd)", dist_to_gy))
        self._status_text = string.format(
            "BG DEF: moving to last GY (%.1f yd)",
            dist_to_gy
        )
        self:_move_to(gy_pos)
        return
    end

    local banner, banner_dist = self:_find_nearest_banner_near(gy_pos, 35.0)
    if banner then
        self:_debug_log("def_banner_found", string.format("DEF banner near last GY (%.1f yd)", banner_dist))
        if not self:_banner_needs_tag(banner) then
            self:_set_action("def_hold_friendly_gy")
            self:_debug_log("def_banner_ours", "DEF last GY banner already friendly", 5.0)
            self._status_text = "BG DEF: last GY already ours"
            return
        end

        if banner_dist > 8.0 then
            self:_set_action("def_move_banner")
            self:_debug_log("def_move_banner", string.format("DEF moving to banner (%.1f yd)", banner_dist))
            self._status_text = string.format(
                "BG DEF: moving to GY banner (%.1f yd)",
                banner_dist
            )
            self:_move_to(banner:get_position())
            return
        end

        local now = now_time()
        if now - self._last_banner_interact_time >= self._banner_interact_cooldown then
            self:_set_action("def_interact_banner")
            self:_debug_log("def_tag_banner", "DEF interacting with banner (retag/hold)")
            core.input.look_at(banner:get_position())
            core.input.interact_with_object(banner)
            self._last_banner_interact_time = now
            self._banner_interact_cooldown = random_between(self._banner_interact_cooldown_min, self._banner_interact_cooldown_max)
            self._status_text = "BG DEF: holding/retagging last GY"
            return
        end
    else
        self:_debug_log("def_no_banner", "DEF no banner found near last GY", 6.0)
    end

    self:_debug_log("def_hold_gy", "DEF holding last GY", 5.0)
    self:_set_action("def_hold_last_gy")
    self._status_text = "BG DEF: holding last GY"
end

function QueueManager:_is_enemy_player(local_player, obj)
    if not obj or not obj:is_valid() or not obj:is_player() or obj:is_dead() then
        return false
    end
    return safe_relation(local_player, obj, "is_enemy_with")
end

function QueueManager:_is_friendly_player(local_player, obj)
    if not obj or not obj:is_valid() or not obj:is_player() or obj:is_dead() then
        return false
    end
    return safe_relation(local_player, obj, "is_friend_with")
end

function QueueManager:_unit_has_flag_aura(unit)
    if not unit or not unit.is_valid or not unit:is_valid() then
        return false
    end

    local ok_buffs, buffs = pcall(function()
        return unit:get_buffs()
    end)
    if not ok_buffs or not buffs then
        return false
    end

    for _, buff in ipairs(buffs) do
        local name = string.lower(tostring((buff and buff.buff_name) or ""))
        if name ~= "" then
            if string_contains(name, "flag")
                or string_contains(name, "drapeau")
                or string_contains(name, "banni")
                or string_contains(name, "silverwing")
                or string_contains(name, "chanteguerre")
            then
                return true
            end
        end
    end

    return false
end

function QueueManager:_find_nearest_enemy_player(local_player, max_dist)
    local objects = core.object_manager.get_all_objects()
    local my_pos = local_player:get_position()
    local best = nil
    local best_dist = max_dist + 1.0

    for _, obj in ipairs(objects) do
        if self:_is_enemy_player(local_player, obj) then
            local dist = distance_3d(my_pos, obj:get_position())
            if dist <= max_dist and dist < best_dist then
                best = obj
                best_dist = dist
            end
        end
    end

    return best, best_dist
end

function QueueManager:_find_nearest_friendly_player(local_player, max_dist)
    local objects = core.object_manager.get_all_objects()
    local my_pos = local_player:get_position()
    local best = nil
    local best_dist = max_dist + 1.0

    for _, obj in ipairs(objects) do
        if self:_is_friendly_player(local_player, obj) then
            local dist = distance_3d(my_pos, obj:get_position())
            if dist > 2.0 and dist <= max_dist and dist < best_dist then
                best = obj
                best_dist = dist
            end
        end
    end

    return best, best_dist
end

function QueueManager:_find_flag_carrier(local_player, enemy_side, max_dist)
    local objects = core.object_manager.get_all_objects()
    local my_pos = local_player:get_position()
    local best = nil
    local best_dist = max_dist + 1.0

    for _, obj in ipairs(objects) do
        local side_ok = false
        if enemy_side then
            side_ok = self:_is_enemy_player(local_player, obj)
        else
            side_ok = self:_is_friendly_player(local_player, obj)
        end

        if side_ok and self:_unit_has_flag_aura(obj) then
            local dist = distance_3d(my_pos, obj:get_position())
            if dist <= max_dist and dist < best_dist then
                best = obj
                best_dist = dist
            end
        end
    end

    return best, best_dist
end

function QueueManager:_warsong_skirmish(local_player)
    local enemy_fc, enemy_fc_dist = self:_find_flag_carrier(local_player, true, WSG_SCAN_RADIUS)
    if enemy_fc then
        if enemy_fc_dist > WSG_CHASE_RANGE then
            self:_set_action("wsg_chase_enemy_flag")
            self._status_text = string.format("WSG: chasing enemy flag carrier (%.1f yd)", enemy_fc_dist)
            self:_move_to(enemy_fc:get_position())
        else
            self:_set_action("wsg_pressure_enemy_flag")
            self._status_text = "WSG: pressuring enemy flag carrier"
        end
        return
    end

    local friendly_fc, friendly_fc_dist = self:_find_flag_carrier(local_player, false, WSG_FOLLOW_ALLY_RADIUS)
    if friendly_fc then
        if friendly_fc_dist > WSG_FOLLOW_MOVE_MIN then
            self:_set_action("wsg_escort_friendly_flag")
            self._status_text = string.format("WSG: escorting friendly flag carrier (%.1f yd)", friendly_fc_dist)
            self:_move_to(friendly_fc:get_position())
        else
            self:_set_action("wsg_guard_friendly_flag")
            self._status_text = "WSG: guarding friendly flag carrier"
        end
        return
    end

    local enemy, enemy_dist = self:_find_nearest_enemy_player(local_player, WSG_SCAN_RADIUS)
    if enemy then
        if enemy_dist > WSG_CHASE_RANGE then
            self:_set_action("wsg_chase_enemy")
            self._status_text = string.format("WSG: pushing mid enemy (%.1f yd)", enemy_dist)
            self:_move_to(enemy:get_position())
        else
            self:_set_action("wsg_fight_enemy")
            self._status_text = "WSG: fighting enemy at mid"
        end
        return
    end

    local ally, ally_dist = self:_find_nearest_friendly_player(local_player, WSG_FOLLOW_ALLY_RADIUS)
    if ally and ally_dist > WSG_FOLLOW_MOVE_MIN then
        self:_set_action("wsg_follow_ally")
        self._status_text = string.format("WSG: regrouping with ally (%.1f yd)", ally_dist)
        self:_move_to(ally:get_position())
        return
    end

    self:_set_action("wsg_hold")
    self._status_text = "WSG: holding position, waiting target"
end

function QueueManager:_arathi_skirmish(local_player)
    local enemy, enemy_dist = self:_find_nearest_enemy_player(local_player, AB_SCAN_RADIUS)
    if enemy then
        if enemy_dist > AB_ENGAGE_RANGE then
            self:_set_action("ab_chase_enemy")
            self._status_text = string.format("AB: rotating to enemy (%.1f yd)", enemy_dist)
            self:_move_to(enemy:get_position())
        else
            self:_set_action("ab_fight_enemy")
            self._status_text = "AB: fighting near node"
        end
        return
    end

    local my_pos = local_player:get_position()
    local banner, banner_dist = self:_find_nearest_banner_near(my_pos, 30.0)
    if banner and self:_banner_needs_tag(banner) then
        if banner_dist > 8.0 then
            self:_set_action("ab_move_banner")
            self._status_text = string.format("AB: rotating to flag (%.1f yd)", banner_dist)
            self:_move_to(banner:get_position())
            return
        end

        local now = now_time()
        if now - self._last_banner_interact_time >= self._banner_interact_cooldown then
            self:_set_action("ab_tag_banner")
            core.input.look_at(banner:get_position())
            core.input.interact_with_object(banner)
            self._last_banner_interact_time = now
            self._banner_interact_cooldown = random_between(self._banner_interact_cooldown_min, self._banner_interact_cooldown_max)
            self._status_text = "AB: tagging/defending node"
            return
        end
    end

    local ally, ally_dist = self:_find_nearest_friendly_player(local_player, AB_FOLLOW_ALLY_RADIUS)
    if ally and ally_dist > AB_FOLLOW_MOVE_MIN then
        self:_set_action("ab_follow_ally")
        self._status_text = string.format("AB: regrouping with ally (%.1f yd)", ally_dist)
        self:_move_to(ally:get_position())
        return
    end

    self:_set_action("ab_hold")
    self._status_text = "AB: holding and scanning for enemies"
end

function QueueManager:_find_nearest_bg_battlemaster(local_player, bg_key)
    local objects = core.object_manager.get_all_objects()
    local my_pos = local_player:get_position()
    local bg = BG_DATA[bg_key] or BG_DATA[BG_ALTERAC]

    local best = nil
    local best_dist = 99999.0
    local best_match_type = "none"
    local scanned = 0
    local matched = 0

    for _, obj in ipairs(objects) do
        scanned = scanned + 1
        local is_match, match_type = is_bg_battlemaster(obj, bg_key)
        if is_match then
            matched = matched + 1
            local dist = distance_3d(my_pos, obj:get_position())
            if dist < best_dist then
                best = obj
                best_dist = dist
                best_match_type = match_type
            end
        end
    end

    self._diag.last_scan_bg = bg.key
    self._diag.scanned_count = scanned
    self._diag.matched_count = matched
    if best then
        self._diag.last_match_type = best_match_type
        self._diag.last_match_npc_id = best:get_npc_id() or 0
        self._diag.last_match_name = safe_lower_name(best)
        self._diag.last_match_distance = best_dist
    else
        self._diag.last_match_type = "none"
        self._diag.last_match_npc_id = 0
        self._diag.last_match_name = ""
        self._diag.last_match_distance = 0
    end

    return best, best_dist
end

function QueueManager:_move_to(pos)
    if not self._nav then
        return
    end

    local now = now_time()
    if now - self._last_move_order_time < self._move_order_cooldown then
        return
    end

    self._last_move_order_time = now
    self._move_order_cooldown = random_between(self._move_order_cooldown_min, self._move_order_cooldown_max)
    self._nav:move_to(pos, nil, { use_navmesh = true })
end

function QueueManager:_attempt_queue(local_player)
    local now = now_time()
    if now - self._last_queue_time < self._queue_cooldown then
        return
    end

    local bg = self:_get_queue_target_bg_data()
    local preferred = self:_get_preferred_battlemaster(self._city, bg.key)
    local battlemaster, dist = self:_find_preferred_battlemaster(local_player, preferred)
    if not battlemaster then
        battlemaster, dist = self:_find_nearest_bg_battlemaster(local_player, bg.key)
    end
    if not battlemaster then
        if preferred and preferred.position then
            local map_id = current_map_id()
            if preferred.map_id and map_id and is_clearly_other_continent(map_id, preferred.map_id) then
                self:_set_action("preferred_battlemaster_wrong_map")
                self._status_text = string.format(
                    "Wrong continent for %s (%s #%d): need map %d, current %d",
                    preferred.map_id,
                    bg.label,
                    tostring(preferred.name or "preferred battlemaster"),
                    tonumber(preferred.npc_id or 0),
                    map_id
                )
                return
            end

            self:_set_action("move_preferred_battlemaster")
            self._status_text = string.format(
                "Moving to %s (%s #%d) at %.1f %.1f %.1f",
                bg.label,
                tostring(preferred.name or "preferred battlemaster"),
                tonumber(preferred.npc_id or 0),
                preferred.position.x,
                preferred.position.y,
                preferred.position.z
            )
            self:_move_to(preferred.position)
            return
        end

        local city_pos = self:_get_queue_anchor(bg.key, self._city)
        self:_set_action("move_anchor")
        self._status_text = string.format(
            "Moving to %s %s BG anchor (%.1f %.1f %.1f)",
            bg.label,
            self._city,
            city_pos.x,
            city_pos.y,
            city_pos.z
        )
        self:_move_to(city_pos)
        return
    end

    if dist > self._interact_range then
        self:_set_action("move_battlemaster")
        self._status_text = string.format("Approaching %s battlemaster (%.1f yd)", bg.label, dist)
        self:_move_to(battlemaster:get_position())
        return
    end

    if now - self._last_interact_time >= self._interact_cooldown then
        self:_set_action("interact_battlemaster")
        core.input.set_target(battlemaster)
        core.input.look_at(battlemaster:get_position())
        core.input.interact_with_object(battlemaster)
        core.input.join_battlefield(bg.queue_id, ROLE_FLAGS_NONE)
        self._last_interact_time = now
        self._last_queue_time = now
        self._interact_cooldown = random_between(self._interact_cooldown_min, self._interact_cooldown_max)
        self._queue_cooldown = random_between(self._queue_cooldown_min, self._queue_cooldown_max)
        self._status_text = "Interacted and requested " .. bg.label .. " queue"
        self:_advance_queue_target(bg.key)
    end
end

function QueueManager:update()
    if self._nav then
        self._nav:update()
    end

    local local_player = core.object_manager.get_local_player()
    if local_player and local_player:is_valid() then
        self:_update_city_from_faction(local_player)
    end

    if not self._running then
        return
    end

    if not self:_ensure_nav() then
        return
    end

    if not local_player or not local_player:is_valid() then
        self._status_text = "Player unavailable"
        return
    end

    if local_player:is_dead() then
        local is_ghost = local_player.is_ghost and local_player:is_ghost()
        if not self._was_dead_last_tick then
            self:_set_action("player_died")
            self:_debug_log("player_died", "Player died", 1.0)
            self._pending_release_spirit_time = now_time() + random_between(
                self._release_spirit_first_delay_min,
                self._release_spirit_first_delay_max
            )
        end
        self._was_dead_last_tick = true

        if self:_is_in_bg_or_busy() then
            if is_ghost then
                self:_set_action("ghost_waiting_rez")
                self._status_text = "Ghost at graveyard, waiting rez wave"
            elseif not self:_try_release_spirit() then
                self._status_text = "Player dead, waiting spirit release/rez"
            end
        else
            self._status_text = "Player dead"
        end
        return
    end
    if self._was_dead_last_tick then
        self._was_dead_last_tick = false
        self._pending_release_spirit_time = 0
        self:_set_action("player_rezzed")
        self:_debug_log("player_rezzed", "Player resurrected, resuming logic", 1.0)
        self._status_text = "Resurrected, resuming"
    end

    self:_tick_stuck(local_player)
    if self:_accept_if_called() then
        return
    end

    if self:_is_in_active_battleground() then
        self:_run_active_scenario(local_player)
        if self._combat then
            self._combat:update(local_player)
        end
        return
    end

    local queued_count, confirm_count, active_count, slots = self:_get_queue_status_counts()
    self._diag.slot1_status = slots[1] or "none"
    self._diag.slot2_status = slots[2] or "none"
    self._diag.slot3_status = slots[3] or "none"
    local target_queue_count = self:_get_target_queue_count()
    self._diag.queue_target_count = target_queue_count
    if confirm_count > 0 or active_count > 0 then
        self:_set_action("bg_busy")
        self._active_scenario_id = "none"
        self._status_text = "Queue popup/active battleground pending"
        return
    end

    if queued_count >= target_queue_count then
        self:_set_action("bg_queued")
        self._active_scenario_id = "none"
        self._status_text = string.format("Queued (%d/%d)", queued_count, target_queue_count)
        return
    end

    self:_attempt_queue(local_player)
end

function QueueManager:destroy()
    self:stop()
    if self._nav and self._nav.destroy then
        self._nav:destroy()
    end
    self._nav = nil
end

return QueueManager
