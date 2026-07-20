-- sentinel/tests/ui/test_window_render_window.lua
-- Regression test for the editor UI not appearing: on_render_window must
-- iterate ALL registered panels (not just combat/settings) and invoke each
-- visible panel's render_window_fn so they render as poppable windows.

local T = require("tests/test_util")
local Window = require("ui/window")

local M = {}

function M.run()
    print("=== Window on_render_window Tests ===")

    _G.core = _G.core or {}
    _G.core.read_data_file = function() return nil end
    _G.core.write_data_file = function() return true end

    -- Minimal SentinelUI mock so panel modules can be constructed.
    package.loaded["shared/ui/sentinel_ui"] = nil
    _G.SentinelUI = {
        new = function(config)
            return {
                id = config.id,
                add_tab = function() end,
                render = function() end,
                render_window = function() end,
                render_menu = function() end,
                tick = function() end,
                update = function() end,
                set_visible = function() end,
            }
        end,
    }
    -- Mock combat/settings (used by _register_builtin_panels).
    package.loaded["ui/panels/combat_panel"] = {
        new = function() return { init = function() end, tick = function() end, update = function() end, render = function() end, render_window = function() end, render_menu = function() end, shutdown = function() end } end
    }
    package.loaded["ui/panels/settings_panel"] = {
        new = function() return { init = function() end, tick = function() end, update = function() end, render = function() end, render_window = function() end, render_menu = function() end, shutdown = function() end } end
    }

    local calls = {}
    local bb = { get = function() return nil end, set = function() end }
    local eb = { publish = function() end, subscribe = function() end }

    local window = Window:new(bb, eb)
    -- Register two panels with distinct render_window_fn; one hidden.
    window:register_panel("a", function() end, {
        default_visible = true,
        render_window_fn = function() calls.a = true end,
    })
    window:register_panel("b", function() end, {
        default_visible = false,
        render_window_fn = function() calls.b = true end,
    })
    window._initialized = true

    window:on_render_window()

    T.assert_true(calls.a == true, "visible panel a render_window_fn invoked")
    T.assert_true(calls.b ~= true, "hidden panel b render_window_fn NOT invoked")

    print("  PASS")
    print("\n=== All Window on_render_window Tests PASSED ===")
end

return M
