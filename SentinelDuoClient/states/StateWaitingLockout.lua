-- StateWaitingLockout.lua — Sit out the lockout window; rebuff and drink.

local helpers = require("lib/helpers")

local StateWaitingLockout = { name = "WAITING_LOCKOUT" }

function StateWaitingLockout:create(ctx)
    local bb = ctx.bb

    return {
        enter = function(_bb)
            local wait_secs = bb:get("duo.lockout.wait_secs", 0)
            helpers.log("[WAITING_LOCKOUT] enter — wait=" .. wait_secs .. "s")
        end,

        update = function(_bb)
            local wait_secs = bb:get("duo.lockout.wait_secs", 0)

            if wait_secs <= 0 then
                helpers.log("[WAITING_LOCKOUT] lockout cleared — BUFFING")
                return "BUFFING"
            end

            -- Could add drinking/rebuffing here via DefensiveManager etc.
            -- For now, just wait.
        end,

        exit = function(_bb)
            helpers.log("[WAITING_LOCKOUT] exit")
        end,
    }
end

return StateWaitingLockout
