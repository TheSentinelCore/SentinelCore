local AuraCatalog = {
    -- Paladin
    seal_of_blood = 31892,
    seal_of_command_ranks = { 20375, 20915, 20918, 20919, 20920, 27170 },
    blessing_of_might_ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140 },
    blessing_of_kings = 20217,
    retribution_aura_ranks = { 7294, 10298, 10299, 10300, 10301, 27150 },
    vengeance_proc_auras = { 20050, 20052, 20053, 20054, 20055 },
    hard_immunity_auras = { 642, 45438, 1020 },

    -- Mage: Frozen mechanic debuffs (on target)
    frost_nova_debuffs = { 122, 865, 6131, 10230, 27088 },
    frostbite_debuffs = { 11071, 12496, 12497 },
    water_elemental_freeze = { 33395 },
    all_frozen_debuffs = { 122, 865, 6131, 10230, 27088, 11071, 12496, 12497, 33395 },

    -- Mage: Defensive auras (on self)
    ice_barrier_auras = { 11426, 13031, 13032, 13033, 27134, 33405 },
    mana_shield_auras = { 1463, 8494, 8495, 10191, 10192, 10193, 27131 },
    icy_veins_aura = 12472,

    -- Mage: CC tracking (on target)
    polymorph_debuffs = { 118, 12824, 12825, 12826 },
}

local ok_buff_manager, buff_manager = pcall(require, "common/modules/buff_manager")
AuraCatalog.buff_manager = ok_buff_manager and buff_manager or nil

local function normalize_ids(ids)
    if type(ids) == "number" then
        return { ids }
    end
    if type(ids) == "table" then
        return ids
    end
    return {}
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

function AuraCatalog.has_any(unit, ids)
    local list = normalize_ids(ids)
    if not unit or #list == 0 then
        return false
    end

    -- IZI SDK game object extension: has_aura() with list
    local ok_has, active = safe_call(unit, "has_aura", list)
    if ok_has and active == true then
        return true
    end

    -- Fallback to individual has_buff checks
    for _, spell_id in ipairs(list) do
        ok_has, active = safe_call(unit, "has_buff", spell_id)
        if ok_has and active == true then
            return true
        end
        local ok_data, data = safe_call(unit, "get_buff_data", spell_id)
        if ok_data and type(data) == "table" and (data.is_active == true or tonumber(data.stack_count or 0) > 0) then
            return true
        end
    end

    if AuraCatalog.buff_manager and type(AuraCatalog.buff_manager.get_buff_data) == "function" then
        local ok_mgr, data = pcall(AuraCatalog.buff_manager.get_buff_data, AuraCatalog.buff_manager, unit, list)
        if ok_mgr and type(data) == "table" and data.is_active == true then
            return true
        end
    end

    local ok_buffs, buffs = safe_call(unit, "get_buffs")
    if ok_buffs and type(buffs) == "table" then
        for _, buff in ipairs(buffs) do
            local aura_id = tonumber(buff.spell_id or buff.id or buff.buff_id)
            if aura_id then
                for _, wanted in ipairs(list) do
                    if aura_id == wanted then
                        return true
                    end
                end
            end
        end
    end

    return false
end

AuraCatalog.has = AuraCatalog.has_any
AuraCatalog.has_any_buff = AuraCatalog.has_any

function AuraCatalog.get_stacks(unit, ids)
    local list = normalize_ids(ids)
    if not unit or #list == 0 then
        return 0
    end
    for _, spell_id in ipairs(list) do
        local ok_stacks, stacks = safe_call(unit, "get_buff_stacks", spell_id)
        if ok_stacks and tonumber(stacks) and tonumber(stacks) > 0 then
            return tonumber(stacks)
        end
        local ok_data, data = safe_call(unit, "get_buff_data", spell_id)
        if ok_data and type(data) == "table" then
            local count = tonumber(data.stack_count or data.stacks or 0) or 0
            if count > 0 then
                return count
            end
        end
    end
    if AuraCatalog.buff_manager and type(AuraCatalog.buff_manager.get_buff_data) == "function" then
        local ok_mgr, data = pcall(AuraCatalog.buff_manager.get_buff_data, AuraCatalog.buff_manager, unit, list)
        if ok_mgr and type(data) == "table" then
            return tonumber(data.stack_count or data.stacks or 0) or 0
        end
    end
    return 0
end

function AuraCatalog.has_protection(unit)
    return AuraCatalog.has_any(unit, AuraCatalog.hard_immunity_auras)
end

function AuraCatalog.has_any_debuff(unit, ids)
    local list = normalize_ids(ids)
    if not unit or #list == 0 then
        return false
    end

    for _, spell_id in ipairs(list) do
        local ok_has, active = safe_call(unit, "has_debuff", spell_id)
        if ok_has and active == true then
            return true
        end
    end

    local ok_debuffs, debuffs = safe_call(unit, "get_debuffs")
    if ok_debuffs and type(debuffs) == "table" then
        for _, debuff in ipairs(debuffs) do
            local aura_id = tonumber(debuff.spell_id or debuff.id or debuff.buff_id)
            if aura_id then
                for _, wanted in ipairs(list) do
                    if aura_id == wanted then
                        return true
                    end
                end
            end
        end
    end

    return false
end

AuraCatalog.has_debuff = function(unit, id)
    return AuraCatalog.has_any_debuff(unit, id)
end

AuraCatalog.get_stack = function(unit, id)
    return AuraCatalog.get_stacks(unit, id)
end

return AuraCatalog
