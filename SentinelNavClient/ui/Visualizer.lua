-- Visualizer.lua
-- In-world 3D visualization for SentinelNavClient navigation data.
-- Renders path lines, waypoint markers, destination, obstacle zones,
-- corridor boundaries, and state indicators.

local color   = require("common/color")
local Helpers = require("lib/Helpers")

---@class Visualizer
local Visualizer = {}
Visualizer.__index = Visualizer

--------------------------------------------------------------------------------
-- Color palette (allocated once at require-time, no per-frame allocation)
--------------------------------------------------------------------------------

local COLORS = {
    -- Path layer — accent blue, unified with UI theme
    path_future_line = color.new(10, 132, 255, 140),
    path_past_line   = color.new(120, 120, 130, 40),
    waypoint_current = color.new(255, 255, 255, 240),
    waypoint_future  = color.new(10, 132, 255, 160),
    player_to_target = color.new(255, 255, 255, 80),

    -- Destination layer — iOS system green
    destination_ring = color.new(48, 209, 88, 200),
    destination_text = color.new(255, 255, 255, 220),

    -- Obstacle layer — iOS system red
    obstacle_fill = color.new(255, 69, 58, 35),
    obstacle_ring = color.new(255, 69, 58, 140),
    obstacle_text = color.new(255, 69, 58, 180),

    -- Corridor layer — white structural guides
    corridor_line = color.new(255, 255, 255, 60),

    -- State indicators — iOS system colors
    requesting_ring = color.new(255, 214, 10, 160),
    failed_ring     = color.new(255, 69, 58, 200),
    failed_text     = color.new(255, 69, 58, 240),
}

--------------------------------------------------------------------------------
-- Culling distances (yards) and rendering constants
--------------------------------------------------------------------------------

local CULL_PATH      = 300
local CULL_OBSTACLES = 200
local CULL_TEXT      = 100
local CULL_CORRIDOR  = 250
local Z_OFFSET       = 2.0

local ARRIVED_FLASH_DURATION = 2.0

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a new Visualizer instance.
---Registers its own render callback via core.register_on_render_callback.
---@param client table SentinelNavClient Client instance
---@param menu table Menu elements table (must contain viz_* checkboxes)
---@return Visualizer
function Visualizer:new(client, menu)
    local o = setmetatable({}, Visualizer)

    o._client       = client
    o._menu         = menu
    o._arrived_time = nil
    o._last_state   = "idle"

    core.register_on_render_callback(function()
        o:_on_render()
    end)

    return o
end

--------------------------------------------------------------------------------
-- Toggle queries
--------------------------------------------------------------------------------

function Visualizer:_is_enabled()
    return self._menu.viz_master:get_state()
end

function Visualizer:_show_path()
    return self._menu.viz_path:get_state()
end

function Visualizer:_show_destination()
    return self._menu.viz_destination:get_state()
end

function Visualizer:_show_obstacles()
    return self._menu.viz_obstacles:get_state()
end

function Visualizer:_show_corridor()
    return self._menu.viz_corridor:get_state()
end

function Visualizer:_show_state()
    return self._menu.viz_state:get_state()
end

--------------------------------------------------------------------------------
-- Render entry point (called every frame by registered callback)
--------------------------------------------------------------------------------

function Visualizer:_on_render()
    if not self._client or not self._menu then return end
    if not self:_is_enabled() then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    local player_pos = player:get_position()
    local client = self._client

    -- Track state transitions for animations
    local current_state = client:get_state()
    local full_state = client.get_full_state and client:get_full_state() or current_state
    if current_state ~= self._last_state then
        if current_state == "arrived" then
            self._arrived_time = core.time()
        end
        self._last_state = current_state
    end

    -- Render layers back-to-front
    if self:_show_corridor() then
        self:_render_corridor(client, player_pos)
    end

    if self:_show_obstacles() then
        self:_render_obstacles(client, player_pos)
    end

    if self:_show_path() then
        self:_render_path(client, player_pos)
    end

    if self:_show_destination() then
        self:_render_destination(client, player_pos)
    end

    if self:_show_state() then
        self:_render_state_indicator(client, player_pos, current_state, full_state)
    end
end

--------------------------------------------------------------------------------
-- Layer: Path + Waypoints
--------------------------------------------------------------------------------

---@param client table
---@param player_pos vec3
function Visualizer:_render_path(client, player_pos)
    local path = client:get_current_path()
    if not path or #path == 0 then return end

    local path_index = client:get_path_index()

    for i = 1, #path do
        local wp = path[i]
        local dist = Helpers.distance_3d(player_pos, wp)

        if dist < CULL_PATH then
            local is_past    = i < path_index
            local is_current = i == path_index
            local is_future  = i > path_index

            -- Line segment to next waypoint
            if i < #path then
                local next_wp = path[i + 1]
                local next_dist = Helpers.distance_3d(player_pos, next_wp)

                if next_dist < CULL_PATH then
                    if is_past then
                        core.graphics.line_3d(wp, next_wp,
                            COLORS.path_past_line, 1, Z_OFFSET)
                    elseif is_current or is_future then
                        core.graphics.line_3d(wp, next_wp,
                            COLORS.path_future_line, 1, Z_OFFSET)
                    end
                end
            end

            -- Waypoint circle markers (skip past waypoints for clean look)
            if is_current then
                core.graphics.circle_3d(wp, 1.5,
                    COLORS.waypoint_current, 3, Z_OFFSET)
            elseif is_future then
                core.graphics.circle_3d(wp, 0.8,
                    COLORS.waypoint_future, 2, Z_OFFSET)
            end

            -- Index text for current waypoint (close range)
            if is_current and dist < CULL_TEXT then
                core.graphics.text_3d(tostring(i), wp, 10,
                    COLORS.waypoint_current, true)
            end
        end
    end

    -- Line from player to current target waypoint
    if path_index >= 1 and path_index <= #path then
        local target_wp = path[path_index]
        local dist = Helpers.distance_3d(player_pos, target_wp)
        if dist < CULL_PATH then
            core.graphics.line_3d(player_pos, target_wp,
                COLORS.player_to_target, 2, Z_OFFSET)
        end
    end
end

--------------------------------------------------------------------------------
-- Layer: Destination Marker
--------------------------------------------------------------------------------

---@param client table
---@param player_pos vec3
function Visualizer:_render_destination(client, player_pos)
    local dest = client:get_destination()
    if not dest then return end

    local dist = Helpers.distance_3d(player_pos, dest)
    if dist > CULL_PATH then return end

    -- Double concentric rings (bullseye)
    core.graphics.circle_3d(dest, 2.0,
        COLORS.destination_ring, 3, Z_OFFSET)
    core.graphics.circle_3d(dest, 2.8,
        COLORS.destination_ring, 1, Z_OFFSET)

    -- Distance text (close range)
    if dist < CULL_TEXT then
        local text = string.format("%.0f yd", dist)
        core.graphics.text_3d(text, dest, 14,
            COLORS.destination_text, true)
    end
end

--------------------------------------------------------------------------------
-- Layer: Obstacle Zones
--------------------------------------------------------------------------------

---@param client table
---@param player_pos vec3
function Visualizer:_render_obstacles(client, player_pos)
    local obstacle = client.obstacle
    if not obstacle then return end

    local zones = obstacle:get_avoidance_zones()
    if not zones or #zones == 0 then return end

    for _, zone in ipairs(zones) do
        local dist = Helpers.distance_3d(player_pos, zone)

        if dist < CULL_OBSTACLES then
            -- Semi-transparent filled circle for zone area
            core.graphics.circle_3d_filled(zone, zone.radius,
                COLORS.obstacle_fill)

            -- Red ring outline
            core.graphics.circle_3d(zone, zone.radius,
                COLORS.obstacle_ring, 2, Z_OFFSET)

            -- Radius text (close range)
            if dist < CULL_TEXT then
                local label = string.format("r=%.1f", zone.radius)
                core.graphics.text_3d(label, zone, 9,
                    COLORS.obstacle_text, true)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Layer: Corridor Boundaries
--------------------------------------------------------------------------------

---@param client table
---@param player_pos vec3
function Visualizer:_render_corridor(client, player_pos)
    local widths = client:get_corridor_widths()
    if not widths then return end

    local path = client:get_current_path()
    if not path or #path < 2 then return end

    local path_index = client:get_path_index()

    for i = 1, math.min(#path - 1, #widths) do
        -- Only render current + future segments
        if i >= path_index - 1 then
            local wp_a = path[i]
            local wp_b = path[i + 1]

            -- Distance cull on segment midpoint
            local mid = {
                x = (wp_a.x + wp_b.x) * 0.5,
                y = (wp_a.y + wp_b.y) * 0.5,
                z = (wp_a.z + wp_b.z) * 0.5,
            }
            local dist = Helpers.distance_3d(player_pos, mid)
            if dist < CULL_CORRIDOR then
                local half_w = widths[i] * 0.5

                -- Perpendicular direction (2D, XY plane)
                local dx = wp_b.x - wp_a.x
                local dy = wp_b.y - wp_a.y
                local seg_len = math.sqrt(dx * dx + dy * dy)

                if seg_len > 0.01 then
                    local px = -dy / seg_len
                    local py =  dx / seg_len

                    -- Left boundary
                    local left_a = { x = wp_a.x + px * half_w, y = wp_a.y + py * half_w, z = wp_a.z }
                    local left_b = { x = wp_b.x + px * half_w, y = wp_b.y + py * half_w, z = wp_b.z }
                    core.graphics.line_3d(left_a, left_b,
                        COLORS.corridor_line, 1, Z_OFFSET)

                    -- Right boundary
                    local right_a = { x = wp_a.x - px * half_w, y = wp_a.y - py * half_w, z = wp_a.z }
                    local right_b = { x = wp_b.x - px * half_w, y = wp_b.y - py * half_w, z = wp_b.z }
                    core.graphics.line_3d(right_a, right_b,
                        COLORS.corridor_line, 1, Z_OFFSET)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Layer: State Indicators
--------------------------------------------------------------------------------

---@param client table
---@param player_pos vec3
---@param state string Top-level HSM state
---@param full_state string Dot-joined full state (e.g. "navigating.recovering")
function Visualizer:_render_state_indicator(client, player_pos, state, full_state)
    if state == "idle" or state == "navigating" then
        -- Check substates that need indicators
        if full_state and full_state:find("recovering") then
            -- Pulsing red circle around player (stuck/recovering)
            local pulse = math.sin(core.time() * 4)
            local alpha = math.floor(100 + 120 * ((pulse + 1) * 0.5))
            local stuck_color = color.new(255, 69, 58, alpha)
            core.graphics.circle_3d(player_pos, 2.5, stuck_color, 3, Z_OFFSET)
            return
        elseif full_state and full_state:find("awaiting_path") then
            -- Static yellow ring while waiting for path
            core.graphics.circle_3d(player_pos, 2.0,
                COLORS.requesting_ring, 2, Z_OFFSET)
            return
        end
        return
    end

    if state == "arrived" then
        -- Expanding green ring that fades over 2 seconds
        if self._arrived_time then
            local elapsed = core.time() - self._arrived_time
            if elapsed < ARRIVED_FLASH_DURATION then
                local fade = 1.0 - (elapsed / ARRIVED_FLASH_DURATION)
                local alpha = math.floor(255 * fade)
                local arrived_color = color.new(48, 209, 88, alpha)
                local radius = 2.0 + (1.0 - fade) * 2.0
                core.graphics.circle_3d(player_pos, radius,
                    arrived_color, 3, Z_OFFSET)
            else
                self._arrived_time = nil
            end
        end

    elseif state == "failed" then
        -- Red X (two crossing diagonal lines) + "FAILED" text
        local size = 1.5
        local px, py, pz = player_pos.x, player_pos.y, player_pos.z
        core.graphics.line_3d(
            { x = px - size, y = py - size, z = pz },
            { x = px + size, y = py + size, z = pz },
            COLORS.failed_ring, 3, Z_OFFSET)
        core.graphics.line_3d(
            { x = px - size, y = py + size, z = pz },
            { x = px + size, y = py - size, z = pz },
            COLORS.failed_ring, 3, Z_OFFSET)
        core.graphics.text_3d("FAILED", player_pos, 14,
            COLORS.failed_text, true)
    end
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Visualizer:destroy()
    self._client = nil
    self._menu = nil
end

return Visualizer
