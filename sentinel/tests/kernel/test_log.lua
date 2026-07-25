-- tests/kernel/test_log.lua
-- `Sentinel.log` (ADR 08 §10: ":debug, :info, :warn, :error (auto-attributed)").
--
-- The interesting property is not "does a line come out". It is that the AUTHOR'S NAME on the
-- line is derived from the call site rather than typed by the caller -- because a typed name is
-- a field that goes stale on the first copy-paste and is never noticed, since a wrong name in a
-- log line looks exactly like a right one.
--
-- The other half is degradation. `debug` is not documented in the Sylvannas surface and this
-- repo has already been bitten by assuming a standard library is there (no `io`, no `load`, no
-- JSON). So the absence of `debug` must cost the ATTRIBUTION, never the log line.

local Log = require("kernel/log")
local T = require("tests/test_util")

local M = {}

local function sink_double()
    local lines = {}
    return function(line) lines[#lines + 1] = line end, lines
end

--- A `debug.getinfo` stand-in that reports a chosen source path.
local function getinfo_for(source)
    return function(_level, _what) return { source = source } end
end

-- ---------------------------------------------------------------------------
-- Attribution
-- ---------------------------------------------------------------------------

function M.test_a_rotation_is_attributed_to_its_package()
    T.assert_equal(Log.attribute("@sentinel/rotations/mage_frost/frost_tbc.lua"),
        "rotations.mage_frost")
end

function M.test_a_module_is_attributed_to_its_package()
    T.assert_equal(Log.attribute("@sentinel/modules/combat/module.lua"), "modules.combat")
end

function M.test_kernel_and_runtime_are_attributed_without_a_sub_package()
    T.assert_equal(Log.attribute("@sentinel/kernel/scheduler.lua"), "kernel")
    T.assert_equal(Log.attribute("@sentinel/runtime/app.lua"), "runtime")
end

--- An unrecognised path is named as unknown rather than guessed at. A plausible-looking wrong
--- attribution is worse than an admitted one, because it sends the next reader to the wrong
--- file.
function M.test_an_unrecognised_path_is_named_unattributed()
    T.assert_equal(Log.attribute("@/tmp/scratch.lua"), Log.UNATTRIBUTED)
    T.assert_equal(Log.attribute(nil), Log.UNATTRIBUTED)
    T.assert_equal(Log.attribute(42), Log.UNATTRIBUTED)
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

function M.test_every_documented_level_exists_and_writes()
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink, getinfo = getinfo_for("@sentinel/rotations/mage_frost/x.lua") })

    for _, level in ipairs(Log.LEVELS) do
        T.assert_true(type(log[level]) == "function", level .. " must be a method")
        log[level](log, "hello")
    end

    T.assert_equal(#lines, #Log.LEVELS)
    T.assert_equal(#Log.LEVELS, 4, "§10 names exactly four levels")
end

function M.test_the_line_carries_the_attributed_owner_and_level()
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink, getinfo = getinfo_for("@sentinel/rotations/mage_frost/x.lua") })
    log:warn("frostbolt refused")

    T.assert_equal(lines[1], "[rotations.mage_frost][warn] frostbolt refused")
end

--- Auto means auto. There is no parameter through which a plugin can claim to be another one.
function M.test_a_caller_cannot_override_its_own_attribution()
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink, getinfo = getinfo_for("@sentinel/modules/combat/module.lua") })
    log:info("I am definitely the questing module")

    T.assert_true(lines[1]:find("%[modules%.combat%]") ~= nil,
        "attribution comes from the call site, not the message: " .. lines[1])
end

function M.test_a_non_string_message_is_coerced_rather_than_thrown_on()
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink, getinfo = getinfo_for("@sentinel/kernel/x.lua") })
    local ok = log:info(nil)
    T.assert_true(ok, "a nil message must still produce a line")
    T.assert_true(lines[1]:find("nil") ~= nil, lines[1])
end

-- ---------------------------------------------------------------------------
-- Degradation
-- ---------------------------------------------------------------------------

--- The sandbox question this file is honest about: no `debug` costs the NAME, not the line.
function M.test_an_absent_debug_library_costs_attribution_not_the_log_line()
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink, getinfo = false })

    local ok = log:error("something broke")
    T.assert_true(ok, "the line must still be written without `debug`")
    T.assert_equal(lines[1], "[" .. Log.UNATTRIBUTED .. "][error] something broke")
end

--- A throwing `getinfo` is the same class of problem as an absent one.
function M.test_a_throwing_getinfo_degrades_rather_than_propagating()
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink, getinfo = function() error("no debug here", 0) end })

    local ok = log:info("still fine")
    T.assert_true(ok)
    T.assert_true(lines[1]:find(Log.UNATTRIBUTED, 1, true) ~= nil, lines[1])
end

--- A diagnostic that can crash the tick is a liability: this runs inside plugin code, so a
--- throw here would be attributed by the ErrorBoundary to the plugin the logger just failed.
function M.test_a_throwing_sink_is_reported_not_propagated()
    local log = Log.new({
        sink = function() error("log pipe closed", 0) end,
        getinfo = getinfo_for("@sentinel/kernel/x.lua"),
    })

    local ok, written, reason = pcall(function() return log:info("boom") end)
    T.assert_true(ok, "a throwing sink must never reach the caller")
    T.assert_false(written)
    T.assert_equal(reason, "sink_error")
end

function M.test_no_sink_at_all_is_reported_by_name()
    local saved = core.log
    core.log = nil
    local log = Log.new({ getinfo = getinfo_for("@sentinel/kernel/x.lua") })
    local written, reason = log:info("nowhere to go")
    core.log = saved

    T.assert_false(written)
    T.assert_equal(reason, "no_sink")
end

--- With no injected sink it must reach the real `core.log`. If it silently did nothing when
--- handed no double, logging would be absent in-game and present in every test.
function M.test_it_defaults_to_the_live_core_log()
    local saved = core.log
    local seen = {}
    core.log = function(line) seen[#seen + 1] = line end

    local log = Log.new({ getinfo = getinfo_for("@sentinel/rotations/mage_frost/x.lua") })
    local ok = log:debug("live")
    core.log = saved

    T.assert_true(ok)
    T.assert_equal(#seen, 1, "with no injected sink the logger must drive core.log")
end

-- ---------------------------------------------------------------------------
-- Real attribution, end to end
-- ---------------------------------------------------------------------------

--- The stack-depth constant is the part most likely to rot: it depends on how many frames sit
--- between the plugin's call and `debug.getinfo`. Pin it against the REAL `debug` library, so a
--- refactor that adds or removes a frame fails here rather than mislabelling every line.
function M.test_the_real_debug_library_attributes_this_test_file()
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
        return  -- nothing to pin under a sandbox without `debug`
    end
    local sink, lines = sink_double()
    local log = Log.new({ sink = sink })
    log:info("from the test file")

    -- This file lives under sentinel/tests/, which matches no ATTRIBUTION rule -- so the
    -- correct answer is "unattributed", and getting a package name here would mean the frame
    -- depth is pointing somewhere it should not.
    T.assert_true(lines[1]:find(Log.UNATTRIBUTED, 1, true) ~= nil,
        "a caller outside every known package must be unattributed, got: " .. lines[1])
end

return M
