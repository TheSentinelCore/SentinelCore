-- sentinel/tests/ui/test_validation_panel.lua
-- Tests for ui/panels/validation_panel.lua

local T = require("tests/test_util")

local M = {}

function M.test_validation_panel_construction()
    print("Test: ValidationPanel construction")
    local ValidationPanel = require("ui/panels/validation_panel")
    local panel = ValidationPanel:new(nil, nil)
    T.assert_not_nil(panel, "Panel should not be nil")
    print("  PASS")
end

function M.test_validation_panel_init()
    print("Test: ValidationPanel init")
    local ValidationPanel = require("ui/panels/validation_panel")
    local panel = ValidationPanel:new(nil, nil)
    local ok = panel:init()
    T.assert_true(ok, "Init should succeed")
    T.assert_not_nil(panel._ui, "UI should be initialized")
    T.assert_equal(#panel._errors, 0, "Initial errors should be empty")
    print("  PASS")
end

function M.test_add_error()
    print("Test: Add error")
    local ValidationPanel = require("ui/panels/validation_panel")
    local panel = ValidationPanel:new(nil, nil)
    panel:init()
    
    panel:add("error", "E001", "Missing field", { type = "operation", id = "op_1" })
    
    T.assert_equal(#panel._errors, 1, "Should have 1 error")
    T.assert_equal(panel._errors[1].severity, "error", "Error should have correct severity")
    T.assert_equal(panel._errors[1].message, "Missing field", "Error should have correct message")
    print("  PASS")
end

function M.test_filtered_count()
    print("Test: Filtered count")
    local ValidationPanel = require("ui/panels/validation_panel")
    local panel = ValidationPanel:new(nil, nil)
    panel:init()
    
    panel:add("error", "E001", "Error 1")
    panel:add("warning", "W001", "Warning 1")
    panel:add("info", "I001", "Info 1")
    
    local count_with_all = panel:_get_filtered_count()
    T.assert_equal(count_with_all, 3, "Should count all when all filters enabled")
    
    panel._show_warnings = false
    panel._show_info = false
    local count_errors_only = panel:_get_filtered_count()
    T.assert_equal(count_errors_only, 1, "Should count only errors")
    print("  PASS")
end

function M.test_clear_errors()
    print("Test: Clear errors")
    local ValidationPanel = require("ui/panels/validation_panel")
    local panel = ValidationPanel:new(nil, nil)
    panel:init()
    
    panel:add("error", "E001", "Error 1")
    panel:add("warning", "W001", "Warning 1")
    
    panel:clear()
    
    T.assert_equal(#panel._errors, 0, "Errors should be cleared")
    print("  PASS")
end

function M.test_get_errors()
    print("Test: Get errors")
    local ValidationPanel = require("ui/panels/validation_panel")
    local panel = ValidationPanel:new(nil, nil)
    panel:init()
    
    panel:add("error", "E001", "Error 1")
    panel:add("error", "E002", "Error 2")
    
    local errors = panel:get_errors()
    T.assert_equal(#errors, 2, "Should return all errors")
    print("  PASS")
end

function M.run()
    print("=== Validation Panel Tests ===")
    M.test_validation_panel_construction()
    M.test_validation_panel_init()
    M.test_add_error()
    M.test_filtered_count()
    M.test_clear_errors()
    M.test_get_errors()
    print("\n=== All Validation Panel Tests PASSED ===")
end

return M