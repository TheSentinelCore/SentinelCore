--[[
    Obstacles Tab - Avoidance zones, probing, lookahead
]]

local Defaults = require("core/Defaults")

local ObstaclesTab = {}

---Register the obstacles tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function ObstaclesTab.register(ui, menu)
    local M = Defaults.movement
    local O = Defaults.obstacles

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
                { element = menu.avoidance_radius, label = "Avoidance Radius", min = O.avoidance_radius.min, max = O.avoidance_radius.max, suffix = " yd", step = 0.1, use_stepper = true, tooltip = "How wide to steer around detected obstacles" },
                { element = menu.max_zones, label = "Max Remembered Zones", min = O.max_zones.min, max = O.max_zones.max, step = 1, integer = true, use_stepper = true, tooltip = "Maximum number of obstacle zones tracked simultaneously" },
                { element = menu.zone_ttl, label = "Zone Expiry", min = O.zone_ttl.min, max = O.zone_ttl.max, suffix = " s", step = 5, integer = true, use_stepper = true, tooltip = "How long obstacle zones persist before being forgotten" },
            }
        })

        -- Scanning (advanced)
        t:slider_list({
            label = "Scanning",
            visible_when = function() return show_advanced() and proactive_on() end,
            elements = {
                { element = menu.obstacle_interval, label = "Scan Interval", min = M.proactive_obstacle_interval.min, max = M.proactive_obstacle_interval.max, suffix = " s", step = 0.1, use_stepper = true, tooltip = "Time between proactive obstacle scans" },
            }
        })

        -- Costs (advanced)
        t:slider_list({
            label = "Costs",
            visible_when = show_advanced,
            elements = {
                { element = menu.avoidance_cost, label = "Avoidance Cost", min = O.avoidance_cost.min, max = O.avoidance_cost.max, step = 1, integer = true, use_stepper = true, tooltip = "Pathfinding cost penalty for obstacle-adjacent areas" },
                { element = menu.zone_prune, label = "Zone Prune Distance", min = O.zone_prune_dist.min, max = O.zone_prune_dist.max, suffix = " yd", step = 5, integer = true, use_stepper = true, tooltip = "Obstacle zones farther than this are removed" },
            }
        })

        -- Reactive Probing (advanced)
        t:slider_list({
            label = "Reactive Probing",
            visible_when = show_advanced,
            elements = {
                { element = menu.probe_distance, label = "Probe Distance", min = O.probe_distance.min, max = O.probe_distance.max, suffix = " yd", step = 0.5, use_stepper = true, tooltip = "How far ahead to probe for reactive obstacle detection" },
                { element = menu.probe_spread, label = "Probe Spread", min = O.probe_spread_deg.min, max = O.probe_spread_deg.max, suffix = "\194\176", step = 1, integer = true, use_stepper = true, tooltip = "Angular width of the obstacle detection cone" },
                { element = menu.probe_height, label = "Probe Height", min = O.probe_height_offset.min, max = O.probe_height_offset.max, suffix = " yd", step = 0.1, use_stepper = true, tooltip = "Vertical offset for obstacle probing rays" },
            }
        })

        -- Proactive Lookahead (advanced)
        t:slider_list({
            label = "Proactive Lookahead",
            visible_when = show_advanced,
            elements = {
                { element = menu.look_height, label = "Height Offset", min = O.lookahead_height_offset.min, max = O.lookahead_height_offset.max, suffix = " yd", step = 0.1, use_stepper = true, tooltip = "Vertical offset for lookahead obstacle checks" },
                { element = menu.look_spread, label = "Spread Angle", min = O.lookahead_spread_deg.min, max = O.lookahead_spread_deg.max, suffix = "\194\176", step = 1, integer = true, use_stepper = true, tooltip = "Angular width of the proactive lookahead cone" },
                { element = menu.look_segments, label = "Segments to Check", min = O.lookahead_segments.min, max = O.lookahead_segments.max, step = 1, integer = true, use_stepper = true, tooltip = "Number of path segments to check ahead for obstacles" },
            }
        })

    end)
end

return ObstaclesTab
