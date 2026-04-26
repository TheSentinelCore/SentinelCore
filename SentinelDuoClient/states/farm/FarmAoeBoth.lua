-- FarmAoeBoth.lua — Both mages run AoE rotation until all mobs dead; then barrier → LOOTING.

local helpers     = require("lib/helpers")
local AoeRotation = require("combat/AoeRotation")

local FarmAoeBoth = { name = "FARM_AOE_BOTH" }

local BARRIER_NAME = "pull_complete"

function FarmAoeBoth:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local sc           = ctx.spell_catalog

    local aoe_rot         = AoeRotation:new(sc, bb)
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[FARM_AOE_BOTH] enter")
            bb:set("duo.farm_sub_state", "aoe_both")
            barrier_entered = false
            aoe_rot:reset()
            bb:set("duo.all_mobs_dead", false)
        end,

        update = function(_bb)
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt     = helpers.game_time_ms()
            local pull   = bb:get("duo.current_pull_def", nil)
            local center = pull and pull.blizzard_center

            -- Both run AoE rotation
            aoe_rot:tick(player, center, gt)

            -- Check if all mobs are dead
            if bb:get("duo.all_mobs_dead", false) and not barrier_entered then
                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
                helpers.log("[FARM_AOE_BOTH] all mobs dead — entering barrier")
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true then
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_LOOTING"
                elseif result == "timeout" then
                    helpers.log_warn("[FARM_AOE_BOTH] barrier timeout — looting anyway")
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_LOOTING"
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

return FarmAoeBoth
