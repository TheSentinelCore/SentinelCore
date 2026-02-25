local T = require("tests/TestUtil")

local function run()
    T.install_core_stub()

    local Logger = require("core/Logger")
    local LEVELS = Logger.get_levels()

    -- Reset global state between test runs
    Logger.set_global_level("INFO")
    Logger.clear_history()
    Logger.set_max_history(200)

    -- Test 1: Creation and defaults
    local log = Logger:new("TestModule")
    T.assert_eq(log._name, "TestModule", "logger name mismatch")
    T.assert_eq(log._level, LEVELS.INFO, "default level should be INFO")

    -- Test 2: Creation with string level
    local log_debug = Logger:new("Debug", "DEBUG")
    T.assert_eq(log_debug._level, LEVELS.DEBUG, "string level parse failed")

    -- Test 3: Creation with numeric level
    local log_warn = Logger:new("Warn", LEVELS.WARNING)
    T.assert_eq(log_warn._level, LEVELS.WARNING, "numeric level parse failed")

    -- Test 4: Instance set_level
    log:set_level("ERROR")
    T.assert_eq(log._level, LEVELS.ERROR, "set_level string failed")
    log:set_level(LEVELS.DEBUG)
    T.assert_eq(log._level, LEVELS.DEBUG, "set_level numeric failed")

    -- Test 5: Global level
    Logger.set_global_level("DEBUG")
    T.assert_eq(Logger.get_global_level(), LEVELS.DEBUG, "set_global_level failed")
    Logger.set_global_level("INFO")
    T.assert_eq(Logger.get_global_level(), LEVELS.INFO, "global level reset failed")

    -- Test 6: Level filtering - instance level
    Logger.clear_history()
    Logger.set_global_level("DEBUG")
    local filtered_log = Logger:new("Filtered", "WARNING")
    filtered_log:debug("should be filtered")
    filtered_log:info("should be filtered too")
    filtered_log:warn("should appear")
    local hist = Logger.get_history()
    T.assert_eq(#hist, 1, "instance level filtering: expected 1 entry, got " .. #hist)
    T.assert_eq(hist[1].level, "WARN", "expected WARN level entry")

    -- Test 7: Level filtering - global level
    Logger.clear_history()
    Logger.set_global_level("ERROR")
    local all_log = Logger:new("All", "DEBUG")
    all_log:debug("filtered by global")
    all_log:info("filtered by global")
    all_log:warn("filtered by global")
    all_log:error("should appear")
    hist = Logger.get_history()
    T.assert_eq(#hist, 1, "global level filtering: expected 1 entry, got " .. #hist)
    T.assert_eq(hist[1].level, "ERROR", "expected ERROR level entry")

    -- Test 8: Varargs formatting
    Logger.clear_history()
    Logger.set_global_level("DEBUG")
    local fmt_log = Logger:new("Fmt", "DEBUG")
    fmt_log:info("value=%d name=%s", 42, "test")
    hist = Logger.get_history()
    T.assert_eq(#hist, 1, "format test: expected 1 entry")
    T.assert_true(hist[1].message:find("value=42") ~= nil, "format substitution failed")
    T.assert_true(hist[1].message:find("name=test") ~= nil, "format substitution failed (2)")

    -- Test 9: pcall protection for bad format strings
    Logger.clear_history()
    local bad_log = Logger:new("Bad", "DEBUG")
    bad_log:info("missing arg %d %s")
    hist = Logger.get_history()
    T.assert_eq(#hist, 1, "pcall protection: expected 1 entry")
    T.assert_true(hist[1].message:find("FORMAT ERROR") ~= nil, "pcall protection: expected FORMAT ERROR tag")

    -- Test 10: History buffer limits
    Logger.clear_history()
    Logger.set_max_history(5)
    local buf_log = Logger:new("Buf", "DEBUG")
    for i = 1, 10 do
        buf_log:info("msg %d", i)
    end
    hist = Logger.get_history()
    T.assert_eq(#hist, 5, "history buffer limit: expected 5, got " .. #hist)
    T.assert_true(hist[1].message:find("msg 6") ~= nil, "oldest entry should be msg 6")
    Logger.set_max_history(200)

    -- Test 11: get_history limit parameter
    Logger.clear_history()
    local limit_log = Logger:new("Limit", "DEBUG")
    for i = 1, 10 do
        limit_log:info("entry %d", i)
    end
    local limited = Logger.get_history(3)
    T.assert_eq(#limited, 3, "get_history(3) should return 3 entries")
    T.assert_true(limited[1].message:find("entry 8") ~= nil, "get_history(3) should return last 3")

    -- Test 12: push_history class method (used by ConsoleLogger)
    Logger.clear_history()
    Logger.push_history(LEVELS.INFO, "event message", "event.test")
    hist = Logger.get_history()
    T.assert_eq(#hist, 1, "push_history: expected 1 entry")
    T.assert_eq(hist[1].source, "event.test", "push_history source mismatch")
    T.assert_eq(hist[1].message, "event message", "push_history message mismatch")
    T.assert_eq(hist[1].level, "INFO", "push_history level mismatch")

    -- Test 13: Table serialization
    Logger.clear_history()
    local tbl_log = Logger:new("Tbl", "DEBUG")
    tbl_log:table("test data", { x = 1, y = "hello" })
    hist = Logger.get_history()
    T.assert_eq(#hist, 1, "table log: expected 1 entry")
    T.assert_true(hist[1].message:find("test data") ~= nil, "table log: missing description")
    T.assert_true(hist[1].message:find("x=1") ~= nil, "table log: missing key x")

    -- Test 14: Missing core handling (history still works)
    local saved_core = _G.core
    _G.core = nil
    Logger.clear_history()
    local no_core_log = Logger:new("NoCore", "DEBUG")
    no_core_log:info("no core test")
    hist = Logger.get_history()
    T.assert_eq(#hist, 1, "missing core: history should still work")
    T.assert_eq(hist[1].message, "no core test", "missing core: message mismatch")
    _G.core = saved_core

    -- Test 15: Noop fallback pattern
    local noop = { debug=function()end, info=function()end, warn=function()end, error=function()end }
    local noop_ok = pcall(function()
        noop:debug("test %d", 1)
        noop:info("test")
        noop:warn("test")
        noop:error("test")
    end)
    T.assert_true(noop_ok, "noop fallback pattern should not error")

    -- Test 16: Format output
    Logger.set_global_level("DEBUG")
    local fmt_out_log = Logger:new("FmtTest", "DEBUG")
    local formatted = fmt_out_log:_format(LEVELS.INFO, "hello world")
    T.assert_true(formatted:find("%[INFO%]") ~= nil, "format output: missing level")
    T.assert_true(formatted:find("%[FmtTest%]") ~= nil, "format output: missing name")
    T.assert_true(formatted:find("hello world") ~= nil, "format output: missing message")

    -- Test 17: Level names
    T.assert_eq(LEVELS.DEBUG, 1, "DEBUG level value")
    T.assert_eq(LEVELS.INFO, 2, "INFO level value")
    T.assert_eq(LEVELS.WARNING, 3, "WARNING level value")
    T.assert_eq(LEVELS.ERROR, 4, "ERROR level value")
    T.assert_eq(LEVELS.NONE, 5, "NONE level value")

    -- Cleanup
    Logger.set_global_level("INFO")
    Logger.clear_history()
    Logger.set_max_history(200)

    return {
        sc025_logger = true,
    }
end

return { run = run }
