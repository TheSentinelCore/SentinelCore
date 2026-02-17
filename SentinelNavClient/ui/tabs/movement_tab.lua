--[[
    Movement Tab - Speed, tolerances, anti-detection, stuck recovery
]]

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

        -- Dynamic Speed Tuning (advanced + dynamic speed on)
        t:slider_list({
            label = "Dynamic Speed Tuning",
            visible_when = dynamic_speed_advanced,
            elements = {
                { element = menu.dyn_tol_scale, label = "Tolerance Scale", suffix = "x", tooltip = "Max tolerance multiplier at high speed" },
                { element = menu.dyn_tol_bonus, label = "Tolerance Bonus", suffix = " yd", tooltip = "Flat tolerance bonus at high speed" },
                { element = menu.dyn_ramp_z, label = "Z-Delta Threshold", suffix = " yd", tooltip = "Z-change threshold for speed ramp" },
                { element = menu.dyn_ramp_tol, label = "Ramp Tolerance", suffix = " yd", tooltip = "Tolerance ramp distance" },
                { element = menu.dyn_ramp_look, label = "Look Distance", suffix = " yd", tooltip = "Lookahead distance for speed decisions" },
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

    end)
end

return MovementTab
