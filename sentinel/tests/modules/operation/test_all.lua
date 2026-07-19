-- sentinel/tests/modules/operation/test_all.lua
-- Test runner for all Phase 5 Operation System Logic tests

local TestUtil = require("tests/test_util")

local M = {}

local function run_all()
    local all_passed = true
    local results = {}

    local test_files = {
        "tests/modules/operation/test_goal_coverage",
        "tests/modules/operation/test_condition_evaluator",
        "tests/modules/operation/test_dependency_graph",
        "tests/modules/operation/test_cycle_detector",
        "tests/modules/operation/test_topological_sort",
        "tests/modules/operation/test_operation_lifecycle",
        "tests/modules/operation/test_sub_operation_composer",
    }

    for _, module_name in ipairs(test_files) do
        package.loaded[module_name] = nil
    end

    print("=" .. string.rep("=", 50))
    print("Running Phase 5 Operation System Logic Tests")
    print("=" .. string.rep("=", 50))

    for _, module_name in ipairs(test_files) do
        local ok, test_module = pcall(require, module_name)
        if ok and test_module and type(test_module.run) == "function" then
            local result = TestUtil.run(module_name, test_module.run)
            if not result.ok then
                all_passed = false
                print("FAILED: " .. module_name .. " - " .. tostring(result.err))
            else
                print("PASSED: " .. module_name)
            end
        else
            all_passed = false
            print("FAILED: " .. module_name .. " - could not load")
        end
    end

    print("")
    print("=" .. string.rep("=", 50))
    if all_passed then
        print("ALL PHASE 5 TESTS PASSED")
    else
        print("SOME TESTS FAILED")
    end
    print("=" .. string.rep("=", 50))

    return all_passed
end

function M.run()
    run_all()
end

return M