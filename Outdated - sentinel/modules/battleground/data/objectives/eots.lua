local objectives = {
    {
        id = "FEL_REAVER",
        type = "NODE",
        x = 2057.46,
        y = 1735.07,
        z = 1187.91,
        approach_anchor = { x = 2024.60, y = 1742.82, z = 1195.16 },
        approach_anchor_meta = {
            entry = 184081,
            name = "Fel Reaver Cap Pt",
            source = "db_cap_point",
        },
        team_hint = "UPPER_LEFT",
        owner_map = {
            [184381] = "ALLIANCE",
            [184380] = "HORDE",
            [184382] = "NEUTRAL",
        },
    },
    {
        id = "BLOOD_ELF",
        type = "NODE",
        x = 2047.19,
        y = 1349.19,
        z = 1189.00,
        approach_anchor = { x = 2050.49, y = 1372.24, z = 1194.56 },
        approach_anchor_meta = {
            entry = 184080,
            name = "BE Tower Cap Pt",
            source = "db_cap_point",
        },
        team_hint = "LOWER_LEFT",
        owner_map = {
            [184381] = "ALLIANCE",
            [184380] = "HORDE",
            [184382] = "NEUTRAL",
        },
    },
    {
        id = "DRAENEI_RUINS",
        type = "NODE",
        x = 2276.80,
        y = 1400.41,
        z = 1196.33,
        approach_anchor = { x = 2301.01, y = 1386.93, z = 1197.18 },
        approach_anchor_meta = {
            entry = 184083,
            name = "Draenei Tower Cap Pt",
            source = "db_cap_point",
        },
        team_hint = "LOWER_RIGHT",
        owner_map = {
            [184381] = "ALLIANCE",
            [184380] = "HORDE",
            [184382] = "NEUTRAL",
        },
    },
    {
        id = "MAGE_TOWER",
        type = "NODE",
        x = 2270.84,
        y = 1784.08,
        z = 1186.76,
        approach_anchor = { x = 2282.12, y = 1760.01, z = 1189.71 },
        approach_anchor_meta = {
            entry = 184082,
            name = "Human Tower Cap Pt",
            source = "db_cap_point",
        },
        team_hint = "UPPER_RIGHT",
        owner_map = {
            [184381] = "ALLIANCE",
            [184380] = "HORDE",
            [184382] = "NEUTRAL",
        },
    },
    {
        id = "CENTER_FLAG",
        type = "FLAG",
        x = 2174.78,
        y = 1569.05,
        z = 1160.36,
        team_hint = "CENTER",
        owner_map = {
            [184141] = "NEUTRAL",
            [184493] = "NEUTRAL",
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
        ALLIANCE = { id = "ALLIANCE_RETREAT", type = "ANCHOR", x = 2523.69, y = 1596.60, z = 1269.35 },
        HORDE = { id = "HORDE_RETREAT", type = "ANCHOR", x = 1807.74, y = 1539.42, z = 1267.63 },
    },
}
