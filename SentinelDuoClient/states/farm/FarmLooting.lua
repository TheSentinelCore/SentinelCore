-- FarmLooting.lua — Wait for loot settle, loot all corpses, enter loot_complete barrier, advance pull.

local helpers     = require("lib/helpers")
local LootEngine  = require("loot/LootEngine")

local FarmLooting = { name = "FARM_LOOTING" }

local BARRIER_NAME = "loot_complete"

function FarmLooting:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local sc           = ctx.spell_catalog

    local loot_engine     = LootEngine:new(duo_nav, bb)
    local enter_time      = 0
    local settle_delay    = 0
    local looting_started = false
    local loot_done       = false
    local barrier_entered = false

    return {
        enter = function(_bb)
            helpers.log("[FARM_LOOTING] enter")
            bb:set("duo.farm_sub_state", "looting")
            enter_time      = helpers.game_time_ms()
            looting_started = false
            loot_done       = false
            barrier_entered = false

            -- Jittered settle delay
            local pull   = bb:get("duo.current_pull_def", nil)
            local timing = pull and pull.timing or {}
            local base   = timing.loot_settle_ms or 1500
            settle_delay = helpers.jitter(base, 0.25)
        end,

        update = function(_bb)
            local gt   = helpers.game_time_ms()
            local pull = bb:get("duo.current_pull_def", nil)

            -- Wait for settle delay
            if gt - enter_time < settle_delay then return end

            -- Start looting
            if not looting_started then
                looting_started = true
                local center = pull and pull.blizzard_center
                if center then
                    loot_engine:loot_all_in_area(center, 30)
                end
            end

            -- Drive the loot navigation/interaction loop every frame
            if looting_started and not loot_done then
                loot_engine:poll()
            end

            -- Check loot complete
            if not loot_done then
                if loot_engine:is_complete() then
                    loot_done = true
                    helpers.log("[FARM_LOOTING] loot complete")
                end
                -- Safety timeout
                if gt - enter_time > 30000 then
                    loot_done = true
                    helpers.log_warn("[FARM_LOOTING] loot timeout")
                end
            end

            -- Barrier and advance pull when done
            if loot_done and not barrier_entered then
                coord_client:enter_barrier(BARRIER_NAME)
                barrier_entered = true
            end

            if barrier_entered then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true or result == "timeout" then
                    if result == "timeout" then
                        helpers.log_warn("[FARM_LOOTING] barrier timeout")
                    end
                    coord_client:release_barrier(BARRIER_NAME)
                    -- Increment local per-run pull counter BEFORE advancing to FarmAdvance
                    local local_idx = bb:get("duo.farm_local_pull_idx", 0)
                    bb:set("duo.farm_local_pull_idx", local_idx + 1)
                    coord_client:advance_pull()
                    return "FARM_ADVANCE"
                end
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

return FarmLooting
