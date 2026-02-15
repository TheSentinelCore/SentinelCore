--[[
    Movement Tab - Speed, tolerances, anti-detection, stuck recovery
]]

local vec2      = require("common/geometry/vector_2")
local enums     = require("common/enums")
local AstroUI   = require("shared/AstroUI")
local Defaults  = require("core/Defaults")

local LAYOUT = AstroUI.LAYOUT
local D = Defaults.movement

local MovementTab = {}

---Register the movement tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function MovementTab.register(ui, menu)
    -- Visibility helpers
    local function anti_detection_on()
        return menu.anti_detection:get_state()
    end

    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    ui:add_tab({ id = "movement", label = "Movement" }, function(t)
        -- Speed
        t:checkbox_grid({
            label = "Speed",
            columns = 1,
            elements = {
                { element = menu.dynamic_speed, label = "Dynamic Speed", tooltip = "Adjusts movement speed based on path curvature and terrain" },
            }
        })

        -- Tolerances
        t:slider_list({
            label = "Tolerances",
            elements = {
                { element = menu.waypoint_tolerance, label = "Waypoint", suffix = " yd", tooltip = "Distance from waypoint before advancing to the next one" },
                { element = menu.final_tolerance, label = "Final", suffix = " yd", tooltip = "Distance from destination to consider arrival complete" },
            }
        })

        -- Anti-Detection
        t:checkbox_grid({
            label = "Anti-Detection",
            columns = 1,
            elements = {
                { element = menu.anti_detection, label = "Enable", tooltip = "Adds slight random deviations to movement path" },
            }
        })

        t:slider_list({
            visible_when = anti_detection_on,
            elements = {
                { element = menu.max_deviation, label = "Max Deviation", suffix = " yd", tooltip = "Maximum random offset from the path" },
            }
        })

        -- Stuck Recovery (advanced)
        t:slider_list({
            label = "Stuck Recovery",
            visible_when = show_advanced,
            elements = {
                { element = menu.stuck_interval, label = "Check Interval", suffix = " s", tooltip = "How often to check if character is stuck" },
                { element = menu.stuck_distance, label = "Min Distance", suffix = " yd", tooltip = "Minimum distance to travel between stuck checks" },
                { element = menu.max_stuck, label = "Max Attempts", tooltip = "Number of stuck recoveries before aborting path" },
            }
        })

        -- Path Validation (advanced)
        t:slider_list({
            label = "Path Validation",
            visible_when = show_advanced,
            elements = {
                { element = menu.path_check, label = "Check Interval", suffix = " s", tooltip = "How often to revalidate the current path" },
            }
        })

        -- Deviation Detection (advanced)
        t:slider_list({
            label = "Deviation Detection",
            visible_when = show_advanced,
            elements = {
                { element = menu.deviation_check_interval, label = "Check Interval", suffix = " s", tooltip = "Seconds between deviation checks" },
                { element = menu.deviation_threshold, label = "Lateral Threshold", suffix = " yd", tooltip = "Yards off-path before repath (outdoor fallback)" },
                { element = menu.deviation_vertical_threshold, label = "Vertical Threshold", suffix = " yd", tooltip = "Vertical offset before repath (wrong floor/level)" },
                { element = menu.deviation_corridor_factor, label = "Corridor Factor", suffix = "x", tooltip = "Repath when drift exceeds this fraction of corridor width (indoor)" },
                { element = menu.repath_cooldown, label = "Repath Cooldown", suffix = " s", tooltip = "Minimum seconds between deviation repaths" },
                { element = menu.max_deviation_repaths, label = "Max Repaths", tooltip = "Max consecutive deviation repaths before giving up (resets on new path)" },
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
                        { menu.dynamic_speed,               D.dynamic_speed },
                        { menu.waypoint_tolerance,          D.waypoint_tolerance },
                        { menu.final_tolerance,             D.final_tolerance },
                        { menu.anti_detection,              D.anti_detection },
                        { menu.max_deviation,               D.max_deviation },
                        { menu.stuck_interval,              D.stuck_check_interval },
                        { menu.stuck_distance,              D.stuck_distance_min },
                        { menu.max_stuck,                   D.max_stuck_attempts },
                        { menu.path_check,                  D.path_check_interval },
                        { menu.deviation_check_interval,    D.deviation_check_interval },
                        { menu.deviation_threshold,         D.deviation_threshold },
                        { menu.deviation_vertical_threshold,D.deviation_vertical_threshold },
                        { menu.deviation_corridor_factor,   D.deviation_corridor_factor },
                        { menu.repath_cooldown,             D.repath_cooldown },
                        { menu.max_deviation_repaths,       D.max_deviation_repaths },
                    })
                end

                return y_offset + h + 4
            end
        })
    end)
end

return MovementTab
