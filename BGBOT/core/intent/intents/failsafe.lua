---@module BGBOT.core.intent.intents.failsafe
-- Failsafe intent: prevent solo feed behavior when isolated from allies.
-- Cross-BG global intent that routes to nearest safe anchor while disengaging.

local intent_base   = require("core/intent/intent_base")
local constants     = require("shared/constants")
local bg_constants  = require("shared/bg_constants")
local utils         = require("shared/utils")
local helpers       = require("core/intent/intents/wsg_helpers")
local pathing       = require("core/intent/pathing")

local failsafe = {}
failsafe.__index = failsafe
setmetatable(failsafe, { __index = intent_base })

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

local HERD_NEARBY_RADIUS  = 80
local ENEMY_NEARBY_RADIUS = 80
local ALLY_ANCHOR_RANGE   = 80

local SCORE_DANGER        = 85
local SCORE_ISOLATED      = 50

local ARRIVED_DIST        = 10
local REPATH_MIN          = 3.0
local REPATH_MAX          = 5.0
local ANCHOR_JITTER       = 1.25

local POSITION_MATCH_TOL  = 5.0

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function failsafe.new()
    local self = intent_base.create("failsafe")
    setmetatable(self, failsafe)
    self._nav_goal = nil
    self._anchor_kind = "none"
    self._repath_at = 0
    return self
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function copy_pos(pos)
    return pathing.copy_pos(pos)
end

local function count_nearby_allies(world_model, self_state, radius)
    local self_pos = self_state and self_state.position
    if not self_pos then
        return 0
    end

    local self_handle = self_state and self_state.handle or nil
    local count = 0

    for _, ally in ipairs(world_model:get_allies()) do
        if ally and ally.position and ally.position.x then
            local same = false
            if self_handle and ally.handle then
                same = helpers.same_handle(self_handle, ally.handle)
            end

            if not same then
                local dist = utils.distance_3d(self_pos, ally.position)
                if dist <= radius then
                    count = count + 1
                end
            end
        end
    end

    return count
end

local function count_nearby_enemies(world_model, self_pos, radius)
    if not self_pos then
        return 0
    end

    local count = 0
    for _, ent in pairs(world_model:get_all_entities()) do
        if ent and ent.is_player and ent.is_enemy and not ent.is_dead and ent.position then
            local dist = utils.distance_3d(self_pos, ent.position)
            if dist <= radius then
                count = count + 1
            end
        end
    end
    return count
end

local function select_best_anchor(self_pos, anchors, bg_type, max_linear_distance)
    return select(1, pathing.select_best_anchor(self_pos, anchors, {
        bg_type = bg_type,
        max_linear_distance = max_linear_distance,
    }))
end

local function nearest_extracted_anchor(bg_type, self_pos)
    if not self_pos then
        return nil
    end

    local src = nil
    if bg_type == "ab" then
        src = ((bg_constants or {}).ARATHI_BASIN or {}).NODES
    elseif bg_type == "eots" then
        src = ((bg_constants or {}).EYE_OF_THE_STORM or {}).NODES
    elseif bg_type == "av" then
        src = ((bg_constants or {}).ALTERAC_VALLEY or {}).NODES
    end

    if not src then
        return nil
    end

    local extracted = {}
    for _, node in ipairs(src) do
        if node and node.x and node.y and node.z then
            extracted[#extracted + 1] = { x = node.x, y = node.y, z = node.z }
        end
    end

    return select_best_anchor(self_pos, extracted, bg_type)
end

local function select_best_ally_anchor(world_model, self_state, bg_type)
    local self_pos = self_state and self_state.position
    if not self_pos then
        return nil
    end

    local self_handle = self_state and self_state.handle or nil
    local anchors = {}
    for _, ally in ipairs(world_model:get_allies()) do
        if ally and ally.position and ally.position.x then
            local same = false
            if self_handle and ally.handle then
                same = helpers.same_handle(self_handle, ally.handle)
            end

            if not same then
                local dist = utils.distance_3d(self_pos, ally.position)
                if dist <= (ALLY_ANCHOR_RANGE + POSITION_MATCH_TOL) then
                    anchors[#anchors + 1] = ally.position
                end
            end
        end
    end

    return select_best_anchor(self_pos, anchors, bg_type, ALLY_ANCHOR_RANGE + POSITION_MATCH_TOL)
end

local function select_safe_anchor(world_model, self_state)
    local self_pos = self_state and self_state.position
    if not self_pos then
        return nil, "none"
    end

    local bg = world_model:get_bg_state()
    local bg_type = (bg and bg.bg_type) or "unknown"

    local ally_anchor = select_best_ally_anchor(world_model, self_state, bg_type)
    if ally_anchor then
        return ally_anchor, "ally"
    end

    local anchors = constants.BG_SAFE_ANCHORS and constants.BG_SAFE_ANCHORS[bg_type]
    local anchor = select_best_anchor(self_pos, anchors, bg_type)
    if anchor then
        return copy_pos(anchor), "bg_anchor"
    end

    local extracted = nearest_extracted_anchor(bg_type, self_pos)
    if extracted then
        return extracted, "extracted_anchor"
    end

    return copy_pos(self_pos), "hold_ground"
end

----------------------------------------------------------------------
-- Scoring (called by strategist global scoring path)
----------------------------------------------------------------------

---@param world_model WorldModel
---@return number score
function failsafe.compute_score(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        return 0
    end

    if self_state.is_in_combat then
        return 0
    end

    local allies_near = count_nearby_allies(world_model, self_state, HERD_NEARBY_RADIUS)
    if allies_near > 0 then
        return 0
    end

    local enemies_near = count_nearby_enemies(world_model, self_state.position, ENEMY_NEARBY_RADIUS)
    if enemies_near >= 1 then
        return SCORE_DANGER
    end

    return SCORE_ISOLATED
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function failsafe:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._anchor_kind = "none"
    self._repath_at = 0
    self:_update_goal(world_model)
end

function failsafe:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    if self._nav_goal == nil or now >= self._repath_at then
        self:_update_goal(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist <= ARRIVED_DIST then
            self:_update_goal(world_model)
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = nil,
        face_target     = nil,
    }
end

function failsafe:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._anchor_kind = "none"
end

function failsafe:is_complete()
    return false
end

function failsafe:get_context()
    return {
        engage_allowed       = false,
        max_chase_range      = 0,
        priority_target      = nil,
        disengage_requested  = true,
    }
end

----------------------------------------------------------------------
-- Internal
----------------------------------------------------------------------

function failsafe:_update_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._anchor_kind = "none"
        self._repath_at = core.time() + REPATH_MIN
        return
    end

    local anchor, kind = select_safe_anchor(world_model, self_state)
    self._anchor_kind = kind or "none"

    if not anchor then
        self._nav_goal = nil
        self._repath_at = core.time() + REPATH_MIN
        return
    end

    self._nav_goal = helpers.to_goal(anchor, ANCHOR_JITTER) or anchor
    self._repath_at = core.time() + REPATH_MIN + (math.random() * (REPATH_MAX - REPATH_MIN))
end

return failsafe
