---@module BGBOT.core.intent.intents.roam
-- Roam intent: move toward midfield with random offset.
-- Default fallback intent. Always yields to higher-priority intents.

local intent_base = require("core/intent/intent_base")
local constants   = require("shared/constants")
local config      = require("shared/config")
local utils       = require("shared/utils")
local helpers     = require("core/intent/intents/wsg_helpers")

local roam = {}
roam.__index = roam
setmetatable(roam, { __index = intent_base })

local function get_nav_state(nav_client)
    if not nav_client then
        return "unknown"
    end

    local ok_state, raw_state = pcall(function()
        return nav_client:get_state()
    end)
    local state = tostring((ok_state and raw_state) or "unknown")

    if state == "navigating" and nav_client.get_full_state then
        local ok_full, raw_full = pcall(function()
            return nav_client:get_full_state()
        end)
        local full_state = tostring((ok_full and raw_full) or "")
        if string.find(full_state, "navigating.recovering", 1, true) == 1 then
            return "stuck"
        end
    end

    return state
end

local function build_jittered_goal(base, jitter_radius)
    if not base or base.x == nil or base.y == nil or base.z == nil then
        return nil
    end

    local radius = jitter_radius or 8
    local offset_x = (math.random() - 0.5) * radius
    local offset_y = (math.random() - 0.5) * radius
    local target_x = base.x + offset_x
    local target_y = base.y + offset_y
    local target_z = base.z

    -- Prefer terrain-correct Z to reduce invalid/stuck paths on uncalibrated constants.
    local terrain_z = core.get_height_for_position({ x = target_x, y = target_y, z = base.z })
    if terrain_z and math.abs(terrain_z) > 0.01 then
        target_z = terrain_z
    end

    return {
        x = target_x,
        y = target_y,
        z = target_z,
    }
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function roam.new()
    local self = intent_base.create("roam")
    setmetatable(self, roam)
    self._nav_goal    = nil
    self._repath_at   = 0
    self._route       = nil
    self._route_index = 0
    self._bg_type     = "unknown"  -- resolved on enter/rebuild
    return self
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function roam:enter(world_model, params)
    intent_base.enter(self, world_model, params)

    -- Resolve current BG type for route selection
    local bg = world_model and world_model:get_bg_state()
    self._bg_type = (bg and bg.bg_type) or "unknown"

    self:_build_route(world_model)
    self:pick_roam_target(world_model, true)
end

function roam:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    -- Check if we've arrived close to the target
    if self_state and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist < 8 then
            -- Arrived — advance to next patrol node
            self:pick_roam_target(world_model, true)
        end
    end

    -- Handle nav errors by advancing node (uses get_state/get_full_state recovering pattern)
    local nav_client = _G.SentinelNavClient and _G.SentinelNavClient.client
    if nav_client then
        local nav_state = get_nav_state(nav_client)
        if nav_state == "stuck" or nav_state == "failed" then
            self:pick_roam_target(world_model, true)
        end
    end

    -- If bg_type changed (rare: zone transition mid-intent), rebuild route
    local bg = world_model:get_bg_state()
    local current_bg = (bg and bg.bg_type) or "unknown"
    if current_bg ~= self._bg_type then
        self._bg_type = current_bg
        self:_build_route(world_model)
        self:pick_roam_target(world_model, true)
    end

    -- Re-pick or initialize target periodically
    if self._nav_goal == nil or now >= self._repath_at then
        if self._nav_goal == nil then
            self:pick_roam_target(world_model, true)
        else
            -- Keep current node but refresh target with slight jitter/repath.
            self:pick_roam_target(world_model, false)
        end
    end

    -- Teamwork safety: if outnumbered while roaming, collapse to support anchor.
    if current_bg == "wsg" and self_state and self_state.position then
        local allies, enemies = helpers.count_players_near(
            world_model, self_state.position, constants.WSG.LOCAL_RISK_RADIUS
        )
        if enemies > (allies + (config.wsg.outnumbered_margin or constants.WSG.OUTNUMBERED_MARGIN)) then
            local anchor = select(1, helpers.find_support_anchor(world_model, self_state))
            if anchor then
                self._nav_goal = helpers.to_goal(anchor, 0.75)
                self._repath_at = now + 2.0
            end
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = nil,
        face_target     = nil,
    }
end

function roam:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._route = nil
end

function roam:is_complete()
    -- Roam never completes on its own — always yields to better intents
    return false
end

function roam:get_nav_goal()
    return self._nav_goal
end

function roam:get_context()
    return {
        engage_allowed       = true,    -- fight enemies of opportunity
        max_chase_range      = constants.COMBAT.DEFAULT_CHASE_RANGE,
        priority_target      = nil,
        disengage_requested  = false,
    }
end

----------------------------------------------------------------------
-- Internal: Pick roam target
----------------------------------------------------------------------

function roam:_build_route(world_model)
    local bg_type = self._bg_type or "unknown"

    -- WSG: use the original full patrol loop
    if bg_type == "wsg" then
        local p = constants.WSG_POSITIONS or {}
        local route = {}
        local ordered = {
            p.horde_flag_room,
            p.horde_tunnel,
            p.midfield,
            p.alliance_tunnel,
            p.alliance_flag_room,
            p.alliance_graveyard,
            p.midfield,
            p.horde_graveyard,
        }
        for _, pos in ipairs(ordered) do
            if pos and pos.x and pos.y and pos.z then
                route[#route + 1] = pos
            end
        end
        self._route = route
        self._route_index = 0
        return
    end

    -- Non-WSG BGs: use BG_SAFE_ANCHORS for a node-hopping patrol.
    local anchors = constants.BG_SAFE_ANCHORS and constants.BG_SAFE_ANCHORS[bg_type]
    if anchors and #anchors > 0 then
        local route = {}
        for _, pos in ipairs(anchors) do
            if pos and pos.x and pos.y and pos.z then
                route[#route + 1] = pos
            end
        end
        self._route = route
        self._route_index = 0
        return
    end

    -- Unknown BG / no anchors: try to stay near self (emergency fallback)
    local self_state = world_model and world_model:get_self()
    if self_state and self_state.position then
        self._route = { self_state.position }
    else
        self._route = {}
    end
    self._route_index = 0
end

function roam:pick_roam_target(world_model, advance_node)
    local self_state = world_model:get_self()
    local bg = world_model:get_bg_state()

    if self_state and self._bg_type == "wsg" then
        local buff_goal = helpers.pick_buff_detour(world_model, self_state)
        if buff_goal then
            self._nav_goal = buff_goal
            self._repath_at = core.time() + 3.0 + (math.random() * 2.0)
            return
        end
    end

    -- AB: prefer module-selected node target when available.
    if self._bg_type == "ab" and bg and bg.ab_target_node_pos then
        local node_goal = build_jittered_goal(bg.ab_target_node_pos, 6)
        if node_goal then
            self._nav_goal = node_goal
            self._repath_at = core.time() + 4.0 + (math.random() * 2.0)
            return
        end
    end

    -- EotS: prefer module-selected tower/mid-flag target when available.
    if self._bg_type == "eots" and bg and bg.eots_target_node_pos then
        local node_goal = build_jittered_goal(bg.eots_target_node_pos, 6)
        if node_goal then
            self._nav_goal = node_goal
            self._repath_at = core.time() + 4.0 + (math.random() * 2.0)
            return
        end
    end

    -- AV: prefer module-selected node target when available.
    if self._bg_type == "av" and bg and bg.av_target_node_pos then
        local node_goal = build_jittered_goal(bg.av_target_node_pos, 6)
        if node_goal then
            self._nav_goal = node_goal
            self._repath_at = core.time() + 4.0 + (math.random() * 2.0)
            return
        end
    end

    if not self._route or #self._route == 0 then
        self:_build_route(world_model)
    end

    if not self._route or #self._route == 0 then
        self._nav_goal = nil
        return
    end

    if advance_node then
        self._route_index = (self._route_index % #self._route) + 1
    end

    local base = self._route[self._route_index] or self._route[1]
    if not base then
        self._nav_goal = nil
        return
    end

    self._nav_goal = build_jittered_goal(base, 8)

    -- Refresh every 8-12 seconds while roaming.
    self._repath_at = core.time() + 8 + (math.random() * 4)
end

return roam
