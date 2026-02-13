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
                { element = menu.smoothing, label = "Algorithm", options = SMOOTHING_NAMES, tooltip = "Chaikin for sharp turns, Catmull-Rom/Bezier for smooth curves" },
            }
        })

        -- Smoothing Params (conditional on algorithm)
        t:slider_list({
            label = "Smoothing Params",
            visible_when = smoothing_not_none,
            elements = {
                { element = menu.smooth_iterations, label = "Iterations", min = 1, max = 5, visible_when = smoothing_is_chaikin, tooltip = "More iterations produce smoother paths but may overshoot corners" },
                { element = menu.smooth_samples, label = "Samples", min = 5, max = 50, visible_when = smoothing_is_spline, tooltip = "Number of interpolation points per path segment" },
                { element = menu.smooth_ratio, label = "Corner-Cut Ratio", suffix = "%", min = 50, max = 95, visible_when = smoothing_is_chaikin, tooltip = "How aggressively corners are cut \xe2\x80\x94 higher values cut more" },
                { element = menu.corner_angle, label = "Min Corner Angle", suffix = "\194\176", visible_when = smoothing_is_chaikin, tooltip = "Corners sharper than this are preserved during smoothing" },
            }
        })

        t:checkbox_grid({
            visible_when = smoothing_not_none,
            columns = 1,
            elements = {
                { element = menu.keep_originals, label = "Keep Original Waypoints", tooltip = "Retains original path points alongside smoothed points" },
            }
        })

        -- Optimization
        t:checkbox_grid({
            label = "Optimization",
            columns = 1,
            elements = {
                { element = menu.optimize, label = "String-Pulling", tooltip = "Removes unnecessary waypoints by testing line-of-sight" },
                { element = menu.allow_partial, label = "Allow Partial Paths", tooltip = "Accept incomplete paths when a full path is unavailable" },
            }
        })

        -- Terrain Costs
        t:slider_list({
            label = "Terrain Costs",
            elements = {
                { element = menu.filter_ground, label = "Ground", tooltip = "Pathfinding cost multiplier for ground terrain" },
                { element = menu.filter_water, label = "Water", tooltip = "Pathfinding cost multiplier \xe2\x80\x94 higher values avoid water" },
                { element = menu.filter_lava, label = "Lava", tooltip = "Pathfinding cost multiplier \xe2\x80\x94 higher values avoid lava" },
            }
        })

        -- Indoor
        t:checkbox_grid({
            label = "Indoor Navigation",
            columns = 1,
            elements = {
                { element = menu.corridor, label = "Corridor Pathfinding", tooltip = "Uses tighter pathfinding for indoor and corridor areas" },
            }
        })

        t:slider_list({
            visible_when = function() return corridor_on() and show_advanced() end,
            elements = {
                { element = menu.corridor_probe, label = "Probe Distance", suffix = " yd", tooltip = "How far ahead to probe for corridor detection" },
            }
        })

        -- Wall Clearance
        t:checkbox_grid({
            label = "Wall Clearance",
            columns = 1,
            elements = {
                { element = menu.wall_clearance_en, label = "Enable", tooltip = "Pushes path away from walls by the specified distance" },
            }
        })

        t:slider_list({
            visible_when = wall_clearance_on,
            elements = {
                { element = menu.wall_clearance, label = "Distance", suffix = " yd", tooltip = "Minimum distance to maintain from walls" },
            }
        })
    end)
end

--- Smoothing IDs exposed for sync
PathfindingTab.SMOOTHING_IDS = SMOOTHING_IDS

return PathfindingTab
