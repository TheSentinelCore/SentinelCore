--[[
    Settings Sync Module
    Reads menu element values and writes them to the Settings persistence layer.
    Called once per frame from the UI orchestrator.
]]

local Settings = require("core/Settings")

local SettingsSync = {}

---Sync all menu element states to the Settings persistence layer
---@param menu_elements table The menu_elements table from main.lua
function SettingsSync.sync(menu_elements)
    -- Gathering
    Settings.set("gathering.gather_herbs", menu_elements.gather_herbs_cb:get_state())
    Settings.set("gathering.gather_ores", menu_elements.gather_ores_cb:get_state())
    Settings.set("gathering.check_skills", menu_elements.check_skills_cb:get_state())
    Settings.set("gathering.node_search_radius", menu_elements.node_search_radius_slider:get())
    Settings.set("gathering.gather_timeout", menu_elements.gather_timeout_slider:get())

    -- Movement basics
    Settings.set("movement.waypoint_tolerance", menu_elements.waypoint_tolerance_slider:get())
    Settings.set("movement.mount_threshold", menu_elements.mount_threshold_slider:get())

    -- Path smoothing
    local Constants = require("core/Constants")
    local selected_idx = menu_elements.smoothing_combo:get()
    local selected_algo = Constants.SMOOTHING_ALGORITHMS[selected_idx]
    if selected_algo then
        Settings.set("movement.preferred_smoothing", selected_algo.id)
    end
    Settings.set("movement.smooth_iterations", menu_elements.smooth_iterations_slider:get())
    Settings.set("movement.smooth_samples", menu_elements.smooth_samples_slider:get())
    -- smooth_ratio slider returns 75 (scaled) or 0.75 (raw) depending on SDK state;
    -- normalize so the API always receives a value in 0.5-0.95
    local smooth_ratio_raw = menu_elements.smooth_ratio_slider:get()
    Settings.set("movement.smooth_ratio", smooth_ratio_raw > 1 and smooth_ratio_raw / 100.0 or smooth_ratio_raw)
    Settings.set("movement.min_corner_angle", menu_elements.min_corner_angle_slider:get())
    Settings.set("movement.keep_originals", menu_elements.keep_originals_cb:get_state())

    -- Optimization
    Settings.set("movement.path_optimize", menu_elements.path_optimize_cb:get_state())
    Settings.set("movement.filter_ground", menu_elements.filter_ground_slider:get())
    Settings.set("movement.filter_water", menu_elements.filter_water_slider:get())
    Settings.set("movement.filter_lava", menu_elements.filter_lava_slider:get())

    -- Indoor corridor pathfinding
    Settings.set("movement.use_corridor_indoor", menu_elements.use_corridor_indoor_cb:get_state())

    -- Wall clearance
    Settings.set("movement.wall_clearance_enabled", menu_elements.wall_clearance_cb:get_state())
    Settings.set("movement.wall_clearance", menu_elements.wall_clearance_slider:get())

    -- Anti-detection
    Settings.set("movement.anti_detection", menu_elements.anti_detection_cb:get_state())
    Settings.set("movement.max_deviation", menu_elements.max_deviation_slider:get())
    Settings.set("anti_detection.random_pause_enabled", menu_elements.random_pause_cb:get_state())
    Settings.set("anti_detection.random_pause_interval_min", menu_elements.pause_interval_min_slider:get())
    Settings.set("anti_detection.random_pause_interval_max", menu_elements.pause_interval_max_slider:get())
    Settings.set("anti_detection.random_jump_enabled", menu_elements.random_jump_cb:get_state())

    -- Safety
    Settings.set("safety.enemy_scan_radius", menu_elements.enemy_scan_radius_slider:get())
    Settings.set("safety.skip_if_enemies_near", menu_elements.skip_if_enemies_cb:get_state())
    Settings.set("safety.flee_health_threshold", menu_elements.flee_health_slider:get())
end

return SettingsSync
