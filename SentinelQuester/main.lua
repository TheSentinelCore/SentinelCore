local QuestingBuddy = require("init")

local _loaded = false

local menu = {
    toggle_btn = core.menu.button("qb_toggle"),
    enabled_cb = core.menu.checkbox(false, "qb_enabled"),
    require_questie_cb = core.menu.checkbox(true, "qb_require_questie"),
    fallback_hostiles_cb = core.menu.checkbox(true, "qb_fallback_hostiles"),
    debug_cb = core.menu.checkbox(false, "qb_debug"),
    scan_radius_slider = core.menu.slider_int(20, 150, 70, "qb_scan_radius"),
    interact_range_slider = core.menu.slider_float(2.0, 10.0, 5.0, "qb_interact_range"),
    objective_timeout_slider = core.menu.slider_float(5.0, 60.0, 25.0, "qb_objective_timeout"),
}

local function sync_runtime_settings()
    local cfg = {
        scan_radius = menu.scan_radius_slider:get(),
        interact_range = menu.interact_range_slider:get(),
        objective_timeout = menu.objective_timeout_slider:get(),
        require_questie = menu.require_questie_cb:get_state(),
        fallback_include_hostiles = menu.fallback_hostiles_cb:get_state(),
        debug = menu.debug_cb:get_state(),
    }

    QuestingBuddy:configure(cfg)
    QuestingBuddy:set_enabled(menu.enabled_cb:get_state())
end

local function on_load()
    if _loaded then
        return
    end

    if not QuestingBuddy:initialize() then
        core.log_error("[QuestingBuddy] Failed to initialize")
        return
    end

    _loaded = true
    core.log("[QuestingBuddy] Loaded")
end

local function on_unload()
    QuestingBuddy:destroy()
    _loaded = false
    core.log("[QuestingBuddy] Unloaded")
end

core.register_on_update_callback(function()
    if not _loaded then
        on_load()
    end

    if not _loaded then
        return
    end

    sync_runtime_settings()
    QuestingBuddy:update()
end)

core.register_on_render_menu_callback(function()
    if not _loaded then
        return
    end

    if menu.toggle_btn:render("QuestingBuddy") then
        local enabled = not menu.enabled_cb:get_state()
        menu.enabled_cb:set(enabled)
        core.log("[QuestingBuddy] " .. (enabled and "Enabled" or "Disabled"))
    end

    menu.enabled_cb:render("Enable QuestingBuddy")
    menu.require_questie_cb:render("Require Questie Hook")
    menu.fallback_hostiles_cb:render("Fallback Hostile Units")
    menu.scan_radius_slider:render("Scan Radius")
    menu.interact_range_slider:render("Interact Range")
    menu.objective_timeout_slider:render("Objective Timeout")
    menu.debug_cb:render("Debug Logs")
end)

return {
    name = "QuestingBuddy",
    version = QuestingBuddy.VERSION,

    start = function()
        menu.enabled_cb:set(true)
        return QuestingBuddy:start()
    end,
    stop = function()
        menu.enabled_cb:set(false)
        QuestingBuddy:stop()
    end,
    status = function()
        return QuestingBuddy:get_status()
    end,
    unload = on_unload,
}
