--[[
    Obstacles Tab - Avoidance zones, probing, lookahead
]]

local vec2      = require("common/geometry/vector_2")
local enums     = require("common/enums")
local AstroUI   = require("shared/AstroUI")
local Defaults  = require("core/Defaults")

local LAYOUT = AstroUI.LAYOUT
local Dm = Defaults.movement
local Do = Defaults.obstacles

local ObstaclesTab = {}

---Register the obstacles tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function ObstaclesTab.register(ui, menu)
    local function proactive_on()
        return menu.proactive_obstacle:get_state()
    end

    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    ui:add_tab({ id = "obstacles", label = "Obstacles" }, function(t)
        -- Object Scanner
        t:checkbox_grid({
            label = "Object Scanner",
            columns = 1,
            elements = {
                { element = menu.scanner_enabled, label = "Scan Nearby Objects", tooltip = "Periodically scans for solid GameObjects and creates avoidance zones" },
            }
        })

        t:slider_list({
            visible_when = function() return menu.scanner_enabled:get_state() end,
            elements = {
                { element = menu.scanner_range,  label = "Scan Range",  suffix = " yd", tooltip = "How far to scan for objects" },
                { element = menu.scanner_buffer, label = "Buffer Size", suffix = " yd", tooltip = "Extra clearance around detected objects" },
            }
        })

        -- Object Scanner Advanced
        t:slider_list({
            label = "Scanner Tuning",
            visible_when = function() return show_advanced() and menu.scanner_enabled:get_state() end,
            elements = {
                { element = menu.scanner_interval,   label = "Scan Interval",   suffix = " s", tooltip = "Time between object scans" },
                { element = menu.scanner_min_radius,  label = "Min Object Size", suffix = " yd", tooltip = "Skip objects smaller than this bounding radius" },
                { element = menu.scanner_cost,        label = "Avoidance Cost",  tooltip = "Pathfinding cost penalty for scanned object areas" },
            }
        })

        -- Basic Obstacle Avoidance
        t:checkbox_grid({
            label = "Obstacle Avoidance",
            columns = 1,
            elements = {
                { element = menu.proactive_obstacle, label = "Proactive Scanning", tooltip = "Periodically scans the path ahead for obstacles" },
            }
        })

        t:slider_list({
            elements = {
                { element = menu.avoidance_radius, label = "Avoidance Radius", suffix = " yd", tooltip = "How wide to steer around detected obstacles" },
                { element = menu.max_zones, label = "Max Remembered Zones", tooltip = "Maximum number of obstacle zones tracked simultaneously" },
                { element = menu.zone_ttl, label = "Zone Expiry", suffix = " s", tooltip = "How long obstacle zones persist before being forgotten" },
            }
        })

        -- Scanning (advanced)
        t:slider_list({
            label = "Scanning",
            visible_when = function() return show_advanced() and proactive_on() end,
            elements = {
                { element = menu.obstacle_interval, label = "Scan Interval", suffix = " s", tooltip = "Time between proactive obstacle scans" },
            }
        })

        -- Costs (advanced)
        t:slider_list({
            label = "Costs",
            visible_when = show_advanced,
            elements = {
                { element = menu.avoidance_cost, label = "Avoidance Cost", tooltip = "Pathfinding cost penalty for obstacle-adjacent areas" },
                { element = menu.zone_prune, label = "Zone Prune Distance", suffix = " yd", tooltip = "Obstacle zones farther than this are removed" },
            }
        })

        -- Reactive Probing (advanced)
        t:slider_list({
            label = "Reactive Probing",
            visible_when = show_advanced,
            elements = {
                { element = menu.probe_distance, label = "Probe Distance", suffix = " yd", tooltip = "How far ahead to probe for reactive obstacle detection" },
                { element = menu.probe_spread, label = "Probe Spread", suffix = "\194\176", tooltip = "Angular width of the obstacle detection cone" },
                { element = menu.probe_height, label = "Probe Height", suffix = " yd", tooltip = "Vertical offset for obstacle probing rays" },
            }
        })

        -- Proactive Lookahead (advanced)
        t:slider_list({
            label = "Proactive Lookahead",
            visible_when = show_advanced,
            elements = {
                { element = menu.look_height, label = "Height Offset", suffix = " yd", tooltip = "Vertical offset for lookahead obstacle checks" },
                { element = menu.look_spread, label = "Spread Angle", suffix = "\194\176", tooltip = "Angular width of the proactive lookahead cone" },
                { element = menu.look_segments, label = "Segments to Check", tooltip = "Number of path segments to check ahead for obstacles" },
            }
        })

        -- Reset Defaults
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local w = window:get_size().x - (2 * LAYOUT.padding_side)
                local h = 22

                local label = "Reset Defaults"
                local btn_start = vec2.new(x, y_offset)
                local btn_end = vec2.new(x + w, y_offset + h)
                local hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
                window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

                local bg = hovered and colors.primary_accent or colors.slider_fill
                window:render_rect_filled(btn_start, btn_end, bg, 2)
                window:render_rect(btn_start, btn_end, colors.primary_accent, 2, 1.0)

                local text_size = window:get_text_size(label)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + (w - text_size.x) / 2, y_offset + (h - text_size.y) / 2),
                    colors.text_primary, label)

                if window:is_rect_clicked(btn_start, btn_end) then
                    Defaults.reset({
                        { menu.scanner_enabled,    Do.scanner_enabled },
                        { menu.scanner_interval,   Do.scanner_interval },
                        { menu.scanner_range,      Do.scanner_range },
                        { menu.scanner_buffer,     Do.scanner_buffer },
                        { menu.scanner_min_radius, Do.scanner_min_radius },
                        { menu.scanner_cost,       Do.scanner_cost },
                        { menu.proactive_obstacle, Dm.proactive_obstacle_check },
                        { menu.obstacle_interval,  Dm.proactive_obstacle_interval },
                        { menu.avoidance_radius,   Do.avoidance_radius },
                        { menu.max_zones,          Do.max_zones },
                        { menu.zone_ttl,           Do.zone_ttl },
                        { menu.avoidance_cost,     Do.avoidance_cost },
                        { menu.zone_prune,         Do.zone_prune_dist },
                        { menu.probe_distance,     Do.probe_distance },
                        { menu.probe_spread,       Do.probe_spread_deg },
                        { menu.probe_height,       Do.probe_height_offset },
                        { menu.look_height,        Do.lookahead_height_offset },
                        { menu.look_spread,        Do.lookahead_spread_deg },
                        { menu.look_segments,      Do.lookahead_segments },
                    })
                end

                return y_offset + h + 4
            end
        })
    end)
end

return ObstaclesTab
