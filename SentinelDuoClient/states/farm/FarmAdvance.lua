-- FarmAdvance.lua — Advance pull index, check vendor/complete, loop back to POSITIONING.

local helpers = require("lib/helpers")

local FarmAdvance = { name = "FARM_ADVANCE" }

function FarmAdvance:create(ctx)
    local bb      = ctx.bb
    local profile = ctx.profile

    return {
        enter = function(_bb)
            helpers.log("[FARM_ADVANCE] enter")
            bb:set("duo.farm_sub_state", "positioning")
        end,

        update = function(_bb)
            -- Use local per-run counter (not server pull_index which has async lag
            -- and persists stale across runs until server is explicitly reset).
            local pull_index = bb:get("duo.farm_local_pull_idx", 0)
            local pulls      = profile and profile.pulls or {}

            helpers.log("[FARM_ADVANCE] local_pull_idx=" .. pull_index .. " total=" .. #pulls)

            -- Check completion BEFORE accessing pulls array
            if pull_index >= #pulls then
                helpers.log("[FARM_ADVANCE] all pulls done — farm complete")
                bb:set("duo.farm_exit_reason", "complete")
                return "FARM_EXIT"
            end

            -- Update current pull definition (safe: index is valid after guard above)
            local new_pull = pulls[pull_index + 1]  -- 1-based Lua indexing
            if new_pull then
                bb:set("duo.current_pull_def", new_pull)
            end

            -- Check vendor break requested
            if bb:get("duo.vendor_break_active", false) then
                helpers.log("[FARM_ADVANCE] vendor break requested")
                bb:set("duo.farm_exit_reason", "vendor")
                return "FARM_EXIT"
            end

            return "FARM_POSITIONING"
        end,

        exit = function(_bb) end,
    }
end

return FarmAdvance
