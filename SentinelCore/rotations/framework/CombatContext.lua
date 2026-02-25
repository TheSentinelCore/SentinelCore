local get_now = require("lib/TimeHelper").get_now
local UnitQueries = require("lib/UnitQueries")
local safe_unit_call = UnitQueries.safe_method

---@class CombatContextBuilder
---@field private _blackboard Blackboard
local CombatContext = {}
CombatContext.__index = CombatContext

---@param blackboard Blackboard
---@return CombatContextBuilder
function CombatContext:new(blackboard)
    local o = setmetatable({}, CombatContext)
    o._blackboard = blackboard
    return o
end

---@private
---@param value any
---@return number|nil
local function to_number(value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    return n
end

---@private
---@param value number|nil
---@return number|nil
local function normalize_pct(value)
    local n = to_number(value)
    if n == nil then
        return nil
    end

    -- Runtime helpers are inconsistent between 0..1 and 0..100 outputs.
    if n > 1.0 then
        n = n / 100.0
    end

    if n < 0 then
        n = 0
    elseif n > 1 then
        n = 1
    end

    return n
end

---@private
---@param unit game_object|nil
---@return number|nil
local function fallback_health_pct(unit)
    if not unit then
        return nil
    end

    local hp = to_number(safe_unit_call(unit, "get_health")) or 0
    local hp_max = to_number(safe_unit_call(unit, "get_max_health")) or hp
    hp_max = math.max(1, hp_max)
    return normalize_pct(hp / hp_max)
end

---@private
---@param unit game_object|nil
---@param unit_helper table|nil
---@return number|nil
local function resolve_health_pct(unit, unit_helper)
    if unit and unit_helper and unit_helper.get_health_percentage then
        local ok, pct = pcall(unit_helper.get_health_percentage, unit_helper, unit)
        if ok then
            local normalized = normalize_pct(pct)
            if normalized ~= nil then
                return normalized
            end
        end
    end

    return fallback_health_pct(unit)
end

---@private
---@param unit game_object|nil
---@param unit_helper table|nil
---@param mana_type number|nil
---@return number|nil
local function resolve_mana_pct(unit, unit_helper, mana_type)
    if not unit then
        return nil
    end

    local function ratio(current, maximum)
        local c = to_number(current)
        local m = to_number(maximum)
        if c == nil or m == nil or m <= 0 then
            return nil
        end
        return normalize_pct(c / m)
    end

    local helper_pct = nil
    if unit_helper and unit_helper.get_resource_percentage and mana_type ~= nil then
        local ok, pct = pcall(unit_helper.get_resource_percentage, unit_helper, unit, mana_type)
        if ok then
            helper_pct = normalize_pct(pct)
        end
    end

    local mana_api_pct = ratio(
        safe_unit_call(unit, "get_mana"),
        safe_unit_call(unit, "get_max_mana")
    )

    local power_primary_pct = nil
    if mana_type ~= nil then
        power_primary_pct = ratio(
            safe_unit_call(unit, "get_power", mana_type),
            safe_unit_call(unit, "get_max_power", mana_type)
        )
    end

    local power_fallback_zero_pct = nil
    if mana_type ~= nil then
        power_fallback_zero_pct = ratio(
            safe_unit_call(unit, "get_power", 0),
            safe_unit_call(unit, "get_max_power", 0)
        )
    end

    -- Prefer direct power for the declared mana type. If enum mapping is wrong
    -- and reports 0, fall back to power(0) when it is positive.
    if power_primary_pct ~= nil then
        if power_primary_pct > 0 then
            return power_primary_pct
        end
        if mana_type ~= 0 and power_fallback_zero_pct ~= nil and power_fallback_zero_pct > 0 then
            return power_fallback_zero_pct
        end
        if mana_api_pct ~= nil and mana_api_pct > 0 then
            return mana_api_pct
        end
        if helper_pct ~= nil and helper_pct > 0 then
            return helper_pct
        end
        return power_primary_pct
    end

    if power_fallback_zero_pct ~= nil then
        if power_fallback_zero_pct > 0 then
            return power_fallback_zero_pct
        end
        if mana_api_pct ~= nil and mana_api_pct > 0 then
            return mana_api_pct
        end
        if helper_pct ~= nil and helper_pct > 0 then
            return helper_pct
        end
        return power_fallback_zero_pct
    end

    if mana_api_pct ~= nil then
        return mana_api_pct
    end

    return helper_pct
end

---@private
---@param player game_object|nil
---@return boolean
local function resolve_player_moving(player)
    if not player then
        return false
    end

    if player.is_standing_still then
        local ok, standing_still = pcall(player.is_standing_still, player, 0.10)
        if ok and type(standing_still) == "boolean" then
            return not standing_still
        end
    end

    if player.get_movement_speed then
        local ok, speed = pcall(player.get_movement_speed, player)
        if ok then
            return (to_number(speed) or 0) > 0.1
        end
    end

    return false
end

---@private
---@param value any
---@return number
local function normalize_seconds(value)
    local n = tonumber(value)
    if n == nil then
        return 0
    end
    if n > 50 then
        n = n / 1000.0
    end
    if n < 0 then
        n = 0
    end
    return n
end

---@private
---@return number
local function resolve_global_cooldown_remaining()
    if not core or not core.spell_book then
        return 0
    end
    if type(core.spell_book.get_global_cooldown) ~= "function" then
        return 0
    end

    local ok, value = pcall(core.spell_book.get_global_cooldown)
    if not ok then
        return 0
    end
    return normalize_seconds(value)
end

---@private
---@param spell_id number|nil
---@param gcd_remaining number
---@return number
local function resolve_spell_cooldown_remaining(spell_id, gcd_remaining)
    local id = tonumber(spell_id) or 0
    if id <= 0 or not core or not core.spell_book then
        return gcd_remaining or 0
    end

    local remaining = nil
    if type(core.spell_book.get_spell_cooldown_remaining) == "function" then
        local ok_remaining, value = pcall(core.spell_book.get_spell_cooldown_remaining, id)
        if ok_remaining then
            remaining = tonumber(value)
        end
    end

    if (remaining == nil or remaining <= 0) and type(core.spell_book.get_spell_cooldown) == "function" then
        local ok_cd, a, b = pcall(core.spell_book.get_spell_cooldown, id)
        if ok_cd then
            if type(a) == "table" then
                remaining = tonumber(a.remaining)
                    or tonumber(a.cooldown_remaining)
                    or tonumber(a.time_left)
                    or tonumber(a.left)
                    or tonumber(a.duration)
            elseif tonumber(a) and tonumber(a) > 0 and tonumber(a) <= 30 then
                remaining = tonumber(a)
            elseif tonumber(b) and tonumber(b) > 0 and tonumber(b) <= 30 and tonumber(a) == 0 then
                remaining = tonumber(b)
            end
        end
    end

    remaining = normalize_seconds(remaining)
    local gcd = normalize_seconds(gcd_remaining)
    if gcd > remaining then
        remaining = gcd
    end
    return remaining
end

local SWING_REMAINING_METHODS = {
    "get_main_hand_swing_time_remaining",
    "get_main_hand_swing_remaining",
    "get_swing_time_remaining",
    "get_melee_swing_time_remaining",
    "get_auto_attack_time_remaining",
    "get_attack_cooldown_remaining",
}

---@private
---@param player game_object|nil
---@return number
local function resolve_melee_swing_remaining(player)
    if not player then
        return 0
    end

    for i = 1, #SWING_REMAINING_METHODS do
        local value = safe_unit_call(player, SWING_REMAINING_METHODS[i])
        if type(value) == "table" then
            value = tonumber(value.remaining)
                or tonumber(value.time_left)
                or tonumber(value.left)
                or tonumber(value.duration)
        end
        local normalized = normalize_seconds(value)
        if normalized > 0 then
            return normalized
        end
    end

    return 0
end

---@private
---@param player game_object|nil
---@return number
local function resolve_player_move_speed(player)
    if not player then
        return 7.0
    end

    local speed = to_number(safe_unit_call(player, "get_movement_speed"))
    if speed == nil or speed <= 0 then
        return 7.0
    end
    return speed
end

---@private
---@param unit game_object|nil
---@param spec any
---@return boolean
local function unit_has_aura(unit, spec)
    if not unit or spec == nil then
        return false
    end

    if type(spec) == "table" then
        for i = 1, #spec do
            if unit_has_aura(unit, spec[i]) then
                return true
            end
        end
        return false
    end

    if unit.has_aura then
        local ok, up = pcall(unit.has_aura, unit, spec)
        if ok and up == true then
            return true
        end
    end

    if unit.has_buff then
        local ok, up = pcall(unit.has_buff, unit, spec)
        if ok and up == true then
            return true
        end
    end

    if unit.has_debuff then
        local ok, up = pcall(unit.has_debuff, unit, spec)
        if ok and up == true then
            return true
        end
    end

    return false
end

---@private
---@param unit game_object|nil
---@param spec any
---@return number
local function unit_aura_remaining(unit, spec)
    if not unit or spec == nil then
        return 0
    end

    if type(spec) == "table" then
        local best = 0
        for i = 1, #spec do
            local r = unit_aura_remaining(unit, spec[i])
            if r > best then
                best = r
            end
        end
        return best
    end

    local remaining_methods = {
        "get_debuff_remaining", "get_buff_remaining",
        "get_aura_remaining",
    }
    for i = 1, #remaining_methods do
        local value = safe_unit_call(unit, remaining_methods[i], spec)
        local n = normalize_seconds(value)
        if n > 0 then
            return n
        end
    end

    local obj_methods = { "get_debuff", "get_buff", "get_aura" }
    for i = 1, #obj_methods do
        local obj = safe_unit_call(unit, obj_methods[i], spec)
        if type(obj) == "table" then
            local r = normalize_seconds(obj.remaining or obj.time_left or obj.duration_left or obj.expires_at)
            if r > 0 then
                return r
            end
        end
    end

    if unit_has_aura(unit, spec) then
        return 999
    end
    return 0
end

---@private
---@param player game_object|nil
---@param enums table|nil
---@return table
local function resolve_consuming_state(player, enums)
    local buff_db = enums and enums.buff_db or nil
    if buff_db == nil then
        return {
            eating = false,
            drinking = false,
            either = false,
        }
    end

    local eating = buff_db.EATING and unit_has_aura(player, buff_db.EATING) or false
    local drinking = buff_db.DRINKING and unit_has_aura(player, buff_db.DRINKING) or false
    local either = buff_db.EATING_OR_DRINKING and unit_has_aura(player, buff_db.EATING_OR_DRINKING) or false

    return {
        eating = eating == true,
        drinking = drinking == true,
        either = either == true or eating == true or drinking == true,
    }
end

---@private
---@param blackboard Blackboard|nil
---@param now number
---@param kind? string
---@return number
local function resolve_rest_lock_until(blackboard, now, kind)
    if not blackboard or type(blackboard.get) ~= "function" then
        return 0
    end
    local key = "rotation.rest.lock_until"
    local normalized_kind = string.lower(tostring(kind or ""))
    if normalized_kind ~= "" then
        key = key .. "." .. normalized_kind
    end
    local lock_until = tonumber(blackboard:get(key, 0)) or 0
    if lock_until <= now then
        return 0
    end
    return lock_until
end

local CREATURE_TYPE_ID = {
    HUMANOID = 7,
    DEMON = 3,
    UNDEAD = 6,
}

---@private
---@param value any
---@return string|nil
local function normalize_creature_type_name(value)
    if type(value) ~= "string" then
        return nil
    end

    local lowered = string.lower(value)
    if lowered == "" then
        return nil
    end
    return lowered
end

---@private
---@param unit game_object|nil
---@return number|nil
---@return string|nil
local function resolve_creature_type(unit)
    if not unit then
        return nil, nil
    end

    if safe_unit_call(unit, "is_undead") == true then
        return CREATURE_TYPE_ID.UNDEAD, "undead"
    end
    if safe_unit_call(unit, "is_demon") == true then
        return CREATURE_TYPE_ID.DEMON, "demon"
    end

    local id = nil
    local name = nil

    local methods = {
        "get_creature_type",
        "get_creature_type_id",
        "get_unit_type",
    }
    for i = 1, #methods do
        local value = safe_unit_call(unit, methods[i])
        if type(value) == "number" and id == nil then
            id = tonumber(value)
        elseif type(value) == "string" and name == nil then
            name = normalize_creature_type_name(value)
        elseif type(value) == "table" then
            if id == nil then
                id = tonumber(value.id or value.type_id or value.creature_type)
            end
            if name == nil then
                name = normalize_creature_type_name(value.name or value.type or value.creature_type_name)
            end
        end
    end

    if name == nil then
        name = normalize_creature_type_name(safe_unit_call(unit, "get_creature_type_name"))
    end

    return id, name
end

---@private
---@param unit game_object|nil
---@return boolean
---@return boolean
---@return number|nil
---@return string|nil
local function resolve_cast_state(unit)
    if not unit then
        return false, false, nil, nil
    end

    local casting = safe_unit_call(unit, "is_casting_spell") == true
    local channeling = safe_unit_call(unit, "is_channelling_spell") == true
        or safe_unit_call(unit, "is_channeling_spell") == true

    local cast_spell_id = nil
    local cast_spell_name = nil

    local direct_methods = {
        "get_casting_spell_id",
        "get_current_cast_spell_id",
        "get_cast_spell_id",
        "get_channel_spell_id",
        "get_current_channel_spell_id",
        "get_spell_cast_id",
    }
    for i = 1, #direct_methods do
        local value = safe_unit_call(unit, direct_methods[i])
        local numeric = tonumber(value)
        if numeric and numeric > 0 then
            cast_spell_id = numeric
            break
        end
    end

    local detail_methods = {
        "get_casting_spell",
        "get_current_cast_spell",
        "get_channel_spell",
        "get_current_channel_spell",
        "get_active_spell",
    }
    for i = 1, #detail_methods do
        local value = safe_unit_call(unit, detail_methods[i])
        if type(value) == "table" then
            if cast_spell_id == nil then
                local numeric = tonumber(value.spell_id or value.id or value.entry)
                if numeric and numeric > 0 then
                    cast_spell_id = numeric
                end
            end
            if cast_spell_name == nil and type(value.name) == "string" and value.name ~= "" then
                cast_spell_name = value.name
            end
        elseif cast_spell_name == nil and type(value) == "string" and value ~= "" then
            cast_spell_name = value
        end
    end

    local name_methods = {
        "get_casting_spell_name",
        "get_current_cast_spell_name",
        "get_channel_spell_name",
        "get_current_channel_spell_name",
    }
    if cast_spell_name == nil then
        for i = 1, #name_methods do
            local value = safe_unit_call(unit, name_methods[i])
            if type(value) == "string" and value ~= "" then
                cast_spell_name = value
                break
            end
        end
    end

    return casting, channeling, cast_spell_id, cast_spell_name
end

---@private
---@param creature_type_id number|nil
---@param creature_type_name string|nil
---@param wanted string
---@return boolean
local function creature_type_matches(creature_type_id, creature_type_name, wanted)
    local key = string.upper(tostring(wanted or ""))
    if key == "" then
        return false
    end

    local normalized_name = normalize_creature_type_name(creature_type_name)
    if normalized_name and string.find(normalized_name, string.lower(key), 1, true) ~= nil then
        return true
    end

    local wanted_id = CREATURE_TYPE_ID[key]
    if wanted_id and tonumber(creature_type_id) == wanted_id then
        return true
    end

    return false
end

---@param deps table
---@return table
function CombatContext:build(deps)
    deps = deps or {}
    local bb = self._blackboard

    local player = bb:get("player.object")
    local target = bb:get("combat.target")
    if safe_unit_call(player, "is_valid") ~= true then
        player = nil
    end
    if safe_unit_call(target, "is_valid") ~= true then
        target = nil
    end

    local player_pos = bb:get("player.position")
    local target_pos = safe_unit_call(target, "get_position")

    local helpers = deps.helpers or {}
    local unit_helper = helpers.unit_helper
    local distance_3d = helpers.distance_3d
    local spellbook = deps.spellbook
    local enums = deps.enums

    local mana_type = enums and enums.power_type and enums.power_type.MANA or 0

    local player_health_pct = resolve_health_pct(player, unit_helper)
    local target_health_pct = resolve_health_pct(target, unit_helper)
    local player_mana_pct = resolve_mana_pct(player, unit_helper, mana_type)

    local target_distance = nil
    if distance_3d then
        target_distance = distance_3d(player_pos, target_pos)
    end

    local target_is_casting, target_is_channeling, target_cast_spell_id, target_cast_spell_name = resolve_cast_state(target)
    local _, player_is_channeling_flag = resolve_cast_state(player)
    local target_creature_type_id, target_creature_type_name = resolve_creature_type(target)
    local target_is_demon = creature_type_matches(target_creature_type_id, target_creature_type_name, "demon")
    local target_is_undead = creature_type_matches(target_creature_type_id, target_creature_type_name, "undead")
    local target_is_player = safe_unit_call(target, "is_player") == true
        or safe_unit_call(target, "is_player_unit") == true
    local player_is_moving = resolve_player_moving(player)
    local player_move_speed = resolve_player_move_speed(player)
    local gcd_remaining = resolve_global_cooldown_remaining()
    local melee_swing_remaining = resolve_melee_swing_remaining(player)
    local melee_swing_window_open = melee_swing_remaining > 0.8
    local melee_twist_window = melee_swing_remaining > 0 and melee_swing_remaining <= 0.4
    local now = get_now()
    local rest_lock_until = resolve_rest_lock_until(bb, now)
    local rest_lock_food_until = resolve_rest_lock_until(bb, now, "food")
    local rest_lock_water_until = resolve_rest_lock_until(bb, now, "water")
    local consuming = resolve_consuming_state(player, enums)
    local player_is_eating = consuming.eating == true or rest_lock_food_until > now
    local player_is_drinking = consuming.drinking == true or rest_lock_water_until > now
    local eating_or_drinking = consuming.either == true
        or player_is_eating
        or player_is_drinking
        or rest_lock_until > now

    local in_combat = bb:get("player.in_combat", false)
    local player_combat_duration = 0
    if in_combat then
        local entered_at = tonumber(bb:get("combat.entered_at", 0)) or 0
        if entered_at > 0 then
            player_combat_duration = math.max(0, now - entered_at)
        end
    end

    local active_dot_count = 0
    local dot_aura_ids = deps.dot_aura_ids
    if target and type(dot_aura_ids) == "table" then
        for i = 1, #dot_aura_ids do
            if unit_has_aura(target, dot_aura_ids[i]) then
                active_dot_count = active_dot_count + 1
            end
        end
    end

    -- Player CC state
    local player_is_stunned = safe_unit_call(player, "is_stunned") == true
    local player_is_rooted = safe_unit_call(player, "is_rooted") == true
    local player_is_silenced = safe_unit_call(player, "is_silenced") == true
    local player_is_feared = safe_unit_call(player, "is_feared") == true
    local player_is_casting = safe_unit_call(player, "is_casting_spell") == true

    -- Player stats
    local player_attack_speed = to_number(safe_unit_call(player, "get_attack_speed")) or 0

    -- Loss of control
    local player_loss_of_control = safe_unit_call(player, "get_loss_of_control_info")

    -- Target interrupt data
    local target_is_interruptable = safe_unit_call(target, "is_active_spell_interruptable") == true
    local target_active_spell_id = to_number(safe_unit_call(target, "get_active_spell_id"))

    -- Target cast timing
    local target_cast_remaining_sec = 0
    local target_cast_end = to_number(safe_unit_call(target, "get_active_spell_cast_end_time"))
    if target_cast_end and target_cast_end > 0 then
        target_cast_remaining_sec = normalize_seconds(math.max(0, target_cast_end - now))
    end
    local target_cast_progress = 0
    local target_cast_start = to_number(safe_unit_call(target, "get_active_spell_cast_start_time"))
    if target_cast_start and target_cast_end and target_cast_end > target_cast_start then
        target_cast_progress = math.max(0, math.min(1.0, (now - target_cast_start) / (target_cast_end - target_cast_start)))
    end

    -- Target TTD (izi_sdk)
    local target_ttd_seconds = nil
    if target then
        local ttd = to_number(safe_unit_call(target, "time_to_die"))
        if ttd and ttd >= 0 then
            target_ttd_seconds = ttd
        end
    end

    -- Player aura remaining
    local function player_aura_remaining(spec)
        return unit_aura_remaining(player, spec)
    end

    local function player_has_aura(spec)
        return unit_has_aura(player, spec)
    end

    local function target_has_aura(spec)
        return unit_has_aura(target, spec)
    end

    local function target_aura_remaining(spec)
        return unit_aura_remaining(target, spec)
    end

    local function target_is_creature_type(spec)
        if type(spec) ~= "string" then
            return false
        end
        return creature_type_matches(target_creature_type_id, target_creature_type_name, spec)
    end

    local pet = safe_unit_call(player, "get_pet")
    local pet_valid = safe_unit_call(pet, "is_valid") == true
        and safe_unit_call(pet, "is_dead") ~= true
    if not pet_valid then
        pet = nil
    end
    local pet_health_pct = resolve_health_pct(pet, unit_helper)

    local function resolve_spell_id(name, fallback_ids)
        if spellbook and spellbook.best_rank then
            return spellbook:best_rank(name, fallback_ids)
        end
        return nil
    end

    local function spell_cooldown_remaining(spell_id)
        return resolve_spell_cooldown_remaining(spell_id, gcd_remaining)
    end

    return {
        player = player,
        target = target,
        player_position = player_pos,
        target_position = target_pos,
        class_id = bb:get("player.class_id", 0),
        spec_id = bb:get("player.spec_id", 0),
        enemy_count = bb:get("combat.enemy_count", 1),
        combat_state = bb:get("combat.state", "idle"),
        in_combat = in_combat,
        now = now,
        player_health_pct = player_health_pct,
        player_mana_pct = player_mana_pct,
        target_health_pct = target_health_pct,
        target_distance = target_distance,
        target_is_casting = target_is_casting,
        target_is_channeling = target_is_channeling,
        target_is_casting_or_channeling = target_is_casting or target_is_channeling,
        target_cast_spell_id = target_cast_spell_id,
        target_cast_spell_name = target_cast_spell_name,
        target_is_player = target_is_player,
        target_creature_type_id = target_creature_type_id,
        target_creature_type_name = target_creature_type_name,
        target_is_demon = target_is_demon,
        target_is_undead = target_is_undead,
        target_is_undead_or_demon = target_is_demon or target_is_undead,
        player_is_moving = player_is_moving,
        player_move_speed = player_move_speed,
        global_cooldown_remaining = gcd_remaining,
        melee_swing_remaining = melee_swing_remaining,
        melee_swing_window_open = melee_swing_window_open,
        melee_twist_window = melee_twist_window,
        player_is_channeling = player_is_channeling_flag == true,
        player_combat_duration = player_combat_duration,
        active_dot_count = active_dot_count,
        player_is_eating = player_is_eating,
        player_is_drinking = player_is_drinking,
        eating_or_drinking = eating_or_drinking,
        rest_lock_until = rest_lock_until,
        rest_lock_food_until = rest_lock_food_until,
        rest_lock_water_until = rest_lock_water_until,
        routine_policy = bb:get("rotation.policy"),
        player_has_aura = player_has_aura,
        target_has_aura = target_has_aura,
        target_aura_remaining = target_aura_remaining,
        target_is_creature_type = target_is_creature_type,
        pet = pet,
        pet_health_pct = pet_health_pct,
        resolve_spell_id = resolve_spell_id,
        spell_cooldown_remaining = spell_cooldown_remaining,
        player_is_stunned = player_is_stunned,
        player_is_rooted = player_is_rooted,
        player_is_silenced = player_is_silenced,
        player_is_feared = player_is_feared,
        player_is_casting = player_is_casting,
        player_attack_speed = player_attack_speed,
        player_loss_of_control = player_loss_of_control,
        target_is_interruptable = target_is_interruptable,
        target_active_spell_id = target_active_spell_id,
        target_cast_remaining_sec = target_cast_remaining_sec,
        target_cast_progress = target_cast_progress,
        target_ttd_seconds = target_ttd_seconds,
        player_aura_remaining = player_aura_remaining,
    }
end

return CombatContext
