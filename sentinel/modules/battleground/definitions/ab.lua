local Objectives = require("modules/battleground/data/objectives/ab")
local Routes = require("modules/battleground/data/routes/ab")
local Strategies = require("modules/battleground/strategies/ab")

local ABDefinition = {
    id = "AB",
    map_id = 529,
    battleground_id = 3,
    label = "Arathi Basin",
    supports = {
        balanced = true,
        node_rotation = true,
        turtle_defense = true,
        aggressive_push = true,
    },
}

function ABDefinition:get_objectives()
    return Objectives.all
end

function ABDefinition:get_routes()
    return Routes
end

function ABDefinition:get_strategy(name)
    return Strategies:get(name)
end

function ABDefinition:list_strategies()
    return Strategies:list()
end

function ABDefinition:get_route_for_strategy(strategy_id, side)
    local s = tostring(strategy_id or "balanced")
    local faction = tostring(side or "ALLIANCE")

    if s == "turtle_defense" then
        return faction == "ALLIANCE" and "AB_A_DEFENSE" or "AB_H_DEFENSE"
    end

    return faction == "ALLIANCE" and "AB_A_NODE_ROTATION" or "AB_H_NODE_ROTATION"
end

function ABDefinition:get_bootstrap_route(side, _objective_id, strategy_id)
    return self:get_route_for_strategy(strategy_id, side)
end

return ABDefinition
