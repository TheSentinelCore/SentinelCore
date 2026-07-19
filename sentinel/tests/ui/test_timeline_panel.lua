-- sentinel/tests/ui/test_timeline_panel.lua
-- Tests for ui/panels/timeline_panel.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== TimelinePanel Tests ===")

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
                    listbox_selected = { r = 86, g = 140, b = 210, a = 45 },
                }
            }
        end
    }

    -- Mock blackboard
    local mock_operation = nil
    local function create_mock_blackboard()
        return {
            get = function(self, key, default)
                if key == "module.ui.selected_operation" then
                    return mock_operation
                end
                return default
            end,
            set = function(self, key, value)
                if key == "module.ui.selected_operation" then
                    mock_operation = value
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
    package.loaded["ui/panels/timeline_panel"] = nil

    -- Load TimelinePanel
    local TimelinePanel = require("ui/panels/timeline_panel")

    -- Test 1: Panel creation
    print("Test 1: Panel creation")
    local bb = create_mock_blackboard()
    local eb = create_mock_event_bus()
    local panel = TimelinePanel:new(bb, eb)
    T.assert_not_nil(panel, "Panel should be created")
    T.assert_equal(panel._blackboard, bb, "Blackboard should be set")
    T.assert_equal(panel._event_bus, eb, "Event bus should be set")
    print("  PASS")

    -- Test 2: Init
    print("Test 2: Init")
    panel:init()
    T.assert_not_nil(panel._ui, "UI should be created")
    print("  PASS")

    -- Test 3: No operation state
    print("Test 3: No operation state")
    T.assert_nil(panel._operation, "Should have no operation initially")
    T.assert_true(type(panel._actions) == "table", "Actions should be a table")
    T.assert_true(#panel._actions == 0, "Actions should be empty")
    print("  PASS")

    -- Test 4: Set operation
    print("Test 4: Set operation")
    local test_operation = {
        id = "op-1",
        name = "Travel to Camp",
        type = "operation",
        actions = {
            { id = "act-1", type = "movement", name = "Move to Position" },
            { id = "act-2", type = "spell", name = "Cast Spell" },
        }
    }
    panel:set_operation(test_operation)
    T.assert_equal(panel._operation, test_operation, "Operation should be set")
    T.assert_true(#panel._actions == 2, "Should have 2 actions")
    print("  PASS")

    -- Test 5: Action colors
    print("Test 5: Action colors")
    local move_color = panel:_get_action_color("movement")
    T.assert_not_nil(move_color, "Should have movement color")
    T.assert_true(type(move_color.r) == "number", "Color should have r component")

    local spell_color = panel:_get_action_color("spell")
    T.assert_not_nil(spell_color, "Should have spell color")

    local unknown_color = panel:_get_action_color("unknown")
    T.assert_not_nil(unknown_color, "Should have fallback color for unknown type")
    print("  PASS")

    -- Test 6: Selected action tracking
    print("Test 6: Selected action tracking")
    T.assert_nil(panel:get_selected_index(), "No index selected initially")
    T.assert_nil(panel:get_selected_action(), "No action selected initially")

    panel._selected_action_idx = 1
    T.assert_equal(panel:get_selected_index(), 1, "Index should be 1")
    T.assert_equal(panel:get_selected_action().type, "movement", "Action should match")
    print("  PASS")

    -- Test 7: Set actions directly
    print("Test 7: Set actions directly")
    panel:set_actions({
        { id = "act-3", type = "wait", name = "Wait 5s" }
    })
    T.assert_true(#panel._actions == 1, "Should have 1 action")
    T.assert_equal(panel._actions[1].type, "wait", "Action type should match")
    print("  PASS")

    -- Test 8: Shutdown
    print("Test 8: Shutdown")
    panel:shutdown()
    T.assert_nil(panel._ui, "UI should be nil after shutdown")
    print("  PASS")

    print("\n=== All TimelinePanel Tests PASSED ===")
end

return M