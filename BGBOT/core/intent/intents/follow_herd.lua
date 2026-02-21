---@module BGBOT.core.intent.intents.follow_herd
-- Follow-herd intent: stay with the main ally group.
-- Cross-BG global intent. Active when out of combat and too far from herd.

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local config      = require("shared/config")
local utils       = require("shared/utils")

local follow_herd = {}
follow_herd.__index = follow_herd
setmetatable(follow_herd, { __index = intent_base })

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

local HERD_DISTANCE_THRESHOLD = 40   -- activate when further than this
local HERD_SCORE_BASE         = 55   -- base score when far from herd
local HERD_ARRIVED_DIST       = 12   -- close enough to herd center
local HERD_MIN_ALLIES         = 2    -- need at least this many allies for a herd
local HERD_JITTER             = 4    -- random offset to avoid stacking
local HERD_NEARBY_RADIUS      = 80   -- only consider nearby allies for CoM

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function follow_herd.new()
    local self = intent_base.create("follow_herd")
    setmetatable(self, follow_herd)
    self._nav_goal   = nil
    self._repath_at  = 0
    self._herd_center = nil
    return self
end

----------------------------------------------------------------------
-- Herd center-of-mass computation
----------------------------------------------------------------------

---@param world_model WorldModel
---@param self_pos table|nil {x,y,z}
---@param max_range number|nil
---@return table|nil {x,y,z}  center of mass of living allies, or nil if < min
---@return number ally_count
local function compute_herd_center(world_model, self_pos, max_range)
    local allies = world_model:get_allies()
    local range = tonumber(max_range) or HERD_NEARBY_RADIUS

    local sum_x, sum_y, sum_z = 0, 0, 0
    local count = 0
    for _, ally in ipairs(allies) do
        if ally.position and ally.position.x then
            local keep = true
            if self_pos and self_pos.x and self_pos.y and self_pos.z then
                keep = utils.distance_3d(self_pos, ally.position) <= range
            end
            if keep then
                sum_x = sum_x + ally.position.x
                sum_y = sum_y + ally.position.y
                sum_z = sum_z + ally.position.z
                count = count + 1
            end
        end
    end

    if count < HERD_MIN_ALLIES then
        return nil, count
    end

    return {
        x = sum_x / count,
        y = sum_y / count,
        z = sum_z / count,
    }, count
end

----------------------------------------------------------------------
-- Scoring (called by strategist global scoring path)
----------------------------------------------------------------------

--- Compute the score for follow_herd given world state.
--- Returns 0 if conditions are not met.
---@param world_model WorldModel
---@return number score
function follow_herd.compute_score(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        return 0
    end

    -- Only activate out of combat
    if self_state.is_in_combat then
        return 0
    end

    local center = compute_herd_center(world_model, self_state.position, HERD_NEARBY_RADIUS)
    if not center then
        return 0
    end

    local dist = utils.distance_3d(self_state.position, center)
    if dist <= HERD_DISTANCE_THRESHOLD then
        return 0
    end

    -- Score scales with distance: farther = more urgent
    local dist_bonus = math.min(20, (dist - HERD_DISTANCE_THRESHOLD) * 0.5)
    return HERD_SCORE_BASE + dist_bonus
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function follow_herd:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._repath_at = 0
    self:_update_goal(world_model)
end

function follow_herd:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    -- Refresh goal periodically or when arrived
    if self._nav_goal == nil or now >= self._repath_at then
        self:_update_goal(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist < HERD_ARRIVED_DIST then
            self:_update_goal(world_model)
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = nil,
        face_target     = nil,
    }
end

function follow_herd:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._herd_center = nil
end

function follow_herd:is_complete()
    -- Complete when we've arrived near the herd
    if self._herd_center and self._nav_goal then
        -- Will be re-scored next evaluate cycle anyway
        return false
    end
    return false
end

function follow_herd:get_context()
    return {
        engage_allowed      = true,    -- fight enemies of opportunity while moving
        max_chase_range     = constants.COMBAT.DEFAULT_CHASE_RANGE,
        priority_target     = nil,
        disengage_requested = false,
    }
end

----------------------------------------------------------------------
-- Internal
----------------------------------------------------------------------

function follow_herd:_update_goal(world_model)
    local self_state = world_model:get_self()
    local self_pos = self_state and self_state.position or nil
    local center = compute_herd_center(world_model, self_pos, HERD_NEARBY_RADIUS)
    self._herd_center = center

    if not center then
        self._nav_goal = nil
        self._repath_at = core.time() + 2.0
        return
    end

    -- Add small jitter to avoid all bots stacking on exact center
    local jx = (math.random() - 0.5) * HERD_JITTER * 2
    local jy = (math.random() - 0.5) * HERD_JITTER * 2

    self._nav_goal = {
        x = center.x + jx,
        y = center.y + jy,
        z = center.z,
    }
    self._repath_at = core.time() + 3.0 + (math.random() * 2.0)
end

return follow_herd
