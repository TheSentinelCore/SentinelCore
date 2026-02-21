---@module BGBOT.core.intent.intents.spin_flag
-- Spin-flag intent: emergency engage to stop an enemy capping a friendly node.
-- Primarily for Arathi Basin. Score 100 when enemy is near a friendly-held
-- node within 30 yards; uses existing intent output fields (nav_goal, face_target).

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local utils       = require("shared/utils")

local spin_flag = {}
spin_flag.__index = spin_flag
setmetatable(spin_flag, { __index = intent_base })

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

local SPIN_ENGAGE_RANGE = 30   -- max distance to engage a node threat
local SPIN_ARRIVED_DIST = 5    -- close enough to the threat
local SPIN_REPATH_SEC   = 1.5  -- seconds between goal refreshes
local SPIN_NODE_RADIUS  = 15   -- capper threat radius around node

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function spin_flag.new()
    local self = intent_base.create("spin_flag")
    setmetatable(self, spin_flag)
    self._nav_goal     = nil
    self._face_target  = nil
    self._repath_at    = 0
    return self
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function spin_flag:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal    = nil
    self._face_target = nil
    self._repath_at   = 0
    self:_update_target(world_model)
end

function spin_flag:tick(world_model)
    local now = core.time()

    if self._nav_goal == nil or now >= self._repath_at then
        self:_update_target(world_model)
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = nil,
        face_target     = self._face_target,
    }
end

function spin_flag:exit()
    intent_base.exit(self)
    self._nav_goal    = nil
    self._face_target = nil
end

function spin_flag:is_complete()
    -- Re-scored every evaluate cycle; never self-completes.
    return false
end

function spin_flag:get_context()
    return {
        engage_allowed      = true,    -- must fight the capper
        max_chase_range     = 15,      -- don't chase far from node
        priority_target     = self._face_target,
        disengage_requested = false,
    }
end

function spin_flag:can_bypass_gates(_current_intent_id)
    return true
end

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------

local function copy_pos(pos)
    if not pos or pos.x == nil or pos.y == nil or pos.z == nil then
        return nil
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local function is_valid_handle(handle)
    if not handle then
        return false
    end
    local t = type(handle)
    if t ~= "table" and t ~= "userdata" then
        return false
    end
    if handle.is_valid == nil then
        return false
    end
    local ok, valid = pcall(function()
        return handle:is_valid()
    end)
    return ok and valid == true
end

local function handle_position(handle)
    if not is_valid_handle(handle) then
        return nil
    end
    local ok, pos = pcall(function()
        return handle:get_position()
    end)
    if not ok or not pos then
        return nil
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local function find_enemy_near_node(world_model, self_pos, node_pos)
    local best_handle = nil
    local best_pos = nil
    local best_node_dist = SPIN_NODE_RADIUS + 1

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.is_player and ent.is_enemy and not ent.is_dead and ent.position and ent.handle then
            local node_dist = utils.distance_3d(node_pos, ent.position)
            if node_dist <= SPIN_NODE_RADIUS then
                local self_dist = utils.distance_3d(self_pos, ent.position)
                if self_dist <= SPIN_ENGAGE_RANGE and node_dist < best_node_dist then
                    best_node_dist = node_dist
                    best_handle = ent.handle
                    best_pos = copy_pos(ent.position)
                end
            end
        end
    end

    return best_handle, best_pos
end

function spin_flag:_update_target(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal   = nil
        self._face_target = nil
        self._repath_at  = core.time() + SPIN_REPATH_SEC
        return
    end

    local self_pos = self_state.position
    local bg = world_model:get_bg_state()

    -- AB module provides preferred capper target metadata in bg_state.
    if bg and bg.bg_type == "ab" then
        local node_pos = bg.ab_spin_node_pos
        if node_pos and utils.distance_3d(self_pos, node_pos) <= SPIN_ENGAGE_RANGE then
            local handle = bg.ab_spin_target_handle
            local pos = handle_position(handle) or copy_pos(bg.ab_spin_target_pos)

            if (not handle or not is_valid_handle(handle) or not pos) then
                handle, pos = find_enemy_near_node(world_model, self_pos, node_pos)
            end

            if pos then
                self._nav_goal = pos
                self._face_target = is_valid_handle(handle) and handle or nil
                self._repath_at = core.time() + SPIN_REPATH_SEC
                return
            end
        end
    end

    self._nav_goal    = nil
    self._face_target = nil
    self._repath_at = core.time() + SPIN_REPATH_SEC
end

return spin_flag
