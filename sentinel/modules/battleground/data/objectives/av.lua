local objectives = {
    { id = "AID_STATION", type = "GRAVEYARD", x = 638.59, y = -32.42, z = 46.06, team_hint = "ALLIANCE_BASE", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "STORMPIKE_GY", type = "GRAVEYARD", x = 669.01, y = -294.08, z = 30.29, team_hint = "ALLIANCE", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "STONEHEARTH_GY", type = "GRAVEYARD", x = 77.80, y = -404.70, z = 46.75, team_hint = "ALLIANCE", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "SNOWFALL_GY", type = "GRAVEYARD", x = -202.58, y = -112.73, z = 78.49, team_hint = "NEUTRAL", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "ICEBLOOD_GY", type = "GRAVEYARD", x = -611.96, y = -396.17, z = 60.84, team_hint = "HORDE", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "FROSTWOLF_GY", type = "GRAVEYARD", x = -1082.45, y = -346.82, z = 54.92, team_hint = "HORDE", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "FROSTWOLF_HUT", type = "GRAVEYARD", x = -1402.21, y = -307.43, z = 89.44, team_hint = "HORDE_BASE", owner_map = { [178365] = "ALLIANCE", [178364] = "HORDE", [179286] = "CONTESTED", [179287] = "CONTESTED", [180418] = "NEUTRAL" } },
    { id = "STONEHEARTH_BUNKER", type = "TOWER", x = -152.44, y = -441.76, z = 40.40, team_hint = "ALLIANCE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "ICEWING_BUNKER", type = "TOWER", x = 203.28, y = -360.37, z = 56.39, team_hint = "ALLIANCE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "DUN_BALDAR_SOUTH_BUNKER", type = "TOWER", x = 553.78, y = -78.66, z = 51.94, team_hint = "ALLIANCE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "DUN_BALDAR_NORTH_BUNKER", type = "TOWER", x = 674.00, y = -143.12, z = 63.66, team_hint = "ALLIANCE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "ICEBLOOD_TOWER", type = "TOWER", x = -571.88, y = -262.78, z = 75.01, team_hint = "HORDE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "TOWER_POINT", type = "TOWER", x = -768.91, y = -363.71, z = 90.89, team_hint = "HORDE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "FROSTWOLF_EAST_TOWER", type = "TOWER", x = -1302.90, y = -316.98, z = 113.87, team_hint = "HORDE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "FROSTWOLF_WEST_TOWER", type = "TOWER", x = -1297.50, y = -266.77, z = 114.15, team_hint = "HORDE", owner_map = { [178925] = "ALLIANCE", [178943] = "HORDE", [178940] = "CONTESTED" } },
    { id = "DREK", type = "BOSS", x = -1370.88, y = -220.21, z = 98.51, team_hint = "HORDE_BASE" },
    { id = "VANDAR", type = "BOSS", x = 722.43, y = -11.00, z = 50.70, team_hint = "ALLIANCE_BASE" },
    { id = "CAPTAIN_GALVANGAR", type = "CAPTAIN", x = -545.23, y = -165.35, z = 57.01, team_hint = "HORDE" },
    { id = "CAPTAIN_BALINDA", type = "CAPTAIN", x = -57.79, y = -286.60, z = 15.65, team_hint = "ALLIANCE" },
    { id = "ALLIANCE_GATE", type = "GATE", x = 780.49, y = -493.02, z = 99.96, team_hint = "ALLIANCE_BASE" },
    { id = "HORDE_GATE", type = "GATE", x = -1375.19, y = -538.98, z = 55.28, team_hint = "HORDE_BASE" },
}

local by_id = {}
for _, objective in ipairs(objectives) do
    by_id[objective.id] = objective
end

return {
    all = objectives,
    by_id = by_id,
    retreat = {
        ALLIANCE = { id = "ALLIANCE_RETREAT", type = "ANCHOR", x = 873.00, y = -491.28, z = 96.54 },
        HORDE = { id = "HORDE_RETREAT", type = "ANCHOR", x = -1437.67, y = -610.09, z = 51.16 },
    },
    defend = {
        ALLIANCE = "STONEHEARTH_GY",
        HORDE = "ICEBLOOD_GY",
    },
}
