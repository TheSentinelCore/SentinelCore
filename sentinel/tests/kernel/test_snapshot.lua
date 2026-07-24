-- tests/kernel/test_snapshot.lua
-- ADR 08 §2.7 -- the single most important invariant in Phase 1:
--
--   "Every game_object is a raw 8-byte pointer into game memory that can become invalid
--    BETWEEN USES, and the docs say to guard before EVERY use, not just at acquisition.
--    A 'snapshot frozen for the tick' that stores game_object references is therefore
--    unsound -- the pointer can die inside the tick that froze it. The snapshot must
--    store EXTRACTED VALUES."
--
-- That invariant is unenforceable by convention, so it is enforced structurally: `put`
-- REFUSES anything carrying behaviour (userdata, functions, or a table containing them --
-- which is what every handle looks like), and every accepted table is deep-copied so the
-- snapshot owns its data outright.
--
-- ADR 08 §13 risk 2 is the other half: "Under-capture forces a mid-tick live read, which
-- reintroduces exactly the inconsistency the snapshot exists to prevent." Hence `get` on a
-- missing key is loud enough to notice (`has`), not a silent nil that reads like a value.

local Snapshot = require("kernel/snapshot")
local T = require("tests/test_util")

local M = {}

function M.test_builder_stores_and_reads_scalars()
    local b = Snapshot.builder()
    b:put("player.health_pct", 0.75)
    b:put("player.name", "Sentinel")
    b:put("player.in_combat", true)
    local snap = b:freeze()

    T.assert_equal(snap:get("player.health_pct"), 0.75)
    T.assert_equal(snap:get("player.name"), "Sentinel")
    T.assert_equal(snap:get("player.in_combat"), true)
end

function M.test_missing_key_returns_the_default()
    local snap = Snapshot.builder():freeze()
    T.assert_nil(snap:get("player.nothing"))
    T.assert_equal(snap:get("player.nothing", 7), 7)
    T.assert_false(snap:has("player.nothing"))
end

--- Frozen means frozen. A late write is a bug in the caller, and it fails loudly.
function M.test_frozen_snapshot_rejects_further_writes()
    local b = Snapshot.builder()
    b:put("player.level", 60)
    local snap = b:freeze()

    local ok, err = pcall(function() b:put("player.level", 70) end)
    T.assert_false(ok, "writing through the builder after freeze must fail")
    T.assert_true(tostring(err):find("frozen", 1, true) ~= nil, "the refusal must be named: " .. tostring(err))
    T.assert_equal(snap:get("player.level"), 60, "the frozen value must be unchanged")
end

function M.test_snapshot_object_rejects_field_assignment()
    local snap = Snapshot.builder():freeze()
    local ok = pcall(function() snap.injected = "nope" end)
    T.assert_false(ok, "the snapshot object itself must reject assignment")
end

--- The core refusal: a raw handle must never enter the snapshot.
function M.test_put_refuses_a_game_object_handle()
    local b = Snapshot.builder()
    local handle = {
        is_valid = function() return true end,
        get_position = function() return { x = 1, y = 2, z = 3 } end,
    }
    local ok, err = pcall(function() b:put("player.object", handle) end)
    T.assert_false(ok, "a handle-shaped table must be refused (ADR 08 §2.7)")
    T.assert_true(tostring(err):find("player.object", 1, true) ~= nil, "the refusal must name the key: " .. tostring(err))
end

function M.test_put_refuses_a_bare_function()
    local b = Snapshot.builder()
    local ok = pcall(function() b:put("player.getter", function() return 1 end) end)
    T.assert_false(ok, "a function is behaviour, not a value")
end

--- Handles nested one level down are the realistic mistake: a sensor builds a table of
--- "extracted" values and leaves the unit handle in it.
function M.test_put_refuses_a_handle_nested_inside_a_value_table()
    local b = Snapshot.builder()
    local ok, err = pcall(function()
        b:put("player.target", {
            name = "Kobold",
            distance = 12.5,
            unit = { is_valid = function() return true end }, -- the smuggled handle
        })
    end)
    T.assert_false(ok, "a handle nested inside a value table must still be refused")
    T.assert_true(tostring(err):find("player.target", 1, true) ~= nil, tostring(err))
end

--- Deep copy is what makes "frozen" true for tables, not just for scalars.
function M.test_tables_are_deep_copied_on_put()
    local source = { x = 1, y = 2, z = 3, tags = { "a", "b" } }
    local b = Snapshot.builder()
    b:put("player.position", source)
    local snap = b:freeze()

    source.x = 999
    source.tags[1] = "mutated"

    T.assert_equal(snap:get("player.position").x, 1, "mutating the source must not reach the snapshot")
    T.assert_equal(snap:get("player.position").tags[1], "a", "the copy must be deep, not shallow")
end

--- Self-referential input would hang a naive deep copy.
function M.test_cyclic_tables_are_refused_not_hung_on()
    local cyclic = { name = "loop" }
    cyclic.self_ref = cyclic
    local b = Snapshot.builder()
    local ok, err = pcall(function() b:put("player.weird", cyclic) end)
    T.assert_false(ok, "a cyclic table must be refused rather than copied forever")
    T.assert_true(tostring(err):find("cycle", 1, true) ~= nil, tostring(err))
end

function M.test_keys_lists_what_was_captured()
    local b = Snapshot.builder()
    b:put("player.health_pct", 1)
    b:put("player.level", 60)
    local snap = b:freeze()

    local keys = snap:keys()
    table.sort(keys)
    T.assert_equal(#keys, 2)
    T.assert_equal(keys[1], "player.health_pct")
    T.assert_equal(keys[2], "player.level")
end

--- The tick index is what lets a consumer prove it is reading THIS tick's snapshot and not
--- a reference stashed from an earlier one (ADR 08 §6.1, the caretaker idea).
function M.test_carries_its_tick_index()
    local snap = Snapshot.builder({ tick_index = 42 }):freeze()
    T.assert_equal(snap:tick_index(), 42)
    T.assert_true(snap:is_frozen())
end

function M.test_builder_is_not_frozen_before_freeze()
    local b = Snapshot.builder()
    T.assert_false(b:is_frozen())
    b:put("player.level", 1)
    T.assert_equal(b:get("player.level"), 1, "the builder must be readable while it is being filled")
end

return M
