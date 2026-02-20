-- NavigationTree.lua
-- Root navigation behavior tree composing all BT behaviors.
--
-- Structure:
--   Selector "NavigationRoot"
--     ├─ Condition "NotNavigating" (guard: skip if not navigating)
--     ├─ Sequence "HandleCastingDeferral"
--     │    ├─ IsCasting
--     │    └─ Action "DeferMovement" (RUNNING)
--     └─ Sequence "HandleNavigation"
--          ├─ Selector "EnsurePath"
--          │    ├─ HasPath
--          │    └─ RequestPath
--          └─ Selector "FollowOrRecover"
--               ├─ ReactiveSequence "NormalFollow"
--               │    ├─ Inverter(IsStuck)              ← re-evaluated EVERY tick
--               │    ├─ Inverter(IsDeviated)            ← re-evaluated EVERY tick
--               │    └─ Parallel "DoFollowing" (require_all)
--               │         ├─ ApplyDynamicSpeed
--               │         ├─ AdvanceWaypoint
--               │         ├─ Selector "OptionalProactive"  ← absorbs FAILURE
--               │         │    ├─ Throttle "ProactiveObstacleScan"
--               │         │    │    └─ Sequence "ProactiveGuarded"
--               │         │    │         ├─ Condition "ProactiveObstacleEnabled"
--               │         │    │         └─ Sequence "ProactiveAvoid"
--               │         │    │              ├─ ProbeForObstacle
--               │         │    │              ├─ AddAvoidanceZone
--               │         │    │              └─ SoftRepath
--               │         │    └─ Action "ProactiveSkip" (SUCCESS)
--               │         └─ Selector "OptionalValidation"  ← absorbs FAILURE
--               │              ├─ Throttle "PeriodicValidation"
--               │              │    └─ ValidatePath
--               │              └─ Action "ValidationSkip" (SUCCESS)
--               ├─ Cooldown "RepathCooldown"
--               │    └─ Sequence "HandleDeviation"
--               │         ├─ IsDeviated
--               │         ├─ Condition "MaxRepathNotExceeded"
--               │         └─ SoftRepath
--               └─ StuckRecoveryTree

local BT = require("lib/BehaviorTree")

-- Conditions
local IsCasting = require("behaviors/conditions/IsCasting")
local HasPath = require("behaviors/conditions/HasPath")
local IsStuck = require("behaviors/conditions/IsStuck")
local IsDeviated = require("behaviors/conditions/IsDeviated")

-- Actions
local RequestPath = require("behaviors/actions/RequestPath")
local AdvanceWaypoint = require("behaviors/actions/AdvanceWaypoint")
local ApplyDynamicSpeed = require("behaviors/actions/ApplyDynamicSpeed")
local ProbeForObstacle = require("behaviors/actions/ProbeForObstacle")
local AddAvoidanceZone = require("behaviors/actions/AddAvoidanceZone")
local SoftRepath = require("behaviors/actions/SoftRepath")
local ValidatePath = require("behaviors/actions/ValidatePath")

-- Sub-trees
local StuckRecoveryTree = require("behaviors/trees/StuckRecoveryTree")

--- Create the root navigation tree.
---@param services table { navigation, movement, obstacle, validation, event_bus }
---@return table BT.Tree instance
local function create(services)
    local nav_service = services.navigation
    local movement_service = services.movement
    local obstacle_service = services.obstacle
    local validation_service = services.validation
    local event_bus = services.event_bus

    local root = BT.Selector:new("NavigationRoot")

    -- Guard: if not navigating, succeed (skip entire tree)
    root:add(BT.Condition:new(function(bb)
        return bb:get("hsm.state") ~= "navigating"
    end, "NotNavigating"))

    -- Handle casting deferral: pause navigation while casting
    local defer = BT.Sequence:new("HandleCastingDeferral")
    defer:add(IsCasting())
    defer:add(BT.Action:new(function(bb, dt)
        return BT.RUNNING -- just wait until cast finishes
    end, "DeferMovement"))
    root:add(defer)

    -- Main navigation sequence
    local nav = BT.Sequence:new("HandleNavigation")

    -- Step 1: Ensure we have a valid path
    local ensure_path = BT.Selector:new("EnsurePath")
    ensure_path:add(HasPath())
    ensure_path:add(RequestPath(nav_service, movement_service, event_bus))
    nav:add(ensure_path)

    -- Step 2: Follow path or recover from issues
    local follow_or_recover = BT.Selector:new("FollowOrRecover")

    -- Normal path following (reactive guards + concurrent actions)
    -- ReactiveSequence ensures IsStuck/IsDeviated guards are checked EVERY tick.
    -- Parallel ensures AdvanceWaypoint, ProactiveObstacleScan, and PeriodicValidation
    -- all run every tick concurrently.
    local normal_follow = BT.ReactiveSequence:new("NormalFollow")
    normal_follow:add(BT.Inverter:new(IsStuck(), "NotStuck"))
    normal_follow:add(BT.Inverter:new(IsDeviated(validation_service, event_bus), "NotDeviated"))

    -- Concurrent actions: all tick every frame
    local do_following = BT.Parallel:new("require_all", "DoFollowing")
    do_following:add(ApplyDynamicSpeed(movement_service))
    do_following:add(AdvanceWaypoint(movement_service, event_bus))

    -- Proactive obstacle scanning (guarded by config toggle, throttled by config interval)
    local proactive_avoid = BT.Sequence:new("ProactiveAvoid")
    proactive_avoid:add(ProbeForObstacle(obstacle_service))
    proactive_avoid:add(AddAvoidanceZone(obstacle_service))
    proactive_avoid:add(SoftRepath(nav_service, movement_service, obstacle_service, event_bus, {
        reason = "proactive_obstacle",
        count_deviation = false,
    }))

    local proactive_guarded = BT.Sequence:new("ProactiveGuarded")
    proactive_guarded:add(BT.Condition:new(function(bb)
        return bb:get("config.proactive_obstacle_check", true)
    end, "ProactiveObstacleEnabled"))
    proactive_guarded:add(proactive_avoid)

    -- Wrap optional children in Selectors to absorb FAILURE (no obstacle found / path valid
    -- are normal outcomes that shouldn't kill the Parallel)
    local optional_proactive = BT.Selector:new("OptionalProactive")
    optional_proactive:add(BT.Throttle:new(proactive_guarded, 1.5, "ProactiveObstacleScan",
        "config.proactive_obstacle_interval"))
    optional_proactive:add(BT.Action:new(function() return BT.SUCCESS end, "ProactiveSkip"))
    do_following:add(optional_proactive)

    -- Periodic path validation (moved here from unreachable HandleNavigation child 3)
    local optional_validation = BT.Selector:new("OptionalValidation")
    optional_validation:add(BT.Throttle:new(
        ValidatePath(nav_service, validation_service),
        5.0,
        "PeriodicValidation",
        "config.path_check_interval"
    ))
    optional_validation:add(BT.Action:new(function() return BT.SUCCESS end, "ValidationSkip"))
    do_following:add(optional_validation)

    normal_follow:add(do_following)
    follow_or_recover:add(normal_follow)

    -- Handle deviation: soft repath if deviated and under max repaths
    local handle_deviation = BT.Sequence:new("HandleDeviation")
    handle_deviation:add(IsDeviated(validation_service, event_bus))
    handle_deviation:add(BT.Condition:new(function(bb)
        local count = bb:get("deviation.count", 0)
        local max = bb:get("config.max_deviation_repaths", 5)
        if count >= max then
            bb:set("nav.fail_reason", "max_repath_exceeded")
            bb:set("nav.fail_detail", "deviation repath budget exhausted")
            return false
        end
        return true
    end, "MaxRepathNotExceeded"))
    handle_deviation:add(SoftRepath(nav_service, movement_service, obstacle_service, event_bus, {
        reason = "deviation",
        count_deviation = true,
    }))
    follow_or_recover:add(BT.Cooldown:new(handle_deviation, 0.1, "RepathCooldown", "config.repath_cooldown"))

    -- Stuck recovery (escalating 5-stage)
    follow_or_recover:add(StuckRecoveryTree.create(services))

    nav:add(follow_or_recover)

    root:add(nav)

    return BT.Tree:new(root, "NavigationTree")
end

return { create = create }
