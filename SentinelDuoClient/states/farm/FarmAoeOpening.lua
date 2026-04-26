-- FarmAoeOpening.lua — Support starts Blizzard; puller waits in Ice Block; enter ice_block_cancel barrier.

local helpers     = require("lib/helpers")
local AoeRotation = require("combat/AoeRotation")

local FarmAoeOpening = { name = "FARM_AOE_OPENING" }

local BARRIER_NAME = "ice_block_cancel"
local BLIZZARD_ID  = 27085

function FarmAoeOpening:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local sc           = ctx.spell_catalog

    local aoe_rot         = AoeRotation:new(sc, bb)
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[FARM_AOE_OPENING] enter")
            bb:set("duo.farm_sub_state", "aoe_opening")
            barrier_entered = false
            aoe_rot:reset()

            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)

            if not is_puller and pull and pull.blizzard_center then
                -- Support: cast first Blizzard immediately
                local ok_pl, player = pcall(core.object_manager.get_local_player)
                if ok_pl and player then
                    local blizz_id = sc:resolve("Blizzard", player) or BLIZZARD_ID
                    local gt = helpers.game_time_ms()
                    if select(1, pcall(core.input.cast_position_spell, blizz_id, pull.blizzard_center)) then
                        bb:set("duo.blizzard_channel_start_ms", gt)
                        helpers.log("[FARM_AOE_OPENING] Blizzard started at center")
                    end
                end
            end
        end,

        update = function(_bb)
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt        = helpers.game_time_ms()
            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)
            local center    = pull and pull.blizzard_center

            if not is_puller then
                -- Support: continue AoE rotation
                aoe_rot:tick(player, center, gt)
            else
                -- Puller: stay in Ice Block — just monitor, no action needed
            end

            -- Both enter ice_block_cancel barrier when ready
            if not barrier_entered then
                if not is_puller then
                    -- Support enters barrier once Blizzard is running (channel start set)
                    if bb:get("duo.blizzard_channel_start_ms", 0) > 0 then
                        coord_client:enter_barrier(BARRIER_NAME)
                        barrier_entered = true
                    end
                else
                    -- Puller enters barrier immediately (already in IB)
                    coord_client:enter_barrier(BARRIER_NAME)
                    barrier_entered = true
                end
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true then
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_ICE_BLOCK_CANCEL"
                elseif result == "timeout" then
                    helpers.log_warn("[FARM_AOE_OPENING] barrier timeout")
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_ICE_BLOCK_CANCEL"
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

return FarmAoeOpening
