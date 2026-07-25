local AuraCatalog = require("kernel/catalogs/aura")
local H = require("shared/combat_helpers")
local SpellHelper = require("shared/spell_helper")

local Cond = {}

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
        return H.num(blackboard:get("player.health_pct", 0)) < threshold
    end
end

function Cond.mana_below(threshold)
    return function(blackboard)
        return H.num(blackboard:get("player.mana_pct", 0)) < threshold
    end
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

function Cond.level_at_least(level)
    return function(blackboard)
        return H.num(blackboard:get("player.level", 0)) >= level
    end
end

function Cond.enemies_in_melee(min_count)
    return function(blackboard)
        return H.num(blackboard:get("combat.enemy_count_10yd", 0)) >= min_count
    end
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
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = H.safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
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
        return ok_interruptible and interruptible == true
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

function Cond.missing_ice_barrier(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.ice_barrier_auras)
end

function Cond.missing_mana_shield(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.mana_shield_auras)
end

function Cond.missing_water_elemental(blackboard)
    return blackboard:get("combat.has_water_elemental", false) ~= true
end

-- ---------------------------------------------------------------------------
-- Target health closures
-- ---------------------------------------------------------------------------

--- threshold is 0-1 scale; get_health_percentage returns 1-100.
function Cond.target_health_below(threshold)
    return function(blackboard)
        local _, target = H.player_and_target(blackboard)
        if not target then return false end
        local ok, pct = H.safe_call(target, "get_health_percentage")
        return ok and H.num(pct) / 100 < threshold
    end
end

--- threshold is 0-1 scale; get_health_percentage returns 1-100.
function Cond.target_health_above(threshold)
    return function(blackboard)
        local _, target = H.player_and_target(blackboard)
        if not target then return false end
        local ok, pct = H.safe_call(target, "get_health_percentage")
        return ok and H.num(pct) / 100 > threshold
    end
end

-- ---------------------------------------------------------------------------
-- Hostile count closures
-- ---------------------------------------------------------------------------

function Cond.hostile_count_at_least(count, radius)
    return function(blackboard)
        local key = "combat.enemy_count_" .. tostring(radius) .. "yd"
        return H.num(blackboard:get(key, 0)) >= count
    end
end

function Cond.hostile_count_below(count, radius)
    return function(blackboard)
        local key = "combat.enemy_count_" .. tostring(radius) .. "yd"
        return H.num(blackboard:get(key, 0)) < count
    end
end

-- ---------------------------------------------------------------------------
-- Range closures
-- ---------------------------------------------------------------------------

function Cond.target_in_range(range)
    return function(blackboard)
        return H.num(blackboard:get("combat.target_distance", 99999)) <= range
    end
end

-- ---------------------------------------------------------------------------
-- Frozen / kill-secure (read from frost_combat_state)
-- ---------------------------------------------------------------------------

function Cond.target_is_frozen(blackboard)
    return blackboard:get("combat.target_frozen", false) == true
end

function Cond.target_not_frozen(blackboard)
    return blackboard:get("combat.target_frozen", false) ~= true
end

function Cond.target_killable_instant(blackboard)
    return blackboard:get("combat.target_killable_instant", false) == true
end

-- ---------------------------------------------------------------------------
-- Cast analysis (read from frost_combat_state)
-- ---------------------------------------------------------------------------

function Cond.should_cancel_cast(blackboard)
    return blackboard:get("combat.should_cancel_cast", false) == true
end

function Cond.cast_is_overkill(blackboard)
    return blackboard:get("combat.cast_overkill", false) == true
end

function Cond.not_casting_or_channeling(blackboard)
    return blackboard:get("player.is_casting", false) ~= true
        and blackboard:get("player.is_channeling", false) ~= true
end

-- ---------------------------------------------------------------------------
-- Kite state (read from kite_controller via blackboard)
-- ---------------------------------------------------------------------------

function Cond.is_kiting(blackboard)
    local state = blackboard:get("combat.kite_state", "NONE")
    return state ~= "NONE"
end

function Cond.not_kiting(blackboard)
    local state = blackboard:get("combat.kite_state", "NONE")
    return state == "NONE"
end

function Cond.is_running_away(blackboard)
    return blackboard:get("combat.kite_state", "NONE") == "RUNNING_AWAY"
end

function Cond.not_running_away(blackboard)
    return blackboard:get("combat.kite_state", "NONE") ~= "RUNNING_AWAY"
end

-- ---------------------------------------------------------------------------
-- AoE / Spellsteal / Mana gem (read from frost_combat_state)
-- ---------------------------------------------------------------------------

function Cond.should_use_aoe(blackboard)
    return blackboard:get("combat.use_aoe_rotation", false) == true
end

function Cond.target_has_stealable_buff(blackboard)
    return blackboard:get("combat.target_has_stealable_buff", false) == true
end

function Cond.has_mana_gem(blackboard)
    return blackboard:get("combat.has_mana_gem", false) == true
end

function Cond.missing_mana_gem(blackboard)
    return blackboard:get("combat.has_mana_gem", false) ~= true
end

-- ---------------------------------------------------------------------------
-- Potion conditions
-- ---------------------------------------------------------------------------

function Cond.has_health_potion()
    return function(blackboard)
        return blackboard:get("combat.has_health_potion") == true
    end
end

function Cond.has_mana_potion()
    return function(blackboard)
        return blackboard:get("combat.has_mana_potion") == true
    end
end

function Cond.potion_ready()
    return function(blackboard)
        local now = blackboard:get("system.now_ms", 0)
        return now >= (blackboard:get("combat.potion_cd_until_ms", 0))
    end
end

-- ---------------------------------------------------------------------------
-- Pet conditions
-- ---------------------------------------------------------------------------

function Cond.has_pet()
    return function(blackboard)
        return blackboard:get("combat.has_water_elemental") == true
    end
end

function Cond.pet_not_attacking_target()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        local target = blackboard:get("combat.target") or blackboard:get("player.target")
        if not pet_ctrl or not target then return false end
        return not pet_ctrl:already_sent_to(target)
    end
end

function Cond.pet_freeze_useful()
    return function(blackboard)
        if blackboard:get("combat.target_frozen") then return false end
        -- Don't waste pet freeze while kiting (pet could die in Blizzard AoE)
        if blackboard:get("combat.kite_state", "NONE") ~= "NONE" then return false end
        local catalog = blackboard:get("module.combat.catalog")
        local cooldowns = blackboard:get("module.combat.cooldowns")
        if not catalog or not cooldowns then return false end
        local nova_id = catalog:resolve_best_rank("frost_nova")
        if nova_id and cooldowns:spell_ready(nova_id) then return false end
        return true
    end
end

-- ---------------------------------------------------------------------------
-- Safety / defensive checks
-- ---------------------------------------------------------------------------

function Cond.safe_to_evocate(blackboard)
    local enemy_count = H.num(blackboard:get("combat.enemy_count_10yd", 0))
    if enemy_count > 0 then return false end
    if blackboard:get("combat.kite_state", "NONE") ~= "NONE" then return false end

    -- Use health prediction if available for safer evocation check
    local player = blackboard:get("player.object")
    local hp_pct = H.num(blackboard:get("player.health_pct", 0))
    if player then
        local izi_bridge = blackboard:get("module.combat.izi_bridge")
        if izi_bridge then
            local predicted_pct = izi_bridge:predict_hp_pct(player, 6.0)
            if predicted_pct and predicted_pct < 0.30 then
                return false
            end
        end
    end

    if hp_pct < 0.50 then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Add handling (read from frost_combat_state)
-- ---------------------------------------------------------------------------

function Cond.has_low_health_add(blackboard)
    return blackboard:get("combat.low_health_add") ~= nil
end

-- ---------------------------------------------------------------------------
-- Emergency escape (read from frost_combat_state)
-- ---------------------------------------------------------------------------

function Cond.should_emergency_escape(blackboard)
    return blackboard:get("combat.can_emergency_escape", false) == true
end

-- ---------------------------------------------------------------------------
-- PvP classification (read from frost_combat_state)
-- ---------------------------------------------------------------------------

function Cond.target_is_player(blackboard)
    return blackboard:get("combat.target_is_player", false) == true
end

function Cond.target_is_caster(blackboard)
    return blackboard:get("combat.target_is_caster", false) == true
end

function Cond.target_is_healer(blackboard)
    return blackboard:get("combat.target_is_healer", false) == true
end

return Cond
