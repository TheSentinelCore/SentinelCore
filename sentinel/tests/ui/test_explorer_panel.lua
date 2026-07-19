-- sentinel/tests/ui/test_explorer_panel.lua
-- Tests for ui/panels/explorer_panel.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== ExplorerPanel Tests ===")

    -- Mock core API
    _G.core = _G.core or {}
    _G.core.game_time = function() return 1000 end

    -- Mock SentinelUI
    package.loaded["shared/ui/sentinel_ui"] = nil
    _G.SentinelUI = {
        new = function(config)
            return {
                id = config.id,
                add_tab = function() end,
                colors = {
                    text_primary = { r = 220, g = 225, b = 232, a = 245 },
                    text_secondary = { r = 160, g = 170, b = 182, a = 210 },
                    text_disabled = { r = 100, g = 108, b = 118, a = 170 },
                    primary_accent = { r = 86, g = 140, b = 210, a = 255 },
                    secondary_accent = { r = 210, g = 160, b = 80, a = 255 },
                    status_green = { r = 72, g = 200, b = 110, a = 255 },
                    status_orange = { r = 235, g = 150, b = 40, a = 255 },
                    status_purple = { r = 170, g = 100, b = 230, a = 255 },
                    listbox_selected = { r = 86, g = 140, b = 210, a = 45 },
                }
            }
        end
    }

    -- Mock blackboard with profile
    local mock_profile = nil
    local function create_mock_blackboard()
        return {
            get = function(self, key, default)
                if key == "module.runtime.active_profile" then
                    return mock_profile
                end
                return default
            end,
            set = function(self, key, value)
                if key == "module.runtime.active_profile" then
                    mock_profile = value
                end
            end
        }
    end

    -- Mock event bus
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
    package.loaded["ui/panels/explorer_panel"] = nil

    -- Load ExplorerPanel
    local ExplorerPanel = require("ui/panels/explorer_panel")

    -- Test 1: Panel creation
    print("Test 1: Panel creation")
    local bb = create_mock_blackboard()
    local eb = create_mock_event_bus()
    local panel = ExplorerPanel:new(bb, eb)
    T.assert_not_nil(panel, "Panel should be created")
    T.assert_equal(panel._blackboard, bb, "Blackboard should be set")
    T.assert_equal(panel._event_bus, eb, "Event bus should be set")
    T.assert_equal(panel._indent_width, 20, "Indent width should be 20")
    print("  PASS")

    -- Test 2: Init
    print("Test 2: Init")
    panel:init()
    T.assert_not_nil(panel._ui, "UI should be created")
    print("  PASS")

    -- Test 3: No profile state
    print("Test 3: No profile state")
    T.assert_nil(panel._profile, "Should have no profile initially")
    print("  PASS")

    -- Test 4: Profile from blackboard
    print("Test 4: Profile from blackboard")
    eb:clear_events()
    mock_profile = {
        name = "Test Profile",
        operations = {
            { id = "op-1", name = "Movement Op", actions = {} },
            { id = "op-2", name = "Combat Op", actions = {} }
        }
    }
    panel:update()
    T.assert_not_nil(panel._profile, "Should have profile from blackboard")
    T.assert_equal(panel._profile.name, "Test Profile", "Profile name should match")
    print("  PASS")

    -- Test 5: Action colors
    print("Test 5: Action colors")
    local move_color = panel:_get_action_color("movement")
    T.assert_not_nil(move_color, "Should have movement color")

    local spell_color = panel:_get_action_color("spell")
    T.assert_not_nil(spell_color, "Should have spell color")

    local unknown_color = panel:_get_action_color("unknown")
    T.assert_not_nil(unknown_color, "Should have fallback color")
    print("  PASS")

    -- Test 6: Operation expansion state
    print("Test 6: Operation expansion state")
    T.assert_true(type(panel._expanded_ops) == "table", "Expanded ops should be a table")
    panel._expanded_ops["op-1"] = false
    T.assert_false(panel._expanded_ops["op-1"], "Op should be collapsed when set to false")
    print("  PASS")

    -- Test 7: Selected operation
    print("Test 7: Selected operation")
    T.assert_nil(panel._selected_operation, "Nothing selected initially")
    panel._selected_operation = "op-1"
    T.assert_equal(panel._selected_operation, "op-1", "Selection should be set")
    print("  PASS")

    -- Test 8: Shutdown
    print("Test 8: Shutdown")
    panel:shutdown()
    T.assert_nil(panel._ui, "UI should be nil after shutdown")
    print("  PASS")

    print("\n=== All ExplorerPanel Tests PASSED ===")
end

return M