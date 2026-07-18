#!/usr/bin/env lua
-- sentinel/tests/run_tests.lua
-- Test runner for out-of-game tests

package.path = package.path .. ";sentinel/?.lua;sentinel/?/init.lua;tests/harness/?.lua"

local function run_test_file(filepath, name)
    print("========================================")
    print("Running: " .. name)
    print("========================================")

    local ok, err = pcall(dofile, filepath)
    if not ok then
        print("FAILED: " .. tostring(err))
        return false
    end
    print("PASSED: " .. name .. "\n")
    return true
end

local tests = {
    { path = "sentinel/tests/unit/core/test_blackboard.lua", name = "Blackboard" },
    { path = "sentinel/tests/unit/core/test_event_bus.lua", name = "EventBus" },
    { path = "sentinel/tests/unit/core/test_geometry.lua", name = "Geometry" },
}

local passed = 0
local failed = 0

for _, test in ipairs(tests) do
    if run_test_file(test.path, test.name) then
        passed = passed + 1
    else
        failed = failed + 1
    end
end

print("========================================")
print("SUMMARY: " .. passed .. " passed, " .. failed .. " failed")
print("========================================")

if failed > 0 then
    os.exit(1)
end