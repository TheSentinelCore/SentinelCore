local AuraCatalog = require("modules/combat/aura_catalog")
local CooldownTracker = require("modules/combat/cooldown_tracker")
local SpellCatalog = require("modules/combat/spell_catalog")
local SwingTracker = require("modules/combat/swing_tracker")

local ConditionLibrary = {}

-- Helper functions
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
        return spell_helper
    end
    local ok, mod = pcall(require, "common/utility/spell_helper")
    if ok and mod then
        spell_helper = mod
        return spell_helper
    end
    return nil
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

local function resolve_spell_helper_cached()
    if _spell_helper_resolved then
        return _spell_helper_ref
    end
    
    if spell_helper then
        _spell_helper_ref = spell_helper
        _spell_helper_resolved = true
        _spell_helper_call_style = "self"
        return _spell_helper_ref
    end
    
    local ok, mod = pcall(require, "common/utility/spell_helper")
    if ok and mod then
        _spell_helper_ref = mod
        _spell_helper_resolved = true
        _spell_helper_call_style = "self"
        return _spell_helper_ref
    end
    
    _spell_helper_resolved = true
    return nil
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

-- ============================================================================
-- BASIC CONDITIONS
-- ============================================================================

--- Health/Mana conditions
function ConditionLibrary.health_below(threshold)
    return function(blackboard)
        return num(blackboard:get("player.health_pct", 0)) < threshold
    end
end

function ConditionLibrary.mana_below(threshold)
    return function(blackboard)
        return num(blackboard:get("player.mana_pct", 0)) < threshold
    end
end

function ConditionLibrary.health_above(threshold)
    return function(blackboard)
        return num(blackboard:get("player.health_pct", 0)) > threshold
    end
end

function ConditionLibrary.mana_above(threshold)
    return function(blackboard)
        return num(blackboard:get("player.mana_pct", 0)) > threshold
    end
end

--- Level check
function ConditionLibrary.level_at_least(level)
    return function(blackboard)
        return num(blackboard:get("player.level", 0)) >= level
    end
end

--- Enemy count conditions (proximity-based)
function ConditionLibrary.enemies_in_melee(min_count)
    return function(blackboard)
        return num(blackboard:get("combat.enemy_count_10yd", 0)) >= min_count
    end
end

function ConditionLibrary.enemies_in_range(min_count, radius)
    return function(blackboard)
        local key = "combat.enemy_count_" .. tostring(radius) .. "yd"
        return num(blackboard:get(key, 0)) >= min_count
    end
end

function ConditionLibrary.enemies_below(max_count, radius)
    return function(blackboard)
        local key = "combat.enemy_count_" .. tostring(radius) .. "yd"
        return num(blackboard:get(key, 0)) < max_count
    end
end

-- ============================================================================
-- TARGET CONDITIONS
-- ============================================================================

function ConditionLibrary.target_valid(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
end

function ConditionLibrary.target_casting_interruptible(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_casting, casting = safe_call(target, "is_casting_spell")
    local ok_channel, channeling = safe_call(target, "is_channelling_spell")
    if (ok_casting and casting == true) or (ok_channel and channeling == true) then
        local ok_interruptible, interruptible = safe_call(target, "is_active_spell_interruptable")
        return ok_interruptible and interruptible == true
    end
    return false
end

function ConditionLibrary.target_in_range(range)
    return function(blackboard)
        return num(blackboard:get("combat.target_distance", 99999)) <= range
    end
end

function ConditionLibrary.target_health_below(threshold)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return false end
        local ok, pct = safe_call(target, "get_health_percentage")
        return ok and num(pct) / 100 < threshold
    end
end

function ConditionLibrary.target_health_above(threshold)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return false end
        local ok, pct = safe_call(target, "get_health_percentage")
        return ok and num(pct) / 100 > threshold
    end
end

-- ============================================================================
-- PLAYER STATE CONDITIONS
-- ============================================================================

function ConditionLibrary.gcd_ready(blackboard)
    local cooldowns = blackboard:get("module.combat.cooldowns")
    return cooldowns and cooldowns:is_gcd_ready(blackboard:get("system.now_ms", 0)) or false
end

function ConditionLibrary.not_in_combat(blackboard)
    return blackboard:get("player.in_combat", false) == false
end

function ConditionLibrary.in_combat(blackboard)
    return blackboard:get("player.in_combat", false) == true
end

function ConditionLibrary.player_is_moving(blackboard)
    return blackboard:get("player.is_moving", false) == true
end

function ConditionLibrary.player_is_casting(blackboard)
    return blackboard:get("player.is_casting", false) == true
end

function ConditionLibrary.player_is_channeling(blackboard)
    return blackboard:get("player.is_channeling", false) == true
end

function ConditionLibrary.not_casting_or_channeling(blackboard)
    return blackboard:get("player.is_casting", false) ~= true
        and blackboard:get("player.is_channeling", false) ~= true
end

-- ============================================================================
-- AURA/BUFF CONDITIONS
-- ============================================================================

function ConditionLibrary.has_buff(buff_id_or_name)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return false end
        return AuraCatalog.has(player, buff_id_or_name)
    end
end

function ConditionLibrary.has_buff_any(buff_ids)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return false end
        return AuraCatalog.has_any(player, buff_ids)
    end
end

function ConditionLibrary.missing_buff(buff_id_or_name)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return true end
        return not AuraCatalog.has(player, buff_id_or_name)
    end
end

function ConditionLibrary.missing_buff_any(buff_ids)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return true end
        return not AuraCatalog.has_any(player, buff_ids)
    end
end

function ConditionLibrary.has_debuff(buff_id_or_name)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return false end
        return AuraCatalog.has_debuff(target, buff_id_or_name)
    end
end

function ConditionLibrary.has_debuff_any(buff_ids)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return false end
        return AuraCatalog.has_any_debuff(target, buff_ids)
    end
end

function ConditionLibrary.missing_debuff(buff_id_or_name)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return true end
        return not AuraCatalog.has_debuff(target, buff_id_or_name)
    end
end

function ConditionLibrary.missing_debuff_any(buff_ids)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return true end
        return not AuraCatalog.has_any_debuff(target, buff_ids)
    end
end

-- Stack count conditions
function ConditionLibrary.get_buff_stack(buff_id_or_name)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return 0 end
        return AuraCatalog.get_stack(player, buff_id_or_name) or 0
    end
end

function ConditionLibrary.buff_stack_at_least(buff_id_or_name, min_stacks)
    return function(blackboard)
        return ConditionLibrary.get_buff_stack(buff_id_or_name)(blackboard) >= min_stacks
    end
end

function ConditionLibrary.buff_stack_below(buff_id_or_name, max_stacks)
    return function(blackboard)
        return ConditionLibrary.get_buff_stack(buff_id_or_name)(blackboard) < max_stacks
    end
end

-- ============================================================================
-- COOLDOWN CONDITIONS
-- ============================================================================

function ConditionLibrary.spell_ready(spell_key, mode, cast_target)
    mode = mode or "best"
    cast_target = cast_target or "target"
    return function(blackboard)
        local player, target = player_and_target(blackboard)
        local spell_id = spell_id_for(blackboard, spell_key, mode)
        local cooldowns = blackboard:get("module.combat.cooldowns")
        if not spell_id or not cooldowns or not cooldowns:spell_ready(spell_id) then
            return false
        end
        local helper = resolve_spell_helper_cached()
        if not helper or type(helper.is_spell_castable) ~= "function" then
            return true
        end
        local source = player
        local dest = cast_target == "self" and player or (target or player)
        local ok, castable = call_helper(helper.is_spell_castable, helper, spell_id, source, dest, true, true)
        if not ok or castable ~= true then
            return false
        end
        -- Check line of sight for targeted spells (not self-cast)
        if cast_target ~= "self" and dest and dest ~= source then
            if type(helper.is_spell_in_line_of_sight) == "function" then
                local los_ok, in_los = call_helper(helper.is_spell_in_line_of_sight, helper, spell_id, source, dest)
                if los_ok and in_los ~= true then
                    return false
                end
            end
        end
        return true
    end
end

-- ============================================================================
-- COMBAT STATE CONDITIONS
-- ============================================================================

function ConditionLibrary.target_is_frozen(blackboard)
    return blackboard:get("combat.target_frozen", false) == true
end

function ConditionLibrary.target_not_frozen(blackboard)
    return blackboard:get("combat.target_frozen", false) ~= true
end

function ConditionLibrary.target_killable_instant(blackboard)
    return blackboard:get("combat.target_killable_instant", false) == true
end

function ConditionLibrary.should_cancel_cast(blackboard)
    return blackboard:get("combat.should_cancel_cast", false) == true
end

function ConditionLibrary.cast_is_overkill(blackboard)
    return blackboard:get("combat.cast_overkill", false) == true
end

function ConditionLibrary.use_aoe_rotation(blackboard)
    return blackboard:get("combat.use_aoe_rotation", false) == true
end

function ConditionLibrary.target_has_stealable_buff(blackboard)
    return blackboard:get("combat.target_has_stealable_buff", false) == true
end

function ConditionLibrary.has_mana_gem(blackboard)
    return blackboard:get("combat.has_mana_gem", false) == true
end

function ConditionLibrary.missing_mana_gem(blackboard)
    return blackboard:get("combat.has_mana_gem", false) ~= true
end

function ConditionLibrary.has_water_elemental(blackboard)
    return blackboard:get("combat.has_water_elemental", false) == true
end

function ConditionLibrary.missing_water_elemental(blackboard)
    return blackboard:get("combat.has_water_elemental", false) ~= true
end

-- ============================================================================
-- PET CONDITIONS
-- ============================================================================

function ConditionLibrary.has_pet(blackboard)
    return blackboard:get("combat.has_water_elemental") == true
end

function ConditionLibrary.pet_not_attacking_target(blackboard)
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        local target = blackboard:get("combat.target") or blackboard:get("player.target")
        if not pet_ctrl or not target then return false end
        return not pet_ctrl:already_sent_to(target)
    end
end

function ConditionLibrary.pet_freeze_useful(blackboard)
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

-- ============================================================================
-- CONSUMABLE CONDITIONS
-- ============================================================================

function ConditionLibrary.has_health_potion()
    return function(blackboard)
        return blackboard:get("combat.has_health_potion") == true
    end
end

function ConditionLibrary.has_mana_potion()
    return function(blackboard)
        return blackboard:get("combat.has_mana_potion") == true
    end
end

function ConditionLibrary.potion_ready()
    return function(blackboard)
        local now = blackboard:get("system.now_ms", 0)
        return now >= (blackboard:get("combat.potion_cd_until_ms", 0))
    end
end

-- ============================================================================
-- PVP/CLASS SPECIFIC CONDITIONS
-- ============================================================================

function ConditionLibrary.target_is_player(blackboard)
    return blackboard:get("combat.target_is_player", false) == true
end

function ConditionLibrary.target_is_caster(blackboard)
    return blackboard:get("combat.target_is_caster", false) == true
end

function ConditionLibrary.target_is_healer(blackboard)
    return blackboard:get("combat.target_is_healer", false) == true
end

function ConditionLibrary.burst_enabled(blackboard)
    return blackboard:get("module.combat.enable_burst", true) ~= false
end

function ConditionLibrary.burst_context(blackboard)
    return blackboard:get("combat.burst_context", false) == true
end

function ConditionLibrary.in_combat_context(blackboard)
    return blackboard:get("player.in_combat", false) == true
        or tostring(blackboard:get("combat.state", "IDLE") or "IDLE") ~= "IDLE"
end

function ConditionLibrary.desired_seal_is(seal)
    return function(blackboard)
        return blackboard:get("rotation.desired_seal") == seal
    end
end

function ConditionLibrary.active_seal_is(seal)
    return function(blackboard)
        return blackboard:get("rotation.active_seal") == seal
    end
end

function ConditionLibrary.seal_missing(seal)
    return function(blackboard)
        return blackboard:get("rotation.active_seal") ~= seal
    end
end

-- ============================================================================
-- ADVANCED CONDITIONS (IZI SDK BASED)
-- ============================================================================

function ConditionLibrary.time_to_die_below(seconds)
    return function(blackboard)
        local _, target = player_and_target(blackboard)
        if not target then return false end
        local izi_bridge = blackboard:get("module.combat.izi_bridge")
        if izi_bridge then
            local ttd = izi_bridge:get_time_to_die(target)
            if ttd and ttd < seconds then
                return true
            end
        end
        -- Fallback to HP% check
        local ok_hp, hp_pct = safe_call(target, "get_health_percentage")
        return ok_hp and num(hp_pct) <= (seconds * 10)  -- rough estimate: 10% HP per second
    end
end

function ConditionLibrary.incoming_damage_above(threshold_pct, time_seconds)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return false end
        local izi_bridge = blackboard:get("module.combat.izi_bridge")
        if izi_bridge then
            local incoming = izi_bridge:get_incoming_damage(player, time_seconds)
            local max_hp = player:get_max_health()
            local incoming_pct = incoming / max_hp
            return incoming_pct >= threshold_pct
        end
        return false
    end
end

function ConditionLibrary.health_prediction_below(threshold_pct, time_seconds)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then return false end
        local izi_bridge = blackboard:get("module.combat.izi_bridge")
        if izi_bridge then
            local predicted_hp_pct = izi_bridge:predict_hp_pct(player, time_seconds)
            if predicted_hp_pct then
                return predicted_hp_pct < threshold_pct
            end
        end
        return false
    end
end

-- ============================================================================
-- COMPOUND CONDITIONS (for fluent interface)
-- ============================================================================

function ConditionLibrary.not_(condition_func)
    return function(blackboard)
        return not condition_func(blackboard)
    end
end

function ConditionLibrary.and_(...)
    local conditions = {...}
    return function(blackboard)
        for _, cond in ipairs(conditions) do
            if not cond(blackboard) then
                return false
            end
        end
        return true
    end
end

function ConditionLibrary.or_(...)
    local conditions = {...}
    return function(blackboard)
        for _, cond in ipairs(conditions) do
            if cond(blackboard) then
                return true
            end
        end
        return false
    end
end

return ConditionLibrary
