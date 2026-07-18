local SpellCatalog = {}
SpellCatalog.__index = SpellCatalog

local SPELLS = {
    seal_of_blood = { key = "seal_of_blood", id = 31892, gcd = true, description = "Seal of Blood" },
    seal_of_command = { key = "seal_of_command", ranks = { 20375, 20915, 20918, 20919, 20920, 27170 }, gcd = true, description = "Seal of Command" },
    seal_of_righteousness = { key = "seal_of_righteousness", ranks = { 20154, 20284, 20285, 20286, 20287, 20288, 20289, 20290, 20291, 27156 }, gcd = true, description = "Seal of Righteousness" },
    judgement = { key = "judgement", id = 20271, gcd = true, description = "Judgement" },
    judgement_of_blood = { key = "judgement_of_blood", id = 31898, gcd = false, description = "Judgement of Blood proc" },
    judgement_of_command = { key = "judgement_of_command", id = 27171, gcd = false, description = "Judgement of Command proc" },
    crusader_strike = { key = "crusader_strike", id = 35395, gcd = true, description = "Crusader Strike" },
    avenging_wrath = { key = "avenging_wrath", id = 31884, gcd = false, ogcd = true, description = "Avenging Wrath" },
    consecration = { key = "consecration", ranks = { 26573, 20116, 20922, 20923, 20924, 27173 }, gcd = true, description = "Consecration" },
    blessing_of_might = { key = "blessing_of_might", ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140 }, gcd = true, description = "Blessing of Might" },
    blessing_of_kings = { key = "blessing_of_kings", id = 20217, gcd = true, description = "Blessing of Kings" },
    retribution_aura = { key = "retribution_aura", ranks = { 7294, 10298, 10299, 10300, 10301, 27150 }, gcd = true, description = "Retribution Aura" },
    vengeance_talent = { key = "vengeance_talent", ranks = { 20049, 20056, 20057, 20058, 20059 }, gcd = false, description = "Vengeance talent" },
    vengeance_proc = { key = "vengeance_proc", ranks = { 20050, 20052, 20053, 20054, 20055 }, gcd = false, description = "Vengeance proc aura" },
    hammer_of_wrath = { key = "hammer_of_wrath", ranks = { 24275, 24274, 24239, 27180 }, gcd = true, description = "Hammer of Wrath" },
    hammer_of_justice = { key = "hammer_of_justice", ranks = { 853, 5588, 5589, 10308 }, gcd = true, description = "Hammer of Justice" },
    repentance = { key = "repentance", id = 20066, gcd = true, description = "Repentance" },

    -- Mage: Frost Combat
    frostbolt = { key = "frostbolt", ranks = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304, 27071, 27072, 38697 }, gcd = true, description = "Frostbolt" },
    frost_nova = { key = "frost_nova", ranks = { 122, 865, 6131, 10230, 27088 }, gcd = true, description = "Frost Nova" },
    cone_of_cold = { key = "cone_of_cold", ranks = { 120, 8492, 10159, 10160, 10161, 27087 }, gcd = true, description = "Cone of Cold" },
    blizzard = { key = "blizzard", ranks = { 10, 6141, 8427, 10185, 10186, 10187, 27085 }, gcd = true, description = "Blizzard" },
    ice_lance = { key = "ice_lance", id = 30455, gcd = true, description = "Ice Lance" },

    -- Mage: Fire/Arcane Combat
    fireball = { key = "fireball", ranks = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306, 27070 }, gcd = true, description = "Fireball" },
    fire_blast = { key = "fire_blast", ranks = { 2136, 2137, 2138, 8412, 8413, 10197, 10199, 27078, 27079 }, gcd = true, description = "Fire Blast" },
    counterspell = { key = "counterspell", id = 2139, gcd = true, description = "Counterspell" },

    -- Mage: Defensive
    ice_barrier = { key = "ice_barrier", ranks = { 11426, 13031, 13032, 13033, 27134, 33405 }, gcd = false, ogcd = true, description = "Ice Barrier" },
    ice_block = { key = "ice_block", id = 45438, gcd = true, description = "Ice Block" },
    blink = { key = "blink", id = 1953, gcd = true, description = "Blink" },
    mana_shield = { key = "mana_shield", ranks = { 1463, 8494, 8495, 10191, 10192, 10193, 27131 }, gcd = true, description = "Mana Shield" },

    -- Mage: Cooldowns
    evocation = { key = "evocation", id = 12051, gcd = true, description = "Evocation" },
    cold_snap = { key = "cold_snap", id = 11958, gcd = false, ogcd = true, description = "Cold Snap" },
    icy_veins = { key = "icy_veins", id = 12472, gcd = false, ogcd = true, description = "Icy Veins" },

    -- Mage: Buffs
    frost_armor = { key = "frost_armor", ranks = { 168, 7300, 7301 }, gcd = true, description = "Frost Armor" },
    ice_armor = { key = "ice_armor", ranks = { 7302, 7320, 10219, 10220, 27124 }, gcd = true, description = "Ice Armor" },
    arcane_intellect = { key = "arcane_intellect", ranks = { 1459, 1460, 1461, 10156, 10157, 27126 }, gcd = true, description = "Arcane Intellect" },

    -- Mage: Conjure
    conjure_food = { key = "conjure_food", ranks = { 587, 597, 990, 6129, 10144, 10145, 28612, 33717 }, gcd = true, description = "Conjure Food" },
    conjure_water = { key = "conjure_water", ranks = { 5504, 5505, 5506, 6127, 10138, 10139, 10140, 27090, 37420 }, gcd = true, description = "Conjure Water" },

    -- Mage: CC / AoE / Utility
    polymorph = { key = "polymorph", ranks = { 118, 12824, 12825, 12826 }, gcd = true, description = "Polymorph" },
    spellsteal = { key = "spellsteal", id = 30449, gcd = true, description = "Spellsteal" },
    arcane_explosion = { key = "arcane_explosion", ranks = { 1449, 8437, 8438, 8439, 10201, 10202, 27080, 27082 }, gcd = true, description = "Arcane Explosion" },
    flamestrike = { key = "flamestrike", ranks = { 2120, 2121, 8422, 8423, 10215, 10216, 27086 }, gcd = true, description = "Flamestrike" },
    scorch = { key = "scorch", ranks = { 2948, 8444, 8445, 8446, 10205, 10206, 10207, 27073, 27074 }, gcd = true, description = "Scorch" },
    dragons_breath = { key = "dragons_breath", ranks = { 31661, 33041, 33042, 33043 }, gcd = true, description = "Dragon's Breath" },
    summon_water_elemental = { key = "summon_water_elemental", id = 31687, gcd = true, description = "Summon Water Elemental" },

    -- Mage: Defensive / Utility
    frost_ward = { key = "frost_ward", ranks = { 6143, 8461, 8462, 10177, 28609 }, gcd = true, description = "Frost Ward" },
    fire_ward = { key = "fire_ward", ranks = { 543, 8457, 8458, 10223, 10225, 27128 }, gcd = true, description = "Fire Ward" },
    invisibility = { key = "invisibility", id = 66, gcd = true, description = "Invisibility" },
    mage_armor = { key = "mage_armor", ranks = { 6117, 22782, 22783, 27125 }, gcd = true, description = "Mage Armor" },
    molten_armor = { key = "molten_armor", id = 30482, gcd = true, description = "Molten Armor" },

    -- Mage: Conjure Mana Gems
    conjure_mana_agate = { key = "conjure_mana_agate", id = 759, gcd = true, description = "Conjure Mana Agate" },
    conjure_mana_jade = { key = "conjure_mana_jade", id = 3552, gcd = true, description = "Conjure Mana Jade" },
    conjure_mana_citrine = { key = "conjure_mana_citrine", id = 10053, gcd = true, description = "Conjure Mana Citrine" },
    conjure_mana_ruby = { key = "conjure_mana_ruby", id = 10054, gcd = true, description = "Conjure Mana Ruby" },
    conjure_mana_emerald = { key = "conjure_mana_emerald", id = 27101, gcd = true, description = "Conjure Mana Emerald" },
}

local function shallow_copy(src)
    local out = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            local sub = {}
            for i = 1, #value do
                sub[i] = value[i]
            end
            out[key] = sub
        else
            out[key] = value
        end
    end
    return out
end

function SpellCatalog:new()
    local o = setmetatable({}, SpellCatalog)
    o._spells = {}
    o._id_index = {}
    for key, data in pairs(SPELLS) do
        o._spells[key] = shallow_copy(data)
        if data.id then
            o._id_index[data.id] = key
        end
        if data.ranks then
            for _, spell_id in ipairs(data.ranks) do
                o._id_index[spell_id] = key
            end
        end
    end
    return o
end

function SpellCatalog:get(key)
    return self._spells[key]
end

function SpellCatalog:all()
    return self._spells
end

function SpellCatalog:find_key_by_id(spell_id)
    return self._id_index[tonumber(spell_id) or -1]
end

function SpellCatalog:resolve_best_rank(key)
    local spell = self:get(key)
    if not spell then
        return nil
    end
    if spell.id then
        if core and core.spell_book and core.spell_book.has_spell then
            local ok, known = pcall(core.spell_book.has_spell, spell.id)
            if ok and known then return spell.id end
            return nil
        end
        return spell.id
    end
    if spell.ranks and #spell.ranks > 0 then
        if core and core.spell_book and core.spell_book.has_spell then
            for i = #spell.ranks, 1, -1 do
                local ok, known = pcall(core.spell_book.has_spell, spell.ranks[i])
                if ok and known then return spell.ranks[i] end
            end
            return nil
        end
        return spell.ranks[#spell.ranks]
    end
    return nil
end

function SpellCatalog:resolve_lowest_rank(key)
    local spell = self:get(key)
    if not spell then
        return nil
    end
    if spell.id then
        if core and core.spell_book and core.spell_book.has_spell then
            local ok, known = pcall(core.spell_book.has_spell, spell.id)
            if ok and known then return spell.id end
            return nil
        end
        return spell.id
    end
    if spell.ranks and #spell.ranks > 0 then
        if core and core.spell_book and core.spell_book.has_spell then
            for i = 1, #spell.ranks do
                local ok, known = pcall(core.spell_book.has_spell, spell.ranks[i])
                if ok and known then return spell.ranks[i] end
            end
            return nil
        end
        return spell.ranks[1]
    end
    return nil
end

local function get_spell(self, key_or_id)
    if type(key_or_id) == "string" then
        return self:get(key_or_id)
    end
    local key = self:find_key_by_id(key_or_id)
    return key and self:get(key) or nil
end

function SpellCatalog:is_gcd_spell(key_or_id)
    local spell = get_spell(self, key_or_id)
    return spell and spell.gcd == true or false
end

function SpellCatalog:is_ogcd_spell(key_or_id)
    local spell = get_spell(self, key_or_id)
    return spell and spell.ogcd == true or false
end

return SpellCatalog
