local StrategyFactory = {}
StrategyFactory.__index = StrategyFactory

local GrindTargetStrategy = require("modules/combat/strategies/grind_target_strategy")
local PvPTargetStrategy = require("modules/combat/strategies/pvp_target_strategy")

function StrategyFactory.create(strategy_name, event_bus, blackboard, izi_bridge, unit_helper)
    if strategy_name == "grind" then
        return GrindTargetStrategy:new(event_bus, blackboard, izi_bridge, unit_helper)
    elseif strategy_name == "pvp" then
        return PvPTargetStrategy:new(event_bus, blackboard)
    end
    return GrindTargetStrategy:new(event_bus, blackboard, izi_bridge, unit_helper)
end

return StrategyFactory