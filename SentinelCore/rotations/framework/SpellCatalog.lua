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
            ids = { 853 },
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
            ids = { 27138, 10314, 10313, 5615, 879 },
        },
        HOLY_WRATH = {
            name = "holy wrath",
            ids = { 27139, 10318, 5588, 5589, 2812 },
        },
        HOLY_LIGHT = {
            name = "holy light",
            ids = { 27136, 25292, 10329, 10328, 3472, 1042, 1026, 647, 639, 635 },
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
        SHOOT = {
            name = "shoot",
            ids = { 5019 },
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
