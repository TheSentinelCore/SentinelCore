-- FarmPullRunning.lua — Puller runs pull path and tags mobs; support waits at safe pos.

local helpers         = require("lib/helpers")
local PullExecutor    = require("combat/PullExecutor")
local DefensiveManager = require("combat/DefensiveManager")

local FarmPullRunning = { name = "FARM_PULL_RUNNING" }

function FarmPullRunning:create(ctx)
    local bb      = ctx.bb
    local duo_nav = ctx.duo_nav
    local sc      = ctx.spell_catalog

    local pull_exec  = PullExecutor:new(duo_nav, sc, bb)
    local defensive  = DefensiveManager:new(sc, bb)
    local enter_ms   = 0

    return {
        enter = function(_bb)
            helpers.log("[FARM_PULL_RUNNING] enter")
            bb:set("duo.farm_sub_state", "pull_running")
            enter_ms = helpers.game_time_ms()

            local pull = bb:get("duo.current_pull_def", nil)
            local is_puller = bb:get("duo.is_puller", false)

            if is_puller and pull then
                pull_exec:start(pull)
            end
        end,

        update = function(_bb)
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt        = helpers.game_time_ms()
            local is_puller = bb:get("duo.is_puller", false)

            if is_puller then
                local result = pull_exec:tick(player, gt)
                if result == "ib_time" then
                    return "FARM_PULL_ICEBLOCK"
                elseif result == "abort" then
                    helpers.log_warn("[FARM_PULL_RUNNING] pull aborted — repositioning")
                    return "FARM_POSITIONING"
                end
            else
                -- Support: stay at safe position, maintain defensive CDs
                defensive:tick(player, gt)

                -- Transition when partner phase shows puller is in IB phase.
                local partner_phase = bb:get("duo.partner_phase", "")
                if partner_phase == "pull_ice_block" then
                    return "FARM_PULL_ICEBLOCK"
                end
                -- Safety timeout: if partner never reports IB phase (offline/lag), proceed after 45s.
                if gt - enter_ms > 45000 then
                    helpers.log_warn("[FARM_PULL_RUNNING] support partner-phase timeout — proceeding to IB")
                    return "FARM_PULL_ICEBLOCK"
                end
            end
        end,

        exit = function(_bb) end,
    }
end

return FarmPullRunning
