---@class RotationAuraCatalog
local AuraCatalog = {}

AuraCatalog.PALADIN = {
    RETRIBUTION = {
        SEAL_OF_COMMAND = { 27174, 20920, 20919, 20918, 20915, 20375 },
        SEAL_OF_BLOOD = { 31892 },
        SANCTITY_AURA = { 20218 },
        BLESSING_OF_MIGHT = { 25291, 19838, 19837, 19836, 19835, 19834, 19740 },
        SEAL_OF_VENGEANCE = { 31801 },
        BLESSING_OF_FREEDOM = { 1044 },
        VENGEANCE_PROC = { 20059 },
    },
}

AuraCatalog.WARLOCK = {
    AFFLICTION = {
        -- Target debuffs
        CORRUPTION = { 27216, 25311, 11672, 11671, 7648, 6223, 6222, 172 },
        CURSE_OF_AGONY = { 27218, 11713, 11712, 11711, 6217, 1014, 980 },
        CURSE_OF_THE_ELEMENTS = { 27228, 11722, 11721, 1490 },
        CURSE_OF_TONGUES = { 11719, 1714 },
        CURSE_OF_DOOM = { 30910, 603 },
        CURSE_OF_RECKLESSNESS = { 27226, 11717, 7659, 7658, 704 },
        CURSE_OF_WEAKNESS = { 30909, 27224, 11708, 11707, 7646, 6205, 1108, 702 },
        AMPLIFY_CURSE = { 18288 },
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

AuraCatalog.MAGE = {
    FROST = {
        -- Player buffs
        FROST_ARMOR = { 7301, 7300, 168 },
        ICE_ARMOR = { 27124, 10220, 10219, 7320 },
        ARCANE_INTELLECT = { 27126, 10157, 10156, 1461, 1459, 1008 },
        ICE_BARRIER = { 33405, 13033, 13032, 13031, 11426 },
        MANA_SHIELD = { 27131, 10193, 10192, 10191, 8494, 1463 },

        -- Procs
        FINGERS_OF_FROST = { 44544 },

        -- Target debuffs
        FROSTBITE = { 12494, 12496, 12497 },
        WINTERS_CHILL = { 12579 },
    },
}

return AuraCatalog
