local BT = require("ai/BehaviorTree")
local BTStatus = BT.Status
local Helpers = require("lib/Helpers")
local FactionResolver = require("lib/FactionResolver")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local get_now = require("lib/TimeHelper").get_now
local UnitQueries = require("lib/UnitQueries")
local safe_method = UnitQueries.safe_method
local unwrap_game_object = UnitQueries.unwrap_game_object
local is_same_unit = UnitQueries.is_same_unit

local CRITTER_CREATURE_TYPE_ID = 8

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
---@param objects table|nil
---@param guid number
---@return game_object|nil
local function find_visible_unit_by_guid(objects, guid)
    local wanted = tonumber(guid) or 0
    if wanted <= 0 or type(objects) ~= "table" then
        return nil
    end

    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        local candidate_guid = tonumber(safe_method(candidate, "get_guid"))
            or tonumber(safe_method(candidate, "get_object_guid"))
            or 0
        if candidate_guid == wanted then
            return candidate
        end
    end

    return nil
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
function TargetingService:new(event_bus, blackboard, cfg, navigation, logger)
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
    -- Sub-frame cache for get_visible_objects(). Avoids 4 full scans per update tick.
    -- 50 ms TTL comfortably covers one game frame at 20+ fps while staying fresh enough
    -- that threat counts and target availability are never stale.
    o._visible_cache = { at = 0, objects = {} }
    o._log = logger or { debug=function()end, info=function()end, warn=function()end, error=function()end }
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

    -- Sort by retry_until ascending: evict entries closest to expiry first.
    -- Preserves the longest-remaining blacklist entries (most valuable to keep).
    local sorted = {}
    for key, entry in pairs(self._target_memory) do
        sorted[#sorted + 1] = { key = key, retry_until = tonumber(entry.retry_until) or 0 }
    end
    table.sort(sorted, function(a, b) return a.retry_until < b.retry_until end)
    local overflow = active_count - max_entries
    for i = 1, #sorted do
        self._target_memory[sorted[i].key] = nil
        overflow = overflow - 1
        if overflow <= 0 then break end
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
    now = tonumber(now) or get_now()
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
    self._log:warn("target failed: %s reason=%s", tostring(safe_method(target, "get_name") or "unknown"), tostring(reason or "-"))

    local now = get_now()
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
    local blocked = self:_is_target_blacklisted(target, get_now())
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

    -- Sort by updated_at ascending: evict oldest entries first.
    -- Preserves the most recently computed path costs (freshest data).
    local sorted = {}
    for key, entry in pairs(self._path_cost_cache) do
        sorted[#sorted + 1] = { key = key, updated_at = tonumber(entry and entry.updated_at) or 0 }
    end
    table.sort(sorted, function(a, b) return a.updated_at < b.updated_at end)
    local overflow = active - max_entries
    for i = 1, #sorted do
        self._path_cost_cache[sorted[i].key] = nil
        overflow = overflow - 1
        if overflow <= 0 then break end
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
        current.updated_at = get_now()
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
---@param player game_object|nil
---@return string|nil
function TargetingService:_resolve_player_team(player)
    local team = FactionResolver.resolve_team(self._blackboard:get("player.faction_team"))
    if team ~= nil and team ~= "" then
        return team
    end

    team = FactionResolver.resolve_team(self._blackboard:get("player.faction_id"))
    if team ~= nil and team ~= "" then
        return team
    end

    team = FactionResolver.resolve_team(safe_method(player, "get_faction_id"))
    if team ~= nil and team ~= "" then
        return team
    end

    return nil
end

---@private
---@return number
---@return table
function TargetingService:_resolve_pull_risk_budget()
    local base_budget = tonumber(self._cfg.pull_risk_budget) or 0
    if base_budget <= 0 then
        return 0, {
            base = base_budget,
            effective = 0,
            scale = 0,
            deaths_per_hour = tonumber(self._blackboard:get("telemetry.rates.deaths_per_hour", 0)) or 0,
        }
    end

    local deaths_per_hour = tonumber(self._blackboard:get("telemetry.rates.deaths_per_hour", 0)) or 0
    if deaths_per_hour < 0 then
        deaths_per_hour = 0
    end

    local low = tonumber(self._cfg.pull_risk_deaths_per_hour_low) or 0.20
    local high = tonumber(self._cfg.pull_risk_deaths_per_hour_high) or 1.50
    if high <= low then
        high = low + 0.01
    end

    local min_scale = tonumber(self._cfg.pull_risk_budget_min_scale) or 0.45
    local max_scale = tonumber(self._cfg.pull_risk_budget_max_scale) or 1.00
    min_scale = Helpers.clamp(min_scale, 0.05, 2.00)
    max_scale = Helpers.clamp(max_scale, min_scale, 2.00)

    local t = Helpers.clamp((deaths_per_hour - low) / (high - low), 0.0, 1.0)
    local scale = max_scale + ((min_scale - max_scale) * t)
    local effective = base_budget * scale

    local min_absolute = tonumber(self._cfg.pull_risk_budget_min_absolute) or 0
    if min_absolute > 0 then
        effective = math.max(min_absolute, effective)
    end

    return effective, {
        base = base_budget,
        effective = effective,
        scale = scale,
        deaths_per_hour = deaths_per_hour,
    }
end

---@private
---@param unit game_object
---@param player game_object
---@return boolean
local function can_engage(unit, player)
    local player_can_attack = safe_method(player, "can_attack", unit)

    -- The player must be able to attack the target. Without this, the bot
    -- would chase invulnerable NPCs (guard post turrets, world triggers)
    -- that it can never damage. Defensive reactions (flee, retarget) are
    -- handled separately by CombatService when the bot is being attacked.
    if player_can_attack == true then
        return true
    end

    -- Fallback: mutual is_enemy_with when can_attack is unreliable.
    local player_enemy_with = safe_method(player, "is_enemy_with", unit)
    local unit_enemy_with = safe_method(unit, "is_enemy_with", player)
    if player_enemy_with == true and unit_enemy_with == true then
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

    if is_same_unit(unit_target, player) then
        return true
    end

    local player_pet = unwrap_game_object(safe_method(player, "get_pet"))
    if player_pet and is_same_unit(unit_target, player_pet) then
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
local function is_pet_like_unit(unit)
    return safe_method(unit, "is_pet") == true
        or safe_method(unit, "is_player_pet") == true
        or safe_method(unit, "is_guardian") == true
        or safe_method(unit, "is_summon") == true
end

---@private
---@param unit game_object
---@param objects table|nil
---@return game_object|nil
---@return number
local function resolve_unit_owner(unit, objects)
    if not unit then
        return nil, 0
    end

    local owner = nil
    local owner_guid = 0
    local owner_methods = {
        "get_owner",
        "get_owner_unit",
        "get_master",
        "get_master_unit",
        "get_charmer",
        "get_charmer_unit",
        "get_pet_owner",
    }
    for i = 1, #owner_methods do
        local value = unwrap_game_object(safe_method(unit, owner_methods[i]))
        if type(value) == "table" then
            owner = value
            owner_guid = safe_unit_guid(owner)
            break
        end
        local numeric = tonumber(value) or 0
        if numeric > 0 then
            owner_guid = numeric
            break
        end
    end

    if owner_guid <= 0 then
        local owner_guid_methods = {
            "get_owner_guid",
            "get_master_guid",
            "get_charmer_guid",
            "get_pet_owner_guid",
        }
        for i = 1, #owner_guid_methods do
            local numeric = tonumber(safe_method(unit, owner_guid_methods[i])) or 0
            if numeric > 0 then
                owner_guid = numeric
                break
            end
        end
    end

    if not owner and owner_guid > 0 then
        owner = find_visible_unit_by_guid(objects, owner_guid)
    end

    return owner, owner_guid
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
---@param objects table|nil
---@return boolean
local function passes_faction_policy(unit, player, player_team, cfg, objects)
    if not cfg or cfg.only_engage_opposing_faction_if_attacked ~= true then
        return true
    end

    local owner, owner_guid = resolve_unit_owner(unit, objects)
    if owner and is_player_unit(owner) then
        local owner_team = FactionResolver.resolve_team(safe_method(owner, "get_faction_team"))
            or FactionResolver.resolve_team(safe_method(owner, "get_faction_id"))
        if owner_team == nil or player_team == nil or owner_team ~= player_team then
            return is_targeting_player_or_pet(unit, player)
        end
        return false
    end

    if owner_guid > 0 and is_pet_like_unit(unit) then
        local player_guid = safe_unit_guid(player)
        local player_pet = unwrap_game_object(safe_method(player, "get_pet"))
        local player_pet_guid = safe_unit_guid(player_pet)
        if owner_guid ~= player_guid and owner_guid ~= player_pet_guid then
            return is_targeting_player_or_pet(unit, player)
        end
        return false
    end

    -- Pet-like unit with no resolved owner (owner out of range / not visible).
    -- Conservatively treat as enemy-controlled; only engage defensively.
    if is_pet_like_unit(unit) then
        return is_targeting_player_or_pet(unit, player)
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
        and passes_faction_policy(preferred, player, player_team, cfg, objects)
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
            and passes_faction_policy(candidate, player, player_team, cfg, objects)
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

    if is_same_unit(unit_target, player) then
        return false
    end

    local player_pet = unwrap_game_object(safe_method(player, "get_pet"))
    if player_pet and is_same_unit(unit_target, player_pet) then
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
    if safe_method(unit, "is_basic_object") == true then
        return false
    end
    if safe_method(unit, "is_dead") == true or safe_method(unit, "is_ghost") == true then
        return false
    end
    if is_critter_unit(unit) then
        return false
    end
    if is_same_unit(unit, player) then
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
            and not is_same_unit(candidate, target)
            and safe_method(candidate, "is_valid") == true
            and safe_method(candidate, "is_unit") == true
            and safe_method(candidate, "is_basic_object") ~= true
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
    local changed = not is_same_unit(self._current_target, target)
    self._current_target = target
    self._blackboard:set("combat.target", target)
    self._blackboard:set("combat.enemy_count", math.max(1, nearby_combat_count))
    if changed then
        self._log:info("target acquired: %s score=%.2f reason=%s",
            tostring(safe_method(target, "get_name") or "unknown"),
            tonumber(score) or 0,
            tostring(reason or "-"))
        self._event_bus:emit(Events.TARGET_ACQUIRED, {
            timestamp = get_now(),
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

    local now = type(opts) == "table" and tonumber(opts.now) or get_now()
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
    local w_travel = tonumber(weights.travel_cost) or 0.45
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

    -- Cluster proximity bonus: when the active tactic prefers AoE clusters,
    -- boost score for targets near other candidates.
    local cluster_bonus = 0
    local target_cfg = self._blackboard:get("tactical.target_config")
    if type(target_cfg) == "table" and target_cfg.prefer_clusters == true
        and type(opts) == "table" and type(opts.objects) == "table" then
        local cluster_radius = tonumber(target_cfg.cluster_radius) or 15
        local cluster_weight = tonumber(target_cfg.cluster_weight) or 0.15
        local nearby_count = 0
        for ci = 1, #opts.objects do
            local other = unwrap_game_object(opts.objects[ci])
            if other and not is_same_unit(other, target)
                and safe_method(other, "is_valid") == true
                and safe_method(other, "is_unit") == true
                and safe_method(other, "is_dead") ~= true then
                local other_pos = safe_method(other, "get_position")
                local cdist = Helpers.distance_3d(target_pos, other_pos)
                if cdist and cdist <= cluster_radius then
                    nearby_count = nearby_count + 1
                end
            end
        end
        cluster_bonus = nearby_count * cluster_weight
        score = score + cluster_bonus
    end

    local pull_risk_budget = tonumber(type(opts) == "table" and opts.pull_risk_budget or nil) or 0
    local pull_risk_scale = tonumber(type(opts) == "table" and opts.pull_risk_scale or nil) or 0
    local pull_risk_deaths_per_hour = tonumber(type(opts) == "table" and opts.pull_risk_deaths_per_hour or nil) or 0

    local suppress_debug = type(opts) == "table" and opts.suppress_debug == true
    if not suppress_debug then
        self._event_bus:emit(Events.TARGET_SCORE_DEBUG, {
            target_id = tonumber(safe_method(target, "get_npc_id")) or 0,
            score = score,
            kill_speed = kill_speed,
            loot_value = loot_value,
            travel_cost = travel_cost,
            path_distance = path_distance,
            risk = risk,
            pull_risk_budget = pull_risk_budget,
            pull_risk_scale = pull_risk_scale,
            pull_risk_deaths_per_hour = pull_risk_deaths_per_hour,
            pull_pressure = pull_pressure,
            unreachable_penalty = unreachable_penalty,
            cluster_bonus = cluster_bonus,
        })
    end

    return score, {
        risk = risk,
        pull_pressure = pull_pressure,
        distance = distance,
        path_distance = path_distance,
        cluster_bonus = cluster_bonus,
    }
end

---@private
---@return table
function TargetingService:_get_visible_objects()
    local now = get_now()
    if (now - self._visible_cache.at) < 0.05 then
        return self._visible_cache.objects
    end
    local objects = {}
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok_objects, value = pcall(core.object_manager.get_visible_objects)
        if ok_objects and type(value) == "table" then
            objects = value
        end
    end
    self._visible_cache.at = now
    self._visible_cache.objects = objects
    return objects
end

---@private
---@param candidates table[]
---@return table[]
function TargetingService:_apply_profile_filters(candidates)
    local filters = self._blackboard:get("profile.target_filters")
    if not filters then return candidates end

    local level_min = tonumber(filters.level_min) or 0
    local level_max = tonumber(filters.level_max) or 999
    local creature_types = filters.creature_types
    local npc_blacklist = filters.npc_blacklist
    local npc_whitelist = filters.npc_whitelist
    local has_whitelist = type(npc_whitelist) == "table" and #npc_whitelist > 0
    local has_creature_filter = type(creature_types) == "table" and #creature_types > 0

    local result = {}
    for i = 1, #candidates do
        local entry = candidates[i]
        local target = entry.target
        local dominated = false

        local level = tonumber(safe_method(target, "get_level")) or 0
        if level < level_min or level > level_max then
            dominated = true
        end

        if not dominated and has_creature_filter then
            local ct = tostring(safe_method(target, "get_creature_type_name") or ""):lower()
            local match = false
            for j = 1, #creature_types do
                if ct == tostring(creature_types[j]):lower() then
                    match = true
                    break
                end
            end
            if not match then dominated = true end
        end

        local npc_id = tonumber(safe_method(target, "get_npc_id")) or 0

        if not dominated and has_whitelist then
            local on_list = false
            for j = 1, #npc_whitelist do
                if npc_id == tonumber(npc_whitelist[j]) then
                    on_list = true
                    break
                end
            end
            if not on_list then dominated = true end
        end

        if not dominated and type(npc_blacklist) == "table" then
            for j = 1, #npc_blacklist do
                if npc_id == tonumber(npc_blacklist[j]) then
                    dominated = true
                    break
                end
            end
        end

        if not dominated then
            result[#result + 1] = entry
        end
    end

    return result
end

---@param opts? table
---@return table
function TargetingService:get_visible_candidates(opts)
    opts = opts or {}

    local player = unwrap_game_object(self._blackboard:get("player.object"))
    if not player or safe_method(player, "is_valid") ~= true then
        return {}
    end

    local now = type(opts) == "table" and tonumber(opts.now) or get_now()
    self:_prune_target_memory(now)
    self:_prune_path_cost_cache(now)

    local player_team = self:_resolve_player_team(player)
    local player_pos = opts.player_pos
    if type(player_pos) ~= "table" then
        player_pos = self._blackboard:get("player.position")
    end
    if type(player_pos) ~= "table" then
        return {}
    end

    local max_distance = tonumber(opts.max_distance) or tonumber(self._cfg.max_radius) or 75.0
    local include_blacklisted = opts.include_blacklisted == true
    local include_engaged = opts.include_engaged == true

    local objects = self:_get_visible_objects()
    local pull_pressure_cache = {}
    local pull_risk_budget, pull_risk_meta = self:_resolve_pull_risk_budget()
    local candidates = {}

    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        local valid = is_valid_target(candidate, player)
        if not valid and include_engaged and candidate and safe_method(candidate, "is_valid") == true then
            valid = safe_method(candidate, "is_unit") == true
                and safe_method(candidate, "is_basic_object") ~= true
                and safe_method(candidate, "is_dead") ~= true
                and safe_method(candidate, "is_ghost") ~= true
                and can_engage(candidate, player) == true
                and is_critter_unit(candidate) ~= true
                and not is_same_unit(candidate, player)
        end

        if valid and passes_faction_policy(candidate, player, player_team, self._cfg, objects) then
            local candidate_pos = safe_method(candidate, "get_position")
            local dist = Helpers.distance_3d(player_pos, candidate_pos)
            if dist <= max_distance then
                self:_warm_path_cost(candidate, player_pos, now)
                local blacklisted = self:_is_target_blacklisted(candidate, now)
                if include_blacklisted or blacklisted ~= true then
                    local score, meta = self:score_target(candidate, {
                        now = now,
                        objects = objects,
                        player_pos = player_pos,
                        pull_pressure_cache = pull_pressure_cache,
                        pull_risk_budget = pull_risk_budget,
                        pull_risk_scale = pull_risk_meta and pull_risk_meta.scale,
                        pull_risk_deaths_per_hour = pull_risk_meta and pull_risk_meta.deaths_per_hour,
                        suppress_debug = true,
                    })

                    candidates[#candidates + 1] = {
                        target = candidate,
                        distance = dist,
                        score = tonumber(score) or 0,
                        risk = tonumber(meta and meta.risk) or 0,
                        pull_pressure = tonumber(meta and meta.pull_pressure) or 0,
                        defensive = is_targeting_player_or_pet(candidate, player),
                        blacklisted = blacklisted == true,
                    }
                end
            end
        end
    end

    -- Apply profile target filters if active
    candidates = self:_apply_profile_filters(candidates)

    table.sort(candidates, function(a, b)
        local a_def = a and a.defensive == true
        local b_def = b and b.defensive == true
        if a_def ~= b_def then
            return a_def
        end

        local a_score = tonumber(a and a.score) or -math.huge
        local b_score = tonumber(b and b.score) or -math.huge
        if a_score == b_score then
            local a_dist = tonumber(a and a.distance) or math.huge
            local b_dist = tonumber(b and b.distance) or math.huge
            return a_dist < b_dist
        end

        return a_score > b_score
    end)

    return candidates
end

---@return table[] Array of visible hostile game_object references for PackTracker
function TargetingService:get_visible_hostiles()
    local player = unwrap_game_object(self._blackboard:get("player.object"))
    if not player or safe_method(player, "is_valid") ~= true then
        return {}
    end

    local objects = self:_get_visible_objects()
    local hostiles = {}

    for i = 1, #objects do
        local unit = unwrap_game_object(objects[i])
        if is_valid_target(unit, player) then
            hostiles[#hostiles + 1] = unit
        end
    end

    return hostiles
end

---@return game_object|nil
---@return string|nil
function TargetingService:acquire_target()
    local player = unwrap_game_object(self._blackboard:get("player.object"))
    if not player or safe_method(player, "is_valid") ~= true then
        return nil, ErrorCodes.TARGET_NOT_FOUND
    end
    local now = get_now()
    self:_prune_target_memory(now)
    local player_team = self:_resolve_player_team(player)

    local objects = self:_get_visible_objects()
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
    local pull_risk_budget, pull_risk_meta = self:_resolve_pull_risk_budget()
    self._blackboard:set("targeting.pull_risk_budget.base", tonumber(pull_risk_meta.base) or 0)
    self._blackboard:set("targeting.pull_risk_budget.scale", tonumber(pull_risk_meta.scale) or 0)
    self._blackboard:set("targeting.pull_risk_budget.effective", tonumber(pull_risk_meta.effective) or 0)
    self._blackboard:set("targeting.pull_risk_budget.deaths_per_hour", tonumber(pull_risk_meta.deaths_per_hour) or 0)

    if defensive_target then
        best_target = defensive_target
        self:_warm_path_cost(defensive_target, player_pos, now)
        best_score = self:score_target(defensive_target, {
            now = now,
            objects = objects,
            player_pos = player_pos,
            pull_pressure_cache = pull_pressure_cache,
            pull_risk_budget = pull_risk_budget,
            pull_risk_scale = pull_risk_meta and pull_risk_meta.scale,
            pull_risk_deaths_per_hour = pull_risk_meta and pull_risk_meta.deaths_per_hour,
        })
    end

    for i = 1, #objects do
        local candidate = unwrap_game_object(objects[i])
        if is_valid_target(candidate, player)
            and passes_faction_policy(candidate, player, player_team, self._cfg, objects) then
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
                            pull_risk_budget = pull_risk_budget,
                            pull_risk_scale = pull_risk_meta and pull_risk_meta.scale,
                            pull_risk_deaths_per_hour = pull_risk_meta and pull_risk_meta.deaths_per_hour,
                        })
                        -- Stickiness: strongly prefer current target to prevent
                        -- flip-flopping between similarly-scored mobs. A new target
                        -- must score significantly higher to override the current one.
                        if self._current_target and is_same_unit(candidate, self._current_target) then
                            local sticky_bonus = tonumber(self._cfg.target_sticky_bonus) or 0.25
                            score = score + sticky_bonus
                        end
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

    local objects = self:_get_visible_objects()

    local radius = tonumber(self._cfg.defensive_retarget_radius) or tonumber(self._cfg.max_radius) or 75.0
    local player_pos = self._blackboard:get("player.position")
    local player_team = self:_resolve_player_team(player)
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
            -- Verify target is still engageable (prevents stale unattackable
            -- targets like guard posts from blocking the entire BT forever).
            local player = unwrap_game_object(self._blackboard:get("player.object"))
            if player and not can_engage(self._current_target, player) then
                self:clear_target("not_engageable")
                return nil
            end
            return self._current_target
        end
    end
    return nil
end

function TargetingService:clear_target(reason)
    if self._current_target then
        self._log:info("target cleared: reason=%s", tostring(reason or "-"))
        self._event_bus:emit(Events.TARGET_LOST, {
            timestamp = get_now(),
            reason = reason,
        })
    end
    self._current_target = nil
    self._blackboard:clear("combat.target")
    self._blackboard:set("combat.enemy_count", 0)
end

function TargetingService:update()
    local target = self:get_target()
    -- When current target is dead/invalid but player is in combat, proactively
    -- acquire a replacement so the combat BT has a valid target this same tick.
    -- Without this, a 1-2 frame gap lets exploration issue move_to(waypoint) in
    -- the opposite direction before combat re-acquires.
    -- Guard: skip re-acquisition during the post-kill loot window so we don't
    -- immediately pull a new mob while the corpse is waiting to be looted.
    local loot_pending = self._blackboard:get("loot.pending_target") ~= nil
    if not target and self._blackboard:get("player.in_combat", false) and not loot_pending then
        local ok, new_target = pcall(self.acquire_target, self)
        if ok and new_target then
            target = new_target
        end
    end
    if target then
        self._blackboard:set("combat.target", target)
        -- Keep combat.enemy_count current with a live attacker scan every frame so
        -- FleeService sees accurate multi-mob state even when the TargetingService BT
        -- node is bypassed (CombatService holds the ReactiveSelector during combat).
        local player = unwrap_game_object(self._blackboard:get("player.object"))
        if player and safe_method(player, "is_valid") == true then
            local objects = self:_get_visible_objects()
            local attackers = 0
            for i = 1, #objects do
                local unit = unwrap_game_object(objects[i])
                if unit and safe_method(unit, "is_valid") == true
                    and safe_method(unit, "is_unit") == true
                    and safe_method(unit, "is_basic_object") ~= true
                    and safe_method(unit, "is_dead") ~= true then
                    local unit_target = unwrap_game_object(safe_method(unit, "get_target"))
                    if is_same_unit(unit_target, player) then
                        attackers = attackers + 1
                    end
                end
            end
            self._blackboard:set("combat.enemy_count", math.max(1, attackers))
        else
            local current_count = tonumber(self._blackboard:get("combat.enemy_count", 0)) or 0
            if current_count <= 0 then
                self._blackboard:set("combat.enemy_count", 1)
            end
        end
    end
end

--- Build BT node for target acquisition (used by GrindService).
---@return table BT node
function TargetingService:build()
    local bb = self._blackboard

    return BT.Sequence:new("find_target", {
        -- Gate: no valid target currently
        BT.Condition:new("no_target", function()
            local target = bb:get("combat.target")
            if not target then return true end
            local ok, hp = pcall(function() return target:get_health() end)
            if not ok or not hp or hp <= 0 then return true end
            return false
        end),

        -- Scan and select
        BT.Action:new("scan_score_select", function()
            local ok, target = pcall(function()
                return self:acquire_target()
            end)

            if ok and target then
                bb:set("combat.target", target)
                return BTStatus.SUCCESS
            end

            return BTStatus.FAILURE
        end),
    })
end

return TargetingService
