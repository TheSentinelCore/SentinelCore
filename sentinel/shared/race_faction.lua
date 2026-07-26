-- shared/race_faction.lua
-- race_id -> faction side. ADR 07 §9 item 17 records that player FACTION is not readable from
-- the Sylvannas API — but RACE is (`get_race_id()` returns a bare number), and race determines
-- faction by a ten-entry constant. This is the one derivation that makes faction-split flight
-- nodes ("Gadgetzan, Tanaris" exists once per side) resolvable at runtime.
--
-- Ids are the client's ChrRaces ids, the same axis `get_race_id()` reads. 9 is unused in 2.4.3.
-- VERIFY-IN-GAME: confirm get_race_id() returns ChrRaces ids (1=Human … 11=Draenei); shared
-- class_names.lua carries the same caveat for get_class() and it held.
local RaceFaction = {}

local RACE_TO_FACTION = {
    [1] = "Alliance",  -- Human
    [2] = "Horde",     -- Orc
    [3] = "Alliance",  -- Dwarf
    [4] = "Alliance",  -- Night Elf
    [5] = "Horde",     -- Undead
    [6] = "Horde",     -- Tauren
    [7] = "Alliance",  -- Gnome
    [8] = "Horde",     -- Troll
    [10] = "Horde",    -- Blood Elf
    [11] = "Alliance", -- Draenei
}

---@param race_id number|nil
---@return string|nil "Alliance" | "Horde", nil for an unknown or missing id — never a guess
function RaceFaction.resolve(race_id)
    return RACE_TO_FACTION[tonumber(race_id)]
end

return RaceFaction
