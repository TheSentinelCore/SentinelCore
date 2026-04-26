-- StateResetting.lua — Enter barrier, leader resets instances, check lockout, loop back to BUFFING.

local helpers = require("lib/helpers")

local StateResetting = { name = "RESETTING" }

local BARRIER_NAME = "ready_to_reset"

function StateResetting:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client

    local barrier_entered = false
    local reset_triggered = false

    return {
        enter = function(_bb)
            helpers.log("[RESETTING] enter")
            barrier_entered = false
            reset_triggered = false
            coord_client:enter_barrier(BARRIER_NAME)
            barrier_entered = true
        end,

        update = function(_bb)
            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true or result == "timeout" then
                    coord_client:release_barrier(BARRIER_NAME)
                    barrier_entered = false

                    -- Only mage_a (party leader) calls reset
                    local my_id = bb:get("duo.my_client_id", "")
                    if my_id == "mage_a" and not reset_triggered then
                        reset_triggered = true
                        local ok, err = pcall(core.game_ui.reset_instances)
                        if ok then
                            coord_client:record_reset()
                            helpers.log("[RESETTING] instances reset")
                        else
                            helpers.log_err("[RESETTING] reset_instances error: " .. tostring(err))
                        end
                    end

                    -- Check lockout
                    if bb:get("duo.lockout.near_limit", false) then
                        helpers.log_warn("[RESETTING] near lockout limit")
                    end
                    if bb:get("duo.lockout.wait_secs", 0) > 0 then
                        helpers.log("[RESETTING] must wait for lockout — WAITING_LOCKOUT")
                        return "WAITING_LOCKOUT"
                    end

                    -- Clear farm state, loop back
                    bb:clear_prefix("duo.farm_")
                    bb:set("duo.pull_index", 0)
                    local runs = (bb:get("duo.runs_completed", 0)) + 1
                    bb:set("duo.runs_completed", runs)
                    helpers.log("[RESETTING] run #" .. runs .. " complete — BUFFING")
                    return "BUFFING"
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[RESETTING] exit")
        end,
    }
end

return StateResetting
