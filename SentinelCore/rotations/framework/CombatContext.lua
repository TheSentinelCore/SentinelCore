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
---@param player game_object|nil
---@param enums table|nil
---@return boolean
local function resolve_eating_or_drinking(player, enums)
    local buff_db = enums and enums.buff_db or nil
    if buff_db == nil then
        return false
    end

    if buff_db.EATING_OR_DRINKING and unit_has_aura(player, buff_db.EATING_OR_DRINKING) then
        return true
    end

    if buff_db.EATING and unit_has_aura(player, buff_db.EATING) then
        return true
    end

    if buff_db.DRINKING and unit_has_aura(player, buff_db.DRINKING) then
        return true
    end

    return false
end

---@private
---@param blackboard Blackboard|nil
---@param now number
---@return number
local function resolve_rest_lock_until(blackboard, now)
    if not blackboard or type(blackboard.get) ~= "function" then
        return 0
    end
    local lock_until = tonumber(blackboard:get("rotation.rest.lock_until", 0)) or 0
    if lock_until <= now then
        return 0
    end
    return lock_until
end

local CREATURE_TYPE_ID = {
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

    local target_is_casting = safe_unit_call(target, "is_casting_spell") == true
    local target_creature_type_id, target_creature_type_name = resolve_creature_type(target)
    local target_is_demon = creature_type_matches(target_creature_type_id, target_creature_type_name, "demon")
    local target_is_undead = creature_type_matches(target_creature_type_id, target_creature_type_name, "undead")
    local target_is_player = safe_unit_call(target, "is_player") == true
        or safe_unit_call(target, "is_player_unit") == true
    local player_is_moving = resolve_player_moving(player)
    local now = (core and core.time and core.time()) or 0
    local rest_lock_until = resolve_rest_lock_until(bb, now)
    local eating_or_drinking = resolve_eating_or_drinking(player, enums) or rest_lock_until > now

    local function player_has_aura(spec)
        return unit_has_aura(player, spec)
    end

    local function target_has_aura(spec)
        return unit_has_aura(target, spec)
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

    return {
        player = player,
        target = target,
        player_position = player_pos,
        target_position = target_pos,
        class_id = bb:get("player.class_id", 0),
        spec_id = bb:get("player.spec_id", 0),
        enemy_count = bb:get("combat.enemy_count", 1),
        in_combat = bb:get("player.in_combat", false),
        now = now,
        player_health_pct = player_health_pct,
        player_mana_pct = player_mana_pct,
        target_health_pct = target_health_pct,
        target_distance = target_distance,
        target_is_casting = target_is_casting,
        target_is_player = target_is_player,
        target_creature_type_id = target_creature_type_id,
        target_creature_type_name = target_creature_type_name,
        target_is_demon = target_is_demon,
        target_is_undead = target_is_undead,
        target_is_undead_or_demon = target_is_demon or target_is_undead,
        player_is_moving = player_is_moving,
        eating_or_drinking = eating_or_drinking,
        rest_lock_until = rest_lock_until,
        routine_policy = bb:get("rotation.policy"),
        player_has_aura = player_has_aura,
        target_has_aura = target_has_aura,
        target_is_creature_type = target_is_creature_type,
        pet = pet,
        pet_health_pct = pet_health_pct,
        resolve_spell_id = resolve_spell_id,
    }
end

return CombatContext
