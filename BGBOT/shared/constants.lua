---@module BGBOT.shared.constants
-- Central constant definitions for BGBOT.
-- WSG map IDs and static positions are HARD M1 GATES (Q-001, Q-007).
-- They MUST be validated in-game before intent logic is written.

local constants = {}

----------------------------------------------------------------------
-- Team/Faction
----------------------------------------------------------------------
constants.FACTION = {
    UNKNOWN  = 0,
    HORDE    = 1,
    ALLIANCE = 2,
}

constants.GROUP_ROLE = {
    NONE    = -1,
    TANK    = 0,
    HEALER  = 1,
    DAMAGER = 2,
}

-- User-facing behavior profile.
-- AUTO defers to group role + class heuristic.
constants.ROLE = {
    AUTO    = 0,
    DPS     = 1,
    HEALER  = 2,
    TANKISH = 3,
}

constants.ROLE_NAME = {
    [constants.ROLE.AUTO]    = "auto",
    [constants.ROLE.DPS]     = "dps",
    [constants.ROLE.HEALER]  = "healer",
    [constants.ROLE.TANKISH] = "tankish",
}

-- WoW class IDs (TBC-era compatible subset used for role heuristics).
constants.CLASS = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER  = 3,
    ROGUE   = 4,
    PRIEST  = 5,
    SHAMAN  = 7,
    MAGE    = 8,
    WARLOCK = 9,
    DRUID   = 11,
}

-- Mapping for game_object:get_faction_id() -> team side.
-- Keep this conservative; scanner also falls back to aura-driven inference.
constants.FACTION_BY_ID = {
    [1] = constants.FACTION.ALLIANCE,
    [2] = constants.FACTION.HORDE,
}

----------------------------------------------------------------------
-- BG Map IDs  (core.get_map_id)
----------------------------------------------------------------------
-- WSG IDs (Q-001 - HARD GATE: confirm in calibration logs)
constants.WSG_MAP_IDS = {
    489,   -- Warsong Gulch (instance map id)
    1460,  -- Private-server/client variant observed from core.get_map_id() in WSG
}

-- UiMap IDs (core.game_ui.get_current_map_id) kept for diagnostics/calibration only.
-- Activation logic must use core.get_map_id() / WSG_MAP_IDS.
constants.WSG_UI_MAP_IDS = {
    947,   -- Warsong Gulch
    1460,  -- Warsong Scramble (client/UI variant seen in Classic clients)
}

constants.AB_MAP_IDS = {
    529,   -- Arathi Basin (instance map id)
}

constants.EOTS_MAP_IDS = {
    566,   -- Eye of the Storm (instance map id)
}

constants.AV_MAP_IDS = {
    30,    -- Alterac Valley (instance map id)
}

-- Ordered registry for BG detection. Scanner checks top-down, first match wins.
-- Each entry: { map_ids = {...}, bg_type = "string" }
constants.BG_MAP_REGISTRY = {
    { map_ids = constants.WSG_MAP_IDS,  bg_type = "wsg" },
    { map_ids = constants.AB_MAP_IDS,   bg_type = "ab" },
    { map_ids = constants.EOTS_MAP_IDS, bg_type = "eots" },
    { map_ids = constants.AV_MAP_IDS,   bg_type = "av" },
}

----------------------------------------------------------------------
-- WSG Trackable Basic Objects (SQL-grounded from tbc-db)
----------------------------------------------------------------------
-- Used for runtime perception of map flags and buff pickups.
-- Key: game_object:get_npc_id()
constants.WSG_OBJECT_IDS = {
    [179830] = { kind = "flag", name = "Silverwing Flag" },
    [179831] = { kind = "flag", name = "Warsong Flag" },
    [179871] = { kind = "buff_speed", name = "Speed Buff" },
    [179905] = { kind = "buff_berserker", name = "Berserk Buff" },   -- strength-style buff
    [179904] = { kind = "buff_restoration", name = "Food Buff" },    -- DB label, functions as restoration pickup
}

----------------------------------------------------------------------
-- Cross-BG Trackable Basic Objects
----------------------------------------------------------------------
-- Unified NPC ID → meta lookup. Scanner uses this when bg_type is known.
-- Contains objects from WSG, AB, EotS, AV.
-- Buff objects share the same NPC IDs across BGs (179871, 179905, 179904).
constants.BG_OBJECT_IDS = {
    -- Shared BG buffs (same objects appear in WSG, AB, EotS, AV)
    [179871] = { kind = "buff_speed",       name = "Speed Buff",       bg = "all" },
    [179905] = { kind = "buff_berserker",    name = "Berserk Buff",     bg = "all" },
    [179904] = { kind = "buff_restoration",  name = "Food Buff",        bg = "all" },
    -- WSG flags
    [179830] = { kind = "flag",  name = "Silverwing Flag",  bg = "wsg" },
    [179831] = { kind = "flag",  name = "Warsong Flag",     bg = "wsg" },
    -- AB banners (Alliance/Horde/Contested visible states)
    [180058] = { kind = "banner_alliance",  name = "Alliance Banner",   bg = "ab" },
    [180060] = { kind = "banner_horde",     name = "Horde Banner",      bg = "ab" },
    [180061] = { kind = "banner_contested", name = "Contested Banner",  bg = "ab" },
    [180059] = { kind = "banner_contested", name = "Contested Banner",  bg = "ab" },
    [180087] = { kind = "banner_named",     name = "Stable Banner",     bg = "ab" },
    [180088] = { kind = "banner_named",     name = "Blacksmith Banner", bg = "ab" },
    [180089] = { kind = "banner_named",     name = "Farm Banner",       bg = "ab" },
    [180090] = { kind = "banner_named",     name = "Lumber Mill Banner",bg = "ab" },
    [180091] = { kind = "banner_named",     name = "Mine Banner",       bg = "ab" },
    -- EotS capture points and Netherstorm Flag
    [184080] = { kind = "cap_point",  name = "BE Tower Cap Pt",       bg = "eots" },
    [184081] = { kind = "cap_point",  name = "FE Tower Cap Pt",       bg = "eots" },
    [184082] = { kind = "cap_point",  name = "Human Tower Cap Pt",    bg = "eots" },
    [184083] = { kind = "cap_point",  name = "Draenei Tower Cap Pt",  bg = "eots" },
    [184141] = { kind = "flag",       name = "Netherstorm Flag",      bg = "eots" },
    [184493] = { kind = "flag",       name = "Netherstorm Flag",      bg = "eots" },
    -- AV banners (Alliance/Horde/Contested)
    [178925] = { kind = "banner_alliance",  name = "Alliance Banner",   bg = "av" },
    [178365] = { kind = "banner_alliance",  name = "Alliance Banner",   bg = "av" },
    [178943] = { kind = "banner_horde",     name = "Horde Banner",      bg = "av" },
    [178364] = { kind = "banner_horde",     name = "Horde Banner",      bg = "av" },
    [178940] = { kind = "banner_contested", name = "Contested Banner",  bg = "av" },
    [179435] = { kind = "banner_contested", name = "Contested Banner",  bg = "av" },
    [179286] = { kind = "banner_contested", name = "Contested Banner",  bg = "av" },
    [179287] = { kind = "banner_contested", name = "Contested Banner",  bg = "av" },
    [179025] = { kind = "banner_horde",     name = "Frostwolf Banner",  bg = "av" },
    [179024] = { kind = "banner_alliance",  name = "Stormpike Banner",  bg = "av" },
    [180418] = { kind = "banner_contested", name = "Snowfall Banner",   bg = "av" },
}

----------------------------------------------------------------------
-- WSG Flag Aura IDs  (A-001 — validate in-game)
----------------------------------------------------------------------
constants.FLAG_AURAS = {
    HORDE_FLAG    = 23333,   -- "Warsong Flag"   (Alliance player carries Horde flag)
    ALLIANCE_FLAG = 23335,   -- "Silverwing Flag" (Horde player carries Alliance flag)
}

----------------------------------------------------------------------
-- BG Phases  (core.game_ui.get_battlefield_state() values)
----------------------------------------------------------------------
constants.BG_PHASE = {
    PREP     = 2,
    ACTION   = 3,
    FINISHED = 5,
}

-- Phase fallback policy for private servers with incomplete battlefield APIs.
constants.BG = {
    UNKNOWN_TO_ACTION_SECS = 30, -- if phase stays unknown this long (without prep aura), assume ACTION
}

----------------------------------------------------------------------
-- BG Preparation Aura Detection
----------------------------------------------------------------------
-- IDs are client/version dependent. Keep name matching enabled as fallback.
constants.BG_PREP_AURA_IDS = {
    44521, -- Preparation (common battleground prep aura in modern clients)
}

constants.BG_PREP_AURA_NAME_MATCH = {
    "preparation",
    "arena preparation",
}

----------------------------------------------------------------------
-- Perception Rings  (distance in yards)
----------------------------------------------------------------------
constants.RING = {
    NEAR_MAX     = 40,
    TACTICAL_MAX = 100,
}

----------------------------------------------------------------------
-- Scan Rates  (ticks between scans)
----------------------------------------------------------------------
constants.SCAN = {
    NEAR_INTERVAL       = 1,    -- every tick
    TACTICAL_INTERVAL   = 5,
    FULL_INTERVAL       = 30,   -- ~1 second
    MAX_ENTITY_PER_TICK = 50,
    MAX_ENTITY_FULL     = 200,
}

----------------------------------------------------------------------
-- Entity Staleness
----------------------------------------------------------------------
constants.ENTITY = {
    STALE_EVICT_SECS    = 10.0,
    STALE_LOW_CONF_SECS = 5.0,
    CONFIDENCE_DECAY    = 0.1,   -- per second
}

----------------------------------------------------------------------
-- Intent Controller
----------------------------------------------------------------------
constants.INTENT = {
    SWITCH_MARGIN     = 0.15,    -- new must be > current * (1 + margin)
    SWITCH_COOLDOWN   = 3.0,     -- seconds after any switch
    POST_DEATH_GRACE  = 0.3,     -- seconds to suppress scoring after respawn
}

constants.MIN_COMMIT = {
    carry_flag         = 8.0,
    escort_carrier     = 6.0,
    intercept_carrier  = 6.0,
    return_flag        = 5.0,
    fight              = 5.0,
    retreat            = 3.0,
    roam               = 4.0,
    follow_herd        = 5.0,
    grab_bg_buff       = 2.0,
    spin_flag          = 1.0,
    failsafe           = 3.0,
}

----------------------------------------------------------------------
-- Navigation Budget  (DEC-008)
----------------------------------------------------------------------
constants.NAV = {
    MAX_INFLIGHT  = 3,
    REPATH_CD     = 2.0,     -- seconds
    STALE_PATH    = 5.0,     -- seconds before path considered stale
    MIN_GOAL_DELTA = 4.0,    -- minimum 2D delta to resend a new goal while moving
}

----------------------------------------------------------------------
-- WSG Tactical Behavior
----------------------------------------------------------------------
constants.WSG = {
    LOCAL_RISK_RADIUS        = 35,   -- yards for ally/enemy local balance checks
    OUTNUMBERED_MARGIN       = 2,    -- enemies >= allies + margin => risky
    ESCORT_RANGE             = 24,   -- preferred distance to own carrier
    BUFF_DETOUR_MAX          = 35,   -- max detour distance for map buffs
    BUFF_ENEMY_ADVANTAGE_MAX = 1,    -- skip buffs if enemies outnumber allies beyond this
    INTERACT_COOLDOWN        = 0.5,  -- seconds between interaction attempts
    -- Flag basic-object NPC IDs by team ownership.
    FLAG_OBJECT_NPC = {
        HORDE    = 179831, -- Warsong Flag
        ALLIANCE = 179830, -- Silverwing Flag
    },
    -- If a flag object is this close to its home room, treat it as "at base" (not dropped).
    FLAG_HOME_RADIUS         = 14,
}

----------------------------------------------------------------------
-- WSG Static Positions  (Q-007 — NON-AUTHORITATIVE, require calibration)
----------------------------------------------------------------------
constants.WSG_POSITIONS = {
    -- Seeded from bg_seed gameobject entries (map 489), still subject to in-game calibration.
    horde_flag_room    = { x = 916.5,  y = 1433.8, z = 346.4 },   -- Warsong Flag (179831)
    alliance_flag_room = { x = 1540.4, y = 1481.3, z = 351.8 },   -- Silverwing Flag (179830)
    horde_graveyard    = { x = 1032.0, y = 1388.0, z = 340.0 },   -- UNCALIBRATED
    alliance_graveyard = { x = 1415.0, y = 1555.0, z = 343.0 },   -- UNCALIBRATED
    midfield           = { x = 1228.5, y = 1457.6, z = 349.1 },   -- midpoint between flag rooms
    horde_tunnel       = { x = 1005.2, y = 1448.0, z = 335.9 },   -- Speed Buff (179871)
    alliance_tunnel    = { x = 1449.9, y = 1470.7, z = 342.6 },   -- Speed Buff (179871)
}

----------------------------------------------------------------------
-- AB Static Positions  (NON-AUTHORITATIVE — from bg_constants.lua)
----------------------------------------------------------------------
constants.AB_POSITIONS = {
    stable     = { x = 1166.79, y = 1200.13, z = -56.71 },
    blacksmith = { x = 977.02,  y = 1046.62, z = -44.81 },
    farm       = { x = 806.18,  y = 874.27,  z = -55.99 },
    lumber     = { x = 856.14,  y = 1148.9,  z = 11.18 },
    mine       = { x = 1146.92, y = 848.18,  z = -110.92 },
    -- Safe roam anchors (approx center of map + GY positions)
    alliance_start = { x = 1285.0, y = 1281.0, z = -15.0 },  -- UNCALIBRATED
    horde_start    = { x = 708.0,  y = 708.0,  z = -17.0 },   -- UNCALIBRATED
    midfield       = { x = 990.0,  y = 1010.0, z = -44.0 },
}

----------------------------------------------------------------------
-- EotS Static Positions  (NON-AUTHORITATIVE — from bg_constants.lua)
----------------------------------------------------------------------
constants.EOTS_POSITIONS = {
    be_tower      = { x = 2050.49, y = 1372.24, z = 1194.56 },
    draenei_tower = { x = 2301.01, y = 1386.93, z = 1197.18 },
    human_tower   = { x = 2282.12, y = 1760.01, z = 1189.71 },
    fe_tower      = { x = 2046.33, y = 1748.81, z = 1190.03 },  -- Fel Reaver / Mage Tower
    mid_flag      = { x = 2174.78, y = 1569.05, z = 1160.36 },
    -- Safe roam anchors
    alliance_start = { x = 2523.0, y = 1596.0, z = 1269.0 },  -- UNCALIBRATED
    horde_start    = { x = 1808.0, y = 1540.0, z = 1267.0 },   -- UNCALIBRATED
    midfield       = { x = 2174.0, y = 1569.0, z = 1160.0 },
}

----------------------------------------------------------------------
-- AV Static Positions  (NON-AUTHORITATIVE — from bg_constants.lua)
----------------------------------------------------------------------
constants.AV_POSITIONS = {
    stormpike_gy   = { x = 63.27,    y = 5.84,     z = -4.10 },  -- Stormpike Banner
    frostwolf_gy   = { x = -1551.88, y = -364.19,  z = 65.59 },  -- Frostwolf Banner
    snowfall_gy    = { x = -202.58,  y = -112.73,  z = 78.49 },  -- Neutral Snowfall
    -- Safe roam anchors
    alliance_start = { x = 873.0,    y = -489.0,   z = 96.5 },   -- UNCALIBRATED
    horde_start    = { x = -1370.0,  y = -219.0,   z = 98.5 },   -- UNCALIBRATED
    midfield       = { x = -202.0,   y = -112.0,   z = 78.5 },   -- near Snowfall GY
}

----------------------------------------------------------------------
-- Per-BG Safe Anchors  (for roam fallback when bg_type is known)
----------------------------------------------------------------------
-- Each entry has "nodes" (if available) and "midfield" as last-resort.
constants.BG_SAFE_ANCHORS = {
    wsg  = {
        constants.WSG_POSITIONS.midfield,
        constants.WSG_POSITIONS.horde_tunnel,
        constants.WSG_POSITIONS.alliance_tunnel,
    },
    ab   = {
        constants.AB_POSITIONS.blacksmith,
        constants.AB_POSITIONS.stable,
        constants.AB_POSITIONS.farm,
        constants.AB_POSITIONS.lumber,
        constants.AB_POSITIONS.mine,
    },
    eots = {
        constants.EOTS_POSITIONS.be_tower,
        constants.EOTS_POSITIONS.fe_tower,
        constants.EOTS_POSITIONS.human_tower,
        constants.EOTS_POSITIONS.draenei_tower,
        constants.EOTS_POSITIONS.mid_flag,
    },
    av   = {
        constants.AV_POSITIONS.snowfall_gy,
        constants.AV_POSITIONS.stormpike_gy,
        constants.AV_POSITIONS.frostwolf_gy,
    },
}

----------------------------------------------------------------------
-- Combat Micro
----------------------------------------------------------------------
constants.COMBAT = {
    TARGET_SCORE_MIN       = 10,
    DEFAULT_CHASE_RANGE    = 30,
    CARRIER_CHASE_RANGE    = 0,
    INTERCEPT_CHASE_RANGE  = 50,
    RETREAT_HEALTH_PCT     = 30,
    CRITICAL_HEALTH_PCT    = 15,
}

----------------------------------------------------------------------
-- Humanization
----------------------------------------------------------------------
constants.HUMAN = {
    REACTION_MIN_MS  = 150,
    REACTION_MAX_MS  = 600,
    HESITATION_MIN   = 0.2,   -- seconds
    HESITATION_MAX   = 0.6,
    MAX_IDLE_SECS    = 2.0,
    EMERGENCY_HP_PCT = 20,
    FLAG_INTERACT_RANGE = 3,
    DEATH_RELEASE_MIN = 2.0,  -- seconds
    DEATH_RELEASE_MAX = 4.0,
}

----------------------------------------------------------------------
-- Nav Stuck Penalty
----------------------------------------------------------------------
constants.NAV_STUCK = {
    PENALTY_MULTIPLIER = 0.5,   -- halve intent score when stuck
    PENALTY_DURATION   = 15.0,  -- seconds before penalty expires
}

return constants
