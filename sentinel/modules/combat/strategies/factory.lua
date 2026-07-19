local StrategyFactory = {}
StrategyFactory.__index = StrategyFactory

local DefaultTargetStrategy = require("modules/combat/strategies/default_target_strategy")
local PvPTargetStrategy = require("modules/combat/strategies/pvp_target_strategy")

function StrategyFactory.create(strategy_name, event_bus, blackboard, izi_bridge, unit_helper)
    if strategy_name == "default" then
        return DefaultTargetStrategy:new(event_bus, blackboard, izi_bridge, unit_helper)
    elseif strategy_name == "pvp" then
        return PvPTargetStrategy:new(event_bus, blackboard)
    end
    return DefaultTargetStrategy:new(event_bus, blackboard, izi_bridge, unit_helper)
end

return StrategyFactory