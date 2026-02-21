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
