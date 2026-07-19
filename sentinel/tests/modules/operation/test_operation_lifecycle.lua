-- sentinel/tests/modules/operation/test_operation_lifecycle.lua
-- Tests for SENT-5.6: Operation Lifecycle State Machine
-- ADR 007 §13-14

local T = require("tests/test_util")
local Blackboard = require("core/blackboard")

local M = {}

function M.test_initial_status_is_locked()
    print("Test: initial status is Locked")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")

    T.assert_equal(lifecycle:get_status("op-1"), "Locked", "Initial status is Locked")

    print("  PASS")
end

function M.test_locked_to_ready_transition()
    print("Test: Locked → Ready transition")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:transition_to_ready("op-1", true)

    T.assert_equal(lifecycle:get_status("op-1"), "Ready", "Status transitioned to Ready")

    print("  PASS")
end

function M.test_locked_to_skipped_transition()
    print("Test: Locked → Skipped transition (goals already satisfied)")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:transition_to_ready("op-1", false, true)

    T.assert_equal(lifecycle:get_status("op-1"), "Skipped", "Status transitioned to Skipped")
    T.assert_equal(lifecycle:get_skip_reason("op-1"), "Goals already satisfied", "Skip reason recorded")

    print("  PASS")
end

function M.test_ready_to_active_transition()
    print("Test: Ready → Active transition")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:set_status("op-1", "Ready")
    lifecycle:transition_to_active("op-1")

    T.assert_equal(lifecycle:get_status("op-1"), "Active", "Status transitioned to Active")

    print("  PASS")
end

function M.test_active_to_completed_transition()
    print("Test: Active → Completed transition")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:transition_to_ready("op-1", true)
    lifecycle:set_status("op-1", "Active")
    lifecycle:transition_to_completed("op-1")

    T.assert_equal(lifecycle:get_status("op-1"), "Completed", "Status transitioned to Completed")

    print("  PASS")
end

function M.test_active_to_failed_transition()
    print("Test: Active → Failed transition")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:transition_to_ready("op-1", true)
    lifecycle:set_status("op-1", "Active")
    lifecycle:transition_to_failed("op-1")

    T.assert_equal(lifecycle:get_status("op-1"), "Failed", "Status transitioned to Failed")

    print("  PASS")
end

function M.test_active_to_aborted_transition()
    print("Test: Active → Aborted transition")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:transition_to_ready("op-1", true)
    lifecycle:set_status("op-1", "Active")
    lifecycle:transition_to_aborted("op-1")

    T.assert_equal(lifecycle:get_status("op-1"), "Aborted", "Status transitioned to Aborted")

    print("  PASS")
end

function M.test_is_terminal()
    print("Test: is_terminal")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-active")
    lifecycle:transition_to_ready("op-active", true)
    lifecycle:set_status("op-active", "Active")
    T.assert_false(lifecycle:is_terminal("op-active"), "Active is not terminal")

    lifecycle:set_status("op-active", "Completed")
    T.assert_true(lifecycle:is_terminal("op-active"), "Completed is terminal")

    lifecycle:create("op-failed")
    lifecycle:transition_to_ready("op-failed", true)
    lifecycle:set_status("op-failed", "Active")
    lifecycle:set_status("op-failed", "Failed")
    T.assert_true(lifecycle:is_terminal("op-failed"), "Failed is terminal")

    lifecycle:create("op-aborted")
    lifecycle:transition_to_ready("op-aborted", true)
    lifecycle:set_status("op-aborted", "Active")
    lifecycle:set_status("op-aborted", "Aborted")
    T.assert_true(lifecycle:is_terminal("op-aborted"), "Aborted is terminal")

    lifecycle:create("op-skipped")
    lifecycle:set_status("op-skipped", "Skipped")
    T.assert_true(lifecycle:is_terminal("op-skipped"), "Skipped is terminal")

    print("  PASS")
end

function M.test_invalid_transition_rejected()
    print("Test: invalid transition rejected")

    local OperationLifecycle = require("modules/operation/operation_lifecycle")
    local bb = Blackboard:new()
    local lifecycle = OperationLifecycle:new(bb)

    lifecycle:create("op-1")
    lifecycle:set_status("op-1", "Ready")

    local result = lifecycle:set_status("op-1", "Completed")
    T.assert_false(result, "Invalid transition returns false")
    T.assert_equal(lifecycle:get_status("op-1"), "Ready", "Status unchanged on invalid transition")

    print("  PASS")
end

function M.run()
    print("=== Operation Lifecycle Tests ===")
    M.test_initial_status_is_locked()
    M.test_locked_to_ready_transition()
    M.test_locked_to_skipped_transition()
    M.test_ready_to_active_transition()
    M.test_active_to_completed_transition()
    M.test_active_to_failed_transition()
    M.test_active_to_aborted_transition()
    M.test_is_terminal()
    M.test_invalid_transition_rejected()
    print("\n=== All Operation Lifecycle Tests PASSED ===")
end

return M