--[[
    Movement Tab - Speed, tolerances, anti-detection, stuck recovery
    Apple HIG card-based design using AstroUI row_list widgets.
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
        t:row_list({
            label = "Speed",
            elements = {
                {
                    type = "toggle",
                    label = "Dynamic Speed",
                    element = menu.dynamic_speed,
                    tooltip = "Adjusts movement speed based on path curvature and terrain",
                },
            },
        })

        -- Tolerances
        t:row_list({
            label = "Tolerances",
            elements = {
                {
                    type = "stepper",
                    label = "Waypoint Tolerance",
                    element = menu.waypoint_tolerance,
                    min = M.waypoint_tolerance.min,
                    max = M.waypoint_tolerance.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Distance from waypoint before advancing to the next one",
                },
                {
                    type = "stepper",
                    label = "Final Tolerance",
                    element = menu.final_tolerance,
                    min = M.final_tolerance.min,
                    max = M.final_tolerance.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Distance from destination to consider arrival complete",
                },
            },
        })

        -- Anti-Detection
        t:row_list({
            label = "Anti-Detection",
            elements = {
                {
                    type = "toggle",
                    label = "Enable",
                    element = menu.anti_detection,
                    tooltip = "Adds slight random deviations to movement path",
                },
                {
                    type = "stepper",
                    label = "Max Deviation",
                    element = menu.max_deviation,
                    min = M.max_deviation.min,
                    max = M.max_deviation.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Maximum random offset from the path",
                    visible_when = anti_detection_on,
                },
            },
        })

        -- Dynamic Speed Tuning (advanced + dynamic speed on)
        t:row_list({
            label = "Dynamic Speed Tuning",
            visible_when = dynamic_speed_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Tolerance Scale",
                    element = menu.dyn_tol_scale,
                    min = M.dynamic_speed_max_tolerance_scale.min,
                    max = M.dynamic_speed_max_tolerance_scale.max,
                    step = 0.01,
                    decimals = 2,
                    suffix = "x",
                    tooltip = "Max tolerance multiplier at high speed",
                },
                {
                    type = "stepper",
                    label = "Tolerance Bonus",
                    element = menu.dyn_tol_bonus,
                    min = M.dynamic_speed_max_tolerance_bonus.min,
                    max = M.dynamic_speed_max_tolerance_bonus.max,
                    step = 0.05,
                    decimals = 2,
                    suffix = " yd",
                    tooltip = "Flat tolerance bonus at high speed",
                },
                {
                    type = "stepper",
                    label = "Z-Delta Threshold",
                    element = menu.dyn_ramp_z,
                    min = M.dynamic_speed_ramp_z_delta.min,
                    max = M.dynamic_speed_ramp_z_delta.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Z-change threshold for speed ramp",
                },
                {
                    type = "stepper",
                    label = "Ramp Tolerance",
                    element = menu.dyn_ramp_tol,
                    min = M.dynamic_speed_ramp_tolerance.min,
                    max = M.dynamic_speed_ramp_tolerance.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Tolerance ramp distance",
                },
                {
                    type = "stepper",
                    label = "Look Distance",
                    element = menu.dyn_ramp_look,
                    min = M.dynamic_speed_ramp_look_distance.min,
                    max = M.dynamic_speed_ramp_look_distance.max,
                    step = 0.5,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Lookahead distance for speed decisions",
                },
            },
        })

        -- Stuck Recovery (advanced)
        t:row_list({
            label = "Stuck Recovery",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Check Interval",
                    element = menu.stuck_interval,
                    min = M.stuck_check_interval.min,
                    max = M.stuck_check_interval.max,
                    step = 0.05,
                    decimals = 2,
                    suffix = " s",
                    tooltip = "How often to check if character is stuck",
                },
                {
                    type = "stepper",
                    label = "Min Distance",
                    element = menu.stuck_distance,
                    min = M.stuck_distance_min.min,
                    max = M.stuck_distance_min.max,
                    step = 0.05,
                    decimals = 2,
                    suffix = " yd",
                    tooltip = "Minimum distance to travel between stuck checks",
                },
                {
                    type = "stepper",
                    label = "Max Attempts",
                    element = menu.max_stuck,
                    min = M.max_stuck_attempts.min,
                    max = M.max_stuck_attempts.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "Number of stuck recoveries before aborting path",
                },
            },
        })

        -- Path Validation (advanced)
        t:row_list({
            label = "Path Validation",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Check Interval",
                    element = menu.path_check,
                    min = M.path_check_interval.min,
                    max = M.path_check_interval.max,
                    step = 0.5,
                    decimals = 1,
                    suffix = " s",
                    tooltip = "How often to revalidate the current path",
                },
                {
                    type = "stepper",
                    label = "Path Retries",
                    element = menu.path_req_retries,
                    min = M.path_request_max_retries.min,
                    max = M.path_request_max_retries.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "How many times to retry failed path requests before failing navigation",
                },
                {
                    type = "stepper",
                    label = "Repath Fail Budget",
                    element = menu.max_repath_failures,
                    min = M.max_repath_failures.min,
                    max = M.max_repath_failures.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "Max failed repath attempts before terminal failure",
                },
            },
        })

        -- Deviation Detection (advanced)
        t:row_list({
            label = "Deviation Detection",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Check Interval",
                    element = menu.deviation_check_interval,
                    min = M.deviation_check_interval.min,
                    max = M.deviation_check_interval.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " s",
                    tooltip = "Seconds between deviation checks",
                },
                {
                    type = "stepper",
                    label = "Lateral Threshold",
                    element = menu.deviation_threshold,
                    min = M.deviation_threshold.min,
                    max = M.deviation_threshold.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Yards off-path before repath (outdoor fallback)",
                },
                {
                    type = "stepper",
                    label = "Vertical Threshold",
                    element = menu.deviation_vertical_threshold,
                    min = M.deviation_vertical_threshold.min,
                    max = M.deviation_vertical_threshold.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Vertical offset before repath (wrong floor/level)",
                },
                {
                    type = "stepper",
                    label = "Corridor Factor",
                    element = menu.deviation_corridor_factor,
                    min = M.deviation_corridor_factor.min,
                    max = M.deviation_corridor_factor.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = "x",
                    tooltip = "Repath when drift exceeds this fraction of corridor width (indoor)",
                },
                {
                    type = "stepper",
                    label = "Repath Cooldown",
                    element = menu.repath_cooldown,
                    min = M.repath_cooldown.min,
                    max = M.repath_cooldown.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " s",
                    tooltip = "Minimum seconds between deviation repaths",
                },
                {
                    type = "stepper",
                    label = "Max Repaths",
                    element = menu.max_deviation_repaths,
                    min = M.max_deviation_repaths.min,
                    max = M.max_deviation_repaths.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "Max consecutive deviation repaths before giving up (resets on new path)",
                },
            },
        })

    end)
end

return MovementTab
