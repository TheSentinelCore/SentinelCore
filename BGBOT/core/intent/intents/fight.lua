---@module BGBOT.core.intent.intents.fight
-- Engage nearby enemies while keeping tactical positioning.

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local config      = require("shared/config")
local utils       = require("shared/utils")
local helpers     = require("core/intent/intents/wsg_helpers")

local fight = {}
fight.__index = fight
setmetatable(fight, { __index = intent_base })

function fight.new()
    local self = intent_base.create("fight")
    setmetatable(self, fight)
    self._nav_goal = nil
    self._face_target = nil
    self._repath_at = 0
    return self
end

function fight:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._face_target = nil
    self._repath_at = 0
end

function fight:choose_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._face_target = nil
        return
    end

    local enemy, enemy_dist = helpers.find_nearest_enemy(world_model, self_state.position, 45)
    local allies_near, enemies_near = helpers.count_players_near(
        world_model,
        self_state.position,
        constants.WSG.LOCAL_RISK_RADIUS
    )
    local outnumbered = enemies_near > (allies_near + (config.wsg.outnumbered_margin or constants.WSG.OUTNUMBERED_MARGIN))
    local low_hp = (self_state.health_pct or 100) <= (config.combat.retreat_hp_pct or constants.COMBAT.RETREAT_HEALTH_PCT)

    if enemy and enemy.handle and enemy.position and not (outnumbered and low_hp) then
        local jitter = enemy_dist and enemy_dist < 10 and 0.5 or 1.5
        self._nav_goal = helpers.to_goal(enemy.position, jitter)
        self._face_target = enemy.handle
    else
        local anchor = select(1, helpers.find_support_anchor(world_model, self_state))
        self._nav_goal = helpers.to_goal(anchor, 1.5)
        self._face_target = enemy and enemy.handle or nil
    end

    self._repath_at = core.time() + 0.8 + (math.random() * 1.2)
end

function fight:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    if self._nav_goal == nil or now >= self._repath_at then
        self:choose_goal(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist <= 4 then
            self:choose_goal(world_model)
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = nil,
        face_target     = self._face_target,
    }
end

function fight:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._face_target = nil
end

function fight:get_context()
    return {
        engage_allowed      = true,
        max_chase_range     = constants.COMBAT.DEFAULT_CHASE_RANGE,
        priority_target     = self._face_target,
        disengage_requested = false,
    }
end

return fight
