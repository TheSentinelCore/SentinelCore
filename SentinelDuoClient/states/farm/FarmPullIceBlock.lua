-- FarmPullIceBlock.lua — Puller navigates to IB position, casts Ice Block, enters barrier.

local helpers          = require("lib/helpers")
local DefensiveManager = require("combat/DefensiveManager")

local FarmPullIceBlock = { name = "FARM_PULL_ICEBLOCK" }

local ICE_BLOCK_ID = 45438
local BARRIER_NAME = "ice_block_up"

function FarmPullIceBlock:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local sc           = ctx.spell_catalog

    local defensive          = DefensiveManager:new(sc, bb)
    local barrier_entered    = false
    local ib_cast_done       = false
    local blizz_nav_started  = false

    return {
        enter = function(_bb)
            helpers.log("[FARM_PULL_ICEBLOCK] enter")
            bb:set("duo.farm_sub_state", "pull_ice_block")
            barrier_entered   = false
            ib_cast_done      = false
            blizz_nav_started = false

            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)

            if is_puller and pull and pull.ice_block_position then
                duo_nav:move_to(pull.ice_block_position)
            end
        end,

        update = function(_bb)
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt        = helpers.game_time_ms()
            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)

            if is_puller then
                -- Wait until arrived at IB position
                if not ib_cast_done then
                    local at_pos = pull and pull.ice_block_position and duo_nav:is_arrived(3.0)
                    if at_pos then
                        -- Cast Ice Block
                        local ib_id = sc:resolve("Ice Block", player) or ICE_BLOCK_ID
                        if select(1, pcall(core.input.cast_target_spell, ib_id, player)) then
                            bb:set("duo.ice_block_cast_ms", gt)
                            ib_cast_done = true
                            helpers.log("[FARM_PULL_ICEBLOCK] Ice Block cast")
                        end
                    end
                end

                -- Enter barrier after IB cast
                if ib_cast_done and not barrier_entered then
                    coord_client:enter_barrier(BARRIER_NAME)
                    barrier_entered = true
                end
            else
                -- Support: navigate to blizzard_position (within casting range of
                -- blizzard_center) while puller moves to IB position.  Enter the
                -- barrier once arrived so both sides sync after IB is cast.
                defensive:tick(player, gt)

                if not barrier_entered then
                    local at_blizz = false
                    if pull and pull.blizzard_position then
                        if not blizz_nav_started then
                            duo_nav:move_to(pull.blizzard_position)
                            blizz_nav_started = true
                            helpers.log("[FARM_PULL_ICEBLOCK] support navigating to blizzard_position")
                        end
                        at_blizz = duo_nav:is_arrived(4.0)
                    else
                        at_blizz = true  -- no blizzard_position defined — enter immediately
                    end

                    if at_blizz then
                        duo_nav:stop("at_blizz_pos")
                        coord_client:enter_barrier(BARRIER_NAME)
                        barrier_entered = true
                        helpers.log("[FARM_PULL_ICEBLOCK] support at blizzard_position — barrier entered")
                    end
                end
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true then
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_AOE_OPENING"
                elseif result == "timeout" then
                    helpers.log_warn("[FARM_PULL_ICEBLOCK] barrier timeout")
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_AOE_OPENING"
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

return FarmPullIceBlock
