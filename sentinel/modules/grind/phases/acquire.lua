local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local TargetFilter = require("modules/grind/target_filter")
local Compat = require("shared/compat")

local Acquire = {}

local SPOT_ARRIVE_DIST = 15
local ACQUIRE_SCAN_THROTTLE_MS = 500

---Build the acquire-target phase sub-tree.
---@param blackboard table Blackboard instance (used for closure captures)
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Acquire.build(blackboard, event_bus, nav_adapter)
    local unit_helper = nil
    local ok_unit, uh = pcall(require, "common/utility/unit_helper")
    if ok_unit then unit_helper = uh end

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

        -- Throttle acquire scans to 500ms
        local now = bb:get("system.now_ms", 0)
        local last_acquire = bb:get("module.grind.last_acquire_ms", 0)
        if now - last_acquire < ACQUIRE_SCAN_THROTTLE_MS then
            return Status.RUNNING
        end
        bb:set("module.grind.last_acquire_ms", now)

        -- Use unit_helper for localized scan instead of get_all_objects
        local units = {}
        if unit_helper and type(unit_helper.get_enemy_list_around) == "function" then
            local ok, list = pcall(unit_helper.get_enemy_list_around, unit_helper, player_pos, 55, true, false)
            if ok and type(list) == "table" then
                units = list
            end
        end

        -- Fallback to get_all_objects if unit_helper unavailable
        if #units == 0 and core and core.object_manager and core.object_manager.get_all_objects then
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
            filter_opts = { threat_map = threat_map, now_ms = now }
        end

        local best = TargetFilter.select_best(units, spot, player_level, player_pos, player, filter_opts)

        if best then
            bb:set("module.grind.current_target", best)
            return Status.SUCCESS
        end

        -- No target found — navigate to hotspot center if we're far away
        local center = spot.center
        if not center then return Status.FAILURE end

        local dist_to_center = Compat.dist(player_pos, center)
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
