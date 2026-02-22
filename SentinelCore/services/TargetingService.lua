local Helpers = require("lib/Helpers")
local FactionResolver = require("lib/FactionResolver")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}

local CRITTER_CREATURE_TYPE_ID = 8

---@param obj any
---@param method string
---@param ... any
---@return any
local function safe_method(obj, method, ...)
    if not obj then
        return nil
    end
    local fn = obj[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return value
end

---@param value any
---@return any
local function unwrap_game_object(value)
    if type(value) ~= "table" then
        return value
    end

    for i = 1, #OBJECT_UNWRAP_KEYS do
        local candidate = rawget(value, OBJECT_UNWRAP_KEYS[i])
        if candidate ~= nil then
            return candidate
        end
    end

    return value
end

---@private
---@param lhs game_object|nil
---@param rhs game_object|nil
---@return boolean
local function is_same_unit(lhs, rhs)
    if not lhs or not rhs then
        return false
    end
    if lhs == rhs then
        return true
    end

    local lhs_guid = tonumber(safe_method(lhs, "get_guid"))
        or tonumber(safe_method(lhs, "get_object_guid"))
        or 0
    local rhs_guid = tonumber(safe_method(rhs, "get_guid"))
        or tonumber(safe_method(rhs, "get_object_guid"))
        or 0
    if lhs_guid > 0 and rhs_guid > 0 then
        return lhs_guid == rhs_guid
    end

    return false
end

---@private
---@param objects table
---@param unit game_object|nil
---@return boolean
local function is_visible_unit(objects, unit)
    if not unit then
        return false
    end
    if type(objects) ~= "table" then
        return false
    end

    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        if is_same_unit(candidate, unit) then
            return true
        end
    end
    return false
end

---@private
---@param unit game_object|nil
---@return number
local function safe_unit_guid(unit)
    local guid = tonumber(safe_method(unit, "get_guid"))
        or tonumber(safe_method(unit, "get_object_guid"))
        or 0
    return guid
end

---@private
---@return number
local function now_seconds()
    return (core and core.time and core.time()) or 0
end

---@class TargetingService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _nav NavigationAdapter|nil
---@field private _current_target game_object|nil
---@field private _target_memory table<string, table>
---@field private _target_memory_last_prune_at number
---@field private _path_cost_cache table<string, table>
---@field private _path_cost_last_prune_at number
local TargetingService = {}
TargetingService.__index = TargetingService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@param navigation? NavigationAdapter
---@return TargetingService
function TargetingService:new(event_bus, blackboard, cfg, navigation)
    local o = setmetatable({}, TargetingService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._current_target = nil
    o._target_memory = {}
    o._target_memory_last_prune_at = 0
    o._path_cost_cache = {}
    o._path_cost_last_prune_at = 0
    return o
end

---@private
---@param target game_object|nil
---@return string
function TargetingService:_target_memory_key(target)
    local guid = safe_unit_guid(target)
    if guid > 0 then
        return "guid:" .. tostring(guid)
    end

    local npc_id = tonumber(safe_method(target, "get_npc_id")) or 0
    local pos = safe_method(target, "get_position")
    local x = tonumber(pos and pos.x) or 0
    local y = tonumber(pos and pos.y) or 0
    local z = tonumber(pos and pos.z) or 0
    local name = tostring(safe_method(target, "get_name") or "unknown")
    return string.format("fallback:%d:%s:%.1f:%.1f:%.1f", npc_id, name, x, y, z)
end

---@private
---@param now number
function TargetingService:_prune_target_memory(now)
    local prune_interval = tonumber(self._cfg.target_memory_prune_interval) or 2.0
    if (now - (tonumber(self._target_memory_last_prune_at) or 0)) < prune_interval then
        return
    end
    self._target_memory_last_prune_at = now

    local active_count = 0
    for key, entry in pairs(self._target_memory) do
        local retry_until = tonumber(entry and entry.retry_until) or 0
        if retry_until > now then
            active_count = active_count + 1
        else
            self._target_memory[key] = nil
        end
    end

    local max_entries = tonumber(self._cfg.target_memory_max_entries) or 256
    if active_count <= max_entries then
        return
    end

    local overflow = active_count - max_entries
    for key, _ in pairs(self._target_memory) do
        self._target_memory[key] = nil
        overflow = overflow - 1
        if overflow <= 0 then
            break
        end
    end
end

---@private
---@param target game_object|nil
---@param now? number
---@return boolean
---@return table|nil
function TargetingService:_is_target_blacklisted(target, now)
    if not target then
        return false, nil
    end
    now = tonumber(now) or now_seconds()
    local key = self:_target_memory_key(target)
    local entry = self._target_memory[key]
    if type(entry) ~= "table" then
        return false, nil
    end

    local retry_until = tonumber(entry.retry_until) or 0
    if retry_until > now then
        return true, entry
    end

    self._target_memory[key] = nil
    return false, nil
end

---@param target game_object|nil
---@param reason string|nil
---@param ttl number|nil
function TargetingService:mark_target_failed(target, reason, ttl)
    if not target then
        return
    end

    local now = now_seconds()
    self:_prune_target_memory(now)

    local resolved_ttl = tonumber(ttl) or tonumber(self._cfg.target_memory_default_ttl) or 12.0
    if resolved_ttl <= 0 then
        return
    end

    local key = self:_target_memory_key(target)
    local previous = self._target_memory[key]
    local retry_until = now + resolved_ttl
    if type(previous) == "table" and tonumber(previous.retry_until) then
        retry_until = math.max(retry_until, tonumber(previous.retry_until) or 0)
    end

    self._target_memory[key] = {
        retry_until = retry_until,
        reason = reason or (type(previous) == "table" and previous.reason) or ErrorCodes.TARGET_LOST,
        failures = (type(previous) == "table" and (tonumber(previous.failures) or 0) or 0) + 1,
        last_updated = now,
    }
end

---@param target game_object|nil
---@return boolean
function TargetingService:is_target_blacklisted(target)
    local blocked = self:_is_target_blacklisted(target, now_seconds())
    return blocked == true
end

---@private
---@param target game_object|nil
---@return string
function TargetingService:_path_cost_key(target)
    return self:_target_memory_key(target)
end

---@private
---@param now number
function TargetingService:_prune_path_cost_cache(now)
    local prune_interval = tonumber(self._cfg.path_cost_prune_interval) or 2.0
    if (now - (tonumber(self._path_cost_last_prune_at) or 0)) < prune_interval then
        return
    end
    self._path_cost_last_prune_at = now

    local ttl = tonumber(self._cfg.path_cost_cache_ttl) or 8.0
    local max_entries = tonumber(self._cfg.path_cost_cache_max_entries) or 256
    local active = 0
    for key, entry in pairs(self._path_cost_cache) do
        local updated_at = tonumber(entry and entry.updated_at) or 0
        local pending = entry and entry.pending == true
        if pending or (updated_at > 0 and (now - updated_at) <= ttl) then
            active = active + 1
        else
            self._path_cost_cache[key] = nil
        end
    end

    if active <= max_entries then
        return
    end

    local overflow = active - max_entries
    for key, _ in pairs(self._path_cost_cache) do
        self._path_cost_cache[key] = nil
        overflow = overflow - 1
        if overflow <= 0 then
            break
        end
    end
end

---@private
---@param target game_object|nil
---@param now number
---@return table|nil
function TargetingService:_path_cost_snapshot(target, now)
    if not target then
        return nil
    end
    local key = self:_path_cost_key(target)
    local entry = self._path_cost_cache[key]
    if type(entry) ~= "table" then
        return nil
    end

    local ttl = tonumber(self._cfg.path_cost_cache_ttl) or 8.0
    local updated_at = tonumber(entry.updated_at) or 0
    if entry.pending == true then
        return nil
    end
    if updated_at <= 0 or (now - updated_at) > ttl then
        self._path_cost_cache[key] = nil
        return nil
    end
    return entry
end

---@private
---@param target game_object|nil
---@param player_pos vec3|nil
---@param now number
function TargetingService:_warm_path_cost(target, player_pos, now)
    if not target
        or not player_pos
        or not self._nav
        or type(self._nav.estimate_path_cost) ~= "function" then
        return
    end

    self:_prune_path_cost_cache(now)

    local target_pos = safe_method(target, "get_position")
    if not target_pos then
        return
    end

    local key = self:_path_cost_key(target)
    local entry = self._path_cost_cache[key]
    local request_interval = tonumber(self._cfg.path_cost_request_interval) or 1.5
    local stale_window = tonumber(self._cfg.path_cost_cache_ttl) or 8.0
    if type(entry) == "table" then
        local requested_at = tonumber(entry.requested_at) or 0
        if entry.pending == true and (now - requested_at) < request_interval then
            return
        end
        local updated_at = tonumber(entry.updated_at) or 0
        if entry.pending ~= true and updated_at > 0 and (now - updated_at) < stale_window then
            return
        end
    else
        entry = {}
        self._path_cost_cache[key] = entry
    end

    entry.pending = true
    entry.requested_at = now

    local target_ref = target
    self._nav:estimate_path_cost(player_pos, target_pos, function(ok, cost, error_code)
        local current = self._path_cost_cache[key]
        if type(current) ~= "table" then
            current = {}
            self._path_cost_cache[key] = current
        end

        current.pending = false
        current.updated_at = now_seconds()
        if ok == true and tonumber(cost) and tonumber(cost) > 0 then
            current.ok = true
            current.cost = tonumber(cost)
            current.error_code = nil
        else
            current.ok = false
            current.cost = nil
            current.error_code = error_code or ErrorCodes.NAV_MOVE_FAILED

            local ttl = tonumber(self._cfg.path_unreachable_ttl) or 20.0
            self:mark_target_failed(target_ref, current.error_code, ttl)
        end
    end)
end

---@return number
function TargetingService:get_adaptive_radius()
    local base = tonumber(self._cfg.base_radius) or 45.0
    local max_radius = tonumber(self._cfg.max_radius) or 75.0

    -- Expand radius while out of combat and no target to improve XP/h acquisition uptime.
    local in_combat = self._blackboard:get("player.in_combat", false)
    local has_target = self:get_target() ~= nil
    local boost = (not in_combat and not has_target) and 10.0 or 0.0
    return math.min(max_radius, base + boost)
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function can_engage(unit, player)
    local player_can_attack = safe_method(player, "can_attack", unit)
    local unit_can_attack = safe_method(unit, "can_attack", player)
    local player_enemy_with = safe_method(player, "is_enemy_with", unit)
    local unit_enemy_with = safe_method(unit, "is_enemy_with", player)

    -- Different mob families/expansions can report hostility flags inconsistently.
    -- Allow engagement if any reliable attackability/hostility signal is positive.
    if player_can_attack == true
        or unit_can_attack == true
        or player_enemy_with == true
        or unit_enemy_with == true then
        return true
    end

    return false
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function is_targeting_player_or_pet(unit, player)
    local unit_target = unwrap_game_object(safe_method(unit, "get_target"))
    if not unit_target then
        return false
    end

    if unit_target == player then
        return true
    end

    local player_pet = unwrap_game_object(safe_method(player, "get_pet"))
    if player_pet and unit_target == player_pet then
        return true
    end

    return false
end

---@private
---@param unit game_object
---@return boolean
local function is_player_unit(unit)
    return safe_method(unit, "is_player") == true
        or safe_method(unit, "is_player_unit") == true
end

---@private
---@param unit game_object
---@return boolean
local function is_critter_unit(unit)
    if safe_method(unit, "is_critter") == true then
        return true
    end

    local methods = {
        "get_creature_type",
        "get_creature_type_id",
        "get_unit_type",
    }
    for i = 1, #methods do
        local value = safe_method(unit, methods[i])
        if type(value) == "number" and tonumber(value) == CRITTER_CREATURE_TYPE_ID then
            return true
        end
        if type(value) == "string" and string.find(string.lower(value), "critter", 1, true) ~= nil then
            return true
        end
        if type(value) == "table" then
            local id = tonumber(value.id or value.type_id or value.creature_type)
            if id == CRITTER_CREATURE_TYPE_ID then
                return true
            end
            local name = value.name or value.type or value.creature_type_name
            if type(name) == "string" and string.find(string.lower(name), "critter", 1, true) ~= nil then
                return true
            end
        end
    end

    local creature_name = safe_method(unit, "get_creature_type_name")
    if type(creature_name) == "string" and string.find(string.lower(creature_name), "critter", 1, true) ~= nil then
        return true
    end

    return false
end

local is_valid_target

---@private
---@param unit game_object
---@param player game_object
---@param player_team string|nil
---@param cfg table|nil
---@return boolean
local function passes_faction_policy(unit, player, player_team, cfg)
    if not cfg or cfg.only_engage_opposing_faction_if_attacked ~= true then
        return true
    end

    -- Never proactively start fights with players; only defend when they engage us/pet.
    if is_player_unit(unit) then
        return is_targeting_player_or_pet(unit, player)
    end

    local team = FactionResolver.resolve_team(safe_method(unit, "get_faction_id"))
    if team == nil or team == "neutral" then
        return true
    end

    if player_team == nil or player_team == "" then
        return true
    end

    if team ~= player_team then
        return is_targeting_player_or_pet(unit, player)
    end

    return true
end

---@private
---@param objects table
---@param player game_object
---@param player_pos vec3|nil
---@param radius number
---@param player_team string|nil
---@param cfg table|nil
---@param preferred_target game_object|nil
---@return game_object|nil
local function find_defensive_target(objects, player, player_pos, radius, player_team, cfg, preferred_target)
    local preferred = unwrap_game_object(preferred_target)
    if preferred
        and is_visible_unit(objects, preferred)
        and is_valid_target(preferred, player)
        and passes_faction_policy(preferred, player, player_team, cfg)
        and is_targeting_player_or_pet(preferred, player) then
        local preferred_pos = safe_method(preferred, "get_position")
        local preferred_dist = Helpers.distance_3d(player_pos, preferred_pos)
        if preferred_dist <= radius then
            return preferred
        end
    end

    local best_target = nil
    local best_distance = math.huge
    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        if is_valid_target(candidate, player)
            and passes_faction_policy(candidate, player, player_team, cfg)
            and is_targeting_player_or_pet(candidate, player) then
            local candidate_pos = safe_method(candidate, "get_position")
            local dist = Helpers.distance_3d(player_pos, candidate_pos)
            if dist <= radius and dist < best_distance then
                best_distance = dist
                best_target = candidate
            end
        end
    end

    return best_target
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function is_engaged_by_others(unit, player)
    if safe_method(unit, "is_in_combat") ~= true then
        return false
    end

    local unit_target = unwrap_game_object(safe_method(unit, "get_target"))
    if not unit_target then
        -- Out-of-party contested combat; safest default is skip.
        return true
    end

    if unit_target == player then
        return false
    end

    local player_pet = unwrap_game_object(safe_method(player, "get_pet"))
    if player_pet and unit_target == player_pet then
        return false
    end

    return true
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
is_valid_target = function(unit, player)
    if not unit then
        return false
    end
    if safe_method(unit, "is_valid") ~= true then
        return false
    end
    if safe_method(unit, "is_unit") ~= true then
        return false
    end
    if safe_method(unit, "is_dead") == true or safe_method(unit, "is_ghost") == true then
        return false
    end
    if is_critter_unit(unit) then
        return false
    end
    if unit == player then
        return false
    end
    if is_engaged_by_others(unit, player) then
        return false
    end
    if not can_engage(unit, player) then
        return false
    end
    return true
end

---@private
---@param target game_object
---@param player game_object
---@param objects table|nil
---@param cfg table
---@param cache table|nil
---@return number
local function estimate_pull_pressure(target, player, objects, cfg, cache)
    if type(objects) ~= "table" then
        return 0
    end

    local key = safe_unit_guid(target)
    if key <= 0 then
        key = target
    end
    if type(cache) == "table" and cache[key] ~= nil then
        return tonumber(cache[key]) or 0
    end

    local scan_radius = tonumber(cfg and cfg.pull_add_scan_radius) or 10.0
    local target_pos = safe_method(target, "get_position")
    if not target_pos then
        return 0
    end

    local nearby = 0
    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        if candidate
            and candidate ~= target
            and safe_method(candidate, "is_valid") == true
            and safe_method(candidate, "is_dead") ~= true
            and safe_method(candidate, "is_ghost") ~= true
            and is_critter_unit(candidate) ~= true
            and can_engage(candidate, player) then
            local candidate_pos = safe_method(candidate, "get_position")
            local dist = Helpers.distance_3d(target_pos, candidate_pos)
            if dist <= scan_radius then
                nearby = nearby + 1
            end
        end
    end

    if type(cache) == "table" then
        cache[key] = nearby
    end
    return nearby
end

---@private
---@param target game_object
---@param score number
---@param nearby_combat_count number
---@param reason string|nil
function TargetingService:_commit_target(target, score, nearby_combat_count, reason)
    local changed = self._current_target ~= target
    self._current_target = target
    self._blackboard:set("combat.target", target)
    self._blackboard:set("combat.enemy_count", math.max(1, nearby_combat_count))
    if changed then
        self._event_bus:emit(Events.TARGET_ACQUIRED, {
            timestamp = (core and core.time and core.time()) or 0,
            target_name = tostring(safe_method(target, "get_name") or "unknown"),
            target_level = tonumber(safe_method(target, "get_level")) or 0,
            score = score,
            reason = reason,
        })
    end
end

---@param target game_object
---@param opts? table
---@return number
---@return table
function TargetingService:score_target(target, opts)
    local player = self._blackboard:get("player.object")
    if not player then
        return -math.huge, {}
    end

    local player_pos = self._blackboard:get("player.position")
    local target_pos = safe_method(target, "get_position")
    if not target_pos then
        return -math.huge, {}
    end
    if type(opts) == "table" and opts.player_pos then
        player_pos = opts.player_pos
    end

    local now = type(opts) == "table" and tonumber(opts.now) or now_seconds()
    local distance = Helpers.distance_3d(player_pos, target_pos)
    local path_distance = distance
    local path_info = self:_path_cost_snapshot(target, now)
    if type(path_info) == "table" and path_info.ok == true and tonumber(path_info.cost) then
        path_distance = math.max(distance, tonumber(path_info.cost) or distance)
    end

    local target_hp = math.max(1, tonumber(safe_method(target, "get_health")) or 1)
    local target_max_hp = math.max(1, tonumber(safe_method(target, "get_max_health")) or target_hp)
    local hp_ratio = target_hp / target_max_hp

    local player_level = tonumber(safe_method(player, "get_level")) or 1
    local target_level = tonumber(safe_method(target, "get_level")) or player_level
    local level_delta = target_level - player_level

    local classification = tonumber(safe_method(target, "get_classification")) or 0
    local elite_risk = (classification == 1 or classification == 2 or classification == 3) and 1.0 or 0.0

    local weights = self._cfg.score_weights or {}
    local w_kill = tonumber(weights.kill_speed) or 0.40
    local w_loot = tonumber(weights.loot_value) or 0.20
    local w_travel = tonumber(weights.travel_cost) or 0.30
    local w_risk = tonumber(weights.risk) or 0.10

    local kill_speed = 1.0 - hp_ratio
    local loot_value = (target_level >= player_level) and 1.0 or 0.6
    local travel_cost = path_distance / math.max(1.0, tonumber(self._cfg.max_radius) or 75.0)
    local risk = math.max(0, level_delta * 0.2) + elite_risk

    local blacklisted, memory_entry = self:_is_target_blacklisted(target, now)
    if blacklisted == true then
        risk = risk + 2.0
    else
        local failures = tonumber(memory_entry and memory_entry.failures) or 0
        local failure_penalty = tonumber(self._cfg.memory_failure_risk_penalty) or 0.12
        risk = risk + math.min(1.0, failures * failure_penalty)
    end

    local pull_pressure = 0
    if type(opts) == "table" and type(opts.objects) == "table" then
        pull_pressure = estimate_pull_pressure(
            target,
            player,
            opts.objects,
            self._cfg,
            opts.pull_pressure_cache
        )
    end
    local add_risk_weight = tonumber(self._cfg.pull_add_risk_weight) or 0.20
    risk = risk + (math.max(0, pull_pressure - 1) * add_risk_weight)

    local unreachable_penalty = 0
    if type(path_info) == "table" and path_info.ok == false then
        unreachable_penalty = tonumber(self._cfg.path_unreachable_risk_penalty) or 1.0
        risk = risk + unreachable_penalty
    end

    local score = (kill_speed * w_kill) + (loot_value * w_loot) - (travel_cost * w_travel) - (risk * w_risk)

    self._event_bus:emit(Events.TARGET_SCORE_DEBUG, {
        target_id = tonumber(safe_method(target, "get_npc_id")) or 0,
        score = score,
        kill_speed = kill_speed,
        loot_value = loot_value,
        travel_cost = travel_cost,
        path_distance = path_distance,
        risk = risk,
        pull_pressure = pull_pressure,
        unreachable_penalty = unreachable_penalty,
    })

    return score, {
        risk = risk,
        pull_pressure = pull_pressure,
        distance = distance,
        path_distance = path_distance,
    }
end

---@return game_object|nil
---@return string|nil
function TargetingService:acquire_target()
    local player = unwrap_game_object(self._blackboard:get("player.object"))
    if not player or safe_method(player, "is_valid") ~= true then
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end
    local now = now_seconds()
    self:_prune_target_memory(now)
    local player_team = FactionResolver.resolve_team(self._blackboard:get("player.faction_team", ""))

    local objects = {}
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok_objects, value = pcall(core.object_manager.get_visible_objects)
        if ok_objects and type(value) == "table" then
            objects = value
        end
    end
    local radius = self:get_adaptive_radius()
    local player_pos = self._blackboard:get("player.position")

    local defensive_target = find_defensive_target(
        objects,
        player,
        player_pos,
        radius,
        player_team,
        self._cfg,
        self._current_target
    )

    local best_target = nil
    local best_score = -math.huge
    local nearby_combat_count = 0
    local pull_pressure_cache = {}
    local pull_risk_budget = tonumber(self._cfg.pull_risk_budget) or 0

    if defensive_target then
        best_target = defensive_target
        self:_warm_path_cost(defensive_target, player_pos, now)
        best_score = self:score_target(defensive_target, {
            now = now,
            objects = objects,
            player_pos = player_pos,
            pull_pressure_cache = pull_pressure_cache,
        })
    end

    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        if is_valid_target(candidate, player)
            and passes_faction_policy(candidate, player, player_team, self._cfg) then
            self:_warm_path_cost(candidate, player_pos, now)
            local blacklisted = self:_is_target_blacklisted(candidate, now)
            if blacklisted ~= true then
                local candidate_pos = safe_method(candidate, "get_position")
                local dist = Helpers.distance_3d(player_pos, candidate_pos)
                if dist <= radius then
                    if dist <= 10.0 then
                        nearby_combat_count = nearby_combat_count + 1
                    end
                    if not defensive_target then
                        local score, meta = self:score_target(candidate, {
                            now = now,
                            objects = objects,
                            player_pos = player_pos,
                            pull_pressure_cache = pull_pressure_cache,
                        })
                        local risk = tonumber(meta and meta.risk) or 0
                        local over_budget = pull_risk_budget > 0 and risk > pull_risk_budget
                        if not over_budget and score > best_score then
                            best_score = score
                            best_target = candidate
                        end
                    end
                end
            end
        end
    end

    if not best_target then
        self._current_target = nil
        self._blackboard:clear("combat.target")
        self._blackboard:set("combat.enemy_count", 0)
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end

    self:_commit_target(
        best_target,
        best_score,
        math.max(1, nearby_combat_count),
        defensive_target and "defensive" or "grind"
    )

    return best_target, nil
end

---@param preferred_target? game_object
---@return game_object|nil
---@return string|nil
function TargetingService:acquire_defensive_target(preferred_target)
    local player = unwrap_game_object(self._blackboard:get("player.object"))
    if not player or safe_method(player, "is_valid") ~= true then
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end

    local objects = {}
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok_objects, value = pcall(core.object_manager.get_visible_objects)
        if ok_objects and type(value) == "table" then
            objects = value
        end
    end

    local radius = tonumber(self._cfg.defensive_retarget_radius) or tonumber(self._cfg.max_radius) or 75.0
    local player_pos = self._blackboard:get("player.position")
    local player_team = FactionResolver.resolve_team(self._blackboard:get("player.faction_team", ""))
    local target = find_defensive_target(
        objects,
        player,
        player_pos,
        radius,
        player_team,
        self._cfg,
        preferred_target or self._current_target
    )
    if not target then
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end

    self:_commit_target(target, self:score_target(target), 1, "defensive_retarget")
    return target, nil
end

---@return game_object|nil
function TargetingService:get_target()
    if self._current_target and safe_method(self._current_target, "is_valid") == true then
        if safe_method(self._current_target, "is_dead") ~= true then
            return self._current_target
        end
    end
    return nil
end

function TargetingService:clear_target(reason)
    if self._current_target then
        self._event_bus:emit(Events.TARGET_LOST, {
            timestamp = (core and core.time and core.time()) or 0,
            reason = reason,
        })
    end
    self._current_target = nil
    self._blackboard:clear("combat.target")
    self._blackboard:set("combat.enemy_count", 0)
end

function TargetingService:update()
    local target = self:get_target()
    if target then
        self._blackboard:set("combat.target", target)
        local current_count = tonumber(self._blackboard:get("combat.enemy_count", 0)) or 0
        if current_count <= 0 then
            self._blackboard:set("combat.enemy_count", 1)
        end
    end
end

return TargetingService
