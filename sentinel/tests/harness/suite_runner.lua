-- tests/harness/suite_runner.lua
-- How a suite is discovered, executed and counted. Extracted from `run_offline.lua` so the
-- instrument itself can be tested (`tests/harness/test_suite_runner.lua`).
--
-- ================================================================================
-- WHAT THE HARNESS USED TO DO, AND WHY BOTH HALVES UNDERSTATED FAILURE
-- ================================================================================
-- It asked `type(suite.run) == "function"` FIRST, and fell through to `test*` functions only if
-- there was no `run`. Two consequences, both silent:
--
--   1. A `run()` SUITE WAS ONE PCALL. Twelve suites in this tree are a sorted loop that calls
--      `error(name .. " FAILED: " .. err)` on the first failure, so a regression in case 3 of 38
--      concealed the 35 after it and moved the headline by exactly 1. "One regression hides every
--      subsequent result" was not a property of the suites; it was a property of counting them as
--      one thing.
--   2. `run()` WON OVER `test*` EVEN WHEN BOTH EXISTED. Fifteen suites export both. In twelve of
--      them `run()` is a driver over the very same functions, so nothing was lost but the count.
--      In `tests/modules/combat/test_retribution_tbc` it is NOT a driver -- it is a
--      `package.loaded` reset -- so the harness ran the reset, ran NEITHER of the two tests, and
--      reported a pass. Those two cases had never executed.
--
-- ================================================================================
-- THE RULE NOW
-- ================================================================================
-- ENUMERATE FIRST, ALWAYS. A case is any function reachable by name: `suite.test*`, or an entry in
-- an exported `suite.tests` table. Each runs in its own pcall, in SORTED order, and counts as one.
--
-- `run()` is called ONLY when nothing is enumerable, and then it is reported as OPAQUE: executed,
-- but contributing NO case count, because its case count is genuinely unknown. Counting it as one
-- pass is the specific lie this file exists to stop telling.
--
-- When a suite has both, `run()` is SKIPPED and the skip is reported. Calling it as well would run
-- every case twice -- and for the drivers that means every fixture, every `_G` swap and every
-- `package.loaded` reset twice.
--
-- SORTED, not `pairs` order. Twelve suites sort their own case names deliberately: their headers
-- record that `pairs` order turned shared-fixture leakage into a failure that moved around and read
-- as flaky. Enumerating with raw `pairs` would hand that instability straight back.
--
-- ================================================================================
-- WHAT THIS RUNNER CANNOT SEE
-- ================================================================================
--  1. A TEST FILE NOBODY REGISTERED. The module list is hand-maintained in `run_offline.lua`.
--     Nothing derives it from the filesystem, so a suite that exists on disk and is named nowhere
--     is invisible -- it does not fail, it does not appear, and the total does not notice.
--  2. WHAT IS INSIDE AN OPAQUE SUITE. It reports that the count is unknown. It cannot make it
--     known. The only fix is to enumerate the suite, which is a change to that suite.
--  3. A CASE THAT ASSERTS NOTHING. An empty function passes. The runner counts EXECUTIONS that did
--     not throw; it has no idea whether anything was checked.
--  4. CROSS-SUITE INTERFERENCE. Cases share `_G`, `package.loaded` and the mocked `core` table.
--     Deterministic ordering makes leakage reproducible rather than intermittent; it does not
--     detect it, and a case that passes only because of what ran before it looks identical to one
--     that stands alone.
--  5. WHETHER `run()` WAS SAFE TO SKIP. When a suite exports both, this assumes `run()` is a driver
--     over the enumerated cases. If it also did setup, that setup no longer happens. The skip is
--     REPORTED for exactly that reason -- it is a decision a human has to check once per suite, not
--     something the runner can decide.
--  6. TIME. Nothing here measures how long a case took, so a suite that has become pathologically
--     slow is indistinguishable from one that has not.
--  7. ITSELF, EXCEPT WHERE `tests/harness/test_suite_runner.lua` LOOKS. Counting and REPORTING are
--     two surfaces here, and they can disagree: the first version of `format_report` gated the
--     failure list on `report.failed`, which an opaque suite's death never increments -- so a
--     `run()` suite could throw, be tallied, have its error collected, and never be named. It was
--     found by running the repaired harness on the real tree, not by reading it. Anything counted
--     in one place and printed from another can drift the same way.

local SuiteRunner = {}

---Every case in `suite`, by name, sorted.
---
---The union of `suite.test*` and `suite.tests`, DEDUPED BY NAME. `tests = { test_a = M.test_a }`
---is the shape twelve suites use, so counting both routes would inflate the headline by exactly
---the amount this file exists to make honest.
---@param suite table
---@return table cases -- array of { name, fn }, sorted by name
function SuiteRunner.discover(suite)
    local by_name = {}
    for key, value in pairs(suite) do
        if type(value) == "function" and type(key) == "string" and key:match("^test") then
            by_name[key] = value
        end
    end
    if type(suite.tests) == "table" then
        for key, value in pairs(suite.tests) do
            if type(value) == "function" and type(key) == "string" then
                by_name[key] = by_name[key] or value
            end
        end
    end

    local names = {}
    for name in pairs(by_name) do names[#names + 1] = name end
    table.sort(names)

    local cases = {}
    for i, name in ipairs(names) do cases[i] = { name = name, fn = by_name[name] } end
    return cases
end

---Run one already-loaded suite.
---@param module_name string
---@param suite table
---@return table result { module, cases[], opaque?, skipped_run?, error? }
function SuiteRunner.run_suite(module_name, suite)
    local result = { module = module_name, cases = {} }
    if type(suite) ~= "table" then
        result.error = "suite did not return a table"
        return result
    end

    local cases = SuiteRunner.discover(suite)
    local has_run = type(suite.run) == "function"

    if #cases > 0 then
        for _, case in ipairs(cases) do
            -- One pcall PER CASE. This is the whole fix for "a failure hides its siblings": the
            -- loop cannot be exited by a case, only by the case list running out.
            local ok, err = pcall(case.fn)
            result.cases[#result.cases + 1] = { name = case.name, ok = ok, err = (not ok) and err or nil }
        end
        result.skipped_run = has_run or nil
        return result
    end

    if has_run then
        local ok, err = pcall(suite.run)
        result.opaque = { ok = ok, err = (not ok) and err or nil }
        return result
    end

    result.error = "no run() and no test* functions"
    return result
end

---Run every registered suite. NOTHING here may abort the sweep.
---@param module_names table array of module paths, in the order they must run
---@param requirer function|nil defaults to the real `require`
---@return table report
function SuiteRunner.run_all(module_names, requirer)
    requirer = requirer or require

    local report = {
        passed = 0, failed = 0,
        opaque_passed = 0, opaque_failed = 0,
        load_errors = 0,
        opaque_suites = {},
        hybrid_suites = {},
        failures = {},
        suites = {},
    }

    for _, module_name in ipairs(module_names) do
        -- The require is pcalled separately from the run so a syntax error in one suite is
        -- reported as a LOAD failure rather than as a mysteriously absent set of cases.
        local loaded, suite = pcall(requirer, module_name)
        if not loaded then
            report.load_errors = report.load_errors + 1
            report.failed = report.failed + 1
            report.failures[#report.failures + 1] =
                string.format("LOAD ERROR %s: %s", module_name, tostring(suite))
            io.write("E")
        else
            local result = SuiteRunner.run_suite(module_name, suite)
            report.suites[#report.suites + 1] = result

            for _, case in ipairs(result.cases) do
                if case.ok then
                    report.passed = report.passed + 1
                    io.write(".")
                else
                    report.failed = report.failed + 1
                    report.failures[#report.failures + 1] =
                        string.format("FAIL %s.%s: %s", module_name, case.name, tostring(case.err))
                    io.write("F")
                end
            end

            if result.skipped_run then
                report.hybrid_suites[#report.hybrid_suites + 1] = module_name
            end

            if result.opaque then
                report.opaque_suites[#report.opaque_suites + 1] = module_name
                if result.opaque.ok then
                    report.opaque_passed = report.opaque_passed + 1
                    io.write("o")
                else
                    report.opaque_failed = report.opaque_failed + 1
                    report.failures[#report.failures + 1] =
                        string.format("FAIL %s.run (OPAQUE -- cases after this one did not run): %s",
                            module_name, tostring(result.opaque.err))
                    io.write("O")
                end
            end

            if result.error then
                report.failed = report.failed + 1
                report.failures[#report.failures + 1] =
                    string.format("ERROR %s: %s", module_name, result.error)
                io.write("E")
            end
        end
    end

    return report
end

---The human-facing summary. Returns the text; the caller decides where it goes.
---@param report table
---@return string
function SuiteRunner.format_report(report)
    local out = {}
    out[#out + 1] = string.format("\n\n%d passed, %d failed   (individually counted cases)",
        report.passed, report.failed)

    local opaque_total = report.opaque_passed + report.opaque_failed
    if opaque_total > 0 then
        out[#out + 1] = string.format(
            "%d suite(s) ran OPAQUE through run(): %d ok, %d failed -- their case counts are UNKNOWN "
            .. "and are NOT in the figures above.",
            opaque_total, report.opaque_passed, report.opaque_failed)
        table.sort(report.opaque_suites)
        for _, name in ipairs(report.opaque_suites) do
            out[#out + 1] = "    opaque: " .. name
        end
    end

    if #report.hybrid_suites > 0 then
        out[#out + 1] = string.format(
            "%d suite(s) export BOTH enumerable cases and run(); run() was skipped as a driver. "
            .. "If one of them also did setup, that setup no longer happens -- see suite_runner's "
            .. "header, item 5.", #report.hybrid_suites)
    end

    -- KEYED ON THE LIST, NOT ON `report.failed`. An opaque suite that throws increments
    -- `opaque_failed` and never `failed`, so gating this on the case counter printed "1 failed"
    -- with no name attached -- a failure counted and then thrown away, which is the exact defect
    -- this file was written to remove.
    if #report.failures > 0 then
        out[#out + 1] = "\nFailures:"
        for _, failure in ipairs(report.failures) do
            out[#out + 1] = "  " .. failure
        end
    end

    return table.concat(out, "\n")
end

return SuiteRunner
