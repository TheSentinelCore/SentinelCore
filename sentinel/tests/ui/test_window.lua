-- sentinel/tests/ui/test_window.lua
-- Tests for ui/window.lua panel system

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Window Panel System Tests ===")

    -- Mock core API
    _G.core = _G.core or {}
    _G.core.read_data_file = function() return nil end
    _G.core.write_data_file = function() return true end
    _G.core.game_time = function() return 0 end

    -- Mock SentinelUI
    package.loaded["shared/ui/sentinel_ui"] = nil
    _G.SentinelUI = {
        new = function(config)
            return {
                id = config.id,
                title = config.title,
                add_tab = function(self, tab, fn) end,
                render = function() end,
                render_window = function() end,
                render_menu = function() end,
                tick = function() end,
                update = function() end,
            }
        end
    }

    -- Mock panels (minimal)
    package.loaded["ui/panels/combat_panel"] = {
        new = function() return { init = function() end, tick = function() end, update = function() end, render = function() end, render_window = function() end, render_menu = function() end, shutdown = function() end } end
    }
    package.loaded["ui/panels/settings_panel"] = {
        new = function() return { init = function() end, tick = function() end, update = function() end, render = function() end, render_window = function() end, render_menu = function() end, shutdown = function() end } end
    }

    -- Mock event bus
    local function create_mock_event_bus()
        local events = {}
        return {
            publish = function(self, event, data)
                table.insert(events, { event = event, data = data })
            end,
            get_events = function() return events end,
            clear_events = function() events = {} end
        }
    end

    -- Mock blackboard
    local function create_mock_blackboard()
        local data = {}
        return {
            get = function(self, key, default)
                return data[key] or default
            end,
            set = function(self, key, value)
                data[key] = value
            end,
            clear = function(self, key)
                data[key] = nil
            end
        }
    end

    -- Clear package cache to get fresh Window
    package.loaded["ui/window"] = nil

    local Window = require("ui/window")

    -- Test 1: Window creation
    print("Test 1: Window creation")
    local bb = create_mock_blackboard()
    local eb = create_mock_event_bus()
    local window = Window:new(bb, eb)
    T.assert_not_nil(window, "Window should be created")
    T.assert_equal(window._blackboard, bb, "Blackboard should be set")
    T.assert_equal(window._event_bus, eb, "Event bus should be set")
    T.assert_not_nil(window._panel_registry, "Panel registry should exist")
    print("  PASS")

    -- Test 2: Panel registration
    print("Test 2: Panel registration")
    local render_fn_called = false
    local function test_render()
        render_fn_called = true
    end

    local success = window:register_panel("test_panel", test_render, {
        default_visible = true,
        dock = "left",
        width = 300,
        title = "Test Panel"
    })
    T.assert_true(success, "register_panel should succeed")

    local panel = window:get_panel("test_panel")
    T.assert_not_nil(panel, "Panel should be retrievable")
    T.assert_true(panel.visible, "Panel should be visible by default")
    T.assert_equal(panel.options.dock, "left", "Dock option should be set")
    T.assert_equal(panel.options.width, 300, "Width should be set")
    T.assert_equal(panel.options.title, "Test Panel", "Title should be set")
    print("  PASS")

    -- Test 3: Show/hide/toggle panel
    print("Test 3: Show/hide/toggle panel")
    window:register_panel("toggle_test", function() end, { default_visible = false })

    local panel2 = window:get_panel("toggle_test")
    T.assert_false(panel2.visible, "Panel should start hidden")

    window:show_panel("toggle_test")
    local panel2_shown = window:get_panel("toggle_test")
    T.assert_true(panel2_shown.visible, "Panel should be visible after show_panel")

    window:hide_panel("toggle_test")
    local panel2_hidden = window:get_panel("toggle_test")
    T.assert_false(panel2_hidden.visible, "Panel should be hidden after hide_panel")

    window:toggle_panel("toggle_test")
    local panel2_toggled = window:get_panel("toggle_test")
    T.assert_true(panel2_toggled.visible, "Panel should be visible after toggle")

    print("  PASS")

    -- Test 4: Panel visibility persists
    print("Test 4: Panel visibility persists")
    window:register_panel("persist_test", function() end, { default_visible = true })
    window:hide_panel("persist_test")

    local persisted = window:get_panel("persist_test")
    T.assert_false(persisted.visible, "Visibility change should persist")
    print("  PASS")

    -- Test 5: Get non-existent panel
    print("Test 5: Get non-existent panel")
    local missing = window:get_panel("nonexistent_panel")
    T.assert_nil(missing, "get_panel should return nil for non-existent panel")
    print("  PASS")

    -- Test 6: Layout save
    print("Test 6: Layout save")
    window:register_panel("save_test", function() end, { default_visible = true })
    local saved = window:save_layout()
    T.assert_true(saved, "save_layout should return true")
    print("  PASS")

    -- Test 7: Panel names list
    print("Test 7: Panel names list")
    local names = window:get_panel_names()
    T.assert_true(type(names) == "table", "panel_names should be a table")
    T.assert_true(#names > 0, "should have panel names")
    print("  PASS")

    -- Test 8: Panel options defaults
    print("Test 8: Panel options defaults")
    window:register_panel("defaults_test", function() end, {})

    local panel_defaults = window:get_panel("defaults_test")
    T.assert_equal(panel_defaults.options.dock, "center", "Default dock should be center")
    T.assert_true(panel_defaults.options.default_visible, "Default visible should be true")
    print("  PASS")

    print("\n=== All Window Tests PASSED ===")
end

return M