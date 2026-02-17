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

    -- Movement (SentinelGather-specific only)
    Settings.set("movement.mount_threshold", menu_elements.mount_threshold_slider:get())

    -- Safety
    Settings.set("safety.enemy_scan_radius", menu_elements.enemy_scan_radius_slider:get())
    Settings.set("safety.skip_if_enemies_near", menu_elements.skip_if_enemies_cb:get_state())
    Settings.set("safety.flee_health_threshold", menu_elements.flee_health_slider:get())

    -- Anti-detection (SentinelGather-specific pause/jump behavior)
    Settings.set("anti_detection.random_pause_enabled", menu_elements.random_pause_cb:get_state())
    Settings.set("anti_detection.random_pause_interval_min", menu_elements.pause_interval_min_slider:get())
    Settings.set("anti_detection.random_pause_interval_max", menu_elements.pause_interval_max_slider:get())
    Settings.set("anti_detection.random_jump_enabled", menu_elements.random_jump_cb:get_state())
end

return SettingsSync
