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
                { element = menu.proactive_obstacle, label = "Proactive Scanning", tooltip = "Periodically scans the path ahead for obstacles" },
            }
        })

        t:slider_list({
            elements = {
                { element = menu.avoidance_radius, label = "Avoidance Radius", suffix = " yd", tooltip = "How wide to steer around detected obstacles" },
                { element = menu.max_zones, label = "Max Remembered Zones", tooltip = "Maximum number of obstacle zones tracked simultaneously" },
                { element = menu.zone_ttl, label = "Zone Expiry", suffix = " s", tooltip = "How long obstacle zones persist before being forgotten" },
            }
        })

        -- Scanning (advanced)
        t:slider_list({
            label = "Scanning",
            visible_when = function() return show_advanced() and proactive_on() end,
            elements = {
                { element = menu.obstacle_interval, label = "Scan Interval", suffix = " s", tooltip = "Time between proactive obstacle scans" },
            }
        })

        -- Costs (advanced)
        t:slider_list({
            label = "Costs",
            visible_when = show_advanced,
            elements = {
                { element = menu.avoidance_cost, label = "Avoidance Cost", tooltip = "Pathfinding cost penalty for obstacle-adjacent areas" },
                { element = menu.zone_prune, label = "Zone Prune Distance", suffix = " yd", tooltip = "Obstacle zones farther than this are removed" },
            }
        })

        -- Reactive Probing (advanced)
        t:slider_list({
            label = "Reactive Probing",
            visible_when = show_advanced,
            elements = {
                { element = menu.probe_distance, label = "Probe Distance", suffix = " yd", tooltip = "How far ahead to probe for reactive obstacle detection" },
                { element = menu.probe_spread, label = "Probe Spread", suffix = "\194\176", tooltip = "Angular width of the obstacle detection cone" },
                { element = menu.probe_height, label = "Probe Height", suffix = " yd", tooltip = "Vertical offset for obstacle probing rays" },
            }
        })

        -- Proactive Lookahead (advanced)
        t:slider_list({
            label = "Proactive Lookahead",
            visible_when = show_advanced,
            elements = {
                { element = menu.look_height, label = "Height Offset", suffix = " yd", tooltip = "Vertical offset for lookahead obstacle checks" },
                { element = menu.look_spread, label = "Spread Angle", suffix = "\194\176", tooltip = "Angular width of the proactive lookahead cone" },
                { element = menu.look_segments, label = "Segments to Check", tooltip = "Number of path segments to check ahead for obstacles" },
            }
        })

    end)
end

return ObstaclesTab
