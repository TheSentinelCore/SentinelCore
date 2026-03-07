local AuraCatalog = {
    seal_of_blood = 31892,
    seal_of_command_ranks = { 20375, 20915, 20918, 20919, 20920, 27170 },
    blessing_of_might_ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140 },
    blessing_of_kings = 20217,
    retribution_aura_ranks = { 7294, 10298, 10299, 10300, 10301, 27150 },
    vengeance_proc_auras = { 20050, 20052, 20053, 20054, 20055 },
    hard_immunity_auras = { 642, 45438, 1020 },
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

    local ok_has, active = safe_call(unit, "has_buff", list)
    if ok_has and active == true then
        return true
    end

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

return AuraCatalog
