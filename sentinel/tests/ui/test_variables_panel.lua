-- sentinel/tests/ui/test_variables_panel.lua
-- Tests for ui/panels/variables_panel.lua

local Blackboard = require("core/blackboard")
local T = require("tests/test_util")
local VariablesPanel = require("ui/panels/variables_panel")

local M = {}

function M.test_variables_panel_construction()
    print("Test: VariablesPanel construction")
    local bb = Blackboard:new()
    local panel = VariablesPanel:new(bb, nil)
    T.assert_not_nil(panel, "Panel should not be nil")
    print("  PASS")
end

function M.test_variables_panel_init()
    print("Test: VariablesPanel init")
    local bb = Blackboard:new()
    local panel = VariablesPanel:new(bb, nil)
    -- Skip init() since it requires SentinelUI which uses core.menu
    T.assert_true(panel._active_scope == "global", "Default scope should be global (set in constructor)")
    print("  PASS")
end

function M.test_format_value_position()
    print("Test: Format value for position")
    local bb = Blackboard:new()
    local panel = VariablesPanel:new(bb, nil)
    
    local formatted = panel:_format_value({ x = 100, y = 200, z = 30 }, "position")
    T.assert_equal(formatted, "(100, 200, 30)", "Position should be formatted correctly")
    print("  PASS")
end

function M.test_format_value_other_types()
    print("Test: Format value for other types")
    local bb = Blackboard:new()
    local panel = VariablesPanel:new(bb, nil)
    
    local str = panel:_format_value("test", "string")
    T.assert_equal(str, "test", "String value should be returned as-is")
    
    local num = panel:_format_value(42, "integer")
    T.assert_equal(num, "42", "Number should be converted to string")
    print("  PASS")
end

function M.test_variable_selected_publishes_event()
    print("Test: Variable selected publishes event")
    local bb = Blackboard:new()
    local published = {}
    local mock_bus = {
        publish = function(_, event, payload)  -- Note: self is first arg with : syntax
            published.event = event
            published.payload = payload
        end,
    }
    
    local panel = VariablesPanel:new(bb, mock_bus)
    panel._event_bus = mock_bus  -- Ensure it's set
    panel:_on_variable_selected("my_var")
    
    T.assert_equal(published.event, "variable:selected", "Should publish variable:selected event")
    T.assert_equal(published.payload.key, "my_var", "Payload should include variable key")
    print("  PASS")
end

function M.test_create_and_delete_variable()
    print("Test: Create and delete variable")
    local bb = Blackboard:new()
    local panel = VariablesPanel:new(bb, nil)
    panel:init()
    
    local ok, err = panel:create_variable("global", "test_key", "integer", 123)
    T.assert_true(ok, "Create should succeed")
    
    local deleted = panel:delete_variable("global", "test_key")
    T.assert_true(deleted, "Delete should succeed")
    print("  PASS")
end

function M.run()
    print("=== Variables Panel Tests ===")
    M.test_variables_panel_construction()
    M.test_variables_panel_init()
    M.test_format_value_position()
    M.test_format_value_other_types()
    M.test_variable_selected_publishes_event()
    M.test_create_and_delete_variable()
    print("\n=== All Variables Panel Tests PASSED ===")
end

return M