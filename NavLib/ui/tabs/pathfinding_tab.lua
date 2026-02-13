--[[
    Pathfinding Tab - Smoothing, optimization, terrain costs, indoor, wall clearance
]]

local PathfindingTab = {}

-- Smoothing algorithm names (combo options) — order matches NavBuddy API
local SMOOTHING_NAMES = { "None", "Chaikin", "Catmull-Rom", "Bezier" }
local SMOOTHING_IDS   = { "none", "chaikin", "catmull_rom", "bezier" }

---Register the pathfinding tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function PathfindingTab.register(ui, menu)
    -- Visibility helpers
    local function smoothing_not_none()
        local idx = menu.smoothing:get()
        return idx > 1
    end

    local function smoothing_is_chaikin()
        local idx = menu.smoothing:get()
        return idx == 2
    end

    local function smoothing_is_spline()
        local idx = menu.smoothing:get()
        return idx == 3 or idx == 4
    end

    local function corridor_on()
        return menu.corridor:get_state()
    end

    local function wall_clearance_on()
        return menu.wall_clearance_en:get_state()
    end

    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    ui:add_tab({ id = "pathfinding", label = "Pathfinding" }, function(t)
        -- Path Smoothing
        t:combo_list({
            label = "Path Smoothing",
            elements = {
                { element = menu.smoothing, label = "Algorithm", options = SMOOTHING_NAMES },
            }
        })

        -- Smoothing Params (conditional on algorithm)
        t:slider_list({
            label = "Smoothing Params",
            visible_when = smoothing_not_none,
            elements = {
                { element = menu.smooth_iterations, label = "Iterations", visible_when = smoothing_is_chaikin },
                { element = menu.smooth_samples, label = "Samples", visible_when = smoothing_is_spline },
                { element = menu.smooth_ratio, label = "Corner-Cut Ratio", visible_when = smoothing_is_chaikin },
                { element = menu.corner_angle, label = "Min Corner Angle", suffix = "\194\176", visible_when = smoothing_is_chaikin },
            }
        })

        t:checkbox_grid({
            visible_when = smoothing_not_none,
            columns = 1,
            elements = {
                { element = menu.keep_originals, label = "Keep Original Waypoints" },
            }
        })

        -- Optimization
        t:checkbox_grid({
            label = "Optimization",
            columns = 1,
            elements = {
                { element = menu.optimize, label = "String-Pulling" },
                { element = menu.allow_partial, label = "Allow Partial Paths" },
            }
        })

        -- Terrain Costs
        t:slider_list({
            label = "Terrain Costs",
            elements = {
                { element = menu.filter_ground, label = "Ground" },
                { element = menu.filter_water, label = "Water" },
                { element = menu.filter_lava, label = "Lava" },
            }
        })

        -- Indoor
        t:checkbox_grid({
            label = "Indoor Navigation",
            columns = 1,
            elements = {
                { element = menu.corridor, label = "Corridor Pathfinding" },
            }
        })

        t:slider_list({
            visible_when = function() return corridor_on() and show_advanced() end,
            elements = {
                { element = menu.corridor_probe, label = "Probe Distance", suffix = " yd" },
            }
        })

        -- Wall Clearance
        t:checkbox_grid({
            label = "Wall Clearance",
            columns = 1,
            elements = {
                { element = menu.wall_clearance_en, label = "Enable" },
            }
        })

        t:slider_list({
            visible_when = wall_clearance_on,
            elements = {
                { element = menu.wall_clearance, label = "Distance", suffix = " yd" },
            }
        })
    end)
end

--- Smoothing IDs exposed for sync
PathfindingTab.SMOOTHING_IDS = SMOOTHING_IDS

return PathfindingTab
