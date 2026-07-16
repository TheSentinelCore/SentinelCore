--[[
    Pathfinding Tab - String-pull tuning, optimization, terrain costs, indoor, wall clearance
    Apple HIG card-based design using AstroUI row_list widgets.
]]

local Defaults = require("core/Defaults")

local PathfindingTab = {}

---Register the pathfinding tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu table Menu elements table
function PathfindingTab.register(ui, menu)
    local M = Defaults.movement

    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    local function wall_clearance_on()
        return menu.wall_clearance_en:get_state()
    end

    local function corridor_on()
        return menu.corridor:get_state()
    end

    ui:add_tab({ id = "pathfinding", label = "Pathfinding" }, function(t)

        -- Optimization
        t:row_list({
            label = "Optimization",
            elements = {
                {
                    type = "toggle",
                    label = "String-Pulling",
                    element = menu.optimize,
                    tooltip = "Removes unnecessary waypoints by testing line-of-sight",
                },
                {
                    type = "toggle",
                    label = "Allow Partial Paths",
                    element = menu.allow_partial,
                    tooltip = "Accept incomplete paths when a full path is unavailable",
                },
            },
        })

        -- String-Pull Tuning (advanced)
        t:row_list({
            label = "String-Pull Tuning",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Max Deviation",
                    element = menu.sp_deviation,
                    min = M.string_pull_deviation.min,
                    max = M.string_pull_deviation.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Max 3D deviation for string-pull optimization (lower = tighter corners)",
                },
                {
                    type = "stepper",
                    label = "Max Heading Change",
                    element = menu.sp_heading,
                    min = M.string_pull_heading.min,
                    max = M.string_pull_heading.max,
                    step = 1,
                    decimals = 0,
                    suffix = "\xC2\xB0",
                    tooltip = "Max heading change in degrees (lower = preserves more curves)",
                },
                {
                    type = "stepper",
                    label = "Min Wall Distance",
                    element = menu.sp_wall_dist,
                    min = M.string_pull_wall_dist.min,
                    max = M.string_pull_wall_dist.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Min wall distance for shortcuts (higher = tighter corners, 0 = disabled)",
                },
                {
                    type = "stepper",
                    label = "Segment Length",
                    element = menu.densify_seg,
                    min = M.densify_segment_length.min,
                    max = M.densify_segment_length.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Max distance between waypoints (lower = smoother curves)",
                },
            },
        })

        -- Wall Clearance
        t:row_list({
            label = "Wall Clearance",
            elements = {
                {
                    type = "toggle",
                    label = "Enable",
                    element = menu.wall_clearance_en,
                    tooltip = "Pushes path away from walls by the specified distance",
                },
                {
                    type = "stepper",
                    label = "Distance",
                    element = menu.wall_clearance,
                    min = M.wall_clearance.min,
                    max = M.wall_clearance.max,
                    step = 0.1,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "Minimum distance to maintain from walls",
                    visible_when = wall_clearance_on,
                },
            },
        })

        -- Indoor Navigation
        t:row_list({
            label = "Indoor Navigation",
            elements = {
                {
                    type = "toggle",
                    label = "Corridor Pathfinding",
                    element = menu.corridor,
                    tooltip = "Uses tighter pathfinding for indoor and corridor areas",
                },
                {
                    type = "stepper",
                    label = "Probe Distance",
                    element = menu.corridor_probe,
                    min = M.corridor_probe_dist.min,
                    max = M.corridor_probe_dist.max,
                    step = 0.5,
                    decimals = 1,
                    suffix = " yd",
                    tooltip = "How far ahead to probe for corridor detection",
                    visible_when = function() return corridor_on() and show_advanced() end,
                },
            },
        })

        -- Terrain Costs (advanced)
        t:row_list({
            label = "Terrain Costs",
            visible_when = show_advanced,
            elements = {
                {
                    type = "stepper",
                    label = "Ground",
                    element = menu.filter_ground,
                    min = M.filter_ground.min,
                    max = M.filter_ground.max,
                    step = 0.1,
                    decimals = 1,
                    tooltip = "Pathfinding cost multiplier for ground terrain",
                },
                {
                    type = "stepper",
                    label = "Water",
                    element = menu.filter_water,
                    min = M.filter_water.min,
                    max = M.filter_water.max,
                    step = 0.1,
                    decimals = 1,
                    tooltip = "Pathfinding cost multiplier \xe2\x80\x94 higher values avoid water",
                },
                {
                    type = "stepper",
                    label = "Lava",
                    element = menu.filter_lava,
                    min = M.filter_lava.min,
                    max = M.filter_lava.max,
                    step = 0.1,
                    decimals = 1,
                    tooltip = "Pathfinding cost multiplier \xe2\x80\x94 higher values avoid lava",
                },
            },
        })

    end)
end

return PathfindingTab
