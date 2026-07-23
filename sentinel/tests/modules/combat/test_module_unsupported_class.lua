-- Unit C (C3): characterization/red tests proving the combat module disables
-- cleanly (no throw, no wrong-class rotation) when Registry.resolve returns nil
-- for an unmapped class_id, instead of the old silent Paladin fallback.
--
-- Separate file from test_module.lua because that module uses the M.run()
-- dispatch (run_offline.lua:386-417 runs ONLY M.run() when present, never
-- test* alongside it) -- this file uses the test* dispatch style, mirroring
-- test_spell_catalog_known_rank.lua.
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SentinelCombat = require("modules/combat/module")
local T = require("tests/test_util")

local M = {}

local function make_nav()
    return {
        move_to = function() end,
        stop = function() end,
        is_active = function() return false end,
    }
end

-- 9 (Warlock) was unregistered as of Unit C; Unit D registered it
-- (WarlockAfflictionTBC), so the unmapped-class fixture moved to 99 -- a
-- class_id with no plausible mapping in any unit of this change.
local UNSUPPORTED_CLASS_ID = 99

local function mock_player_with_class(class_id)
    return {
        object_manager = {
            get_local_player = function()
                return { get_class = function() return class_id end }
            end,
        },
        spell_book = {
            get_specialization_id = function() return 0 end,
        },
    }
end

function M.test_initialize_with_unsupported_class_does_not_throw()
    local prev_core = _G.core
    _G.core = mock_player_with_class(UNSUPPORTED_CLASS_ID)

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local combat = SentinelCombat:new(bus, bb, make_nav())

    local ok, err = pcall(function() combat:initialize() end)
    _G.core = prev_core

    T.assert_true(ok, "initialize() must not throw for an unmapped class_id: " .. tostring(err))
end

function M.test_initialize_with_unsupported_class_disables_combat()
    local prev_core = _G.core
    _G.core = mock_player_with_class(UNSUPPORTED_CLASS_ID)

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local combat = SentinelCombat:new(bus, bb, make_nav())
    combat:initialize()
    _G.core = prev_core

    T.assert_equal(bb:get("module.combat.enabled", true), false,
        "combat must be disabled on the blackboard when class_id resolves to nil")
end

function M.test_update_no_ops_after_unsupported_class_disable()
    local prev_core = _G.core
    _G.core = mock_player_with_class(UNSUPPORTED_CLASS_ID)

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local combat = SentinelCombat:new(bus, bb, make_nav())
    combat:initialize()
    bb:set("system.now_ms", 1000)

    local ok, err = pcall(function() combat:update(bb) end)
    _G.core = prev_core

    T.assert_true(ok, "update() must no-op cleanly (not throw) after an unsupported-class disable: " .. tostring(err))
    T.assert_equal(combat:get_state(), "IDLE", "combat must stay IDLE when disabled for an unsupported class")
end

-- _confirm_class_detection re-resolves later in the boot sequence (module.lua:562)
-- once a real class_id becomes readable; it must guard the same nil case.
function M.test_confirm_class_detection_disables_on_unsupported_class_without_throwing()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local combat = SentinelCombat:new(bus, bb, make_nav())

    -- Boot with no readable player object -- initialize() defers to the mage
    -- placeholder (class_id 8) and leaves _class_confirmed false, exactly like
    -- test_module.lua's Test 3.
    combat:initialize()
    T.assert_false(combat._class_confirmed, "class should not be confirmed without a readable player object")

    local prev_core = _G.core
    _G.core = mock_player_with_class(UNSUPPORTED_CLASS_ID)

    local ok, err = pcall(function() combat:_confirm_class_detection(bb) end)
    _G.core = prev_core

    T.assert_true(ok, "_confirm_class_detection must not throw for an unmapped class_id: " .. tostring(err))
    T.assert_true(combat._class_confirmed, "class should still latch as confirmed even when the resolved profile is nil")
    T.assert_equal(bb:get("module.combat.enabled", true), false,
        "combat must be disabled once a real but unsupported class_id is confirmed")
end

return M
