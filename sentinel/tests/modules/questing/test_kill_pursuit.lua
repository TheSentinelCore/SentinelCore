-- tests/modules/questing/test_kill_pursuit.lua
-- The Kill action owns pursuit (combat owns only the rotation), so its notion of
-- "in range" must match the range the combat module will actually act at.
--
-- Measured live 2026-07-23 on a level-3 Paladin: execute_kill called 18 yd
-- "in range" (its threshold was a flat 30) and stopped chasing, while
-- SentinelCombat:update skips the whole GCD tree beyond combat_range + 10
-- (15 yd for melee). Between 15 and 30 yards nobody moved and nobody swung --
-- the target drifted 11.6 -> 14.6 -> 18.1 yd with the player standing still.

local RuntimeAction = require("modules/questing/runtime_action")
local Blackboard = require("core/blackboard")
local T = require("tests/test_util")

local M = {}

--- Creature stub parked `dist` yards along +x from the origin.
--- Must satisfy UnitHelper.get_nearest_creature: is_valid + is_unit + get_npc_id.
local function make_creature(dist, dead, guid)
    local unit = {}
    function unit:get_position() return { x = dist, y = 0, z = 0 } end
    function unit:is_dead() return dead == true end
    function unit:get_name() return "Young Wolf" end
    function unit:is_valid() return true end
    function unit:is_unit() return true end
    function unit:get_npc_id() return 299 end
    function unit:get_guid() return guid or "wolf-1" end
    return unit
end

--- Records every nav command so the test can assert on pursuit, not on internals.
local function make_nav()
    local nav = { moves = {}, stops = 0, active = false }
    function nav:is_active() return self.active end
    function nav:move_to(pos, opts)
        self.moves[#self.moves + 1] = { pos = pos, opts = opts }
        self.active = true
        return true
    end
    function nav:stop()
        self.stops = self.stops + 1
        self.active = false
    end
    return nav
end

local function make_ctx(dist, combat_range, nav)
    local bb = Blackboard:new()
    bb:set("module.combat.combat_range", combat_range)

    local engage_events = {}
    return {
        blackboard = bb,
        nav = nav,
        persist = {},
        event_bus = {
            publish = function(_self, name, data)
                engage_events[#engage_events + 1] = { name = name, data = data }
            end,
        },
        _engage_events = engage_events,
        is_at_npc = function() return false end,
        is_quest_active = function() return true end,
        is_objective_complete = function() return false end,
    }, engage_events
end

--- Install the globals execute_kill reaches for: the local player, the
--- nearest-creature lookup, and the loot input. Returns the loot call log.
local function with_world(dist, dead, fn, guid)
    local previous_om = _G.core.object_manager.get_local_player
    local previous_objs = _G.core.object_manager.get_all_objects
    local previous_target = _G.core.input and _G.core.input.set_target
    local previous_loot = _G.core.input and _G.core.input.loot_object

    local player = {}
    function player:get_position() return { x = 0, y = 0, z = 0 } end
    function player:is_dead() return false end

    local loots = {}
    local creature = make_creature(dist, dead, guid)
    _G.core.object_manager.get_local_player = function() return player end
    _G.core.object_manager.get_all_objects = function() return { creature } end
    _G.core.input = _G.core.input or {}
    _G.core.input.set_target = function() return true end
    _G.core.input.loot_object = function(obj) loots[#loots + 1] = obj end

    local ok, err = pcall(fn, creature, loots)

    _G.core.object_manager.get_local_player = previous_om
    _G.core.object_manager.get_all_objects = previous_objs
    _G.core.input.set_target = previous_target
    _G.core.input.loot_object = previous_loot
    if not ok then error(err) end
    return loots
end

--- Drive one execute_kill tick against a target `dist` yards away.
--- Returns the branch recorded in the kill trace plus the nav stub.
local function run_kill(dist, combat_range)
    local nav = make_nav()
    local branch, status, ctx
    with_world(dist, false, function()
        ctx = make_ctx(dist, combat_range, nav)
        -- UnitHelper.get_nearest_creature resolves through the object manager,
        -- so a matching entry id is all the payload needs.
        status = RuntimeAction.execute_kill(
            { creature_entries = { 299 }, quantity = 40 },
            ctx
        )
        branch = ctx.persist._kill_trace and ctx.persist._kill_trace.branch
    end)
    return branch, status, nav, ctx
end

--- 18 yd from a melee Paladin (combat_range 5) is the dead band: it must chase.
function M.test_melee_chases_inside_the_old_dead_band()
    local branch, status, nav = run_kill(18.0, 5.0)
    T.assert_equal(branch, "chasing", "18 yd from a melee class must pursue, not idle")
    T.assert_equal(status, "waiting")
    T.assert_true(#nav.moves > 0, "pursuit must issue a nav move_to")
end

--- Anything past the old flat 30 yd threshold was already chasing; keep that.
function M.test_far_target_still_chases()
    local branch = run_kill(45.0, 5.0)
    T.assert_equal(branch, "chasing")
end

--- Inside melee range the action engages instead of chasing. For combat_range 5
--- the engage threshold is max(2.5, 5-2) = 3 yd, so 2 yd engages...
function M.test_melee_range_engages()
    local branch, status, _, ctx = run_kill(2.0, 5.0)
    T.assert_equal(branch, "engaging", "inside combat range the action must engage")
    T.assert_equal(status, "waiting")
    T.assert_equal(ctx._engage_events[1].name, "combat:engage_requested")
end

--- ...and 4 yd does NOT. Stopping at the edge of combat_range left a melee
--- character hovering ~5 yd out, where a wandering mob steps out of swing range
--- and the corpse sits outside loot range.
function M.test_melee_closes_to_three_yards()
    local branch = run_kill(4.0, 5.0)
    T.assert_equal(branch, "chasing", "4 yd is still too far for melee -- must close to ~3")
end

--- A ranged profile publishes a much larger combat_range, so 18 yd is already
--- within its engagement window and it must NOT be dragged into melee.
function M.test_ranged_engages_at_distance()
    local branch = run_kill(18.0, 28.0)
    T.assert_equal(branch, "engaging", "a 28 yd caster must engage at 18 yd, not close to melee")
end

--- Once inside engage range, the chase nav must be released so it stops fighting
--- the rotation for control of movement.
function M.test_engaging_stops_chase_nav()
    local nav = make_nav()
    nav.active = true
    local ctx
    with_world(2.0, false, function()
        ctx = make_ctx(2.0, 5.0, nav)
        RuntimeAction.execute_kill({ creature_entries = { 299 }, quantity = 40 }, ctx)
    end)
    T.assert_true(nav.stops > 0, "entering engage range must stop the chase nav")
end

--- The nav tolerance must be tighter than melee range, otherwise nav reports
--- "arrived" while still out of swing range.
function M.test_chase_tolerance_is_tighter_than_melee()
    local _, _, nav = run_kill(18.0, 5.0)
    local opts = nav.moves[1] and nav.moves[1].opts
    T.assert_true(opts ~= nil, "chase must pass nav options")
    T.assert_true(opts.tolerance < 5.0,
        "nav tolerance must be tighter than melee range, got " .. tostring(opts.tolerance))
end

-- ============================================================================
-- Corpse handling: loot before counting, and count each corpse exactly once.
-- ============================================================================

--- Drive N execute_kill ticks against a single dead corpse, sharing one persist
--- table so state carries across ticks the way the real executor does.
local function run_corpse_ticks(ticks, dist)
    local nav = make_nav()
    local persist = {}
    local branches, loots = {}, nil
    loots = with_world(dist or 1.0, true, function()
        for _ = 1, ticks do
            local ctx = make_ctx(dist or 1.0, 5.0, nav)
            ctx.persist = persist
            RuntimeAction.execute_kill({ creature_entries = { 299 }, quantity = 40 }, ctx)
            branches[#branches + 1] = persist._kill_trace.branch
        end
    end)
    return branches, loots, persist, nav
end

--- A kill objective is often an item drop ("Tough Wolf Meat: 0/8"), so walking
--- off without looting can never satisfy it.
function M.test_corpse_is_looted_before_being_counted()
    local branches, loots, persist = run_corpse_ticks(1, 1.0)
    T.assert_equal(branches[1], "looting", "first tick on a corpse must loot it")
    T.assert_equal(#loots, 1, "loot_object must be called on the corpse")
    T.assert_equal(persist.kill_counts["299"], 0, "must not count before looting")
end

--- After looting the corpse gets tallied exactly once.
function M.test_corpse_counted_once_after_looting()
    local branches, _, persist = run_corpse_ticks(8, 1.0)
    T.assert_equal(persist.kill_counts["299"], 1,
        "one corpse must count exactly once, got " .. tostring(persist.kill_counts["299"]))
    T.assert_equal(branches[#branches], "next_target")
end

--- Loot attempts are bounded so an unlootable corpse cannot wedge the run.
function M.test_loot_attempts_are_bounded()
    local _, loots = run_corpse_ticks(10, 1.0)
    T.assert_true(#loots <= 3, "loot attempts must be bounded, got " .. tostring(#loots))
end

--- A corpse out of loot range must be walked to, not looted from afar.
function M.test_far_corpse_is_approached()
    local branches, loots, _, nav = run_corpse_ticks(1, 20.0)
    T.assert_equal(branches[1], "looting_approach", "a distant corpse must be walked to")
    T.assert_equal(#loots, 0, "must not attempt to loot from 20 yd")
    T.assert_true(#nav.moves > 0, "approach must issue a nav move")
end

-- ============================================================================
-- The loop must not wedge on a corpse it has already finished with.
-- Observed live: a looted+counted Timber Wolf 2.3 yd away stayed "nearest"
-- forever, so every tick returned next_target while a live wolf 9 yd out was
-- ignored -- and next_target returned "blocked", burning the retry budget until
-- the Kill action was skipped entirely (executor jumped from action 18 to 19).
-- ============================================================================

--- World with two creatures: a near corpse and a further LIVE target.
local function with_corpse_and_live(corpse_dist, live_dist, fn)
    local previous_om = _G.core.object_manager.get_local_player
    local previous_objs = _G.core.object_manager.get_all_objects
    local previous_target = _G.core.input and _G.core.input.set_target
    local previous_loot = _G.core.input and _G.core.input.loot_object

    local player = {}
    function player:get_position() return { x = 0, y = 0, z = 0 } end
    function player:is_dead() return false end

    local corpse = make_creature(corpse_dist, true, "corpse-1")
    local live = make_creature(live_dist, false, "live-1")

    _G.core.object_manager.get_local_player = function() return player end
    _G.core.object_manager.get_all_objects = function() return { corpse, live } end
    _G.core.input = _G.core.input or {}
    _G.core.input.set_target = function() return true end
    _G.core.input.loot_object = function() end

    local ok, err = pcall(fn, corpse, live)

    _G.core.object_manager.get_local_player = previous_om
    _G.core.object_manager.get_all_objects = previous_objs
    _G.core.input.set_target = previous_target
    _G.core.input.loot_object = previous_loot
    if not ok then error(err) end
end

--- Once the near corpse is looted and counted, the loop must move to the live
--- target instead of returning next_target forever.
function M.test_finished_corpse_is_skipped_for_live_target()
    local persist = {}
    local branches = {}
    with_corpse_and_live(1.0, 9.0, function()
        for _ = 1, 10 do
            local ctx = make_ctx(1.0, 5.0, make_nav())
            ctx.persist = persist
            RuntimeAction.execute_kill({ creature_entries = { 299 }, quantity = 40 }, ctx)
            branches[#branches + 1] = persist._kill_trace.branch
        end
    end)

    local last = branches[#branches]
    T.assert_true(last == "chasing" or last == "engaging",
        "after finishing the corpse the loop must pursue the live target, got " .. tostring(last))
    T.assert_equal(persist.kill_counts["299"], 1, "the corpse counts exactly once")
end

--- next_target must never return "blocked" -- blocked burns the action's retry
--- budget and gets a 40-kill objective abandoned after a few corpses.
function M.test_next_target_does_not_burn_retry_budget()
    local persist = {}
    local statuses = {}
    with_corpse_and_live(1.0, 9.0, function()
        for _ = 1, 6 do
            local ctx = make_ctx(1.0, 5.0, make_nav())
            ctx.persist = persist
            statuses[#statuses + 1] =
                RuntimeAction.execute_kill({ creature_entries = { 299 }, quantity = 40 }, ctx)
        end
    end)
    for i, status in ipairs(statuses) do
        T.assert_true(status ~= "blocked",
            "tick " .. i .. " returned blocked, which burns the retry budget")
    end
end

-- ============================================================================
-- Target stickiness.
-- Observed live: with two wolves at similar range the bot targeted one and moved
-- toward the other, oscillating between them and never arriving. Re-picking
-- "nearest" every tick is the cause -- as the player shifts, which one is nearest
-- flips, and each flip re-issues move_to to a different destination.
-- ============================================================================

--- Two live creatures whose distances SWAP between ticks, simulating the player
--- drifting between them.
local function with_two_swapping_wolves(fn)
    local previous_om = _G.core.object_manager.get_local_player
    local previous_objs = _G.core.object_manager.get_all_objects
    local previous_target = _G.core.input and _G.core.input.set_target

    local player = {}
    function player:get_position() return { x = 0, y = 0, z = 0 } end
    function player:is_dead() return false end

    local dist_a, dist_b = 10.0, 11.0
    local a = make_creature(0, false, "wolf-a")
    local b = make_creature(0, false, "wolf-b")
    function a:get_position() return { x = dist_a, y = 0, z = 0 } end
    function b:get_position() return { x = dist_b, y = 0, z = 0 } end

    _G.core.object_manager.get_local_player = function() return player end
    _G.core.object_manager.get_all_objects = function() return { a, b } end
    _G.core.input = _G.core.input or {}
    _G.core.input.set_target = function() return true end

    local swap = function()
        dist_a, dist_b = dist_b, dist_a
    end

    local ok, err = pcall(fn, swap)

    _G.core.object_manager.get_local_player = previous_om
    _G.core.object_manager.get_all_objects = previous_objs
    _G.core.input.set_target = previous_target
    if not ok then error(err) end
end

--- Even as the two wolves trade places for "nearest", the committed target must
--- not change -- otherwise the chase destination flips every tick.
function M.test_target_does_not_thrash_when_nearest_flips()
    local persist = {}
    local keys = {}
    with_two_swapping_wolves(function(swap)
        for i = 1, 6 do
            local ctx = make_ctx(10.0, 5.0, make_nav())
            ctx.persist = persist
            RuntimeAction.execute_kill({ creature_entries = { 299 }, quantity = 40 }, ctx)
            keys[#keys + 1] = persist._target_key
            if i % 2 == 0 then swap() end
        end
    end)

    for i = 2, #keys do
        T.assert_equal(keys[i], keys[1],
            "target must stay committed across ticks; flipped at tick " .. i)
    end
end

--- A committed target that runs beyond ABANDON_RANGE must be released so the bot
--- does not chase one wolf across the zone forever.
function M.test_target_released_when_it_runs_too_far()
    local persist = {}
    local far = 200.0
    local previous_om = _G.core.object_manager.get_local_player
    local previous_objs = _G.core.object_manager.get_all_objects
    local previous_target = _G.core.input and _G.core.input.set_target

    local player = {}
    function player:get_position() return { x = 0, y = 0, z = 0 } end
    function player:is_dead() return false end

    local runner = make_creature(0, false, "runner")
    function runner:get_position() return { x = far, y = 0, z = 0 } end
    local near = make_creature(6.0, false, "near")

    _G.core.object_manager.get_local_player = function() return player end
    _G.core.object_manager.get_all_objects = function() return { runner, near } end
    _G.core.input = _G.core.input or {}
    _G.core.input.set_target = function() return true end

    -- Commit to the runner first...
    persist._target_key = "guid:runner"
    local ctx = make_ctx(6.0, 5.0, make_nav())
    ctx.persist = persist
    RuntimeAction.execute_kill({ creature_entries = { 299 }, quantity = 40 }, ctx)

    _G.core.object_manager.get_local_player = previous_om
    _G.core.object_manager.get_all_objects = previous_objs
    _G.core.input.set_target = previous_target

    T.assert_equal(persist._target_key, "guid:near",
        "a target beyond ABANDON_RANGE must be dropped for a reachable one")
end

return M
