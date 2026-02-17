local BgBuddy = require("init")
local UIWindow = require("ui/window")

local _loaded = false

local menu = {
    open = core.menu.button("bgb_open"),
}

local function on_load()
    if _loaded then
        return
    end
    if not BgBuddy:initialize() then
        core.log_error("[BgBuddy] Initialization failed")
        return
    end
    UIWindow.init(BgBuddy)
    _loaded = true
    core.log("[BgBuddy] Loaded")
end

core.register_on_update_callback(function()
    if not _loaded then
        on_load()
    end
    BgBuddy:update()
end)

core.register_on_render_callback(function()
    if not _loaded then
        return
    end
    UIWindow.on_render()
end)

core.register_on_render_menu_callback(function()
    if not _loaded then
        return
    end

    UIWindow.on_menu_render()

    if menu.open:render("BgBuddy") then
        UIWindow.open()
    end
end)

return {
    name = "BgBuddy",
    version = BgBuddy.VERSION,
    start = function() BgBuddy:start() end,
    stop = function() BgBuddy:stop() end,
    set_city = function(city) BgBuddy:set_city(city) end,
    set_anchor_from_player = function(city) return BgBuddy:set_anchor_from_player(city) end,
    set_bg_anchor_from_player = function(city, bg_key) return BgBuddy:set_bg_anchor_from_player(city, bg_key) end,
    set_bg_role = function(role) BgBuddy:set_bg_role(role) end,
    get_bg_role = function() return BgBuddy:get_bg_role() end,
    set_combat_enabled = function(enabled) BgBuddy:set_combat_enabled(enabled) end,
    get_combat_enabled = function() return BgBuddy:get_combat_enabled() end,
    set_rotation_class = function(class_key) BgBuddy:set_rotation_class(class_key) end,
    get_rotation_class = function() return BgBuddy:get_rotation_class() end,
    get_rotation_class_options = function() return BgBuddy:get_rotation_class_options() end,
    set_selected_bg = function(bg_key) BgBuddy:set_selected_bg(bg_key) end,
    get_selected_bg = function() return BgBuddy:get_selected_bg() end,
    get_bg_options = function() return BgBuddy:get_bg_options() end,
    set_multi_queue_enabled = function(enabled) BgBuddy:set_multi_queue_enabled(enabled) end,
    get_multi_queue_enabled = function() return BgBuddy:get_multi_queue_enabled() end,
    set_multi_queue_bg_enabled = function(bg_key, enabled) BgBuddy:set_multi_queue_bg_enabled(bg_key, enabled) end,
    get_multi_queue_bg_enabled = function(bg_key) return BgBuddy:get_multi_queue_bg_enabled(bg_key) end,
    set_auto_faction = function(enabled) BgBuddy:set_auto_faction(enabled) end,
    get_auto_faction = function() return BgBuddy:get_auto_faction() end,
    get_detected_faction = function() return BgBuddy:get_detected_faction() end,
    set_debug_enabled = function(enabled) BgBuddy:set_debug_enabled(enabled) end,
    get_debug_enabled = function() return BgBuddy:get_debug_enabled() end,
    get_debug_snapshot = function() return BgBuddy:get_debug_snapshot() end,
    get_status = function() return BgBuddy:get_status_text() end,
    open_window = function() UIWindow.open() end,
}
