local AuraCatalog = require("modules/combat/aura_catalog")
local Events = require("modules/combat/events")
local PvPTargetSelector = require("modules/combat/pvp_target_selector")
local StrategyFactory = require("modules/combat/strategies/factory")

local TargetSelector = {}
TargetSelector.__index = TargetSelector
local _spell_helper_ref = nil
local _spell_helper_resolved = false
local _spell_helper_call_style = "self"

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function same_guid(a, b)
    local ok_a, guid_a = safe_call(a, "get_guid")
    local ok_b, guid_b = safe_call(b, "get_guid")
    return ok_a and ok_b and tostring(guid_a) == tostring(guid_b)
end

local function set_target(unit)
    if not core or not core.input or type(core.input.set_target) ~= "function" then
        return false
    end
    local ok = pcall(core.input.set_target, unit)
    if ok then
        return true
    end
    ok = pcall(core.input.set_target, core.input, unit)
    return ok
end

local function call_helper(fn, owner, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    if _spell_helper_call_style == "plain" then
        local ok, value = pcall(fn, ...)
        if ok then
            return true, value
        end
    end
    local ok, value = pcall(fn, owner, ...)
    if ok then
        return true, value
    end
    if _spell_helper_call_style ~= "plain" then
        return pcall(fn, ...)
    end
    return false, nil
end

local function resolve_spell_helper()
    if spell_helper then
        _spell_helper_ref = spell_helper
        _spell_helper_resolved = true
        _spell_helper_call_style = "self"
        return _spell_helper_ref
    end
    if not _spell_helper_resolved then
        local ok, mod = pcall(require, "common/utility/spell_helper")
        if ok and mod then
            _spell_helper_ref = mod
            _spell_helper_call_style = "self"
        end
        _spell_helper_resolved = true
    end
    return _spell_helper_ref
end

local function is_hostile(player, unit)
    local ok_enemy, enemy = safe_call(unit, "is_enemy_with", player)
    if ok_enemy and enemy == true then
        return true
    end
    ok_enemy, enemy = safe_call(player, "is_enemy_with", unit)
    if ok_enemy and enemy == true then
        return true
    end
    local ok_attack, can_attack = safe_call(player, "can_attack", unit)
    if ok_attack and can_attack == true then
        return true
    end
    return false
end

local function is_player_unit(unit)
    local ok_player, is_player = safe_call(unit, "is_player")
    if ok_player then
        return is_player == true
    end
    return false
end

function TargetSelector:new(event_bus, blackboard, izi_bridge)
    local o = setmetatable({}, TargetSelector)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._izi_bridge = izi_bridge
    local ok_unit, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok_unit and unit_helper or nil
    o._pvp_selector = PvPTargetSelector.new(event_bus, blackboard)

    -- Strategy pattern support
    o._strategies = {
        grind = StrategyFactory.create("grind", event_bus, blackboard, izi_bridge, o._unit_helper),
        pvp = StrategyFactory.create("pvp", event_bus, blackboard, izi_bridge, o._unit_helper),
    }
    o._current_strategy = "grind"

    return o
end

function TargetSelector:set_strategy(name)
    if self._strategies[name] then
        self._current_strategy = name
    end
end

function TargetSelector:get_strategy()
    return self._strategies[self._current_strategy]
end

function TargetSelector:is_valid_enemy(unit, opts)
    opts = opts or {}
    local player = self._blackboard:get("player.object")
    if not player or not unit then
        return false
    end
    local ok_dead, dead = safe_call(unit, "is_dead")
    if ok_dead and dead == true then
        return false
    end

    -- Check if it's a player unit - only allow for require_player (PvP) mode
    local ok_is_player, is_player = safe_call(unit, "is_player")
    if ok_is_player and is_player == true then
        return opts.require_player == true
    end

    -- Check attack_neutral setting - if enabled, accept neutral (yellow) mobs
    local attack_neutral = self._blackboard:get("module.grind.attack_neutral") == true
    if attack_neutral then
        -- For attack_neutral, we accept any unit that could be attacked.
        -- Neutral yellow mobs become attackable when targeted by the player.
        -- We already filtered out players above, so this is safe for PvE.
        return true
    end

    return is_hostile(player, unit)
end

function TargetSelector:_enemy_list(player_pos, opts)
    local scan_radius = 55.0
    local attack_neutral = self._blackboard:get("module.grind.attack_neutral") == true

    -- For attack_neutral, use get_all_objects to include neutral (yellow) mobs
    -- unit_helper.get_enemy_list_around only returns hostile (red) mobs
    if attack_neutral then
        if core and core.object_manager and type(core.object_manager.get_all_objects) == "function" then
            local ok, objects = pcall(core.object_manager.get_all_objects)
            if ok and type(objects) == "table" then
                local results = {}
                for _, candidate in ipairs(objects) do
                    if candidate and self:is_valid_enemy(candidate, opts) then
                        local ok_dead, dead = safe_call(candidate, "is_dead")
                        if not ok_dead or dead ~= true then
                            local ok_unit, is_unit = safe_call(candidate, "is_unit")
                            if ok_unit and is_unit then
                                local ok_pos, pos = safe_call(candidate, "get_position")
                                if ok_pos and type(pos) == "table" and distance(player_pos, pos) <= scan_radius then
                                    results[#results + 1] = candidate
                                end
                            end
                        end
                    end
                end
                if #results > 0 then
                    return results
                end
            end
        end
    end

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
        if #filtered > 0 then
            return filtered
        end
    end
    return self:_visible_enemy_list(player_pos, scan_radius, opts)
end

function TargetSelector:_visible_enemy_list(player_pos, scan_radius, opts)
    local player = self._blackboard:get("player.object")
    if not player or not core or not core.object_manager or type(core.object_manager.get_visible_objects) ~= "function" then
        return {}
    end
    local ok, visible = pcall(core.object_manager.get_visible_objects)
    if not ok or type(visible) ~= "table" then
        return {}
    end
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

function TargetSelector:_score(player, candidate, current_target, leash_center, leash_radius)
    local ok_candidate_pos, candidate_pos = safe_call(candidate, "get_position")
    local ok_player_pos, player_pos = safe_call(player, "get_position")
    local score = 0
    local dist = 99999
    if ok_player_pos and ok_candidate_pos and type(player_pos) == "table" and type(candidate_pos) == "table" then
        dist = distance(player_pos, candidate_pos)
    end

    if self._unit_helper and type(self._unit_helper.is_healer) == "function" then
        local ok_healer, healer = pcall(self._unit_helper.is_healer, self._unit_helper, candidate)
        if ok_healer and healer == true then
            score = score + 40
        end
    end

    local ok_target, candidate_target = safe_call(candidate, "get_target")
    if ok_target and candidate_target and same_guid(candidate_target, player) then
        score = score + 25
    end

    -- Use TTD for current target stickiness
    if current_target and same_guid(candidate, current_target) then
        if self._izi_bridge then
            local current_ttd = self._izi_bridge:get_time_to_die(candidate)
            if current_ttd and current_ttd < 5.0 then
                score = score + 20
            else
                score = score + 5
            end
        else
            score = score + 20
        end
    end

    -- Use TTD for execute priority scoring
    if self._izi_bridge then
        local ttd = self._izi_bridge:get_time_to_die(candidate)
        if ttd and ttd > 0 then
            if ttd < 4.5 then
                score = score + 30
            elseif ttd < 8.0 then
                score = score + 15
            end
        else
            local ok_hp, hp_pct = safe_call(candidate, "get_health_percentage")
            if ok_hp and tonumber(hp_pct) and tonumber(hp_pct) <= 20 then
                score = score + 15
            end
        end
    else
        local ok_hp, hp_pct = safe_call(candidate, "get_health_percentage")
        if ok_hp and tonumber(hp_pct) and tonumber(hp_pct) <= 20 then
            score = score + 15
        end
    end

    if dist <= 10 then
        score = score + 10
    end
    if dist <= 5 then
        score = score + 10
    end

    local helper = resolve_spell_helper()
    if helper and type(helper.is_spell_in_line_of_sight) == "function" then
        local ok_los, los = call_helper(helper.is_spell_in_line_of_sight, helper, 20271, player, candidate)
        if ok_los and los ~= true then
            score = score - 15
        end
    end

    if leash_center and leash_radius and ok_candidate_pos and type(candidate_pos) == "table" then
        if distance(candidate_pos, leash_center) > leash_radius then
            score = score - 20
        end
    end

    if AuraCatalog.has_protection(candidate) then
        score = score - 25
    end

    return score, dist
end

function TargetSelector:get_best_target(opts)
    opts = opts or {}
    local player = self._blackboard:get("player.object")
    local player_pos = self._blackboard:get("player.position")
    local current_target = self._blackboard:get("combat.target")
    local player_target = self._blackboard:get("player.target")
    if not player or type(player_pos) ~= "table" then
        return nil
    end

    if self._blackboard:get("bg.active", false) == true then
        self:set_strategy("pvp")
    else
        self:set_strategy("grind")
    end

    local strategy = self:get_strategy()
    if strategy and strategy.get_best_target then
        return strategy:get_best_target(opts)
    end

    return nil, 0
end

return TargetSelector
