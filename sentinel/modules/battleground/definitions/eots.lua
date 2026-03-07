local Objectives = require("modules/battleground/data/objectives/eots")
local Routes = require("modules/battleground/data/routes/eots")
local Strategies = require("modules/battleground/strategies/eots")

local EOTSDefinition = {
    id = "EOTS",
    map_id = 566,
    battleground_id = 7,
    label = "Eye of the Storm",
    supports = {
        balanced = true,
        node_control = true,
        flag_focus = true,
        hybrid = true,
    },
}

function EOTSDefinition:get_objectives()
    return Objectives.all
end

function EOTSDefinition:get_routes()
    return Routes
end

function EOTSDefinition:get_strategy(name)
    return Strategies:get(name)
end

function EOTSDefinition:list_strategies()
    return Strategies:list()
end

function EOTSDefinition:get_route_for_strategy(strategy_id, side)
    local s = tostring(strategy_id or "balanced")
    local faction = tostring(side or "ALLIANCE")

    if s == "flag_focus" then
        return faction == "ALLIANCE" and "EOTS_FLAG_FOCUS_A" or "EOTS_FLAG_FOCUS_H"
    end

    return faction == "ALLIANCE" and "EOTS_A_NODE_CONTROL" or "EOTS_H_NODE_CONTROL"
end

function EOTSDefinition:get_bootstrap_route(side, objective_id, strategy_id)
    local faction = tostring(side or "ALLIANCE")
    if tostring(strategy_id or "balanced") == "flag_focus" then
        return faction == "ALLIANCE" and "EOTS_FLAG_FOCUS_A" or "EOTS_FLAG_FOCUS_H"
    end
    if objective_id == "CENTER_FLAG" then
        return faction == "ALLIANCE" and "EOTS_A_BOOTSTRAP_MAGE_TOWER" or "EOTS_H_BOOTSTRAP_BLOOD_ELF"
    end
    if faction == "ALLIANCE" then
        if objective_id == "DRAENEI_RUINS" then
            return "EOTS_A_BOOTSTRAP_DRAENEI"
        end
        return "EOTS_A_BOOTSTRAP_MAGE_TOWER"
    end
    if objective_id == "FEL_REAVER" then
        return "EOTS_H_BOOTSTRAP_FEL_REAVER"
    end
    return "EOTS_H_BOOTSTRAP_BLOOD_ELF"
end

return EOTSDefinition
