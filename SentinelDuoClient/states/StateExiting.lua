-- StateExiting.lua — Exit the instance (die or walk out), wait at barrier, route to next step.

local helpers = require("lib/helpers")

local StateExiting = { name = "EXITING" }

local BARRIER_NAME     = "ready_to_exit"
local EXIT_TIMEOUT_MS  = 120000

function StateExiting:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local profile      = ctx.profile

    local enter_time      = 0
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[EXITING] enter")
            barrier_entered = false
            enter_time      = helpers.game_time_ms()

            -- Navigate to exit position
            if profile and profile.exit_position then
                duo_nav:move_to(profile.exit_position)
            end
        end,

        update = function(_bb)
            local gt          = helpers.game_time_ms()
            local in_instance = bb:get("player.in_instance", false)

            -- Outside instance or timeout → enter barrier
            if not in_instance and not barrier_entered then
                duo_nav:stop("exited_instance")
                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
                helpers.log("[EXITING] outside instance — barrier entered")
            end

            if gt - enter_time > EXIT_TIMEOUT_MS and not barrier_entered then
                helpers.log_warn("[EXITING] timeout — forcing barrier")
                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true or result == "timeout" then
                    coord_client:release_barrier(BARRIER_NAME)
                    local reason = bb:get("duo.farm_exit_reason", "complete")
                    if reason == "vendor" then
                        return "TRAVEL_TO_VENDOR"
                    else
                        return "RESETTING"
                    end
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[EXITING] exit")
        end,
    }
end

return StateExiting
