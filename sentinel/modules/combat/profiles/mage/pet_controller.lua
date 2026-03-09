local PetController = {}
PetController.__index = PetController

local FREEZE_SPELL_ID = 33395

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

function PetController:refresh(bb)
    local player = bb:get("player.object")
    if not player then
        bb:set("combat.has_water_elemental", false)
        bb:set("combat.pet_is_attacking", false)
        return
    end

    local ok_pet, pet = safe_call(player, "get_pet")
    if not ok_pet or not pet then
        bb:set("combat.has_water_elemental", false)
        bb:set("combat.pet_is_attacking", false)
        return
    end

    local ok_alive, alive = safe_call(pet, "is_alive")
    local is_alive = ok_alive and alive == true
    bb:set("combat.has_water_elemental", is_alive)

    if is_alive then
        local ok_target, pet_target = safe_call(pet, "get_target")
        bb:set("combat.pet_is_attacking", ok_target and pet_target ~= nil)
    else
        bb:set("combat.pet_is_attacking", false)
    end
end

function PetController:attack(target)
    self._state = "attacking"
    self._sent_guid = get_guid(target)
    if core and core.input then
        pcall(core.input.pet_attack, target)
    end
end

function PetController:freeze(target)
    self._state = "attacking"
    self._sent_guid = get_guid(target)
    if core and core.input then
        pcall(core.input.pet_cast_target_spell, FREEZE_SPELL_ID, target)
    end
end

function PetController:passive()
    self._state = "passive"
    if core and core.input then
        pcall(core.input.set_pet_passive)
        pcall(core.input.set_pet_follow)
    end
end

function PetController:reset()
    self._state = "idle"
    self._sent_guid = nil
end

function PetController:already_sent_to(target)
    if not target or not self._sent_guid then
        return false
    end
    return self._sent_guid == get_guid(target)
end

return PetController
