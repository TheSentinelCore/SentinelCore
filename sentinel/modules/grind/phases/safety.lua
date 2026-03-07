local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Safety = {}

---Build the safety/flee phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Safety.build(event_bus, nav_adapter)
    return BT.sequence("safety_flee", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: player must be alive (not dead, not ghost)
        BT.condition("player_alive", function(bb)
            return bb:get("player.is_dead") ~= true
                and bb:get("player.is_ghost") ~= true
        end),

        -- At least one safety trigger must fire
        BT.selector("safety_triggers", {
            BT.condition("health_critical", function(bb)
                local pct = bb:get("player.health_pct", 1)
                local threshold = bb:get("module.grind.health_flee_pct", 0.20)
                return pct < threshold
            end),
            BT.condition("too_many_mobs", function(bb)
                local count = bb:get("combat.enemy_count_30yd", 0)
                local max = bb:get("module.grind.max_hostiles", 3)
                return count > max
            end),
        }),

        -- Disengage: signal combat module and stop navigation
        BT.action("disengage", function(bb)
            event_bus:publish("combat:disengage_requested", {})
            nav_adapter:stop("safety_flee")
            return Status.SUCCESS
        end),

        -- Flee to safe point: move until within 5yd
        BT.action("flee_to_safe_point", function(bb)
            local flee_pos = bb:get("module.grind.flee_position")
            if not flee_pos then
                -- Fallback: use the grind spot center as safe point
                local spot = bb:get("module.grind.current_spot")
                if spot and spot.center then
                    flee_pos = spot.center
                else
                    return Status.FAILURE
                end
            end

            local player_pos = bb:get("player.position")
            if player_pos then
                local dx = (player_pos.x or 0) - (flee_pos.x or 0)
                local dy = (player_pos.y or 0) - (flee_pos.y or 0)
                local dz = (player_pos.z or 0) - (flee_pos.z or 0)
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist <= 5 then
                    event_bus:publish("grind:safety_flee", { position = flee_pos })
                    return Status.SUCCESS
                end
            end

            if not nav_adapter:is_active() then
                nav_adapter:move_to(flee_pos)
            end
            return Status.RUNNING
        end),
    })
end

return Safety
