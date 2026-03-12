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
            _spell_helper_call_style = "self"
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

function Cond.target_valid(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
end

function Cond.in_melee(blackboard)
    local player = blackboard:get("player.position")
    local _, target = player_and_target(blackboard)
    local ok_target_pos, target_pos = safe_call(target, "get_position")
    if type(player) ~= "table" or not ok_target_pos then
        return false
    end
    return distance(player, target_pos) <= 5.0
end

function Cond.in_judgement_range(blackboard)
    local player = blackboard:get("player.position")
    local _, target = player_and_target(blackboard)
    local ok_target_pos, target_pos = safe_call(target, "get_position")
    if type(player) ~= "table" or not ok_target_pos then
        return false
    end
    return distance(player, target_pos) <= 10.0
end

function Cond.active_seal_present(blackboard)
    return blackboard:get("rotation.active_seal") ~= nil
end

function Cond.gcd_ready(blackboard)
    local cooldowns = blackboard:get("module.combat.cooldowns")
    return cooldowns and cooldowns:is_gcd_ready(blackboard:get("system.now_ms", 0)) or false
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

function Cond.twist_enabled(blackboard)
    return blackboard:get("rotation.twist.enabled", false) == true
        and blackboard:get("rotation.desired_seal", "blood") == "blood"
        and blackboard:get("rotation.active_seal") == "blood"
end

function Cond.twist_window_open(blackboard)
    local remaining_ms = num(blackboard:get("combat.swing.remaining_ms", 99999))
    local twist_window_ms = num(blackboard:get("module.combat.twist_window_ms", 350))
    return remaining_ms > 0 and remaining_ms <= twist_window_ms
end

function Cond.blood_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "blood"
end

function Cond.command_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "command"
end

function Cond.target_execute(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_hp, hp_pct = safe_call(target, "get_health_percentage")
    return ok_hp and num(hp_pct) <= 0.20
end

function Cond.not_twisting(blackboard)
    return blackboard:get("rotation.twist.pending_reseal", false) ~= true
end

function Cond.aoe_mode(blackboard)
    return num(blackboard:get("combat.enemy_count_10yd", 0)) >= 2
end

function Cond.burst_enabled(blackboard)
    return blackboard:get("module.combat.enable_burst", true) ~= false
end

function Cond.burst_context(blackboard)
    return blackboard:get("combat.burst_context", false) == true
end

function Cond.in_combat_context(blackboard)
    return blackboard:get("player.in_combat", false) == true
        or tostring(blackboard:get("combat.state", "IDLE") or "IDLE") ~= "IDLE"
end

function Cond.desired_seal_is_blood(blackboard)
    return blackboard:get("rotation.desired_seal") == "blood"
end

function Cond.desired_seal_is_command(blackboard)
    return blackboard:get("rotation.desired_seal") == "command"
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

function Cond.enemy_count_at_least(count)
    return function(blackboard)
        return num(blackboard:get("combat.enemy_count_10yd", 0)) >= count
    end
end

function Cond.after_judgement_reseal(blackboard)
    return blackboard:get("rotation.after_judgement_reseal", false) == true
end

function Cond.twist_reseal_pending(blackboard)
    return blackboard:get("rotation.twist.pending_reseal", false) == true
        and blackboard:get("rotation.twist.swing_rolled", false) == true
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

function Cond.preferred_blessing_is_kings(blackboard)
    return blackboard:get("module.combat.preferred_blessing", "might") == "kings"
end

function Cond.missing_retribution_aura(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.retribution_aura_ranks)
end

function Cond.missing_might(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.blessing_of_might_ranks)
end

function Cond.missing_kings(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.blessing_of_kings)
end

function Cond.baseline_seal_missing(blackboard)
    local desired = blackboard:get("rotation.desired_seal", "blood")
    if desired == "command" then
        return blackboard:get("rotation.active_seal") ~= "command"
    end
    return blackboard:get("rotation.active_seal") ~= "blood"
end

return Cond
