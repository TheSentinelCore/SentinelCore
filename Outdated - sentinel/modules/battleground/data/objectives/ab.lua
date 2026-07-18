local objectives = {
    {
        id = "STABLES",
        type = "NODE",
        x = 1166.79,
        y = 1200.13,
        z = -56.71,
        team_hint = "ALLIANCE_SIDE",
        owner_map = {
            [180087] = "NEUTRAL",
            [180058] = "ALLIANCE",
            [180060] = "HORDE",
            [180059] = "CONTESTED",
            [180061] = "CONTESTED",
        },
    },
    {
        id = "BLACKSMITH",
        type = "NODE",
        x = 977.02,
        y = 1046.62,
        z = -44.81,
        team_hint = "CENTER",
        owner_map = {
            [180088] = "NEUTRAL",
            [180058] = "ALLIANCE",
            [180060] = "HORDE",
            [180059] = "CONTESTED",
            [180061] = "CONTESTED",
        },
    },
    {
        id = "FARM",
        type = "NODE",
        x = 806.18,
        y = 874.27,
        z = -55.99,
        team_hint = "HORDE_SIDE",
        owner_map = {
            [180089] = "NEUTRAL",
            [180058] = "ALLIANCE",
            [180060] = "HORDE",
            [180059] = "CONTESTED",
            [180061] = "CONTESTED",
        },
    },
    {
        id = "LUMBER_MILL",
        type = "NODE",
        x = 856.14,
        y = 1148.90,
        z = 11.18,
        team_hint = "UPPER",
        owner_map = {
            [180090] = "NEUTRAL",
            [180058] = "ALLIANCE",
            [180060] = "HORDE",
            [180059] = "CONTESTED",
            [180061] = "CONTESTED",
        },
    },
    {
        id = "GOLD_MINE",
        type = "NODE",
        x = 1146.92,
        y = 848.18,
        z = -110.92,
        team_hint = "LOWER",
        owner_map = {
            [180091] = "NEUTRAL",
            [180058] = "ALLIANCE",
            [180060] = "HORDE",
            [180059] = "CONTESTED",
            [180061] = "CONTESTED",
        },
    },
}

local by_id = {}
for _, objective in ipairs(objectives) do
    by_id[objective.id] = objective
end

return {
    all = objectives,
    by_id = by_id,
    retreat = {
        ALLIANCE = { id = "ALLIANCE_RETREAT", type = "ANCHOR", x = 1313.90, y = 1310.74, z = -9.01 },
        HORDE = { id = "HORDE_RETREAT", type = "ANCHOR", x = 684.01, y = 681.22, z = -12.92 },
    },
}
