local MapIds = require("shared/map_ids")

local Catalog = {
    AV = {
        key = "AV",
        map_id = MapIds.ALTERAC_VALLEY,
        battleground_id = 1,
        name = "Alterac Valley",
        aliases = { "alterac valley" },
        anchors = {
            ALLIANCE = { x = 873.00, y = -491.28, z = 96.54 },
            HORDE = { x = -1437.67, y = -610.09, z = 51.16 },
        },
    },
    WSG = {
        key = "WSG",
        map_id = MapIds.WARSONG_GULCH,
        battleground_id = 2,
        name = "Warsong Gulch",
        aliases = { "warsong gulch" },
        anchors = {
            ALLIANCE = { x = 1523.81, y = 1481.76, z = 352.01 },
            HORDE = { x = 933.33, y = 1433.72, z = 345.54 },
        },
    },
    AB = {
        key = "AB",
        map_id = MapIds.ARATHI_BASIN,
        battleground_id = 3,
        name = "Arathi Basin",
        aliases = { "arathi basin" },
        anchors = {
            ALLIANCE = { x = 1313.90, y = 1310.74, z = -9.01 },
            HORDE = { x = 684.01, y = 681.22, z = -12.92 },
        },
    },
    EOTS = {
        key = "EOTS",
        map_id = MapIds.EYE_OF_THE_STORM,
        battleground_id = 7,
        name = "Eye of the Storm",
        aliases = { "eye of the storm" },
        anchors = {
            ALLIANCE = { x = 2523.69, y = 1596.60, z = 1269.35 },
            HORDE = { x = 1807.74, y = 1539.42, z = 1267.63 },
        },
    },
}

return Catalog
