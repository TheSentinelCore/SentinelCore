-- FarmPositioning.lua — Navigate to pull start position, enter pull_start barrier.

local helpers = require("lib/helpers")

local FarmPositioning = { name = "FARM_POSITIONING" }

local BARRIER_NAME       = "pull_start"
local NAV_FAIL_WAIT_MS   = 5000    -- treat as arrived after this long if nav failed
local STATE_HARD_TIMEOUT = 120000  -- bail out of entire state after 120s (e.g. server unreachable)

function FarmPositioning:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav

    local barrier_entered = false
    local enter_ms        = 0

    return {
        enter = function(_bb)
            helpers.log("[FARM_POSITIONING] enter")
            barrier_entered = false
            enter_ms        = helpers.game_time_ms()
            bb:set("duo.all_mobs_dead", false)
            bb:set("duo.farm_sub_state", "positioning")

            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)
            if not pull then return end

            if is_puller then
                -- Navigate to first pull waypoint
                local path = pull.pull_path or {}
                if #path > 0 then
                    duo_nav:move_to(path[1])
                end
            else
                -- Support goes to safe position
                if pull.safe_position then
                    duo_nav:move_to(pull.safe_position)
                end
            end
        end,

        update = function(_bb)
            local is_puller = bb:get("duo.is_puller", false)
            local pull      = bb:get("duo.current_pull_def", nil)
            if not pull then return "FARM_POSITIONING" end

            -- Check arrival
            local nav_state  = duo_nav:get_state()
            local elapsed_ms = helpers.game_time_ms() - enter_ms

            local arrived = false
            if is_puller then
                local path = pull.pull_path or {}
                arrived = duo_nav:is_arrived(4.0) or #path == 0
            else
                arrived = duo_nav:is_arrived(4.0)
            end

            -- If we haven't arrived within the timeout window, treat as arrived in-place.
            -- This handles the case where navmesh 422s keep cycling (SentinelNavClient
            -- retries internally so state never reaches "failed"). Coordinates need
            -- to be captured in-game via ProfileTab to resolve the root cause.
            if not arrived and elapsed_ms >= NAV_FAIL_WAIT_MS then
                helpers.log_warn(string.format(
                    "[FARM_POSITIONING] positioning timeout (%dms, nav=%s) — treating as arrived in-place",
                    elapsed_ms, nav_state))
                arrived = true
            end

            if arrived and not barrier_entered then
                local is_first_pull = bb:get("duo.farm_local_pull_idx", 0) == 0

                if is_first_pull then
                    -- On the first pull of a run both roles skip the pull_start barrier.
                    -- The puller starts running, support navigates to safe_position concurrently;
                    -- first real sync point is ice_block_up (puller has mobs + is IB'd,
                    -- support is positioned to Blizzard).
                    helpers.log("[FARM_POSITIONING] first pull — skipping pull_start barrier")
                    duo_nav:stop("at_position")
                    return "FARM_PULL_RUNNING"
                end

                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
                duo_nav:stop("at_position")
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true then
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_PULL_RUNNING"
                elseif result == "timeout" then
                    helpers.log_warn("[FARM_POSITIONING] barrier timeout")
                    coord_client:release_barrier(BARRIER_NAME)
                    return "FARM_PULL_RUNNING"
                end
            end

            -- Hard state timeout: if we've been here too long (e.g. server unreachable),
            -- proceed solo rather than waiting forever.
            if elapsed_ms >= STATE_HARD_TIMEOUT then
                helpers.log_warn(string.format(
                    "[FARM_POSITIONING] state hard timeout (%dms) — proceeding solo", elapsed_ms))
                if barrier_entered then
                    coord_client:release_barrier(BARRIER_NAME)
                end
                return "FARM_PULL_RUNNING"
            end
        end,

        exit = function(_bb)
            if barrier_entered then
                coord_client:release_barrier(BARRIER_NAME)
                barrier_entered = false
            end
        end,
    }
end

return FarmPositioning
