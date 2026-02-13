--[[
    Obstacles Tab - Avoidance zones, probing, lookahead
]]

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
        -- Basic Obstacle Avoidance
        t:checkbox_grid({
            label = "Obstacle Avoidance",
            columns = 1,
            elements = {
                { element = menu.proactive_obstacle, label = "Proactive Scanning" },
            }
        })

        t:slider_list({
            elements = {
                { element = menu.avoidance_radius, label = "Avoidance Radius", suffix = " yd" },
                { element = menu.max_zones, label = "Max Remembered Zones" },
                { element = menu.zone_ttl, label = "Zone Expiry", suffix = " s" },
            }
        })

        -- Scanning (advanced)
        t:slider_list({
            label = "Scanning",
            visible_when = function() return show_advanced() and proactive_on() end,
            elements = {
                { element = menu.obstacle_interval, label = "Scan Interval", suffix = " s" },
            }
        })

        -- Costs (advanced)
        t:slider_list({
            label = "Costs",
            visible_when = show_advanced,
            elements = {
                { element = menu.avoidance_cost, label = "Avoidance Cost" },
                { element = menu.zone_prune, label = "Zone Prune Distance", suffix = " yd" },
            }
        })

        -- Reactive Probing (advanced)
        t:slider_list({
            label = "Reactive Probing",
            visible_when = show_advanced,
            elements = {
                { element = menu.probe_distance, label = "Probe Distance", suffix = " yd" },
                { element = menu.probe_spread, label = "Probe Spread", suffix = "\194\176" },
                { element = menu.probe_height, label = "Probe Height", suffix = " yd" },
            }
        })

        -- Proactive Lookahead (advanced)
        t:slider_list({
            label = "Proactive Lookahead",
            visible_when = show_advanced,
            elements = {
                { element = menu.look_height, label = "Height Offset", suffix = " yd" },
                { element = menu.look_spread, label = "Spread Angle", suffix = "\194\176" },
                { element = menu.look_segments, label = "Segments to Check" },
            }
        })
    end)
end

return ObstaclesTab
