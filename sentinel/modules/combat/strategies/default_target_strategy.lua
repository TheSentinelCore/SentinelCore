local DefaultTargetStrategy = {}
DefaultTargetStrategy.__index = DefaultTargetStrategy

local AuraCatalog = require("modules/combat/aura_catalog")
local Events = require("modules/combat/events")
local SpellHelper = require("shared/spell_helper")
local Geometry = require("core/geometry")

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function num(value)
    return tonumber(value) or 0
end

-- F5: delegate to Geometry.distance. Unmeasurable input now returns math.huge
-- (was a private 99999 sentinel), matching every other distance helper.
local function distance(a, b)
    return Geometry.distance(a, b)
end

local function same_guid(a, b)
    local ok_a, guid_a = safe_call(a, "get_guid")
    local ok_b, guid_b = safe_call(b, "get_guid")
    return ok_a and ok_b and tostring(guid_a) == tostring(guid_b)
end

local function is_hostile(player, unit)
    local ok_enemy, enemy = safe_call(unit, "is_enemy_with", player)
    if ok_enemy and enemy == true then return true end
    ok_enemy, enemy = safe_call(player, "is_enemy_with", unit)
    if ok_enemy and enemy == true then return true end
    local ok_attack, can_attack = safe_call(player, "can_attack", unit)
    if ok_attack and can_attack == true then return true end
    return false
end

function DefaultTargetStrategy:new(event_bus, blackboard, izi_bridge, unit_helper)
    local o = setmetatable({}, DefaultTargetStrategy)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._izi_bridge = izi_bridge
    o._unit_helper = unit_helper
    return o
end

function DefaultTargetStrategy:is_valid_enemy(unit, opts)
    opts = opts or {}
    local player = self._blackboard:get("player.object")
    if not player or not unit then return false end
    local ok_dead, dead = safe_call(unit, "is_dead")
    if ok_dead and dead == true then return false end

    -- Check if it's a player unit - only allow for require_player (PvP) mode
    local ok_is_player, is_player = safe_call(unit, "is_player")
    if ok_is_player and is_player == true then
        return opts.require_player == true
    end

    -- Default: accept hostile (red) mobs only
    return is_hostile(player, unit)
end

function DefaultTargetStrategy:_enemy_list(player_pos, opts)
    local scan_radius = 55.0

    if not self._unit_helper or type(self._unit_helper.get_enemy_list_around) ~= "function" or type(player_pos) ~= "table" then
        return self:_visible_enemy_list(player_pos, scan_radius, opts)
    end
    local ok, units = pcall(self._unit_helper.get_enemy_list_around, self._unit_helper, player_pos, scan_radius, true, false, true, false)
    if (not ok) or type(units) ~= "table" then
        ok, units = pcall(self._unit_helper.get_enemy_list_around, self._unit_helper, player_pos, scan_radius, true, false)
    end
    if ok and type(units) == "table" then
        local filtered = {}
        for _, candidate in ipairs(units) do
            if self:is_valid_enemy(candidate, opts) then
                filtered[#filtered + 1] = candidate
            end
        end
        if #filtered > 0 then return filtered end
    end
    return self:_visible_enemy_list(player_pos, scan_radius, opts)
end

function DefaultTargetStrategy:_visible_enemy_list(player_pos, scan_radius, opts)
    local player = self._blackboard:get("player.object")
    if not player or not core or not core.object_manager or type(core.object_manager.get_visible_objects) ~= "function" then
        return {}
    end
    local ok, visible = pcall(core.object_manager.get_visible_objects)
    if not ok or type(visible) ~= "table" then return {} end
    local results = {}
    for _, candidate in ipairs(visible) do
        if candidate and self:is_valid_enemy(candidate, opts or { require_player = true }) then
            local ok_dead, dead = safe_call(candidate, "is_dead")
            if not ok_dead or dead ~= true then
                local ok_pos, pos = safe_call(candidate, "get_position")
                if ok_pos and type(pos) == "table" and distance(player_pos, pos) <= (scan_radius or 55.0) then
                    results[#results + 1] = candidate
                end
            end
        end
    end
    return results
end

function DefaultTargetStrategy:_score(player, candidate, current_target, leash_center, leash_radius)
    local ok_candidate_pos, candidate_pos = safe_call(candidate, "get_position")
    local ok_player_pos, player_pos = safe_call(player, "get_position")
    local score = 0
    local dist = math.huge
    if ok_player_pos and ok_candidate_pos and type(player_pos) == "table" and type(candidate_pos) == "table" then
        dist = distance(player_pos, candidate_pos)
    end

    if self._unit_helper and type(self._unit_helper.is_healer) == "function" then
        local ok_healer, healer = pcall(self._unit_helper.is_healer, self._unit_helper, candidate)
        if ok_healer and healer == true then score = score + 40 end
    end

    local ok_target, candidate_target = safe_call(candidate, "get_target")
    if ok_target and candidate_target and same_guid(candidate_target, player) then
        score = score + 25
    end

    if current_target and same_guid(candidate, current_target) then
        if self._izi_bridge then
            local current_ttd = self._izi_bridge:get_time_to_die(candidate)
            if current_ttd and current_ttd < 5.0 then score = score + 20 else score = score + 5 end
        else
            score = score + 20
        end
    end

    if self._izi_bridge then
        local ttd = self._izi_bridge:get_time_to_die(candidate)
        if ttd and ttd > 0 then
            if ttd < 4.5 then score = score + 30
            elseif ttd < 8.0 then score = score + 15 end
        else
            local ok_hp, hp_pct = safe_call(candidate, "get_health_percentage")
            if ok_hp and tonumber(hp_pct) and tonumber(hp_pct) <= 20 then score = score + 15 end
        end
    else
        local ok_hp, hp_pct = safe_call(candidate, "get_health_percentage")
        if ok_hp and tonumber(hp_pct) and tonumber(hp_pct) <= 20 then score = score + 15 end
    end

    if dist <= 10 then score = score + 10 end
    if dist <= 5 then score = score + 10 end

    if not SpellHelper.is_spell_in_los(20271, player, candidate) then
        score = score - 15
    end

    if leash_center and leash_radius and ok_candidate_pos and type(candidate_pos) == "table" then
        if distance(candidate_pos, leash_center) > leash_radius then score = score - 20 end
    end

    if AuraCatalog.has_protection(candidate) then score = score - 25 end

    return score, dist
end

-- Helper for targeting
local function set_target(unit)
    if not core or not core.input or type(core.input.set_target) ~= "function" then
        return false
    end
    local ok = pcall(core.input.set_target, unit)
    if ok then return true end
    ok = pcall(core.input.set_target, core.input, unit)
    return ok
end

function DefaultTargetStrategy:get_best_target(opts)
    opts = opts or {}
    local player = self._blackboard:get("player.object")
    local player_pos = self._blackboard:get("player.position")
    local current_target = self._blackboard:get("combat.target")
    local player_target = self._blackboard:get("player.target")
    if not player or type(player_pos) ~= "table" then return nil end

    local leash_center = self._blackboard:get("combat.leash_center")
    local leash_radius = tonumber(self._blackboard:get("combat.leash_radius", 25)) or 25
    local best_unit = nil
    local best_score = -99999
    local best_dist = math.huge

    for _, candidate in ipairs(self:_enemy_list(player_pos, opts)) do
        local ok_dead, dead = safe_call(candidate, "is_dead")
        if not ok_dead or dead ~= true then
            local score, dist = self:_score(player, candidate, current_target, leash_center, leash_radius)
            if score > best_score or (score == best_score and dist < best_dist) then
                best_unit = candidate
                best_score = score
                best_dist = dist
            end
        end
    end

    if not best_unit and self:is_valid_enemy(player_target, opts) then
        local ok_dead, dead = safe_call(player_target, "is_dead")
        if not ok_dead or dead ~= true then
            best_unit = player_target
            best_score = 0
        end
    end

    if best_unit then
        if not current_target then
            self._event_bus:publish(Events.TARGET_ACQUIRED, {
                target = best_unit,
                score = best_score,
                source = self._blackboard:get("combat.source", "selector"),
            })
        elseif not same_guid(current_target, best_unit) then
            self._event_bus:publish(Events.TARGET_CHANGED, {
                from_target = current_target,
                to_target = best_unit,
                reason = "higher_score",
            })
        end
        if not current_target or not same_guid(current_target, best_unit) then
            set_target(best_unit)
        end
    elseif current_target then
        self._event_bus:publish(Events.TARGET_LOST, {
            target = current_target,
            reason = "no_candidates",
        })
    end

    return best_unit, best_score
end

return DefaultTargetStrategy