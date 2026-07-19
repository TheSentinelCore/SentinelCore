local Objectives = require("modules/battleground/data/objectives/av")
local Routes = require("modules/battleground/data/routes/av")
local Strategies = require("modules/battleground/strategies/av")

local AVDefinition = {
    id = "AV",
    map_id = 30,
    battleground_id = 1,
    label = "Alterac Valley",
    supports = {
        zerg_rush = true,
        tower_push = true,
        turtle_defense = true,
        balanced = true,
    },
}

function AVDefinition:get_objectives()
    return Objectives.all
end

function AVDefinition:get_routes()
    return Routes
end

function AVDefinition:get_strategy(name)
    return Strategies:get(name)
end

function AVDefinition:list_strategies()
    return Strategies:list()
end

function AVDefinition:get_route_for_strategy(strategy_id, side)
    local s = tostring(strategy_id or "balanced")
    local faction = tostring(side or "ALLIANCE")

    if s == "zerg_rush" then
        return faction == "ALLIANCE" and "AV_A_ZERG" or "AV_H_ZERG"
    end

    return faction == "ALLIANCE" and "AV_A_TOWER_PUSH" or "AV_H_TOWER_PUSH"
end

function AVDefinition:get_bootstrap_route(side, _objective_id, strategy_id)
    return self:get_route_for_strategy(strategy_id, side)
end

return AVDefinition
