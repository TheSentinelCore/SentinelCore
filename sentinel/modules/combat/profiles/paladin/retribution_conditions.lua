local AuraCatalog = require("kernel/catalogs/aura")
local H = require("shared/combat_helpers")
local SpellHelper = require("shared/spell_helper")

local Cond = {}

function Cond.target_valid(blackboard)
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = H.safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
end

function Cond.in_melee(blackboard)
    local player = blackboard:get("player.position")
    local _, target = H.player_and_target(blackboard)
    local ok_target_pos, target_pos = H.safe_call(target, "get_position")
    if type(player) ~= "table" or not ok_target_pos then
        return false
    end
    return H.distance(player, target_pos) <= 5.0
end

function Cond.in_judgement_range(blackboard)
    local player = blackboard:get("player.position")
    local _, target = H.player_and_target(blackboard)
    local ok_target_pos, target_pos = H.safe_call(target, "get_position")
    if type(player) ~= "table" or not ok_target_pos then
        return false
    end
    return H.distance(player, target_pos) <= 10.0
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
        local player, target = H.player_and_target(blackboard)
        local spell_id = H.spell_id_for(blackboard, spell_key, mode)
        local cooldowns = blackboard:get("module.combat.cooldowns")
        if not spell_id or not cooldowns or not cooldowns:spell_ready(spell_id) then
            return false
        end
        local source = player
        local dest = cast_target == "self" and player or (target or player)
        if not SpellHelper.is_spell_castable(spell_id, source, dest) then
            return false
        end
        -- Check line of sight for targeted spells (not self-cast)
        if cast_target ~= "self" and dest and dest ~= source then
            if not SpellHelper.is_spell_in_los(spell_id, source, dest) then
                return false
            end
        end
        return true
    end
end

function Cond.twist_enabled(blackboard)
    return blackboard:get("rotation.twist.enabled", false) == true
        and blackboard:get("rotation.desired_seal", "blood") == "blood"
        and blackboard:get("rotation.active_seal") == "blood"
end

function Cond.twist_window_open(blackboard)
    local remaining_ms = H.num(blackboard:get("combat.swing.remaining_ms", 99999))
    local twist_window_ms = H.num(blackboard:get("module.combat.twist_window_ms", 350))
    return remaining_ms > 0 and remaining_ms <= twist_window_ms
end

function Cond.blood_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "blood"
end

function Cond.command_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "command"
end

function Cond.righteousness_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "righteousness"
end

function Cond.target_execute(blackboard)
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end

    -- Use TTD if available for more reliable execute detection
    local izi_bridge = blackboard:get("module.combat.izi_bridge")
    if izi_bridge then
        local ttd = izi_bridge:get_time_to_die(target)
        if ttd and ttd < 3.0 then
            return true
        end
    end

    -- Fallback to HP% check
    local ok_hp, hp_pct = H.safe_call(target, "get_health_percentage")
    return ok_hp and H.num(hp_pct) <= 0.20
end

function Cond.not_twisting(blackboard)
    return blackboard:get("rotation.twist.pending_reseal", false) ~= true
end

function Cond.aoe_mode(blackboard)
    return H.num(blackboard:get("combat.enemy_count_10yd", 0)) >= 2
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
        return H.num(blackboard:get("player.health_pct", 0)) > threshold
    end
end

function Cond.mana_above(threshold)
    return function(blackboard)
        return H.num(blackboard:get("player.mana_pct", 0)) > threshold
    end
end

function Cond.enemy_count_at_least(count)
    return function(blackboard)
        return H.num(blackboard:get("combat.enemy_count_10yd", 0)) >= count
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
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_casting, casting = H.safe_call(target, "is_casting_spell")
    local ok_channel, channeling = H.safe_call(target, "is_channelling_spell")
    if (ok_casting and casting == true) or (ok_channel and channeling == true) then
        local ok_interruptible, interruptible = H.safe_call(target, "is_active_spell_interruptable")
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

---True when no seal at all is up. Any seal satisfies the baseline — a level-3
---Paladin only has Righteousness, and refusing it would leave the character
---permanently sealless, which in turn kills judgement (active_seal_present).
function Cond.baseline_seal_missing(blackboard)
    return blackboard:get("rotation.active_seal") == nil
end

-- Maps the seal names published on the blackboard to spell catalog keys.
local SEAL_SPELL_KEYS = {
    blood = "seal_of_blood",
    command = "seal_of_command",
    righteousness = "seal_of_righteousness",
}

---True when the level-aware primary seal is known, off cooldown, and castable.
---Replaces the hardcoded spell_ready("seal_of_blood") gate, which could never
---pass below level 64 and so stranded the whole levelling rotation.
function Cond.primary_seal_castable(blackboard)
    local seal = blackboard:get("rotation.primary_seal")
        or blackboard:get("rotation.desired_seal")
    local spell_key = SEAL_SPELL_KEYS[seal]
    if not spell_key then
        return false
    end
    return Cond.spell_ready(spell_key, nil, "self")(blackboard)
end

---True when the seal the rotation wants is not the one currently up.
function Cond.primary_seal_not_active(blackboard)
    local seal = blackboard:get("rotation.primary_seal")
        or blackboard:get("rotation.desired_seal")
    return seal ~= nil and blackboard:get("rotation.active_seal") ~= seal
end

return Cond
