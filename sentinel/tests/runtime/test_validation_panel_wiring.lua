-- sentinel/tests/runtime/test_validation_panel_wiring.lua
-- SENT-8.7 / Phase 10: engine continuous-validation surfaces errors to the
-- existing ValidationPanel via the validation:add / validation:clear contract.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")
local RuntimeEngine = require("runtime/runtime_engine")
local ValidationService = require("runtime/validation_service")
local ValidationPanel = require("ui/panels/validation_panel")

local M = {}

function M.run()
    print("=== ValidationPanel <-> Engine Wiring Tests ===")

    -- Shared event bus so the engine's published events reach the panel.
    local bb = Blackboard:new()
    local eb = EventBus:new()

    local op = {
        id = "op-v",
        goals = { { type = "KillCount", entry = 305, count = 5, required = true } },
        actions = {}, -- intentionally uncovered
    }
    local profile = { id = "prof-v", name = "Wire", operations = { op } }
    local pm = {
        get_active_profile = function() return profile end,
        get_active_profile_id = function() return "prof-v" end,
    }
    local mock_nav = { _state = "idle" }

    local panel = ValidationPanel:new(bb, eb)
    panel:init()

    local eng = RuntimeEngine:new(bb, eb, pm, mock_nav)
    eng:set_validation_service(ValidationService:new())

    -- A freshly-initialized panel has no errors.
    T.assert_equal(#panel:get_errors(), 0, "panel starts with no errors")

    -- Mark the uncovered op dirty and validate; the panel should receive the
    -- validation:clear + validation:add events and now show 1 error.
    eng:mark_operation_dirty("op-v")
    eng:validate()

    local errs = panel:get_errors()
    T.assert_equal(#errs, 1, "panel shows one error after failed validation")
    T.assert_equal(errs[1].entity_ref, "op-v", "error attributed to failing op")
    T.assert_equal(errs[1].severity, "error", "error severity is error")

    -- Fix the profile (add covering action) and re-validate; panel clears.
    profile.operations[1].actions = { { action_type = "grind_area", creature_entry = 305 } }
    eng:mark_operation_dirty("op-v")
    eng:validate()
    T.assert_equal(#panel:get_errors(), 0, "panel clears after valid revalidation")

    print("  PASS")
    print("\n=== All ValidationPanel Wiring Tests PASSED ===")
end

return M
