local Blackboard = require("core/blackboard")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:is_alive() return opts.alive ~= false end
    function unit:get_target() return opts.target end
    function unit:get_pet() return opts.pet end
    return unit
end

local function make_bb(overrides)
    overrides = overrides or {}

    local bb = Blackboard:new()
    local pet_target = overrides.pet_target
    local pet = overrides.pet and make_unit({
        guid = "pet",
        alive = overrides.pet_alive ~= false,
        target = pet_target,
    }) or nil

    local player = make_unit({
        guid = "player",
        pet = pet,
    })

    bb:set("player.object", player)
    return bb
end

function M.run()
    local PetController = require("modules/combat/profiles/mage/pet_controller")

    -- get_state returns "idle" initially
    local pc = PetController:new()
    T.assert_equal(pc:get_state(), "idle", "initial state should be idle")

    -- refresh detects live pet and sets has_water_elemental = true
    local bb = make_bb({ pet = true, pet_alive = true })
    pc:refresh(bb)
    T.assert_true(bb:get("combat.has_water_elemental"), "should detect live pet")
    T.assert_false(bb:get("combat.pet_is_attacking"), "pet without target should not be attacking")

    -- refresh detects pet with target and sets pet_is_attacking = true
    local pet_target = make_unit({ guid = "mob1" })
    bb = make_bb({ pet = true, pet_alive = true, pet_target = pet_target })
    pc:refresh(bb)
    T.assert_true(bb:get("combat.has_water_elemental"), "should detect live pet")
    T.assert_true(bb:get("combat.pet_is_attacking"), "pet with target should be attacking")

    -- refresh detects no pet and sets has_water_elemental = false
    bb = make_bb({ pet = false })
    pc:refresh(bb)
    T.assert_false(bb:get("combat.has_water_elemental"), "should detect no pet")
    T.assert_false(bb:get("combat.pet_is_attacking"), "no pet should not be attacking")

    -- refresh detects dead pet and sets has_water_elemental = false
    bb = make_bb({ pet = true, pet_alive = false })
    pc:refresh(bb)
    T.assert_false(bb:get("combat.has_water_elemental"), "dead pet should set false")

    -- attack transitions state to "attacking"
    pc = PetController:new()
    local target = make_unit({ guid = "mob1" })
    pc:attack(target)
    T.assert_equal(pc:get_state(), "attacking", "state should be attacking after attack")

    -- passive transitions state to "passive"
    pc:passive()
    T.assert_equal(pc:get_state(), "passive", "state should be passive after passive")

    -- reset clears state to "idle"
    pc:reset()
    T.assert_equal(pc:get_state(), "idle", "state should be idle after reset")

    -- already_sent_to returns true for same target, false for different
    pc = PetController:new()
    local mob1 = make_unit({ guid = "mob1" })
    local mob2 = make_unit({ guid = "mob2" })
    pc:attack(mob1)
    T.assert_true(pc:already_sent_to(mob1), "should recognize same target")
    T.assert_false(pc:already_sent_to(mob2), "should not match different target")

    -- already_sent_to returns false when idle (no target sent to)
    pc = PetController:new()
    T.assert_false(pc:already_sent_to(mob1), "idle controller should not match any target")

    -- freeze transitions state to "attacking" (pet engages via freeze)
    pc = PetController:new()
    pc:freeze(mob1)
    T.assert_equal(pc:get_state(), "attacking", "freeze should transition to attacking")

    -- attack after passive returns to "attacking"
    pc = PetController:new()
    pc:attack(mob1)
    pc:passive()
    T.assert_equal(pc:get_state(), "passive", "should be passive")
    pc:attack(mob2)
    T.assert_equal(pc:get_state(), "attacking", "should be attacking again after re-attack")
    T.assert_true(pc:already_sent_to(mob2), "should track new target after re-attack")
    T.assert_false(pc:already_sent_to(mob1), "should not track old target after re-attack")

    -- refresh with no player sets false
    local bb_empty = Blackboard:new()
    bb_empty:set("player.object", nil)
    pc:refresh(bb_empty)
    T.assert_false(bb_empty:get("combat.has_water_elemental"), "no player should set false")
    T.assert_false(bb_empty:get("combat.pet_is_attacking"), "no player should set pet_is_attacking false")
end

return M
