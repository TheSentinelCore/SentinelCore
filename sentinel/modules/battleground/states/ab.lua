local Base = require("modules/battleground/state_machine_base")
local Objectives = require("modules/battleground/data/objectives/ab")
local Routes = require("modules/battleground/data/routes/ab")

local AB = setmetatable({}, { __index = Base })
AB.__index = AB

local PLANS = {
    ALLIANCE = {
        { state = "OPENING_SPLIT", route_id = "AB_A_DEFENSE", objective_id = "BLACKSMITH" },
        { state = "PRIMARY_NODE_ASSAULT", target_id = "BLACKSMITH" },
        { state = "DEFEND_NODE", target_id = "BLACKSMITH" },
        { state = "SECONDARY_ROTATION", route_id = "AB_A_NODE_ROTATION", objective_id = "LUMBER_MILL" },
    },
    HORDE = {
        { state = "OPENING_SPLIT", route_id = "AB_H_DEFENSE", objective_id = "BLACKSMITH" },
        { state = "PRIMARY_NODE_ASSAULT", target_id = "BLACKSMITH" },
        { state = "DEFEND_NODE", target_id = "BLACKSMITH" },
        { state = "SECONDARY_ROTATION", route_id = "AB_H_NODE_ROTATION", objective_id = "GOLD_MINE" },
    },
}

function AB:new(event_bus, blackboard, side)
    local o = Base.new(self, event_bus, blackboard, "AB", side)
    o._plan_index = 1
    return o
end

function AB:_objective(id)
    return Objectives.by_id[id]
end

function AB:_apply_plan_step()
    local step = PLANS[self._side][self._plan_index]
    if not step then
        step = PLANS[self._side][#PLANS[self._side]]
    end
    local route_nodes = step.route_id and Routes[step.route_id] or nil
    local nav_target = step.target_id and self:_objective(step.target_id) or (step.objective_id and self:_objective(step.objective_id)) or (route_nodes and route_nodes[#route_nodes])
    self:_set_objective(step.objective_id or step.target_id or step.route_id, nav_target, route_nodes, step.route_id)
    self:_set_state(step.state, "plan_step")
end

function AB:update(blackboard)
    if blackboard:get("bg.retreat_requested", false) == true then
        blackboard:clear("bg.retreat_requested")
        self:_set_objective("RETREAT", Objectives.retreat[self._side], nil)
        self:_set_state("RETREAT", "retreat_requested")
        return
    end

    local nav_result = self:_consume_nav_result()
    if nav_result == "failed" then
        self:_set_objective("REGROUP", Objectives.retreat[self._side], nil)
        self:_set_state("REGROUP", "nav_failed")
        return
    elseif nav_result == "arrived" then
        if self._state == "RETREAT" then
            self:_set_objective("REGROUP", Objectives.retreat[self._side], nil)
            self:_set_state("REGROUP", "retreat_arrived")
            return
        end
        if self._plan_index < #PLANS[self._side] then
            self._plan_index = self._plan_index + 1
        else
            self._plan_index = 3
        end
        self:_apply_plan_step()
        return
    end

    if self._state == "SPAWN" then
        self:_apply_plan_step()
        return
    end

    if self._state == "REGROUP" then
        local hp = tonumber(blackboard:get("player.health_pct", 0)) or 0
        if hp >= 0.60 then
            self._plan_index = 1
            self:_apply_plan_step()
        end
    end
end

return AB
