local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Pull = {}

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Build the pull phase sub-tree.
---@param blackboard table Blackboard instance (used for closure captures)
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Pull.build(blackboard, event_bus, nav_adapter)
    return BT.sequence("pull_target", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: must have a grind target
        BT.condition("has_grind_target", function(bb)
            return bb:get("module.grind.current_target") ~= nil
        end),

        -- Gate: must not be in combat
        BT.condition("not_in_combat", function(bb)
            return bb:get("player.in_combat") ~= true
        end),

        -- Execute pull: use profile hook or default approach
        BT.action("execute_pull", function(bb)
            local target = bb:get("module.grind.current_target")
            if not target then return Status.FAILURE end

            -- Try profile tick_pull hook first
            local profile = bb:get("module.combat.profile")
            if profile and type(profile.tick_pull) == "function" then
                local result = profile:tick_pull(bb, target)
                if result == Status.RUNNING or result == Status.SUCCESS or result == Status.FAILURE then
                    return result
                end
                return Status.SUCCESS
            end

            -- Default: approach within 30yd and set combat target
            local ok_pos, target_pos = pcall(target.get_position, target)
            if not ok_pos or type(target_pos) ~= "table" then
                return Status.FAILURE
            end

            local player_pos = bb:get("player.position")
            if not player_pos then return Status.FAILURE end

            local dist = distance_3d(player_pos, target_pos)
            if dist > 30 then
                if not nav_adapter:is_active() then
                    nav_adapter:move_to(target_pos)
                end
                return Status.RUNNING
            end

            -- Within range: set as combat target
            bb:set("combat.target", target)
            return Status.SUCCESS
        end),

        -- Publish pull event
        BT.action("publish_mob_pulled", function(bb)
            local target = bb:get("module.grind.current_target")
            event_bus:publish("grind:mob_pulled", { target = target })
            return Status.SUCCESS
        end),
    })
end

return Pull
