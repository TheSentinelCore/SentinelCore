-- StuckRecoveryTree.lua
-- 5-stage escalating stuck recovery as a BT Selector.
--
-- Stage 1 (count=1): Jump
-- Stage 2 (count=2): Probe for obstacle + add avoidance zone + repath
-- Stage 3 (count=3): Strafe left + jump
-- Stage 4 (count=4): Move backward + jump
-- Stage 5 (count>=5): Add zone at position + repath
-- Beyond max: signal failure to HSM
local BT = require("lib/BehaviorTree")
local IsStuck = require("behaviors/conditions/IsStuck")
local Jump = require("behaviors/actions/Jump")
local Strafe = require("behaviors/actions/Strafe")
local MoveBackward = require("behaviors/actions/MoveBackward")
local ProbeForObstacle = require("behaviors/actions/ProbeForObstacle")
local AddAvoidanceZone = require("behaviors/actions/AddAvoidanceZone")
local Repath = require("behaviors/actions/Repath")

--- Helper: condition that checks stuck.count == n
local function stuck_count_eq(n)
    return BT.Condition:new(function(bb)
        return bb:get("stuck.count", 0) == n
    end, "StuckCount==" .. n)
end

--- Helper: condition that checks stuck.count >= n
local function stuck_count_gte(n)
    return BT.Condition:new(function(bb)
        return bb:get("stuck.count", 0) >= n
    end, "StuckCount>=" .. n)
end

--- Create the stuck recovery tree.
---@param services table { navigation, movement, obstacle, event_bus }
---@return table BT Selector node
local function create(services)
    local nav_service = services.navigation
    local movement_service = services.movement
    local obstacle_service = services.obstacle
    local event_bus = services.event_bus

    local tree = BT.Selector:new("StuckRecovery")

    -- Guard: if not stuck, succeed immediately (skip recovery)
    tree:add(BT.Inverter:new(IsStuck(), "NotStuck"))

    -- Stage 1: Jump
    local try_jump = BT.Sequence:new("TryJump")
    try_jump:add(stuck_count_eq(1))
    try_jump:add(Jump())
    tree:add(try_jump)

    -- Stage 2: Probe + avoidance zone + repath
    local try_probe = BT.Sequence:new("TryProbeAndRepath")
    try_probe:add(stuck_count_eq(2))
    try_probe:add(ProbeForObstacle(obstacle_service))
    try_probe:add(AddAvoidanceZone(obstacle_service))
    try_probe:add(Repath(nav_service, movement_service, obstacle_service, event_bus))
    tree:add(try_probe)

    -- Stage 3: Strafe + jump
    local try_strafe = BT.Sequence:new("TryStrafeAndJump")
    try_strafe:add(stuck_count_eq(3))
    try_strafe:add(Strafe(0.5, "left"))
    try_strafe:add(Jump())
    tree:add(try_strafe)

    -- Stage 4: Backward + jump
    local try_backward = BT.Sequence:new("TryBacktrackAndJump")
    try_backward:add(stuck_count_eq(4))
    try_backward:add(MoveBackward(1.0))
    try_backward:add(Jump())
    tree:add(try_backward)

    -- Stage 5: Add zone at position + repath
    local try_zone = BT.Sequence:new("TryZoneAndRepath")
    try_zone:add(stuck_count_gte(5))
    try_zone:add(AddAvoidanceZone(obstacle_service))
    try_zone:add(Repath(nav_service, movement_service, obstacle_service, event_bus))
    tree:add(try_zone)

    -- Final: signal max stuck exceeded
    tree:add(BT.Action:new(function(bb, dt)
        local max = bb:get("config.max_stuck_attempts", 6)
        if bb:get("stuck.count", 0) > max then
            return BT.SUCCESS -- signals HSM to transition to Failed
        end
        return BT.FAILURE
    end, "MaxStuckExceeded"))

    return tree
end

return { create = create }
