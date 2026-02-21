---@module BGBOT.core.intent.intents.escort_carrier
-- Escort our carrier by staying in support range and peeling nearby enemies.

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local utils       = require("shared/utils")
local helpers     = require("core/intent/intents/wsg_helpers")

local escort = {}
escort.__index = escort
setmetatable(escort, { __index = intent_base })

function escort.new()
    local self = intent_base.create("escort_carrier")
    setmetatable(self, escort)
    self._nav_goal = nil
    self._face_target = nil
    self._repath_at = 0
    return self
end

function escort:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._face_target = nil
    self._repath_at = 0
end

function escort:choose_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._face_target = nil
        return
    end

    if self_state.is_in_combat then
        self._nav_goal = nil
        local enemy = select(1, helpers.find_nearest_enemy(world_model, self_state.position, 25))
        self._face_target = enemy and enemy.handle or nil
        self._repath_at = core.time() + 0.6
        return
    end

    local bg = world_model:get_bg_state()
    local anchor_pos = nil
    local carrier_handle = nil

    local observed_ally_carrier = select(1, helpers.find_flag_carriers(world_model, self_state))
    if observed_ally_carrier and helpers.is_valid_handle(observed_ally_carrier)
        and not helpers.same_handle(observed_ally_carrier, self_state.handle) then
        anchor_pos = helpers.handle_to_pos(observed_ally_carrier)
        carrier_handle = observed_ally_carrier
    elseif bg and helpers.is_valid_handle(bg.our_flag_carrier)
        and not helpers.same_handle(bg.our_flag_carrier, self_state.handle) then
        anchor_pos = helpers.handle_to_pos(bg.our_flag_carrier)
        carrier_handle = bg.our_flag_carrier
    end

    if not anchor_pos then
        anchor_pos = select(1, helpers.find_support_anchor(world_model, self_state))
    end

    if not anchor_pos then
        local team = helpers.get_team_positions(self_state)
        anchor_pos = team.our_tunnel or team.our_base or team.midfield
    end

    self._nav_goal = helpers.to_goal(anchor_pos, 1.0)
    self._repath_at = core.time() + 1.0 + (math.random() * 1.5)

    local face_enemy = nil
    if carrier_handle and helpers.is_valid_handle(carrier_handle) then
        local carrier_pos = helpers.handle_to_pos(carrier_handle)
        if carrier_pos then
            local enemy = select(1, helpers.find_nearest_enemy(world_model, carrier_pos, 25))
            face_enemy = enemy and enemy.handle or nil
        end
    end
    if not face_enemy then
        local enemy = select(1, helpers.find_nearest_enemy(world_model, self_state.position, 22))
        face_enemy = enemy and enemy.handle or nil
    end
    self._face_target = face_enemy
end

function escort:tick(world_model)
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
        interact_target = nil,
        face_target     = self._face_target,
    }
end

function escort:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._face_target = nil
end

function escort:get_context()
    return {
        engage_allowed      = true,
        max_chase_range     = constants.COMBAT.DEFAULT_CHASE_RANGE,
        priority_target     = self._face_target,
        disengage_requested = false,
    }
end

return escort
