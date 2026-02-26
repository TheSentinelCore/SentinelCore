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
local TacticalPlanner = require("ai/TacticalPlanner")

local GrindService = {}

local S = BT.Status

--- Fallback node that always returns FAILURE (used when an optional dep is nil).
local function noop_node(name)
    return BT.Action:new(name or "noop", function() return S.FAILURE end)
end

--- Build a mount node that fires MountService:try_mount() when conditions are met.
--- Returns SUCCESS on the tick the mount is requested (blocking further children that
--- tick so the bot doesn't immediately start a pull while the mount cast begins).
--- Returns FAILURE when mounting is not applicable, letting the tree fall through.
local function mount_node(mount_service)
    if not mount_service then
        return noop_node("mount_noop")
    end
    return BT.Action:new("mount", function()
        if not mount_service:should_mount() then
            return S.FAILURE
        end
        mount_service:try_mount()
        -- Block this tick so nothing else (pull/explore) starts on the same frame.
        -- Next tick player.is_mounted == true → should_mount() returns false → FAILURE.
        return S.SUCCESS
    end)
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
        -- Don't start new pauses during combat.
        -- If combat interrupts an active pause, cancel it so the bot doesn't
        -- resume the same pause window the moment combat ends (phantom pause).
        local in_combat = bb:get("player.in_combat", false)
        if in_combat then
            if was_pausing and type(session_behavior.cancel_pause) == "function" then
                session_behavior:cancel_pause()
            end
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

--- Build a tactical combat node that delegates combat to TacticalSelector + TacticalPlanner.
--- Used when deps.tactical_selector is provided; falls through to CombatService otherwise.
local function build_tactical_combat_node(deps)
    local selector = deps.tactical_selector
    local planner = TacticalPlanner:new()
    local bb = deps.bb

    return BT.ReactiveSequence:new("tactical_combat", {
        -- Gate: must be in combat (same as CombatService gate)
        BT.Condition:new("in_combat_or_pulling", function()
            return bb:get("player.in_combat", false)
                or bb:get("combat.has_aggro", false)
                or (bb:get("combat.target") ~= nil and not bb:get("player.is_dead", false))
        end),

        -- Select best tactic and tick its planner
        BT.Action:new("tactical_tick", function()
            local ctx = {
                in_combat = bb:get("player.in_combat", false),
                has_target = bb:get("combat.target") ~= nil,
                target_alive = false,
                enemy_count = bb:get("combat.enemy_count", 0),
                player_mana_pct = 0,
                pack_count = bb:get("pack.count", 0),
            }

            -- Check target alive
            local target = bb:get("combat.target")
            if target then
                local ok, hp = pcall(function() return target:get_health() end)
                ctx.target_alive = ok and hp and hp > 0
            end

            -- Player mana (read directly from game object; blackboard has no mana keys)
            local player_obj = bb:get("player.object")
            if player_obj then
                local ok_cur, cur = pcall(function() return player_obj:get_power(0) end)
                local ok_max, mx  = pcall(function() return player_obj:get_max_power(0) end)
                if ok_cur and ok_max and type(cur) == "number" and type(mx) == "number" and mx > 0 then
                    ctx.player_mana_pct = cur / mx
                end
            end

            local active = selector:select(ctx)
            if not active then return BT.Status.FAILURE end

            bb:set("tactical.target_config", active:get_target_config())
            bb:set("tactical.explore_config", active:get_explore_config())
            bb:set("tactical.rest_config", active:get_rest_config())

            planner:set_tactic(active)
            return planner:tick(ctx, deps)
        end),
    })
end

---@param deps table { bb, evaluator, swing_timer, human_timing, session_behavior?, spell_executor, navigation, rotation_engine?, targeting, vendor_service, exploration_service, loot_service, death_recovery_service, mount_service?, tactical_selector? }
---@return table BT Selector node
function GrindService.build(deps)
    -- Wire existing combat/pull nodes for SingleTargetTactic phase delegation
    if deps.tactical_selector then
        deps.combat_node = CombatService.build_bt(deps.bb, deps.evaluator, deps.swing_timer, deps.human_timing, deps.spell_executor, deps.navigation)
        deps.pull_node = PullService.build(deps.bb, deps.navigation, deps.rotation_engine)
    end

    return BT.ReactiveSelector:new("grind_root", {
        fatigue_sync_node(deps.human_timing, deps.session_behavior),
        deps.death_recovery_service and deps.death_recovery_service:build() or noop_node("death_noop"),
        CombatInterruptService.build(deps.bb),
        deps.tactical_selector
            and build_tactical_combat_node(deps)
            or CombatService.build_bt(deps.bb, deps.evaluator, deps.swing_timer, deps.human_timing, deps.spell_executor, deps.navigation),
        FleeService.build(deps.bb, deps.navigation),
        idle_pause_node(deps.bb, deps.session_behavior, deps.navigation),
        deps.loot_service and deps.loot_service:build() or noop_node("loot_noop"),
        RestService.build(deps.bb, deps.navigation),
        deps.vendor_service and deps.vendor_service:build() or noop_node("vendor_noop"),
        MaintenanceService.build(deps.bb),
        mount_node(deps.mount_service),
        deps.pull_node or PullService.build(deps.bb, deps.navigation, deps.rotation_engine),
        deps.targeting and deps.targeting:build() or noop_node("target_noop"),
        deps.exploration_service and deps.exploration_service:build() or noop_node("explore_noop"),
    })
end

return GrindService
