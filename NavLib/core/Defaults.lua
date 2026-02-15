-- NavLib/core/Defaults.lua
-- Single source of truth for all NavLib configuration defaults.
-- Movement.lua, Obstacle.lua, and window.lua all read from this file.

local Defaults = {}

--------------------------------------------------------------------------------
-- Movement settings
--------------------------------------------------------------------------------
Defaults.movement = {
    -- Speed
    dynamic_speed           = { type = "bool",  default = false,  id = "navlib_dynamic_speed" },

    -- Tolerances
    waypoint_tolerance      = { type = "float", min = 0.5,  max = 10.0,  default = 3.0,   id = "navlib_waypoint_tolerance" },
    final_tolerance         = { type = "float", min = 0.5,  max = 5.0,   default = 1.5,   id = "navlib_final_tolerance" },

    -- Anti-Detection
    anti_detection          = { type = "bool",  default = false,  id = "navlib_anti_detection" },
    max_deviation           = { type = "float", min = 1.0,  max = 20.0,  default = 3.0,   id = "navlib_max_deviation" },

    -- Stuck Recovery
    stuck_check_interval    = { type = "float", min = 0.25, max = 5.0,   default = 0.25,   id = "navlib_stuck_interval" },
    stuck_distance_min      = { type = "float", min = 0.1,  max = 2.0,   default = 0.1,  id = "navlib_stuck_distance_v2" },
    max_stuck_attempts      = { type = "int",   min = 1,    max = 10,    default = 6,     id = "navlib_max_stuck" },

    -- Path Validation
    path_check_interval     = { type = "float", min = 1.0,  max = 30.0,  default = 5.0,   id = "navlib_path_check" },

    -- Deviation Detection
    deviation_check_interval     = { type = "float", min = 0.1,  max = 5.0,   default = 1.0,   id = "navlib_deviation_check_interval" },
    deviation_threshold          = { type = "float", min = 1.0,  max = 20.0,  default = 2.0,   id = "navlib_deviation_threshold" },
    deviation_vertical_threshold = { type = "float", min = 0.5,  max = 10.0,  default = 2.0,   id = "navlib_deviation_vertical_threshold" },
    deviation_corridor_factor    = { type = "float", min = 0.1,  max = 2.0,   default = 0.75,  id = "navlib_deviation_corridor_factor" },
    repath_cooldown              = { type = "float", min = 0.1,  max = 5.0,   default = 0.1,   id = "navlib_repath_cooldown" },
    max_deviation_repaths        = { type = "int",   min = 1,    max = 10,    default = 5,     id = "navlib_max_deviation_repaths" },

    -- Smoothing
    smoothing               = { type = "combo", default = 2, options = { "none", "chaikin", "catmull", "bezier" }, id = "navlib_smoothing" },
    smooth_iterations       = { type = "int",   min = 1,    max = 5,     default = 3,     id = "navlib_smooth_iterations" },
    smooth_samples          = { type = "int",   min = 5,    max = 50,    default = 10,    id = "navlib_smooth_samples" },
    smooth_ratio            = { type = "int",   min = 50,   max = 95,    default = 50,    id = "navlib_smooth_ratio_pct" },
    min_corner_angle        = { type = "float", min = 0.0,  max = 120.0, default = 90.0,  id = "navlib_corner_angle" },
    keep_originals          = { type = "bool",  default = false,  id = "navlib_keep_originals" },

    -- Optimization
    optimize                = { type = "bool",  default = true,   id = "navlib_optimize" },
    allow_partial           = { type = "bool",  default = false,   id = "navlib_allow_partial" },

    -- Terrain Costs
    filter_ground           = { type = "float", min = 0.1,  max = 10.0,   default = 1.0,   id = "navlib_filter_ground" },
    filter_water            = { type = "float", min = 0.1,  max = 100.0,  default = 10.0,  id = "navlib_filter_water" },
    filter_lava             = { type = "float", min = 0.1,  max = 1000.0, default = 100.0, id = "navlib_filter_lava" },

    -- Indoor / Corridor
    use_corridor_indoor     = { type = "bool",  default = true,   id = "navlib_corridor" },
    corridor_probe_dist     = { type = "float", min = 5.0,  max = 30.0,  default = 15.0,  id = "navlib_corridor_probe" },

    -- Wall Clearance
    wall_clearance_enabled  = { type = "bool",  default = true,   id = "navlib_wall_clearance_en" },
    wall_clearance          = { type = "float", min = 0.5,  max = 5.0,   default = 1.0,   id = "navlib_wall_clearance" },

    -- Obstacle Scanning
    proactive_obstacle_check    = { type = "bool",  default = true,  id = "navlib_proactive_obstacle" },
    proactive_obstacle_interval = { type = "float", min = 0.5, max = 5.0, default = 1.5, id = "navlib_obstacle_interval" },

    -- Debug
    debug_verbose           = { type = "bool",  default = false,  id = "navlib_debug_verbose" },
}

--------------------------------------------------------------------------------
-- Obstacle settings
--------------------------------------------------------------------------------
Defaults.obstacles = {
    avoidance_radius        = { type = "float", min = 1.0,  max = 10.0,  default = 3.0,   id = "navlib_avoidance_radius" },
    max_zones               = { type = "int",   min = 1,    max = 20,    default = 5,     id = "navlib_max_zones" },
    zone_ttl                = { type = "float", min = 30.0, max = 300.0, default = 120.0, id = "navlib_zone_ttl" },
    avoidance_cost          = { type = "float", min = 1.0,  max = 100.0,  default = 100.0,   id = "navlib_avoidance_cost" },
    zone_prune_dist         = { type = "float", min = 50.0, max = 500.0, default = 100.0, id = "navlib_zone_prune" },

    -- Reactive Probing
    probe_distance          = { type = "float", min = 2.0,  max = 20.0,  default = 8.0,   id = "navlib_probe_distance" },
    probe_spread_deg        = { type = "float", min = 5.0,  max = 45.0,  default = 20.0,  id = "navlib_probe_spread" },
    probe_height_offset     = { type = "float", min = 0.5,  max = 5.0,   default = 1.0,   id = "navlib_probe_height" },

    -- Proactive Lookahead
    lookahead_height_offset = { type = "float", min = 0.5,  max = 5.0,   default = 1.5,   id = "navlib_look_height" },
    lookahead_spread_deg    = { type = "float", min = 5.0,  max = 45.0,  default = 15.0,  id = "navlib_look_spread" },
    lookahead_segments      = { type = "int",   min = 1,    max = 10,    default = 3,     id = "navlib_look_segments" },
}

--------------------------------------------------------------------------------
-- Debug / Visualization (UI-only, no engine default)
--------------------------------------------------------------------------------
Defaults.debug = {
    debug_mode       = { type = "int",  min = 0, max = 12, default = 0,    id = "navlib_debug_mode" },
    viz_master       = { type = "bool", default = true,  id = "navlib_viz_master" },
    viz_path         = { type = "bool", default = true,  id = "navlib_viz_path" },
    viz_destination  = { type = "bool", default = true,  id = "navlib_viz_destination" },
    viz_obstacles    = { type = "bool", default = true,  id = "navlib_viz_obstacles" },
    viz_corridor     = { type = "bool", default = true,  id = "navlib_viz_corridor" },
    viz_state        = { type = "bool", default = true,  id = "navlib_viz_state" },
}

--------------------------------------------------------------------------------
-- Window-level (UI-only)
--------------------------------------------------------------------------------
Defaults.window = {
    show_advanced    = { type = "bool", default = false, id = "navlib_show_advanced" },
}

--------------------------------------------------------------------------------
-- Helper: reset menu elements to their defaults
--------------------------------------------------------------------------------
function Defaults.reset(pairs_list)
    for _, pair in ipairs(pairs_list) do
        pair[1]:set(pair[2].default)
    end
end

--------------------------------------------------------------------------------
-- Helper: extract flat default values from a section
--------------------------------------------------------------------------------
function Defaults.flat(section)
    local out = {}
    for key, def in pairs(section) do
        if def.type == "combo" then
            out[key] = def.options[def.default] or def.options[1]
        else
            out[key] = def.default
        end
    end
    return out
end

return Defaults
