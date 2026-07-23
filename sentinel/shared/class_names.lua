-- sentinel/shared/class_names.lua
-- Single authority for numeric class_id -> class name (B8).
--
-- Two independent copies used to exist (modules/combat/module.lua UPPER-CASE,
-- modules/questing/runtime_profile.lua Title-Case) with different casing and
-- no shared source of truth. Title-Case is the authority here because
-- `ClassIs` runtime conditions and RestedXP guide class tails ("Warrior",
-- "!Rogue") compare against Title-Case names -- questing's copy was correct
-- for that contract. Combat wants UPPER-CASE for `player.class_name`; it
-- upper-cases at its own boundary (see modules/combat/module.lua) rather
-- than this module exposing two casings.
--
-- IDs match both the injector class enums and the tbcmangos DB
-- player_classlevelstats: {1,2,3,4,5,6,7,8,9,11}. 6 (Death Knight) is not
-- playable in TBC; included for forward-compat.

local ClassNames = {}

--- Title-Case class_id -> name map. Do not mutate at runtime.
ClassNames.CLASS_ID_TO_NAME = {
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [6] = "DeathKnight",
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
    [11] = "Druid",
}

--- Resolve a numeric class_id to its Title-Case name, or nil if unknown.
---@param class_id number|nil
---@return string|nil
function ClassNames.resolve(class_id)
    if class_id == nil then
        return nil
    end
    return ClassNames.CLASS_ID_TO_NAME[class_id]
end

return ClassNames
