-- StateVendoring.lua — Sell all items, conjure supplies, signal vendor_complete barrier.

local helpers          = require("lib/helpers")
local VendorInteractor = require("travel/VendorInteractor")

local StateVendoring = { name = "VENDORING" }

local BARRIER_NAME = "vendor_complete"

function StateVendoring:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local sc           = ctx.spell_catalog
    local profile      = ctx.profile

    local vendor         = nil
    local barrier_entered = false
    local conjure_done   = false

    return {
        enter = function(_bb)
            helpers.log("[VENDORING] enter")
            barrier_entered = false
            conjure_done    = false

            vendor = VendorInteractor:new(duo_nav, bb, profile)
            vendor:start()
        end,

        update = function(_bb)
            -- Poll vendor interaction
            local v_state = vendor:poll()

            if v_state == "failed" then
                helpers.log_err("[VENDORING] vendor interaction failed")
                -- fall through anyway
                v_state = "done"
            end

            if v_state == "done" and not conjure_done then
                -- Conjure water after selling
                local ok_pl, player = pcall(core.object_manager.get_local_player)
                if ok_pl and player then
                    local cw_id = sc:resolve("Conjure Water", player)
                    if cw_id and sc:is_ready("Conjure Water", player) then
                        pcall(core.input.cast_target_spell, cw_id, player)
                        helpers.log("[VENDORING] conjuring water")
                    end
                end
                conjure_done = true
            end

            if conjure_done and not barrier_entered then
                bb:set("duo.vendor_sell_complete", true)
                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true or result == "timeout" then
                    coord_client:release_barrier(BARRIER_NAME)
                    return "TRAVEL_RETURN"
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[VENDORING] exit")
        end,
    }
end

return StateVendoring
