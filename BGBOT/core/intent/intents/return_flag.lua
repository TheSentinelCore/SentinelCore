---@module BGBOT.core.intent.intents.return_flag
-- Return our dropped flag (or pressure likely flag location when not visible).

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local utils       = require("shared/utils")
local helpers     = require("core/intent/intents/wsg_helpers")

local return_flag = {}
return_flag.__index = return_flag
setmetatable(return_flag, { __index = intent_base })

function return_flag.new()
    local self = intent_base.create("return_flag")
    setmetatable(self, return_flag)
    self._nav_goal = nil
    self._interact_target = nil
    self._face_target = nil
    self._repath_at = 0
    return self
end

function return_flag:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._interact_target = nil
    self._face_target = nil
    self._repath_at = 0
end

function return_flag:choose_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._interact_target = nil
        self._face_target = nil
        return
    end

    local team = helpers.get_team_positions(self_state)
    local target_pos = nil

    self._interact_target = nil
    self._face_target = nil

    if not target_pos then
        local flag_obj, dist = helpers.find_nearest_flag_object(
            world_model, self_state.position, 75, self_state, "our"
        )
        if flag_obj and flag_obj.position then
            local at_home = false
            if team.our_base then
                at_home = utils.distance_2d(flag_obj.position, team.our_base)
                    <= (constants.WSG.FLAG_HOME_RADIUS or 14)
            end

            if not at_home then
                target_pos = flag_obj.position
                if flag_obj.handle and dist <= (constants.HUMAN.FLAG_INTERACT_RANGE + 2) then
                    self._interact_target = flag_obj.handle
                end
            end
        end
    end

    if not target_pos then
        target_pos = team.our_tunnel or team.our_base or team.midfield
    end

    self._nav_goal = helpers.to_goal(target_pos, 1.0)
    self._repath_at = core.time() + 1.0 + (math.random() * 1.2)
end

function return_flag:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    if self._nav_goal == nil or now >= self._repath_at then
        self:choose_goal(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist <= 5 then
            self:choose_goal(world_model)
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = self._interact_target,
        face_target     = self._face_target,
    }
end

function return_flag:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._interact_target = nil
    self._face_target = nil
end

function return_flag:get_context()
    return {
        engage_allowed      = true,
        max_chase_range     = constants.COMBAT.INTERCEPT_CHASE_RANGE,
        priority_target     = self._face_target,
        disengage_requested = false,
    }
end

return return_flag
