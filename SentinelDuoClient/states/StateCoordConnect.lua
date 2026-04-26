-- StateCoordConnect.lua — Wait for partner to connect (or timeout to solo mode).

local helpers = require("lib/helpers")

local StateCoordConnect = { name = "COORD_CONNECT" }

local PARTNER_TIMEOUT_MS = 120000  -- 2 minutes

function StateCoordConnect:create(ctx)
    local bb = ctx.bb

    local enter_time_ms = 0

    return {
        enter = function(_bb)
            enter_time_ms = helpers.game_time_ms()
            helpers.log("[COORD_CONNECT] waiting for partner...")
        end,

        update = function(_bb)
            if bb:get("duo.partner_connected", false) then
                helpers.log("[COORD_CONNECT] partner connected — proceeding")
                return "BUFFING"
            end

            if helpers.game_time_ms() - enter_time_ms > PARTNER_TIMEOUT_MS then
                helpers.log_warn("[COORD_CONNECT] partner timeout — proceeding solo")
                return "BUFFING"
            end
        end,

        exit = function(_bb) end,
    }
end

return StateCoordConnect
