--[[
    Debug Tab - Live status, logging, waypoint testing, all pathfinding modes
]]

local vec2    = require("common/geometry/vector_2")
local enums   = require("common/enums")
local AstroUI = require("shared/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local DebugTab = {}

-- Module-level state
local _waypoints = {}
local _nav_active = false
local _nav_index = 0
local _last_result = nil

-- Mode definitions (1-based, combobox value + 1)
local MODES = {
    { name = "Move To",       btn = "Go",              min_wps = 1, sequential = true,  query = false },
    { name = "Move Direct",   btn = "Go (Direct)",     min_wps = 1, sequential = true,  query = false },
    { name = "TSP Route",     btn = "Go (TSP)",        min_wps = 2, sequential = false, query = false },
    { name = "Multi-stop",    btn = "Go (Multi)",      min_wps = 2, sequential = false, query = false },
    { name = "Corridor Path", btn = "Go (Corridor)",   min_wps = 1, sequential = false, query = false },
    { name = "Path + Avoid",  btn = "Go (Avoid)",      min_wps = 1, sequential = false, query = false },
    { name = "Flee",          btn = "Go (Flee)",       min_wps = 1, sequential = false, query = false },
    { name = "Kite",          btn = "Go (Kite)",       min_wps = 1, sequential = false, query = false },
    { name = "Random Point",  btn = "Go (Random)",     min_wps = 0, sequential = false, query = false },
    { name = "Raycast",       btn = "Query",           min_wps = 1, sequential = false, query = true  },
    { name = "Validate",      btn = "Query",           min_wps = 1, sequential = false, query = true  },
    { name = "Get Height",    btn = "Query",           min_wps = 0, sequential = false, query = true  },
    { name = "Health Check",  btn = "Query",           min_wps = 0, sequential = false, query = true  },
}

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

--------------------------------------------------------------------------------
-- Go button dispatch for all 13 modes
--------------------------------------------------------------------------------

local function dispatch_go(mode_idx, facade, waypoints)
    local mode = MODES[mode_idx]
    if not mode or not facade then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end
    local player_pos = player:get_position()

    local nav_client = facade.nav_client

    -- Shared failure callback for navigation modes
    local function nav_callback(success, reason)
        if not success then
            core.log("[NavLib Debug] " .. mode.name .. " failed: " .. tostring(reason))
            _nav_active = false
        end
    end

    -- Shared callback for raw-path modes (nav_client → follow_path)
    local function raw_path_callback(ok, data, err)
        if not ok or not data then
            _last_result = "ERROR: " .. tostring(err)
            core.log("[NavLib Debug] " .. mode.name .. " failed: " .. tostring(err))
            _nav_active = false
            return
        end
        local wps = data.waypoints
        if not wps or #wps == 0 then
            _last_result = "Empty path returned"
            _nav_active = false
            return
        end
        local dist = data.distance or data.total_distance or 0
        _last_result = string.format("%s: %d wps, %.0f yd", mode.name, #wps, dist)
        facade:follow_path(wps, nav_callback)
    end

    -- Reset state
    facade:stop()
    _last_result = nil

    -- Query modes don't set _nav_active
    if mode.query then
        _nav_active = false
    else
        _nav_active = true
        _nav_index = 1
    end

    -- Build opts once for modes that call nav_client directly
    local path_opts = facade:get_path_opts()

    -- ===== Navigation modes =====
    if mode_idx == 1 then
        -- Move To (sequential)
        facade:move_to(waypoints[1], nav_callback)

    elseif mode_idx == 2 then
        -- Move Direct (sequential, no pathfinding)
        facade:move_direct(waypoints[1], nav_callback)

    elseif mode_idx == 3 then
        -- TSP Route
        facade:plan_route(waypoints, function(success)
            if not success then
                core.log("[NavLib Debug] TSP route failed")
                _nav_active = false
            end
        end)

    elseif mode_idx == 4 then
        -- Multi-stop (ordered, prepend player as first stop)
        local stops = { player_pos }
        for _, wp in ipairs(waypoints) do
            stops[#stops + 1] = wp
        end
        nav_client:find_route_multi(stops, raw_path_callback, path_opts)

    elseif mode_idx == 5 then
        -- Corridor Path
        nav_client:find_path_corridor(player_pos, waypoints[1], raw_path_callback, facade:get_corridor_opts())

    elseif mode_idx == 6 then
        -- Path + Avoid (uses current obstacle zones)
        local zones = facade.obstacle and facade.obstacle:get_avoidance_zones() or {}
        nav_client:find_path_avoid(player_pos, waypoints[1], zones, raw_path_callback, path_opts)

    elseif mode_idx == 7 then
        -- Flee (waypoints are threat positions)
        nav_client:flee(player_pos, waypoints, raw_path_callback, path_opts)

    elseif mode_idx == 8 then
        -- Kite (arc around waypoint 1)
        nav_client:kite(player_pos, waypoints[1], raw_path_callback, facade:get_path_opts({ kite_radius = 8.0 }))

    elseif mode_idx == 9 then
        -- Random Point → navigate to it
        nav_client:random_point(function(ok, data, err)
            if not ok or not data or not data.point then
                _last_result = "ERROR: " .. tostring(err)
                _nav_active = false
                return
            end
            _last_result = string.format("Random: %.0f, %.0f, %.0f",
                data.point.x, data.point.y, data.point.z)
            facade:move_to(data.point, nav_callback)
        end)

    -- ===== Query modes =====
    elseif mode_idx == 10 then
        -- Raycast (LoS test)
        nav_client:raycast(player_pos, waypoints[1], function(ok, data, err)
            if not ok then
                _last_result = "Raycast ERROR: " .. tostring(err)
                return
            end
            if data.hit then
                _last_result = string.format("HIT at %.1f, %.1f, %.1f (t=%.2f)",
                    data.hit_position.x, data.hit_position.y, data.hit_position.z, data.t)
            else
                _last_result = "CLEAR (no obstruction)"
            end
        end)

    elseif mode_idx == 11 then
        -- Validate destination
        facade:validate_destination(waypoints[1], function(reachable, reason, distance)
            if reachable then
                _last_result = string.format("REACHABLE (%.1f yd)", distance or 0)
            else
                _last_result = "UNREACHABLE: " .. tostring(reason)
            end
        end)

    elseif mode_idx == 12 then
        -- Get Height
        nav_client:get_height(player_pos, function(ok, data, err)
            if not ok then
                _last_result = "Height ERROR: " .. tostring(err)
                return
            end
            _last_result = string.format("Navmesh: %.2f | Player Z: %.2f",
                data.height, player_pos.z)
        end)

    elseif mode_idx == 13 then
        -- Health Check
        facade:health_check(function(ok, data, err)
            if not ok then
                _last_result = "Health ERROR: " .. tostring(err)
                return
            end
            local maps = data.loaded_maps and #data.loaded_maps or 0
            _last_result = string.format("%s | v%s | Up: %ds | Maps: %d",
                tostring(data.status), tostring(data.version),
                data.uptime_secs or 0, maps)
        end)
    end
end

--------------------------------------------------------------------------------
-- Tab registration
--------------------------------------------------------------------------------

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

        -- Visualization Toggles
        t:checkbox_grid({
            label = "Visualization",
            columns = 2,
            elements = {
                { element = menu.viz_master,      label = "Enable 3D Overlay",
                  tooltip = "Master toggle for all in-world 3D visualization" },
                { element = menu.viz_path,        label = "Path + Waypoints",
                  tooltip = "Show path lines and waypoint markers in-world" },
                { element = menu.viz_destination,  label = "Destination",
                  tooltip = "Show circle and distance text at final destination" },
                { element = menu.viz_obstacles,    label = "Obstacle Zones",
                  tooltip = "Show avoidance zone circles around detected obstacles" },
                { element = menu.viz_corridor,     label = "Corridor Bounds",
                  tooltip = "Show corridor width boundaries when indoors" },
                { element = menu.viz_state,        label = "State Indicators",
                  tooltip = "Show stuck/requesting/arrived/failed indicators" },
            }
        })

        -- Avoid Zones (custom rendered)
        t:custom_render({
            render_fn = function(self, y_offset)
                if not facade then return y_offset end
                local obstacle = facade.obstacle
                if not obstacle then return y_offset end

                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local window_size = window:get_size()
                local content_width = window_size.x - (2 * LAYOUT.padding_side)
                local btn_w = (content_width - 4) / 2
                local btn_h = 20

                -- Section label with count
                local zones = obstacle:get_avoidance_zones()
                local header = "Avoid Zones (" .. #zones .. ")"
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.primary_accent, header)
                y_offset = y_offset + window:get_text_size(header).y + 4

                -- Zone list with inline remove buttons
                for i, zone in ipairs(zones) do
                    local zone_text = string.format("#%d: %.0f, %.0f, %.0f (r=%.1f)",
                        i, zone.x, zone.y, zone.z, zone.radius)
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, zone_text)

                    -- Per-zone remove button
                    local rm_w = 16
                    local rm_x = x + content_width - rm_w
                    local rm_start = vec2.new(rm_x, y_offset)
                    local rm_end = vec2.new(rm_x + rm_w, y_offset + 14)
                    window:is_mouse_hovering_rect_block_movement(rm_start, rm_end)
                    if window:is_rect_clicked(rm_start, rm_end) then
                        obstacle:remove_zone(i)
                    end
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(rm_x + 3, y_offset), colors.text_secondary, "X")

                    y_offset = y_offset + 16
                end

                if #zones == 0 then
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, "(no zones)")
                    y_offset = y_offset + 16
                end

                y_offset = y_offset + 4

                -- Button row: Add Zone Here / Clear Zones
                local clicked_add_zone = render_button(window, colors, x, y_offset,
                    btn_w, btn_h, "Add Zone Here")
                if clicked_add_zone then
                    local player = core.object_manager.get_local_player()
                    if player then
                        obstacle:add_zone(player:get_position())
                        core.log("[NavLib Debug] Added avoid zone at player position")
                    end
                end

                local clicked_clear_zones = render_button(window, colors, x + btn_w + 4, y_offset,
                    btn_w, btn_h, "Clear Zones", #zones > 0)
                if clicked_clear_zones then
                    obstacle:clear()
                    core.log("[NavLib Debug] Cleared all avoid zones")
                end

                y_offset = y_offset + btn_h + 4

                return y_offset + 4
            end
        })

        -- Waypoint Management + Mode Selector (custom rendered)
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

                -- Mode selector (click-to-cycle)
                local mode_idx = menu.debug_mode:get() + 1
                if mode_idx < 1 or mode_idx > #MODES then mode_idx = 1 end
                local mode = MODES[mode_idx]

                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_primary, "Mode")
                local box_x = x + 40
                local box_w = content_width - 40
                local box_h = 18
                local box_start = vec2.new(box_x, y_offset)
                local box_end = vec2.new(box_x + box_w, y_offset + box_h)
                local box_hovered = window:is_mouse_hovering_rect(box_start, box_end)
                window:is_mouse_hovering_rect_block_movement(box_start, box_end)

                local box_bg = box_hovered and colors.slider_fill or colors.slider_bg
                window:render_rect_filled(box_start, box_end, box_bg, 2)
                window:render_rect(box_start, box_end, colors.primary_accent, 2, 1.0)

                local mode_text = mode.name
                local mode_size = window:get_text_size(mode_text)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(box_x + (box_w - mode_size.x) / 2,
                             y_offset + (box_h - mode_size.y) / 2),
                    colors.text_primary, mode_text)

                if window:is_rect_clicked(box_start, box_end) then
                    menu.debug_mode:set(mode_idx % #MODES)  -- cycles 0..12
                end

                y_offset = y_offset + box_h + 6

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
                    _last_result = nil
                    if facade then facade:stop() end
                    core.log("[NavLib Debug] Cleared all waypoints")
                end

                y_offset = y_offset + btn_h + 4

                -- Button row 2: Go / Stop
                local has_enough = #_waypoints >= mode.min_wps
                local go_enabled = has_enough and (mode.query or not _nav_active)

                local clicked_go = render_button(window, colors, x, y_offset,
                    btn_w, btn_h, mode.btn, go_enabled)
                if clicked_go and facade then
                    dispatch_go(mode_idx, facade, _waypoints)
                end

                local clicked_stop = render_button(window, colors, x + btn_w + 4, y_offset,
                    btn_w, btn_h, "Stop", _nav_active)
                if clicked_stop and facade then
                    facade:stop()
                    _nav_active = false
                    _nav_index = 0
                end

                y_offset = y_offset + btn_h + 4

                -- Result display
                if _last_result then
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.secondary_accent, "Result:")
                    y_offset = y_offset + 14
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, _last_result)
                    y_offset = y_offset + window:get_text_size(_last_result).y + 4
                end

                return y_offset
            end
        })
    end)
end

--------------------------------------------------------------------------------
-- Sequential navigation update — call from Window.on_render()
--------------------------------------------------------------------------------

function DebugTab.update(facade, menu)
    if not _nav_active or not facade or not menu then return end

    local mode_idx = menu.debug_mode:get() + 1
    if mode_idx < 1 or mode_idx > #MODES then return end
    if not MODES[mode_idx].sequential then return end

    local state = facade:get_state()
    if state == "arrived" and _nav_index < #_waypoints then
        _nav_index = _nav_index + 1
        local cb = function(success)
            if not success then
                core.log("[NavLib Debug] Failed at waypoint #" .. _nav_index)
                _nav_active = false
            end
        end
        if mode_idx == 1 then
            facade:move_to(_waypoints[_nav_index], cb)
        elseif mode_idx == 2 then
            facade:move_direct(_waypoints[_nav_index], cb)
        end
    elseif state == "arrived" and _nav_index >= #_waypoints then
        core.log("[NavLib Debug] All waypoints reached!")
        _nav_active = false
    elseif state == "failed" then
        core.log("[NavLib Debug] Navigation failed at waypoint #" .. _nav_index)
        _nav_active = false
    end
end

return DebugTab
