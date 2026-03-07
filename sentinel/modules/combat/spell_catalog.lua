local SpellCatalog = {}
SpellCatalog.__index = SpellCatalog

local SPELLS = {
    seal_of_blood = { key = "seal_of_blood", id = 31892, gcd = true, description = "Seal of Blood" },
    seal_of_command = { key = "seal_of_command", ranks = { 20375, 20915, 20918, 20919, 20920, 27170 }, gcd = true, description = "Seal of Command" },
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
        return spell.id
    end
    if spell.ranks and #spell.ranks > 0 then
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
        return spell.id
    end
    if spell.ranks and #spell.ranks > 0 then
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
