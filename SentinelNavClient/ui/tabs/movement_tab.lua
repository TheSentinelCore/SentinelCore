--[[
    Movement Tab - Speed, tolerances, anti-detection, stuck recovery
]]

local Defaults = require("core/Defaults")

local MovementTab = {}

---Register the movement tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function MovementTab.register(ui, menu)
    local M = Defaults.movement

    -- Visibility helpers
    local function anti_detection_on()
        return menu.anti_detection:get_state()
    end

    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    local function dynamic_speed_advanced()
        return menu.dynamic_speed:get_state() and menu.show_advanced:get_state()
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
                { element = menu.waypoint_tolerance, label = "Waypoint", min = M.waypoint_tolerance.min, max = M.waypoint_tolerance.max, suffix = " yd", tooltip = "Distance from waypoint before advancing to the next one" },
                { element = menu.final_tolerance, label = "Final", min = M.final_tolerance.min, max = M.final_tolerance.max, suffix = " yd", tooltip = "Distance from destination to consider arrival complete" },
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
                { element = menu.max_deviation, label = "Max Deviation", min = M.max_deviation.min, max = M.max_deviation.max, suffix = " yd", tooltip = "Maximum random offset from the path" },
            }
        })

        -- Dynamic Speed Tuning (advanced + dynamic speed on)
        t:slider_list({
            label = "Dynamic Speed Tuning",
            visible_when = dynamic_speed_advanced,
            elements = {
                { element = menu.dyn_tol_scale, label = "Tolerance Scale", min = M.dynamic_speed_max_tolerance_scale.min, max = M.dynamic_speed_max_tolerance_scale.max, suffix = "x", tooltip = "Max tolerance multiplier at high speed" },
                { element = menu.dyn_tol_bonus, label = "Tolerance Bonus", min = M.dynamic_speed_max_tolerance_bonus.min, max = M.dynamic_speed_max_tolerance_bonus.max, suffix = " yd", tooltip = "Flat tolerance bonus at high speed" },
                { element = menu.dyn_ramp_z, label = "Z-Delta Threshold", min = M.dynamic_speed_ramp_z_delta.min, max = M.dynamic_speed_ramp_z_delta.max, suffix = " yd", tooltip = "Z-change threshold for speed ramp" },
                { element = menu.dyn_ramp_tol, label = "Ramp Tolerance", min = M.dynamic_speed_ramp_tolerance.min, max = M.dynamic_speed_ramp_tolerance.max, suffix = " yd", tooltip = "Tolerance ramp distance" },
                { element = menu.dyn_ramp_look, label = "Look Distance", min = M.dynamic_speed_ramp_look_distance.min, max = M.dynamic_speed_ramp_look_distance.max, suffix = " yd", tooltip = "Lookahead distance for speed decisions" },
            }
        })

        -- Stuck Recovery (advanced)
        t:slider_list({
            label = "Stuck Recovery",
            visible_when = show_advanced,
            elements = {
                { element = menu.stuck_interval, label = "Check Interval", min = M.stuck_check_interval.min, max = M.stuck_check_interval.max, suffix = " s", tooltip = "How often to check if character is stuck" },
                { element = menu.stuck_distance, label = "Min Distance", min = M.stuck_distance_min.min, max = M.stuck_distance_min.max, suffix = " yd", tooltip = "Minimum distance to travel between stuck checks" },
                { element = menu.max_stuck, label = "Max Attempts", min = M.max_stuck_attempts.min, max = M.max_stuck_attempts.max, tooltip = "Number of stuck recoveries before aborting path" },
            }
        })

        -- Path Validation (advanced)
        t:slider_list({
            label = "Path Validation",
            visible_when = show_advanced,
            elements = {
                { element = menu.path_check, label = "Check Interval", min = M.path_check_interval.min, max = M.path_check_interval.max, suffix = " s", tooltip = "How often to revalidate the current path" },
            }
        })

        -- Deviation Detection (advanced)
        t:slider_list({
            label = "Deviation Detection",
            visible_when = show_advanced,
            elements = {
                { element = menu.deviation_check_interval, label = "Check Interval", min = M.deviation_check_interval.min, max = M.deviation_check_interval.max, suffix = " s", tooltip = "Seconds between deviation checks" },
                { element = menu.deviation_threshold, label = "Lateral Threshold", min = M.deviation_threshold.min, max = M.deviation_threshold.max, suffix = " yd", tooltip = "Yards off-path before repath (outdoor fallback)" },
                { element = menu.deviation_vertical_threshold, label = "Vertical Threshold", min = M.deviation_vertical_threshold.min, max = M.deviation_vertical_threshold.max, suffix = " yd", tooltip = "Vertical offset before repath (wrong floor/level)" },
                { element = menu.deviation_corridor_factor, label = "Corridor Factor", min = M.deviation_corridor_factor.min, max = M.deviation_corridor_factor.max, suffix = "x", tooltip = "Repath when drift exceeds this fraction of corridor width (indoor)" },
                { element = menu.repath_cooldown, label = "Repath Cooldown", min = M.repath_cooldown.min, max = M.repath_cooldown.max, suffix = " s", tooltip = "Minimum seconds between deviation repaths" },
                { element = menu.max_deviation_repaths, label = "Max Repaths", min = M.max_deviation_repaths.min, max = M.max_deviation_repaths.max, tooltip = "Max consecutive deviation repaths before giving up (resets on new path)" },
            }
        })

    end)
end

return MovementTab
