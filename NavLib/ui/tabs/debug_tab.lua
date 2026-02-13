--[[
    Debug Tab - Live status, logging, waypoint testing
]]

local vec2    = require("common/geometry/vector_2")
local enums   = require("common/enums")
local AstroUI = require("shared/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local DebugTab = {}

-- Module-level waypoint storage
local _waypoints = {}
local _nav_active = false
local _nav_index = 0

-- Helper: render a clickable button, returns (clicked, next_y)
local function render_button(window, colors, x, y, w, h, label, enabled)
    enabled = enabled ~= false
    local btn_start = vec2.new(x, y)
    local btn_end = vec2.new(x + w, y + h)
    local hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local bg = enabled and (hovered and colors.primary_accent or colors.slider_fill) or colors.slider_bg
    window:render_rect_filled(btn_start, btn_end, bg, 2)
    window:render_rect(btn_start, btn_end, colors.primary_accent, 2, 1.0)

    local text_size = window:get_text_size(label)
    local text_x = x + (w - text_size.x) / 2
    local text_y = y + (h - text_size.y) / 2
    local text_col = enabled and colors.text_primary or colors.text_secondary
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), text_col, label)

    local clicked = enabled and hovered and window:is_rect_clicked(btn_start, btn_end)
    return clicked, y + h + 4
end

-- Helper: render a label: value text line
local function render_line(window, colors, x, y, label, value)
    local text = label .. ": " .. tostring(value)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x, y), colors.text_secondary, text)
    return y + window:get_text_size(text).y + 2
end

---Register the debug tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
---@param facade table|nil NavLib Facade instance
function DebugTab.register(ui, menu, facade)
    ui:add_tab({ id = "debug", label = "Debug" }, function(t)

        -- Live Status (custom rendered)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side

                -- Section label
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.primary_accent, "Live Status")
                y_offset = y_offset + window:get_text_size("Live Status").y + 4

                if not facade then
                    y_offset = render_line(window, colors, x, y_offset, "State", "no facade")
                    return y_offset + 8
                end

                local state = facade:get_state()
                y_offset = render_line(window, colors, x, y_offset, "State", state)

                local player = core.object_manager.get_local_player()
                if player then
                    local pos = player:get_position()
                    y_offset = render_line(window, colors, x, y_offset, "Position",
                        string.format("%.1f, %.1f, %.1f", pos.x, pos.y, pos.z))
                end

                local dest = facade:get_destination()
                if dest then
                    y_offset = render_line(window, colors, x, y_offset, "Destination",
                        string.format("%.1f, %.1f, %.1f", dest.x, dest.y, dest.z))
                    if player then
                        local dist = player:get_position():dist_to(dest)
                        y_offset = render_line(window, colors, x, y_offset, "Distance",
                            string.format("%.1f yd", dist))
                    end
                end

                local path = facade:get_current_path()
                if path then
                    local idx = facade:get_path_index()
                    y_offset = render_line(window, colors, x, y_offset, "Waypoint",
                        string.format("%d / %d", idx, #path))
                end

                return y_offset + 8
            end
        })

        -- Verbose Logging toggle
        t:checkbox_grid({
            label = "Logging",
            columns = 1,
            elements = {
                { element = menu.debug_verbose, label = "Verbose Logging",
                  tooltip = "Enables detailed movement and pathfinding log output" },
            }
        })

        -- Waypoint Management (custom rendered)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local window_size = window:get_size()
                local content_width = window_size.x - (2 * LAYOUT.padding_side)
                local btn_w = (content_width - 4) / 2
                local btn_h = 20

                -- Section label
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.primary_accent, "Waypoints")
                y_offset = y_offset + window:get_text_size("Waypoints").y + 4

                -- Waypoint list
                for i, wp in ipairs(_waypoints) do
                    local wp_text = string.format("#%d: %.0f, %.0f, %.0f", i, wp.x, wp.y, wp.z)
                    local is_current = _nav_active and i == _nav_index
                    local wp_color = is_current and colors.secondary_accent or colors.text_secondary
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), wp_color, wp_text)

                    -- Per-waypoint remove button
                    local rm_w = 16
                    local rm_x = x + content_width - rm_w
                    local rm_start = vec2.new(rm_x, y_offset)
                    local rm_end = vec2.new(rm_x + rm_w, y_offset + 14)
                    window:is_mouse_hovering_rect_block_movement(rm_start, rm_end)
                    if window:is_rect_clicked(rm_start, rm_end) then
                        table.remove(_waypoints, i)
                    end
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(rm_x + 3, y_offset), colors.text_secondary, "X")

                    y_offset = y_offset + 16
                end

                if #_waypoints == 0 then
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, "(no waypoints)")
                    y_offset = y_offset + 16
                end

                y_offset = y_offset + 4

                -- Button row 1: Add Here / Clear All
                local clicked_add = render_button(window, colors, x, y_offset,
                    btn_w, btn_h, "Add Here")
                if clicked_add then
                    local player = core.object_manager.get_local_player()
                    if player then
                        table.insert(_waypoints, player:get_position())
                        core.log("[NavLib Debug] Added waypoint #" .. #_waypoints)
                    end
                end

                local clicked_clear = render_button(window, colors, x + btn_w + 4, y_offset,
                    btn_w, btn_h, "Clear All")
                if clicked_clear then
                    _waypoints = {}
                    _nav_active = false
                    _nav_index = 0
                    if facade then facade:stop() end
                    core.log("[NavLib Debug] Cleared all waypoints")
                end

                y_offset = y_offset + btn_h + 4

                -- Button row 2: Go / Stop
                local tsp_on = menu.debug_tsp:get_state()
                local has_wps = #_waypoints > 0

                local clicked_go = render_button(window, colors, x, y_offset,
                    btn_w, btn_h, tsp_on and "Go (TSP)" or "Go", has_wps and not _nav_active)
                if clicked_go and facade and has_wps then
                    _nav_active = true
                    _nav_index = 1
                    if tsp_on then
                        facade:plan_route(_waypoints, function(success)
                            if not success then
                                core.log("[NavLib Debug] TSP route failed")
                                _nav_active = false
                            end
                        end)
                    else
                        facade:move_to(_waypoints[1], function(success)
                            if not success then
                                _nav_active = false
                            end
                        end)
                    end
                end

                local clicked_stop = render_button(window, colors, x + btn_w + 4, y_offset,
                    btn_w, btn_h, "Stop", _nav_active)
                if clicked_stop and facade then
                    facade:stop()
                    _nav_active = false
                    _nav_index = 0
                end

                y_offset = y_offset + btn_h + 4

                return y_offset
            end
        })

        -- TSP toggle (standard checkbox below waypoint controls)
        t:checkbox_grid({
            columns = 1,
            elements = {
                { element = menu.debug_tsp, label = "TSP Optimize Route",
                  tooltip = "Optimizes waypoint order using Travelling Salesman before navigating" },
            }
        })
    end)
end

---Sequential navigation update — call from Window.on_render()
function DebugTab.update(facade, menu)
    if not _nav_active or not facade or not menu then return end
    if menu.debug_tsp:get_state() then return end

    local state = facade:get_state()
    if state == "arrived" and _nav_index < #_waypoints then
        _nav_index = _nav_index + 1
        facade:move_to(_waypoints[_nav_index], function(success)
            if not success then
                core.log("[NavLib Debug] Failed to reach waypoint #" .. _nav_index)
                _nav_active = false
            end
        end)
    elseif state == "arrived" and _nav_index >= #_waypoints then
        core.log("[NavLib Debug] All waypoints reached!")
        _nav_active = false
    elseif state == "failed" then
        core.log("[NavLib Debug] Navigation failed at waypoint #" .. _nav_index)
        _nav_active = false
    end
end

return DebugTab
