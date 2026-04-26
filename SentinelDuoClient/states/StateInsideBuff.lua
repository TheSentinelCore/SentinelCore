-- StateInsideBuff.lua — Quick re-buff inside the instance before the first pull.
-- Only casts Ice Armor + Ice Barrier. No drink/conjure (no time for it mid-run).
-- Uses "inside_buff_ready" barrier so both mages are buffed before FARMING starts.

local helpers = require("lib/helpers")

local StateInsideBuff = { name = "INSIDE_BUFF" }

local BARRIER_NAME    = "inside_buff_ready"
local HARD_TIMEOUT_MS = 15000
local MIN_CAST_GAP_MS = 600

local ICE_ARMOR_IDS   = { 10220, 10219, 7320, 7302 }              -- R4→R1
local ICE_BARRIER_IDS = { 13033, 13032, 13031, 11426 }             -- R7→R4
local MANA_SHIELD_IDS = { 27131, 10193, 10192, 10191, 8494, 8493 } -- R7→R2

local function has_any_aura(player, ids)
    if not player then return false end
    local ok, data = pcall(player.get_buff_data, player, ids)
    return ok and data ~= nil
end

local function try_cast_list(ids)
    local ok_pl, player = pcall(core.object_manager.get_local_player)
    if not ok_pl or not player then return false end
    for _, id in ipairs(ids) do
        local ok = select(1, pcall(core.input.cast_target_spell, id, player))
        if ok then return true end
    end
    return false
end

function StateInsideBuff:create(ctx)
    local bb           = ctx.bb
    local sc           = ctx.spell_catalog
    local coord_client = ctx.coord_client

    local enter_ms        = 0
    local last_cast_ms    = 0
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[INSIDE_BUFF] enter")
            enter_ms        = helpers.game_time_ms()
            last_cast_ms    = 0
            barrier_entered = false
            bb:set("duo.farm_sub_state", "inside_buffing")
        end,

        update = function(_bb)
            -- Guard: dead/ghost state should escalate
            if bb:get("player.is_dead", false) or bb:get("player.is_ghost", false) then
                return "DEAD"
            end

            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt      = helpers.game_time_ms()
            local elapsed = gt - enter_ms

            local ice_armor_ok    = has_any_aura(player, ICE_ARMOR_IDS)
            local ice_barrier_ok  = has_any_aura(player, ICE_BARRIER_IDS)
            local mana_shield_ok  = has_any_aura(player, MANA_SHIELD_IDS)
            local buffs_ready     = ice_armor_ok and ice_barrier_ok and mana_shield_ok

            -- Cast missing buffs while waiting for barrier
            if not buffs_ready and not barrier_entered and gt - last_cast_ms >= MIN_CAST_GAP_MS then
                if not ice_armor_ok then
                    local cast_ok = false
                    if sc then
                        local id = sc:resolve("Ice Armor", player)
                        if id then cast_ok = select(1, pcall(core.input.cast_target_spell, id, player)) end
                    end
                    if not cast_ok then cast_ok = try_cast_list(ICE_ARMOR_IDS) end
                    if cast_ok then last_cast_ms = gt; return end
                end

                if not ice_barrier_ok then
                    local cast_ok = false
                    if sc then
                        local id = sc:resolve("Ice Barrier", player)
                        if id then cast_ok = select(1, pcall(core.input.cast_target_spell, id, player)) end
                    end
                    if not cast_ok then cast_ok = try_cast_list(ICE_BARRIER_IDS) end
                    if cast_ok then last_cast_ms = gt; return end
                end

                if not mana_shield_ok then
                    local cast_ok = false
                    if sc then
                        local id = sc:resolve("Mana Shield", player)
                        if id then cast_ok = select(1, pcall(core.input.cast_target_spell, id, player)) end
                    end
                    if not cast_ok then cast_ok = try_cast_list(MANA_SHIELD_IDS) end
                    if cast_ok then last_cast_ms = gt; return end
                end
            end

            -- Enter barrier once buffs are up or hard timeout reached
            if not barrier_entered and (buffs_ready or elapsed >= HARD_TIMEOUT_MS) then
                if elapsed >= HARD_TIMEOUT_MS then
                    helpers.log_warn("[INSIDE_BUFF] timeout — proceeding to FARMING without full buffs")
                else
                    helpers.log("[INSIDE_BUFF] buffs ready — entering barrier")
                end
                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true then
                    coord_client:release_barrier(BARRIER_NAME)
                    helpers.log("[INSIDE_BUFF] barrier released — FARMING")
                    return "FARMING"
                elseif result == "timeout" then
                    helpers.log_warn("[INSIDE_BUFF] barrier timeout — proceeding solo")
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARMING"
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[INSIDE_BUFF] exit")
        end,
    }
end

return StateInsideBuff
