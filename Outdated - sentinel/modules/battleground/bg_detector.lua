local Catalog = require("modules/battleground/data/bg_catalog")

local Detector = {}
Detector.__index = Detector

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

function Detector:new()
    return setmetatable({}, Detector)
end

local function combined_name(map_name, instance_name)
    return (tostring(map_name or "") .. " " .. tostring(instance_name or "")):lower()
end

local function matches_alias(data, haystack)
    local lowered = tostring(haystack or ""):lower()
    if lowered == "" or not data then
        return false
    end
    if lowered:find(tostring(data.name or ""):lower(), 1, true) then
        return true
    end
    local aliases = data.aliases or {}
    for _, alias in ipairs(aliases) do
        local normalized = tostring(alias or ""):lower()
        if normalized ~= "" and lowered:find(normalized, 1, true) then
            return true
        end
    end
    return false
end

function Detector:detect(map_id, map_name, instance_id, instance_name)
    local map_num = num(map_id)
    local instance_num = num(instance_id)
    for key, data in pairs(Catalog) do
        if data.map_id == map_num then
            return key, data, "map_id"
        end
    end
    for key, data in pairs(Catalog) do
        if data.map_id == instance_num then
            return key, data, "instance_id"
        end
    end
    for key, data in pairs(Catalog) do
        if data.battleground_id == map_num then
            return key, data, "battleground_id"
        end
    end
    for key, data in pairs(Catalog) do
        if data.battleground_id == instance_num then
            return key, data, "battleground_id"
        end
    end

    local lowered_map_name = tostring(map_name or ""):lower()
    for key, data in pairs(Catalog) do
        if matches_alias(data, lowered_map_name) then
            return key, data, "map_name"
        end
    end

    local lowered_instance_name = tostring(instance_name or ""):lower()
    for key, data in pairs(Catalog) do
        if matches_alias(data, lowered_instance_name) then
            return key, data, "instance_name"
        end
    end

    local joined = combined_name(map_name, instance_name)
    for key, data in pairs(Catalog) do
        if matches_alias(data, joined) then
            return key, data, "combined_name"
        end
    end
    return nil, nil, "unresolved"
end

local ALLIANCE_FACTION_IDS = {
    [1] = true,     -- Human
    [3] = true,     -- Dwarf
    [4] = true,     -- Night Elf
    [115] = true,   -- Gnome
    [1629] = true,  -- Draenei
    [469] = true,   -- Alliance (generic)
    [11] = true,    -- Stormwind
    [55] = true,    -- Ironforge
    [79] = true,    -- Darnassus
    [80] = true,    -- Gnomeregan Exiles
    [927] = true,   -- Exodar
}

local HORDE_FACTION_IDS = {
    [2] = true,     -- Orc
    [5] = true,     -- Undead
    [6] = true,     -- Tauren
    [116] = true,   -- Troll
    [1610] = true,  -- Blood Elf
    [67] = true,    -- Horde (generic)
    [29] = true,    -- Orgrimmar
    [68] = true,    -- Undercity
    [104] = true,   -- Thunder Bluff
    [126] = true,   -- Darkspear Trolls
    [911] = true,   -- Silvermoon City
}

function Detector:resolve_side(bg_key, position, player_object)
    if player_object and type(player_object.get_faction_id) == "function" then
        local ok, fid = pcall(player_object.get_faction_id, player_object)
        if ok and tonumber(fid) then
            local id = tonumber(fid)
            if ALLIANCE_FACTION_IDS[id] then
                return "ALLIANCE"
            end
            if HORDE_FACTION_IDS[id] then
                return "HORDE"
            end
        end
    end

    local data = Catalog[bg_key]
    if not data or type(position) ~= "table" then
        return nil
    end
    local da = distance(position, data.anchors.ALLIANCE)
    local dh = distance(position, data.anchors.HORDE)
    if math.abs(da - dh) < 30 then
        return nil
    end
    if da <= dh then
        return "ALLIANCE"
    end
    return "HORDE"
end

return Detector
