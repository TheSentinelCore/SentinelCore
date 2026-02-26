---@class RotationSpellCatalog
local SpellCatalog = {}

SpellCatalog.PALADIN = {
    RETRIBUTION = {
        CRUSADER_STRIKE = {
            name = "crusader strike",
            ids = { 35395 },
        },
        JUDGEMENT = {
            name = "judgement",
            ids = { 20271 },
        },
        HAMMER_OF_WRATH = {
            name = "hammer of wrath",
            ids = { 24275 },
        },
        AVENGING_WRATH = {
            name = "avenging wrath",
            ids = { 31884 },
        },
        HAMMER_OF_JUSTICE = {
            name = "hammer of justice",
            ids = { 10308, 5589, 5588, 853 },
        },
        REPENTANCE = {
            name = "repentance",
            ids = { 20066 },
        },
        SEAL_OF_BLOOD = {
            name = "seal of blood",
            ids = { 31892 },
        },
        SEAL_OF_COMMAND = {
            name = "seal of command",
            ids = { 27174, 20920, 20919, 20918, 20915, 20375 },
        },
        SANCTITY_AURA = {
            name = "sanctity aura",
            ids = { 20218 },
        },
        CONSECRATION = {
            name = "consecration",
            ids = { 27173, 20924, 20923, 20922, 20116, 26573 },
        },
        EXORCISM = {
            name = "exorcism",
            ids = { 27138, 10314, 10313, 10312, 5615, 5614, 879 },
        },
        HOLY_WRATH = {
            name = "holy wrath",
            ids = { 27139, 10318, 2812 },
        },
        HOLY_LIGHT = {
            name = "holy light",
            ids = { 27136, 25292, 10329, 10328, 3472, 1042, 1026, 647, 639, 635 },
            low_mana_ids = { 3472, 1042 },
        },
        FLASH_OF_LIGHT = {
            name = "flash of light",
            ids = { 27137, 19943, 19942, 19941, 19940, 19939, 19750 },
            low_mana_ids = { 19750 },
        },
        DIVINE_PROTECTION = {
            name = "divine protection",
            ids = { 498 },
        },
        DIVINE_SHIELD = {
            name = "divine shield",
            ids = { 642 },
        },
        LAY_ON_HANDS = {
            name = "lay on hands",
            ids = { 633 },
        },
        BLESSING_OF_MIGHT = {
            name = "blessing of might",
            ids = { 25291, 19838, 19837, 19836, 19835, 19834, 19740 },
        },
        SEAL_OF_VENGEANCE = {
            name = "seal of vengeance",
            ids = { 31801 },
        },
        BLESSING_OF_FREEDOM = {
            name = "blessing of freedom",
            ids = { 1044 },
        },
    },
}

SpellCatalog.WARLOCK = {
    AFFLICTION = {
        -- Damage
        SHADOW_BOLT = {
            name = "shadow bolt",
            ids = { 27209, 25307, 11661, 11660, 11659, 7641, 1106, 1088, 705, 695, 686 },
        },
        CORRUPTION = {
            name = "corruption",
            ids = { 27216, 25311, 11672, 11671, 7648, 6223, 6222, 172 },
        },
        CURSE_OF_AGONY = {
            name = "curse of agony",
            ids = { 27218, 11713, 11712, 11711, 6217, 1014, 980 },
        },
        CURSE_OF_THE_ELEMENTS = {
            name = "curse of the elements",
            ids = { 27228, 11722, 11721, 1490 },
        },
        CURSE_OF_TONGUES = {
            name = "curse of tongues",
            ids = { 11719, 1714 },
        },
        CURSE_OF_DOOM = {
            name = "curse of doom",
            ids = { 30910, 603 },
        },
        CURSE_OF_RECKLESSNESS = {
            name = "curse of recklessness",
            ids = { 27226, 11717, 7659, 7658, 704 },
        },
        CURSE_OF_WEAKNESS = {
            name = "curse of weakness",
            ids = { 30909, 27224, 11708, 11707, 7646, 6205, 1108, 702 },
        },
        AMPLIFY_CURSE = {
            name = "amplify curse",
            ids = { 18288 },
        },
        IMMOLATE = {
            name = "immolate",
            ids = { 27215, 25309, 11668, 11667, 2941, 1094, 707, 348 },
        },
        SIPHON_LIFE = {
            name = "siphon life",
            ids = { 27264, 18881, 18880, 18879, 18265 },
        },
        UNSTABLE_AFFLICTION = {
            name = "unstable affliction",
            ids = { 30405, 30404, 30108 },
        },
        DRAIN_LIFE = {
            name = "drain life",
            ids = { 27220, 27219, 11700, 11699, 7651, 709, 699, 689 },
        },
        DRAIN_SOUL = {
            name = "drain soul",
            ids = { 27217, 11675, 8289, 8288, 1120 },
        },
        SEED_OF_CORRUPTION = {
            name = "seed of corruption",
            ids = { 27243 },
        },
        RAIN_OF_FIRE = {
            name = "rain of fire",
            ids = { 27212, 11678, 11677, 6219, 5740 },
        },
        INCINERATE = {
            name = "incinerate",
            ids = { 32231, 29722 },
        },
        SEARING_PAIN = {
            name = "searing pain",
            ids = { 27210, 17923, 17922, 17921, 17920, 17919, 5676 },
        },

        -- Defensive / Utility
        DEATH_COIL = {
            name = "death coil",
            ids = { 27223, 17926, 17925, 6789 },
        },
        FEAR = {
            name = "fear",
            ids = { 6215, 6213, 5782 },
        },
        HOWL_OF_TERROR = {
            name = "howl of terror",
            ids = { 17928, 5484 },
        },
        LIFE_TAP = {
            name = "life tap",
            ids = { 27222, 11689, 11688, 11687, 1456, 1455, 1454 },
            low_mana_ids = { 1454 },
        },
        DARK_PACT = {
            name = "dark pact",
            ids = { 27265, 18938, 18937, 18220 },
        },
        HEALTH_FUNNEL = {
            name = "health funnel",
            ids = { 27259, 11695, 11694, 11693, 3700, 3699, 3698, 755 },
        },
        SPELL_LOCK = {
            name = "spell lock",
            ids = { 19647, 19244 },
        },
        SOUL_LINK = {
            name = "soul link",
            ids = { 19028 },
        },
        FEL_DOMINATION = {
            name = "fel domination",
            ids = { 18708 },
        },

        -- Armor Buffs
        DEMON_SKIN = {
            name = "demon skin",
            ids = { 696, 687 },
        },
        DEMON_ARMOR = {
            name = "demon armor",
            ids = { 27260, 11735, 11734, 11733, 1086, 706 },
        },
        FEL_ARMOR = {
            name = "fel armor",
            ids = { 28189, 28176 },
        },

        -- Pet Summons
        SUMMON_IMP = {
            name = "summon imp",
            ids = { 688 },
        },
        SUMMON_VOIDWALKER = {
            name = "summon voidwalker",
            ids = { 697 },
        },
        SUMMON_SUCCUBUS = {
            name = "summon succubus",
            ids = { 712 },
        },
        SUMMON_FELHUNTER = {
            name = "summon felhunter",
            ids = { 691 },
        },
        SUMMON_FELGUARD = {
            name = "summon felguard",
            ids = { 30146 },
        },

        -- Misc
        CREATE_HEALTHSTONE = {
            name = "create healthstone",
            ids = { 27230, 11730, 11729, 5699, 6202, 6201 },
        },
        CREATE_SOULSTONE = {
            name = "create soulstone",
            ids = { 27238, 20757, 20756, 20755, 20752, 693 },
        },
        SHADOW_WARD = {
            name = "shadow ward",
            ids = { 28610, 11740, 11739, 6229 },
        },
        SHOOT = {
            name = "shoot",
            ids = { 5019 },
        },
    },
}

SpellCatalog.MAGE = {
    FROST = {
        -- Primary nukes
        FROSTBOLT = {
            name = "frostbolt",
            ids = { 27072, 25304, 12506, 12505, 10181, 10180, 10179, 8408, 8407, 7322, 837, 205, 116 },
        },
        FIRE_BLAST = {
            name = "fire blast",
            ids = { 27079, 10199, 10197, 8413, 8412, 2138, 2136, 1953 },
        },
        ICE_LANCE = {
            name = "ice lance",
            ids = { 30455 },
        },

        -- AoE
        BLIZZARD = {
            name = "blizzard",
            ids = { 27085, 10187, 10186, 10185, 6141, 10 },
        },
        CONE_OF_COLD = {
            name = "cone of cold",
            ids = { 27087, 10161, 10160, 10159, 8492, 120 },
        },
        ARCANE_EXPLOSION = {
            name = "arcane explosion",
            ids = { 27082, 10202, 10201, 8437, 8439, 1449 },
        },

        -- Defensive / Control
        FROST_NOVA = {
            name = "frost nova",
            ids = { 27088, 10230, 6131, 122 },
        },
        ICE_BARRIER = {
            name = "ice barrier",
            ids = { 33405, 13033, 13032, 13031, 11426 },
        },
        ICE_BLOCK = {
            name = "ice block",
            ids = { 45438, 27619 },
        },
        BLINK = {
            name = "blink",
            ids = { 1953 },
        },
        MANA_SHIELD = {
            name = "mana shield",
            ids = { 27131, 10193, 10192, 10191, 8494, 1463 },
        },
        COLD_SNAP = {
            name = "cold snap",
            ids = { 11958 },
        },
        COUNTERSPELL = {
            name = "counterspell",
            ids = { 2139 },
        },

        -- Utility / Buffs
        EVOCATION = {
            name = "evocation",
            ids = { 12051 },
        },
        ARCANE_INTELLECT = {
            name = "arcane intellect",
            ids = { 27126, 10157, 10156, 1461, 1459, 1008 },
        },
        FROST_ARMOR = {
            name = "frost armor",
            ids = { 7301, 7300, 168 },
        },
        ICE_ARMOR = {
            name = "ice armor",
            ids = { 27124, 10220, 10219, 7320 },
        },
        CONJURE_WATER = {
            name = "conjure water",
            ids = { 27090, 10140, 10139, 10138, 6127, 5506, 5505, 5504 },
        },
        CONJURE_FOOD = {
            name = "conjure food",
            ids = { 33717, 28612, 10145, 10144, 6129, 990, 597, 587 },
        },
    },
}

---@param spec table
---@return string|nil
function SpellCatalog.name(spec)
    return spec and spec.name or nil
end

---@param spec table
---@return number[]|nil
function SpellCatalog.ids(spec)
    return spec and spec.ids or nil
end

---@param spec table
---@return number[]|nil
function SpellCatalog.low_mana_ids(spec)
    return spec and spec.low_mana_ids or nil
end

return SpellCatalog
