local Objectives = require("modules/battleground/data/objectives/wsg")
local Routes = require("modules/battleground/data/routes/wsg")
local Strategies = require("modules/battleground/strategies/wsg")

local WSGDefinition = {
    id = "WSG",
    map_id = 489,
    battleground_id = 2,
    label = "Warsong Gulch",
    supports = {
        balanced = true,
        flag_run = true,
        turtle_defense = true,
        midfield_control = true,
    },
}

function WSGDefinition:get_objectives()
    return Objectives.all
end

function WSGDefinition:get_routes()
    return Routes
end

function WSGDefinition:get_strategy(name)
    return Strategies:get(name)
end

function WSGDefinition:list_strategies()
    return Strategies:list()
end

function WSGDefinition:get_route_for_strategy(strategy_id, side)
    local s = tostring(strategy_id or "balanced")
    local faction = tostring(side or "ALLIANCE")

    if s == "flag_run" then
        return faction == "ALLIANCE" and "WSG_A_FLAG_RUN" or "WSG_H_FLAG_RUN"
    end
    if s == "turtle_defense" then
        return faction == "ALLIANCE" and "WSG_A_DEFENSE" or "WSG_H_DEFENSE"
    end
    if s == "midfield_control" then
        return "WSG_MID_CONTROL"
    end

    return faction == "ALLIANCE" and "WSG_A_FLAG_RUN" or "WSG_H_FLAG_RUN"
end

function WSGDefinition:get_bootstrap_route(side, _objective_id, strategy_id)
    return self:get_route_for_strategy(strategy_id, side)
end

return WSGDefinition
