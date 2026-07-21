local PvPTargetSelector = require("modules/combat/pvp_target_selector")
local StrategyFactory = require("modules/combat/strategies/factory")
local H = require("shared/combat_helpers")

local TargetSelector = {}
TargetSelector.__index = TargetSelector

local function is_hostile(player, unit)
    local ok_enemy, enemy = H.safe_call(unit, "is_enemy_with", player)
    if ok_enemy and enemy == true then return true end
    ok_enemy, enemy = H.safe_call(player, "is_enemy_with", unit)
    if ok_enemy and enemy == true then return true end
    local ok_attack, can_attack = H.safe_call(player, "can_attack", unit)
    if ok_attack and can_attack == true then return true end
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
        default = StrategyFactory.create("default", event_bus, blackboard, izi_bridge, o._unit_helper),
        pvp = StrategyFactory.create("pvp", event_bus, blackboard, izi_bridge, o._unit_helper),
    }
    o._current_strategy = "default"

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
    local ok_dead, dead = H.safe_call(unit, "is_dead")
    if ok_dead and dead == true then
        return false
    end

    -- Check if it's a player unit - only allow for require_player (PvP) mode
    local ok_is_player, is_player = H.safe_call(unit, "is_player")
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
                        local ok_dead, dead = H.safe_call(candidate, "is_dead")
                        if not ok_dead or dead ~= true then
                            local ok_unit, is_unit = H.safe_call(candidate, "is_unit")
                            if ok_unit and is_unit then
                                local ok_pos, pos = H.safe_call(candidate, "get_position")
                                if ok_pos and type(pos) == "table" and H.distance(player_pos, pos) <= scan_radius then
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
            local ok_dead, dead = H.safe_call(candidate, "is_dead")
            if not ok_dead or dead ~= true then
                local ok_pos, pos = H.safe_call(candidate, "get_position")
                if ok_pos and type(pos) == "table" and H.distance(player_pos, pos) <= (scan_radius or 55.0) then
                    results[#results + 1] = candidate
                end
            end
        end
    end
    return results
end

function TargetSelector:get_best_target(opts)
    opts = opts or {}
    local player = self._blackboard:get("player.object")
    local player_pos = self._blackboard:get("player.position")
    if not player or type(player_pos) ~= "table" then
        return nil
    end

    if self._blackboard:get("bg.active", false) == true then
        self:set_strategy("pvp")
    else
        self:set_strategy("default")
    end

    local strategy = self:get_strategy()
    -- Sync unit_helper to strategy (may be set after construction by tests or lazy init)
    if strategy and self._unit_helper then
        strategy._unit_helper = self._unit_helper
    end
    if strategy and strategy.get_best_target then
        return strategy:get_best_target(opts)
    end

    return nil, 0
end

return TargetSelector
