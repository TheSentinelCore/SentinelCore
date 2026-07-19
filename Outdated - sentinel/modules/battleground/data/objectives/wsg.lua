local objectives = {
    {
        id = "ALLIANCE_FLAG",
        type = "FLAG",
        x = 1540.42,
        y = 1481.32,
        z = 351.83,
        team_hint = "ALLIANCE_BASE",
        owner_map = {
            [179830] = "ALLIANCE",
        },
    },
    {
        id = "HORDE_FLAG",
        type = "FLAG",
        x = 916.51,
        y = 1433.83,
        z = 346.38,
        team_hint = "HORDE_BASE",
        owner_map = {
            [179831] = "HORDE",
        },
    },
    {
        id = "MID_FIELD",
        type = "MID",
        x = 1228.47,
        y = 1457.58,
        z = 349.10,
        team_hint = "NEUTRAL",
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
        ALLIANCE = { id = "ALLIANCE_RETREAT", type = "ANCHOR", x = 1523.81, y = 1481.76, z = 352.01 },
        HORDE = { id = "HORDE_RETREAT", type = "ANCHOR", x = 933.33, y = 1433.72, z = 345.54 },
    },
}
