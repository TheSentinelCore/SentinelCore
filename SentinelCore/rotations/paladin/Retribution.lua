---@class PaladinRetributionRotation
local Retribution = {}
Retribution.__index = Retribution

local ActionBuilder = require("rotations/framework/ActionBuilder")
local ConsumableCatalog = require("rotations/framework/ConsumableCatalog")
local SpellCatalog = require("rotations/framework/SpellCatalog")
local AuraCatalog = require("rotations/framework/AuraCatalog")
local RankPolicy = require("rotations/framework/RankPolicy")

Retribution.CLASS_ID = 2
Retribution.SPEC = "retribution"

local RET_SPELLS = SpellCatalog.PALADIN.RETRIBUTION
local RET_AURAS = AuraCatalog.PALADIN.RETRIBUTION

local SPELLS = {
    CRUSADER_STRIKE = RET_SPELLS.CRUSADER_STRIKE.ids[1],
    JUDGEMENT = RET_SPELLS.JUDGEMENT.ids[1],
    HAMMER_OF_WRATH = RET_SPELLS.HAMMER_OF_WRATH.ids[1],
    AVENGING_WRATH = RET_SPELLS.AVENGING_WRATH.ids[1],
    HAMMER_OF_JUSTICE = RET_SPELLS.HAMMER_OF_JUSTICE.ids[1],

    SEAL_OF_BLOOD = RET_SPELLS.SEAL_OF_BLOOD,
    SEAL_OF_COMMAND = RET_SPELLS.SEAL_OF_COMMAND,
    SANCTITY_AURA = RET_SPELLS.SANCTITY_AURA,
    CONSECRATION = RET_SPELLS.CONSECRATION,
    EXORCISM = RET_SPELLS.EXORCISM,
    HOLY_WRATH = RET_SPELLS.HOLY_WRATH,
    HOLY_LIGHT = RET_SPELLS.HOLY_LIGHT,
    FLASH_OF_LIGHT = RET_SPELLS.FLASH_OF_LIGHT,

    DIVINE_PROTECTION = RET_SPELLS.DIVINE_PROTECTION.ids[1],
    DIVINE_SHIELD = RET_SPELLS.DIVINE_SHIELD.ids[1],
    LAY_ON_HANDS = RET_SPELLS.LAY_ON_HANDS.ids[1],
}

local MELEE_RANGE = 5.5
local JUDGEMENT_RANGE = 10.0
local JUDGEMENT_CAST_RANGE = 9.0
local EXECUTE_TARGET_HEALTH_PCT = 0.20

local DEFAULT_POLICY = {
    drink_mana_pct = 0.45,
    eat_health_pct = 0.80,

    loh_hp_pct = 0.10,
    divine_shield_hp_pct = 0.20,
    divine_protection_hp_pct = 0.35,

    holy_light_hp_pct = 0.60,
    holy_light_min_mana_pct = 0.22,

    flash_light_hp_pct = 0.45,
    flash_light_very_oom_mana_pct = 0.12,
    heal_low_mana_threshold = 0.22,
    heal_critical_mana_threshold = 0.08,

    health_potion_hp_pct = 0.30,
    mana_potion_mana_pct = 0.15,
    mana_potion_min_hp_pct = 0.35,

    consecration_st_min_mana_pct = 0.35,
    consecration_aoe_min_mana_pct = 0.45,
    exorcism_min_mana_pct = 0.55,
    holy_wrath_aoe_min_mana_pct = 0.30,

    mana_sustain_enter_pct = 0.48,
    mana_sustain_exit_pct = 0.60,
    mana_recovery_enter_pct = 0.24,
    mana_recovery_exit_pct = 0.34,
    holy_light_execute_hold_hp_pct = 0.45,
}

---@private
---@param value any
---@return number|nil
local function spell_id(value)
    local id = tonumber(value)
    if id == nil or id <= 0 then
        return nil
    end
    return id
end

---@private
---@param ctx table
---@param spec table|string|number
---@param fallback? number[]
---@return number|nil
local function resolve_spell(ctx, spec, fallback)
    if type(spec) == "number" then
        return spell_id(spec)
    end

    local spell_name = spec
    local spell_fallback = fallback

    if type(spec) == "table" then
        spell_name = SpellCatalog.name(spec)
        spell_fallback = SpellCatalog.ids(spec)
    end

    if ctx and type(ctx.resolve_spell_id) == "function" and type(spell_name) == "string" and spell_name ~= "" then
        local id = spell_id(ctx.resolve_spell_id(spell_name, spell_fallback))
        if id then
            return id
        end
    end

    if type(spell_fallback) == "table" and #spell_fallback > 0 then
        return spell_id(spell_fallback[1])
    end

    return nil
end

---@private
---@param spell number|nil
---@return boolean
local function is_learned(spell)
    local id = spell_id(spell)
    if not id then
        return false
    end

    if core and core.spell_book and core.spell_book.is_spell_learned then
        local ok, learned = pcall(core.spell_book.is_spell_learned, id)
        if ok and learned == true then
            return true
        end
    end

    if core and core.spell_book and core.spell_book.has_spell then
        local ok, has = pcall(core.spell_book.has_spell, id)
        if ok and has == true then
            return true
        end
    end

    return false
end

---@private
---@param ctx table
---@return table
local function policy(ctx)
    local out = {}
    for k, v in pairs(DEFAULT_POLICY) do
        out[k] = v
    end

    local runtime = type(ctx) == "table" and ctx.routine_policy or nil
    local paladin = type(runtime) == "table" and runtime.paladin or nil
    local retribution = type(paladin) == "table" and paladin.retribution or nil
    if type(retribution) == "table" then
        for k, v in pairs(retribution) do
            out[k] = v
        end
    end

    return out
end

---@private
---@param ctx table
---@return number|nil
local function preferred_seal_id(ctx)
    local blood = resolve_spell(ctx, SPELLS.SEAL_OF_BLOOD)
    if is_learned(blood) then
        return blood
    end

    local command = resolve_spell(ctx, SPELLS.SEAL_OF_COMMAND)
    if is_learned(command) then
        return command
    end

    return command or blood
end

---@private
---@param ctx table
---@param aura_ids number[]
---@return boolean
local function has_any_aura(ctx, aura_ids)
    if type(ctx.player_has_aura) ~= "function" then
        return false
    end

    for i = 1, #aura_ids do
        if ctx.player_has_aura(aura_ids[i]) then
            return true
        end
    end

    return false
end

---@private
---@param ctx table
---@return boolean
local function has_active_seal(ctx)
    return has_any_aura(ctx, RET_AURAS.SEAL_OF_COMMAND) or has_any_aura(ctx, RET_AURAS.SEAL_OF_BLOOD)
end

---@private
---@param ctx table
---@return boolean
local function should_reseal(ctx)
    local seal_id = preferred_seal_id(ctx)
    if not seal_id then
        return false
    end

    if type(ctx.player_has_aura) ~= "function" then
        return true
    end

    local blood = resolve_spell(ctx, SPELLS.SEAL_OF_BLOOD)
    if blood and seal_id == blood then
        return not has_any_aura(ctx, RET_AURAS.SEAL_OF_BLOOD)
    end

    local command = resolve_spell(ctx, SPELLS.SEAL_OF_COMMAND)
    if command and seal_id == command then
        return not has_any_aura(ctx, RET_AURAS.SEAL_OF_COMMAND)
    end

    return ctx.player_has_aura(seal_id) ~= true
end

---@private
---@param ctx table
---@return number|nil
local function current_seal_id(ctx)
    if not has_active_seal(ctx) then
        return nil
    end

    local command = resolve_spell(ctx, SPELLS.SEAL_OF_COMMAND)
    if command and has_any_aura(ctx, RET_AURAS.SEAL_OF_COMMAND) then
        return command
    end

    local blood = resolve_spell(ctx, SPELLS.SEAL_OF_BLOOD)
    if blood and has_any_aura(ctx, RET_AURAS.SEAL_OF_BLOOD) then
        return blood
    end

    return nil
end

---@private
---@param ctx table
---@return number|nil
local function flash_of_light_max_rank(ctx)
    return RankPolicy.select_max_rank(ctx, SpellCatalog.name(SPELLS.FLASH_OF_LIGHT), SpellCatalog.ids(SPELLS.FLASH_OF_LIGHT))
end

---@private
---@param ctx table
---@param p table
---@return boolean
local function should_hold_flash_for_execute(ctx, p)
    local target_health_pct = tonumber(ctx and ctx.target_health_pct)
    if not target_health_pct or target_health_pct > EXECUTE_TARGET_HEALTH_PCT then
        return false
    end

    -- In execute range, preserve mana unless player health is in the critical heal band.
    local player_health_pct = tonumber(ctx and ctx.player_health_pct) or 1.0
    local critical_heal_floor = tonumber(p and p.holy_light_hp_pct) or 0.35
    return player_health_pct > critical_heal_floor
end

---@private
---@param ctx table
---@param p table
---@return boolean
local function should_hold_holy_light_for_execute(ctx, p)
    local target_health_pct = tonumber(ctx and ctx.target_health_pct)
    if not target_health_pct or target_health_pct > EXECUTE_TARGET_HEALTH_PCT then
        return false
    end

    local player_health_pct = tonumber(ctx and ctx.player_health_pct) or 1.0
    local hold_floor = tonumber(p and p.holy_light_execute_hold_hp_pct) or 0.45
    local mana_mode = string.lower(tostring(ctx and (ctx.ret_mana_mode or ctx.mana_mode or ctx.combat_mode or "")))
    if mana_mode == "burst" then
        return false
    end

    return player_health_pct > hold_floor
end

---@private
---@param ctx table
---@return boolean
local function target_is_undead_or_demon(ctx)
    if type(ctx) ~= "table" then
        return false
    end
    if ctx.target_is_undead_or_demon == true then
        return true
    end
    if type(ctx.target_is_creature_type) == "function" then
        return ctx.target_is_creature_type("undead") or ctx.target_is_creature_type("demon")
    end
    return false
end

---@private
---@param spec table|string|number|function
---@param priority number
---@param opts? table
---@return table
local function target_spell(spec, priority, opts)
    if type(spec) == "number" or type(spec) == "function" then
        return ActionBuilder.target_spell(spec, priority, opts)
    end

    return ActionBuilder.target_spell(function(ctx)
        return resolve_spell(ctx, spec)
    end, priority, opts)
end

---@private
---@param spec table|string|number|function
---@param priority number
---@param opts? table
---@return table
local function self_spell(spec, priority, opts)
    if type(spec) == "number" or type(spec) == "function" then
        return ActionBuilder.self_spell(spec, priority, opts)
    end

    return ActionBuilder.self_spell(function(ctx)
        return resolve_spell(ctx, spec)
    end, priority, opts)
end

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
    return 0
end

---@return string
function Retribution:spec()
    return Retribution.SPEC
end

---@private
---@param ctx table
---@param p table
---@return string
function Retribution:_resolve_mana_mode(ctx, p)
    local mana_pct = tonumber(ctx and ctx.player_mana_pct) or 1.0
    local mode = tostring(self._mana_mode or "burst")

    local sustain_enter = tonumber(p and p.mana_sustain_enter_pct) or 0.48
    local sustain_exit = tonumber(p and p.mana_sustain_exit_pct) or 0.60
    local recovery_enter = tonumber(p and p.mana_recovery_enter_pct) or 0.24
    local recovery_exit = tonumber(p and p.mana_recovery_exit_pct) or 0.34

    if mode == "recovery" then
        if mana_pct >= recovery_exit then
            if mana_pct >= sustain_exit then
                mode = "burst"
            else
                mode = "sustain"
            end
        end
    elseif mode == "sustain" then
        if mana_pct <= recovery_enter then
            mode = "recovery"
        elseif mana_pct >= sustain_exit then
            mode = "burst"
        end
    else
        if mana_pct <= recovery_enter then
            mode = "recovery"
        elseif mana_pct <= sustain_enter then
            mode = "sustain"
        else
            mode = "burst"
        end
    end

    self._mana_mode = mode
    return mode
end

---@param ctx table
---@return table
function Retribution:resolve_combat_state(ctx)
    local p = policy(ctx)
    local mana_mode = self:_resolve_mana_mode(ctx, p)
    local target_health_pct = tonumber(ctx and ctx.target_health_pct)
    local execute = target_health_pct ~= nil and target_health_pct <= EXECUTE_TARGET_HEALTH_PCT

    local intents = {
        defensive = 1.0,
        interrupt = 1.0,
        utility = 0.4,
        sustain = 0.8,
        burst = 0.5,
        recover = 0.2,
        execute = execute and 1.0 or 0.0,
    }

    if mana_mode == "burst" then
        intents.burst = 1.0
        intents.sustain = 0.6
        intents.recover = -1.0
    elseif mana_mode == "sustain" then
        intents.burst = 0.2
        intents.sustain = 1.0
        intents.recover = 0.4
    else
        intents.burst = -1.6
        intents.sustain = 0.9
        intents.recover = 1.0
    end

    return {
        combat_mode = mana_mode,
        mana_mode = mana_mode,
        ret_mana_mode = mana_mode,
        in_execute_phase = execute,
        planner_intents = intents,
    }
end

---@param ctx table
---@return boolean
function Retribution:can_run(ctx)
    return (tonumber(ctx.class_id or 0) or 0) == Retribution.CLASS_ID
end

---@param ctx table
---@return table[]
function Retribution:precombat(ctx)
    return {}
end

---@param ctx table
---@return table[]
function Retribution:maintenance(ctx)
    local p = policy(ctx)
    local aura_id = resolve_spell(ctx, SPELLS.SANCTITY_AURA)

    return {
        ActionBuilder.item_self(ConsumableCatalog.TBC_FOOD_ITEM_IDS, 985, {
            max_player_health_pct = p.eat_health_pct,
            item_kind = "food",
            rest_lock_secs = 2.0,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.player_is_eating ~= true
                    and (local_ctx.eating_or_drinking ~= true or local_ctx.player_is_drinking == true)
            end,
        }),
        ActionBuilder.item_self(ConsumableCatalog.TBC_WATER_ITEM_IDS, 980, {
            max_player_mana_pct = p.drink_mana_pct,
            item_kind = "water",
            rest_lock_secs = 2.0,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.player_is_drinking ~= true
                    and (local_ctx.eating_or_drinking ~= true or local_ctx.player_is_eating == true)
            end,
        }),
        self_spell(function()
            return aura_id
        end, 250, {
            condition = function(local_ctx)
                return local_ctx.player_has_aura and local_ctx.player_has_aura(aura_id) ~= true
            end,
        }),
    }
end

---@param ctx table
---@return boolean
function Retribution:should_hold_maintenance(ctx)
    local p = policy(ctx)
    if ctx.in_combat == true then
        return false
    end

    local needs_health = ctx.player_health_pct and ctx.player_health_pct < p.eat_health_pct
    local needs_mana = ctx.player_mana_pct and ctx.player_mana_pct < p.drink_mana_pct
    return needs_health == true or needs_mana == true
end

---@param ctx table
---@return table[]
function Retribution:defensive(ctx)
    local p = policy(ctx)

    local holy_light = function(local_ctx)
        return RankPolicy.select_max_rank(local_ctx, SpellCatalog.name(SPELLS.HOLY_LIGHT), SpellCatalog.ids(SPELLS.HOLY_LIGHT))
    end

    local flash_light = function(local_ctx)
        return flash_of_light_max_rank(local_ctx)
    end

    return {
        self_spell(SPELLS.LAY_ON_HANDS, 1000, {
            max_player_health_pct = p.loh_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
        ActionBuilder.best_health_potion(995, {
            max_player_health_pct = p.health_potion_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        self_spell(SPELLS.DIVINE_SHIELD, 980, {
            max_player_health_pct = p.divine_shield_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
        self_spell(SPELLS.DIVINE_PROTECTION, 965, {
            max_player_health_pct = p.divine_protection_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
        self_spell(holy_light, 945, {
            max_player_health_pct = p.holy_light_hp_pct,
            min_player_mana_pct = p.holy_light_min_mana_pct,
            allow_movement = false,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and not should_hold_holy_light_for_execute(local_ctx, p)
            end,
        }),
        self_spell(flash_light, 935, {
            max_player_health_pct = p.flash_light_hp_pct,
            max_player_mana_pct = p.flash_light_very_oom_mana_pct,
            allow_movement = false,
            intent = "recover",
            combat_modes = { "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and not should_hold_flash_for_execute(local_ctx, p)
            end,
        }),
        ActionBuilder.best_mana_potion(620, {
            max_player_mana_pct = p.mana_potion_mana_pct,
            min_player_health_pct = p.mana_potion_min_hp_pct,
            intent = "recover",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:interrupt(ctx)
    return {
        target_spell(SPELLS.HAMMER_OF_JUSTICE, 760, {
            target_must_be_casting = true,
            max_target_distance = 10.0,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:utility(ctx)
    local aura_id = resolve_spell(ctx, SPELLS.SANCTITY_AURA)
    local seal_id = preferred_seal_id(ctx)

    return {
        self_spell(SPELLS.AVENGING_WRATH, 700, {
            min_player_health_pct = 0.45,
            min_target_health_pct = 0.25,
            max_target_distance = 20.0,
            intent = "burst",
            combat_modes = { "burst" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        self_spell(function()
            return seal_id
        end, 670, {
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true and should_reseal(local_ctx)
            end,
        }),
        self_spell(function()
            return aura_id
        end, 660, {
            intent = "utility",
            condition = function(local_ctx)
                return local_ctx.player_has_aura and local_ctx.player_has_aura(aura_id) ~= true
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:combat(ctx)
    local p = policy(ctx)

    return {
        target_spell(SPELLS.HAMMER_OF_WRATH, 560, {
            max_target_health_pct = 0.20,
            max_target_distance = 30.0,
            intent = { "execute", "sustain" },
            combat_modes = { "burst", "sustain", "recovery" },
        }),
        target_spell(SPELLS.CRUSADER_STRIKE, 555, {
            max_target_distance = MELEE_RANGE,
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
        target_spell(SPELLS.JUDGEMENT, 550, {
            max_target_distance = JUDGEMENT_CAST_RANGE,
            allow_movement = true,
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return has_active_seal(local_ctx)
            end,
        }),
        self_spell(function(local_ctx)
            return preferred_seal_id(local_ctx)
        end, 545, {
            intent = "utility",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return should_reseal(local_ctx)
            end,
        }),
        target_spell(SPELLS.EXORCISM, 500, {
            max_target_distance = 30.0,
            min_player_mana_pct = p.exorcism_min_mana_pct,
            intent = "burst",
            combat_modes = { "burst" },
            condition = function(local_ctx)
                return target_is_undead_or_demon(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Retribution:aoe(ctx)
    local p = policy(ctx)

    return {
        self_spell(SPELLS.CONSECRATION, 580, {
            max_target_distance = 8.0,
            min_player_mana_pct = p.consecration_aoe_min_mana_pct,
            intent = { "burst", "sustain" },
            combat_modes = { "burst", "sustain" },
        }),
        self_spell(SPELLS.HOLY_WRATH, 560, {
            max_target_distance = 10.0,
            min_player_mana_pct = p.holy_wrath_aoe_min_mana_pct,
            intent = { "burst", "sustain" },
            combat_modes = { "burst", "sustain" },
            condition = function(local_ctx)
                return target_is_undead_or_demon(local_ctx)
            end,
        }),
        target_spell(SPELLS.CRUSADER_STRIKE, 555, {
            max_target_distance = MELEE_RANGE,
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
        target_spell(SPELLS.JUDGEMENT, 550, {
            max_target_distance = JUDGEMENT_CAST_RANGE,
            allow_movement = true,
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return has_active_seal(local_ctx)
            end,
        }),
        self_spell(function(local_ctx)
            return preferred_seal_id(local_ctx)
        end, 545, {
            intent = "utility",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return should_reseal(local_ctx)
            end,
        }),
        target_spell(SPELLS.HAMMER_OF_WRATH, 520, {
            max_target_health_pct = 0.20,
            max_target_distance = 30.0,
            intent = { "execute", "sustain" },
            combat_modes = { "burst", "sustain", "recovery" },
        }),
    }
end

---@param ctx table
---@return table
function Retribution:get_pull_profile(ctx)
    local seal = current_seal_id(ctx)
    if not seal then
        return {
            pull_spell_id = nil,
            max_pull_range = MELEE_RANGE,
        }
    end

    return {
        pull_spell_id = SPELLS.JUDGEMENT,
        max_pull_range = JUDGEMENT_CAST_RANGE,
    }
end

---@param ctx table
---@return table
function Retribution:get_movement_profile(ctx)
    return {
        combat_chase_range = MELEE_RANGE,
    }
end

return setmetatable({}, Retribution)
