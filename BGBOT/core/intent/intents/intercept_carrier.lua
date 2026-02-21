---@module BGBOT.core.intent.intents.intercept_carrier
-- Intercept enemy flag carrier. Falls back to likely route when carrier is unseen.

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local utils       = require("shared/utils")
local helpers     = require("core/intent/intents/wsg_helpers")

local intercept = {}
intercept.__index = intercept
setmetatable(intercept, { __index = intent_base })

function intercept.new()
    local self = intent_base.create("intercept_carrier")
    setmetatable(self, intercept)
    self._nav_goal = nil
    self._face_target = nil
    self._repath_at = 0
    return self
end

function intercept:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._face_target = nil
    self._repath_at = 0
end

function intercept:choose_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._face_target = nil
        return
    end

    local bg = world_model:get_bg_state()
    local team = helpers.get_team_positions(self_state)
    local target_pos = nil
    local face_target = nil

    local observed_enemy_carrier = select(2, helpers.find_flag_carriers(world_model, self_state))
    if observed_enemy_carrier and helpers.is_valid_handle(observed_enemy_carrier) then
        target_pos = helpers.handle_to_pos(observed_enemy_carrier)
        face_target = observed_enemy_carrier
    elseif bg and helpers.is_valid_handle(bg.their_flag_carrier) then
        target_pos = helpers.handle_to_pos(bg.their_flag_carrier)
        face_target = bg.their_flag_carrier
    end

    if not target_pos then
        target_pos = team.their_tunnel or team.their_base or team.midfield
    end

    local buff_goal = helpers.pick_buff_detour(world_model, self_state, 20)
    if buff_goal and not face_target then
        target_pos = buff_goal
    end

    self._nav_goal = helpers.to_goal(target_pos, 1.0)
    self._face_target = face_target
    self._repath_at = core.time() + 1.0 + (math.random() * 1.5)
end

function intercept:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    if self._nav_goal == nil or now >= self._repath_at then
        self:choose_goal(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist <= 6 then
            self:choose_goal(world_model)
        end
    end

    if not self._face_target and self_state and self_state.position then
        local enemy = select(1, helpers.find_nearest_enemy(world_model, self_state.position, 20))
        self._face_target = enemy and enemy.handle or nil
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = nil,
        face_target     = self._face_target,
    }
end

function intercept:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._face_target = nil
end

function intercept:get_context()
    return {
        engage_allowed      = true,
        max_chase_range     = constants.COMBAT.INTERCEPT_CHASE_RANGE,
        priority_target     = self._face_target,
        disengage_requested = false,
    }
end

return intercept
