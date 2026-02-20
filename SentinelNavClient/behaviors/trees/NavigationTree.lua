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
--          ├─ Selector "FollowOrRecover"
--          │    ├─ Sequence "NormalFollow"
--          │    │    ├─ Inverter(IsStuck)
--          │    │    ├─ Inverter(IsDeviated)
--          │    │    ├─ ApplyDynamicSpeed
--          │    │    ├─ AdvanceWaypoint
--          │    │    └─ Throttle "ProactiveObstacleScan"
--          │    │         └─ Sequence "ProactiveAvoid"
--          │    │              ├─ ProbeForObstacle
--          │    │              ├─ AddAvoidanceZone
--          │    │              └─ SoftRepath
--          │    ├─ Sequence "HandleDeviation"
--          │    │    ├─ IsDeviated
--          │    │    ├─ Condition "MaxRepathNotExceeded"
--          │    │    └─ SoftRepath
--          │    └─ StuckRecoveryTree
--          └─ Throttle "PeriodicValidation"
--               └─ ValidatePath

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

    -- Normal path following (only when not stuck and not deviated)
    local normal_follow = BT.Sequence:new("NormalFollow")
    normal_follow:add(BT.Inverter:new(IsStuck(), "NotStuck"))
    normal_follow:add(BT.Inverter:new(IsDeviated(validation_service, event_bus), "NotDeviated"))
    normal_follow:add(ApplyDynamicSpeed(movement_service))
    normal_follow:add(AdvanceWaypoint(movement_service, event_bus))

    -- Proactive obstacle scanning (throttled)
    local proactive_avoid = BT.Sequence:new("ProactiveAvoid")
    proactive_avoid:add(ProbeForObstacle(obstacle_service))
    proactive_avoid:add(AddAvoidanceZone(obstacle_service))
    proactive_avoid:add(SoftRepath(nav_service, movement_service, obstacle_service, event_bus))

    normal_follow:add(BT.Throttle:new(proactive_avoid, 1.5, "ProactiveObstacleScan"))
    follow_or_recover:add(normal_follow)

    -- Handle deviation: soft repath if deviated and under max repaths
    local handle_deviation = BT.Sequence:new("HandleDeviation")
    handle_deviation:add(IsDeviated(validation_service, event_bus))
    handle_deviation:add(BT.Condition:new(function(bb)
        return bb:get("deviation.count", 0) < bb:get("config.max_deviation_repaths", 5)
    end, "MaxRepathNotExceeded"))
    handle_deviation:add(SoftRepath(nav_service, movement_service, obstacle_service, event_bus))
    follow_or_recover:add(handle_deviation)

    -- Stuck recovery (escalating 5-stage)
    follow_or_recover:add(StuckRecoveryTree.create(services))

    nav:add(follow_or_recover)

    -- Step 3: Periodic path validation (throttled)
    nav:add(BT.Throttle:new(
        ValidatePath(nav_service, validation_service),
        5.0,
        "PeriodicValidation"
    ))

    root:add(nav)

    return BT.Tree:new(root, "NavigationTree")
end

return { create = create }
