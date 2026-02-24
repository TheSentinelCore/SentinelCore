local BT = require("ai/BehaviorTree")
local S = BT.Status
local Helpers = require("lib/Helpers")
local AutoAttackHelper = require("lib/AutoAttackHelper")

local PullService = {}

--- Idempotent auto-attack: uses SDK auto_attack_helper if available,
--- falls back to cast_target_spell(6603) only when not already attacking.
---@param target game_object
---@param player game_object|nil
local function start_auto_attack(target, player)
    if not target or not core or not core.input then return end
    pcall(function()
        if core.input.set_target then core.input.set_target(target) end
    end)

    -- Primary: SDK auto_attack_helper (truly idempotent)
    local aa = AutoAttackHelper.get()
    if aa and aa.start_attack then
        local ok = pcall(function()
            aa:start_attack(target, aa.ATTACK_TYPE and aa.ATTACK_TYPE.MELEE or 6603)
        end)
        if ok then return end
    end

    -- Fallback: only send 6603 toggle when NOT already auto-attacking
    if player then
        local ok, attacking = pcall(function() return player:is_auto_attacking() end)
        if ok and attacking == true then return end
    end
    if core.input.cast_target_spell then
        pcall(core.input.cast_target_spell, 6603, target)
    end
end

function PullService.build(bb, navigation)
    local last_dest = nil
    local auto_attack_started = false

    return BT.ReactiveSequence:new("pull", {
        -- Gate: has valid target and not yet in combat (re-evaluated every tick)
        -- Resets closure state when gate fails to avoid stale nav data on next pull.
        BT.Condition:new("has_valid_target", function()
            if bb:get("player.in_combat", false) then
                last_dest = nil
                auto_attack_started = false
                return false
            end
            local target = bb:get("combat.target")
            if not target then
                last_dest = nil
                auto_attack_started = false
                return false
            end
            local ok, hp = pcall(function() return target:get_health() end)
            if not ok or not hp or hp <= 0 then
                last_dest = nil
                auto_attack_started = false
                return false
            end
            return true
        end),

        -- Navigate to pull range with timeout
        BT.Timeout:new("pull_timeout", 12.0,
            BT.Action:new("navigate_and_pull", function()
                local target = bb:get("combat.target")
                if not target then return S.FAILURE end

                -- Check if in combat already (pull succeeded)
                if bb:get("player.in_combat", false) then
                    last_dest = nil
                    auto_attack_started = false
                    return S.SUCCESS
                end

                local ok, tpos = pcall(function() return target:get_position() end)
                if not ok or not tpos then return S.FAILURE end

                local player_pos = bb:get("player.position")
                if not player_pos then return S.FAILURE end

                local dist = Helpers.distance_3d(player_pos, tpos)

                -- Navigate toward target: move_to when idle, soft_repath when
                -- target moves >1yd from last destination. No pending gate —
                -- soft_repath is a fast localhost HTTP call that overrides in-flight requests.
                if dist > 5 and navigation then
                    if not navigation:is_moving() then
                        last_dest = tpos
                        pcall(function() navigation:move_to(tpos) end)
                    elseif last_dest then
                        if Helpers.distance_3d(last_dest, tpos) > 1.0 then
                            last_dest = tpos
                            pcall(function() navigation:soft_repath(tpos) end)
                        end
                    else
                        last_dest = tpos
                        pcall(function() navigation:soft_repath(tpos) end)
                    end
                end

                local player = bb:get("player.object")

                -- Ranged pull: cast Judgement at 10yd if available (don't stop nav)
                -- Also start auto-attack so melee swings begin as soon as we arrive.
                if dist <= 10 and dist > 5 then
                    if core.input and core.input.set_target and core.input.cast_target_spell
                        and core.spell_book and core.spell_book.get_spell_cooldown then
                        local cd_ok, cd = pcall(core.spell_book.get_spell_cooldown, 20271)
                        if cd_ok and cd and cd <= 0 then
                            pcall(function()
                                core.input.set_target(target)
                                core.input.cast_target_spell(20271, target) -- Judgement
                            end)
                            -- Start auto-attack after Judgement so melee swings queue
                            start_auto_attack(target, player)
                            auto_attack_started = true
                        end
                    end
                    -- Start auto-attack at 10yd even without Judgement
                    if not auto_attack_started then
                        start_auto_attack(target, player)
                        auto_attack_started = true
                    end
                end

                -- Melee range: stop nav, ensure auto-attack is running
                if dist <= 5 then
                    if navigation and navigation:is_moving() then
                        pcall(function() navigation:stop() end)
                    end
                    if not auto_attack_started then
                        start_auto_attack(target, player)
                        auto_attack_started = true
                    end
                end

                return S.RUNNING
            end)
        ),
    })
end

return PullService
