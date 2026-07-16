local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local TargetFilter = require("modules/grind/target_filter")

local Patrol = {}

local TWO_PI = 2 * math.pi
local WAYPOINT_ARRIVE_DIST = 8
local NO_TARGET_PATROL_DELAY_MS = 10000

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Generate evenly-spaced patrol waypoints on a circle.
---@param center table { x, y, z }
---@param radius number
---@param count number Number of waypoints
---@return table[] Array of { x, y, z }
local function generate_ring(center, radius, count)
    local points = {}
    for i = 0, count - 1 do
        local angle = (i / count) * TWO_PI
        points[#points + 1] = {
            x = center.x + radius * math.cos(angle),
            y = center.y + radius * math.sin(angle),
            z = center.z,
        }
    end
    return points
end

---Build a patrol-mode acquire node.
---Generates ring waypoints around a center and cycles through them,
---scanning for targets at each waypoint.
---@param event_bus table
---@param nav_adapter table
---@return table BT node
function Patrol.build_acquire(event_bus, nav_adapter)
    local waypoints = nil
    local waypoint_index = 1
    local ring_index = 1
    local rings = { 30, 60, 100 }
    local points_per_ring = 8
    local last_kill_ms = nil  -- nil = not yet initialized; set to now on first tick
    local center = nil

    return BT.action("patrol_acquire", function(bb)
        if bb:get("module.grind.enabled") ~= true then return Status.FAILURE end
        if bb:get("combat.source") ~= nil then return Status.FAILURE end
        if bb:get("module.grind.current_target") ~= nil then return Status.FAILURE end

        local player_pos = bb:get("player.position")
        local player = bb:get("player.object")
        if not player_pos then return Status.FAILURE end

        local now = bb:get("system.now_ms", 0)
        local patrol_radius = bb:get("module.grind.patrol_radius", 60)

        -- Reset patrol state when signaled (e.g. mode switch)
        if bb:get("module.grind.patrol_center_reset") then
            center = nil
            waypoints = nil
            ring_index = 1
            waypoint_index = 1
            bb:set("module.grind.patrol_center_reset", nil)
        end

        -- Initialize center on first tick (player's current position)
        if not center then
            center = { x = player_pos.x, y = player_pos.y, z = player_pos.z }
            bb:set("module.grind.patrol_center", center)
        end

        -- Build a spot config for target filtering in patrol mode
        local spot = bb:get("module.grind.current_spot")
        if not spot then
            -- No profile loaded — create a minimal spot from patrol center
            spot = {
                center = center,
                radius = patrol_radius,
                level_min = 1,
                level_max = 99,
            }
        end

        -- Scan for targets
        local player_level = 70
        if player and type(player.get_level) == "function" then
            local ok, level = pcall(player.get_level, player)
            if ok and type(level) == "number" then
                player_level = level
            end
        end

        local units = {}
        if core and core.object_manager and core.object_manager.get_all_objects then
            local ok, objects = pcall(core.object_manager.get_all_objects)
            if ok and type(objects) == "table" then
                for _, obj in ipairs(objects) do
                    local ok2, iu = pcall(obj.is_unit, obj)
                    if ok2 and iu then
                        units[#units + 1] = obj
                    end
                end
            end
        end

        local best = TargetFilter.select_best(units, spot, player_level, player_pos, player)
        if best then
            bb:set("module.grind.current_target", best)
            last_kill_ms = now
            return Status.SUCCESS
        end

        -- No target found — patrol if idle long enough
        if not last_kill_ms then
            last_kill_ms = now  -- initialize on first tick
        end
        if (now - last_kill_ms) < NO_TARGET_PATROL_DELAY_MS then
            return Status.FAILURE
        end

        -- Generate waypoints if needed
        if not waypoints then
            local ring_radius = rings[ring_index] or patrol_radius
            -- Scale ring sizes to patrol_radius
            ring_radius = math.min(ring_radius, patrol_radius)
            waypoints = generate_ring(center, ring_radius, points_per_ring)
            waypoint_index = 1
        end

        -- Navigate to current waypoint
        local wp = waypoints[waypoint_index]
        if not wp then
            -- Advance to next ring
            ring_index = ring_index + 1
            if ring_index > #rings then ring_index = 1 end
            waypoints = nil
            return Status.FAILURE
        end

        local dist = distance_3d(player_pos, wp)
        if dist <= WAYPOINT_ARRIVE_DIST then
            -- Arrived at waypoint, advance
            waypoint_index = waypoint_index + 1
            if waypoint_index > #waypoints then
                -- Completed ring, advance to next
                ring_index = ring_index + 1
                if ring_index > #rings then ring_index = 1 end
                waypoints = nil
            end
            return Status.FAILURE -- re-enter to scan for targets
        end

        -- Stuck detection while patrolling
        local stuck = bb:get("module.grind.stuck_detector")
        if stuck then
            stuck:sample(now, player_pos, "patrol")
            if stuck:is_stuck() then
                nav_adapter:stop("patrol_stuck")
                stuck:reset()
                event_bus:publish("grind:stuck_recovery", { phase = "patrol" })
                -- Skip this waypoint
                waypoint_index = waypoint_index + 1
                if waypoint_index > #waypoints then
                    ring_index = ring_index + 1
                    if ring_index > #rings then ring_index = 1 end
                    waypoints = nil
                end
                return Status.FAILURE
            end
        end

        if not nav_adapter:is_active() then
            nav_adapter:move_to(wp, { soft_update = true })
        end
        return Status.RUNNING
    end)
end

---Reset patrol state (e.g. when switching modes or loading a profile).
function Patrol.reset_center()
    -- Patrol center resets naturally on next tick when center is nil
end

return Patrol
