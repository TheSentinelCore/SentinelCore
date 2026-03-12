local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local TargetFilter = require("modules/grind/target_filter")

local Acquire = {}

local SPOT_ARRIVE_DIST = 15

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Build the acquire-target phase sub-tree.
---@param blackboard table Blackboard instance (used for closure captures)
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Acquire.build(blackboard, event_bus, nav_adapter)
    return BT.action("acquire_target", function(bb)
        if bb:get("module.grind.enabled") ~= true then return Status.FAILURE end
        if bb:get("combat.source") ~= nil then return Status.FAILURE end
        if bb:get("module.grind.current_target") ~= nil then return Status.FAILURE end

        local spot = bb:get("module.grind.current_spot")
        local player_pos = bb:get("player.position")
        local player = bb:get("player.object")

        if not spot then return Status.FAILURE end
        if not player_pos then return Status.FAILURE end

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

        local threat_map = bb:get("module.grind.threat_map")
        local filter_opts = nil
        if threat_map then
            filter_opts = { threat_map = threat_map, now_ms = bb:get("system.now_ms", 0) }
        end

        local best = TargetFilter.select_best(units, spot, player_level, player_pos, player, filter_opts)

        if best then
            bb:set("module.grind.current_target", best)
            return Status.SUCCESS
        end

        -- No target found — navigate to hotspot center if we're far away
        local center = spot.center
        if not center then return Status.FAILURE end

        local dist_to_center = distance_3d(player_pos, center)
        if dist_to_center <= SPOT_ARRIVE_DIST then
            -- Already at hotspot, no targets here — let profile_manager dry-spell advance
            return Status.FAILURE
        end

        -- Mount controller: update dismount checks while traveling
        local mount_ctrl = bb:get("module.grind.mount_controller")
        if mount_ctrl then
            mount_ctrl:update(bb)
        end

        -- Stuck detection while walking to hotspot
        local stuck = bb:get("module.grind.stuck_detector")
        if stuck then
            local now = bb:get("system.now_ms", 0)
            stuck:sample(now, player_pos, "acquire")
            if stuck:is_stuck() then
                nav_adapter:stop("acquire_stuck")
                stuck:reset()
                event_bus:publish("grind:stuck_recovery", { phase = "acquire" })
                return Status.FAILURE
            end
        end

        -- Don't start nav while casting (nav client defers and invalidates session)
        local casting = bb:get("player.is_casting", false) or bb:get("player.is_channeling", false)
        if not casting and not nav_adapter:is_active() then
            nav_adapter:move_to(center)
            -- Mount for long-distance travel
            if mount_ctrl then
                mount_ctrl:begin_travel(bb, center)
            end
        end
        return Status.RUNNING
    end)
end

return Acquire
