-- StateError.lua — Terminal error state; stop everything, set bot_running = false.

local helpers = require("lib/helpers")

local StateError = { name = "ERROR" }

function StateError:create(ctx)
    local bb      = ctx.bb
    local duo_nav = ctx.duo_nav

    return {
        enter = function(_bb)
            local reason = bb:get("duo.error_reason", "unknown")
            helpers.log_err("[ERROR] enter — reason=" .. tostring(reason))
            duo_nav:stop("error")
            bb:set("duo.bot_running", false)
        end,

        update = function(_bb)
            -- Stay in ERROR; user must restart
        end,

        exit = function(_bb)
            helpers.log("[ERROR] exit")
        end,
    }
end

return StateError
