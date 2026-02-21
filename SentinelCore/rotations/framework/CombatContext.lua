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
    if unit and unit_helper and unit_helper.get_resource_percentage and mana_type ~= nil then
        local ok, pct = pcall(unit_helper.get_resource_percentage, unit_helper, unit, mana_type)
        if ok then
            local normalized = normalize_pct(pct)
            if normalized ~= nil then
                return normalized
            end
        end
    end

    if unit and mana_type ~= nil then
        local mana = to_number(safe_unit_call(unit, "get_power", mana_type)) or 0
        local mana_max = to_number(safe_unit_call(unit, "get_max_power", mana_type)) or mana
        mana_max = math.max(1, mana_max)
        return normalize_pct(mana / mana_max)
    end

    return nil
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
    local player_is_moving = resolve_player_moving(player)
    local eating_or_drinking = resolve_eating_or_drinking(player, enums)

    local function player_has_aura(spec)
        return unit_has_aura(player, spec)
    end

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
        now = (core and core.time and core.time()) or 0,
        player_health_pct = player_health_pct,
        player_mana_pct = player_mana_pct,
        target_health_pct = target_health_pct,
        target_distance = target_distance,
        target_is_casting = target_is_casting,
        player_is_moving = player_is_moving,
        eating_or_drinking = eating_or_drinking,
        routine_policy = bb:get("rotation.policy"),
        player_has_aura = player_has_aura,
        resolve_spell_id = resolve_spell_id,
    }
end

return CombatContext
