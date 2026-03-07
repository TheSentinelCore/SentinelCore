local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local TargetFilter = require("modules/grind/target_filter")

local Acquire = {}

---Build the acquire-target phase sub-tree.
---@param blackboard table Blackboard instance (used for closure captures)
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Acquire.build(blackboard, nav_adapter)
    return BT.sequence("acquire_target", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: must not be in combat
        BT.condition("not_in_combat", function(bb)
            return bb:get("player.in_combat") ~= true
        end),

        -- Gate: must not already have a target
        BT.condition("no_current_target", function(bb)
            return bb:get("module.grind.current_target") == nil
        end),

        -- Scan units and select best target
        BT.action("scan_and_select", function(bb)
            local spot = bb:get("module.grind.current_spot")
            if not spot then return Status.FAILURE end

            local player_pos = bb:get("player.position")
            if not player_pos then return Status.FAILURE end

            -- Get player level from object or default to 70
            local player = bb:get("player.object")
            local player_level = 70
            if player and type(player.get_level) == "function" then
                local ok, level = pcall(player.get_level, player)
                if ok and type(level) == "number" then
                    player_level = level
                end
            end

            -- Scan all visible units
            local units = {}
            if core and core.object_manager and core.object_manager.get_all_objects then
                local ok, objects = pcall(core.object_manager.get_all_objects)
                if ok and type(objects) == "table" then
                    for _, obj in ipairs(objects) do
                        if type(obj.is_unit) == "function" and obj:is_unit() then
                            units[#units + 1] = obj
                        end
                    end
                end
            end

            local best = TargetFilter.select_best(units, spot, player_level, player_pos)
            if not best then
                return Status.FAILURE
            end

            bb:set("module.grind.current_target", best)
            return Status.SUCCESS
        end),

        -- Move toward the selected target
        BT.action("move_toward_target", function(bb)
            local target = bb:get("module.grind.current_target")
            if not target then return Status.FAILURE end

            local ok_pos, target_pos = pcall(target.get_position, target)
            if not ok_pos or type(target_pos) ~= "table" then
                return Status.FAILURE
            end

            if not nav_adapter:is_active() then
                nav_adapter:move_to(target_pos)
            end
            return Status.RUNNING
        end),
    })
end

return Acquire
