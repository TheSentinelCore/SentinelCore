---@class WarlockAfflictionRotation
local Affliction = {}
Affliction.__index = Affliction

local ActionBuilder = require("rotations/framework/ActionBuilder")
local ConsumableCatalog = require("rotations/framework/ConsumableCatalog")
local SpellCatalog = require("rotations/framework/SpellCatalog")
local AuraCatalog = require("rotations/framework/AuraCatalog")
local RankPolicy = require("rotations/framework/RankPolicy")

Affliction.CLASS_ID = 9
Affliction.SPEC = "affliction"

local WL_SPELLS = SpellCatalog.WARLOCK.AFFLICTION
local WL_AURAS = AuraCatalog.WARLOCK.AFFLICTION

local SPELLS = {
    SHADOW_BOLT = WL_SPELLS.SHADOW_BOLT,
    CORRUPTION = WL_SPELLS.CORRUPTION,
    CURSE_OF_AGONY = WL_SPELLS.CURSE_OF_AGONY,
    IMMOLATE = WL_SPELLS.IMMOLATE,
    SIPHON_LIFE = WL_SPELLS.SIPHON_LIFE,
    UNSTABLE_AFFLICTION = WL_SPELLS.UNSTABLE_AFFLICTION,
    DRAIN_LIFE = WL_SPELLS.DRAIN_LIFE,
    DRAIN_SOUL = WL_SPELLS.DRAIN_SOUL,
    SEED_OF_CORRUPTION = WL_SPELLS.SEED_OF_CORRUPTION,
    RAIN_OF_FIRE = WL_SPELLS.RAIN_OF_FIRE,
    INCINERATE = WL_SPELLS.INCINERATE,
    SEARING_PAIN = WL_SPELLS.SEARING_PAIN,

    DEATH_COIL = WL_SPELLS.DEATH_COIL,
    FEAR = WL_SPELLS.FEAR,
    HOWL_OF_TERROR = WL_SPELLS.HOWL_OF_TERROR,
    LIFE_TAP = WL_SPELLS.LIFE_TAP,
    DARK_PACT = WL_SPELLS.DARK_PACT,
    HEALTH_FUNNEL = WL_SPELLS.HEALTH_FUNNEL,

    DEMON_SKIN = WL_SPELLS.DEMON_SKIN,
    DEMON_ARMOR = WL_SPELLS.DEMON_ARMOR,
    FEL_ARMOR = WL_SPELLS.FEL_ARMOR,

    SUMMON_IMP = WL_SPELLS.SUMMON_IMP,
    SUMMON_VOIDWALKER = WL_SPELLS.SUMMON_VOIDWALKER,
    SUMMON_SUCCUBUS = WL_SPELLS.SUMMON_SUCCUBUS,
    SUMMON_FELHUNTER = WL_SPELLS.SUMMON_FELHUNTER,
    SUMMON_FELGUARD = WL_SPELLS.SUMMON_FELGUARD,

    CREATE_HEALTHSTONE = WL_SPELLS.CREATE_HEALTHSTONE,
    SHOOT = WL_SPELLS.SHOOT,
}

local SHARD_ITEM_ID = 6265

local DEFAULT_POLICY = {
    drink_mana_pct = 0.40,
    eat_health_pct = 0.65,
    life_tap_min_health_pct = 0.50,
    life_tap_max_mana_pct = 0.60,
    life_tap_ooc_max_mana_pct = 0.85,
    death_coil_hp_pct = 0.25,
    drain_life_hp_pct = 0.45,
    health_funnel_pet_hp_pct = 0.30,
    health_potion_hp_pct = 0.25,
    mana_potion_mana_pct = 0.15,
    mana_potion_min_hp_pct = 0.35,
    wand_mana_pct = 0.08,
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
---@return table
local function runtime_cache(ctx)
    if type(ctx) ~= "table" then
        return {}
    end

    local cache = rawget(ctx, "_warlock_affliction_cache")
    if type(cache) ~= "table" then
        cache = {}
        ctx._warlock_affliction_cache = cache
    end

    return cache
end

---@private
---@param raw any
---@return boolean
local function learned_spell(raw)
    local id = spell_id(raw)
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
        local id = spell_id(spec)
        if learned_spell(id) then
            return id
        end
        return nil
    end

    local spell_name = spec
    local spell_fallback = fallback
    if type(spec) == "table" then
        spell_name = SpellCatalog.name(spec)
        spell_fallback = SpellCatalog.ids(spec)
    end

    local cache = runtime_cache(ctx)
    local key = tostring(spell_name or "") .. "#" .. tostring(type(spell_fallback) == "table" and spell_fallback[1] or 0)
    local cached = cache[key]
    if cached ~= nil then
        return cached or nil
    end

    local resolved = nil
    if ctx and type(ctx.resolve_spell_id) == "function" and type(spell_name) == "string" and spell_name ~= "" then
        local id = spell_id(ctx.resolve_spell_id(spell_name, spell_fallback))
        if id and learned_spell(id) then
            resolved = id
        end
    end

    if resolved == nil and type(spell_fallback) == "table" and #spell_fallback > 0 then
        for i = 1, #spell_fallback do
            local id = spell_id(spell_fallback[i])
            if id and learned_spell(id) then
                resolved = id
                break
            end
        end
    end

    cache[key] = resolved or false
    return resolved
end

---@private
---@param a any
---@param b? any
---@return boolean
local function is_learned(a, b)
    if b ~= nil then
        return resolve_spell(a, b) ~= nil
    end
    return learned_spell(a)
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
    local warlock = type(runtime) == "table" and runtime.warlock or nil
    local affliction = type(warlock) == "table" and warlock.affliction or nil
    if type(affliction) == "table" then
        for k, v in pairs(affliction) do
            out[k] = v
        end
    end

    return out
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
---@param aura_ids number[]
---@return boolean
local function target_has_any_aura(ctx, aura_ids)
    if type(ctx.target_has_aura) ~= "function" then
        return false
    end

    for i = 1, #aura_ids do
        if ctx.target_has_aura(aura_ids[i]) then
            return true
        end
    end

    return false
end

---@private
---@param ctx table
---@return boolean
local function has_armor_buff(ctx)
    return has_any_aura(ctx, WL_AURAS.FEL_ARMOR)
        or has_any_aura(ctx, WL_AURAS.DEMON_ARMOR)
        or has_any_aura(ctx, WL_AURAS.DEMON_SKIN)
end

---@private
---@param ctx table
---@return number|nil
local function best_armor_spell(ctx)
    local fel = resolve_spell(ctx, SPELLS.FEL_ARMOR)
    if is_learned(fel) then
        return fel
    end

    local demon = resolve_spell(ctx, SPELLS.DEMON_ARMOR)
    if is_learned(demon) then
        return demon
    end

    local skin = resolve_spell(ctx, SPELLS.DEMON_SKIN)
    if is_learned(skin) then
        return skin
    end

    return nil
end

---@private
---@param row any
---@return any
local function unwrap_item_object(row)
    if type(row) ~= "table" then
        return nil
    end
    return row.item or row.object or row.raw_object or row.game_object
end

---@private
---@param row any
---@return number
local function stack_count(row)
    if type(row) == "table" then
        local c = tonumber(row.count or row.stack_count or row.stack)
        if c and c > 0 then
            return c
        end
    end

    local item = unwrap_item_object(row)
    if item and item.get_item_stack_count then
        local ok, c = pcall(item.get_item_stack_count, item)
        if ok and tonumber(c) and tonumber(c) > 0 then
            return tonumber(c)
        end
    end

    return 1
end

---@private
---@param row any
---@return number
local function item_id_from_row(row)
    if type(row) ~= "table" then
        return 0
    end

    local direct = tonumber(row.item_id) or 0
    if direct > 0 then
        return direct
    end

    local item = unwrap_item_object(row)
    if item and item.get_item_id then
        local ok, id = pcall(item.get_item_id, item)
        if ok then
            return tonumber(id) or 0
        end
    end

    return 0
end

---@private
---@param item_id number
---@return number
local function inventory_item_count(item_id)
    local id = tonumber(item_id) or 0
    if id <= 0 or not core or not core.inventory or not core.inventory.get_items_in_bag then
        return 0
    end

    local total = 0
    for bag_id = 0, 4 do
        local ok, slots = pcall(core.inventory.get_items_in_bag, bag_id)
        if ok and type(slots) == "table" then
            for i = 1, #slots do
                local row = slots[i]
                if item_id_from_row(row) == id then
                    total = total + stack_count(row)
                end
            end
        end
    end

    return total
end

---@private
---@param ctx table
---@return number
local function soul_shard_count(ctx)
    local cache = runtime_cache(ctx)
    if cache.soul_shard_count ~= nil then
        return tonumber(cache.soul_shard_count) or 0
    end

    local count = inventory_item_count(SHARD_ITEM_ID)
    cache.soul_shard_count = count
    return count
end

---@private
---@param ctx table
---@return boolean
local function has_soul_shard(ctx)
    return soul_shard_count(ctx) > 0
end

---@private
---@param ctx table
---@return number|nil
local function best_summon_spell(ctx)
    local felguard = resolve_spell(ctx, SPELLS.SUMMON_FELGUARD)
    if is_learned(felguard) and has_soul_shard(ctx) then
        return felguard
    end

    local voidwalker = resolve_spell(ctx, SPELLS.SUMMON_VOIDWALKER)
    if is_learned(voidwalker) and has_soul_shard(ctx) then
        return voidwalker
    end

    local imp = resolve_spell(ctx, SPELLS.SUMMON_IMP)
    if is_learned(imp) then
        return imp
    end

    return nil
end

---@private
---@param ctx table
local function ensure_pet_attack(ctx)
    if not ctx or ctx.in_combat ~= true or not ctx.target or not ctx.pet then
        return
    end

    if not core or not core.input or type(core.input.pet_attack) ~= "function" then
        return
    end

    pcall(core.input.pet_attack, ctx.target)
end

---@private
---@param ctx table
---@return boolean
local function player_is_busy(ctx)
    local player = ctx and ctx.player
    if not player then
        return false
    end

    if player.is_casting_spell then
        local ok, casting = pcall(player.is_casting_spell, player)
        if ok and casting == true then
            return true
        end
    end

    if player.is_channelling_spell then
        local ok, channeling = pcall(player.is_channelling_spell, player)
        if ok and channeling == true then
            return true
        end
    end

    return false
end

---@return string
function Affliction:id()
    return "warlock.affliction"
end

---@return number
function Affliction:class_id()
    return Affliction.CLASS_ID
end

---@return number
function Affliction:spec_id()
    return 0
end

---@return string
function Affliction:spec()
    return Affliction.SPEC
end

---@param ctx table
---@return boolean
function Affliction:can_run(ctx)
    return (tonumber(ctx.class_id or 0) or 0) == Affliction.CLASS_ID
end

---@param ctx table
---@return table[]
function Affliction:precombat(ctx)
    return {}
end

---@param ctx table
---@return table[]
function Affliction:maintenance(ctx)
    local p = policy(ctx)
    local armor_spell = best_armor_spell(ctx)
    local summon_spell = best_summon_spell(ctx)

    return {
        ActionBuilder.item_self(ConsumableCatalog.TBC_WATER_ITEM_IDS, 980, {
            max_player_mana_pct = p.drink_mana_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.eating_or_drinking ~= true
            end,
        }),
        ActionBuilder.item_self(ConsumableCatalog.TBC_FOOD_ITEM_IDS, 970, {
            max_player_health_pct = p.eat_health_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.eating_or_drinking ~= true
            end,
        }),
        self_spell(function()
            return armor_spell
        end, 260, {
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true and not has_armor_buff(local_ctx)
            end,
        }),
        self_spell(function()
            return summon_spell
        end, 255, {
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.pet == nil
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.LIFE_TAP, 250, {
            max_player_mana_pct = p.life_tap_ooc_max_mana_pct,
            min_player_health_pct = p.life_tap_min_health_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true and not player_is_busy(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return boolean
function Affliction:should_hold_maintenance(ctx)
    local p = policy(ctx)
    if ctx.in_combat == true then
        return false
    end
    if ctx.eating_or_drinking == true then
        return true
    end

    local needs_health = ctx.player_health_pct and ctx.player_health_pct < p.eat_health_pct
    local needs_mana = ctx.player_mana_pct and ctx.player_mana_pct < p.drink_mana_pct
    return needs_health == true or needs_mana == true
end

---@param ctx table
---@return table[]
function Affliction:defensive(ctx)
    local p = policy(ctx)

    return {
        target_spell(SPELLS.DEATH_COIL, 1000, {
            max_player_health_pct = p.death_coil_hp_pct,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        ActionBuilder.best_health_potion(995, {
            max_player_health_pct = p.health_potion_hp_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        target_spell(SPELLS.DRAIN_LIFE, 945, {
            max_player_health_pct = p.drain_life_hp_pct,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return local_ctx.in_combat == true and not player_is_busy(local_ctx)
            end,
        }),
        ActionBuilder.best_mana_potion(620, {
            max_player_mana_pct = p.mana_potion_mana_pct,
            min_player_health_pct = p.mana_potion_min_hp_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:interrupt(ctx)
    return {
        target_spell(SPELLS.DEATH_COIL, 760, {
            target_must_be_casting = true,
            max_target_distance = 30.0,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:utility(ctx)
    local p = policy(ctx)
    local armor_spell = best_armor_spell(ctx)

    ensure_pet_attack(ctx)

    return {
        self_spell(function()
            return armor_spell
        end, 690, {
            condition = function(local_ctx)
                return not has_armor_buff(local_ctx) and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.HEALTH_FUNNEL, 680, {
            min_player_health_pct = 0.60,
            requires_castable_check = false,
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and local_ctx.pet ~= nil
                    and (tonumber(local_ctx.pet_health_pct) or 1.0) < p.health_funnel_pet_hp_pct
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.DARK_PACT, 650, {
            max_player_mana_pct = p.life_tap_max_mana_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat == true and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.LIFE_TAP, 640, {
            max_player_mana_pct = p.life_tap_max_mana_pct,
            min_player_health_pct = p.life_tap_min_health_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat == true and not player_is_busy(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:combat(ctx)
    local p = policy(ctx)

    return {
        target_spell(SPELLS.SHADOW_BOLT, 570, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.SHADOW_TRANCE[1]) == true
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.SHADOW_BOLT, 565, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.BACKLASH[1]) == true
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.CORRUPTION, 555, {
            allow_movement = true,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return not target_has_any_aura(local_ctx, WL_AURAS.CORRUPTION)
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.CURSE_OF_AGONY, 550, {
            allow_movement = true,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return not target_has_any_aura(local_ctx, WL_AURAS.CURSE_OF_AGONY)
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.SIPHON_LIFE, 545, {
            allow_movement = true,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.SIPHON_LIFE) ~= nil
                    and not target_has_any_aura(local_ctx, WL_AURAS.SIPHON_LIFE)
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.UNSTABLE_AFFLICTION, 540, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.UNSTABLE_AFFLICTION) ~= nil
                    and not target_has_any_aura(local_ctx, WL_AURAS.UNSTABLE_AFFLICTION)
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.IMMOLATE, 535, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return not target_has_any_aura(local_ctx, WL_AURAS.IMMOLATE)
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.DRAIN_SOUL, 530, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.DRAIN_SOUL) ~= nil
                    and soul_shard_count(local_ctx) <= 0
                    and (tonumber(local_ctx.player_mana_pct) or 1.0) <= p.wand_mana_pct
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.SHADOW_BOLT, 520, {
            min_player_mana_pct = p.wand_mana_pct,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.SHOOT, 510, {
            max_target_distance = 30.0,
            requires_castable_check = false,
            condition = function(local_ctx)
                return local_ctx.in_combat == true and not player_is_busy(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:aoe(ctx)
    return {
        target_spell(SPELLS.SEED_OF_CORRUPTION, 580, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.SEED_OF_CORRUPTION) ~= nil
                    and not target_has_any_aura(local_ctx, WL_AURAS.SEED_OF_CORRUPTION)
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.RAIN_OF_FIRE, 560, {
            max_target_distance = 30.0,
            requires_castable_check = false,
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.RAIN_OF_FIRE) ~= nil
                    and local_ctx.in_combat == true
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.CORRUPTION, 555, {
            allow_movement = true,
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return not target_has_any_aura(local_ctx, WL_AURAS.CORRUPTION)
                    and not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.SHADOW_BOLT, 520, {
            max_target_distance = 30.0,
            condition = function(local_ctx)
                return not player_is_busy(local_ctx)
            end,
        }),
        target_spell(SPELLS.SHOOT, 510, {
            max_target_distance = 30.0,
            requires_castable_check = false,
            condition = function(local_ctx)
                return local_ctx.in_combat == true and not player_is_busy(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table
function Affliction:get_pull_profile(ctx)
    local bolt = resolve_spell(ctx, SPELLS.SHADOW_BOLT)
    if bolt then
        return {
            pull_spell_id = bolt,
            max_pull_range = 30,
        }
    end

    local immolate = resolve_spell(ctx, SPELLS.IMMOLATE)
    return {
        pull_spell_id = immolate,
        max_pull_range = 30,
    }
end

return setmetatable({}, Affliction)
