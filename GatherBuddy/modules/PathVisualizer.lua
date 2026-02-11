---@class PathVisualizer
---@field private _movement_module MovementModule
---@field private _profile_manager ProfileManager
---@field private _enabled boolean
---@field private _show_profile_waypoints boolean
---@field private _show_current_path boolean
---@field private _show_destination boolean
local PathVisualizer = {}
PathVisualizer.__index = PathVisualizer

-- Import dependencies
local color = require("common/color")
local vec3 = require("common/geometry/vector_3")
local Helpers = require("utils/Helpers")

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "utils/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("PathVisualizer")
    end
    return nil
end

---Create a new PathVisualizer instance
---@param movement_module MovementModule
---@param profile_manager ProfileManager
---@return PathVisualizer
function PathVisualizer:new(movement_module, profile_manager)
    local instance = setmetatable({}, PathVisualizer)

    instance._movement_module = movement_module
    instance._profile_manager = profile_manager
    instance._log = get_logger()

    -- Visualization settings
    instance._enabled = true
    instance._show_profile_waypoints = true
    instance._show_current_path = true
    instance._show_destination = true
    instance._show_distance_text = true

    -- Colors
    instance._colors = {
        path_waypoint = color.green(180),
        hotspot_waypoint = color.yellow(180),
        current_path = color.cyan(200),
        current_path_line = color.cyan(150),
        destination = color.red(255),
        destination_text = color.white(255),
        current_target = color.orange(255),
        partial_endpoint = color.red(200),
    }

    -- Register render callback
    core.register_on_render_callback(function()
        if instance._enabled then
            instance:_render()
        end
    end)

    if instance._log then
        instance._log:info("PathVisualizer initialized")
    end

    return instance
end

---Enable or disable visualization
---@param enabled boolean
function PathVisualizer:set_enabled(enabled)
    self._enabled = enabled
end

---Check if visualization is enabled
---@return boolean
function PathVisualizer:is_enabled()
    return self._enabled
end

---Toggle visualization on/off
function PathVisualizer:toggle()
    self._enabled = not self._enabled
    if self._log then
        self._log:info("Visualization %s", self._enabled and "enabled" or "disabled")
    end
end

---Set which elements to visualize
---@param profile_waypoints boolean Show profile waypoints
---@param current_path boolean Show current navigation path
---@param destination boolean Show destination marker
function PathVisualizer:set_visibility(profile_waypoints, current_path, destination)
    self._show_profile_waypoints = profile_waypoints
    self._show_current_path = current_path
    self._show_destination = destination
end

---Main render function (called every frame when enabled)
function PathVisualizer:_render()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    local player_pos = player:get_position()

    -- Draw profile waypoints
    if self._show_profile_waypoints then
        self:_render_profile_waypoints(player_pos)
    end

    -- Draw current navigation path
    if self._show_current_path then
        self:_render_current_path(player_pos)
    end

    -- Draw destination marker
    if self._show_destination then
        self:_render_destination(player_pos)
    end
end

---Render profile waypoints
---@param player_pos vec3
function PathVisualizer:_render_profile_waypoints(player_pos)
    if not self._profile_manager then
        return
    end

    local profile = self._profile_manager:get_current_profile()
    if not profile or not profile.waypoints then
        return
    end

    local current_wp_id = nil
    if self._profile_manager.get_current_waypoint then
        local current_wp = self._profile_manager:get_current_waypoint()
        if current_wp then
            current_wp_id = current_wp.id
        end
    end

    for i, wp in ipairs(profile.waypoints) do
        local pos = vec3.new(wp.x, wp.y, wp.z)
        local dist = Helpers.distance_3d(player_pos, pos)

        -- Only render waypoints within reasonable distance (500 yards)
        if dist < 500 then
            local is_current = current_wp_id and wp.id == current_wp_id
            local is_hotspot = wp.type == "hotspot"

            -- Choose color based on type
            local wp_color
            if is_current then
                wp_color = self._colors.current_target
            elseif is_hotspot then
                wp_color = self._colors.hotspot_waypoint
            else
                wp_color = self._colors.path_waypoint
            end

            -- Draw circle at waypoint
            local radius = is_current and 1.5 or 0.8
            local thickness = is_current and 3 or 2
            core.graphics.circle_3d(pos, radius, wp_color, thickness, 2.5)

            -- Draw waypoint ID text for closer waypoints
            if dist < 100 then
                local label = tostring(wp.id)
                if is_hotspot then
                    label = label .. " (H)"
                end
                core.graphics.text_3d(label, pos, 10, wp_color, true)
            end

            -- Draw hotspot radius
            if is_hotspot and wp.radius then
                core.graphics.circle_3d(pos, wp.radius, self._colors.hotspot_waypoint, 1, 3.0)
            end
        end
    end
end

---Render current navigation path
---@param player_pos vec3
function PathVisualizer:_render_current_path(player_pos)
    if not self._movement_module then
        return
    end

    local path = self._movement_module:get_current_path()
    if not path or #path == 0 then
        return
    end

    -- Get current path index if available
    local current_index = 1
    if self._movement_module.get_path_index then
        current_index = self._movement_module:get_path_index()
    end

    -- Draw path waypoints and lines
    for i, wp in ipairs(path) do
        local dist = Helpers.distance_3d(player_pos, wp)

        -- Only render within reasonable distance
        if dist < 300 then
            local is_current_target = i == current_index
            local is_future = i > current_index
            local is_past = i < current_index

            -- Draw waypoint marker
            if is_future or is_current_target then
                local wp_color = is_current_target and self._colors.current_target or self._colors.current_path
                local radius = is_current_target and 1.2 or 0.5
                core.graphics.circle_3d(wp, radius, wp_color, 2)
            end

            -- Draw line to next waypoint
            if i < #path and (is_future or is_current_target) then
                local next_wp = path[i + 1]
                local line_color = is_current_target and self._colors.current_target or self._colors.current_path_line
                core.graphics.line_3d(wp, next_wp, line_color, 1, 2.5)
            end
        end
    end

    -- Draw line from player to current target waypoint
    if current_index <= #path then
        local target_wp = path[current_index]
        local dist = Helpers.distance_3d(player_pos, target_wp)
        if dist < 200 then
            core.graphics.line_3d(player_pos, target_wp, self._colors.current_target, 2, 2.0)
        end
    end
end

---Render destination marker
---@param player_pos vec3
function PathVisualizer:_render_destination(player_pos)
    if not self._movement_module then
        return
    end

    local dest = self._movement_module:get_destination()
    if not dest then
        return
    end

    local dist = Helpers.distance_3d(player_pos, dest)

    -- Draw destination circle
    core.graphics.circle_3d(dest, 2.0, self._colors.destination, 3, 2.0)

    -- Draw distance text
    if self._show_distance_text and dist < 500 then
        local text = string.format("%.0f yds", dist)
        core.graphics.text_3d(text, dest, 14, self._colors.destination_text, true)
    end

    -- If in iterative mode, show final destination differently
    if self._movement_module._iterative_mode and self._movement_module._final_destination then
        local final_dest = self._movement_module._final_destination
        local final_dist = Helpers.distance_3d(player_pos, final_dest)

        -- Draw final destination with different style
        core.graphics.circle_3d(final_dest, 3.0, self._colors.partial_endpoint, 2, 2.5)

        if final_dist < 500 then
            local text = string.format("Final: %.0f yds", final_dist)
            core.graphics.text_3d(text, final_dest, 12, self._colors.partial_endpoint, true)
        end
    end
end

---Clean up and unregister callbacks
function PathVisualizer:destroy()
    self._enabled = false
    -- Note: Sylvannas doesn't have unregister for render callbacks
    -- The callback will still run but do nothing since _enabled is false
end

return PathVisualizer
