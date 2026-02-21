---@class RotationAuraCatalog
local AuraCatalog = {}

AuraCatalog.PALADIN = {
    RETRIBUTION = {
        SEAL_OF_COMMAND = { 27174, 20920, 20919, 20918, 20915, 20375 },
        SEAL_OF_BLOOD = { 31892 },
        SANCTITY_AURA = { 20218 },
    },
}

AuraCatalog.WARLOCK = {
    AFFLICTION = {
        -- Target debuffs
        CORRUPTION = { 27216, 25311, 11672, 11671, 7648, 6223, 6222, 172 },
        CURSE_OF_AGONY = { 27218, 11713, 11712, 11711, 6217, 1014, 980 },
        IMMOLATE = { 27215, 25309, 11668, 11667, 2941, 1094, 707, 348 },
        SIPHON_LIFE = { 27264, 18881, 18880, 18879, 18265 },
        UNSTABLE_AFFLICTION = { 30405, 30404, 30108 },
        SEED_OF_CORRUPTION = { 27243 },

        -- Player buffs
        DEMON_SKIN = { 696, 687 },
        DEMON_ARMOR = { 27260, 11735, 11734, 11733, 1086, 706 },
        FEL_ARMOR = { 28189, 28176 },
        SOUL_LINK = { 19028 },

        -- Procs
        SHADOW_TRANCE = { 17941 },
        BACKLASH = { 34939 },
    },
}

return AuraCatalog
