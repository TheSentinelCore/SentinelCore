local SentinelCore = require("init")
local UIWindow = require("ui/window")
local _is_loaded = false
rawset(_G, "__SentinelCoreHostCore", rawget(_G, "__SentinelCoreHostCore") or rawget(_G, "core"))
rawset(_G, "__SentinelCoreHostNavClient", rawget(_G, "__SentinelCoreHostNavClient") or rawget(_G, "SentinelNavClient"))

local _menu_tree = core.menu.tree_node()
local _open_button = core.menu.button("sc_open")
local _start_stop_button = core.menu.button("sc_start_stop")

local function on_load()
    if _is_loaded then
        return
    end

    local ok, err = SentinelCore:initialize({})
    if not ok then
        if core and core.log_error then
            core.log_error("[SentinelCore] Initialization failed: " .. tostring(err))
        end
        return
    end

    local client = SentinelCore:get_client()
    if client then
        UIWindow.init(client)
    end

    _is_loaded = true
    if core and core.log then
        core.log("[SentinelCore] Loaded")
    end
end

on_load()

core.register_on_update_callback(function()
    if not _is_loaded then
        return
    end
    local client = SentinelCore:get_client()
    if client and client.update then
        client:update()
    end
end)

core.register_on_render_menu_callback(function()
    if not _is_loaded then
        return
    end

    UIWindow.on_menu_render()

    _menu_tree:render("SentinelCore", function()
        if _open_button:render("Open Settings") then
            local ui = UIWindow.get_ui()
            if ui and ui.menu and ui.menu.enable then
                ui.menu.enable:set(not ui.menu.enable:get_state())
            end
        end

        if _start_stop_button:render("Start/Stop") then
            local client = SentinelCore:get_client()
            if client then
                local state = client:get_state()
                if state == "idle" or state == "failed" then
                    client:start("grind")
                else
                    client:stop("menu_stop")
                end
            end
        end
    end)
end)

core.register_on_render_callback(function()
    if not _is_loaded then
        return
    end

    UIWindow.on_render()
end)

_G.SentinelCore = {
    create = function(config)
        SentinelCore:initialize(config)
        return SentinelCore:get_client()
    end,
    ui = UIWindow,
    run_tests = function()
        local host_core = rawget(_G, "__SentinelCoreHostCore") or rawget(_G, "core")
        local host_nav = rawget(_G, "__SentinelCoreHostNavClient") or rawget(_G, "SentinelNavClient")
        local host_sc = rawget(_G, "SentinelCore")

        for name, _ in pairs(package.loaded) do
            if type(name) == "string" and name:find("^tests/", 1, false) then
                package.loaded[name] = nil
            end
        end

        local ok_runner, runner = pcall(require, "tests/run_all")
        if not ok_runner or not runner or type(runner.run_all) ~= "function" then
            rawset(_G, "core", host_core)
            rawset(_G, "SentinelNavClient", host_nav)
            rawset(_G, "SentinelCore", host_sc)
            return {
                passed = 0,
                failed = 1,
                results = {
                    ["tests/run_all"] = { error = tostring(runner) },
                },
            }
        end

        local ok_result, result = pcall(runner.run_all)
        rawset(_G, "core", host_core)
        rawset(_G, "SentinelNavClient", host_nav)
        rawset(_G, "SentinelCore", host_sc)
        if ok_result then
            return result
        end
        return {
            passed = 0,
            failed = 1,
            results = {
                ["tests/run_all"] = { error = tostring(result) },
            },
        }
    end,
    VERSION = SentinelCore.VERSION,
}

setmetatable(_G.SentinelCore, {
    __index = function(_, key)
        if key == "client" then
            return SentinelCore:get_client()
        end
    end,
})

local function on_unload()
    SentinelCore:destroy()
    _G.SentinelCore = nil
    _is_loaded = false
end

return {
    name = "SentinelCore",
    version = SentinelCore.VERSION,
    unload = on_unload,
}
