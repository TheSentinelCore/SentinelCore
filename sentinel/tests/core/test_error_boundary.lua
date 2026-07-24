-- tests/core/test_error_boundary.lua
-- ADR 08 §5.1: "ErrorBoundary + Quarantine -- mandatory once third-party code runs. No
-- engine-level error isolation is documented -- every callback must self-pcall."
--
-- The boundary had no test file at all before Phase 1, despite being the thing that stands
-- between one bad plugin and a frozen client.
--
-- Two behaviours here are not obvious and are the reason this file exists:
--
--   1. MULTI-RETURN. `wrap` used to capture only pcall's FIRST result, silently truncating
--      any wrapped function that returned more than one value. A caller reading the second
--      return got nil and could not tell that from a real nil.
--   2. LOG DEDUPLICATION. A handler that throws every frame throws ~60 times a second. The
--      un-deduplicated boundary emitted 60 identical log lines per second, which is how a
--      real error becomes invisible. main.lua already hand-rolled this pattern per call
--      site (`_last_editor_render_error`); the boundary owns it now.

local ErrorBoundary = require("core/error_boundary")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

local function make_bus_recorder()
    local bus = EventBus:new(function() end)
    local seen = {}
    bus:subscribe("system:error", function(payload) seen[#seen + 1] = payload end)
    return bus, seen
end

--- A capturing stand-in for core.log_error, restored by every test that installs it.
local function with_captured_log(fn)
    local saved = core.log_error
    local lines = {}
    core.log_error = function(msg) lines[#lines + 1] = tostring(msg) end
    local ok, err = pcall(fn, lines)
    core.log_error = saved
    if not ok then error(err, 0) end
    return lines
end

function M.test_successful_call_reports_ok_and_result()
    local boundary = ErrorBoundary:new()
    local ok, value = boundary:wrap("mod", "op", function() return 42 end)
    T.assert_true(ok)
    T.assert_equal(value, 42)
end

--- Regression: pcall's tail was being dropped on the floor.
function M.test_all_return_values_survive_the_boundary()
    local boundary = ErrorBoundary:new()
    local ok, a, b, c = boundary:wrap("mod", "op", function() return 1, 2, 3 end)
    T.assert_true(ok)
    T.assert_equal(a, 1)
    T.assert_equal(b, 2)
    T.assert_equal(c, 3, "the boundary must not truncate multi-value returns")
end

function M.test_arguments_are_forwarded()
    local boundary = ErrorBoundary:new()
    local ok, sum = boundary:wrap("mod", "op", function(x, y) return x + y end, 3, 4)
    T.assert_true(ok)
    T.assert_equal(sum, 7)
end

--- The whole point: a throw stops at the boundary.
function M.test_error_does_not_propagate()
    local boundary = ErrorBoundary:new()
    local ok, err = boundary:wrap("mod", "op", function() error("boom") end)
    T.assert_false(ok, "a throwing function must report failure, not success")
    T.assert_true(tostring(err):find("boom", 1, true) ~= nil, "the reason must be preserved: " .. tostring(err))
end

function M.test_error_is_published_with_attribution()
    local bus, seen = make_bus_recorder()
    local boundary = ErrorBoundary:new(bus)
    boundary:wrap("questing", "tick", function() error("kaboom") end)

    T.assert_equal(#seen, 1, "one fault must publish exactly one system:error")
    T.assert_equal(seen[1].module, "questing")
    T.assert_equal(seen[1].operation, "tick")
    T.assert_true(tostring(seen[1].error):find("kaboom", 1, true) ~= nil)
end

--- A handler failing every frame must not emit one log line per frame.
function M.test_repeated_identical_errors_log_once()
    local boundary = ErrorBoundary:new()
    local lines = with_captured_log(function()
        for _ = 1, 50 do
            boundary:wrap("mod", "op", function() error("same failure", 0) end)
        end
    end)
    T.assert_equal(#lines, 1, "50 identical faults must produce 1 log line, got " .. #lines)
end

--- Deduplication must not hide a DIFFERENT failure arriving after a repeated one.
function M.test_a_changed_error_logs_again()
    local boundary = ErrorBoundary:new()
    local lines = with_captured_log(function()
        boundary:wrap("mod", "op", function() error("first", 0) end)
        boundary:wrap("mod", "op", function() error("first", 0) end)
        boundary:wrap("mod", "op", function() error("second", 0) end)
    end)
    T.assert_equal(#lines, 2, "a new failure must break the dedup streak")
end

--- ...and the same message from a DIFFERENT owner is a different fault.
function M.test_dedup_is_scoped_per_module_and_operation()
    local boundary = ErrorBoundary:new()
    local lines = with_captured_log(function()
        boundary:wrap("combat", "tick", function() error("shared", 0) end)
        boundary:wrap("questing", "tick", function() error("shared", 0) end)
    end)
    T.assert_equal(#lines, 2, "identical text from two owners is two distinct faults")
end

--- Suppressed repeats are still COUNTED -- silence must be measurable, not total.
function M.test_suppressed_repeats_are_counted()
    local boundary = ErrorBoundary:new()
    with_captured_log(function()
        for _ = 1, 10 do
            boundary:wrap("mod", "op", function() error("same", 0) end)
        end
    end)
    T.assert_equal(boundary:fault_count("mod", "op"), 10, "every fault counts even when the log is suppressed")
end

--- Publication is deduplicated alongside the log, or the bus becomes the new spam channel.
function M.test_publication_is_deduplicated_too()
    local bus, seen = make_bus_recorder()
    local boundary = ErrorBoundary:new(bus)
    with_captured_log(function()
        for _ = 1, 20 do
            boundary:wrap("mod", "op", function() error("same", 0) end)
        end
    end)
    T.assert_equal(#seen, 1, "20 identical faults must publish once, got " .. #seen)
    T.assert_equal(seen[1].count, 1, "the first publication reports the first occurrence")
end

--- Callback registration is the actual ADR requirement: "every callback must self-pcall".
function M.test_wrap_callback_returns_a_self_pcalling_function()
    local boundary = ErrorBoundary:new()
    local calls = 0
    local guarded = boundary:wrap_callback("ui", "on_render", function(x)
        calls = calls + 1
        if x == "bad" then error("render blew up", 0) end
        return "rendered:" .. tostring(x)
    end)

    local result = guarded("ok")
    T.assert_equal(result, "rendered:ok", "a wrapped callback must pass its return value through")

    local threw = not pcall(guarded, "bad")
    T.assert_false(threw, "a wrapped callback must swallow the throw, not re-raise it")
    T.assert_equal(calls, 2)
end

--- The boundary itself must never be the thing that breaks the tick: a broken event bus
--- cannot be allowed to turn a handled fault into an unhandled one.
function M.test_a_throwing_event_bus_cannot_break_the_boundary()
    local hostile_bus = { publish = function() error("bus is down", 0) end }
    local boundary = ErrorBoundary:new(hostile_bus)
    local ok = pcall(function()
        return boundary:wrap("mod", "op", function() error("inner", 0) end)
    end)
    T.assert_true(ok, "a throwing event bus must not escape the error boundary")
end

return M
