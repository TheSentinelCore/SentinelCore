local SentinelApp = require("runtime/app")

-- Set up package path for sentinel modules
package.path = table.concat({
    "sentinel/?.lua",
    "sentinel/?/?.lua",
    "sentinel/?/?/?.lua",
    "sentinel/?/?/?/?.lua",
    "sentinel/?/?/?/?/?.lua",
    package.path,
}, ";")

local app = nil
local initialized = false
local last_init_error = nil

-- Menu elements for main menu
local _menu_tree = core.menu.tree_node()
local _toggle_editor_btn = core.menu.button("sentinel_open_runner_cockpit")

-- Runner cockpit UI (deferred load until app is ready, to avoid Sylvannas API issues in tests).
-- Authoring lives OUTSIDE the game (the sentinel-editor HTTP API); the client is a cockpit for
-- running compiled profiles, not for editing them.
local RunnerUI = nil
local _questing_editor = nil
local _editor_subscribed = false

-- Wire the runner cockpit to the toggle event once the app and its event bus are ready.
local function ensure_editor_wired()
    if _editor_subscribed then return end
    if not app or not app.get_event_bus then return end
    -- Lazy-load the UI only when needed (avoids issues in test contexts)
    RunnerUI = RunnerUI or require("modules/questing/runner_ui")
    local questing = app:get_module("questing")
    _questing_editor = RunnerUI:new(questing and questing._questing or nil)
    app:get_event_bus():subscribe("questing:toggle_editor", function()
        if _questing_editor then
            _questing_editor:toggle()
        end
    end)
    _editor_subscribed = true
end

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
    local prefixes = { "runtime/", "core/bt/", "modules/", "shared/" }
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
    ensure_editor_wired()
    log_info("SentinelCore loaded (Combat Engine)")
    return true
end

_G.Sentinel = {
    app = nil,
    get_event_bus = function()
        if ensure_initialized() then return app:get_event_bus() end
        return nil
    end,
    get_blackboard = function()
        if ensure_initialized() then return app:get_blackboard() end
        return nil
    end,
    combat = function()
        if ensure_initialized() then return app:get_module("combat") end
        return nil
    end,
    questing = function()
        if ensure_initialized() then
            local q = app:get_module("questing")
            -- Return inner QuestingModule for direct access
            return q and q._questing or nil
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
            local next_app = SentinelApp:new()
            next_app:initialize()
            return next_app
        end)
        if ok then
            app = result
            initialized = true
            _G.Sentinel.app = app
            _editor_subscribed = false  -- re-subscribe with new event bus
            ensure_editor_wired()
            log_info("Reloaded successfully")
            return true
        else
            log_error("Reload failed: " .. tostring(result))
            return false
        end
    end,

    -- Editor control
    toggle_quest_editor = function()
        if ensure_initialized() then
            local q = app:get_module("questing")
            -- QuestingModuleInit wraps QuestingModule which has toggle_editor
            if q and q._questing and type(q._questing.toggle_editor) == "function" then
                q._questing:toggle_editor()
                return true
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

local _last_editor_create_error = nil
core.register_on_update_callback(function()
    if ensure_initialized() then app:on_update() end
    -- Create quest editor frames in tick context: Sylvannas forbids creating
    -- windows/menu elements inside render callbacks.
    if _questing_editor then
        local ok, err = pcall(function() _questing_editor:ensure_frames_created() end)
        if not ok then
            local msg = "Quest editor frame creation failed: " .. tostring(err)
            if msg ~= _last_editor_create_error then
                _last_editor_create_error = msg
                log_error(msg)
            end
        else
            _last_editor_create_error = nil
        end
    end
end)

core.register_on_spell_cast_callback(function(data)
    if ensure_initialized() then app:on_spell_cast(data) end
end)

core.register_on_legit_spell_cast_callback(function(data)
    if ensure_initialized() then app:on_legit_spell_cast(data) end
end)

-- Optional render callbacks (no-op by default, registered for extensibility)
core.register_on_render_callback(function()
    if ensure_initialized() then app:on_render() end
end)

local _last_editor_render_error = nil
core.register_on_render_window_callback(function()
    if ensure_initialized() then app:on_render_window() end
    if _questing_editor then
        local ok, err = pcall(function() _questing_editor:_on_render_window() end)
        if not ok then
            local msg = "Quest editor render failed: " .. tostring(err)
            if msg ~= _last_editor_render_error then
                _last_editor_render_error = msg
                log_error(msg)
            end
        else
            _last_editor_render_error = nil
        end
    end
end)

-- Sentinel menu entry
core.register_on_render_menu_callback(function()
    if not ensure_initialized() then return end
    _menu_tree:render("SentinelCore", function()
        if _toggle_editor_btn:render("Open Runner Cockpit") then
            _G.Sentinel.toggle_quest_editor()
        end
    end)
end)

local function on_unload()
    if _questing_editor and type(_questing_editor.destroy) == "function" then
        pcall(_questing_editor.destroy, _questing_editor)
    end
    if app and type(app.shutdown) == "function" then
        app:shutdown()
    end
    app = nil
    initialized = false
    _questing_editor = nil
    _editor_subscribed = false
    _G.Sentinel = nil
end

return {
    name = "SentinelCore",
    version = "0.2.0",
    unload = on_unload,
}
