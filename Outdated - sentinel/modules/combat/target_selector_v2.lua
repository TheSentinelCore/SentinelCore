local StrategyFactory = require("modules/combat/strategies/factory")
local Events = require("modules/combat/events")
local AuraCatalog = require("modules/combat/aura_catalog")

local TargetSelector = {}
TargetSelector.__index = TargetSelector

function TargetSelector:new(event_bus, blackboard, izi_bridge)
    local o = setmetatable({}, TargetSelector)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._izi_bridge = izi_bridge

    local ok_unit, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok_unit and unit_helper or nil

    -- Create strategy instances
    o._strategies = {
        pvp = StrategyFactory.create("pvp", event_bus, blackboard, izi_bridge, o._unit_helper),
        grind = StrategyFactory.create("grind", event_bus, blackboard, izi_bridge, o._unit_helper),
        default = StrategyFactory.create("default", event_bus, blackboard, izi_bridge, o._unit_helper),
    }
    o._current_strategy = "default"

    return o
end

function TargetSelector:set_strategy(name)
    if self._strategies[name] then
        self._current_strategy = name
    end
end

function TargetSelector:get_strategy(name)
    return self._strategies[name] or self._strategies.default
end

-- Public API for target validation
function TargetSelector:is_valid_enemy(unit, opts)
    opts = opts or {}
    local strategy = self._strategies[self._current_strategy]
    if strategy and strategy.is_valid_enemy then
        return strategy:is_valid_enemy(unit, opts)
    end
    return false
end

-- Get best target using current strategy
function TargetSelector:get_best_target(opts)
    local strategy = self._strategies[self._current_strategy]
    if strategy and strategy.get_best_target then
        return strategy:get_best_target(opts)
    end
    return nil, 0
end

-- Legacy method for backward compatibility
function TargetSelector:select_target(opts)
    return self:get_best_target(opts)
end

return TargetSelector