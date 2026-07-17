local app = nil
local initialized = false
local last_init_error = nil

local function log_error(message)
    if core and type(core.log_error) == "function" then
        pcall(core.log_error, "[Sentinel] " .. tostring(message))
    end
end

local function log_info(message)
    if core and type(core.log) == "function" then
        pcall(core.log, "[Sentinel] " .. tostring(message))
    end
end

local function clear_module_cache()
    if not package or not package.loaded then return end
    local prefixes = { "runtime/", "core/bt/", "modules/", "shared/", "ui/" }
    for key in pairs(package.loaded) do
        for _, prefix in ipairs(prefixes) do
            if key:sub(1, #prefix) == prefix then
                package.loaded[key] = nil
                break
            end
        end
    end
end

local function ensure_initialized()
    if initialized and app then
        return true
    end

    clear_module_cache()

    local ok, result = pcall(function()
        local SentinelApp = require("runtime/app")
        local next_app = SentinelApp:new()
        next_app:initialize()
        return next_app
    end)

    if not ok then
        if result ~= last_init_error then
            last_init_error = result
            log_error("Initialization failed: " .. tostring(result))
        end
        return false
    end

    app = result
    initialized = true
    last_init_error = nil
    _G.Sentinel.app = app
    log_info("Loaded")
    return true
end

_G.Sentinel = {
    app = nil,
    get_event_bus = function()
        if ensure_initialized() then
            return app:get_event_bus()
        end
        return nil
    end,
    get_blackboard = function()
        if ensure_initialized() then
            return app:get_blackboard()
        end
        return nil
    end,
    combat = function()
        if ensure_initialized() then
            return app:get_module("combat")
        end
        return nil
    end,
    bg = function()
        if ensure_initialized() then
            return app:get_module("battleground")
        end
        return nil
    end,
    battleground = function()
        if ensure_initialized() then
            return app:get_module("battleground")
        end
        return nil
    end,
    ui = function()
        if ensure_initialized() then
            return app:get_ui()
        end
        return nil
    end,
    reload = function()
        log_info("Forcing full reload...")
        if app and type(app.shutdown) == "function" then
            pcall(app.shutdown, app)
        end
        app = nil
        initialized = false
        last_init_error = nil
        clear_module_cache()
        local ok, result = pcall(function()
            local SentinelApp = require("runtime/app")
            local next_app = SentinelApp:new()
            next_app:initialize()
            return next_app
        end)
        if ok then
            app = result
            initialized = true
            _G.Sentinel.app = app
            log_info("Reloaded successfully")
            return true
        else
            log_error("Reload failed: " .. tostring(result))
            return false
        end
    end,
    reload_ui = function()
        if ensure_initialized() then
            local ui = app:get_ui()
            if ui and ui.reload_ui then
                return ui.reload_ui()
            end
        end
        return false
    end,
}

core.register_on_pre_tick_callback(function()
    if ensure_initialized() then
        app:on_pre_tick()
    end
end)

core.register_on_update_callback(function()
    if ensure_initialized() then
        app:on_update()
    end
end)

core.register_on_render_callback(function()
    if ensure_initialized() then
        app:on_render()
    end
end)

core.register_on_render_window_callback(function()
    if ensure_initialized() then
        app:on_render_window()
    end
end)

core.register_on_render_menu_callback(function()
    if ensure_initialized() then
        app:on_render_menu()
    end
end)

core.register_on_spell_cast_callback(function(data)
    if ensure_initialized() then
        app:on_spell_cast(data)
    end
end)

core.register_on_legit_spell_cast_callback(function(data)
    if ensure_initialized() then
        app:on_legit_spell_cast(data)
    end
end)

local function on_unload()
    if app and type(app.shutdown) == "function" then
        app:shutdown()
    end
    app = nil
    initialized = false
    _G.Sentinel = nil
end

return {
    name = "Sentinel",
    version = "0.1.0",
    unload = on_unload,
}
