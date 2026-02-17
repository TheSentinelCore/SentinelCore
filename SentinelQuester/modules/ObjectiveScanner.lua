local QuestieAdapter = require("modules/QuestieAdapter")

---@class ObjectiveScanner
---@field private _config table
---@field private _questie QuestieAdapter
---@field private _last_scan_time number
---@field private _cached_candidates table[]
---@field private _last_fallback_used boolean
local ObjectiveScanner = {}
ObjectiveScanner.__index = ObjectiveScanner

local DEFAULT_CONFIG = {
    scan_interval = 0.30,
    scan_radius = 70.0,
    require_questie = true,
    fallback_include_hostiles = true,
    allow_hooked_fallback = true,
}

local function safe_method(obj, method_name, ...)
    if not obj then
        return nil
    end

    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil
    end

    return result
end

local function safe_bool(obj, method_name, ...)
    return safe_method(obj, method_name, ...) == true
end

local function dist3(a, b)
    if not a or not b then
        return math.huge
    end

    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function merge_config(target, source)
    if not source then
        return
    end

    for k, v in pairs(source) do
        target[k] = v
    end
end

local function try_call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    return result
end

local function normalize_name(s)
    if type(s) ~= "string" then
        return nil
    end
    local n = string.lower(s)
    n = n:gsub("^%s+", ""):gsub("%s+$", "")
    n = n:gsub("[%.,!?:;\"'`%(%)]", "")
    n = n:gsub("%s+", " ")
    if n == "" then
        return nil
    end
    return n
end

local function add_name_hint(name_set, raw_name)
    local n = normalize_name(raw_name)
    if n then
        name_set[n] = true
    end
end

local function extract_names_from_text(name_set, text)
    if type(text) ~= "string" then
        return
    end

    local patterns = {
        "[Pp]arler [aà][uux]* ([^%.!\n]+)",
        "[Rr]apporter [aà][uux]* ([^%.!\n]+)",
        "[Vv]oir ([^%.!\n]+)",
        "[Ss]peak to ([^%.!\n]+)",
        "[Tt]urn in [^%.!\n]+ to ([^%.!\n]+)",
    }

    for _, pattern in ipairs(patterns) do
        local capture = text:match(pattern)
        if capture then
            add_name_hint(name_set, capture)
        end
    end
end

local function harvest_names_from_table(name_set, value, depth)
    if depth > 3 or value == nil then
        return
    end

    local t = type(value)
    if t == "string" then
        extract_names_from_text(name_set, value)
        return
    end

    if t ~= "table" then
        return
    end

    for k, v in pairs(value) do
        local key = type(k) == "string" and string.lower(k) or nil
        if key and type(v) == "string" then
            if key:find("npc", 1, true) or key:find("giver", 1, true) or key:find("turn", 1, true) or key:find("target", 1, true) then
                add_name_hint(name_set, v)
            end
            extract_names_from_text(name_set, v)
        elseif type(v) == "table" then
            harvest_names_from_table(name_set, v, depth + 1)
        end
    end
end

local function collect_quest_name_hints(player)
    local hints = {}
    local sources = {
        safe_method(player, "get_quest_log"),
        safe_method(player, "get_quests"),
        safe_method(player, "get_active_quests"),
        safe_method(player, "get_tracked_quests"),
        try_call(function() return core.quest_log and core.quest_log.get_all and core.quest_log:get_all() end),
        try_call(function() return core.quest and core.quest.get_all and core.quest.get_all() end),
    }

    for _, source in ipairs(sources) do
        harvest_names_from_table(hints, source, 0)
        if type(source) == "string" then
            extract_names_from_text(hints, source)
        end
    end

    return hints
end

---@param config? table
---@param questie_adapter? QuestieAdapter
---@return ObjectiveScanner
function ObjectiveScanner:new(config, questie_adapter)
    local o = setmetatable({}, ObjectiveScanner)

    o._config = {}
    merge_config(o._config, DEFAULT_CONFIG)
    merge_config(o._config, config)

    o._questie = questie_adapter or QuestieAdapter:new()
    o._last_scan_time = 0
    o._cached_candidates = {}
    o._last_fallback_used = false

    return o
end

---@param overrides table
function ObjectiveScanner:update_config(overrides)
    merge_config(self._config, overrides)
end

---@param guid number|string|nil
---@param blacklist table|nil
---@return boolean
local function is_blacklisted(guid, blacklist)
    if not guid or not blacklist then
        return false
    end

    local expires_at = blacklist[guid]
    if not expires_at then
        return false
    end

    return expires_at > core.time()
end

---@param player game_object
---@param obj game_object
---@return boolean
local function is_hostile_to_player(player, obj)
    if safe_method(obj, "is_enemy_with", player) == true then
        return true
    end

    if safe_method(player, "is_enemy_with", obj) == true then
        return true
    end

    if safe_method(player, "can_attack", obj) == true then
        return true
    end

    return false
end

local function has_quest_npc_flag(obj)
    local bool_methods = {
        "has_quest",
        "has_quest_available",
        "has_available_quest",
        "has_quest_turnin",
        "has_quest_turn_in",
        "has_turnin_quest",
        "has_quest_to_turn_in",
        "is_quest_giver",
        "is_quest_npc",
    }
    for _, m in ipairs(bool_methods) do
        if safe_bool(obj, m) then
            return true
        end
    end

    local count_methods = {
        "get_available_quest_count",
        "get_turnin_quest_count",
        "get_quest_count",
    }
    for _, m in ipairs(count_methods) do
        local v = safe_method(obj, m)
        if type(v) == "number" and v > 0 then
            return true
        end
    end

    return false
end

---@param player game_object
---@param blacklist? table
---@return table[]
function ObjectiveScanner:scan(player, blacklist)
    local now = core.time()
    if (now - self._last_scan_time) < (self._config.scan_interval or DEFAULT_CONFIG.scan_interval) then
        return self._cached_candidates
    end
    self._last_scan_time = now

    local player_pos = safe_method(player, "get_position")
    if not player_pos then
        self._cached_candidates = {}
        return self._cached_candidates
    end

    local player_guid = safe_method(player, "get_guid")
    local all_objects = core.object_manager.get_all_objects() or {}

    local questie_hooked = self._questie:is_hooked()
    local require_questie = self._config.require_questie == true
    local scan_radius = self._config.scan_radius or DEFAULT_CONFIG.scan_radius
    local allow_hostiles = self._config.fallback_include_hostiles == true
    local name_hints = collect_quest_name_hints(player)
    local allow_name_hint_fallback = self._config.allow_name_hint_fallback ~= false

    local strict_candidates = {}
    local fallback_candidates = {}
    for _, obj in ipairs(all_objects) do
        if obj and safe_bool(obj, "is_valid") then
            local guid = safe_method(obj, "get_guid")
            if guid and guid ~= player_guid and not is_blacklisted(guid, blacklist) then
                local pos = safe_method(obj, "get_position")
                local distance = dist3(player_pos, pos)
                if pos and distance <= scan_radius then
                    local is_quest_object = false
                    local is_quest_npc = false
                    local accepted = true

                    if questie_hooked then
                        is_quest_object = self._questie:is_quest_object(obj)
                        is_quest_npc = self._questie:is_quest_npc(obj)
                        accepted = is_quest_object or is_quest_npc
                    elseif require_questie then
                        accepted = false
                    end

                    local can_use = safe_bool(obj, "can_be_used")
                    local can_loot = safe_bool(obj, "can_be_looted")
                    local is_unit = safe_bool(obj, "is_unit")
                    local is_dead = safe_bool(obj, "is_dead")
                    local is_hostile = is_unit and (not is_dead) and is_hostile_to_player(player, obj)
                    local fallback_ok = can_use or can_loot or (allow_hostiles and is_hostile)
                    local hooked_fallback_ok = can_loot

                    local name = safe_method(obj, "get_name") or "<unnamed>"
                    local name_key = normalize_name(name)
                    local has_quest_flag = has_quest_npc_flag(obj)
                    local is_named_quest_npc = allow_name_hint_fallback
                        and (name_key ~= nil)
                        and (name_hints[name_key] == true)
                        and is_unit
                        and (not is_dead)
                        and (not is_hostile)
                    local is_flagged_quest_npc = has_quest_flag
                        and is_unit
                        and (not is_dead)
                        and (not is_hostile)
                    local score = distance
                    if is_quest_object then score = score - 15 end
                    if is_quest_npc then score = score - 12 end
                    if is_named_quest_npc then score = score - 20 end
                    if is_flagged_quest_npc then score = score - 18 end
                    if can_use then score = score - 4 end
                    if can_loot then score = score - 3 end
                    if is_hostile then score = score - 2 end

                    local candidate = {
                        object = obj,
                        guid = guid,
                        name = name,
                        position = pos,
                        distance = distance,
                        score = score,
                        is_quest_object = is_quest_object,
                        is_quest_npc = is_quest_npc,
                        is_named_quest_npc = is_named_quest_npc,
                        is_flagged_quest_npc = is_flagged_quest_npc,
                        can_use = can_use,
                        can_loot = can_loot,
                        is_hostile = is_hostile,
                    }

                    if accepted then
                        strict_candidates[#strict_candidates + 1] = candidate
                    elseif questie_hooked and require_questie and is_flagged_quest_npc then
                        fallback_candidates[#fallback_candidates + 1] = candidate
                    elseif questie_hooked and require_questie and is_named_quest_npc then
                        fallback_candidates[#fallback_candidates + 1] = candidate
                    elseif questie_hooked and require_questie and (self._config.allow_hooked_fallback == true) and hooked_fallback_ok then
                        fallback_candidates[#fallback_candidates + 1] = candidate
                    elseif (not questie_hooked) and (not require_questie) and fallback_ok then
                        strict_candidates[#strict_candidates + 1] = candidate
                    end
                end
            end
        end
    end

    table.sort(strict_candidates, function(a, b)
        if a.score == b.score then
            return a.distance < b.distance
        end
        return a.score < b.score
    end)

    table.sort(fallback_candidates, function(a, b)
        if a.score == b.score then
            return a.distance < b.distance
        end
        return a.score < b.score
    end)

    local candidates = strict_candidates
    self._last_fallback_used = false
    if questie_hooked and require_questie and #strict_candidates == 0 and #fallback_candidates > 0 then
        candidates = fallback_candidates
        self._last_fallback_used = true
    end

    self._cached_candidates = candidates
    return candidates
end

---@param player game_object
---@param blacklist? table
---@return table|nil
function ObjectiveScanner:get_best_objective(player, blacklist)
    local candidates = self:scan(player, blacklist)
    if #candidates == 0 then
        return nil
    end
    return candidates[1]
end

---@return table
function ObjectiveScanner:get_status()
    return {
        questie_status = self._questie:get_status(),
        candidate_count = #self._cached_candidates,
        require_questie = self._config.require_questie == true,
        fallback_used = self._last_fallback_used == true,
    }
end

return ObjectiveScanner
