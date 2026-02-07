--[[
    GatherBuddy Main Entry Point

    Slim entry point that registers callbacks, manages menu elements,
    handles profile scanning, and delegates UI rendering to ui/window.lua.

    CRITICAL: Uses ONLY Sylvannas API - no WoW Lua API calls permitted.
]]

-- Imports
local GatherBuddy = require("init")
local color = require("common/color")
local JSON = require("utils/JSON")
local UIWindow = require("ui/window")

-- Module state
local _is_loaded = false

-- UI state (shared with tab modules)
local _ui_state = {
    profiles = {},
    selected_profile_index = 1,
    last_profile_scan = 0,
    current_tab = 1,
}

-- =============================================================================
-- MENU ELEMENTS (persisted via Sylvannas menu system)
-- =============================================================================

local menu_elements = {
    -- Window toggle
    open_btn = core.menu.button("gb_open"),

    -- Overlay toggle
    overlay_enabled_cb = core.menu.checkbox(true, "gb_overlay_enabled"),

    -- Profile tab
    profile_combo = core.menu.combobox(1, "gb_profile_select"),
    hotspot_radius_slider = core.menu.slider_int(10, 100, 30, "gb_hotspot_radius"),

    -- Gathering tab
    gather_herbs_cb = core.menu.checkbox(true, "gb_gather_herbs"),
    gather_ores_cb = core.menu.checkbox(true, "gb_gather_ores"),
    check_skills_cb = core.menu.checkbox(true, "gb_check_skills"),
    node_search_radius_slider = core.menu.slider_int(20, 150, 80, "gb_node_search_radius"),
    gather_timeout_slider = core.menu.slider_float(5.0, 30.0, 10.0, "gb_gather_timeout"),

    -- Navigation tab
    smoothing_combo = core.menu.combobox(1, "gb_smoothing_algorithm"),
    smooth_iterations_slider = core.menu.slider_int(1, 5, 2, "gb_smooth_iterations"),
    smooth_samples_slider = core.menu.slider_int(5, 50, 10, "gb_smooth_samples"),
    smooth_ratio_slider = core.menu.slider_float(0.5, 0.95, 0.75, "gb_smooth_ratio"),
    min_corner_angle_slider = core.menu.slider_float(0.0, 120.0, 30.0, "gb_min_corner_angle"),
    keep_originals_cb = core.menu.checkbox(false, "gb_keep_originals"),
    path_optimize_cb = core.menu.checkbox(false, "gb_path_optimize"),
    anti_detection_cb = core.menu.checkbox(false, "gb_anti_detection"),
    max_deviation_slider = core.menu.slider_float(1.0, 20.0, 5.0, "gb_max_deviation"),
    filter_ground_slider = core.menu.slider_float(0.1, 10.0, 1.0, "gb_filter_ground"),
    filter_water_slider = core.menu.slider_float(0.1, 100.0, 10.0, "gb_filter_water"),
    filter_lava_slider = core.menu.slider_float(0.1, 1000.0, 100.0, "gb_filter_lava"),
    waypoint_tolerance_slider = core.menu.slider_float(0.1, 10.0, 3.0, "gb_waypoint_tolerance"),
    mount_threshold_slider = core.menu.slider_int(10, 100, 40, "gb_mount_threshold"),

    -- Indoor navigation
    use_corridor_indoor_cb = core.menu.checkbox(true, "gb_use_corridor_indoor"),

    -- Wall clearance
    wall_clearance_cb = core.menu.checkbox(false, "gb_wall_clearance_enabled"),
    wall_clearance_slider = core.menu.slider_float(0.5, 5.0, 1.5, "gb_wall_clearance"),

    -- Anti-detection sub-settings
    random_pause_cb = core.menu.checkbox(false, "gb_random_pause"),
    pause_interval_min_slider = core.menu.slider_float(15.0, 120.0, 30.0, "gb_pause_interval_min"),
    pause_interval_max_slider = core.menu.slider_float(30.0, 180.0, 90.0, "gb_pause_interval_max"),
    random_jump_cb = core.menu.checkbox(false, "gb_random_jump"),

    -- Safety tab
    enemy_scan_radius_slider = core.menu.slider_int(10, 60, 30, "gb_enemy_scan_radius"),
    skip_if_enemies_cb = core.menu.checkbox(true, "gb_skip_if_enemies"),
    flee_health_slider = core.menu.slider_int(10, 50, 30, "gb_flee_health"),
}

-- =============================================================================
-- PROFILE SCANNING
-- =============================================================================

---Load profile metadata from JSON file
---@param path string
---@return table|nil
local function load_profile_metadata(path)
    local json_str = core.read_data_file(path)
    if not json_str or json_str == "" then return nil end

    local data, _ = JSON.decode(json_str)
    if not data then return nil end

    return {
        name = (data.metadata and data.metadata.name) or path:match("([^/]+)%.json$"),
        path = path,
        zone = data.requirements and data.requirements.zone,
        map_id = data.requirements and data.requirements.map_id,
        waypoint_count = data.waypoints and #data.waypoints or 0
    }
end

---Scan for available profiles using manifest + discovery
---@return table[] profiles
local function scan_profiles()
    local profiles = {
        { name = "Select profile...", path = nil }
    }

    local base_path = "gatherbuddy/profiles/"
    local found_files = {}

    -- Step 1: Try to load manifest
    local manifest_path = base_path .. "manifest.json"
    local manifest_str = core.read_data_file(manifest_path)

    if manifest_str and manifest_str ~= "" then
        local data, _ = JSON.decode(manifest_str)
        if data and data.profiles then
            for _, entry in ipairs(data.profiles) do
                local full_path = base_path .. entry.filename
                local size = core.get_data_file_size(full_path)
                if size and size > 0 then
                    table.insert(profiles, {
                        name = entry.name or entry.filename:gsub("%.json$", ""),
                        path = full_path,
                        zone = entry.zone,
                        map_id = entry.map_id
                    })
                    found_files[entry.filename] = true
                end
            end
        end
    end

    -- Step 2: Probe for common profile filenames not in manifest
    local known_files = {
        "elwynn_copper.json",
        "westfall_iron.json",
        "durotar_copper.json",
        "mulgore_copper.json",
        "tirisfal_glades.json",
    }

    for _, filename in ipairs(known_files) do
        if not found_files[filename] then
            local full_path = base_path .. filename
            local size = core.get_data_file_size(full_path)
            if size and size > 0 then
                local metadata = load_profile_metadata(full_path)
                if metadata then
                    table.insert(profiles, metadata)
                    found_files[filename] = true
                end
            end
        end
    end

    return profiles
end

-- =============================================================================
-- PATH VISUALIZATION OVERLAY
-- =============================================================================

-- Overlay colors
local OVERLAY_COLORS = {
    waypoint_completed = color.green(180),
    waypoint_current = color.yellow(255),
    waypoint_upcoming = color.new(100, 150, 255, 180),
    path_line = color.new(100, 150, 255, 150),
}

---Render path visualization in game world
local function render_path_overlay()
    if not UIWindow.is_overlay_enabled() then
        return
    end

    local bot_mgr = GatherBuddy:get_bot_manager()
    local movement = bot_mgr and bot_mgr._modules and bot_mgr._modules.MovementModule
    if not movement then return end

    local current_path = movement._current_path
    local path_index = movement._path_index or 1

    if not current_path or #current_path == 0 then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    local player_pos = player:get_position()

    for i, waypoint in ipairs(current_path) do
        local wp_color
        if i < path_index then
            wp_color = OVERLAY_COLORS.waypoint_completed
        elseif i == path_index then
            wp_color = OVERLAY_COLORS.waypoint_current
        else
            wp_color = OVERLAY_COLORS.waypoint_upcoming
        end

        core.graphics.circle_3d(waypoint, 0.8, wp_color, 2)

        if i < #current_path then
            local next_wp = current_path[i + 1]
            core.graphics.line_3d(waypoint, next_wp, OVERLAY_COLORS.path_line, 2)
        end
    end

    if current_path[path_index] then
        local target = current_path[path_index]
        core.graphics.line_3d(player_pos, target, OVERLAY_COLORS.waypoint_current, 3)
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function on_load()
    if _is_loaded then return end

    core.log("[GatherBuddy] Loading...")

    local success = GatherBuddy:initialize()
    if not success then
        core.log_error("[GatherBuddy] Failed to initialize")
        return
    end

    -- Initialize the UI window
    UIWindow.init(GatherBuddy, menu_elements, _ui_state)

    -- Enable the UI by default
    local ui = UIWindow.get_ui()
    if ui and ui.menu and ui.menu.enable then
        ui.menu.enable:set(true)
    end

    _is_loaded = true
    core.log("[GatherBuddy] Loaded successfully")
end

local function on_unload()
    if GatherBuddy then
        GatherBuddy:destroy()
    end
    _is_loaded = false
    core.log("[GatherBuddy] Unloaded")
end

-- =============================================================================
-- CALLBACKS
-- =============================================================================

core.register_on_update_callback(function()
    if not _is_loaded then
        on_load()
    end

    -- Periodically scan for profiles
    local now = core.time()
    if now - _ui_state.last_profile_scan > 5 then
        _ui_state.profiles = scan_profiles()
        _ui_state.last_profile_scan = now
    end
end)

core.register_on_render_callback(function()
    if not _is_loaded then return end
    UIWindow.on_render()
    render_path_overlay()
end)

core.register_on_render_menu_callback(function()
    if not _is_loaded then return end

    UIWindow.on_menu_render()

    -- Toggle button in Sylvannas main menu
    if menu_elements.open_btn:render("GatherBuddy") then
        local ui = UIWindow.get_ui()
        if ui and ui.menu and ui.menu.enable then
            ui.menu.enable:set(true)
        end
    end
end)

-- =============================================================================
-- MODULE EXPORT
-- =============================================================================

return {
    name = "GatherBuddy",
    version = GatherBuddy.VERSION,

    start = function(profile) return GatherBuddy:start(profile) end,
    stop = function() GatherBuddy:stop() end,
    pause = function() GatherBuddy:pause() end,
    resume = function() GatherBuddy:resume() end,
    toggle_pause = function() GatherBuddy:toggle_pause() end,

    is_running = function() return GatherBuddy:is_running() end,
    is_paused = function() return GatherBuddy:is_paused() end,
    get_state = function() return GatherBuddy:get_state() end,

    get_statistics = function() return GatherBuddy:get_statistics() end,
    load_profile = function(path) return GatherBuddy:load_profile(path) end,

    run_tests = function() return GatherBuddy:run_tests() end,

    show_ui = function(show)
        local ui = UIWindow.get_ui()
        if ui and ui.menu and ui.menu.enable then
            ui.menu.enable:set(show)
        end
    end,

    open_window = function()
        local ui = UIWindow.get_ui()
        if ui and ui.menu and ui.menu.enable then
            ui.menu.enable:set(true)
        end
    end,

    unload = on_unload,
}
