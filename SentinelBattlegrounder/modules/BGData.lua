local vec3 = require("common/geometry/vector_3")

local BGData = {}

BGData.CITY_STORMWIND = "stormwind"
BGData.CITY_ORGRIMMAR = "orgrimmar"

BGData.BG_ALTERAC = "alterac"
BGData.BG_WARSONG = "warsong"
BGData.BG_ARATHI = "arathi"
BGData.BG_EOTS = "eots"

BGData.PLAYER_FACTION_ALLIANCE = "alliance"
BGData.PLAYER_FACTION_HORDE = "horde"
BGData.PLAYER_FACTION_UNKNOWN = "unknown"

BGData.CITY_ANCHORS = {
    [BGData.CITY_STORMWIND] = vec3.new(-8385.58, 272.413, 120.969),
    [BGData.CITY_ORGRIMMAR] = vec3.new(1980.9, -4787.78, 55.8796),
}

local function clone_vec3(v)
    return vec3.new(v.x, v.y, v.z)
end

BGData.PREFERRED_BATTLEMASTERS = {
    [BGData.CITY_STORMWIND] = {
        [BGData.BG_ALTERAC] = {
            npc_id = 7410,
            name = "Thelman Slatefist",
            map_id = 0,
            position = vec3.new(-8385.58, 272.413, 120.969),
        },
        [BGData.BG_WARSONG] = {
            npc_id = 14981,
            name = "Elfarran",
            map_id = 0,
            position = vec3.new(-8394.89, 265.282, 120.969),
        },
    },
}

BGData.AV_LAST_GY_BY_CITY = {
    [BGData.CITY_STORMWIND] = vec3.new(638.0, -32.0, 46.0),
    [BGData.CITY_ORGRIMMAR] = vec3.new(-1407.0, -308.0, 89.0),
}

BGData.ALLIANCE_FACTION_IDS = {
    [1] = true,
    [3] = true,
    [4] = true,
    [115] = true,
    [1629] = true,
    [469] = true,
}

BGData.HORDE_FACTION_IDS = {
    [2] = true,
    [5] = true,
    [6] = true,
    [116] = true,
    [1610] = true,
    [67] = true,
}

local function make_id_set(ids)
    local set = {}
    for _, id in ipairs(ids) do
        set[id] = true
    end
    return set
end

BGData.BG_DATA = {
    [BGData.BG_ALTERAC] = {
        key = BGData.BG_ALTERAC,
        label = "Alterac Valley",
        queue_id = 1,
        map_aliases = {
            "alterac valley",
            "valley of alterac",
            "vallee d'alterac",
            "vallee alterac",
        },
        entries = make_id_set({
            347, 5118, 7410, 7427, 12197, 14942, 16695, 17506,
            19906, 19907, 20119, 20271, 20276, 15103, 15106,
        }),
    },
    [BGData.BG_WARSONG] = {
        key = BGData.BG_WARSONG,
        label = "Warsong Gulch",
        queue_id = 2,
        map_aliases = {
            "warsong gulch",
            "goulet des chanteguerres",
            "goulet chanteguerre",
        },
        entries = make_id_set({
            2302, 2804, 3890, 10360, 14981, 14982, 16696, 17507,
            19908, 19910, 20002, 20118, 20269, 20272, 15102, 15105,
        }),
    },
    [BGData.BG_ARATHI] = {
        key = BGData.BG_ARATHI,
        label = "Arathi Basin",
        queue_id = 3,
        map_aliases = {
            "arathi basin",
            "bassin d'arathi",
            "bassin arathi",
        },
        entries = make_id_set({
            857, 907, 12198, 14990, 14991, 15006, 15007, 15008,
            16694, 16711, 19855, 19905, 20120, 20273, 20274,
        }),
    },
    [BGData.BG_EOTS] = {
        key = BGData.BG_EOTS,
        label = "Eye of the Storm (Cyclone)",
        queue_id = 7,
        map_aliases = {
            "eye of the storm",
            "oeil du cyclone",
            "oeil de la tempete",
            "cyclone",
        },
        entries = make_id_set({
            20362, 20374, 20381, 20382, 20383, 20384,
            20385, 20386, 20388, 20390, 22013, 22015,
        }),
    },
}

BGData.BG_KEY_ORDER = {
    BGData.BG_ALTERAC,
    BGData.BG_WARSONG,
    BGData.BG_ARATHI,
    BGData.BG_EOTS,
}

BGData.BG_QUEUE_ANCHORS = {
    [BGData.CITY_STORMWIND] = {
        [BGData.BG_ALTERAC] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_STORMWIND]),
        [BGData.BG_WARSONG] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_STORMWIND]),
        [BGData.BG_ARATHI] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_STORMWIND]),
        [BGData.BG_EOTS] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_STORMWIND]),
    },
    [BGData.CITY_ORGRIMMAR] = {
        [BGData.BG_ALTERAC] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_ORGRIMMAR]),
        [BGData.BG_WARSONG] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_ORGRIMMAR]),
        [BGData.BG_ARATHI] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_ORGRIMMAR]),
        [BGData.BG_EOTS] = clone_vec3(BGData.CITY_ANCHORS[BGData.CITY_ORGRIMMAR]),
    },
}

BGData.BG_OPTIONS = {
    BGData.BG_DATA[BGData.BG_ALTERAC].label,
    BGData.BG_DATA[BGData.BG_WARSONG].label,
    BGData.BG_DATA[BGData.BG_ARATHI].label,
    BGData.BG_DATA[BGData.BG_EOTS].label,
}

local function string_contains(text, fragment)
    return string.find(text, fragment, 1, true) ~= nil
end

function BGData.detect_bg_key_from_map_name(map_name)
    local lower_name = string.lower(tostring(map_name or ""))
    if lower_name == "" then
        return nil
    end

    for _, bg_key in ipairs(BGData.BG_KEY_ORDER) do
        local bg = BGData.BG_DATA[bg_key]
        local aliases = (bg and bg.map_aliases) or {}
        for _, alias in ipairs(aliases) do
            if string_contains(lower_name, alias) then
                return bg_key
            end
        end
    end

    return nil
end

return BGData
