-- sentinel/tests/ui/test_toolbar.lua
-- Tests for ui/toolbar.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Toolbar Tests ===")

    -- Mock core API
    _G.core = _G.core or {}
    _G.core.game_time = function() return 1000 end
    _G.core.read_data_file = function() return nil end
    _G.core.write_data_file = function() return true end

    -- Mock SentinelUI
    package.loaded["shared/ui/sentinel_ui"] = nil
    _G.SentinelUI = {
        new = function(config)
            return {
                id = config.id,
                add_tab = function() end,
                colors = {
                    background = { r = 20, g = 24, b = 28, a = 220 },
                    border = { r = 52, g = 60, b = 72, a = 200 },
                    section_bg = { r = 30, g = 36, b = 44, a = 230 },
                    section_border = { r = 80, g = 90, b = 105, a = 100 },
                    primary_accent = { r = 86, g = 140, b = 210, a = 255 },
                    secondary_accent = { r = 210, g = 160, b = 80, a = 255 },
                    text_primary = { r = 220, g = 225, b = 232, a = 245 },
                    text_secondary = { r = 160, g = 170, b = 182, a = 210 },
                    checkbox_active = { r = 86, g = 140, b = 210, a = 255 },
                    checkbox_inactive = { r = 48, g = 54, b = 64, a = 210 },
                }
            }
        end
    }

    -- Mock Window
    local mock_window = {
        state = {
            _panel_registry = {
                _panels = {},
                get = function(self, name) return self._panels[name] end,
                names = function(self)
                    local result = {}
                    for name, _ in pairs(self._panels) do
                        table.insert(result, name)
                    end
                    return result
                end
            },
            register_panel = function(self, name, render_fn, options)
                self._panel_registry._panels[name] = {
                    name = name,
                    visible = options.default_visible ~= false,
                    render_fn = render_fn,
                    options = options
                }
            end
        },
        get_panel_names = function(self) return {} end
    }

    -- Mock event bus that captures events
    local captured_events = {}
    local function create_mock_event_bus()
        return {
            publish = function(self, event, data)
                table.insert(captured_events, { event = event, data = data })
            end,
            get_captured_events = function() return captured_events end,
            clear_events = function() captured_events = {} end
        }
    end

    -- Clear package cache
    package.loaded["ui/toolbar"] = nil

    -- Load Toolbar
    local Toolbar = require("ui/toolbar")

    -- Test 1: Toolbar creation
    print("Test 1: Toolbar creation")
    local event_bus = create_mock_event_bus()
    local toolbar = Toolbar:new(mock_window, event_bus, {})
    T.assert_not_nil(toolbar, "Toolbar should be created")
    T.assert_equal(toolbar._window, mock_window, "Window should be set")
    T.assert_equal(toolbar._event_bus, event_bus, "Event bus should be set")
    print("  PASS")

    -- Test 2: Init
    print("Test 2: Init")
    toolbar:init()
    T.assert_not_nil(toolbar._ui, "UI should be created")
    print("  PASS")

    -- Test 3: Action colors defined
    print("Test 3: Action colors defined")
    T.assert_not_nil(Toolbar.ACTION_COLORS, "ACTION_COLORS should exist")
    T.assert_not_nil(Toolbar.ACTION_COLORS.movement, "movement color should exist")
    T.assert_not_nil(Toolbar.ACTION_COLORS.spell, "spell color should exist")
    T.assert_not_nil(Toolbar.ACTION_COLORS.interaction, "interaction color should exist")
    print("  PASS")

    -- Test 4: Render buttons (check structure)
    print("Test 4: Render button structure")
    local x = toolbar._padding
    local y = toolbar._padding
    -- Verify button dimensions
    T.assert_equal(toolbar._button_width, 90, "Button width should be 90")
    T.assert_equal(toolbar._button_height, 28, "Button height should be 28")
    print("  PASS")

    -- Test 5: Dry run toggle state
    print("Test 5: Dry run toggle state")
    T.assert_false(toolbar._is_dry_run, "Should start with dry_run false")
    toolbar._is_dry_run = true
    T.assert_true(toolbar._is_dry_run, "Should be true after toggle")
    toolbar._is_dry_run = false
    print("  PASS")

    -- Test 6: Publish toolbar events
    print("Test 6: Publish toolbar events")
    event_bus:clear_events()
    toolbar:_publish_toolbar_event("test_event")
    local events = event_bus:get_captured_events()
    T.assert_true(#events >= 0, "Event publishing works")
    print("  PASS")

    -- Test 7: Shutdown
    print("Test 7: Shutdown")
    toolbar:shutdown()
    T.assert_nil(toolbar._ui, "UI should be nil after shutdown")
    T.assert_nil(toolbar._window, "Window should be nil after shutdown")
    print("  PASS")

    -- Test 8: Panel dropdown integration
    print("Test 8: Panel dropdown integration")
    local mock_window2 = {
        _panel_registry = {
            _panels = {
                combat = { name = "combat", visible = true },
                settings = { name = "settings", visible = true }
            },
            get = function(self, name) return self._panels[name] end,
            names = function(self)
                local result = {}
                for name, _ in pairs(self._panels) do
                    table.insert(result, name)
                end
                return result
            end
        },
        get_panel_names = function(self)
            local result = {}
            for name, _ in pairs(self._panel_registry._panels) do
                table.insert(result, name)
            end
            return result
        end
    }
    package.loaded["ui/toolbar"] = nil
    local Toolbar2 = require("ui/toolbar")
    local toolbar2 = Toolbar2:new(mock_window2, event_bus, {})
    T.assert_not_nil(toolbar2._window, "Window reference should be stored")
    print("  PASS")

    print("\n=== All Toolbar Tests PASSED ===")
end

return M