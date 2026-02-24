local BT = require("ai/BehaviorTree")
local get_now = require("lib/TimeHelper").get_now
local DeathRecoveryService = require("services/DeathRecoveryService")
local CombatInterruptService = require("services/CombatInterruptService")
local CombatService = require("services/CombatService")
local FleeService = require("services/FleeService")
local LootService = require("services/LootService")
local RestService = require("services/RestService")
local VendorService = require("services/VendorService")
local MaintenanceService = require("services/MaintenanceService")
local PullService = require("services/PullService")
local TargetingService = require("services/TargetingService")
local ExplorationService = require("services/ExplorationService")

local GrindService = {}

local S = BT.Status

--- Fallback node that always returns FAILURE (used when an optional dep is nil).
local function noop_node(name)
    return BT.Action:new(name or "noop", function() return S.FAILURE end)
end

--- Build a transparent node that syncs session fatigue into HumanTiming each tick.
--- Always returns FAILURE so ReactiveSelector falls through to real children.
local function fatigue_sync_node(human_timing, session_behavior)
    if not human_timing or not session_behavior then
        return noop_node("fatigue_noop")
    end
    return BT.Action:new("fatigue_sync", function()
        local now = get_now()
        local factor = session_behavior:get_fatigue_factor(now)
        human_timing:set_fatigue(factor - 1.0)
        return S.FAILURE
    end)
end

--- Build an idle-pause node that blocks peaceful activities when SessionBehavior
--- decides to simulate an AFK pause (5% chance every 300s, 2-8s duration).
--- Returns SUCCESS (blocking) during pause, FAILURE (pass-through) otherwise.
--- Placed after combat/flee so the bot still fights if attacked during a pause.
local function idle_pause_node(bb, session_behavior, navigation)
    if not session_behavior then
        return noop_node("idle_pause_noop")
    end
    local was_pausing = false
    return BT.Action:new("idle_pause", function()
        -- Don't start new pauses during combat (active pauses still drain naturally)
        local in_combat = bb:get("player.in_combat", false)
        if in_combat then
            was_pausing = false
            return S.FAILURE
        end

        local now = get_now()
        local pausing = session_behavior:check_idle_pause(now)
        if pausing then
            if not was_pausing and navigation and navigation.stop then
                pcall(function() navigation:stop() end)
            end
            was_pausing = true
            return S.SUCCESS
        end
        was_pausing = false
        return S.FAILURE
    end)
end

---@param deps table { bb, evaluator, swing_timer, human_timing, spell_executor, navigation, targeting, vendor_service, exploration_service, loot_service, death_recovery_service, session_behavior? }
---@return table BT Selector node
function GrindService.build(deps)
    return BT.ReactiveSelector:new("grind_root", {
        fatigue_sync_node(deps.human_timing, deps.session_behavior),
        deps.death_recovery_service and deps.death_recovery_service:build() or noop_node("death_noop"),
        CombatInterruptService.build(deps.bb),
        CombatService.build_bt(deps.bb, deps.evaluator, deps.swing_timer, deps.human_timing, deps.spell_executor, deps.navigation),
        FleeService.build(deps.bb, deps.navigation),
        idle_pause_node(deps.bb, deps.session_behavior, deps.navigation),
        deps.loot_service and deps.loot_service:build() or noop_node("loot_noop"),
        RestService.build(deps.bb, deps.navigation),
        deps.vendor_service and deps.vendor_service:build() or noop_node("vendor_noop"),
        MaintenanceService.build(deps.bb),
        PullService.build(deps.bb, deps.navigation),
        deps.targeting and deps.targeting:build() or noop_node("target_noop"),
        deps.exploration_service and deps.exploration_service:build() or noop_node("explore_noop"),
    })
end

return GrindService
