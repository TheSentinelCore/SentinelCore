-- StateFarming.lua — Farm loop controller. Owns the farm sub-FSM.

local helpers      = require("lib/helpers")
local StateMachine = require("core/StateMachine")

-- Farm sub-state modules
local FarmPositioning   = require("states/farm/FarmPositioning")
local FarmPullRunning   = require("states/farm/FarmPullRunning")
local FarmPullIceBlock  = require("states/farm/FarmPullIceBlock")
local FarmAoeOpening    = require("states/farm/FarmAoeOpening")
local FarmIceBlockCancel = require("states/farm/FarmIceBlockCancel")
local FarmAoeBoth       = require("states/farm/FarmAoeBoth")
local FarmLooting       = require("states/farm/FarmLooting")
local FarmAdvance       = require("states/farm/FarmAdvance")

local StateFarming = { name = "FARMING" }

function StateFarming:create(ctx)
    local bb      = ctx.bb
    local profile = ctx.profile

    local farm_fsm = nil

    local function build_farm_fsm()
        local sub_mods = {
            FarmPositioning,
            FarmPullRunning,
            FarmPullIceBlock,
            FarmAoeOpening,
            FarmIceBlockCancel,
            FarmAoeBoth,
            FarmLooting,
            FarmAdvance,
        }

        local states_table = {}
        for _, mod in ipairs(sub_mods) do
            states_table[mod.name] = mod:create(ctx)
        end

        -- FARM_EXIT is a sentinel state that signals the parent to transition out
        states_table["FARM_EXIT"] = {
            enter = function(_bb)
                helpers.log("[FARM_EXIT] farm sub-FSM complete")
            end,
            update = function(_bb)
                return nil  -- stay; parent StateFarming detects current sub-state == FARM_EXIT
            end,
        }

        return StateMachine:new("FarmSubFSM", states_table, "FARM_POSITIONING")
    end

    return {
        enter = function(_bb)
            helpers.log("[FARMING] enter")
            bb:set("duo.farm_exit_reason", nil)
            -- Local per-run counter — decoupled from server's pull_index which
            -- persists across runs and has async update delays.
            bb:set("duo.farm_local_pull_idx", 0)

            -- Always start from the first pull of the profile for this run.
            local pulls = profile and profile.pulls or {}
            local pull_def = pulls[1]
            if pull_def then
                bb:set("duo.current_pull_def", pull_def)
            else
                helpers.log_warn("[FARMING] no pull defs in profile")
            end

            farm_fsm = build_farm_fsm()
        end,

        update = function(_bb)
            -- Escalation exits
            if bb:get("player.is_dead", false) then
                helpers.log("[FARMING] player dead — exit to DEAD")
                return "DEAD"
            end

            -- Vendor break from coord server
            if bb:get("duo.vendor_break_active", false) then
                bb:set("duo.farm_exit_reason", "vendor")
                helpers.log("[FARMING] vendor break active — EXITING")
                return "EXITING"
            end

            if not farm_fsm then return end

            -- Tick farm sub-FSM
            farm_fsm:tick(bb)

            -- Sync sub-state name for heartbeat phase reporting
            local sub_state = farm_fsm:get_current_state()
            bb:set("duo.farm_sub_state_name", sub_state)

            -- Check if sub-FSM has reached the exit sentinel
            if sub_state == "FARM_EXIT" then
                return "EXITING"
            end
        end,

        exit = function(_bb)
            helpers.log("[FARMING] exit")
            farm_fsm = nil
        end,
    }
end

return StateFarming
