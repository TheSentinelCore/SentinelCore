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
    end)
end

return MovementTab
