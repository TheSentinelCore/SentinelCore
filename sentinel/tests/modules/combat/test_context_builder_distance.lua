-- tests/modules/combat/test_context_builder_distance.lua
-- C6: `combat.target_distance` has two writers -- context_builder.lua (this
-- file) and chase_controller.lua -- and they must agree on what to do when
-- neither one can measure a real distance this tick.
--
-- ContextBuilder:refresh() runs BEFORE module.lua's _ensure_target() picks a
-- fresh target for the tick. On an acquisition tick, `combat.target` (and
-- sometimes `player.target`) can be nil/positionless here even though a
-- target is about to be chosen a few lines later in module.lua. The old
-- behaviour wrote a hardcoded 99999 "far" sentinel into `combat.target_distance`
-- in that gap, stomping whatever chase_controller had measured last tick and
-- spuriously failing `target_distance <= 10.0` (burst_context's range gate) on
-- the very tick a nearby target is (re)acquired. The fix: on a positionless
-- refresh, keep the last real value already on the blackboard instead of a
-- sentinel, and only fall back to Geometry's math.huge sentinel if nothing has
-- ever been written.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local ContextBuilder = require("modules/combat/context_builder")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_position() return opts.position end
    function unit:is_dead() return opts.dead == true end
    function unit:has_buff() return false end
    function unit:get_buff_data() return { is_active = false, stack_count = 0 } end
    function unit:get_buff_stacks() return 0 end
    function unit:get_buffs() return {} end
    return unit
end

local function make_bb()
    local bb = Blackboard:new()
    local player = make_unit({})
    bb:set("player.object", player)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("module.combat.enable_burst", true)
    bb:set("module.combat.primary_seal_preference", "blood")
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("system.now_ms", 1000)
    return bb
end

--- First-ever refresh, no target at all: falls back to Geometry's math.huge
--- sentinel because nothing has been written before (F5 consistency: no
--- private 99999 sentinel anywhere in this file anymore).
function M.test_no_target_ever_falls_back_to_math_huge()
    local bb = make_bb()
    -- No combat.target, no player.target.
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("combat.target_distance"), math.huge)
end

--- Normal tick: target present with a real position -> real measured distance.
function M.test_target_with_position_measures_real_distance()
    local bb = make_bb()
    bb:set("combat.target", make_unit({ position = { x = 3, y = 4, z = 0 } }))
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_near(bb:get("combat.target_distance"), 5.0, 0.0001)
end

--- C6 regression: simulate the acquisition-tick gap. chase_controller wrote a
--- close real distance last tick; this tick ContextBuilder runs before a new
--- target has been chosen (both combat.target and player.target still nil).
--- The stale-but-real distance must survive, not get stomped by a sentinel.
function M.test_acquisition_tick_preserves_last_real_distance()
    local bb = make_bb()
    -- Simulate chase_controller.lua's write from the previous tick.
    bb:set("combat.target_distance", 4.5)

    -- No combat.target / player.target resolvable this tick (the acquisition gap).
    ContextBuilder:new(bb):refresh(EventBus:new())

    T.assert_equal(bb:get("combat.target_distance"), 4.5,
        "acquisition-tick refresh must not stomp the last real distance with a sentinel")
end

--- Once the target resolves again (normal ticks resume), ContextBuilder must
--- go back to measuring for real rather than being stuck on the stale value.
function M.test_recovers_real_measurement_next_tick()
    local bb = make_bb()
    bb:set("combat.target_distance", 4.5)
    ContextBuilder:new(bb):refresh(EventBus:new()) -- acquisition gap tick

    bb:set("combat.target", make_unit({ position = { x = 6, y = 8, z = 0 } }))
    ContextBuilder:new(bb):refresh(EventBus:new()) -- target now resolvable

    T.assert_near(bb:get("combat.target_distance"), 10.0, 0.0001)
end

return M
