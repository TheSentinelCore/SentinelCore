-- FarmIceBlockCancel.lua — Puller cancels Ice Block (via Frost Nova), repositions; support continues Blizzard.
-- Both clients synchronize via an "ib_cancelled" barrier before transitioning to FARM_AOE_BOTH.
-- The previous approach of using duo.ice_block_cast_ms == 0 was broken because each client has
-- a separate Lua state — the support's blackboard never has a non-zero ice_block_cast_ms.

local helpers     = require("lib/helpers")
local AoeRotation = require("combat/AoeRotation")

local FarmIceBlockCancel = { name = "FARM_ICE_BLOCK_CANCEL" }

-- Jittered delay before puller cancels IB (design doc timing)
local DEFAULT_CANCEL_DELAY_MS = 500

local FROST_NOVA_ID = 27088
local BARRIER_NAME  = "ib_cancelled"

function FarmIceBlockCancel:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local sc           = ctx.spell_catalog

    local aoe_rot         = AoeRotation:new(sc, bb)
    local enter_time      = 0
    local cancel_delay    = 0
    local ib_cancelled    = false
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[FARM_ICE_BLOCK_CANCEL] enter")
            bb:set("duo.farm_sub_state", "aoe_opening")  -- still "aoe_opening" phase from coord perspective
            enter_time      = helpers.game_time_ms()
            ib_cancelled    = false
            barrier_entered = false
            aoe_rot:reset()

            -- Jittered cancel delay
            local pull   = bb:get("duo.current_pull_def", nil)
            local timing = pull and pull.timing or {}
            local base   = timing.ice_block_cancel_delay_ms or DEFAULT_CANCEL_DELAY_MS
            cancel_delay = helpers.jitter(base, 0.2)
        end,

        update = function(_bb)
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt        = helpers.game_time_ms()
            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)
            local center    = pull and pull.blizzard_center

            if is_puller then
                -- Wait for jitter delay, then cancel Ice Block
                if not ib_cancelled and (gt - enter_time >= cancel_delay) then
                    -- Cast Frost Nova to cancel IB and root mobs simultaneously
                    -- In TBC, any spell cast cancels Ice Block
                    local nova_id = sc:resolve("Frost Nova", player) or FROST_NOVA_ID
                    pcall(core.input.cast_target_spell, nova_id, player)
                    ib_cancelled = true
                    helpers.log("[FARM_ICE_BLOCK_CANCEL] IB cancelled via Frost Nova")

                    -- Navigate to puller reposition
                    if pull and pull.puller_reposition then
                        duo_nav:move_to(pull.puller_reposition)
                    end
                end

                -- Puller enters barrier once IB is cancelled
                if ib_cancelled and not barrier_entered then
                    coord_client:enter_barrier(BARRIER_NAME)
                    barrier_entered = true
                end
            else
                -- Support: continue AoE rotation while waiting for puller to cancel IB
                aoe_rot:tick(player, center, gt)

                -- Support enters barrier immediately (it just needs to wait for puller)
                if not barrier_entered then
                    coord_client:enter_barrier(BARRIER_NAME)
                    barrier_entered = true
                end
            end

            -- Both proceed to FARM_AOE_BOTH when barrier is released
            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true then
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_AOE_BOTH"
                elseif result == "timeout" then
                    helpers.log_warn("[FARM_ICE_BLOCK_CANCEL] barrier timeout → FARM_AOE_BOTH")
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_AOE_BOTH"
                end
            end
        end,

        exit = function(_bb)
            if barrier_entered then
                coord_client:release_barrier(BARRIER_NAME)
                barrier_entered = false
            end
        end,
    }
end

return FarmIceBlockCancel
