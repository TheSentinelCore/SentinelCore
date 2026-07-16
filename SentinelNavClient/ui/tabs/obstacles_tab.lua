--[[
    Obstacles Tab - Avoidance zones, probing, lookahead
    Apple HIG card-based design using AstroUI row_list widgets.
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

        -- Obstacle Avoidance
        t:row_list({
            label = "Obstacle Avoidance",
            elements = {
                {
                    type = "toggle",
                    label = "Proactive Scanning",
                    element = menu.proactive_obstacle,
                    tooltip = "Periodically scans the path ahead for obstacles",
                },
                {
                    type = "stepper",
                    label = "Avoidance Radius",
                    element = menu.avoidance_radius,
                    min = O.avoidance_radius.min,
                    max = O.avoidance_radius.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "How wide to steer around detected obstacles",
                },
                {
                    type = "stepper",
                    label = "Max Remembered Zones",
                    element = menu.max_zones,
                    min = O.max_zones.min,
                    max = O.max_zones.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "Maximum number of obstacle zones tracked simultaneously",
                },
                {
                    type = "stepper",
                    label = "Zone Expiry",
                    element = menu.zone_ttl,
                    min = O.zone_ttl.min,
                    max = O.zone_ttl.max,
                    step = 5,
                    decimals = 0,
                    suffix = " s",
                    tooltip = "How long obstacle zones persist before being forgotten",
                },
            },
        })

        -- Scanning (advanced, visible when proactive ON)
        t:row_list({
            label = "Scanning",
            visible_when = function() return show_advanced() and proactive_on() end,
            elements = {
                {
                    type = "stepper",
                    label = "Scan Interval",
                    element = menu.obstacle_interval,
                    min = M.proactive_obstacle_interval.min,
                    max = M.proactive_obstacle_interval.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " s",
                    tooltip = "Time between proactive obstacle scans",
                },
            },
        })

        -- Costs (advanced)
        t:row_list({
            label = "Costs",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Avoidance Cost",
                    element = menu.avoidance_cost,
                    min = O.avoidance_cost.min,
                    max = O.avoidance_cost.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "Pathfinding cost penalty for obstacle-adjacent areas",
                },
                {
                    type = "stepper",
                    label = "Zone Prune Distance",
                    element = menu.zone_prune,
                    min = O.zone_prune_dist.min,
                    max = O.zone_prune_dist.max,
                    step = 5,
                    decimals = 0,
                    suffix = " yd",
                    tooltip = "Obstacle zones farther than this are removed",
                },
            },
        })

        -- Reactive Probing (advanced)
        t:row_list({
            label = "Reactive Probing",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Probe Distance",
                    element = menu.probe_distance,
                    min = O.probe_distance.min,
                    max = O.probe_distance.max,
                    step = 0.5,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "How far ahead to probe for reactive obstacle detection",
                },
                {
                    type = "stepper",
                    label = "Probe Spread",
                    element = menu.probe_spread,
                    min = O.probe_spread_deg.min,
                    max = O.probe_spread_deg.max,
                    step = 1,
                    decimals = 0,
                    suffix = "\194\176",
                    tooltip = "Angular width of the obstacle detection cone",
                },
                {
                    type = "stepper",
                    label = "Probe Height",
                    element = menu.probe_height,
                    min = O.probe_height_offset.min,
                    max = O.probe_height_offset.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Vertical offset for obstacle probing rays",
                },
            },
        })

        -- Proactive Lookahead (advanced)
        t:row_list({
            label = "Proactive Lookahead",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Height Offset",
                    element = menu.look_height,
                    min = O.lookahead_height_offset.min,
                    max = O.lookahead_height_offset.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Vertical offset for lookahead obstacle checks",
                },
                {
                    type = "stepper",
                    label = "Spread Angle",
                    element = menu.look_spread,
                    min = O.lookahead_spread_deg.min,
                    max = O.lookahead_spread_deg.max,
                    step = 1,
                    decimals = 0,
                    suffix = "\194\176",
                    tooltip = "Angular width of the proactive lookahead cone",
                },
                {
                    type = "stepper",
                    label = "Segments to Check",
                    element = menu.look_segments,
                    min = O.lookahead_segments.min,
                    max = O.lookahead_segments.max,
                    step = 1,
                    decimals = 0,
                    tooltip = "Number of path segments to check ahead for obstacles",
                },
            },
        })

    end)
end

return ObstaclesTab
