---@class TravelingController
---Handles the TRAVELING state — node scanning, waypoint validation, movement.
---Extracted from BotManager to reduce coupling and flatten callback nesting.
local TravelingController = {}

local Constants = require("core/Constants")
local STATES = Constants.STATES
local EVENTS = Constants.EVENTS

-- Internal substates to flatten callbacks
local SUBSTATES = {
    IDLE = "idle",
    VALIDATING = "validating",
    MOVING = "moving",
}

local _substate = SUBSTATES.IDLE
local _pending_waypoint = nil

---Reset internal state (call on bot stop/start)
function TravelingController.reset()
    _substate = SUBSTATES.IDLE
    _pending_waypoint = nil
end

---Process one tick of the traveling state
---@param ctx table { modules, state_machine, event_bus, log, on_nav_failure: fun(): boolean, on_nav_success: fun() }
function TravelingController.process(ctx)
    local profile_mgr = ctx.modules.ProfileManager
    local movement = ctx.modules.MovementModule
    local scanner = ctx.modules.NodeScanner
    local safety = ctx.modules.SafetyModule

    if not profile_mgr or not movement then
        return
    end

    -- Check for nearby nodes first (regardless of substate)
    if scanner and _substate == SUBSTATES.IDLE then
        local nodes = scanner:scan()
        if #nodes > 0 and safety and safety:is_safe_to_gather() then
            local node = scanner:get_node_with_variance()
            if node then
                ctx.state_machine:transition(STATES.APPROACHING, {
                    target_node = node
                })
                movement:move_to(node.position, nil, { use_navmesh = true })
                if ctx.log then
                    ctx.log:info("Found node: %s, approaching", node.name)
                end
                return
            end
        end
    end

    -- Waiting for async callback — don't issue new commands
    if _substate == SUBSTATES.VALIDATING or _substate == SUBSTATES.MOVING then
        return
    end

    -- Continue to next waypoint if not already moving
    if movement:is_moving() then
        return
    end

    local waypoint = profile_mgr:get_current_waypoint()
    if not waypoint then
        if ctx.log then
            ctx.log:debug("No current waypoint")
        end
        return
    end

    local target = { x = waypoint.x, y = waypoint.y, z = waypoint.z }
    _pending_waypoint = waypoint
    _substate = SUBSTATES.VALIDATING

    movement:validate_destination_reachable(target, function(reachable, reason, distance)
        TravelingController._on_validation_complete(ctx, reachable, reason, distance, target)
    end)
end

---Handle validation result (callback)
---@param ctx table
---@param reachable boolean
---@param reason string|nil
---@param distance number|nil
---@param target table
function TravelingController._on_validation_complete(ctx, reachable, reason, distance, target)
    local profile_mgr = ctx.modules.ProfileManager
    local movement = ctx.modules.MovementModule

    if not reachable then
        if ctx.log then
            ctx.log:warn("Waypoint %d pre-validation failed: %s, skipping",
                _pending_waypoint and _pending_waypoint.id or 0, reason or "unknown")
        end
        if ctx.on_nav_failure() then
            _substate = SUBSTATES.IDLE
            return  -- Bot stopped/paused
        end
        profile_mgr:advance_waypoint()
        _substate = SUBSTATES.IDLE
        return
    end

    if ctx.log then
        ctx.log:debug("Waypoint %d validated (%.0f yards), moving",
            _pending_waypoint and _pending_waypoint.id or 0, distance or 0)
    end

    _substate = SUBSTATES.MOVING
    movement:move_to(target, function(success, move_reason)
        TravelingController._on_movement_complete(ctx, success, move_reason)
    end, { use_navmesh = true })
end

---Handle movement result (callback)
---@param ctx table
---@param success boolean
---@param move_reason string|nil
function TravelingController._on_movement_complete(ctx, success, move_reason)
    local profile_mgr = ctx.modules.ProfileManager

    if success then
        ctx.on_nav_success()
        profile_mgr:advance_waypoint()
        ctx.event_bus:publish(EVENTS.WAYPOINT_REACHED, {
            waypoint = _pending_waypoint,
            timestamp = core.time()
        })
    else
        if ctx.log then
            ctx.log:warn("Waypoint movement failed: %s, skipping", move_reason or "unknown")
        end
        if ctx.on_nav_failure() then
            _substate = SUBSTATES.IDLE
            return  -- Bot stopped/paused
        end
        profile_mgr:advance_waypoint()
    end

    _substate = SUBSTATES.IDLE
    _pending_waypoint = nil
end

return TravelingController
