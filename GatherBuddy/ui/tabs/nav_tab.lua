--[[
    Navigation Tab - TabBuilder configuration for navigation settings
    Uses combo_list, slider_list, and checkbox_grid widgets.
]]

local Constants = require("core/Constants")

local NavTab = {}

---Register the nav tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu_elements table Menu elements table
function NavTab.register(ui, menu_elements)
    -- Build smoothing algorithm options list
    local smoothing_names = {}
    for _, algo in ipairs(Constants.SMOOTHING_ALGORITHMS) do
        table.insert(smoothing_names, algo.name)
    end

    -- Visibility helpers
    local function smoothing_not_none()
        local idx = menu_elements.smoothing_combo:get()
        local algo = Constants.SMOOTHING_ALGORITHMS[idx]
        return algo and algo.id ~= "none"
    end

    local function smoothing_is_chaikin()
        local idx = menu_elements.smoothing_combo:get()
        local algo = Constants.SMOOTHING_ALGORITHMS[idx]
        return algo and algo.id == "chaikin"
    end

    local function smoothing_is_spline()
        local idx = menu_elements.smoothing_combo:get()
        local algo = Constants.SMOOTHING_ALGORITHMS[idx]
        return algo and (algo.id == "catmull_rom" or algo.id == "bezier")
    end

    local function anti_detection_on()
        return menu_elements.anti_detection_cb:get_state()
    end

    local function random_pauses_on()
        return menu_elements.anti_detection_cb:get_state() and menu_elements.random_pause_cb:get_state()
    end

    ui:add_tab({ id = "nav", label = "Nav" }, function(t)
        -- Basic movement
        t:slider_list({
            label = "Movement",
            elements = {
                { element = menu_elements.waypoint_tolerance_slider, label = "Waypoint Tolerance", suffix = " yd" },
                { element = menu_elements.mount_threshold_slider, label = "Mount Distance", suffix = " yd" },
            }
        })

        -- Path smoothing algorithm
        t:combo_list({
            label = "Path Smoothing",
            elements = {
                { element = menu_elements.smoothing_combo, label = "Algorithm", options = smoothing_names },
            }
        })

        -- Smoothing parameters (visible when not "none")
        t:slider_list({
            label = "Smoothing Params",
            visible_when = smoothing_not_none,
            elements = {
                { element = menu_elements.smooth_iterations_slider, label = "Iterations", visible_when = smoothing_is_chaikin },
                { element = menu_elements.smooth_samples_slider, label = "Samples", visible_when = smoothing_is_spline },
                { element = menu_elements.smooth_ratio_slider, label = "Corner-Cut Ratio", visible_when = smoothing_is_chaikin },
                { element = menu_elements.min_corner_angle_slider, label = "Min Corner Angle", suffix = "°", visible_when = smoothing_is_chaikin },
            }
        })

        t:checkbox_grid({
            visible_when = smoothing_is_chaikin,
            columns = 1,
            elements = {
                { element = menu_elements.keep_originals_cb, label = "Keep Original Waypoints" },
            }
        })

        -- Optimization
        t:checkbox_grid({
            label = "Optimization",
            columns = 1,
            elements = {
                { element = menu_elements.path_optimize_cb, label = "String-Pulling" },
            }
        })

        t:slider_list({
            label = "Area Costs",
            elements = {
                { element = menu_elements.filter_ground_slider, label = "Ground" },
                { element = menu_elements.filter_water_slider, label = "Water" },
                { element = menu_elements.filter_lava_slider, label = "Lava" },
            }
        })

        -- Indoor navigation
        t:checkbox_grid({
            label = "Indoor Navigation",
            columns = 1,
            elements = {
                { element = menu_elements.use_corridor_indoor_cb, label = "Corridor Pathfinding (Dungeons)" },
            }
        })

        -- Wall clearance
        t:checkbox_grid({
            label = "Wall Clearance",
            columns = 1,
            elements = {
                { element = menu_elements.wall_clearance_cb, label = "Enable" },
            }
        })

        t:slider_list({
            visible_when = function() return menu_elements.wall_clearance_cb:get_state() end,
            elements = {
                { element = menu_elements.wall_clearance_slider, label = "Distance", suffix = " yd" },
            }
        })

        -- Anti-detection
        t:checkbox_grid({
            label = "Anti-Detection",
            columns = 1,
            elements = {
                { element = menu_elements.anti_detection_cb, label = "Enable" },
                { element = menu_elements.random_pause_cb, label = "Random Pauses", visible_when = anti_detection_on },
                { element = menu_elements.random_jump_cb, label = "Random Jumps", visible_when = anti_detection_on },
            }
        })

        t:slider_list({
            visible_when = anti_detection_on,
            elements = {
                { element = menu_elements.max_deviation_slider, label = "Max Deviation", suffix = " yd" },
            }
        })

        t:slider_list({
            visible_when = random_pauses_on,
            elements = {
                { element = menu_elements.pause_interval_min_slider, label = "Pause Min", suffix = "s" },
                { element = menu_elements.pause_interval_max_slider, label = "Pause Max", suffix = "s" },
            }
        })
    end)
end

return NavTab
