local BT = require("ai/BehaviorTree")
local S = BT.Status
local Helpers = require("lib/Helpers")
local AutoAttackHelper = require("lib/AutoAttackHelper")
local get_now = require("lib/TimeHelper").get_now

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

--- Resolve the pull profile from the rotation engine (once per pull attempt).
--- Returns a table with pull_spell_id, max_pull_range, melee_engage_range, disable_auto_attack.
---@param rotation_engine table|nil
---@return table
local function get_pull_profile(rotation_engine)
    if rotation_engine and type(rotation_engine.get_pull_profile) == "function" then
        local ok, profile = pcall(rotation_engine.get_pull_profile, rotation_engine)
        if ok and type(profile) == "table" then
            return profile
        end
    end
    -- Default: melee-class profile (no ranged pull, auto-attack enabled)
    return {
        pull_spell_id = nil,
        max_pull_range = 5,
        melee_engage_range = 5,
        disable_auto_attack = false,
    }
end

---@param bb table Blackboard
---@param navigation table|nil NavigationAdapter
---@param rotation_engine table|nil RotationEngine (provides class-specific pull profile)
function PullService.build(bb, navigation, rotation_engine)
    local last_dest = nil
    local pull_spell_fired = false
    -- Density guard: throttled scan of nearby hostiles around the pull target.
    -- Skip pull if 3+ total hostiles are within 10yd (including the target itself).
    local density_check_at = 0
    local density_blocked = false
    local DENSITY_CHECK_INTERVAL = 3.0
    local DENSITY_RADIUS = 10.0
    local DENSITY_THRESHOLD = 3  -- target + 2 nearby = too risky

    -- Pull profile cache: refreshed each time the gate resets (new pull target).
    -- Avoids calling rotation_engine:get_pull_profile() every tick.
    local cached_profile = nil

    return BT.ReactiveSequence:new("pull", {
        -- Gate: has valid target, not in combat, not in a high-density cluster.
        -- Resets closure state when gate fails to avoid stale nav data on next pull.
        BT.Condition:new("has_valid_target", function()
            if bb:get("player.in_combat", false) then
                last_dest = nil
                pull_spell_fired = false
                density_blocked = false
                cached_profile = nil
                return false
            end
            local target = bb:get("combat.target")
            if not target then
                last_dest = nil
                pull_spell_fired = false
                density_blocked = false
                cached_profile = nil
                return false
            end
            local ok, hp = pcall(function() return target:get_health() end)
            if not ok or not hp or hp <= 0 then
                last_dest = nil
                pull_spell_fired = false
                density_blocked = false
                cached_profile = nil
                return false
            end
            -- Density check: throttled to avoid scanning every tick.
            local now = get_now()
            if (now - density_check_at) >= DENSITY_CHECK_INTERVAL then
                density_check_at = now
                density_blocked = false
                if core and core.object_manager and core.object_manager.get_visible_objects then
                    local ok_pos, tpos = pcall(function() return target:get_position() end)
                    if ok_pos and tpos then
                        local ok_objs, objects = pcall(core.object_manager.get_visible_objects)
                        if ok_objs and type(objects) == "table" then
                            local nearby = 0
                            for i = 1, #objects do
                                local unit = objects[i]
                                local ok_unit = pcall(function()
                                    if unit and unit.get_position and unit.is_dead
                                        and unit.is_hostile and unit.is_unit
                                        and unit:is_unit() and not unit:is_dead()
                                        and unit:is_hostile()
                                        and not (unit.is_basic_object and unit:is_basic_object()) then
                                        local upos = unit:get_position()
                                        if upos and Helpers.distance_3d(upos, tpos) <= DENSITY_RADIUS then
                                            nearby = nearby + 1
                                        end
                                    end
                                end)
                                _ = ok_unit -- suppress unused warning
                            end
                            if nearby >= DENSITY_THRESHOLD then
                                density_blocked = true
                            end
                        end
                    end
                end
            end
            if density_blocked then
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
                    pull_spell_fired = false
                    cached_profile = nil
                    return S.SUCCESS
                end

                local ok, tpos = pcall(function() return target:get_position() end)
                if not ok or not tpos then return S.FAILURE end

                local player_pos = bb:get("player.position")
                if not player_pos then return S.FAILURE end

                local dist = Helpers.distance_3d(player_pos, tpos)

                -- Resolve pull profile once per pull attempt (lazy-init).
                -- We read it once the action starts rather than at gate time so the
                -- rotation engine has a valid context (player object populated).
                if cached_profile == nil then
                    cached_profile = get_pull_profile(rotation_engine)
                end

                local pull_spell_id = tonumber(cached_profile.pull_spell_id) or 0
                local pull_range = tonumber(cached_profile.max_pull_range) or 5.0
                local melee_range = tonumber(cached_profile.melee_engage_range) or 5.0
                local disable_aa = cached_profile.disable_auto_attack == true

                -- Navigate toward target while outside engage range.
                -- Ranged classes have melee_engage_range == max_pull_range (they
                -- stop navigation once in cast range, not at physical melee).
                if dist > melee_range and navigation then
                    local moving = navigation:is_moving()
                    if moving == nil then
                        -- NavClient unavailable; skip navigation this tick.
                    elseif not moving then
                        last_dest = tpos
                        navigation:move_to(tpos, function(nav_ok)
                            if not nav_ok then last_dest = nil end
                        end)
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

                -- Ranged pull: cast pull spell when target is within pull_range.
                -- Retries every tick until the spell goes on cooldown (= cast succeeded).
                -- For melee classes (Paladin): fires in the window [melee_range, pull_range]
                --   e.g. 5–10yd for Judgement — navigation is still moving the player closer.
                -- For ranged classes (Warlock): fires at any dist <= pull_range (=melee_range=30)
                --   i.e. as soon as navigation stops. We do NOT start auto-attack.
                if pull_spell_id > 0 and dist <= pull_range and not pull_spell_fired then
                    if core and core.input and core.input.set_target and core.input.cast_target_spell
                        and core.spell_book and core.spell_book.get_spell_cooldown then
                        local cd_ok, cd = pcall(core.spell_book.get_spell_cooldown, pull_spell_id)
                        if cd_ok and (cd == nil or cd <= 0) then
                            pcall(function()
                                core.input.set_target(target)
                                -- Face the mob before casting: NavClient may be rotating
                                -- the player toward a path waypoint rather than the target.
                                -- look_at snaps facing to the mob so the spell doesn't
                                -- fail due to not-facing-target.
                                if core.input.look_at then
                                    core.input.look_at(tpos)
                                end
                                core.input.cast_target_spell(pull_spell_id, target)
                            end)
                            -- Verify the spell went on cooldown (= cast succeeded).
                            local cd2_ok, cd2 = pcall(core.spell_book.get_spell_cooldown, pull_spell_id)
                            if cd2_ok and cd2 and cd2 > 0 then
                                pull_spell_fired = true
                            end
                        end
                    end
                    -- Melee classes: start auto-attack alongside ranged pull attempt.
                    if not disable_aa then
                        start_auto_attack(target, player)
                    end
                end

                -- Within engage range (melee range for melee; cast range for ranged):
                -- stop nav so the player settles and can cast/swing freely.
                if dist <= melee_range then
                    if navigation and navigation:is_moving() then
                        pcall(function() navigation:stop() end)
                    end
                    -- Always ensure auto-attack at melee range (idempotent).
                    if not disable_aa then
                        start_auto_attack(target, player)
                    end
                end

                return S.RUNNING
            end)
        ),
    })
end

return PullService
