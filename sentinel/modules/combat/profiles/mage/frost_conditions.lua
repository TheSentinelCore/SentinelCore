local AuraCatalog = require("modules/combat/aura_catalog")

local Cond = {}
local _spell_helper_ref = nil
local _spell_helper_resolved = false
local _spell_helper_call_style = "self"

local function num(value)
    return tonumber(value) or 0
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function player_and_target(blackboard)
    return blackboard:get("player.object"), blackboard:get("combat.target") or blackboard:get("player.target")
end

local function resolve_spell_helper()
    if spell_helper then
        _spell_helper_ref = spell_helper
        _spell_helper_resolved = true
        _spell_helper_call_style = "self"
        return _spell_helper_ref
    end
    if not _spell_helper_resolved then
        local ok, mod = pcall(require, "common/utility/spell_helper")
        if ok and mod then
            _spell_helper_ref = mod
            _spell_helper_call_style = "plain"
        end
        _spell_helper_resolved = true
    end
    return _spell_helper_ref
end

local function call_helper(fn, owner, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    if _spell_helper_call_style == "plain" then
        local ok, value = pcall(fn, ...)
        if ok then
            return true, value
        end
    end
    local ok, value = pcall(fn, owner, ...)
    if ok then
        return true, value
    end
    if _spell_helper_call_style ~= "plain" then
        return pcall(fn, ...)
    end
    return false, nil
end

local function spell_id_for(blackboard, spell_key, mode)
    local catalog = blackboard:get("module.combat.catalog")
    if not catalog then
        return nil
    end
    if mode == "lowest" then
        return catalog:resolve_lowest_rank(spell_key)
    end
    return catalog:resolve_best_rank(spell_key)
end

-- ---------------------------------------------------------------------------
-- Aura IDs for buff checking
-- ---------------------------------------------------------------------------
local frost_armor_aura_ids = { 168, 7300, 7301 }
local ice_armor_aura_ids = { 7302, 7320, 10219, 10220, 27124 }
local arcane_intellect_aura_ids = { 1459, 1460, 1461, 10156, 10157, 27126 }

-- ---------------------------------------------------------------------------
-- Closures (return a function)
-- ---------------------------------------------------------------------------

function Cond.health_below(threshold)
    return function(blackboard)
        return num(blackboard:get("player.health_pct", 0)) < threshold
    end
end

function Cond.mana_below(threshold)
    return function(blackboard)
        return num(blackboard:get("player.mana_pct", 0)) < threshold
    end
end

function Cond.health_above(threshold)
    return function(blackboard)
        return num(blackboard:get("player.health_pct", 0)) > threshold
    end
end

function Cond.mana_above(threshold)
    return function(blackboard)
        return num(blackboard:get("player.mana_pct", 0)) > threshold
    end
end

function Cond.level_at_least(level)
    return function(blackboard)
        return num(blackboard:get("player.level", 0)) >= level
    end
end

function Cond.enemies_in_melee(min_count)
    return function(blackboard)
        return num(blackboard:get("combat.enemy_count_10yd", 0)) >= min_count
    end
end

function Cond.spell_ready(spell_key, mode, cast_target)
    return function(blackboard)
        local player, target = player_and_target(blackboard)
        local spell_id = spell_id_for(blackboard, spell_key, mode)
        local cooldowns = blackboard:get("module.combat.cooldowns")
        if not spell_id or not cooldowns or not cooldowns:spell_ready(spell_id) then
            return false
        end
        local helper = resolve_spell_helper()
        if not helper or type(helper.is_spell_castable) ~= "function" then
            return true
        end
        local source = player
        local dest = cast_target == "self" and player or (target or player)
        local ok, castable = call_helper(helper.is_spell_castable, helper, spell_id, source, dest, true, true)
        return ok and castable == true
    end
end

-- ---------------------------------------------------------------------------
-- Direct functions (take blackboard directly)
-- ---------------------------------------------------------------------------

function Cond.gcd_ready(blackboard)
    local cooldowns = blackboard:get("module.combat.cooldowns")
    return cooldowns and cooldowns:is_gcd_ready(blackboard:get("system.now_ms", 0)) or false
end

function Cond.not_in_combat(blackboard)
    return blackboard:get("player.in_combat", false) == false
end

function Cond.in_combat(blackboard)
    return blackboard:get("player.in_combat", false) == true
end

function Cond.target_valid(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
end

function Cond.target_casting_interruptible(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_casting, casting = safe_call(target, "is_casting_spell")
    local ok_channel, channeling = safe_call(target, "is_channelling_spell")
    if (ok_casting and casting == true) or (ok_channel and channeling == true) then
        local ok_interruptible, interruptible = safe_call(target, "is_active_spell_interruptable")
        return not ok_interruptible or interruptible == true
    end
    return false
end

function Cond.player_is_moving(blackboard)
    return blackboard:get("player.is_moving", false) == true
end

-- ---------------------------------------------------------------------------
-- Aura conditions
-- ---------------------------------------------------------------------------

function Cond.missing_frost_armor(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, frost_armor_aura_ids)
end

function Cond.missing_ice_armor(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, ice_armor_aura_ids)
end

function Cond.missing_arcane_intellect(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, arcane_intellect_aura_ids)
end

return Cond
