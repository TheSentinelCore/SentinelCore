---@class MageFrostRotation
local Frost = {}
Frost.__index = Frost

local ActionBuilder = require("rotations/framework/ActionBuilder")
local ConsumableCatalog = require("rotations/framework/ConsumableCatalog")
local SpellCatalog = require("rotations/framework/SpellCatalog")
local AuraCatalog = require("rotations/framework/AuraCatalog")
local RankPolicy = require("rotations/framework/RankPolicy")
local RestPolicy = require("rotations/framework/RestPolicy")

Frost.CLASS_ID = 8
Frost.SPEC = "frost"

local FROST_SPELLS = SpellCatalog.MAGE.FROST
local FROST_AURAS = AuraCatalog.MAGE.FROST

local SPELLS = {
    FROSTBOLT       = FROST_SPELLS.FROSTBOLT,
    FIRE_BLAST      = FROST_SPELLS.FIRE_BLAST,
    ICE_LANCE       = FROST_SPELLS.ICE_LANCE,
    BLIZZARD        = FROST_SPELLS.BLIZZARD,
    CONE_OF_COLD    = FROST_SPELLS.CONE_OF_COLD,
    ARCANE_EXPLOSION = FROST_SPELLS.ARCANE_EXPLOSION,
    FROST_NOVA      = FROST_SPELLS.FROST_NOVA,
    ICE_BARRIER     = FROST_SPELLS.ICE_BARRIER,
    ICE_BLOCK       = FROST_SPELLS.ICE_BLOCK,
    BLINK           = FROST_SPELLS.BLINK,
    MANA_SHIELD     = FROST_SPELLS.MANA_SHIELD,
    COLD_SNAP       = FROST_SPELLS.COLD_SNAP,
    COUNTERSPELL    = FROST_SPELLS.COUNTERSPELL,
    EVOCATION       = FROST_SPELLS.EVOCATION,
    ARCANE_INTELLECT = FROST_SPELLS.ARCANE_INTELLECT,
    FROST_ARMOR     = FROST_SPELLS.FROST_ARMOR,
    ICE_ARMOR       = FROST_SPELLS.ICE_ARMOR,
    CONJURE_WATER   = FROST_SPELLS.CONJURE_WATER,
    CONJURE_FOOD    = FROST_SPELLS.CONJURE_FOOD,
}

local FROSTBOLT_RANGE      = 30.0
local FIRE_BLAST_RANGE     = 20.0
local ICE_LANCE_RANGE      = 30.0
local BLIZZARD_RANGE       = 30.0
local COUNTERSPELL_RANGE   = 30.0
local CONE_OF_COLD_RANGE   = 10.0
local FROST_NOVA_RANGE     = 10.0
local MELEE_RANGE          = 5.5

local DEFAULT_POLICY = {
    drink_mana_pct              = 0.50,
    eat_health_pct              = 0.70,
    rest_until_full             = true,
    rest_resume_health_pct      = 0.95,
    rest_resume_mana_pct        = 0.90,

    ice_barrier_hp_pct          = 0.85,
    mana_shield_hp_pct          = 0.40,
    ice_block_hp_pct            = 0.12,
    cold_snap_hp_pct            = 0.20,
    frost_nova_hp_pct           = 0.50,

    health_potion_hp_pct        = 0.25,
    mana_potion_mana_pct        = 0.15,

    evocation_mana_pct          = 0.10,

    mana_sustain_enter_pct      = 0.40,
    mana_sustain_exit_pct       = 0.55,
    mana_recovery_enter_pct     = 0.15,
    mana_recovery_exit_pct      = 0.25,

    arcane_intellect_refresh_sec = 60.0,
    armor_refresh_sec           = 60.0,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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
        for i = 1, #spell_fallback do
            local id = spell_id(spell_fallback[i])
            if id and is_learned(id) then
                return id
            end
        end
        return spell_id(spell_fallback[#spell_fallback])
    end

    return nil
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
    local mage = type(runtime) == "table" and runtime.mage or nil
    local frost = type(mage) == "table" and mage.frost or nil
    if type(frost) == "table" then
        for k, v in pairs(frost) do
            out[k] = v
        end
    end

    return out
end

---@private
---@param p table
---@return RestPolicyThresholds
local function rest_policy_thresholds(p)
    return RestPolicy.resolve(p, {
        default_eat_start = DEFAULT_POLICY.eat_health_pct,
        default_drink_start = DEFAULT_POLICY.drink_mana_pct,
        default_eat_stop = DEFAULT_POLICY.rest_resume_health_pct,
        default_drink_stop = DEFAULT_POLICY.rest_resume_mana_pct,
        default_rest_until_full = DEFAULT_POLICY.rest_until_full,
    })
end

---@private
---@param ctx table
---@param spec table|string|number
---@return number
local function spell_cooldown_remaining(ctx, spec)
    if type(ctx) ~= "table" or type(ctx.spell_cooldown_remaining) ~= "function" then
        return 0
    end
    local id = resolve_spell(ctx, spec)
    if not id then
        return 0
    end
    local ok_cd, cooldown = pcall(ctx.spell_cooldown_remaining, id)
    if not ok_cd then
        return 0
    end
    return tonumber(cooldown) or 0
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
local function has_armor_buff(ctx)
    return has_any_aura(ctx, FROST_AURAS.ICE_ARMOR)
        or has_any_aura(ctx, FROST_AURAS.FROST_ARMOR)
end

---@private
---@param ctx table
---@return boolean
local function has_intellect_buff(ctx)
    return has_any_aura(ctx, FROST_AURAS.ARCANE_INTELLECT)
end

-- Shorthand aliases
local target_spell = function(spec, priority, opts)
    if type(spec) == "number" or type(spec) == "function" then
        return ActionBuilder.target_spell(spec, priority, opts)
    end

    return ActionBuilder.target_spell(function(ctx)
        return resolve_spell(ctx, spec)
    end, priority, opts)
end

local self_spell = function(spec, priority, opts)
    if type(spec) == "number" or type(spec) == "function" then
        return ActionBuilder.self_spell(spec, priority, opts)
    end

    return ActionBuilder.self_spell(function(ctx)
        return resolve_spell(ctx, spec)
    end, priority, opts)
end

local position_spell = function(spec, priority, opts)
    if type(spec) == "number" or type(spec) == "function" then
        return ActionBuilder.position_spell(spec, priority, opts)
    end

    return ActionBuilder.position_spell(function(ctx)
        return resolve_spell(ctx, spec)
    end, priority, opts)
end

-- ---------------------------------------------------------------------------
-- Identity methods
-- ---------------------------------------------------------------------------

---@return string
function Frost:id()
    return "mage.frost"
end

---@return number
function Frost:class_id()
    return Frost.CLASS_ID
end

---@return number
function Frost:spec_id()
    return 0
end

---@return string
function Frost:spec()
    return Frost.SPEC
end

---@param ctx table
---@return boolean
function Frost:can_run(ctx)
    return (tonumber(ctx and ctx.class_id or 0) or 0) == 8
end

-- ---------------------------------------------------------------------------
-- Mana mode state machine
-- ---------------------------------------------------------------------------

---@private
---@param ctx table
---@param p table
---@return string
function Frost:_resolve_mana_mode(ctx, p)
    local mana_pct = tonumber(ctx and ctx.player_mana_pct) or 1.0
    local mode = tostring(self._mana_mode or "burst")

    local sustain_enter = tonumber(p and p.mana_sustain_enter_pct) or 0.40
    local sustain_exit = tonumber(p and p.mana_sustain_exit_pct) or 0.55
    local recovery_enter = tonumber(p and p.mana_recovery_enter_pct) or 0.15
    local recovery_exit = tonumber(p and p.mana_recovery_exit_pct) or 0.25

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
function Frost:resolve_combat_state(ctx)
    local p = policy(ctx)
    local mana_mode = self:_resolve_mana_mode(ctx, p)
    local target_ttd = tonumber(ctx and ctx.target_ttd_seconds)

    local intents = {
        defensive = 1.0,
        interrupt = 1.0,
        utility = 0.4,
        sustain = 0.8,
        burst = 0.5,
        recover = 0.2,
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
        frost_mana_mode = mana_mode,
        target_ttd_seconds = target_ttd,
        planner_intents = intents,
    }
end

-- ---------------------------------------------------------------------------
-- Maintenance
-- ---------------------------------------------------------------------------

---@param ctx table
---@return boolean
function Frost:should_hold_maintenance(ctx)
    local p = policy(ctx)
    local rest = rest_policy_thresholds(p)
    return RestPolicy.should_hold(ctx, rest)
end

---@param ctx table
---@return table[]
function Frost:precombat(ctx)
    if ctx.player_is_stunned or ctx.player_is_feared then
        return {}
    end

    local actions = {}

    -- Conjure Water (priority 200) — out of combat, mana > 30%
    local water_id = resolve_spell(ctx, SPELLS.CONJURE_WATER)
    if water_id then
        actions[#actions + 1] = self_spell(water_id, 200, {
            min_player_mana_pct = 0.30,
            intent = "sustain",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.in_combat ~= 1
            end,
        })
    end

    -- Conjure Food (priority 195) — out of combat, mana > 30%
    local food_id = resolve_spell(ctx, SPELLS.CONJURE_FOOD)
    if food_id then
        actions[#actions + 1] = self_spell(food_id, 195, {
            min_player_mana_pct = 0.30,
            intent = "sustain",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.in_combat ~= 1
            end,
        })
    end

    return actions
end

---@param ctx table
---@return table[]
function Frost:maintenance(ctx)
    local p = policy(ctx)
    local rest = rest_policy_thresholds(p)

    return {
        -- Arcane Intellect refresh (priority 240, out of combat)
        self_spell(SPELLS.ARCANE_INTELLECT, 240, {
            intent = "utility",
            condition = function(local_ctx)
                if local_ctx.in_combat == true then
                    return false
                end
                if type(local_ctx.player_aura_remaining) == "function" then
                    local remaining = local_ctx.player_aura_remaining(FROST_AURAS.ARCANE_INTELLECT)
                    return remaining < (tonumber(p.arcane_intellect_refresh_sec) or 60.0)
                end
                return not has_intellect_buff(local_ctx)
            end,
        }),

        -- Frost / Ice Armor refresh (priority 235, prefer Ice Armor if learned)
        self_spell(function(local_ctx)
            local ice_armor = resolve_spell(local_ctx, SPELLS.ICE_ARMOR)
            if is_learned(ice_armor) then
                return ice_armor
            end
            return resolve_spell(local_ctx, SPELLS.FROST_ARMOR)
        end, 235, {
            intent = "utility",
            condition = function(local_ctx)
                if local_ctx.in_combat == true then
                    return false
                end
                if type(local_ctx.player_aura_remaining) == "function" then
                    local remaining_ice = local_ctx.player_aura_remaining(FROST_AURAS.ICE_ARMOR)
                    local remaining_frost = local_ctx.player_aura_remaining(FROST_AURAS.FROST_ARMOR)
                    local remaining = math.max(remaining_ice or 0, remaining_frost or 0)
                    return remaining < (tonumber(p.armor_refresh_sec) or 60.0)
                end
                return not has_armor_buff(local_ctx)
            end,
        }),

        -- Eat food (priority 985)
        ActionBuilder.item_self(ConsumableCatalog.TBC_FOOD_ITEM_IDS, 985, {
            max_player_health_pct = rest.eat_stop_pct,
            item_kind = "food",
            rest_lock_secs = 2.0,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.player_is_eating ~= true
                    and RestPolicy.needs_health_rest(local_ctx, rest)
                    and (local_ctx.eating_or_drinking ~= true or local_ctx.player_is_drinking == true)
            end,
        }),

        -- Drink water (priority 984)
        ActionBuilder.item_self(ConsumableCatalog.TBC_WATER_ITEM_IDS, 984, {
            max_player_mana_pct = rest.drink_stop_pct,
            item_kind = "water",
            rest_lock_secs = 2.0,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.player_is_drinking ~= true
                    and RestPolicy.needs_mana_rest(local_ctx, rest)
                    and (local_ctx.eating_or_drinking ~= true or local_ctx.player_is_eating == true)
            end,
        }),
    }
end

-- ---------------------------------------------------------------------------
-- Defensive
-- ---------------------------------------------------------------------------

---@param ctx table
---@return table[]
function Frost:defensive(ctx)
    local p = policy(ctx)

    return {
        -- Ice Block (990) — emergency < 12% HP, in combat (usable while stunned/feared)
        self_spell(SPELLS.ICE_BLOCK, 990, {
            max_player_health_pct = p.ice_block_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),

        -- Cold Snap (985) — < 20% HP, reset frost CDs when Nova or Block on CD
        self_spell(SPELLS.COLD_SNAP, 985, {
            max_player_health_pct = p.cold_snap_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                if local_ctx.in_combat ~= true then
                    return false
                end
                local nova_cd = spell_cooldown_remaining(local_ctx, SPELLS.FROST_NOVA)
                local block_cd = spell_cooldown_remaining(local_ctx, SPELLS.ICE_BLOCK)
                return nova_cd > 0.5 or block_cd > 0.5
            end,
        }),

        -- Ice Barrier (950) — preemptive < 85% HP, not already buffed, off CD
        self_spell(SPELLS.ICE_BARRIER, 950, {
            max_player_health_pct = p.ice_barrier_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return not has_any_aura(local_ctx, FROST_AURAS.ICE_BARRIER)
            end,
        }),

        -- Frost Nova (940) — escape < 50% HP, target in melee range, off CD
        self_spell(SPELLS.FROST_NOVA, 940, {
            max_player_health_pct = p.frost_nova_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                if local_ctx.in_combat ~= true then
                    return false
                end
                local distance = tonumber(local_ctx.target_distance) or 999
                return distance <= FROST_NOVA_RANGE
            end,
        }),

        -- Mana Shield (920) — fallback < 40% HP, >20% mana, no existing shields
        self_spell(SPELLS.MANA_SHIELD, 920, {
            max_player_health_pct = p.mana_shield_hp_pct,
            min_player_mana_pct = 0.20,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                if local_ctx.in_combat ~= true then
                    return false
                end
                return not has_any_aura(local_ctx, FROST_AURAS.MANA_SHIELD)
                    and not has_any_aura(local_ctx, FROST_AURAS.ICE_BARRIER)
            end,
        }),

        -- Health Potion (910)
        ActionBuilder.best_health_potion(910, {
            max_player_health_pct = p.health_potion_hp_pct,
            intent = "defensive",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),

        -- Mana Potion (905)
        ActionBuilder.best_mana_potion(905, {
            max_player_mana_pct = p.mana_potion_mana_pct,
            intent = "recover",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
    }
end

-- ---------------------------------------------------------------------------
-- Interrupt
-- ---------------------------------------------------------------------------

---@param ctx table
---@return table[]
function Frost:interrupt(ctx)
    return {
        -- Counterspell (980) — target must be casting, 30yd range
        target_spell(SPELLS.COUNTERSPELL, 980, {
            target_must_be_casting = true,
            max_target_distance = COUNTERSPELL_RANGE,
            intent = "interrupt",
            condition = function(local_ctx)
                local cs = resolve_spell(local_ctx, SPELLS.COUNTERSPELL)
                if not is_learned(cs) then
                    return false
                end
                if local_ctx.target_is_interruptable == false then
                    return false
                end
                return true
            end,
        }),
    }
end

-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------

---@param ctx table
---@return table[]
function Frost:utility(ctx)
    return {
        -- Evocation (700) — channel 8s, only in recovery mode, max 10% mana, safe distance
        ActionBuilder.channel_spell(function(local_ctx)
            return resolve_spell(local_ctx, SPELLS.EVOCATION)
        end, 700, {
            channel_duration = 8.0,
            max_player_mana_pct = DEFAULT_POLICY.evocation_mana_pct,
            allow_movement = false,
            intent = "recover",
            combat_modes = { "recovery" },
            condition = function(local_ctx)
                if local_ctx.in_combat ~= true then
                    return false
                end
                local distance = tonumber(local_ctx.target_distance) or 999
                return distance > FROST_NOVA_RANGE
            end,
        }),
    }
end

-- ---------------------------------------------------------------------------
-- Single-target combat
-- ---------------------------------------------------------------------------

---@param ctx table
---@return table[]
function Frost:combat(ctx)
    if ctx.player_is_stunned or ctx.player_is_feared then
        return {}
    end

    return {
        -- Ice Lance (555) — instant, only on Fingers of Frost proc or Frostbite on target
        target_spell(SPELLS.ICE_LANCE, 555, {
            max_target_distance = ICE_LANCE_RANGE,
            intent = "burst",
            combat_modes = { "burst", "sustain", "recovery" },
            condition = function(local_ctx)
                -- Fingers of Frost proc on player
                if has_any_aura(local_ctx, FROST_AURAS.FINGERS_OF_FROST) then
                    return true
                end
                -- Frostbite debuff on target
                if type(local_ctx.target_has_aura) == "function" then
                    if local_ctx.target_has_aura(FROST_AURAS.FROSTBITE) == true then
                        return true
                    end
                end
                return false
            end,
        }),

        -- Fire Blast (545) — instant weave, off CD
        target_spell(SPELLS.FIRE_BLAST, 545, {
            max_target_distance = FIRE_BLAST_RANGE,
            intent = "sustain",
            combat_modes = { "burst", "sustain" },
        }),

        -- Frostbolt (540) — primary nuke, all modes
        target_spell(SPELLS.FROSTBOLT, 540, {
            max_target_distance = FROSTBOLT_RANGE,
            allow_movement = false,
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
    }
end

-- ---------------------------------------------------------------------------
-- AoE combat
-- ---------------------------------------------------------------------------

---@param ctx table
---@return table[]
function Frost:aoe(ctx)
    if ctx.player_is_stunned or ctx.player_is_feared then
        return {}
    end

    return {
        -- Cone of Cold (555) — instant, 10yd, off CD, 2+ enemies
        target_spell(SPELLS.CONE_OF_COLD, 555, {
            max_target_distance = CONE_OF_COLD_RANGE,
            intent = { "burst", "sustain" },
            combat_modes = { "burst", "sustain" },
            condition = function(local_ctx)
                local enemies = tonumber(local_ctx.nearby_enemy_count or local_ctx.aoe_target_count) or 0
                return enemies >= 2
            end,
        }),

        -- Blizzard (550) — channeled AoE at pack centroid, 3+ enemies, 25%+ mana
        position_spell(SPELLS.BLIZZARD, 550, {
            allow_movement = false,
            intent = { "burst", "sustain" },
            combat_modes = { "burst", "sustain" },
            min_player_mana_pct = 0.25,
            condition = function(local_ctx)
                local enemies = tonumber(local_ctx.nearby_enemy_count or local_ctx.aoe_target_count or local_ctx.enemy_count) or 0
                if enemies < 3 then return false end
                local cx = tonumber(local_ctx.pack_centroid_x)
                local cy = tonumber(local_ctx.pack_centroid_y)
                local cz = tonumber(local_ctx.pack_centroid_z)
                if not cx or not cy or not cz then return false end
                if cx == 0 and cy == 0 and cz == 0 then return false end
                return true
            end,
            resolve_position = function(local_ctx)
                return {
                    x = tonumber(local_ctx.pack_centroid_x) or 0,
                    y = tonumber(local_ctx.pack_centroid_y) or 0,
                    z = tonumber(local_ctx.pack_centroid_z) or 0,
                }
            end,
        }),

        -- Arcane Explosion (545) — PBAoE, 20%+ mana, melee range, 3+ enemies
        self_spell(SPELLS.ARCANE_EXPLOSION, 545, {
            max_target_distance = MELEE_RANGE,
            min_player_mana_pct = 0.20,
            intent = { "burst", "sustain" },
            combat_modes = { "burst", "sustain" },
            condition = function(local_ctx)
                local enemies = tonumber(local_ctx.nearby_enemy_count or local_ctx.aoe_target_count) or 0
                return enemies >= 3
            end,
        }),

        -- Frostbolt (530) — fallback
        target_spell(SPELLS.FROSTBOLT, 530, {
            max_target_distance = FROSTBOLT_RANGE,
            allow_movement = false,
            intent = "sustain",
            combat_modes = { "burst", "sustain", "recovery" },
        }),
    }
end

-- ---------------------------------------------------------------------------
-- Pull + movement profiles
-- ---------------------------------------------------------------------------

---@param ctx table
---@return table
function Frost:get_pull_profile(ctx)
    -- Frostbolt at 30yd primary pull
    local frostbolt = resolve_spell(ctx, SPELLS.FROSTBOLT)
    if frostbolt then
        return {
            pull_spell_id = frostbolt,
            max_pull_range = FROSTBOLT_RANGE,
            melee_engage_range = MELEE_RANGE,
        }
    end

    -- Fallback: Fire Blast at 20yd
    local fire_blast = resolve_spell(ctx, SPELLS.FIRE_BLAST)
    if fire_blast then
        return {
            pull_spell_id = fire_blast,
            max_pull_range = FIRE_BLAST_RANGE,
            melee_engage_range = MELEE_RANGE,
        }
    end

    -- Fallback: melee engage
    return {
        pull_spell_id = nil,
        max_pull_range = MELEE_RANGE,
        melee_engage_range = MELEE_RANGE,
    }
end

---@param ctx table
---@return table
function Frost:get_movement_profile(ctx)
    return {
        combat_chase_range = FROSTBOLT_RANGE,
    }
end

-- ---------------------------------------------------------------------------
-- Module return
-- ---------------------------------------------------------------------------

return setmetatable({}, Frost)
