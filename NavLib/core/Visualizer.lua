-- Visualizer.lua
-- In-world 3D visualization for NavLib navigation data.
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
    -- Path layer
    path_future_line = color.cyan(150),
    path_past_line   = color.new(80, 80, 90, 60),
    waypoint_current = color.orange(255),
    waypoint_future  = color.cyan(180),
    player_to_target = color.orange(120),

    -- Destination layer
    destination_ring = color.green(220),
    destination_text = color.white(255),

    -- Obstacle layer (ray-detected)
    obstacle_fill = color.new(220, 40, 40, 50),
    obstacle_ring = color.new(220, 40, 40, 150),
    obstacle_text = color.new(220, 80, 80, 200),

    -- Scanned object layer
    scanned_fill = color.new(220, 180, 40, 40),
    scanned_ring = color.new(220, 180, 40, 150),
    scanned_text = color.new(220, 180, 80, 200),

    -- Corridor layer
    corridor_line = color.new(160, 140, 220, 120),

    -- State indicators
    requesting_ring = color.yellow(180),
    failed_ring     = color.red(220),
    failed_text     = color.red(255),
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
---@param facade table NavLib Facade instance
---@param menu table Menu elements table (must contain viz_* checkboxes)
---@return Visualizer
function Visualizer:new(facade, menu)
    local o = setmetatable({}, Visualizer)

    o._facade       = facade
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
    if not self._facade or not self._menu then return end
    if not self:_is_enabled() then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    local player_pos = player:get_position()
    local facade = self._facade

    -- Track state transitions for animations
    local current_state = facade:get_state()
    if current_state ~= self._last_state then
        if current_state == "arrived" then
            self._arrived_time = core.time()
        end
        self._last_state = current_state
    end

    -- Render layers back-to-front
    if self:_show_corridor() then
        self:_render_corridor(facade, player_pos)
    end

    if self:_show_obstacles() then
        self:_render_obstacles(facade, player_pos)
    end

    if self:_show_path() then
        self:_render_path(facade, player_pos)
    end

    if self:_show_destination() then
        self:_render_destination(facade, player_pos)
    end

    if self:_show_state() then
        self:_render_state_indicator(facade, player_pos, current_state)
    end
end

--------------------------------------------------------------------------------
-- Layer: Path + Waypoints
--------------------------------------------------------------------------------

---@param facade table
---@param player_pos vec3
function Visualizer:_render_path(facade, player_pos)
    local path = facade:get_current_path()
    if not path or #path == 0 then return end

    local path_index = facade:get_path_index()

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

---@param facade table
---@param player_pos vec3
function Visualizer:_render_destination(facade, player_pos)
    local dest = facade:get_destination()
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

---@param facade table
---@param player_pos vec3
function Visualizer:_render_obstacles(facade, player_pos)
    local obstacle = facade.obstacle
    if not obstacle then return end

    -- Ray-detected zones (red)
    local zones = obstacle._zones
    if zones then
        for _, zone in ipairs(zones) do
            local dist = Helpers.distance_3d(player_pos, zone)
            if dist < CULL_OBSTACLES then
                core.graphics.circle_3d_filled(zone, zone.radius,
                    COLORS.obstacle_fill)
                core.graphics.circle_3d(zone, zone.radius,
                    COLORS.obstacle_ring, 2, Z_OFFSET)
                if dist < CULL_TEXT then
                    core.graphics.text_3d(string.format("r=%.1f", zone.radius),
                        zone, 9, COLORS.obstacle_text, true)
                end
            end
        end
    end

    -- Scanned object zones (yellow)
    local scanned = obstacle:get_scanned_zones()
    if scanned then
        for _, zone in ipairs(scanned) do
            local dist = Helpers.distance_3d(player_pos, zone)
            if dist < CULL_OBSTACLES then
                core.graphics.circle_3d_filled(zone, zone.radius,
                    COLORS.scanned_fill)
                core.graphics.circle_3d(zone, zone.radius,
                    COLORS.scanned_ring, 2, Z_OFFSET)
                if dist < CULL_TEXT then
                    core.graphics.text_3d(string.format("r=%.1f", zone.radius),
                        zone, 9, COLORS.scanned_text, true)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Layer: Corridor Boundaries
--------------------------------------------------------------------------------

---@param facade table
---@param player_pos vec3
function Visualizer:_render_corridor(facade, player_pos)
    local widths = facade:get_corridor_widths()
    if not widths then return end

    local path = facade:get_current_path()
    if not path or #path < 2 then return end

    local path_index = facade:get_path_index()

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

---@param facade table
---@param player_pos vec3
---@param state string
function Visualizer:_render_state_indicator(facade, player_pos, state)
    if state == "idle" or state == "moving" then return end

    if state == "stuck" then
        -- Pulsing red circle around player
        local pulse = math.sin(core.time() * 4)
        local alpha = math.floor(100 + 120 * ((pulse + 1) * 0.5))
        local stuck_color = color.new(255, 40, 40, alpha)
        core.graphics.circle_3d(player_pos, 2.5, stuck_color, 3, Z_OFFSET)

    elseif state == "requesting_path" then
        -- Static yellow ring while waiting for path
        core.graphics.circle_3d(player_pos, 2.0,
            COLORS.requesting_ring, 2, Z_OFFSET)

    elseif state == "arrived" then
        -- Expanding green ring that fades over 2 seconds
        if self._arrived_time then
            local elapsed = core.time() - self._arrived_time
            if elapsed < ARRIVED_FLASH_DURATION then
                local fade = 1.0 - (elapsed / ARRIVED_FLASH_DURATION)
                local alpha = math.floor(255 * fade)
                local arrived_color = color.new(40, 255, 40, alpha)
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
    self._facade = nil
    self._menu = nil
end

return Visualizer
