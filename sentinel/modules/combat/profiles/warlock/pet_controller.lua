-- Voidwalker pet controller. MVP scope: summon + attack + alive-state
-- maintenance only. Torment (threat) is explicitly DEFERRED -- see design Open
-- Questions -- casting a pet-bar spell needs core.spell_book.get_pet_spells /
-- get_pet_happiness plumbing that isn't needed for 1-70 leveling survivability.
local PetController = {}
PetController.__index = PetController

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function get_guid(unit)
    local ok, guid = safe_call(unit, "get_guid")
    if ok and guid then
        return guid
    end
    return nil
end

function PetController:new()
    local o = setmetatable({}, PetController)
    o._state = "idle"
    o._sent_guid = nil
    return o
end

function PetController:get_state()
    return self._state
end

--- Refreshes `combat.has_voidwalker` on the blackboard from the live pet
--- object. Called once per tick_off_gcd (mirrors mage/pet_controller.lua's
--- refresh contract, distinct blackboard key so the two pets never collide).
function PetController:refresh(bb)
    local player = bb:get("player.object")
    if not player then
        bb:set("combat.has_voidwalker", false)
        return
    end

    local ok_pet, pet = safe_call(player, "get_pet")
    if not ok_pet or not pet then
        bb:set("combat.has_voidwalker", false)
        return
    end

    local ok_alive, alive = safe_call(pet, "is_alive")
    bb:set("combat.has_voidwalker", ok_alive and alive == true)
end

function PetController:attack(target)
    self._state = "attacking"
    self._sent_guid = get_guid(target)
    if core and core.input then
        pcall(core.input.pet_attack, target)
    end
end

function PetController:already_sent_to(target)
    if not target or not self._sent_guid then
        return false
    end
    return self._sent_guid == get_guid(target)
end

--- Recall on disengage: passive + follow stops an in-progress attack so the
--- Voidwalker cannot chain-pull between kills. Clears the sent guid so the
--- next engagement re-sends attack. Guarded for SDK absence.
function PetController:passive()
    self._state = "passive"
    self._sent_guid = nil
    if core and core.input then
        pcall(core.input.set_pet_passive)
        pcall(core.input.set_pet_follow)
    end
end

function PetController:reset()
    self._state = "idle"
    self._sent_guid = nil
end

return PetController
