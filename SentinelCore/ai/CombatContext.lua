-- SentinelCore/ai/CombatContext.lua
local get_now = require("lib/TimeHelper").get_now
local AutoAttackHelper = require("lib/AutoAttackHelper")

---@class CombatContext
local CombatContext = {}

-- Aura spell IDs for direct game_object queries.
-- Seals/buffs must check ALL ranks since buff ID matches the cast rank.
local AURA = {
    SEAL_OF_BLOOD = { 31892 },
    SEAL_OF_COMMAND = { 27170, 20920, 20919, 20918, 20915, 20375 },
    AVENGING_WRATH = { 31884 },
    BLESSING_OF_MIGHT = { 27140, 25291, 19838, 19837, 19836, 19835, 19834, 19740 },
    VENGEANCE = { 20050 },
}

--- Check if unit has any buff from a list of spell IDs (rank table).
---@param unit any game_object
---@param spell_ids number[] array of spell IDs to check
---@return boolean
local function unit_has_buff(unit, spell_ids)
    if not unit or not spell_ids then return false end
    for i = 1, #spell_ids do
        local sid = spell_ids[i]
        local ok, result = pcall(function()
            if unit.has_buff then return unit:has_buff(sid) end
            if unit.get_auras then
                local auras = unit:get_auras()
                if auras then
                    for _, aura in pairs(auras) do
                        if aura.spell_id == sid then return true end
                    end
                end
            end
            return false
        end)
        if ok and result then return true end
    end
    return false
end

---@return number GCD remaining in seconds
local function resolve_gcd_remaining()
    local aa = AutoAttackHelper.get()
    if aa and aa.get_next_global_core_time then
        local ok, next_gcd = pcall(function() return aa:get_next_global_core_time() end)
        if ok and next_gcd and next_gcd > 0 then
            local now = get_now()
            local rem = next_gcd - now
            return rem > 0 and rem or 0
        end
    end
    if core and core.spell_book and core.spell_book.get_global_cooldown then
        local ok, v = pcall(core.spell_book.get_global_cooldown)
        if ok and v then return v end
    end
    return 0
end

--- Get buff stacks for the first matching spell ID from a rank table.
---@param unit any game_object
---@param spell_ids number[] array of spell IDs to check
---@return number
local function unit_buff_stacks(unit, spell_ids)
    if not unit or not spell_ids then return 0 end
    for i = 1, #spell_ids do
        local sid = spell_ids[i]
        local ok, result = pcall(function()
            if unit.get_buff_stacks then return unit:get_buff_stacks(sid) or 0 end
            return 0
        end)
        if ok and result and result > 0 then return result end
    end
    return 0
end

---Build a flat context table from Blackboard for UtilityEvaluator.
---All values are numbers (0/1 for booleans) so response curves work directly.
---@param bb Blackboard
---@param swing_timer? SwingTimer
---@return table<string, number>
function CombatContext.build(bb, swing_timer)
    local player = bb:get("player.object")
    local target = bb:get("combat.target")

    local p_health = bb:get("player.health", 0)
    local p_max_health = bb:get("player.max_health", 1)
    local p_mana = 0
    local p_max_mana = 1
    if player then
        local ok1, m = pcall(function() return player:get_power(0) end)
        local ok2, mm = pcall(function() return player:get_max_power(0) end)
        if ok1 and ok2 and mm and mm > 0 then
            p_mana = m or 0
            p_max_mana = mm
        end
    end

    -- Player movement: query game_object directly
    local p_is_moving = false
    if player then
        local ok_m, mov = pcall(function() return player:is_moving() end)
        p_is_moving = ok_m and mov or false
    end

    local t_health = 0
    local t_max_health = 1
    local t_distance = 99
    local t_casting = false
    local t_cast_pct = 0
    local t_is_undead_demon = false

    if target then
        local ok1, h = pcall(function() return target:get_health() end)
        local ok2, mh = pcall(function() return target:get_max_health() end)
        if ok1 and ok2 then
            t_health = h or 0
            t_max_health = (mh and mh > 0) and mh or 1
        end

        local pp = bb:get("player.position")
        if pp then
            local ok3, tp = pcall(function() return target:get_position() end)
            if ok3 and tp then
                local dx = (tp.x or 0) - (pp.x or 0)
                local dy = (tp.y or 0) - (pp.y or 0)
                local dz = (tp.z or 0) - (pp.z or 0)
                t_distance = math.sqrt(dx*dx + dy*dy + dz*dz)
            end
        end

        local ok4, casting = pcall(function() return target:is_casting_spell() end)
        t_casting = ok4 and casting or false
        local ok5, cst = pcall(function()
            local st = target:get_active_spell_cast_start_time()
            local et = target:get_active_spell_cast_end_time()
            if st and et and et > st then
                return (get_now() - st) / (et - st)
            end
            return 0
        end)
        t_cast_pct = ok5 and math.max(0, math.min(1, cst or 0)) or 0

        -- Creature type: 3=Demon, 6=Undead
        local ok_ct, ct = pcall(function() return target:get_creature_type() end)
        if ok_ct and ct then
            t_is_undead_demon = (ct == 3 or ct == 6)
        end
    end

    -- Enemy count and nearest enemy distance: query game_object directly
    local enemy_count = 0
    local nearest_enemy_dist = 99
    if player and player.get_enemies_in_range then
        local ok_e, enemies = pcall(function() return player:get_enemies_in_range(40) end)
        if ok_e and enemies then
            local pp = bb:get("player.position")
            for _, enemy in pairs(enemies) do
                enemy_count = enemy_count + 1
                if pp then
                    local eok, epos = pcall(function() return enemy:get_position() end)
                    if eok and epos then
                        local dx = (epos.x or 0) - (pp.x or 0)
                        local dy = (epos.y or 0) - (pp.y or 0)
                        local dz = (epos.z or 0) - (pp.z or 0)
                        local d = math.sqrt(dx*dx + dy*dy + dz*dz)
                        if d < nearest_enemy_dist then nearest_enemy_dist = d end
                    end
                end
            end
        end
    end
    -- Fallback to BB if direct query unavailable
    if enemy_count == 0 then
        enemy_count = bb:get("combat.enemy_count", 0)
    end

    local ctx = {
        -- Player
        player_health_pct = p_max_health > 0 and (p_health / p_max_health) or 0,
        player_mana_pct = p_max_mana > 0 and (p_mana / p_max_mana) or 0,
        player_is_moving = p_is_moving and 1 or 0,
        player_is_casting = (bb:get("player.is_casting") or false) and 1 or 0,
        player_is_cc = 0,
        in_combat = (bb:get("player.in_combat") or false) and 1 or 0,

        -- Target
        target_health_pct = t_max_health > 0 and (t_health / t_max_health) or 0,
        target_distance = t_distance,
        target_is_casting = t_casting and 1 or 0,
        target_cast_progress = t_cast_pct,
        target_time_to_die = bb:get("combat.target_ttd", 30),
        target_is_fleeing = 0,
        target_is_undead_demon = t_is_undead_demon and 1 or 0,

        -- Combat
        enemy_count = enemy_count,
        time_in_combat = bb:get("combat.time_in_combat", 0),
        nearest_enemy_distance = nearest_enemy_dist,

        -- Spell state (GCD from auto_attack_helper if available, else spell_book)
        spell_cooldown_remaining = 0,
        gcd_remaining = resolve_gcd_remaining(),

        -- Swing timer (populated below)
        swing_time_remaining = 0,
        swing_in_prep_window = 0,
        swing_in_twist_window = 0,

        -- Buff state: query player auras directly
        has_seal_of_blood = unit_has_buff(player, AURA.SEAL_OF_BLOOD) and 1 or 0,
        has_seal_of_command = unit_has_buff(player, AURA.SEAL_OF_COMMAND) and 1 or 0,
        has_any_seal = (unit_has_buff(player, AURA.SEAL_OF_BLOOD)
            or unit_has_buff(player, AURA.SEAL_OF_COMMAND)) and 1 or 0,
        has_avenging_wrath = unit_has_buff(player, AURA.AVENGING_WRATH) and 1 or 0,
        has_blessing_of_might = unit_has_buff(player, AURA.BLESSING_OF_MIGHT) and 1 or 0,
        vengeance_stacks = unit_buff_stacks(player, AURA.VENGEANCE),

        -- Config
        seal_twist_enabled = bb:get("config.seal_twist_enabled", 0),
        aoe_threshold = bb:get("config.aoe_threshold", 3),
    }

    -- Swing timer integration
    if swing_timer then
        -- Pass player so SwingTimer can query auto_attack_helper
        if player then
            swing_timer:set_player(player)
        end

        -- Feed weapon speed from player API if available
        if player then
            local ok_ws, ws = pcall(function()
                if player.get_attack_speed then return player:get_attack_speed() end
                return nil
            end)
            if ok_ws and ws and ws > 0 then
                swing_timer:set_weapon_speed(ws)
            end
        end

        ctx.swing_time_remaining = swing_timer:time_until_swing()
        ctx.swing_in_prep_window = swing_timer:in_prep_window() and 1 or 0
        ctx.swing_in_twist_window = swing_timer:in_twist_window() and 1 or 0
    end

    return ctx
end

return CombatContext
