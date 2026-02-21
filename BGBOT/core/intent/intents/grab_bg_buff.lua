---@module BGBOT.core.intent.intents.grab_bg_buff
-- Grab-BG-buff intent: pick up nearby BG buff powerups.
-- Cross-BG global intent. Brief score spike when OOC and a buff is close.

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local config      = require("shared/config")
local utils       = require("shared/utils")

local grab_bg_buff = {}
grab_bg_buff.__index = grab_bg_buff
setmetatable(grab_bg_buff, { __index = intent_base })

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

local BUFF_PICKUP_RANGE    = 25    -- max distance to consider a buff
local BUFF_SCORE_BASE      = 65    -- brief spike; beats roam, below flag ops
local BUFF_ARRIVED_DIST    = 4     -- close enough to interact
local BUFF_ENEMY_MARGIN    = 1     -- skip if enemies outnumber allies by this

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function grab_bg_buff.new()
    local self = intent_base.create("grab_bg_buff")
    setmetatable(self, grab_bg_buff)
    self._nav_goal       = nil
    self._target_handle  = nil
    self._repath_at      = 0
    return self
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

--- Find the nearest buff object from world model entities.
---@param world_model WorldModel
---@param self_pos table {x,y,z}
---@param max_range number
---@return table|nil entity_record, number|nil distance
local function find_nearest_buff(world_model, self_pos, max_range)
    local best_ent = nil
    local best_dist = max_range + 1

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.is_buff_object and ent.position and not ent.is_dead then
            local dist = utils.distance_3d(self_pos, ent.position)
            if dist <= max_range and dist < best_dist then
                best_ent = ent
                best_dist = dist
            end
        end
    end

    if best_ent then
        return best_ent, best_dist
    end
    return nil, nil
end

--- Count nearby allies and enemies for safety check.
---@param world_model WorldModel
---@param pos table {x,y,z}
---@param radius number
---@return number allies, number enemies
local function count_nearby(world_model, pos, radius)
    local allies, enemies = 0, 0
    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.is_player and not ent.is_dead and ent.position then
            local dist = utils.distance_3d(pos, ent.position)
            if dist <= radius then
                if ent.is_ally then
                    allies = allies + 1
                elseif ent.is_enemy then
                    enemies = enemies + 1
                end
            end
        end
    end
    return allies, enemies
end

----------------------------------------------------------------------
-- Scoring (called by strategist global scoring path)
----------------------------------------------------------------------

--- Compute the score for grab_bg_buff given world state.
--- Returns 0 if conditions are not met.
---@param world_model WorldModel
---@return number score
function grab_bg_buff.compute_score(world_model)
    if not config.wsg.enable_buff_pickups then
        return 0
    end

    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        return 0
    end

    -- Only activate out of combat
    if self_state.is_in_combat then
        return 0
    end

    local buff, dist = find_nearest_buff(world_model, self_state.position, BUFF_PICKUP_RANGE)
    if not buff then
        return 0
    end

    -- Safety check: skip if enemies outnumber allies nearby
    local allies, enemies = count_nearby(
        world_model,
        buff.position,
        constants.WSG.LOCAL_RISK_RADIUS
    )
    if enemies > (allies + BUFF_ENEMY_MARGIN) then
        return 0
    end

    -- Score inversely with distance: closer buff = higher urgency
    local dist_bonus = math.max(0, (BUFF_PICKUP_RANGE - dist) * 0.4)
    return BUFF_SCORE_BASE + dist_bonus
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function grab_bg_buff:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._target_handle = nil
    self._repath_at = 0
    self:_update_target(world_model)
end

function grab_bg_buff:tick(world_model)
    if not config.wsg.enable_buff_pickups then
        self._nav_goal = nil
        self._target_handle = nil
        return {
            nav_goal        = nil,
            interact_target = nil,
            face_target     = nil,
        }
    end

    local now = core.time()
    local self_state = world_model:get_self()

    -- Refresh target periodically or on arrival
    if self._nav_goal == nil or now >= self._repath_at then
        self:_update_target(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist < BUFF_ARRIVED_DIST then
            self:_update_target(world_model)
        end
    end

    -- Build interact target if close enough
    local interact = nil
    if self._target_handle and self_state and self_state.position then
        local ok_valid, valid = pcall(function()
            return self._target_handle:is_valid()
        end)
        if ok_valid and valid then
            local ok_pos, tpos = pcall(function()
                return self._target_handle:get_position()
            end)
            if ok_pos and tpos then
                local d = utils.distance_3d(self_state.position, tpos)
                if d <= BUFF_ARRIVED_DIST + 2 then
                    interact = self._target_handle
                end
            end
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = interact,
        face_target     = nil,
    }
end

function grab_bg_buff:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._target_handle = nil
end

function grab_bg_buff:is_complete()
    -- Complete when no target remains (buff picked up or despawned)
    if not self._target_handle then
        return true
    end
    local ok, valid = pcall(function()
        return self._target_handle:is_valid()
    end)
    if not ok or not valid then
        return true
    end
    return false
end

function grab_bg_buff:get_context()
    return {
        engage_allowed      = true,    -- can fight while detouring
        max_chase_range     = 15,      -- short chase so we don't abandon the buff
        priority_target     = nil,
        disengage_requested = false,
    }
end

----------------------------------------------------------------------
-- Internal
----------------------------------------------------------------------

function grab_bg_buff:_update_target(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._target_handle = nil
        return
    end

    local buff, dist = find_nearest_buff(world_model, self_state.position, BUFF_PICKUP_RANGE)
    if not buff or not buff.position then
        self._nav_goal = nil
        self._target_handle = nil
        self._repath_at = core.time() + 1.0
        return
    end

    self._nav_goal = {
        x = buff.position.x,
        y = buff.position.y,
        z = buff.position.z,
    }
    self._target_handle = buff.handle
    self._repath_at = core.time() + 2.0 + (math.random() * 1.0)
end

return grab_bg_buff
