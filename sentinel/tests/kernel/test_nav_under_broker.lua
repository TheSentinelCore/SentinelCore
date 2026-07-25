-- tests/kernel/test_nav_under_broker.lua
-- ADR 08 §2.8 -- the half of the guarantee the key sweep cannot reach.
--
-- ================================================================================
-- WHY THIS FILE EXISTS: test_movement_release.lua LOOKS AT THE WRONG THING
-- ================================================================================
-- `tests/kernel/test_movement_release.lua` proves the eight keys come up on revocation. It
-- proves it against an INPUT DOUBLE, which is exactly the shape of its blind spot: it can only
-- ever observe keys the kernel itself pressed. There were four authorities over movement, and
-- only one of them went through `core.input` from inside the kernel:
--
--   | authority                                          | visible to an input double? |
--   | SDK simple_movement via NavClient MovementService   | no                          |
--   | NavClient Jump.lua / MoveBackward.lua (core.input)  | no -- separate plugin        |
--   | NavAdapter's private owner/preemption mechanism     | no -- a second arbiter       |
--   | kernel `move` intent + movement_release reconciler  | YES                          |
--
-- So the broker revoked MOVEMENT, `release_all` stopped eight keys, the input double saw all
-- eight, the test went green -- and the nav client pressed them straight back down on its next
-- `process()`. §2.8's guarantee ("the character keeps running" is prevented) was FALSE and no
-- test could see it, because the only witness was blind to the authority doing the running.
--
-- This file supplies the missing witness: a NAV DOUBLE. Every test here asks a question the
-- input double structurally cannot answer.
--
-- ================================================================================
-- THE TRAP THIS FILE PINS: `NavAdapter:stop` IS OWNER-SCOPED
-- ================================================================================
-- The obvious fix -- "have `release_all` call the nav adapter's stop" -- is a SILENT NO-OP.
-- `NavAdapter:stop(reason, owner)` returns false without touching the real client when the
-- adapter is owned by someone else, and the broker revoking a lease is never that owner. The
-- fix would look right, the suite would stay green, and in game the character would keep
-- running. `test_the_owner_scoped_adapter_stop_is_not_the_kernel_path` is the test that
-- refuses that fix.

local ControlBroker = require("kernel/control_broker")
local MovementRelease = require("kernel/movement_release")
local NavAdapter = require("integrations/nav_client/adapter")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Doubles
-- ---------------------------------------------------------------------------

--- A recording stand-in for core.input, same shape as test_movement_release's.
local function make_input()
    local calls = {}
    local input = {}
    for _, key in ipairs(MovementRelease.KEYS) do
        input[key .. "_stop"] = function() calls[#calls + 1] = key; return true end
        input[key .. "_start"] = function() calls[#calls + 1] = key .. "_START" end
    end
    return input, calls
end

--- THE MISSING WITNESS. A stand-in for `_G.SentinelNavClient.client`.
---
--- `movement` is present and counted deliberately: ADR-adjacent docs
--- (docs/SylvannasAPI/dev/api/sentinel-navigation.md:597) flag `client.movement` as a
--- "Use With Care" lower-level service "more likely to change" than the high-level client,
--- and `MovementService:stop()` only stops the waypoint follow -- it does not reset the
--- navigation state, so the client's HSM would resume. Counting it lets a test assert which
--- of the two the kernel chose.
local function make_nav_client(opts)
    opts = opts or {}
    local calls = { stop = 0, movement_stop = 0, move_to = 0, reasons = {} }
    local client = {
        move_to = function(_self) calls.move_to = calls.move_to + 1 end,
        follow_path = function() end,
        start_route = function() end,
        stop = function()
            calls.stop = calls.stop + 1
            if opts.throw_on_stop then error("nav client exploded", 0) end
        end,
        get_state = function() return opts.state or "idle" end,
        get_full_state = function() return opts.full_state or "idle" end,
        get_progress = function() return {} end,
        movement = {
            stop = function() calls.movement_stop = calls.movement_stop + 1 end,
        },
    }
    if opts.omit_stop then client.stop = nil end
    return client, calls
end

--- Run `fn` with a known `_G.SentinelNavClient` and a known `_G.Sentinel`, restoring both.
---
--- BOTH are restored because these two globals are how the kernel resolves the nav client and
--- the broker respectively, and other suites in the offline runner set them. A test that read
--- whatever the previous suite happened to leave behind would be measuring test order.
local function with_globals(nav_client, sentinel_api, fn)
    local saved_nav = rawget(_G, "SentinelNavClient")
    local saved_api = rawget(_G, "Sentinel")
    _G.SentinelNavClient = nav_client and { client = nav_client } or nil
    _G.Sentinel = sentinel_api
    local ok, err = pcall(fn)
    _G.SentinelNavClient = saved_nav
    _G.Sentinel = saved_api
    if not ok then error(err, 0) end
end

--- The smallest thing that answers `.control` like the real `_G.Sentinel` does (kernel/api.lua
--- resolves `control` through `__index` at access time).
local function fake_api(broker)
    return setmetatable({}, { __index = function(_, key)
        if key == "control" then return broker end
        return nil
    end })
end

-- ---------------------------------------------------------------------------
-- THE PIN
-- ---------------------------------------------------------------------------

--- ADR 08 §2.8, stated against the authority that actually moves the character.
---
--- The broker revokes MOVEMENT. Eight keys come up -- and the nav client, which is driving the
--- character through the SDK's own `simple_movement`, is never told. On the next `process()` it
--- presses them again. "Mostly stopped" is indistinguishable from "not stopped" once the
--- character is in a lake.
function M.test_revoking_movement_stops_navigation_not_only_the_keys()
    local nav, nav_calls = make_nav_client()
    local input, key_calls = make_input()

    with_globals(nav, nil, function()
        local broker = ControlBroker:new({ input = input })
        broker:begin_tick(1)
        local caretaker = broker:acquire({
            channel = "MOVEMENT", owner = "questing", band = "GOAL", ttl_ticks = 1,
        })
        T.assert_not_nil(caretaker, "the fixture must actually hold MOVEMENT")

        -- TTL expiry -> _revoke -> the §2.8 force-release.
        broker:arbitrate(2)

        T.assert_equal(#key_calls, #MovementRelease.KEYS,
            "the eight keys must still come up -- this half already worked")
        T.assert_equal(nav_calls.stop, 1,
            "revoking MOVEMENT must STOP NAVIGATION, not just release the keys the kernel "
            .. "itself pressed -- the nav client re-presses them on its next process()")
    end)
end

--- The same guarantee on the voluntary path. `ControlBroker:release` force-releases the keys
--- precisely because "the kernel cannot verify that a releasing holder actually let go" --
--- which is at least as true of a navigation the holder forgot to cancel.
function M.test_voluntarily_releasing_movement_also_stops_navigation()
    local nav, nav_calls = make_nav_client()
    local input = make_input()

    with_globals(nav, nil, function()
        local broker = ControlBroker:new({ input = input })
        broker:begin_tick(1)
        local caretaker = broker:acquire({
            channel = "MOVEMENT", owner = "questing", band = "GOAL", ttl_ticks = 4,
        })
        T.assert_true(broker:release(caretaker))
        T.assert_equal(nav_calls.stop, 1,
            "handing MOVEMENT back must stop navigation for the same reason it lifts the keys")
    end)
end

--- MOVEMENT changing hands mid-flight is the case §6.4 describes ("delegates CASTING+TARGETING,
--- keeps MOVEMENT"): the broker already lifts the keys so the incoming holder starts from a
--- known state. A navigation left running across that handover is the same ambiguity wearing a
--- different hat -- the new holder would be steering a path it never asked for.
function M.test_delegating_movement_stops_navigation()
    local nav, nav_calls = make_nav_client()
    local input = make_input()

    with_globals(nav, nil, function()
        local broker = ControlBroker:new({ input = input })
        broker:begin_tick(1)
        broker:acquire({ channel = "MOVEMENT", owner = "grind", band = "GOAL", ttl_ticks = 4 })
        local delegated = broker:delegate("MOVEMENT", "grind", "combat_service")
        T.assert_not_nil(delegated)
        T.assert_equal(nav_calls.stop, 1,
            "MOVEMENT changes hands with navigation stopped, not merely with the keys up")
    end)
end

-- ---------------------------------------------------------------------------
-- THE TRAP
-- ---------------------------------------------------------------------------

--- The fix that looks right and does nothing.
---
--- `NavAdapter:stop(reason, owner)` refuses when `self._owner ~= owner`. A revocation arrives
--- from the broker, which is not the adapter's owner, so routing the kernel's nav stop through
--- the adapter would return false and never reach the real client. This test holds the adapter
--- under a foreign owner and demands that the kernel's stop lands anyway.
function M.test_the_owner_scoped_adapter_stop_is_not_the_kernel_path()
    local nav, nav_calls = make_nav_client()
    local input = make_input()

    with_globals(nav, nil, function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 1, y = 2, z = 3 }, { owner = "combat" }))
        T.assert_equal(adapter:get_owner(), "combat")

        -- Establish the trap is real, rather than assuming it.
        local stopped = adapter:stop("kernel_revocation")   -- no owner arg: not "combat"
        T.assert_true(stopped == false,
            "the adapter's stop IS owner-scoped -- if this ever passes, re-read the fix below")
        T.assert_equal(nav_calls.stop, 0,
            "an owner-scoped refusal never reaches the real client -- that is the silent no-op")

        -- The kernel must therefore bypass the adapter entirely.
        MovementRelease.release_all(input)
        T.assert_equal(nav_calls.stop, 1,
            "release_all must drive the REAL client's stop, not the owner-scoped adapter")
    end)
end

--- Which stop the kernel chose, pinned.
---
--- `client:stop()` "stops all movement and resets the active navigation state"
--- (sentinel-navigation.md:264). `client.movement:stop()` sits under "Advanced APIs -- Use With
--- Care: more likely to change" (:597) and only stops the waypoint follow, leaving the client's
--- state machine live to resume. Calling the lower one would leave §2.8 depending on an API the
--- docs explicitly decline to stabilise.
function M.test_the_kernel_calls_the_high_level_client_stop()
    local nav, nav_calls = make_nav_client()
    local input = make_input()

    with_globals(nav, nil, function()
        MovementRelease.release_all(input)
        T.assert_equal(nav_calls.stop, 1, "the high-level client:stop() is the documented verb")
        T.assert_equal(nav_calls.movement_stop, 0,
            "MovementService:stop() only stops the follow, and the docs flag it as unstable")
    end)
end

-- ---------------------------------------------------------------------------
-- FAULT TOLERANCE -- the nav stop inherits the key sweep's promise
-- ---------------------------------------------------------------------------

--- `release_all` "never throws and never partially aborts". Adding a nav stop in front of the
--- key sweep puts third-party code on the safety path ahead of the eight keys, so the throwing
--- case is the one that matters: a nav client that explodes must cost nothing.
function M.test_a_throwing_nav_stop_does_not_cost_the_eight_keys_their_release()
    local nav = make_nav_client({ throw_on_stop = true })
    local input, key_calls = make_input()

    with_globals(nav, nil, function()
        local ok, report = pcall(function() return MovementRelease.release_all(input) end)
        T.assert_true(ok, "a throwing nav client must not propagate: " .. tostring(report))
        T.assert_equal(#key_calls, #MovementRelease.KEYS,
            "all eight keys must still be released when the nav stop throws")
        T.assert_equal(report.released, #MovementRelease.KEYS)
        T.assert_equal(report.errors, 0, "a nav failure is not one of the eight key errors")
        T.assert_not_nil(report.nav_error, "but it must be reported, not swallowed")
    end)
end

--- Absent is not an error, exactly as it is not for a partial injector build: SentinelNavClient
--- is a separate plugin and may simply not be loaded.
function M.test_an_absent_nav_client_does_not_cost_the_eight_keys_their_release()
    local input, key_calls = make_input()

    with_globals(nil, nil, function()
        local ok, report = pcall(function() return MovementRelease.release_all(input) end)
        T.assert_true(ok, "no nav client at all must not throw: " .. tostring(report))
        T.assert_equal(#key_calls, #MovementRelease.KEYS)
        T.assert_true(report.nav_stopped == false, "nothing was stopped")
        T.assert_true(report.nav_missing == true, "and the absence is reported, not guessed at")
        T.assert_equal(report.errors, 0, "absent is not an error")
    end)
end

--- A nav client that exists but exposes no `stop` -- an older SentinelNavClient build. Same
--- verdict as a missing `*_stop` on the input table: counted, not fatal.
function M.test_a_nav_client_without_stop_is_counted_not_fatal()
    local nav = make_nav_client({ omit_stop = true })
    local input, key_calls = make_input()

    with_globals(nav, nil, function()
        local ok, report = pcall(function() return MovementRelease.release_all(input) end)
        T.assert_true(ok, tostring(report))
        T.assert_equal(#key_calls, #MovementRelease.KEYS)
        T.assert_true(report.nav_missing == true)
        T.assert_equal(report.errors, 0)
    end)
end

--- With no explicit nav argument it must reach the real plugin. Same reasoning as
--- `test_defaults_to_the_live_core_input`: a resolver that silently did nothing when handed no
--- double would be absent in game and present in every test.
function M.test_the_nav_stop_defaults_to_the_live_plugin()
    local nav, nav_calls = make_nav_client()
    local input = make_input()

    with_globals(nav, nil, function()
        MovementRelease.release_all(input)   -- nav argument omitted
        T.assert_equal(nav_calls.stop, 1,
            "with no nav argument the releaser must resolve _G.SentinelNavClient.client")
    end)
end

-- ---------------------------------------------------------------------------
-- NAV AS A LEASE CONSUMER (change 2)
-- ---------------------------------------------------------------------------

--- Nav stops being a fourth authority and becomes a consumer of the MOVEMENT channel like
--- everything else. Without this, the broker can stop navigation but cannot ARBITRATE it: two
--- callers still race for the client with the broker unaware either exists.
function M.test_the_adapter_acquires_movement_before_driving_navigation()
    local nav, nav_calls = make_nav_client()
    local broker = ControlBroker:new({ input = make_input() })
    broker:begin_tick(1)

    with_globals(nav, fake_api(broker), function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 1, y = 2, z = 3 }, { owner = "questing" }))
        T.assert_equal(nav_calls.move_to, 1, "the command must still reach the client")

        local owner = broker:who_owns("MOVEMENT")
        T.assert_equal(owner, "questing",
            "driving navigation must hold the MOVEMENT lease that authorises it")
    end)
end

--- Band ordering replaces the adapter's private `preempt = true` flag. Combat asking for
--- MOVEMENT while questing holds it is a preemption the BROKER expresses -- and the broker's
--- preemption is deliberately not a same-tick handover (control_broker.lua's livelock guards),
--- so the loser is revoked now and the winner acquires on a later tick.
function M.test_a_higher_band_preempts_navigation_through_the_broker()
    local nav, nav_calls = make_nav_client()
    local broker = ControlBroker:new({ input = make_input() })
    broker:begin_tick(1)

    with_globals(nav, fake_api(broker), function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 1, y = 1, z = 1 }, { owner = "questing" }))
        T.assert_equal(broker:who_owns("MOVEMENT"), "questing")

        -- Combat preempts. The revocation is immediate -- safety cannot wait a tick to STOP
        -- something -- and the revocation is what stops questing's navigation.
        local ok, reason = adapter:move_to({ x = 2, y = 2, z = 2 },
            { owner = "combat", band = "COMBAT", preempt = true })
        T.assert_true(ok == false, "the broker does not hand over in the same tick")
        T.assert_equal(reason, "preemption_pending")
        T.assert_equal(nav_calls.stop, 1,
            "the preempted holder's navigation must be stopped, not left running")
        T.assert_nil(broker:who_owns("MOVEMENT"), "the channel is cooling, held by nobody")

        -- Next tick the cool-down has run out and combat gets it.
        broker:begin_tick(3)
        T.assert_true(adapter:move_to({ x = 2, y = 2, z = 2 },
            { owner = "combat", band = "COMBAT", preempt = true }))
        T.assert_equal(broker:who_owns("MOVEMENT"), "combat")
    end)
end

--- A lower band cannot steal MOVEMENT from a higher one. This is the guarantee the adapter's
--- `can_claim` used to provide ("a subsequent unowned questing move_to is rejected at the
--- ADAPTER level ... combat's in-flight path is not silently overwritten"), now provided by
--- the arbiter that was built for it.
function M.test_a_lower_band_cannot_steal_navigation_from_a_higher_one()
    local nav, nav_calls = make_nav_client()
    local broker = ControlBroker:new({ input = make_input() })
    broker:begin_tick(1)

    with_globals(nav, fake_api(broker), function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 1, y = 1, z = 1 },
            { owner = "combat", band = "COMBAT" }))
        T.assert_equal(nav_calls.move_to, 1)

        local ok, reason = adapter:move_to({ x = 9, y = 9, z = 9 }, { owner = "questing" })
        T.assert_true(ok == false, "questing must not overwrite combat's in-flight path")
        T.assert_equal(reason, "channel_held")
        T.assert_equal(nav_calls.move_to, 1, "and the client must never be re-commanded")
        T.assert_equal(broker:who_owns("MOVEMENT"), "combat")
    end)
end

--- An abandoned navigation -- the caller stops polling, faults, or is unloaded mid-path -- is
--- bounded by the lease TTL rather than running forever. §6.1: "A plugin that faults mid-tick
--- cannot permanently hold MOVEMENT." With nav under the broker that sentence finally covers
--- navigation too, and the expiry's force-release is what actually halts the character.
function M.test_an_abandoned_navigation_is_stopped_by_lease_expiry()
    local nav, nav_calls = make_nav_client()
    local broker = ControlBroker:new({ input = make_input() })
    broker:begin_tick(1)

    with_globals(nav, fake_api(broker), function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 5, y = 5, z = 5 }, { owner = "questing" }))
        T.assert_equal(nav_calls.stop, 0)

        -- Nobody renews. The adapter renews on every poll() and on every re-dispatch, so this
        -- is precisely the "caller went away" case.
        for tick = 2, 6 do broker:arbitrate(tick) end

        T.assert_equal(nav_calls.stop, 1,
            "an abandoned navigation must be stopped by TTL expiry, not run until the lake")
        T.assert_nil(broker:who_owns("MOVEMENT"))
    end)
end

--- Polling renews. `poll()` is what app.lua registers in SENSE every tick, so a navigation that
--- is still being watched must not be torn down underneath its watcher.
function M.test_polling_renews_the_movement_lease()
    local nav, nav_calls = make_nav_client({ state = "navigating", full_state = "navigating.following_path" })
    local broker = ControlBroker:new({ input = make_input() })
    broker:begin_tick(1)

    with_globals(nav, fake_api(broker), function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 5, y = 5, z = 5 }, { owner = "questing" }))

        for tick = 2, 6 do
            broker:begin_tick(tick)
            adapter:poll()
            broker:arbitrate(tick)
        end

        T.assert_equal(nav_calls.stop, 0, "a polled navigation must not be revoked out from under itself")
        T.assert_equal(broker:who_owns("MOVEMENT"), "questing")
    end)
end

--- Releasing the adapter hands MOVEMENT back, so the next caller is not rejected forever.
--- chase_controller does exactly this when it comes into range.
function M.test_releasing_the_adapter_hands_the_movement_lease_back()
    local nav = make_nav_client()
    local broker = ControlBroker:new({ input = make_input() })
    broker:begin_tick(1)

    with_globals(nav, fake_api(broker), function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 1, y = 1, z = 1 },
            { owner = "combat", band = "COMBAT" }))
        T.assert_equal(broker:who_owns("MOVEMENT"), "combat")

        T.assert_true(adapter:release("combat"))
        T.assert_nil(broker:who_owns("MOVEMENT"),
            "release must give the channel back, or questing stays rejected forever")

        T.assert_true(adapter:move_to({ x = 2, y = 2, z = 2 }, { owner = "questing" }))
        T.assert_equal(broker:who_owns("MOVEMENT"), "questing")
    end)
end

--- WITHOUT A KERNEL, NAV STILL WORKS. Deliberate, and the riskiest line in this change.
---
--- SentinelNavClient and the questing module both predate the kernel and run in configurations
--- where `_G.Sentinel` was never built. Failing CLOSED there would mean "no broker" implies "no
--- movement at all" -- a certain, total regression bought for a safety property that is already
--- delivered by the force-release above, which needs no lease. Absence of an arbiter is not the
--- same as an arbiter's refusal.
function M.test_navigation_still_works_when_no_broker_exists()
    local nav, nav_calls = make_nav_client()

    with_globals(nav, nil, function()
        local adapter = NavAdapter:new(nil)
        T.assert_true(adapter:move_to({ x = 1, y = 2, z = 3 }, { owner = "questing" }),
            "no kernel must not mean no movement")
        T.assert_equal(nav_calls.move_to, 1)
    end)
end

return M
