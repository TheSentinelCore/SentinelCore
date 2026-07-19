-- sentinel/tests/ui/test_inspector_panel.lua
-- Tests for ui/panels/inspector_panel.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== InspectorPanel Tests ===")

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
                    checkbox_active = { r = 86, g = 140, b = 210, a = 255 },
                    checkbox_inactive = { r = 48, g = 54, b = 64, a = 210 },
                    checkbox_border = { r = 72, g = 82, b = 96, a = 200 },
                    listbox_selected = { r = 86, g = 140, b = 210, a = 45 },
                    status_green = { r = 72, g = 200, b = 110, a = 255 },
                    status_orange = { r = 235, g = 150, b = 40, a = 255 },
                    status_purple = { r = 170, g = 100, b = 230, a = 255 },
                }
            }
        end
    }

    -- Mock blackboard with selection
    local mock_selection = nil
    local function create_mock_blackboard()
        return {
            get = function(self, key, default)
                if key == "module.ui.selected" then
                    return mock_selection
                end
                return default
            end,
            set = function(self, key, value)
                if key == "module.ui.selected" then
                    mock_selection = value
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
    package.loaded["ui/panels/inspector_panel"] = nil

    -- Load InspectorPanel
    local InspectorPanel = require("ui/panels/inspector_panel")

    -- Test 1: Panel creation
    print("Test 1: Panel creation")
    local bb = create_mock_blackboard()
    local eb = create_mock_event_bus()
    local panel = InspectorPanel:new(bb, eb)
    T.assert_not_nil(panel, "Panel should be created")
    T.assert_equal(panel._blackboard, bb, "Blackboard should be set")
    T.assert_equal(panel._event_bus, eb, "Event bus should be set")
    print("  PASS")

    -- Test 2: Init
    print("Test 2: Init")
    panel:init()
    T.assert_not_nil(panel._ui, "UI should be created")
    print("  PASS")

    -- Test 3: No selection state
    print("Test 3: No selection state")
    T.assert_nil(panel._selected_object, "Should have no selected object initially")
    mock_selection = nil
    panel:update()
    T.assert_nil(panel._selected_object, "Should still have no selection")
    print("  PASS")

    -- Test 4: Set selection
    print("Test 4: Set selection")
    local test_obj = { id = "obj-1", name = "Test Object", type = "test" }
    panel:set_selected(test_obj)
    T.assert_equal(panel._selected_object, test_obj, "Selection should be set")
    T.assert_equal(panel._selected_object.name, "Test Object", "Selection name should match")
    print("  PASS")

    -- Test 5: Get object properties
    print("Test 5: Get object properties")
    local props = panel:_get_object_properties(test_obj)
    T.assert_true(type(props) == "table", "Properties should be a table")
    T.assert_true(#props > 0, "Should have properties")
    -- Check that id, name, type are included
    local has_id, has_name, has_type = false, false, false
    for _, p in ipairs(props) do
        if p.key == "id" then has_id = true end
        if p.key == "name" then has_name = true end
        if p.key == "type" then has_type = true end
    end
    T.assert_true(has_id, "Should have id property")
    T.assert_true(has_name, "Should have name property")
    T.assert_true(has_type, "Should have type property")
    print("  PASS")

    -- Test 6: Operation properties
    print("Test 6: Operation properties")
    local op_obj = {
        id = "op-1",
        name = "Test Op",
        type = "operation",
        conditions = { { type = "health", value = 50 } },
        recovery = "retry"
    }
    local op_props = panel:_get_object_properties(op_obj)
    local has_conditions, has_recovery = false, false
    for _, p in ipairs(op_props) do
        if p.key == "conditions" then has_conditions = true end
        if p.key == "recovery" then has_recovery = true end
    end
    T.assert_true(has_conditions, "Should have conditions property")
    T.assert_true(has_recovery, "Should have recovery property")
    print("  PASS")

    -- Test 7: Selection from blackboard
    print("Test 7: Selection from blackboard")
    eb:clear_events()
    mock_selection = { id = "obj-2", name = "New Selection", type = "new" }
    panel:update()
    T.assert_not_nil(panel._selected_object, "Should have selection from blackboard")
    T.assert_equal(panel._selected_object.name, "New Selection", "Selection should match")
    print("  PASS")

    -- Test 8: Shutdown
    print("Test 8: Shutdown")
    panel:shutdown()
    T.assert_nil(panel._ui, "UI should be nil after shutdown")
    T.assert_nil(panel._blackboard, "Blackboard should be nil after shutdown")
    print("  PASS")

    print("\n=== All InspectorPanel Tests PASSED ===")
end

return M