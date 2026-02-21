---@module BGBOT.core.intent.intents.retreat
-- Disengage and run to safety (carrier/ally cluster/our graveyard).

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local utils       = require("shared/utils")
local helpers     = require("core/intent/intents/wsg_helpers")

local retreat = {}
retreat.__index = retreat
setmetatable(retreat, { __index = intent_base })

function retreat.new()
    local self = intent_base.create("retreat")
    setmetatable(self, retreat)
    self._nav_goal = nil
    self._repath_at = 0
    return self
end

function retreat:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._repath_at = 0
end

function retreat:choose_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        return
    end

    local anchor = select(1, helpers.find_support_anchor(world_model, self_state))
    self._nav_goal = helpers.to_goal(anchor, 1.0)
    self._repath_at = core.time() + 1.0 + (math.random() * 1.2)
end

function retreat:tick(world_model)
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
        face_target     = nil,
    }
end

function retreat:exit()
    intent_base.exit(self)
    self._nav_goal = nil
end

function retreat:get_context()
    return {
        engage_allowed      = false,
        max_chase_range     = 0,
        priority_target     = nil,
        disengage_requested = true,
    }
end

return retreat
