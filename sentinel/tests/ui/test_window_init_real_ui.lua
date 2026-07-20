-- sentinel/tests/ui/test_window_init_real_ui.lua
-- Regression test for the in-game failure:
--   "...ui\panels\quest_browser_panel.lua:39: attempt to call method 'clear' (a nil value)"
-- SentinelApp:initialize now constructs and inits the Window, which builds all
-- 12 editor panels via the REAL RotationSettingsUI (SentinelUI). That class was
-- missing clear()/update()/tick(), so panel _build_ui() crashed during init and
-- the whole UI never rendered. This test exercises the REAL UI module so the
-- missing-method class of bug can never slip through again.
--
-- Combat/Settings panels are mocked (they pull in the combat engine); the
-- editor panels are loaded for real to prove _build_ui() succeeds against the
-- real RotationSettingsUI.

local T = require("tests/test_util")
local Window = require("ui/window")

local M = {}

function M.run()
    print("=== Window init (real SentinelUI) Tests ===")

    -- Real UI module, no mock.
    package.loaded["shared/ui/sentinel_ui"] = nil

    -- Minimal core global so any incidental access during init is benign.
    _G.core = _G.core or {}

    -- Mock combat/settings panels (used by _register_builtin_panels).
    package.loaded["ui/panels/combat_panel"] = {
        new = function()
            return {
                init = function() end,
                tick = function() end,
                update = function() end,
                render = function() end,
                render_window = function() end,
                render_menu = function() end,
                shutdown = function() end,
            }
        end,
    }
    package.loaded["ui/panels/settings_panel"] = {
        new = function()
            return {
                init = function() end,
                tick = function() end,
                update = function() end,
                render = function() end,
                render_window = function() end,
                render_menu = function() end,
                shutdown = function() end,
            }
        end,
    }

    local bb = { get = function() return nil end, set = function() end }
    local eb = { publish = function() end, subscribe = function() end }
    local app_stub = { get_module = function() return nil end }

    local window = Window:new(bb, eb)

    -- The key assertion: init must NOT throw (previously threw on
    -- quest_browser_panel calling self._ui:clear() which didn't exist).
    local ok, err = pcall(function()
        window:init(app_stub)
    end)
    T.assert_true(ok, "Window:init built all editor panels without error" .. (err and (": " .. tostring(err)) or ""))

    T.assert_true(window._initialized == true, "window marked initialized")

    -- All 12 editor panels should be registered as windows.
    local names = window:get_panel_names()
    T.assert_true(#names >= 12, "at least 12 panels registered (got " .. #names .. ")")

    print("  PASS")
    print("\n=== All Window init (real SentinelUI) Tests PASSED ===")
end

return M
