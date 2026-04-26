-- StatePaused.lua — Bot paused by user; resume when duo.user_paused is cleared.

local helpers = require("lib/helpers")

local StatePaused = { name = "PAUSED" }

function StatePaused:create(ctx)
    local bb      = ctx.bb
    local duo_nav = ctx.duo_nav

    local previous_state = nil

    return {
        enter = function(_bb)
            helpers.log("[PAUSED] enter")
            previous_state = bb:get("duo.pre_pause_state", "BUFFING")
            duo_nav:stop("paused")
        end,

        update = function(_bb)
            if not bb:get("duo.user_paused", false) then
                helpers.log("[PAUSED] resuming → " .. tostring(previous_state))
                return previous_state or "BUFFING"
            end
        end,

        exit = function(_bb)
            helpers.log("[PAUSED] exit")
        end,
    }
end

return StatePaused
