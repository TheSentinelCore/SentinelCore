local Base = require("modules/battleground/state_machine_base")
local Objectives = require("modules/battleground/data/objectives/eots")
local Routes = require("modules/battleground/data/routes/eots")

local EOTS = setmetatable({}, { __index = Base })
EOTS.__index = EOTS

local PLANS = {
    ALLIANCE = {
        { state = "MID_RACE", route_id = "EOTS_A_NODE_CONTROL", objective_id = "MAGE_TOWER" },
        { state = "PRIMARY_TOWER_ASSAULT", target_id = "MAGE_TOWER" },
        { state = "FLAG_PLATFORM_CONTROL", target_id = "CENTER_FLAG" },
        { state = "FLAG_TURNIN", route_id = "EOTS_FLAG_FOCUS", objective_id = "CENTER_FLAG" },
        { state = "SECONDARY_TOWER_ROTATION", target_id = "DRAENEI_RUINS" },
    },
    HORDE = {
        { state = "MID_RACE", route_id = "EOTS_H_NODE_CONTROL", objective_id = "BLOOD_ELF" },
        { state = "PRIMARY_TOWER_ASSAULT", target_id = "BLOOD_ELF" },
        { state = "FLAG_PLATFORM_CONTROL", target_id = "CENTER_FLAG" },
        { state = "FLAG_TURNIN", route_id = "EOTS_FLAG_FOCUS", objective_id = "CENTER_FLAG" },
        { state = "SECONDARY_TOWER_ROTATION", target_id = "FEL_REAVER" },
    },
}

function EOTS:new(event_bus, blackboard, side)
    local o = Base.new(self, event_bus, blackboard, "EOTS", side)
    o._plan_index = 1
    o._step_retry_used = false
    return o
end

function EOTS:_objective(id)
    return Objectives.by_id[id]
end

function EOTS:_apply_plan_step(preserve_retry)
    local step = PLANS[self._side][self._plan_index]
    if not step then
        step = PLANS[self._side][#PLANS[self._side]]
    end
    local route_nodes = step.route_id and Routes[step.route_id] or nil
    local nav_target = step.target_id and self:_objective(step.target_id) or (step.objective_id and self:_objective(step.objective_id)) or (route_nodes and route_nodes[#route_nodes])
    if preserve_retry ~= true then
        self._step_retry_used = false
    end
    self:_set_objective(step.objective_id or step.target_id or step.route_id, nav_target, route_nodes, step.route_id)
    self:_set_state(step.state, "plan_step")
end

function EOTS:update(blackboard)
    if blackboard:get("bg.retreat_requested", false) == true then
        blackboard:clear("bg.retreat_requested")
        self:_set_objective("RETREAT", Objectives.retreat[self._side], nil)
        self:_set_state("RETREAT", "retreat_requested")
        return
    end

    local nav_result = self:_consume_nav_result()
    if nav_result == "failed" then
        if self._state ~= "RETREAT" and self._state ~= "REGROUP" and not self._step_retry_used then
            self._step_retry_used = true
            blackboard:set("bg.route_failure_reason", "eots_safe_route_retry")
            self:_apply_plan_step(true)
            return
        end
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

return EOTS
