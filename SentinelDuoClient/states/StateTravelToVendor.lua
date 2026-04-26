-- StateTravelToVendor.lua — Hearth to vendor zone, enter vendor barriers.

local helpers            = require("lib/helpers")
local HearthstoneManager = require("travel/HearthstoneManager")

local StateTravelToVendor = { name = "TRAVEL_TO_VENDOR" }

local BARRIER_READY  = "ready_to_vendor"

function StateTravelToVendor:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local profile      = ctx.profile

    local hs_mgr          = nil
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[TRAVEL_TO_VENDOR] enter")
            bb:set("duo.vendor_sell_complete", false)
            barrier_entered = false

            hs_mgr = HearthstoneManager:new(bb, profile)
            hs_mgr:start()
        end,

        update = function(_bb)
            -- Poll hearthstone
            local hs_state = hs_mgr:poll()

            if hs_state == "failed" then
                helpers.log_err("[TRAVEL_TO_VENDOR] hearthstone failed — trying anyway")
                hs_mgr:reset()
                hs_state = "done"  -- fall through to vendor
            end

            if (hs_state == "done") and not barrier_entered then
                coord_client:enter_barrier(BARRIER_READY)
                barrier_entered = true
                helpers.log("[TRAVEL_TO_VENDOR] hearthstone done — barrier entered")
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_READY)
                if result == true or result == "timeout" then
                    coord_client:release_barrier(BARRIER_READY)
                    return "VENDORING"
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[TRAVEL_TO_VENDOR] exit")
        end,
    }
end

return StateTravelToVendor
