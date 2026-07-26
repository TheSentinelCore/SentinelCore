-- tests/harness/test_suite_runner.lua
-- The instrument, under test.
--
-- ================================================================================
-- WHY THE HARNESS NEEDS ITS OWN SUITE
-- ================================================================================
-- Every number this project has reported came out of `run_offline.lua`, and nothing anywhere
-- checked that the number meant what it said. Two defects, both of which understate failure:
--
--   1. A `run()` suite is ONE pcall. Its cases are neither counted individually nor reported
--      individually, and the first `error()` inside it conceals every case after it. Twelve suites
--      in this tree are a sorted loop that `error()`s on the first failure -- so a regression in
--      case 3 of 38 hides 35 results and moves the headline by exactly 1.
--   2. `run()` was PREFERRED over `test*`. A suite exporting both ran only `run()`, so
--      `tests/modules/combat/test_retribution_tbc` -- whose `run()` is a package.loaded reset and
--      not a driver at all -- executed its reset and NEITHER of its two tests, while reporting a
--      pass.
--
-- The logic is extracted into `tests/harness/suite_runner.lua` precisely so it can be driven from
-- here with synthetic suites, rather than being observable only by running the whole tree and
-- squinting at the total.
--
-- ================================================================================
-- WHAT THIS SUITE CANNOT SEE
-- ================================================================================
--  * WHETHER THE REGISTERED MODULE LIST IS COMPLETE. `run_offline.lua` names its suites in a hand
--    written table. A test file that exists on disk and is registered nowhere is invisible to the
--    runner and therefore to this file. Nothing derives that list from the filesystem.
--  * WHAT AN OPAQUE SUITE CONTAINS. It pins that opacity is REPORTED, not that it is absent. A
--    `run()` suite's real case count stays unknown until someone enumerates it.
--  * CROSS-SUITE INTERFERENCE. Cases share `_G`, `package.loaded` and the mocked `core`. The runner
--    orders cases deterministically so leakage is at least reproducible; it cannot detect it.

local Runner = require("tests/harness/suite_runner")
local T = require("tests/test_util")

local M = {}

--- A suite whose cases record the order they ran in.
local function recording_suite(spec)
    local order = {}
    local suite = { _order = order }
    for _, entry in ipairs(spec) do
        suite[entry.name] = function()
            order[#order + 1] = entry.name
            if entry.fails then error(entry.name .. " boom", 0) end
        end
    end
    return suite, order
end

-- ---------------------------------------------------------------------------
-- Individual counting
-- ---------------------------------------------------------------------------

function M.test_every_test_function_is_counted_as_its_own_case()
    local suite = recording_suite({
        { name = "test_a" }, { name = "test_b" }, { name = "test_c" },
    })
    local result = Runner.run_suite("synthetic", suite)

    T.assert_equal(#result.cases, 3, "three cases, counted individually -- not one suite")
    T.assert_nil(result.opaque, "nothing was opaque: every case was reachable by name")
end

--- The headline defect. A failing case must not remove its siblings from the report.
function M.test_a_failing_case_does_not_conceal_the_cases_after_it()
    local suite, order = recording_suite({
        { name = "test_a" }, { name = "test_b", fails = true }, { name = "test_c" },
    })
    local result = Runner.run_suite("synthetic", suite)

    T.assert_equal(#order, 3, "every case must run, including the ones after the failure")
    T.assert_equal(#result.cases, 3)
    local by_name = {}
    for _, c in ipairs(result.cases) do by_name[c.name] = c end
    T.assert_true(by_name.test_a.ok)
    T.assert_false(by_name.test_b.ok, "the failure is recorded")
    T.assert_true(by_name.test_c.ok, "and the case after it still ran and still passed")
end

function M.test_a_failure_is_reported_with_its_own_name_and_message()
    local suite = recording_suite({ { name = "test_only", fails = true } })
    local result = Runner.run_suite("synthetic", suite)

    local case = result.cases[1]
    T.assert_equal(case.name, "test_only")
    T.assert_true(tostring(case.err):find("test_only boom", 1, true) ~= nil,
        "the case's own error must survive to the report, not be summarised away")
end

--- Deterministic order is load-bearing, not cosmetic. Twelve suites sort their names precisely
--- because `pairs` order turned shared-fixture leakage into a failure that moved around and read
--- as flaky. Enumerating with raw `pairs` would hand that instability back.
function M.test_cases_run_in_sorted_order()
    local suite = recording_suite({
        { name = "test_c" }, { name = "test_a" }, { name = "test_b" },
    })
    local order = suite._order
    Runner.run_suite("synthetic", suite)
    T.assert_equal(table.concat(order, ","), "test_a,test_b,test_c")
end

--- A suite may keep its cases in an exported `tests` table instead of on the module itself.
function M.test_cases_in_an_exported_tests_table_are_enumerated_too()
    local ran = {}
    local suite = { tests = {
        test_x = function() ran[#ran + 1] = "x" end,
        test_y = function() ran[#ran + 1] = "y" end,
    } }
    local result = Runner.run_suite("synthetic", suite)

    T.assert_equal(#result.cases, 2, "an exported case table is an enumeration like any other")
    T.assert_equal(table.concat(ran, ","), "x,y")
end

--- The same function reachable both ways is ONE case, not two. `tests = { test_a = M.test_a }` is
--- the shape twelve suites in this tree use, and double-counting it would inflate the headline by
--- exactly the amount this deliverable exists to make honest.
function M.test_a_case_reachable_both_ways_is_counted_once()
    local n = 0
    local suite = {}
    suite.test_a = function() n = n + 1 end
    suite.tests = { test_a = suite.test_a }
    local result = Runner.run_suite("synthetic", suite)

    T.assert_equal(#result.cases, 1, "one function, one case")
    T.assert_equal(n, 1, "and it must be executed once, not twice")
end

-- ---------------------------------------------------------------------------
-- Opacity is reported, never collapsed to one
-- ---------------------------------------------------------------------------

--- A suite the runner cannot enumerate is still RUN -- but it is not counted as a case, because
--- its case count is unknown. Counting it as 1 is what made 38 assertions look like one test.
function M.test_a_run_only_suite_is_opaque_and_contributes_no_case_count()
    local called = false
    local suite = { run = function() called = true end }
    local result = Runner.run_suite("synthetic", suite)

    T.assert_true(called, "an opaque suite must still be executed")
    T.assert_equal(#result.cases, 0, "and must NOT be counted as one passing case")
    T.assert_not_nil(result.opaque, "its opacity must be recorded")
    T.assert_true(result.opaque.ok)
end

function M.test_an_opaque_suite_that_throws_is_recorded_as_a_failing_suite()
    local suite = { run = function() error("suite exploded", 0) end }
    local result = Runner.run_suite("synthetic", suite)

    T.assert_not_nil(result.opaque)
    T.assert_false(result.opaque.ok)
    T.assert_true(tostring(result.opaque.err):find("suite exploded", 1, true) ~= nil)
end

--- `run()` is NOT called when cases are enumerable, and the fact that it was skipped is reported.
--- Every `run()` in this tree that coexists with `test*` functions is either a driver over those
--- same functions -- in which case calling it would run each case twice -- or it is doing something
--- else, which a reader needs told rather than guessed.
function M.test_run_is_skipped_when_cases_are_enumerable_and_the_skip_is_reported()
    local ran_run = false
    local suite = { run = function() ran_run = true end }
    suite.test_a = function() end
    local result = Runner.run_suite("synthetic", suite)

    T.assert_false(ran_run, "run() must not re-execute cases the runner already enumerated")
    T.assert_equal(#result.cases, 1)
    T.assert_true(result.skipped_run, "and the skip must be visible in the report")
    T.assert_nil(result.opaque)
end

function M.test_a_suite_with_no_entry_point_is_an_error_not_a_pass()
    local result = Runner.run_suite("synthetic", { helper = function() end })
    T.assert_not_nil(result.error)
    T.assert_equal(#result.cases, 0)
end

-- ---------------------------------------------------------------------------
-- Running the whole list: nothing may abort the sweep
-- ---------------------------------------------------------------------------

local function fake_requirer(map)
    return function(name)
        local entry = map[name]
        if entry == nil then error("module '" .. name .. "' not found", 0) end
        if type(entry) == "function" then return entry() end
        return entry
    end
end

function M.test_a_failing_suite_does_not_stop_the_ones_after_it()
    local reached = {}
    local report = Runner.run_all({ "first", "second", "third" }, fake_requirer({
        first  = { test_a = function() reached.first = true end },
        second = { test_b = function() reached.second = true; error("boom", 0) end },
        third  = { test_c = function() reached.third = true end },
    }))

    T.assert_true(reached.first and reached.second and reached.third,
        "every registered suite must be reached, whatever the ones before it did")
    T.assert_equal(report.passed, 2)
    T.assert_equal(report.failed, 1)
end

function M.test_a_suite_that_fails_to_load_is_reported_and_the_sweep_continues()
    local reached = false
    local report = Runner.run_all({ "missing", "present" }, fake_requirer({
        present = { test_a = function() reached = true end },
    }))

    T.assert_true(reached, "a load error must not abort the sweep")
    T.assert_equal(report.load_errors, 1)
    T.assert_equal(report.passed, 1)
end

--- The counts a reader acts on. Opaque suites are tallied SEPARATELY so the headline never claims
--- to have counted what it did not.
function M.test_the_report_separates_counted_cases_from_opaque_suites()
    local report = Runner.run_all({ "counted", "opaque_ok", "opaque_bad" }, fake_requirer({
        counted    = { test_a = function() end, test_b = function() error("x", 0) end },
        opaque_ok  = { run = function() end },
        opaque_bad = { run = function() error("y", 0) end },
    }))

    T.assert_equal(report.passed, 1, "counted cases only")
    T.assert_equal(report.failed, 1)
    T.assert_equal(report.opaque_passed, 1)
    T.assert_equal(report.opaque_failed, 1)
    T.assert_equal(#report.opaque_suites, 2,
        "and the opaque suites must be NAMED, so 'case count unknown' points somewhere")
end

function M.test_the_report_lists_every_failure_not_just_the_first()
    local report = Runner.run_all({ "a", "b" }, fake_requirer({
        a = { test_1 = function() error("one", 0) end, test_2 = function() error("two", 0) end },
        b = { test_3 = function() error("three", 0) end },
    }))

    T.assert_equal(report.failed, 3)
    T.assert_equal(#report.failures, 3, "every failure is reported, not merely counted")
    local joined = table.concat(report.failures, "\n")
    for _, needle in ipairs({ "test_1", "test_2", "test_3" }) do
        T.assert_true(joined:find(needle, 1, true) ~= nil,
            needle .. " must appear in the failure list")
    end
end

--- FOUND BY USING THE INSTRUMENT, not by reading it. The first version of `format_report` printed
--- the failure list only `if report.failed > 0` -- and an opaque suite that throws increments
--- `opaque_failed`, never `failed`. So a `run()` suite could die, be counted in the summary line,
--- and have its error collected into `report.failures` and then never printed. The reader saw
--- "1 failed" with no name attached: the same species of defect as the two this file exists to
--- catch, reintroduced in the fix for them.
function M.test_an_opaque_failure_is_printed_and_not_merely_counted()
    local report = Runner.run_all({ "boom" }, fake_requirer({
        boom = { run = function() error("the opaque suite died", 0) end },
    }))
    T.assert_equal(report.failed, 0, "an opaque suite contributes no CASE failures")
    T.assert_equal(report.opaque_failed, 1)

    local text = Runner.format_report(report)
    T.assert_true(text:find("the opaque suite died", 1, true) ~= nil,
        "the error must reach the printed report, not just the counters")
    T.assert_true(text:find("boom", 1, true) ~= nil,
        "and it must name the suite it came from")
end

--- The summary a human reads has to be able to say "everything passed" only when it did.
function M.test_the_formatted_report_is_quiet_when_nothing_failed()
    local report = Runner.run_all({ "fine" }, fake_requirer({ fine = { test_a = function() end } }))
    local text = Runner.format_report(report)
    T.assert_true(text:find("1 passed, 0 failed", 1, true) ~= nil)
    T.assert_nil(text:find("Failures:", 1, true), "no failure block when there are no failures")
end

--- Suites run in the order they were registered. The list is ordered on purpose -- the end-to-end
--- suite is registered last because it replaces `_G.core` for its duration.
function M.test_suites_run_in_registration_order()
    local order = {}
    Runner.run_all({ "z", "a", "m" }, fake_requirer({
        z = { test_z = function() order[#order + 1] = "z" end },
        a = { test_a = function() order[#order + 1] = "a" end },
        m = { test_m = function() order[#order + 1] = "m" end },
    }))
    T.assert_equal(table.concat(order, ","), "z,a,m")
end

return M
