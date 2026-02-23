---@class WarlockAfflictionRotation
local Affliction = {}
Affliction.__index = Affliction

local ActionBuilder = require("rotations/framework/ActionBuilder")
local ConsumableCatalog = require("rotations/framework/ConsumableCatalog")
local SpellCatalog = require("rotations/framework/SpellCatalog")
local AuraCatalog = require("rotations/framework/AuraCatalog")
local RankPolicy = require("rotations/framework/RankPolicy")
local RestPolicy = require("rotations/framework/RestPolicy")

Affliction.CLASS_ID = 9
Affliction.SPEC = "affliction"

local WL_SPELLS = SpellCatalog.WARLOCK.AFFLICTION
local WL_AURAS = AuraCatalog.WARLOCK.AFFLICTION

local SPELLS = {
    SHADOW_BOLT = WL_SPELLS.SHADOW_BOLT,
    CORRUPTION = WL_SPELLS.CORRUPTION,
    CURSE_OF_AGONY = WL_SPELLS.CURSE_OF_AGONY,
    CURSE_OF_THE_ELEMENTS = WL_SPELLS.CURSE_OF_THE_ELEMENTS,
    CURSE_OF_DOOM = WL_SPELLS.CURSE_OF_DOOM,
    CURSE_OF_TONGUES = WL_SPELLS.CURSE_OF_TONGUES,
    CURSE_OF_RECKLESSNESS = WL_SPELLS.CURSE_OF_RECKLESSNESS,
    AMPLIFY_CURSE = WL_SPELLS.AMPLIFY_CURSE,
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
    SPELL_LOCK = WL_SPELLS.SPELL_LOCK,
    SOUL_LINK = WL_SPELLS.SOUL_LINK,
    FEL_DOMINATION = WL_SPELLS.FEL_DOMINATION,

    DEMON_SKIN = WL_SPELLS.DEMON_SKIN,
    DEMON_ARMOR = WL_SPELLS.DEMON_ARMOR,
    FEL_ARMOR = WL_SPELLS.FEL_ARMOR,

    SUMMON_IMP = WL_SPELLS.SUMMON_IMP,
    SUMMON_VOIDWALKER = WL_SPELLS.SUMMON_VOIDWALKER,
    SUMMON_SUCCUBUS = WL_SPELLS.SUMMON_SUCCUBUS,
    SUMMON_FELHUNTER = WL_SPELLS.SUMMON_FELHUNTER,
    SUMMON_FELGUARD = WL_SPELLS.SUMMON_FELGUARD,

    CREATE_HEALTHSTONE = WL_SPELLS.CREATE_HEALTHSTONE,
    CREATE_SOULSTONE = WL_SPELLS.CREATE_SOULSTONE,
    SHADOW_WARD = WL_SPELLS.SHADOW_WARD,
    SHOOT = WL_SPELLS.SHOOT,
}

local SHARD_ITEM_ID = 6265
local PET_ATTACK_THROTTLE = 1.0
local PET_SPELL_LOCK_COOLDOWN = 24.0
local DOT_RECAST_SAFETY_SEC = 4.0
local SPELLBOOK_CACHE_TTL = 0.50
local _spellbook_cache = {
    at = 0,
    ids = {},
}

-- Cross-tick persistent state (module-level upvalues survive across ticks).
-- runtime_cache(ctx) CANNOT persist across ticks because ctx is rebuilt each tick.
local _last_pet_attack_at = 0
local _last_spell_lock_at = 0
local _dot_approved = {}   -- { ["targetkey:aura_id"] = timestamp }
local _dot_approved_last_prune = 0
local DOT_APPROVED_PRUNE_INTERVAL = 10.0

---@private
local function refresh_spellbook_cache()
    if not core or not core.spell_book or type(core.spell_book.get_spells) ~= "function" then
        _spellbook_cache.ids = {}
        _spellbook_cache.at = 0
        return
    end

    local now = (core and core.time and core.time()) or 0
    if now - (_spellbook_cache.at or 0) < SPELLBOOK_CACHE_TTL then
        return
    end

    local ids = {}
    local ok, spells = pcall(core.spell_book.get_spells)
    if ok and type(spells) == "table" then
        for raw_id, raw_name in pairs(spells) do
            local id = tonumber(raw_id)
            if type(raw_name) == "table" then
                id = tonumber(raw_name.spell_id or raw_name.id or raw_id)
            end
            if id and id > 0 then
                ids[id] = true
            end
        end
    end

    _spellbook_cache.ids = ids
    _spellbook_cache.at = now
end

local DEFAULT_POLICY = {
    drink_mana_pct = 0.15,
    eat_health_pct = 0.45,
    rest_until_full = true,
    rest_resume_health_pct = 0.80,
    rest_resume_mana_pct = 0.55,
    life_tap_min_health_pct = 0.50,
    life_tap_max_mana_pct = 0.85,
    life_tap_ooc_max_mana_pct = 0.90,
    death_coil_hp_pct = 0.35,
    drain_life_hp_pct = 0.55,
    health_funnel_pet_hp_pct = 0.30,
    health_potion_hp_pct = 0.25,
    mana_potion_mana_pct = 0.15,
    mana_potion_min_hp_pct = 0.35,
    wand_mana_pct = 0.05,
    mana_sustain_enter_pct = 0.35,
    mana_sustain_exit_pct = 0.50,
    mana_recovery_enter_pct = 0.12,
    mana_recovery_exit_pct = 0.22,
    ttd_alpha = 0.35,
    ttd_min_sample_secs = 0.20,
    ttd_memory_ttl_secs = 20.0,
    ttd_max_seconds = 120.0,
    execute_target_health_pct = 0.25,
    execute_ttd_horizon_sec = 8.0,
    corruption_min_ttd_sec = 6.0,
    curse_of_agony_min_ttd_sec = 6.0,
    immolate_min_ttd_sec = 5.0,
    siphon_life_min_ttd_sec = 8.0,
    unstable_affliction_min_ttd_sec = 6.0,
    dot_refresh_window_sec = 4.5,
}

local CAST_RANGE = 30.0

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

    refresh_spellbook_cache()
    if _spellbook_cache.ids[id] == true then
        return true
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
        if id then
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
---@param spec table|string|number|function
---@param priority number
---@param opts? table
---@return table
local function position_spell(spec, priority, opts)
    if type(spec) == "number" or type(spec) == "function" then
        return ActionBuilder.position_spell(spec, priority, opts)
    end

    return ActionBuilder.position_spell(function(ctx)
        return resolve_spell(ctx, spec)
    end, priority, opts)
end

---@private
---@param value any
---@return string
local function normalize_text(value)
    return tostring(value or ""):lower()
end

---@private
---@param ctx table
---@param spec table|string|number
---@return number|nil
local function resolve_pet_spell(ctx, spec)
    if type(spec) == "number" then
        return spell_id(spec)
    end

    local spell_name = spec
    local spell_fallback = nil
    if type(spec) == "table" then
        spell_name = SpellCatalog.name(spec)
        spell_fallback = SpellCatalog.ids(spec)
    end
    local wanted = normalize_text(spell_name)

    local cache = runtime_cache(ctx)
    local key = "pet#" .. tostring(wanted) .. "#" .. tostring(type(spell_fallback) == "table" and spell_fallback[1] or 0)
    local cached = cache[key]
    if cached ~= nil then
        return cached or nil
    end

    local resolved = nil
    local saw_pet_list = false
    if core and core.spell_book and type(core.spell_book.get_pet_spells) == "function" then
        local ok, pet_spells = pcall(core.spell_book.get_pet_spells)
        if ok and type(pet_spells) == "table" then
            saw_pet_list = true

            local fallback_rank_idx = {}
            if type(spell_fallback) == "table" then
                for i = 1, #spell_fallback do
                    local id = spell_id(spell_fallback[i])
                    if id then
                        fallback_rank_idx[id] = i
                    end
                end
            end

            local best_rank_idx = nil
            for raw_id, raw_name in pairs(pet_spells) do
                local id = tonumber(raw_id)
                local name = normalize_text(raw_name)

                if type(raw_name) == "table" then
                    id = tonumber(raw_name.spell_id or raw_name.id or raw_id)
                    name = normalize_text(raw_name.spell_name or raw_name.name or "")
                end

                if id and id > 0 then
                    local idx = fallback_rank_idx[id]
                    if idx then
                        if best_rank_idx == nil or idx < best_rank_idx then
                            best_rank_idx = idx
                            resolved = id
                        end
                    elseif best_rank_idx == nil and wanted ~= "" and name ~= "" and name:find(wanted, 1, true) then
                        resolved = id
                    end
                end
            end
        end
    end

    if resolved == nil and not saw_pet_list and type(spell_fallback) == "table" and #spell_fallback > 0 then
        resolved = spell_id(spell_fallback[1])
    end

    cache[key] = resolved or false
    return resolved
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
    local now = tonumber(type(ctx) == "table" and ctx.now or nil)
    if now ~= nil
        and cache.soul_shard_count ~= nil
        and tonumber(cache.soul_shard_count_at) == now then
        return tonumber(cache.soul_shard_count) or 0
    end

    local count = inventory_item_count(SHARD_ITEM_ID)
    cache.soul_shard_count = count
    cache.soul_shard_count_at = now
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

    local felhunter = resolve_spell(ctx, SPELLS.SUMMON_FELHUNTER)
    if is_learned(felhunter) and has_soul_shard(ctx) then
        return felhunter
    end

    local succubus = resolve_spell(ctx, SPELLS.SUMMON_SUCCUBUS)
    if is_learned(succubus) and has_soul_shard(ctx) then
        return succubus
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

    local now = tonumber(ctx.now) or ((core and core.time and core.time()) or 0)
    if now - _last_pet_attack_at < PET_ATTACK_THROTTLE then
        return
    end
    _last_pet_attack_at = now

    pcall(core.input.pet_attack, ctx.target)
end

---@private
---@param target any
---@return boolean
local function target_spell_interruptable(target)
    if not target then
        return false
    end
    if type(target.is_active_spell_interruptable) == "function" then
        local ok, interruptable = pcall(target.is_active_spell_interruptable, target)
        if ok and interruptable ~= nil then
            return interruptable == true
        end
    end
    return true
end

---@private
---@param ctx table
local function try_pet_spell_lock(ctx)
    if not ctx or ctx.in_combat ~= true or not ctx.target or not ctx.pet then
        return
    end
    if ctx.target_is_casting ~= true then
        return
    end
    if (tonumber(ctx.target_distance) or 999) > 30.0 then
        return
    end
    if not target_spell_interruptable(ctx.target) then
        return
    end
    if not core or not core.input or type(core.input.pet_cast_target_spell) ~= "function" then
        return
    end

    local lock_id = resolve_pet_spell(ctx, SPELLS.SPELL_LOCK)
    if not lock_id then
        return
    end

    local now = tonumber(ctx.now) or ((core and core.time and core.time()) or 0)
    if now - _last_spell_lock_at < PET_SPELL_LOCK_COOLDOWN then
        return
    end
    _last_spell_lock_at = now

    pcall(core.input.pet_cast_target_spell, lock_id, ctx.target)
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

---@private
---@param ctx table
---@return boolean
local function is_wanding(ctx)
    local shoot_id = resolve_spell(ctx, SPELLS.SHOOT)
    if not shoot_id or shoot_id <= 0 then
        return false
    end
    if core and core.spell_book and type(core.spell_book.is_current_spell) == "function" then
        local ok, active = pcall(core.spell_book.is_current_spell, shoot_id)
        if ok and active == true then
            return true
        end
    end
    return false
end

---@private
---@param target any
---@return string
local function target_key(target)
    if not target then
        return "nil"
    end

    if type(target.get_address) == "function" then
        local ok, addr = pcall(target.get_address, target)
        if ok and addr ~= nil then
            return tostring(addr)
        end
    end
    if type(target.get_pointer) == "function" then
        local ok, ptr = pcall(target.get_pointer, target)
        if ok and ptr ~= nil then
            return tostring(ptr)
        end
    end
    if type(target.get_guid) == "function" then
        local ok, guid = pcall(target.get_guid, target)
        if ok and guid ~= nil then
            return tostring(guid)
        end
    end

    return tostring(target)
end

---@private
---@param v number
---@param lo number
---@param hi number
---@return number
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

---@private
---@param unit any
---@param method string
---@param ... any
---@return any
local function safe_unit_call(unit, method, ...)
    if not unit then
        return nil
    end
    local fn = unit[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, unit, ...)
    if not ok then
        return nil
    end
    return value
end

---@private
---@param now number
local function prune_dot_approved(now)
    if now - _dot_approved_last_prune < DOT_APPROVED_PRUNE_INTERVAL then
        return
    end
    _dot_approved_last_prune = now
    for k, ts in pairs(_dot_approved) do
        if now - ts > DOT_RECAST_SAFETY_SEC * 2 then
            _dot_approved[k] = nil
        end
    end
end

---@private
---@param ctx table
---@param aura_ids number[]
---@param refresh_window number
---@return boolean
local function dot_needs_refresh(ctx, aura_ids, refresh_window)
    if type(ctx.target_has_aura) ~= "function" then
        return true
    end

    local aura_key = aura_ids[1] or 0
    local tkey = target_key(ctx.target)
    local compound = tkey .. ":" .. tostring(aura_key)

    local now = tonumber(ctx.now) or 0
    prune_dot_approved(now)

    if not target_has_any_aura(ctx, aura_ids) then
        -- Anti-double-cast: suppress if we recently approved this DoT on THIS target.
        -- Covers aura-detection-lag when cast_time > GCD (e.g. Immolate 2s cast, 1.5s GCD).
        local last_approved = _dot_approved[compound] or 0
        if now - last_approved < DOT_RECAST_SAFETY_SEC then
            return false
        end
        _dot_approved[compound] = now
        return true
    end

    -- Aura exists — clear the approval record and check remaining time
    _dot_approved[compound] = nil

    if type(ctx.target_aura_remaining) == "function" then
        local remaining = ctx.target_aura_remaining(aura_ids)
        if remaining ~= nil and remaining < refresh_window and remaining < 999 then
            return true
        end
    end
    return false
end

---@private
---@param ctx table
---@return table spell
---@return table aura_ids
local function select_curse(ctx)
    -- Curse of the Elements preferred (benefits all casters + self shadow/fire damage)
    if resolve_spell(ctx, SPELLS.CURSE_OF_THE_ELEMENTS) then
        return SPELLS.CURSE_OF_THE_ELEMENTS, WL_AURAS.CURSE_OF_THE_ELEMENTS
    end
    -- Fallback to Curse of Agony for damage
    return SPELLS.CURSE_OF_AGONY, WL_AURAS.CURSE_OF_AGONY
end

---@private
---@param ctx table
---@param min_ttd_sec number
---@return boolean
local function target_lives_long_enough(ctx, min_ttd_sec)
    local ttd = tonumber(ctx.target_ttd_seconds)
    if ttd == nil then
        return true
    end
    return ttd >= min_ttd_sec
end

---@private
---@param now number
---@param ttl number
function Affliction:_prune_ttd_state(now, ttl)
    if type(self._ttd_state) ~= "table" then
        self._ttd_state = {}
        return
    end

    for key, entry in pairs(self._ttd_state) do
        local updated_at = tonumber(entry and entry.updated_at) or 0
        if updated_at <= 0 or (now - updated_at) > ttl then
            self._ttd_state[key] = nil
        end
    end
end

---@private
---@param ctx table
---@param p table
---@return number|nil
---@return number|nil
function Affliction:_estimate_target_ttd(ctx, p)
    local target = ctx and ctx.target
    if not target then
        return nil, nil
    end

    local now = tonumber(ctx and ctx.now) or ((core and core.time and core.time()) or 0)
    local ttl = tonumber(p and p.ttd_memory_ttl_secs) or 20.0
    if ttl <= 0 then
        ttl = 20.0
    end
    self:_prune_ttd_state(now, ttl)

    self._ttd_state = self._ttd_state or {}
    local key = target_key(target)
    local entry = self._ttd_state[key] or {}

    local hp = tonumber(safe_unit_call(target, "get_health"))
    local max_hp = tonumber(safe_unit_call(target, "get_max_health"))
    if hp == nil then
        local pct = tonumber(ctx and ctx.target_health_pct)
        if pct ~= nil and max_hp and max_hp > 0 then
            hp = pct * max_hp
        end
    end
    if max_hp == nil or max_hp <= 0 then
        max_hp = hp or 0
    end
    if hp == nil then
        return nil, nil
    end
    if hp <= 0 then
        entry.last_hp = 0
        entry.last_ttd = 0
        entry.updated_at = now
        self._ttd_state[key] = entry
        return 0, nil
    end

    local alpha = clamp(tonumber(p and p.ttd_alpha) or 0.35, 0.05, 0.95)
    local min_sample = tonumber(p and p.ttd_min_sample_secs) or 0.20
    if min_sample <= 0 then
        min_sample = 0.20
    end
    local max_ttd = tonumber(p and p.ttd_max_seconds) or 120.0
    if max_ttd <= 0 then
        max_ttd = 120.0
    end

    local last_hp = tonumber(entry.last_hp)
    local last_ts = tonumber(entry.last_ts)
    if last_hp ~= nil and last_ts ~= nil then
        local dt = now - last_ts
        if dt >= min_sample then
            local delta = last_hp - hp
            if delta > 0 then
                local inst_dps = delta / dt
                if inst_dps > 0 then
                    local ema = tonumber(entry.ema_dps)
                    if ema == nil or ema <= 0 then
                        ema = inst_dps
                    else
                        ema = (ema * (1.0 - alpha)) + (inst_dps * alpha)
                    end
                    entry.ema_dps = ema
                end
            end
        end
    end

    entry.last_hp = hp
    entry.last_max_hp = max_hp
    entry.last_ts = now
    entry.updated_at = now

    local hazard = nil
    local ttd = nil
    local ema_dps = tonumber(entry.ema_dps)
    if ema_dps and ema_dps > 0 then
        hazard = ema_dps / math.max(1.0, hp)
        if hazard > 0 then
            ttd = 1.0 / hazard
        end
    end

    if ttd ~= nil then
        ttd = clamp(ttd, 0, max_ttd)
    end
    self._ttd_state[key] = entry

    return ttd, hazard
end

---@private
---@param ctx table
---@param p table
---@return string
function Affliction:_resolve_mana_mode(ctx, p)
    local mana_pct = tonumber(ctx and ctx.player_mana_pct) or 1.0
    local mode = tostring(self._mana_mode or "burst")

    local sustain_enter = tonumber(p and p.mana_sustain_enter_pct) or 0.45
    local sustain_exit = tonumber(p and p.mana_sustain_exit_pct) or 0.58
    local recovery_enter = tonumber(p and p.mana_recovery_enter_pct) or 0.22
    local recovery_exit = tonumber(p and p.mana_recovery_exit_pct) or 0.32

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
function Affliction:resolve_combat_state(ctx)
    local p = policy(ctx)
    local mana_mode = self:_resolve_mana_mode(ctx, p)
    local target_health_pct = tonumber(ctx and ctx.target_health_pct)
    local target_ttd, target_hazard = self:_estimate_target_ttd(ctx, p)

    local execute_hp = tonumber(p.execute_target_health_pct) or 0.25
    local execute = target_health_pct ~= nil and target_health_pct <= execute_hp
    if not execute and target_ttd ~= nil then
        local horizon = tonumber(p.execute_ttd_horizon_sec) or 8.0
        if target_ttd <= horizon then
            execute = true
        end
    end

    local intents = {
        defensive = 1.0,
        interrupt = 1.0,
        utility = 0.4,
        sustain = 0.8,
        burst = 0.5,
        recover = 0.3,
        execute = execute and 1.2 or 0.0,
    }

    if mana_mode == "burst" then
        intents.burst = 1.0
        intents.sustain = 0.6
        intents.recover = -1.0
    elseif mana_mode == "sustain" then
        intents.burst = 0.2
        intents.sustain = 1.0
        intents.recover = 0.5
    else
        intents.burst = -1.6
        intents.sustain = 0.9
        intents.recover = 1.0
    end

    return {
        combat_mode = mana_mode,
        mana_mode = mana_mode,
        in_execute_phase = execute,
        target_ttd_seconds = target_ttd,
        target_hazard_rate = target_hazard,
        planner_intents = intents,
    }
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
    local rest = rest_policy_thresholds(p)

    return {
        ActionBuilder.item_self(ConsumableCatalog.TBC_WATER_ITEM_IDS, 980, {
            max_player_mana_pct = rest.drink_stop_pct,
            item_kind = "water",
            rest_lock_secs = 2.0,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.player_is_drinking ~= true
                    and RestPolicy.needs_mana_rest(local_ctx, rest)
                    and (local_ctx.eating_or_drinking ~= true or local_ctx.player_is_eating == true)
            end,
        }),
        ActionBuilder.item_self(ConsumableCatalog.TBC_FOOD_ITEM_IDS, 970, {
            max_player_health_pct = rest.eat_stop_pct,
            item_kind = "food",
            rest_lock_secs = 2.0,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.player_is_eating ~= true
                    and RestPolicy.needs_health_rest(local_ctx, rest)
                    and (local_ctx.eating_or_drinking ~= true or local_ctx.player_is_drinking == true)
            end,
        }),
        self_spell(function(local_ctx)
            return best_armor_spell(local_ctx or ctx)
        end, 260, {
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true and not has_armor_buff(local_ctx)
            end,
        }),
        self_spell(function(local_ctx)
            return best_summon_spell(local_ctx or ctx)
        end, 255, {
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.pet == nil
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.CREATE_HEALTHSTONE, 252, {
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and not player_is_busy(local_ctx)
                    and soul_shard_count(local_ctx) >= 2
            end,
        }),
        self_spell(SPELLS.DARK_PACT, 251, {
            max_player_mana_pct = p.life_tap_ooc_max_mana_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.eating_or_drinking ~= true
                    and local_ctx.pet ~= nil
                    and resolve_spell(local_ctx, SPELLS.DARK_PACT) ~= nil
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.LIFE_TAP, 250, {
            max_player_mana_pct = p.life_tap_ooc_max_mana_pct,
            min_player_health_pct = p.life_tap_min_health_pct,
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.eating_or_drinking ~= true
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.HEALTH_FUNNEL, 240, {
            min_player_health_pct = 0.60,
            requires_castable_check = false,
            intent = "utility",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.player_is_moving ~= true
                    and local_ctx.pet ~= nil
                    and (tonumber(local_ctx.pet_health_pct) or 1.0) < p.health_funnel_pet_hp_pct
                    and not player_is_busy(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return boolean
function Affliction:should_hold_maintenance(ctx)
    local p = policy(ctx)
    local rest = rest_policy_thresholds(p)
    return RestPolicy.should_hold(ctx, rest)
end

---@param ctx table
---@return table[]
function Affliction:defensive(ctx)
    local p = policy(ctx)

    return {
        target_spell(SPELLS.DEATH_COIL, 1000, {
            max_player_health_pct = p.death_coil_hp_pct,
            max_target_distance = CAST_RANGE,
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        ActionBuilder.best_health_potion(995, {
            max_player_health_pct = p.health_potion_hp_pct,
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        target_spell(SPELLS.FEAR, 960, {
            max_target_distance = 20.0,
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and (tonumber(local_ctx.player_health_pct) or 1.0) < 0.40
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.HOWL_OF_TERROR, 955, {
            requires_castable_check = false,
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and (tonumber(local_ctx.player_health_pct) or 1.0) < 0.40
                    and (tonumber(local_ctx.enemy_count) or 1) >= 2
                    and resolve_spell(local_ctx, SPELLS.HOWL_OF_TERROR) ~= nil
            end,
        }),
        target_spell(SPELLS.DRAIN_LIFE, 945, {
            max_player_health_pct = p.drain_life_hp_pct,
            max_target_distance = CAST_RANGE,
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and not player_is_busy(local_ctx)
                    and not is_wanding(local_ctx)
            end,
        }),
        self_spell(SPELLS.SHADOW_WARD, 935, {
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and resolve_spell(local_ctx, SPELLS.SHADOW_WARD) ~= nil
                    and (tonumber(local_ctx.player_health_pct) or 1.0) < 0.60
            end,
        }),
        ActionBuilder.best_mana_potion(620, {
            max_player_mana_pct = p.mana_potion_mana_pct,
            min_player_health_pct = p.mana_potion_min_hp_pct,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:interrupt(ctx)
    try_pet_spell_lock(ctx)

    return {
        target_spell(SPELLS.DEATH_COIL, 760, {
            target_must_be_casting = true,
            max_target_distance = CAST_RANGE,
            intent = "interrupt",
        }),
        target_spell(SPELLS.FEAR, 740, {
            target_must_be_casting = true,
            max_target_distance = 20.0,
            intent = "interrupt",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
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
        self_spell(SPELLS.SOUL_LINK, 695, {
            intent = "defensive",
            condition = function(local_ctx)
                return local_ctx.pet ~= nil
                    and resolve_spell(local_ctx, SPELLS.SOUL_LINK) ~= nil
                    and local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.SOUL_LINK[1]) ~= true
            end,
        }),
        self_spell(function()
            return armor_spell
        end, 690, {
            intent = "utility",
            condition = function(local_ctx)
                return not has_armor_buff(local_ctx)
            end,
        }),
        self_spell(SPELLS.HEALTH_FUNNEL, 680, {
            min_player_health_pct = 0.60,
            requires_castable_check = false,
            intent = "utility",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and local_ctx.pet ~= nil
                    and (tonumber(local_ctx.pet_health_pct) or 1.0) < p.health_funnel_pet_hp_pct
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(SPELLS.DARK_PACT, 655, {
            max_player_mana_pct = p.life_tap_max_mana_pct,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and local_ctx.pet ~= nil
                    and resolve_spell(local_ctx, SPELLS.DARK_PACT) ~= nil
            end,
        }),
        self_spell(SPELLS.LIFE_TAP, 640, {
            max_player_mana_pct = p.life_tap_max_mana_pct,
            min_player_health_pct = p.life_tap_min_health_pct,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        -- Pet re-summon: Fel Domination (instant summon talent) then Felhunter
        self_spell(SPELLS.FEL_DOMINATION, 631, {
            intent = "utility",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and local_ctx.pet == nil
                    and resolve_spell(local_ctx, SPELLS.FEL_DOMINATION) ~= nil
                    and not player_is_busy(local_ctx)
            end,
        }),
        self_spell(function(local_ctx)
            return best_summon_spell(local_ctx or ctx)
        end, 630, {
            intent = "utility",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and local_ctx.pet == nil
                    and soul_shard_count(local_ctx) >= 1
                    and not player_is_busy(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:combat(ctx)
    local p = policy(ctx)

    return {
        -- Nightfall proc: instant Shadow Bolt
        target_spell(SPELLS.SHADOW_BOLT, 570, {
            max_target_distance = CAST_RANGE,
            intent = "burst",
            condition = function(local_ctx)
                return local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.SHADOW_TRANCE[1]) == true
            end,
        }),
        -- Backlash proc: instant Shadow Bolt
        target_spell(SPELLS.SHADOW_BOLT, 565, {
            max_target_distance = CAST_RANGE,
            intent = "burst",
            condition = function(local_ctx)
                return local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.BACKLASH[1]) == true
            end,
        }),
        -- Drain Soul: execute phase (target < 25% HP), generates soul shard on kill
        target_spell(SPELLS.DRAIN_SOUL, 560, {
            max_target_distance = CAST_RANGE,
            intent = "execute",
            max_target_health_pct = p.execute_target_health_pct,
            min_player_mana_pct = p.wand_mana_pct,
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.DRAIN_SOUL) ~= nil
                    and local_ctx.in_combat == true
                    and not player_is_busy(local_ctx)
            end,
        }),
        -- Corruption (instant, allow movement)
        target_spell(SPELLS.CORRUPTION, 555, {
            allow_movement = true,
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                return dot_needs_refresh(local_ctx, WL_AURAS.CORRUPTION, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.corruption_min_ttd_sec)
            end,
        }),
        -- Amplify Curse: talent, instant, 3-min CD, +50% next curse damage
        self_spell(SPELLS.AMPLIFY_CURSE, 554, {
            intent = "sustain",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and resolve_spell(local_ctx, SPELLS.AMPLIFY_CURSE) ~= nil
                    and local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.AMPLIFY_CURSE[1]) ~= true
            end,
        }),
        -- Curse: prefer Curse of Elements (caster damage buff), fallback to Curse of Agony
        target_spell(SPELLS.CURSE_OF_THE_ELEMENTS, 552, {
            allow_movement = true,
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.CURSE_OF_THE_ELEMENTS) ~= nil
                    and dot_needs_refresh(local_ctx, WL_AURAS.CURSE_OF_THE_ELEMENTS, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.curse_of_agony_min_ttd_sec)
            end,
        }),
        target_spell(SPELLS.CURSE_OF_AGONY, 550, {
            allow_movement = true,
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                -- Only if CoE is not available (not learned)
                if resolve_spell(local_ctx, SPELLS.CURSE_OF_THE_ELEMENTS) ~= nil then
                    return false
                end
                return dot_needs_refresh(local_ctx, WL_AURAS.CURSE_OF_AGONY, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.curse_of_agony_min_ttd_sec)
            end,
        }),
        -- Siphon Life (instant, allow movement, talent-gated)
        target_spell(SPELLS.SIPHON_LIFE, 545, {
            allow_movement = true,
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.SIPHON_LIFE) ~= nil
                    and dot_needs_refresh(local_ctx, WL_AURAS.SIPHON_LIFE, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.siphon_life_min_ttd_sec)
            end,
        }),
        -- Unstable Affliction (cast time, talent-gated)
        target_spell(SPELLS.UNSTABLE_AFFLICTION, 540, {
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                return resolve_spell(local_ctx, SPELLS.UNSTABLE_AFFLICTION) ~= nil
                    and dot_needs_refresh(local_ctx, WL_AURAS.UNSTABLE_AFFLICTION, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.unstable_affliction_min_ttd_sec)
            end,
        }),
        -- Immolate (cast time, stacks with UA for more DoT damage while wanding)
        target_spell(SPELLS.IMMOLATE, 535, {
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                return dot_needs_refresh(local_ctx, WL_AURAS.IMMOLATE, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.immolate_min_ttd_sec)
            end,
        }),
        -- Shadow Bolt filler (skip in recovery mode)
        target_spell(SPELLS.SHADOW_BOLT, 450, {
            min_player_mana_pct = p.wand_mana_pct,
            max_target_distance = CAST_RANGE,
            intent = "burst",
            combat_modes = { "burst" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        -- Wand fallback
        target_spell(SPELLS.SHOOT, 510, {
            max_target_distance = CAST_RANGE,
            requires_castable_check = false,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and not player_is_busy(local_ctx)
                    and not is_wanding(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table[]
function Affliction:aoe(ctx)
    local p = policy(ctx)

    return {
        -- Nightfall proc: instant Shadow Bolt (free damage during AoE)
        target_spell(SPELLS.SHADOW_BOLT, 590, {
            max_target_distance = CAST_RANGE,
            intent = "burst",
            condition = function(local_ctx)
                return local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.SHADOW_TRANCE[1]) == true
            end,
        }),
        -- Backlash proc: instant Shadow Bolt (free damage during AoE)
        target_spell(SPELLS.SHADOW_BOLT, 585, {
            max_target_distance = CAST_RANGE,
            intent = "burst",
            condition = function(local_ctx)
                return local_ctx.player_has_aura
                    and local_ctx.player_has_aura(WL_AURAS.BACKLASH[1]) == true
            end,
        }),
        -- Seed of Corruption: 3+ targets, primary AoE
        target_spell(SPELLS.SEED_OF_CORRUPTION, 580, {
            max_target_distance = CAST_RANGE,
            intent = "burst",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and (tonumber(local_ctx.enemy_count) or 1) >= 3
                    and resolve_spell(local_ctx, SPELLS.SEED_OF_CORRUPTION) ~= nil
                    and not target_has_any_aura(local_ctx, WL_AURAS.SEED_OF_CORRUPTION)
            end,
        }),
        -- Rain of Fire: 3+ targets, secondary AoE
        position_spell(SPELLS.RAIN_OF_FIRE, 560, {
            position = function(local_ctx)
                return local_ctx.target_position
            end,
            max_target_distance = CAST_RANGE,
            requires_castable_check = false,
            intent = "burst",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and (tonumber(local_ctx.enemy_count) or 1) >= 3
                    and resolve_spell(local_ctx, SPELLS.RAIN_OF_FIRE) ~= nil
                    and local_ctx.target_position ~= nil
            end,
        }),
        -- Corruption: spread DoTs in AoE (instant, cheap)
        target_spell(SPELLS.CORRUPTION, 555, {
            allow_movement = true,
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and dot_needs_refresh(local_ctx, WL_AURAS.CORRUPTION, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.corruption_min_ttd_sec)
            end,
        }),
        -- Curse: spread to AoE targets (CoE if available, else CoA)
        target_spell(function(local_ctx)
            local spell, _ = select_curse(local_ctx)
            return resolve_spell(local_ctx, spell)
        end, 548, {
            allow_movement = true,
            max_target_distance = CAST_RANGE,
            intent = "sustain",
            condition = function(local_ctx)
                local _, aura = select_curse(local_ctx)
                return local_ctx.in_combat == true
                    and dot_needs_refresh(local_ctx, aura, p.dot_refresh_window_sec)
                    and target_lives_long_enough(local_ctx, p.curse_of_agony_min_ttd_sec)
            end,
        }),
        -- Shadow Bolt filler (skip in recovery mode)
        target_spell(SPELLS.SHADOW_BOLT, 450, {
            max_target_distance = CAST_RANGE,
            min_player_mana_pct = p.wand_mana_pct,
            intent = "burst",
            combat_modes = { "burst" },
            condition = function(local_ctx)
                return local_ctx.in_combat == true
            end,
        }),
        -- Wand fallback
        target_spell(SPELLS.SHOOT, 510, {
            max_target_distance = CAST_RANGE,
            requires_castable_check = false,
            intent = "recover",
            condition = function(local_ctx)
                return local_ctx.in_combat == true
                    and not player_is_busy(local_ctx)
                    and not is_wanding(local_ctx)
            end,
        }),
    }
end

---@param ctx table
---@return table
function Affliction:get_pull_profile(ctx)
    -- Corruption preferred: instant cast, starts DoT ticking immediately, zero cast time.
    -- Combat rotation applies remaining DoTs (Immolate, CoA, UA) after combat starts.
    -- disable_auto_attack: ranged class, never start melee auto-attack.
    local corruption = resolve_spell(ctx, SPELLS.CORRUPTION)
    if corruption then
        return {
            pull_spell_id = corruption,
            max_pull_range = CAST_RANGE,
            melee_engage_range = CAST_RANGE,
            disable_auto_attack = true,
        }
    end

    local immolate = resolve_spell(ctx, SPELLS.IMMOLATE)
    if immolate then
        return {
            pull_spell_id = immolate,
            max_pull_range = CAST_RANGE,
            melee_engage_range = CAST_RANGE,
            disable_auto_attack = true,
        }
    end

    local bolt = resolve_spell(ctx, SPELLS.SHADOW_BOLT)
    if bolt then
        return {
            pull_spell_id = bolt,
            max_pull_range = CAST_RANGE,
            melee_engage_range = CAST_RANGE,
            disable_auto_attack = true,
        }
    end

    return {
        pull_spell_id = nil,
        max_pull_range = CAST_RANGE,
        melee_engage_range = CAST_RANGE,
        disable_auto_attack = true,
    }
end

---@param ctx table
---@return table
function Affliction:get_movement_profile(ctx)
    return {
        combat_chase_range = CAST_RANGE,
    }
end

return setmetatable({}, Affliction)
