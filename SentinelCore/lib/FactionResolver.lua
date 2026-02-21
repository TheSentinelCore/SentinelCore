local FactionResolver = {}

local ALLIANCE_FACTIONS = {
    [47] = true, [54] = true, [69] = true, [72] = true,
    [469] = true, [471] = true, [509] = true, [589] = true,
    [730] = true, [890] = true, [891] = true, [930] = true,
    [946] = true, [978] = true,
    [1] = true, [3] = true, [4] = true, [10] = true, [11] = true, [12] = true,
    [23] = true, [53] = true, [55] = true, [56] = true, [57] = true,
    [79] = true, [80] = true, [84] = true, [115] = true,
    [122] = true, [123] = true, [124] = true,
    [1054] = true, [1055] = true, [1629] = true,
    [1638] = true, [1639] = true, [1640] = true,
}

local HORDE_FACTIONS = {
    [67] = true, [76] = true, [81] = true, [510] = true,
    [530] = true, [729] = true, [889] = true, [892] = true,
    [911] = true, [922] = true, [941] = true, [947] = true,
    [2] = true, [5] = true, [6] = true, [29] = true, [33] = true,
    [68] = true, [71] = true, [83] = true, [85] = true,
    [104] = true, [105] = true, [106] = true, [116] = true,
    [125] = true, [126] = true,
    [1602] = true, [1603] = true, [1604] = true, [1610] = true,
    [1623] = true, [1628] = true,
}

local NEUTRAL_FACTIONS = {
    [21] = true, [59] = true, [87] = true, [169] = true, [270] = true,
    [349] = true, [369] = true, [470] = true, [529] = true,
    [576] = true, [577] = true, [609] = true, [909] = true, [910] = true,
    [932] = true, [933] = true, [934] = true, [935] = true, [936] = true,
    [942] = true, [967] = true, [970] = true, [989] = true, [1011] = true,
    [1015] = true, [1031] = true, [1038] = true, [1077] = true,
}

local TEAM_MASK = {
    alliance = 1,
    horde = 2,
    neutral = 3,
}

---@param value any
---@return string|nil
function FactionResolver.resolve_team(value)
    if value == nil then
        return nil
    end

    local numeric = tonumber(value)
    if numeric ~= nil then
        -- 469 is the Alliance meta-faction; early return for backward
        -- compatibility with callers that pass raw team IDs.
        if numeric == 469 then
            return "alliance"
        end
        if numeric == 67 then
            return "horde"
        end
        if numeric == 0 then
            return "neutral"
        end

        if ALLIANCE_FACTIONS[numeric] then
            return "alliance"
        end
        if HORDE_FACTIONS[numeric] then
            return "horde"
        end
        if NEUTRAL_FACTIONS[numeric] then
            return "neutral"
        end
        return nil
    end

    local text = tostring(value):lower()
    if text == "alliance" or text == "horde" or text == "neutral" then
        return text
    end

    return nil
end

---@param value any
---@return boolean
function FactionResolver.is_alliance(value)
    return FactionResolver.resolve_team(value) == "alliance"
end

---@param value any
---@return boolean
function FactionResolver.is_horde(value)
    return FactionResolver.resolve_team(value) == "horde"
end

---@param team string|nil
---@return number|nil
function FactionResolver.team_mask(team)
    if not team then
        return nil
    end
    return TEAM_MASK[tostring(team):lower()]
end

---@param vendor_mask any
---@param team string|nil
---@return boolean|nil
function FactionResolver.vendor_mask_allows_team(vendor_mask, team)
    local mask = tonumber(vendor_mask) or 0
    if mask == 0 then
        return true
    end

    local team_mask = FactionResolver.team_mask(team)
    if team_mask == nil then
        return nil
    end

    local bitlib = bit32 or bit
    if bitlib and bitlib.band then
        return bitlib.band(mask, team_mask) ~= 0
    end

    if team_mask == 1 then
        return mask == 1 or mask == 3
    end
    if team_mask == 2 then
        return mask == 2 or mask == 3
    end
    if team_mask == 3 then
        return mask == 3
    end

    return nil
end

return FactionResolver
