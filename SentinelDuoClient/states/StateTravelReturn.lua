-- StateTravelReturn.lua — Fly back to instance zone, walk to entrance, enter return barrier.

local helpers                = require("lib/helpers")
local FlightMasterInteractor = require("travel/FlightMasterInteractor")

local StateTravelReturn = { name = "TRAVEL_RETURN" }

local BARRIER_NAME          = "return_complete"
local ENTRANCE_ARRIVE_RANGE = 5.0
local STATE_HARD_TIMEOUT_MS = 600000  -- 10 min safety net for stuck walkback

function StateTravelReturn:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local profile      = ctx.profile

    local flight           = nil
    local walkback_started = false
    local barrier_entered  = false
    local enter_ms         = 0

    return {
        enter = function(_bb)
            helpers.log("[TRAVEL_RETURN] enter")
            walkback_started = false
            barrier_entered  = false
            enter_ms         = helpers.game_time_ms()

            flight = FlightMasterInteractor:new(duo_nav, bb, profile)
            flight:start("return_flight")
        end,

        update = function(_bb)
            -- Poll flight
            local f_state = flight:poll()

            if f_state == "failed" then
                helpers.log_warn("[TRAVEL_RETURN] flight failed — attempting walkback")
                f_state = "done"
            end

            if f_state == "done" and not walkback_started then
                walkback_started = true
                -- Follow walkback path to entrance
                local route = profile and profile.vendor_route
                if route and route.walkback_path then
                    duo_nav:follow_path(route.walkback_path)
                elseif profile and profile.entrance_position then
                    duo_nav:move_to(profile.entrance_position)
                end
                helpers.log("[TRAVEL_RETURN] walking back to entrance")
            end

            if walkback_started then
                -- Check if arrived at entrance
                local ok, player = pcall(core.object_manager.get_local_player)
                if ok and player then
                    local ok_pos, pos = pcall(player.get_position, player)
                    local dest = profile and profile.entrance_position
                    if ok_pos and pos and dest then
                        local dx = (pos.x or 0) - (dest.x or 0)
                        local dy = (pos.y or 0) - (dest.y or 0)
                        local dz = (pos.z or 0) - (dest.z or 0)
                        if math.sqrt(dx*dx + dy*dy + dz*dz) <= ENTRANCE_ARRIVE_RANGE then
                            if not barrier_entered then
                                duo_nav:stop("at_entrance")
                                bb:set("duo.at_instance_entrance", true)
                                coord_client:enter_barrier(BARRIER_NAME)
                                barrier_entered = true
                                helpers.log("[TRAVEL_RETURN] at entrance — barrier entered")
                            end
                        end
                    end
                end
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true or result == "timeout" then
                    coord_client:release_barrier(BARRIER_NAME)
                    -- Clear vendor break flag so it doesn't trigger again immediately
                    bb:set("duo.vendor_break_active", false)
                    return "BUFFING"
                end
            end

            -- Hard timeout — if walkback navigation never completes, bail out
            if helpers.game_time_ms() - enter_ms > STATE_HARD_TIMEOUT_MS then
                helpers.log_warn("[TRAVEL_RETURN] hard timeout — forcing BUFFING")
                if barrier_entered then coord_client:release_barrier(BARRIER_NAME) end
                bb:set("duo.vendor_break_active", false)
                return "BUFFING"
            end
        end,

        exit = function(_bb)
            helpers.log("[TRAVEL_RETURN] exit")
        end,
    }
end

return StateTravelReturn
