-- tests/kernel/test_snapshot_source.lua
-- The SENSE stage: turn live game_object handles into frozen values.
--
-- THE TEST THAT MATTERS is test_snapshot_survives_a_handle_invalidated_mid_tick.
--
-- ADR 08 §2.7: "Every game_object is a raw 8-byte pointer into game memory that can become
-- invalid BETWEEN USES ... the pointer can die INSIDE the tick that froze it."
--
-- So the contract is not "the snapshot is taken at the start of the tick". It is "the
-- snapshot remains readable and correct even after every handle it was built from has
-- become garbage". That is only true if the source extracted values and dropped the
-- pointer, which is exactly what this file proves.
--
-- ADR 08 §9.3 is the second contract: what cannot be read must be NAMED unavailable, not
-- silently defaulted. "Without an explicit unavailable value, every unreadable field
-- silently becomes a plausible-looking zero."

local Snapshot = require("kernel/snapshot")
local SnapshotSource = require("kernel/snapshot_source")
local T = require("tests/test_util")

local M = {}

--- A stand-in for a Sylvanas game_object. `kill()` models the pointer going stale: every
--- accessor throws afterwards, which is the harshest realistic behaviour.
local function make_handle(fields)
    local alive = true
    local h = {}
    function h.kill() alive = false end
    function h:is_valid() return alive end
    local function guarded(value)
        return function()
            if not alive then error("game_object accessed after invalidation", 0) end
            return value
        end
    end
    h.get_position = guarded(fields.position)
    h.get_health = guarded(fields.health)
    h.get_max_health = guarded(fields.max_health)
    h.get_power = guarded(fields.power)
    h.get_max_power = guarded(fields.max_power)
    h.get_level = guarded(fields.level)
    h.get_class = guarded(fields.class_id)
    h.is_in_combat = guarded(fields.in_combat)
    h.is_casting_spell = guarded(fields.casting)
    h.is_channelling_spell = guarded(fields.channeling)
    h.is_moving = guarded(fields.moving)
    h.is_dead = guarded(fields.dead)
    h.is_mounted = guarded(fields.mounted)
    h.get_target = guarded(fields.target)
    return h
end

local function default_player()
    return make_handle({
        position = { x = -8912.5, y = -132.3, z = 83.2 },
        health = 750, max_health = 1000,
        power = 300, max_power = 1200,
        level = 34, class_id = 8,
        in_combat = true, casting = false, channeling = false,
        moving = true, dead = false, mounted = false,
        target = nil,
    })
end

function M.test_captures_hot_tier_player_values()
    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, default_player())
    local snap = b:freeze()

    T.assert_true(snap:get("player.available"), "a readable player must be marked available")
    T.assert_near(snap:get("player.health_pct"), 0.75, 0.0001)
    T.assert_near(snap:get("player.power_pct"), 0.25, 0.0001)
    T.assert_equal(snap:get("player.level"), 34)
    T.assert_equal(snap:get("player.in_combat"), true)
    T.assert_equal(snap:get("player.is_moving"), true)
    T.assert_near(snap:get("player.position").x, -8912.5, 0.0001)
end

--- =====================================================================================
--- THE INVARIANT. Build the snapshot, then destroy every handle it came from, then read.
--- =====================================================================================
function M.test_snapshot_survives_a_handle_invalidated_mid_tick()
    local player = default_player()

    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, player)
    local snap = b:freeze()

    -- The pointer dies INSIDE the tick that froze the snapshot. Every accessor now throws.
    player.kill()
    T.assert_false(player:is_valid(), "precondition: the handle is now invalid")
    T.assert_false(pcall(function() return player.get_health() end),
        "precondition: touching the dead handle must throw")

    -- ...and the snapshot is completely unaffected, because it never held the pointer.
    T.assert_true(snap:get("player.available"))
    T.assert_near(snap:get("player.health_pct"), 0.75, 0.0001)
    T.assert_equal(snap:get("player.level"), 34)
    T.assert_near(snap:get("player.position").x, -8912.5, 0.0001)
    T.assert_near(snap:get("player.position").z, 83.2, 0.0001)
end

--- Corollary: the handle must not be reachable FROM the snapshot at all. If any key held
--- it, a consumer could revive the mid-tick live read the snapshot exists to prevent.
function M.test_no_handle_is_reachable_from_the_snapshot()
    local player = default_player()
    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, player)
    local snap = b:freeze()

    local function contains_behaviour(value, depth)
        if depth > 6 then return false end
        local t = type(value)
        if t == "function" or t == "userdata" or t == "thread" then return true end
        if t == "table" then
            for k, v in pairs(value) do
                if contains_behaviour(k, depth + 1) or contains_behaviour(v, depth + 1) then
                    return true
                end
            end
        end
        return false
    end

    for _, key in ipairs(snap:keys()) do
        T.assert_false(contains_behaviour(snap:get(key), 0),
            "key '" .. key .. "' carries behaviour -- a handle leaked into the snapshot")
    end
end

--- ADR 08 §9.3: absent is NAMED, not defaulted to a plausible zero.
function M.test_absent_player_is_named_unavailable()
    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, nil)
    local snap = b:freeze()

    T.assert_false(snap:get("player.available"), "no player must be reported as unavailable")
    T.assert_nil(snap:get("player.health_pct"), "an unreadable vital must be nil, NOT 0 and NOT 1")
    T.assert_nil(snap:get("player.position"))
    T.assert_nil(snap:get("player.level"))
end

--- A handle that is already stale at SENSE time is the same case as no handle at all.
function M.test_already_invalid_handle_is_unavailable()
    local player = default_player()
    player.kill()

    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, player)
    local snap = b:freeze()

    T.assert_false(snap:get("player.available"))
    T.assert_nil(snap:get("player.health_pct"))
end

--- A handle that passes is_valid() and then dies between two accessor calls is precisely
--- the case ADR 08 §2.7 warns about ("guard before EVERY use"). Partial capture must not
--- throw out of the sensor, and the fields that were read stay correct.
function M.test_handle_dying_between_accessor_calls_does_not_throw()
    local player = default_player()
    local original_get_health = player.get_health
    player.get_health = function()
        player.kill()             -- dies partway through capture
        return original_get_health()
    end

    local b = Snapshot.builder()
    local ok, err = pcall(function() SnapshotSource.capture_player(b, player) end)
    T.assert_true(ok, "a handle dying mid-capture must not throw out of the sensor: " .. tostring(err))

    local snap = b:freeze()
    T.assert_false(snap:get("player.available"),
        "a player that died mid-capture must be reported unavailable, not partially true")
end

--- Zero max health is a real reading (a corpse, a loading unit); it must not divide by zero
--- or invent a full health bar.
function M.test_zero_max_health_yields_nil_not_a_fabricated_ratio()
    local player = make_handle({
        position = { x = 0, y = 0, z = 0 },
        health = 0, max_health = 0,
        power = 0, max_power = 0,
        level = 1, class_id = 1,
    })
    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, player)
    local snap = b:freeze()

    T.assert_nil(snap:get("player.health_pct"), "0/0 must be nil, not 1 and not 0")
    T.assert_nil(snap:get("player.power_pct"))
end

--- ADR 08 §9.3 / the repo's own recorded trap: get_class() returns a NUMERIC class id,
--- and raw Sylvanas types must stop at the sensor boundary.
function M.test_class_is_normalized_at_the_sensor_boundary()
    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, default_player())
    local snap = b:freeze()

    T.assert_equal(snap:get("player.class_id"), 8, "the raw numeric id is preserved for the record")
    T.assert_equal(snap:get("player.class"), "Mage", "…and normalized to the Title-Case name")
end

--- Target capture: values only, and the handle must not survive into the snapshot either.
function M.test_target_is_captured_as_values()
    local target = make_handle({
        position = { x = 10, y = 20, z = 30 },
        health = 50, max_health = 100,
        power = 0, max_power = 0,
        level = 30, class_id = 1,
        dead = false,
    })
    local player = default_player()
    player.get_target = function() return target end

    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, player)
    local snap = b:freeze()

    T.assert_true(snap:get("target.available"))
    T.assert_near(snap:get("target.health_pct"), 0.5, 0.0001)
    T.assert_equal(snap:get("target.level"), 30)

    target.kill()
    T.assert_near(snap:get("target.health_pct"), 0.5, 0.0001,
        "the target snapshot must outlive its handle too")
end

function M.test_absent_target_is_named_unavailable()
    local b = Snapshot.builder()
    SnapshotSource.capture_player(b, default_player())
    local snap = b:freeze()

    T.assert_false(snap:get("target.available"))
    T.assert_nil(snap:get("target.health_pct"))
end

return M
