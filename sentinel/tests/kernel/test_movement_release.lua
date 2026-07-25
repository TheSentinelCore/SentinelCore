-- tests/kernel/test_movement_release.lua
-- ADR 08 §2.8 -- why this file exists at all:
--
--   "There is NO core.input.move(x,y,z) and NO click-to-move. Movement is stateful key
--    start/stop pairs. Consequence: if a MOVEMENT lease is revoked without the holder
--    releasing its keys, THE CHARACTER KEEPS RUNNING. on_revoke is not a courtesy callback;
--    it is the only thing standing between a preemption and the bot sprinting into a lake.
--    The broker must therefore treat MOVEMENT revocation as a KERNEL-ENFORCED KEY-RELEASE,
--    not as a request the plugin may ignore."
--
-- This is the ONLY module in Phase 2 permitted to touch `core.input.*`. Fencing it to one
-- file makes the boundary greppable: `rg "core\.input" sentinel/kernel` must return this
-- file and nothing else.
--
-- The hard requirement is that it CANNOT PARTIALLY FAIL. It runs on the revocation path,
-- possibly right after a plugin's on_revoke threw, so one dead SDK function must not stop
-- the other seven keys from being released.

local MovementRelease = require("kernel/movement_release")
local T = require("tests/test_util")

local M = {}

--- A recording stand-in for core.input.
local function make_input(opts)
    opts = opts or {}
    local calls = {}
    local input = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        input[key .. "_stop"] = function()
            calls[#calls + 1] = key
            if opts.throw_on == key then error("SDK exploded on " .. key, 0) end
            return true
        end
        -- Start functions exist so the double is shaped like the real thing; the releaser
        -- must never call one.
        input[key .. "_start"] = function() calls[#calls + 1] = key .. "_START" end
    end
    if opts.omit then
        for _, key in ipairs(opts.omit) do input[key .. "_stop"] = nil end
    end
    return input, calls
end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

--- The documented surface is EIGHT start/stop pairs
--- (docs/SylvannasAPI/dev/api/input.md:147-161). ADR 08 §2.8 names only three of them
--- ("move_forward", "turn_left", "strafe_*"); releasing only those would leave
--- move_backward, move_up and move_down held.
function M.test_covers_every_documented_movement_key()
    local expected = {
        "move_forward", "move_backward", "move_up", "move_down",
        "turn_left", "turn_right", "strafe_left", "strafe_right",
    }
    T.assert_equal(#MovementRelease.KEYS, #expected,
        "expected " .. #expected .. " movement keys, got " .. #MovementRelease.KEYS)
    for _, key in ipairs(expected) do
        T.assert_true(contains(MovementRelease.KEYS, key), key .. " must be released")
    end
end

function M.test_releases_all_keys()
    local input, calls = make_input()
    local report = MovementRelease.release_all(input)

    T.assert_equal(#calls, #MovementRelease.KEYS, "every key must be stopped")
    T.assert_equal(report.attempted, #MovementRelease.KEYS)
    T.assert_equal(report.released, #MovementRelease.KEYS)
    T.assert_equal(report.errors, 0)
    T.assert_equal(report.missing, 0)
end

--- It must never press anything. A releaser that starts a key is worse than useless.
function M.test_never_calls_a_start_function()
    local input, calls = make_input()
    MovementRelease.release_all(input)
    for _, call in ipairs(calls) do
        T.assert_false(call:find("_START") ~= nil, "release must never call a *_start function")
    end
end

--- THE critical property: a throwing SDK call must not abort the sweep.
function M.test_one_throwing_stop_does_not_prevent_the_others()
    local input, calls = make_input({ throw_on = "move_forward" })
    local ok, report = pcall(function() return MovementRelease.release_all(input) end)

    T.assert_true(ok, "release_all must never propagate a throw: " .. tostring(report))
    T.assert_equal(#calls, #MovementRelease.KEYS, "all eight keys must still be attempted")
    T.assert_equal(report.errors, 1)
    T.assert_equal(report.released, #MovementRelease.KEYS - 1)
end

function M.test_every_stop_throwing_is_survivable()
    local input = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        input[key .. "_stop"] = function() error("all dead", 0) end
    end
    local ok, report = pcall(function() return MovementRelease.release_all(input) end)
    T.assert_true(ok, "a fully broken input table must not throw")
    T.assert_equal(report.errors, #MovementRelease.KEYS)
    T.assert_equal(report.released, 0)
end

--- An older or partial injector build may not expose every pair. Missing is counted, not
--- fatal, and not confused with an error.
function M.test_missing_sdk_functions_are_counted_not_fatal()
    local input, calls = make_input({ omit = { "move_up", "move_down" } })
    local report = MovementRelease.release_all(input)

    T.assert_equal(report.missing, 2)
    T.assert_equal(report.released, #MovementRelease.KEYS - 2)
    T.assert_equal(report.errors, 0)
    T.assert_equal(#calls, #MovementRelease.KEYS - 2)
end

--- No input surface AT ALL. `core.input` must be nulled to create this state: passing nil
--- explicitly means "use the live SDK" (see test_defaults_to_the_live_core_input), so simply
--- calling release_all(nil) reaches whatever core.input happens to hold -- which made an
--- earlier version of this test pass or fail depending on which harness ran it.
function M.test_a_missing_input_surface_is_survivable()
    local saved = core.input
    core.input = nil

    local ok, report = pcall(function() return MovementRelease.release_all(nil) end)
    core.input = saved

    T.assert_true(ok, "no input surface at all must not throw")
    T.assert_equal(report.released, 0)
    T.assert_equal(report.missing, #MovementRelease.KEYS, "every key must be reported missing")
    T.assert_equal(report.errors, 0, "absent is not an error")
end

--- A partial `core.input` -- which is what the offline harness actually provides -- must
--- release what it can and report the rest missing rather than throwing on the gaps.
function M.test_a_partial_live_input_releases_what_exists()
    local saved = core.input
    core.input = { move_forward_stop = function() return true end }

    local ok, report = pcall(function() return MovementRelease.release_all() end)
    core.input = saved

    T.assert_true(ok)
    T.assert_equal(report.released, 1)
    T.assert_equal(report.missing, #MovementRelease.KEYS - 1)
    T.assert_equal(report.errors, 0)
end

--- ADR 08's requirement that stopping when not moving is a no-op, expressed as the property
--- that matters: calling twice is safe and does the same thing.
function M.test_release_is_idempotent()
    local input, calls = make_input()
    local first = MovementRelease.release_all(input)
    local second = MovementRelease.release_all(input)

    T.assert_equal(first.released, second.released, "a second release must behave identically")
    T.assert_equal(#calls, #MovementRelease.KEYS * 2)
end

-- ---------------------------------------------------------------------------
-- The desired-state reconciler (Phase 4b Deliverable 2)
-- ---------------------------------------------------------------------------
--
-- WHY THE RECONCILER LIVES IN THE SAME MODULE AS THE FORCE-RELEASE.
-- Movement is stateful key start/stop pairs, so whoever presses a key and whoever guarantees
-- it comes up must be the SAME owner. Two owners of that state is precisely how §2.8's
-- guarantee rots: the releaser stops the key, and a reconciler that still believes the
-- character should be running presses it again on the next tick. Keeping both here means
-- `release_all` clears the desire as a matter of course, and the broker's safety path needs
-- no new wiring it could forget.
--
-- WHY DESIRED STATE IS A KEY SET AND NOT A POINT.
-- "Move toward this point" cannot be honoured by MOVEMENT alone -- with key-based movement it
-- requires TURNING, and turning is the FACING channel, held under a different lease. A `move`
-- intent that quietly faced the character would be acting outside the lease that authorised
-- it, which is the whole failure the channel split exists to prevent. So `move` says which
-- keys it wants down, and a plugin that wants to run at something emits `face` too.

local function reconcile_harness(opts)
    local input, calls = make_input(opts)
    MovementRelease.release_all(input)   -- a known-stopped starting point
    for i = #calls, 1, -1 do calls[i] = nil end
    return input, calls
end

function M.test_no_desire_presses_nothing()
    local input, calls = reconcile_harness()
    local report = MovementRelease.reconcile(input)
    T.assert_equal(#calls, 0, "an empty desire must touch no key")
    T.assert_equal(#report.pressed, 0)
    T.assert_equal(#report.released, 0)
end

function M.test_a_desired_key_is_pressed_once_not_every_tick()
    local input, calls = reconcile_harness()
    MovementRelease.set_desired({ move_forward = true })

    local first = MovementRelease.reconcile(input)
    T.assert_equal(#first.pressed, 1, "the first reconcile must press")
    T.assert_equal(first.pressed[1], "move_forward")
    T.assert_equal(#calls, 1)
    T.assert_equal(calls[1], "move_forward_START")

    -- Key state is stateful: pressing an already-held key every tick is the SDK spam the
    -- imperative start/stop pair was causing in the first place.
    local second = MovementRelease.reconcile(input)
    T.assert_equal(#second.pressed, 0, "an already-held key must not be re-pressed")
    T.assert_equal(#calls, 1, "no further SDK traffic while the desire is unchanged")

    MovementRelease.release_all(input)
end

function M.test_clearing_the_desire_releases_the_key()
    local input, calls = reconcile_harness()
    MovementRelease.set_desired({ move_forward = true })
    MovementRelease.reconcile(input)
    for i = #calls, 1, -1 do calls[i] = nil end

    MovementRelease.set_desired(nil)
    local report = MovementRelease.reconcile(input)

    T.assert_equal(#report.released, 1, "dropping the desire must release the key")
    T.assert_equal(report.released[1], "move_forward")
    T.assert_equal(calls[1], "move_forward", "the stop half of the pair, not the start")
end

--- THE exit-criterion test for Phase 4b: revocation clears desired state, and the keys come up
--- as a CONSEQUENCE of the reconciler -- not because a plugin cooperated. The plugin in this
--- test never runs at all; it is not even represented.
function M.test_revocation_clears_the_desire_so_the_reconciler_cannot_re_press()
    local input, calls = reconcile_harness()
    MovementRelease.set_desired({ move_forward = true })
    MovementRelease.reconcile(input)

    -- The broker's force-release, exactly as ControlBroker:_revoke calls it.
    MovementRelease.release_all(input)
    T.assert_true(MovementRelease.desired() == nil,
        "release_all must clear the desire, or the next tick presses the key straight back down")

    for i = #calls, 1, -1 do calls[i] = nil end
    local report = MovementRelease.reconcile(input)
    T.assert_equal(#report.pressed, 0, "a revoked movement claim must not re-press on the next tick")
    T.assert_equal(#calls, 0)
end

--- The reconciler runs every tick on the hot path, so a partial injector build must degrade
--- rather than throw -- same rule the releaser follows.
function M.test_a_missing_start_function_is_counted_not_fatal()
    local input, calls = reconcile_harness()
    input.move_forward_start = nil
    MovementRelease.set_desired({ move_forward = true })

    local ok, report = pcall(function() return MovementRelease.reconcile(input) end)
    T.assert_true(ok, "a missing start function must not throw: " .. tostring(report))
    T.assert_equal(#report.pressed, 0)
    T.assert_equal(report.missing, 1)
    T.assert_equal(#calls, 0)

    MovementRelease.release_all(input)
end

function M.test_a_throwing_start_does_not_abort_the_other_keys()
    local input, calls = reconcile_harness()
    input.strafe_left_start = function() error("SDK exploded", 0) end
    MovementRelease.set_desired({ strafe_left = true, move_forward = true })

    local ok, report = pcall(function() return MovementRelease.reconcile(input) end)
    T.assert_true(ok, "a throwing start must not propagate: " .. tostring(report))
    T.assert_equal(report.errors, 1)
    T.assert_equal(#report.pressed, 1, "the surviving key must still be pressed")
    T.assert_equal(report.pressed[1], "move_forward")

    MovementRelease.release_all(input)
end

--- An unknown key is refused rather than passed through to a `<name>_start` that does not
--- exist. The desire is a closed vocabulary for the same reason the unit reference is.
function M.test_an_unknown_key_is_refused()
    local input = reconcile_harness()
    local ok, reason = MovementRelease.set_desired({ jump = true })
    T.assert_false(ok, "an undocumented movement key must be refused")
    T.assert_equal(reason, "unknown_movement_key")
    T.assert_true(MovementRelease.desired() == nil, "a refused desire must not be stored")
    MovementRelease.release_all(input)
end

--- With no argument it must reach the real SDK. This is the one call site, so if it silently
--- did nothing when handed no double, the safety net would be absent in-game and present in
--- every test.
function M.test_defaults_to_the_live_core_input()
    local saved = core.input
    local stopped = {}
    local fake = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        fake[key .. "_stop"] = function() stopped[#stopped + 1] = key; return true end
    end
    core.input = fake

    local ok, report = pcall(function() return MovementRelease.release_all() end)
    core.input = saved

    T.assert_true(ok, tostring(report))
    T.assert_equal(#stopped, #MovementRelease.KEYS,
        "with no argument the releaser must drive core.input")
end

return M
