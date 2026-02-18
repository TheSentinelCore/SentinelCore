--[[
    Pathfinding Tab - Smoothing, optimization, terrain costs, indoor, wall clearance
]]

local PathfindingTab = {}

---Register the pathfinding tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function PathfindingTab.register(ui, menu)
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
        t:checkbox_grid({
            label = "Path Smoothing",
            columns = 1,
            elements = {
                { element = menu.smoothing, label = "Enable Path Smoothing", tooltip = "Smooths navmesh paths for more natural movement" },
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

        -- Indoor Navigation (always visible)
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

        -- Terrain Costs (advanced)
        t:slider_list({
            label = "Terrain Costs",
            visible_when = show_advanced,
            elements = {
                { element = menu.filter_ground, label = "Ground", tooltip = "Pathfinding cost multiplier for ground terrain" },
                { element = menu.filter_water, label = "Water", tooltip = "Pathfinding cost multiplier \xe2\x80\x94 higher values avoid water" },
                { element = menu.filter_lava, label = "Lava", tooltip = "Pathfinding cost multiplier \xe2\x80\x94 higher values avoid lava" },
            }
        })

    end)
end

return PathfindingTab
