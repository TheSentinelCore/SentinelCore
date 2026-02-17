--[[
    SentinelGather Main Entry Point

    Slim entry point that registers callbacks, manages menu elements,
    handles profile scanning, and delegates UI rendering to ui/window.lua.

    CRITICAL: Uses ONLY Sylvannas API - no WoW Lua API calls permitted.
]]

-- Imports
local SentinelGather = require("init")
local color = require("common/color")
local UIWindow = require("ui/window")
local Constants = require("core/Constants")

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
    mount_threshold_slider = core.menu.slider_int(10, 100, 40, "gb_mount_threshold"),

    -- Safety tab
    enemy_scan_radius_slider = core.menu.slider_int(10, 60, 30, "gb_enemy_scan_radius"),
    skip_if_enemies_cb = core.menu.checkbox(true, "gb_skip_if_enemies"),
    flee_health_slider = core.menu.slider_int(10, 50, 30, "gb_flee_health"),

    -- Anti-detection (rendered in safety tab)
    random_pause_cb = core.menu.checkbox(false, "gb_random_pause"),
    pause_interval_min_slider = core.menu.slider_float(15.0, 120.0, 30.0, "gb_pause_interval_min"),
    pause_interval_max_slider = core.menu.slider_float(30.0, 180.0, 90.0, "gb_pause_interval_max"),
    random_jump_cb = core.menu.checkbox(false, "gb_random_jump"),
}

-- =============================================================================
-- PROFILE SCANNING
-- =============================================================================

-- Profile scanning delegated to ProfileManager
local function scan_profiles()
    local profile_mgr = SentinelGather and SentinelGather:get_module("ProfileManager")
    if profile_mgr and profile_mgr.scan_available_profiles then
        return profile_mgr:scan_available_profiles()
    end
    -- Fallback: return empty list
    return { { name = "Select profile...", path = nil } }
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

    local movement = SentinelGather:get_module("Movement")
    if not movement then return end

    local current_path = movement:get_current_path()
    local path_index = movement:get_path_index()

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

    core.log("[SentinelGather] Loading...")

    local success = SentinelGather:initialize()
    if not success then
        core.log_error("[SentinelGather] Failed to initialize")
        return
    end

    -- Initialize the UI window (starts hidden; user opens via menu button)
    UIWindow.init(SentinelGather, menu_elements, _ui_state)
    local ui = UIWindow.get_ui()
    if ui and ui.menu and ui.menu.enable then
        ui.menu.enable:set(false)
    end

    _is_loaded = true
    core.log("[SentinelGather] Loaded successfully")
end

local function on_unload()
    if SentinelGather then
        SentinelGather:destroy()
    end
    _is_loaded = false
    core.log("[SentinelGather] Unloaded")
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
    if now - _ui_state.last_profile_scan > Constants.OPERATIONAL.PROFILE_SCAN_INTERVAL then
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
    if menu_elements.open_btn:render("Sentinel Gather") then
        local ui = UIWindow.get_ui()
        if ui and ui.menu and ui.menu.enable then
            ui.menu.enable:set(not ui.menu.enable:get_state())
        end
    end
end)

-- =============================================================================
-- MODULE EXPORT
-- =============================================================================

return {
    name = "SentinelGather",
    version = SentinelGather.VERSION,

    start = function(profile) return SentinelGather:start(profile) end,
    stop = function() SentinelGather:stop() end,
    pause = function() SentinelGather:pause() end,
    resume = function() SentinelGather:resume() end,
    toggle_pause = function() SentinelGather:toggle_pause() end,

    is_running = function() return SentinelGather:is_running() end,
    is_paused = function() return SentinelGather:is_paused() end,
    get_state = function() return SentinelGather:get_state() end,

    get_statistics = function() return SentinelGather:get_statistics() end,
    load_profile = function(path) return SentinelGather:load_profile(path) end,

    run_tests = function() return SentinelGather:run_tests() end,

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
