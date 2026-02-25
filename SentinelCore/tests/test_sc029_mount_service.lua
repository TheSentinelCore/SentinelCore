-- Regression tests for MountService.
--
-- Covers:
-- (1)  Construction with noop logger
-- (2)  should_mount() → false when in_combat
-- (3)  should_mount() → false when already mounted (blackboard)
-- (4)  should_mount() → false when player level below min_level
-- (5)  should_mount() → true when all conditions satisfied
-- (6)  try_mount() → sets player.is_mounted when known class spell exists
-- (7)  try_mount() → no-op for unknown class_id (no crash)
-- (8)  try_dismount() → clears player.is_mounted flag
-- (9)  try_dismount() → no-op when not mounted
-- (10) PULL_STARTED event fires try_dismount()
-- (11) TARGET_ACQUIRED event fires try_dismount()
-- (12) update() returns truthy (passive no-op)

local TU = require("tests/TestUtil")

local M = {}

function M.run()
    local env = TU.install_core_stub()

    -- Add spell_book.is_spell_learned and input.cast_spell_self to the core stub
    local known_spells = {}
    env.core.spell_book.is_spell_learned = function(spell_id)
        return known_spells[spell_id] == true
    end
    local cast_calls = {}
    env.core.input.cast_spell_self = function(spell_id)
        cast_calls[#cast_calls + 1] = spell_id
    end
    local dismount_calls = 0
    env.core.input.dismount = function()
        dismount_calls = dismount_calls + 1
    end

    local EventBus    = require("events/EventBus")
    local Blackboard  = require("core/Blackboard")
    local Events      = require("events/Events")
    local MountService = require("services/MountService")

    local now = 1000
    env.core.time = function() return now end

    local function fresh()
        local eb = EventBus:new()
        local bb = Blackboard:new(eb)
        bb:set("player.in_combat", false)
        bb:set("player.is_mounted", false)
        bb:set("player.level", 40)
        bb:set("player.class_id", 2)   -- Paladin
        known_spells = {}
        cast_calls = {}
        dismount_calls = 0
        now = 1000
        env.core.time = function() return now end
        local svc = MountService:new(eb, bb, { min_level = 40 })
        return svc, eb, bb
    end

    -- -----------------------------------------------------------------------
    -- Test 1: construction succeeds, update() returns true
    -- -----------------------------------------------------------------------
    local svc, eb, bb = fresh()
    assert(svc ~= nil, "Test 1: MountService:new() returned nil")
    local ok_update = svc:update()
    assert(ok_update == true, "Test 1: update() should return true")

    -- -----------------------------------------------------------------------
    -- Test 2: should_mount() → false while in combat
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.in_combat", true)
    assert(svc:should_mount() == false,
        "Test 2: should_mount must be false while in combat")

    -- -----------------------------------------------------------------------
    -- Test 3: should_mount() → false when already mounted (blackboard)
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.is_mounted", true)
    assert(svc:should_mount() == false,
        "Test 3: should_mount must be false when already mounted")

    -- -----------------------------------------------------------------------
    -- Test 4: should_mount() → false when player is below min_level
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.level", 39)
    assert(svc:should_mount() == false,
        "Test 4: should_mount must be false below min_level=40")

    -- -----------------------------------------------------------------------
    -- Test 5: should_mount() → true when all conditions are met
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    assert(svc:should_mount() == true,
        "Test 5: should_mount should be true with level=40, not mounted, not in combat")

    -- -----------------------------------------------------------------------
    -- Test 6: try_mount() sets player.is_mounted when a known class spell exists
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    known_spells[13819] = true   -- Paladin Warhorse (L40)
    svc:try_mount()
    assert(bb:get("player.is_mounted") == true,
        "Test 6: player.is_mounted should be set after successful mount")
    assert(#cast_calls == 1,
        "Test 6: expected 1 cast_spell_self call, got " .. #cast_calls)
    assert(cast_calls[1] == 13819 or cast_calls[1] == 34769,
        "Test 6: unexpected spell ID cast: " .. tostring(cast_calls[1]))

    -- -----------------------------------------------------------------------
    -- Test 7: try_mount() → no crash and no cast for unknown class_id
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.class_id", 3)   -- Warrior — no entry in CLASS_MOUNT_SPELLS
    cast_calls = {}
    svc:try_mount()
    -- Should not crash, no cast issued (no class entry)
    assert(#cast_calls == 0,
        "Test 7: no cast expected for unknown class_id=3, got " .. #cast_calls)

    -- -----------------------------------------------------------------------
    -- Test 8: try_dismount() clears player.is_mounted
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.is_mounted", true)
    svc:try_dismount()
    assert(bb:get("player.is_mounted") == false,
        "Test 8: player.is_mounted should be cleared by try_dismount()")
    assert(dismount_calls == 1,
        "Test 8: expected 1 dismount call, got " .. dismount_calls)

    -- -----------------------------------------------------------------------
    -- Test 9: try_dismount() → no-op when not mounted
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.is_mounted", false)
    dismount_calls = 0
    svc:try_dismount()
    assert(dismount_calls == 0,
        "Test 9: no dismount call expected when not mounted")
    assert(bb:get("player.is_mounted") == false,
        "Test 9: player.is_mounted should still be false")

    -- -----------------------------------------------------------------------
    -- Test 10: PULL_STARTED event triggers try_dismount()
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.is_mounted", true)
    dismount_calls = 0
    eb:emit(Events.PULL_STARTED, {})
    assert(bb:get("player.is_mounted") == false,
        "Test 10: PULL_STARTED event should trigger dismount")

    -- -----------------------------------------------------------------------
    -- Test 11: TARGET_ACQUIRED event triggers try_dismount()
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    bb:set("player.is_mounted", true)
    dismount_calls = 0
    eb:emit(Events.TARGET_ACQUIRED, {})
    assert(bb:get("player.is_mounted") == false,
        "Test 11: TARGET_ACQUIRED event should trigger dismount")

    -- -----------------------------------------------------------------------
    -- Test 12: Cooldown prevents immediate remount after try_mount()
    -- -----------------------------------------------------------------------
    svc, eb, bb = fresh()
    known_spells[13819] = true
    svc:try_mount()
    assert(bb:get("player.is_mounted") == true, "Test 12 setup: mounted OK")
    -- Simulate dismount then immediate remount attempt within cooldown
    bb:set("player.is_mounted", false)
    cast_calls = {}
    -- Time has not advanced past mount cooldown (2.0s)
    svc:try_mount()
    assert(#cast_calls == 0,
        "Test 12: remount within cooldown window should be skipped")

    env.restore()
    return true
end

return M
