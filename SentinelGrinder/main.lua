local GrindBuddy = require("init")
local UIWindow = require("ui/window")

local _is_loaded = false
local _next_init_retry = 0
local _last_init_error_log = 0

local menu = {
    start_stop_btn = core.menu.button("grindbuddy_start_stop"),
    open_ui_btn = core.menu.button("grindbuddy_open_ui"),
}

local function on_load()
    if _is_loaded then
        return
    end

    local now = core.time and core.time() or 0
    if now < _next_init_retry then
        return
    end

    if not GrindBuddy:initialize() then
        if (now - _last_init_error_log) > 5.0 then
            core.log_error("[GrindBuddy] Initialization failed")
            _last_init_error_log = now
        end
        _next_init_retry = now + 0.5
        return
    end

    UIWindow.init(GrindBuddy)
    _is_loaded = true
end

local function on_unload()
    GrindBuddy:destroy()
    _is_loaded = false
end

-- Attempt eager initialization so menu/UI are available without requiring a manual reload.
on_load()

core.register_on_update_callback(function()
    if not _is_loaded then
        on_load()
    end

    if _is_loaded then
        local ok, err = pcall(GrindBuddy.update, GrindBuddy)
        if not ok then
            core.log_error("[GrindBuddy] Update error: " .. tostring(err))
        end
    end
end)

core.register_on_render_callback(function()
    if not _is_loaded then
        return
    end
    UIWindow.on_render()
end)

core.register_on_render_menu_callback(function()
    if not _is_loaded then
        on_load()
        if not _is_loaded then
            return
        end
    end

    UIWindow.on_menu_render()

    local label = GrindBuddy:is_running() and "GrindBuddy: Stop" or "GrindBuddy: Start"
    if menu.start_stop_btn:render(label) then
        if GrindBuddy:is_running() then
            GrindBuddy:stop()
        else
            GrindBuddy:start()
        end
    end

    if menu.open_ui_btn:render("GrindBuddy UI") then
        UIWindow.toggle()
    end
end)

return {
    name = GrindBuddy.NAME,
    version = GrindBuddy.VERSION,
    start = function() return GrindBuddy:start() end,
    stop = function() GrindBuddy:stop() end,
    is_running = function() return GrindBuddy:is_running() end,
    get_state = function() return GrindBuddy:get_state() end,
    get_status = function() return GrindBuddy:get_status() end,
    get_version_info = function() return GrindBuddy:get_version_info() end,
    get_rotation_profiles = function() return GrindBuddy:get_rotation_profiles() end,
    get_route_profiles = function() return GrindBuddy:get_route_profiles() end,
    unload = on_unload,
}
