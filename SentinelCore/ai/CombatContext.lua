-- SentinelCore/ai/CombatContext.lua
---@class CombatContext
local CombatContext = {}

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

    local t_health = 0
    local t_max_health = 1
    local t_distance = 99
    local t_casting = false
    local t_cast_pct = 0

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
            if st and et and et > st and core then
                return (core.time() - st) / (et - st)
            end
            return 0
        end)
        t_cast_pct = ok5 and cst or 0
    end

    local ctx = {
        -- Player
        player_health_pct = p_max_health > 0 and (p_health / p_max_health) or 0,
        player_mana_pct = p_max_mana > 0 and (p_mana / p_max_mana) or 0,
        player_is_moving = (bb:get("player.is_moving") or false) and 1 or 0,
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
        target_is_undead_demon = 0,

        -- Combat
        enemy_count = bb:get("combat.enemy_count", 0),
        time_in_combat = bb:get("combat.time_in_combat", 0),
        nearest_enemy_distance = bb:get("combat.nearest_enemy_dist", 99),

        -- Spell state (populated per-action by evaluator)
        spell_cooldown_remaining = 0,
        gcd_remaining = 0,

        -- Swing timer
        swing_time_remaining = 0,
        swing_in_prep_window = 0,
        swing_in_twist_window = 0,

        -- Buff state (populated by rotation before evaluation)
        has_seal_of_blood = 0,
        has_seal_of_command = 0,
        has_avenging_wrath = 0,
        has_blessing_of_might = 0,
        vengeance_stacks = 0,

        -- Config
        seal_twist_enabled = bb:get("config.seal_twist_enabled", 0),
        aoe_threshold = bb:get("config.aoe_threshold", 3),
    }

    -- Swing timer integration
    if swing_timer then
        ctx.swing_time_remaining = swing_timer:time_until_swing()
        ctx.swing_in_prep_window = swing_timer:in_prep_window() and 1 or 0
        ctx.swing_in_twist_window = swing_timer:in_twist_window() and 1 or 0
    end

    return ctx
end

return CombatContext
