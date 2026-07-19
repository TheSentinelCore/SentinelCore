-- sentinel/tests/ui/test_console_diagnostics.lua
-- SENT-11.3: runtime diagnostics (validation_failed / reload_rejected /
-- profile_reloaded) are surfaced to the ConsolePanel via log:runtime.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")
local RuntimeEngine = require("runtime/runtime_engine")
local ValidationService = require("runtime/validation_service")
local ConsolePanel = require("ui/panels/console_panel")

local M = {}

function M.run()
    print("=== Console Diagnostics Tests ===")

    local bb = Blackboard:new()
    local eb = EventBus:new()

    local console = ConsolePanel:new(bb, eb)
    console:init()

    local op = {
        id = "op-c",
        goals = { { type = "KillCount", entry = 305, count = 5, required = true } },
        actions = {}, -- uncovered -> will fail
    }
    local profile = { id = "prof-c", name = "Diag", operations = { op } }
    local pm = {
        get_active_profile = function() return profile end,
        get_active_profile_id = function() return "prof-c" end,
    }
    local eng = RuntimeEngine:new(bb, eb, pm, { _state = "idle" })
    eng:set_validation_service(ValidationService:new())

    -- Trigger a failed continuous validation.
    eng:mark_operation_dirty("op-c")
    eng:validate()

    local runtime_logs = console._logs.runtime
    T.assert_true(#runtime_logs >= 1, "console captured a runtime log entry")
    local found_error = false
    for _, entry in ipairs(runtime_logs) do
        if entry.level == "ERROR" and entry.message:find("validation failed") then
            found_error = true
        end
    end
    T.assert_true(found_error, "console shows ERROR for failed validation")

    print("  PASS")
    print("\n=== All Console Diagnostics Tests PASSED ===")
end

return M
