-- sentinel/tests/ui/test_console_panel.lua
-- Tests for ui/panels/console_panel.lua

local T = require("tests/test_util")

local M = {}

function M.test_console_panel_construction()
    print("Test: ConsolePanel construction")
    local ConsolePanel = require("ui/panels/console_panel")
    local panel = ConsolePanel:new(nil, nil)
    T.assert_not_nil(panel, "Panel should not be nil")
    print("  PASS")
end

function M.test_console_panel_init()
    print("Test: ConsolePanel init")
    local ConsolePanel = require("ui/panels/console_panel")
    local panel = ConsolePanel:new(nil, nil)
    local ok = panel:init()
    T.assert_true(ok, "Init should succeed")
    T.assert_not_nil(panel._ui, "UI should be initialized")
    T.assert_equal(#panel._ui.sections, 3, "Should have 3 tabs (Editor, Compiler, Runtime)")
    print("  PASS")
end

function M.test_log_to_tab()
    print("Test: Log to tab")
    local ConsolePanel = require("ui/panels/console_panel")
    local panel = ConsolePanel:new(nil, nil)
    panel:init()
    
    panel:log("editor", "INFO", "Test message")
    
    local logs = panel:get_logs("editor")
    T.assert_equal(#logs, 1, "Should have 1 log entry")
    T.assert_equal(logs[1].level, "INFO", "Log should have correct level")
    T.assert_equal(logs[1].message, "Test message", "Log should have correct message")
    print("  PASS")
end

function M.test_clear_tab()
    print("Test: Clear tab")
    local ConsolePanel = require("ui/panels/console_panel")
    local panel = ConsolePanel:new(nil, nil)
    panel:init()
    
    panel:log("editor", "INFO", "Message 1")
    panel:log("editor", "INFO", "Message 2")
    panel:log("compiler", "INFO", "Compiler message")
    
    panel:clear("editor")
    
    T.assert_equal(#panel:get_logs("editor"), 0, "Editor tab should be empty")
    T.assert_equal(#panel:get_logs("compiler"), 1, "Compiler tab should still have entries")
    print("  PASS")
end

function M.test_clear_all()
    print("Test: Clear all tabs")
    local ConsolePanel = require("ui/panels/console_panel")
    local panel = ConsolePanel:new(nil, nil)
    panel:init()
    
    panel:log("editor", "INFO", "Message")
    panel:log("compiler", "INFO", "Message")
    panel:log("runtime", "INFO", "Message")
    
    panel:clear()
    
    T.assert_equal(#panel:get_logs("editor"), 0, "Editor should be empty")
    T.assert_equal(#panel:get_logs("compiler"), 0, "Compiler should be empty")
    T.assert_equal(#panel:get_logs("runtime"), 0, "Runtime should be empty")
    print("  PASS")
end

function M.test_is_open()
    print("Test: Search panel is_open")
    local SearchPanel = require("ui/panels/search_panel")
    local panel = SearchPanel:new(nil, nil)
    
    T.assert_false(panel:is_open(), "Should not be open initially")
    
    panel:open()
    T.assert_true(panel:is_open(), "Should be open after open()")
    
    panel:close()
    T.assert_false(panel:is_open(), "Should be closed after close()")
    print("  PASS")
end

function M.run()
    print("=== Console Panel Tests ===")
    M.test_console_panel_construction()
    M.test_console_panel_init()
    M.test_log_to_tab()
    M.test_clear_tab()
    M.test_clear_all()
    M.test_is_open()
    print("\n=== All Console Panel Tests PASSED ===")
end

return M