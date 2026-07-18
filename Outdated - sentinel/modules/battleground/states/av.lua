local Base = require("modules/battleground/state_machine_base")
local Objectives = require("modules/battleground/data/objectives/av")
local Routes = require("modules/battleground/data/routes/av")

local AV = setmetatable({}, { __index = Base })
AV.__index = AV

local PLANS = {
    ALLIANCE = {
        { state = "OPENING_PUSH", route_id = "AV_A_ZERG", objective_id = "ICEBLOOD_GY" },
        { state = "OUTER_OBJECTIVE", target_id = "ICEBLOOD_TOWER" },
        { state = "MID_PUSH", route_id = "AV_A_TOWER_PUSH", objective_id = "TOWER_POINT" },
        { state = "INNER_OBJECTIVE", target_id = "FROSTWOLF_GY" },
        { state = "FINAL_KEEP_PUSH", target_id = "DREK" },
    },
    HORDE = {
        { state = "OPENING_PUSH", route_id = "AV_H_ZERG", objective_id = "STONEHEARTH_GY" },
        { state = "OUTER_OBJECTIVE", target_id = "STONEHEARTH_BUNKER" },
        { state = "MID_PUSH", route_id = "AV_H_TOWER_PUSH", objective_id = "ICEWING_BUNKER" },
        { state = "INNER_OBJECTIVE", target_id = "STORMPIKE_GY" },
        { state = "FINAL_KEEP_PUSH", target_id = "VANDAR" },
    },
}

function AV:new(event_bus, blackboard, side)
    local o = Base.new(self, event_bus, blackboard, "AV", side)
    o._plan_index = 1
    return o
end

function AV:_objective(id)
    return Objectives.by_id[id]
end

function AV:_apply_plan_step()
    local step = PLANS[self._side][self._plan_index]
    if not step then
        step = PLANS[self._side][#PLANS[self._side]]
    end
    local route_nodes = step.route_id and Routes[step.route_id] or nil
    local nav_target = step.target_id and self:_objective(step.target_id) or (route_nodes and route_nodes[#route_nodes])
    self:_set_objective(step.objective_id or step.target_id or step.route_id, nav_target, route_nodes, step.route_id)
    self:_set_state(step.state, "plan_step")
end

function AV:update(blackboard)
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
            self:_apply_plan_step()
            return
        end
    end

    if self._state == "SPAWN" then
        self:_apply_plan_step()
        return
    end

    if self._state == "REGROUP" then
        local hp = tonumber(blackboard:get("player.health_pct", 0)) or 0
        local enemies = tonumber(blackboard:get("combat.enemy_count_10yd", 0)) or 0
        local allies = tonumber(blackboard:get("combat.ally_count_30yd", 0)) or 0
        if hp >= 0.60 and allies >= enemies then
            self:_apply_plan_step()
        end
        return
    end

    if self._state ~= "DEFEND_NEAREST" and self._state ~= "RETREAT" then
        local enemies = tonumber(blackboard:get("combat.enemy_count_10yd", 0)) or 0
        if enemies >= 3 then
            local defend_id = Objectives.defend[self._side]
            self:_set_objective(defend_id, self:_objective(defend_id), nil)
            self:_set_state("DEFEND_NEAREST", "enemy_pressure")
            return
        end
    end

    if self._state == "DEFEND_NEAREST" and (tonumber(blackboard:get("combat.enemy_count_10yd", 0)) or 0) == 0 then
        self:_apply_plan_step()
    end
end

return AV
