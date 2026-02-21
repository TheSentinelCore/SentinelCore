---@class PaladinRetributionRotation
local Retribution = {}
Retribution.__index = Retribution
local ActionBuilder = require("rotations/framework/ActionBuilder")

Retribution.CLASS_ID = 2
Retribution.SPEC = "retribution"

local SPELLS = {
    -- Core TBC Retribution toolkit
    CRUSADER_STRIKE = 35395,
    JUDGEMENT = 20271,
    CONSECRATION = 26573,
    EXORCISM = 879,
    HAMMER_OF_WRATH = 24275,
    AVENGING_WRATH = 31884,
    HOLY_WRATH = 2812,
    HAMMER_OF_JUSTICE = 853,

    -- Maintenance
    SANCTITY_AURA = 20218,
    SEAL_OF_BLOOD = 31892,
    SEAL_OF_COMMAND = 20375,

    -- Survival
    FLASH_OF_LIGHT = 19750,
    DIVINE_PROTECTION = 498,
    DIVINE_SHIELD = 642,
    LAY_ON_HANDS = 633,
}

local MELEE_RANGE = 5.5

---@return string
function Retribution:id()
    return "paladin.retribution"
end

---@return number
function Retribution:class_id()
    return Retribution.CLASS_ID
end

---@return number
function Retribution:spec_id()
    -- TBC builds often expose no reliable per-tree spec id in runtime.
    return 0
end

---@return string
function Retribution:spec()
    return Retribution.SPEC
end

---@param ctx table
---@return boolean
function Retribution:can_run(ctx)
    return (tonumber(ctx.class_id or 0) or 0) == Retribution.CLASS_ID
end

---@param spell_id number
---@param priority number
---@param opts? table
---@return table
local function target_spell(spell_id, priority, opts)
    return ActionBuilder.target_spell(spell_id, priority, opts)
end

---@param spell_id number
---@param priority number
---@param opts? table
---@return table
local function self_spell(spell_id, priority, opts)
    return ActionBuilder.self_spell(spell_id, priority, opts)
end

---@param ctx table
---@return table[]
function Retribution:precombat(ctx)
    return {}
end

---@param ctx table
---@return table[]
function Retribution:defensive(ctx)
    return {
        self_spell(SPELLS.LAY_ON_HANDS, 1000, {
            max_player_health_pct = 0.10,
        }),
        self_spell(SPELLS.DIVINE_SHIELD, 980, {
            max_player_health_pct = 0.20,
        }),
        self_spell(SPELLS.DIVINE_PROTECTION, 960, {
            max_player_health_pct = 0.35,
        }),
        self_spell(SPELLS.FLASH_OF_LIGHT, 920, {
            max_player_health_pct = 0.45,
            min_player_mana_pct = 0.25,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:interrupt(ctx)
    return {
        target_spell(SPELLS.HAMMER_OF_JUSTICE, 700, {
            target_must_be_casting = true,
            max_target_distance = 10.0,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:utility(ctx)
    return {
        self_spell(SPELLS.AVENGING_WRATH, 520, {
            min_player_health_pct = 0.40,
            min_target_health_pct = 0.25,
            max_target_distance = 20.0,
        }),
        self_spell(SPELLS.SEAL_OF_BLOOD, 140),
        self_spell(SPELLS.SEAL_OF_COMMAND, 130),
        self_spell(SPELLS.SANCTITY_AURA, 120),
    }
end

---@param ctx table
---@return table[]
function Retribution:combat(ctx)
    return {
        target_spell(SPELLS.HAMMER_OF_WRATH, 470, {
            max_target_health_pct = 0.20,
            max_target_distance = 30.0,
        }),
        target_spell(SPELLS.CRUSADER_STRIKE, 460, {
            max_target_distance = MELEE_RANGE,
        }),
        target_spell(SPELLS.JUDGEMENT, 450, {
            max_target_distance = 10.0,
        }),
        self_spell(SPELLS.CONSECRATION, 430, {
            max_target_distance = 8.0,
            min_player_mana_pct = 0.35,
        }),
        target_spell(SPELLS.EXORCISM, 410, {
            max_target_distance = 30.0,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:aoe(ctx)
    return {
        self_spell(SPELLS.CONSECRATION, 500, {
            max_target_distance = 8.0,
            min_player_mana_pct = 0.45,
        }),
        self_spell(SPELLS.HOLY_WRATH, 470, {
            max_target_distance = 10.0,
            min_player_mana_pct = 0.30,
        }),
        target_spell(SPELLS.HAMMER_OF_WRATH, 460, {
            max_target_health_pct = 0.20,
            max_target_distance = 30.0,
        }),
        target_spell(SPELLS.CRUSADER_STRIKE, 450, {
            max_target_distance = MELEE_RANGE,
        }),
        target_spell(SPELLS.JUDGEMENT, 440, {
            max_target_distance = 10.0,
        }),
    }
end

---@param ctx table
---@return table
function Retribution:get_pull_profile(ctx)
    return {
        pull_spell_id = SPELLS.JUDGEMENT,
        max_pull_range = 30,
    }
end

return setmetatable({}, Retribution)
