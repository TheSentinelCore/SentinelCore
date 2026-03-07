local Base = require("modules/battleground/state_machine_base")
local Objectives = require("modules/battleground/data/objectives/wsg")
local Routes = require("modules/battleground/data/routes/wsg")

local WSG = setmetatable({}, { __index = Base })
WSG.__index = WSG

local PLANS = {
    ALLIANCE = {
        { state = "MID_CONTROL", route_id = "WSG_MID_CONTROL", objective_id = "MID_FIELD" },
        { state = "ENEMY_FLAG_ROOM", route_id = "WSG_A_FLAG_RUN", objective_id = "HORDE_FLAG" },
        { state = "FLAG_ESCAPE_LANE", route_id = "WSG_H_FLAG_RUN", objective_id = "ALLIANCE_FLAG" },
        { state = "HOME_DEFENSE", route_id = "WSG_A_DEFENSE", objective_id = "ALLIANCE_FLAG" },
    },
    HORDE = {
        { state = "MID_CONTROL", route_id = "WSG_MID_CONTROL", objective_id = "MID_FIELD" },
        { state = "ENEMY_FLAG_ROOM", route_id = "WSG_H_FLAG_RUN", objective_id = "ALLIANCE_FLAG" },
        { state = "FLAG_ESCAPE_LANE", route_id = "WSG_A_FLAG_RUN", objective_id = "HORDE_FLAG" },
        { state = "HOME_DEFENSE", route_id = "WSG_H_DEFENSE", objective_id = "HORDE_FLAG" },
    },
}

function WSG:new(event_bus, blackboard, side)
    local o = Base.new(self, event_bus, blackboard, "WSG", side)
    o._plan_index = 1
    return o
end

function WSG:_objective(id)
    return Objectives.by_id[id]
end

function WSG:_apply_plan_step()
    local step = PLANS[self._side][self._plan_index]
    if not step then
        step = PLANS[self._side][#PLANS[self._side]]
    end
    local route_nodes = step.route_id and Routes[step.route_id] or nil
    local nav_target = step.objective_id and self:_objective(step.objective_id) or (route_nodes and route_nodes[#route_nodes])
    self:_set_objective(step.objective_id or step.route_id, nav_target, route_nodes, step.route_id)
    self:_set_state(step.state, "plan_step")
end

function WSG:update(blackboard)
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
            self._plan_index = 2
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
        return
    end

    if self._state ~= "HOME_DEFENSE" and (tonumber(blackboard:get("combat.enemy_count_10yd", 0)) or 0) >= 3 then
        self._plan_index = #PLANS[self._side]
        self:_apply_plan_step()
    end
end

return WSG
