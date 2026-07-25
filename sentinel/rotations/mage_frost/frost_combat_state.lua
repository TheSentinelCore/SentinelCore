local API = require("rotations/mage_frost/sentinel_api")

local AuraCatalog = setmetatable({}, { __index = function(_, k)
    local c = API.catalogs
    return c and c.aura and c.aura[k] or nil
end })

local FrostCombatState = {}
FrostCombatState.__index = FrostCombatState

-- Fire Blast base damage per spell ID (min only, conservative for kill-secure)
local FIRE_BLAST_BASE = {
    [2136] = 24, [2137] = 57, [2138] = 103, [8412] = 168,
    [8413] = 242, [10197] = 332, [10199] = 431, [27078] = 539, [27079] = 664,
}

-- Ice Lance base damage (single rank in TBC)
local ICE_LANCE_BASE = { [30455] = 161 }

-- Mana gem item IDs (worst to best)
local MANA_GEM_ITEMS = { 5514, 5513, 8007, 8008, 22044 }

-- Conjure spell to gem item mapping (for rank resolution)
local CONJURE_TO_GEM = {
    [759]   = 5514,  -- Mana Agate
    [3552]  = 5513,  -- Mana Jade
    [10053] = 8007,  -- Mana Citrine
    [10054] = 8008,  -- Mana Ruby
    [27101] = 22044, -- Mana Emerald
}

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function num(value)
    return tonumber(value) or 0
end

function FrostCombatState:new(blackboard)
    local o = setmetatable({}, FrostCombatState)
    o._bb = blackboard
    return o
end

function FrostCombatState:refresh(blackboard)
    local bb = blackboard or self._bb
    local target = bb:get("combat.target") or bb:get("player.target")
    local player = bb:get("player.object")

    self:_refresh_frozen(bb, target)
    self:_refresh_kill_secure(bb, target)
    self:_refresh_cast_analysis(bb, player, target)
    self:_refresh_aoe_decision(bb)
    self:_refresh_spellsteal(bb, target)
    self:_refresh_pvp_classification(bb, target)
    self:_refresh_mana_gem(bb, player)
    self:_refresh_water_elemental(bb, player)
    self:_refresh_low_health_add(bb, player, target)
    self:_refresh_emergency_escape(bb, player)

    local pet_ctrl = bb:get("module.combat.pet_controller")
    if pet_ctrl then
        pet_ctrl:refresh(bb)
    end
end

-- ---------------------------------------------------------------------------
-- Frozen detection
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_frozen(bb, target)
    if not target then
        bb:set("combat.target_frozen", false)
        return
    end
    local frozen = AuraCatalog.has_any_debuff(target, AuraCatalog.all_frozen_debuffs)
    bb:set("combat.target_frozen", frozen)
end

-- ---------------------------------------------------------------------------
-- Kill-secure: can an instant spell finish the target?
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_kill_secure(bb, target)
    if not target then
        bb:set("combat.target_killable_instant", false)
        return
    end

    local ok_hp, hp = safe_call(target, "get_health")
    if not ok_hp or not hp or hp <= 0 then
        bb:set("combat.target_killable_instant", false)
        return
    end

    -- Use TTD if available for more accurate kill-secure detection
    local izi_bridge = bb:get("module.combat.izi_bridge")
    if izi_bridge then
        local ttd = izi_bridge:get_time_to_die(target)
        if ttd and ttd < 0.3 then
            bb:set("combat.target_killable_instant", true)
            return
        end
    end

    local catalog = bb:get("module.combat.catalog")
    if not catalog then
        bb:set("combat.target_killable_instant", false)
        return
    end

    -- Check Fire Blast
    local fb_id = catalog:resolve_best_rank("fire_blast")
    if fb_id and FIRE_BLAST_BASE[fb_id] and FIRE_BLAST_BASE[fb_id] >= hp then
        bb:set("combat.target_killable_instant", true)
        return
    end

    -- Check Ice Lance (3x if frozen)
    local il_id = catalog:resolve_best_rank("ice_lance")
    if il_id and ICE_LANCE_BASE[il_id] then
        local frozen = bb:get("combat.target_frozen", false)
        local il_dmg = ICE_LANCE_BASE[il_id] * (frozen and 3 or 1)
        if il_dmg >= hp then
            bb:set("combat.target_killable_instant", true)
            return
        end
    end

    bb:set("combat.target_killable_instant", false)
end

-- ---------------------------------------------------------------------------
-- Cast analysis: should we cancel current cast?
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_cast_analysis(bb, player, target)
    bb:set("combat.should_cancel_cast", false)
    bb:set("combat.cast_overkill", false)

    if not player or bb:get("player.is_casting", false) ~= true then
        return
    end

    if not target then
        return
    end

    -- Remaining cast time
    local ok_end, cast_end = safe_call(player, "get_active_spell_cast_end_time")
    local now_ms = bb:get("system.now_ms", 0)
    if not ok_end or not cast_end then
        return
    end
    local remaining_ms = num(cast_end) - num(now_ms)
    if remaining_ms <= 0 then
        return
    end
    local remaining_s = remaining_ms / 1000

    -- Check overkill: target will die before cast completes
    local ok_ttd, ttd = safe_call(target, "time_to_die")
    if ok_ttd and ttd and num(ttd) > 0 and num(ttd) < remaining_s then
        bb:set("combat.cast_overkill", true)
    end

    -- Check enemy closing: will reach melee before cast completes?
    local ok_dist, predicted_dist = safe_call(target, "predict_distance", remaining_s)
    if ok_dist and predicted_dist and num(predicted_dist) < 5 then
        -- Only flag if we have Frost Nova available to follow up
        local catalog = bb:get("module.combat.catalog")
        local cooldowns = bb:get("module.combat.cooldowns")
        if catalog and cooldowns then
            local nova_id = catalog:resolve_best_rank("frost_nova")
            if nova_id and cooldowns:spell_ready(nova_id) then
                bb:set("combat.should_cancel_cast", true)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- AoE decision
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_aoe_decision(bb)
    local enemy_count = num(bb:get("combat.enemy_count_10yd", 0))
    local level = num(bb:get("player.level", 0))
    bb:set("combat.use_aoe_rotation", enemy_count >= 3 and level >= 20)
end

-- ---------------------------------------------------------------------------
-- Spellsteal detection: target has a stealable magic buff
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_spellsteal(bb, target)
    if not target then
        bb:set("combat.target_has_stealable_buff", false)
        return
    end

    local ok_buffs, buffs = safe_call(target, "get_buffs")
    if not ok_buffs or type(buffs) ~= "table" then
        bb:set("combat.target_has_stealable_buff", false)
        return
    end

    for _, buff in ipairs(buffs) do
        -- type 1 = magic in the buff struct
        if tonumber(buff.type) == 1 then
            bb:set("combat.target_has_stealable_buff", true)
            return
        end
    end

    bb:set("combat.target_has_stealable_buff", false)
end

-- ---------------------------------------------------------------------------
-- PvP target classification
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_pvp_classification(bb, target)
    bb:set("combat.target_is_player", false)
    bb:set("combat.target_is_caster", false)
    bb:set("combat.target_is_healer", false)

    if not target then
        return
    end

    local ok_player, is_player = safe_call(target, "is_player")
    if not ok_player or is_player ~= true then
        return
    end

    bb:set("combat.target_is_player", true)

    -- Healer detection: group role or class heuristic
    local ok_role, role = safe_call(target, "get_group_role")
    if ok_role and num(role) == 1 then
        bb:set("combat.target_is_healer", true)
        bb:set("combat.target_is_caster", true)
        return
    end

    -- Caster detection: has mana
    local ok_power, max_mana = safe_call(target, "get_max_power", 0)
    if ok_power and num(max_mana) > 0 then
        bb:set("combat.target_is_caster", true)

        -- Healer class heuristic: priests (5), druids (11), paladins (2), shamans (7)
        local ok_class, class_id = safe_call(target, "get_class")
        if ok_class then
            local healer_classes = { [5] = true, [11] = true, [2] = true, [7] = true }
            if healer_classes[num(class_id)] then
                bb:set("combat.target_is_healer", true)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Mana gem inventory check
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_mana_gem(bb, player)
    if not player then
        bb:set("combat.has_mana_gem", false)
        return
    end

    for i = #MANA_GEM_ITEMS, 1, -1 do
        local ok, has = safe_call(player, "has_item", MANA_GEM_ITEMS[i])
        if ok and has then
            bb:set("combat.has_mana_gem", true)
            bb:set("combat.mana_gem_item_id", MANA_GEM_ITEMS[i])
            return
        end
    end

    bb:set("combat.has_mana_gem", false)
    bb:set("combat.mana_gem_item_id", nil)
end

-- ---------------------------------------------------------------------------
-- Water Elemental pet check
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_water_elemental(bb, player)
    if not player then
        bb:set("combat.has_water_elemental", false)
        return
    end
    local ok_pet, pet = safe_call(player, "get_pet")
    if ok_pet and pet then
        local ok_alive, alive = safe_call(pet, "is_alive")
        bb:set("combat.has_water_elemental", ok_alive and alive == true)
    else
        bb:set("combat.has_water_elemental", false)
    end
end

-- ---------------------------------------------------------------------------
-- Low-health add detection: find a nearly-dead secondary enemy to finish off
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_low_health_add(bb, player, target)
    bb:set("combat.low_health_add", nil)
    if not player then return end

    local ok_enemies, enemies = safe_call(player, "get_enemies_in_range", 20)
    if not ok_enemies or type(enemies) ~= "table" then return end

    local best_add = nil
    local best_hp_pct = 1.0

    for _, enemy in ipairs(enemies) do
        local dominated = false

        -- Skip primary target
        if not dominated and target then
            local ok_ga, guid_a = safe_call(enemy, "get_guid")
            local ok_gb, guid_b = safe_call(target, "get_guid")
            if ok_ga and ok_gb and tostring(guid_a) == tostring(guid_b) then
                dominated = true
            end
        end

        -- Skip dead
        if not dominated then
            local ok_dead, dead = safe_call(enemy, "is_dead")
            if ok_dead and dead == true then dominated = true end
        end

        if not dominated then
            local ok_hp, hp = safe_call(enemy, "get_health")
            local ok_max, max_hp = safe_call(enemy, "get_max_health")
            if ok_hp and ok_max and hp and max_hp and num(max_hp) > 0 then
                local pct = num(hp) / num(max_hp)
                if pct > 0 and pct < 0.20 and pct < best_hp_pct then
                    best_hp_pct = pct
                    best_add = enemy
                end
            end
        end
    end

    bb:set("combat.low_health_add", best_add)
end

-- ---------------------------------------------------------------------------
-- Emergency escape: all defensives exhausted, must hard flee
-- ---------------------------------------------------------------------------
function FrostCombatState:_refresh_emergency_escape(bb, player)
    bb:set("combat.can_emergency_escape", false)
    if not player then return end

    local hp_pct = num(bb:get("player.health_pct", 1))
    if hp_pct >= 0.15 then return end

    -- Ice Block available → not an emergency
    local catalog = bb:get("module.combat.catalog")
    local cooldowns = bb:get("module.combat.cooldowns")
    if catalog and cooldowns then
        local ib_id = catalog:resolve_best_rank("ice_block")
        if ib_id and cooldowns:spell_ready(ib_id) then
            return
        end
    end

    -- Usable health potion available → not an emergency
    if bb:get("combat.has_health_potion") == true then
        local now = bb:get("system.now_ms", 0)
        local cd = bb:get("combat.potion_cd_until_ms", 0)
        if now >= cd then
            return
        end
    end

    bb:set("combat.can_emergency_escape", true)
end

-- ---------------------------------------------------------------------------
-- Reset all state keys
-- ---------------------------------------------------------------------------
function FrostCombatState:reset()
    local bb = self._bb
    bb:set("combat.target_frozen", false)
    bb:set("combat.target_killable_instant", false)
    bb:set("combat.should_cancel_cast", false)
    bb:set("combat.cast_overkill", false)
    bb:set("combat.use_aoe_rotation", false)
    bb:set("combat.target_has_stealable_buff", false)
    bb:set("combat.target_is_player", false)
    bb:set("combat.target_is_caster", false)
    bb:set("combat.target_is_healer", false)
    bb:set("combat.has_mana_gem", false)
    bb:set("combat.mana_gem_item_id", nil)
    bb:set("combat.has_water_elemental", false)
    bb:set("combat.kite_state", "NONE")
    bb:set("combat.low_health_add", nil)
    bb:set("combat.can_emergency_escape", false)
    bb:set("combat.emergency_flee", false)
end

-- Expose constants for other modules
FrostCombatState.MANA_GEM_ITEMS = MANA_GEM_ITEMS
FrostCombatState.CONJURE_TO_GEM = CONJURE_TO_GEM

return FrostCombatState
