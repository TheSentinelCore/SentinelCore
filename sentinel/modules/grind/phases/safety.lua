local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Safety = {}

---Build the safety/flee phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Safety.build(event_bus, nav_adapter)
    return BT.selector("safety", {
        -- Branch 1: Death loop detection — abort grind entirely
        BT.sequence("death_loop_abort", {
            BT.condition("grind_enabled_for_loop", function(bb)
                return bb:get("module.grind.enabled") == true
            end),
            BT.condition("is_death_loop", function(bb)
                local telemetry = bb:get("module.grind.telemetry")
                if not telemetry then return false end
                local now = bb:get("system.now_ms", 0)
                return telemetry:is_death_loop(now)
            end),
            BT.action("abort_grind", function(bb)
                nav_adapter:stop("death_loop_abort")
                event_bus:publish("combat:disengage_requested", {})
                bb:set("module.grind.enabled", false)
                event_bus:publish("grind:abort", { reason = "death_loop" })
                return Status.SUCCESS
            end),
        }),

        -- Branch 2: Standard safety flee
        BT.sequence("safety_flee", {
            BT.condition("grind_enabled", function(bb)
                return bb:get("module.grind.enabled") == true
            end),

            BT.condition("player_alive", function(bb)
                return bb:get("player.is_dead") ~= true
                    and bb:get("player.is_ghost") ~= true
            end),

            -- Don't flee while resting (eating/drinking)
            BT.condition("not_resting", function(bb)
                return bb:get("module.grind.is_resting") ~= true
            end),

            -- At least one safety trigger must fire
            BT.selector("safety_triggers", {
                BT.condition("health_critical", function(bb)
                    local pct = bb:get("player.health_pct", 1)
                    local threshold = bb:get("module.grind.health_flee_pct", 0.20)
                    return pct < threshold
                end),
                BT.condition("too_many_mobs", function(bb)
                    if bb:get("player.in_combat") ~= true then return false end
                    local count = bb:get("combat.enemy_count_10yd", 0)
                    local max = bb:get("module.grind.max_hostiles", 3)
                    return count > max
                end),
            }),

            -- Disengage: signal combat module and stop navigation
            BT.action("disengage", function()
                event_bus:publish("combat:disengage_requested", {})
                nav_adapter:stop("safety_flee")
                return Status.SUCCESS
            end),

            -- Flee to safe point: move until within 5yd
            BT.action("flee_to_safe_point", function(bb)
                -- If player died during flee, exit so corpse_run can handle
                if bb:get("player.is_dead") == true or bb:get("player.is_ghost") == true then
                    nav_adapter:stop("safety_player_died")
                    return Status.SUCCESS
                end

                -- Re-check safety triggers (sequence running-index may skip gates)
                local hp = bb:get("player.health_pct", 1)
                local hp_thresh = bb:get("module.grind.health_flee_pct", 0.20)
                local in_combat = bb:get("player.in_combat") == true
                local enemies = bb:get("combat.enemy_count_10yd", 0)
                local max_enemies = bb:get("module.grind.max_hostiles", 3)
                local health_ok = hp >= hp_thresh
                local mobs_ok = not in_combat or enemies <= max_enemies
                if health_ok and mobs_ok then
                    nav_adapter:stop("safety_flee_resolved")
                    return Status.SUCCESS
                end

                local flee_pos = bb:get("module.grind.flee_position")
                if not flee_pos then
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
        }),
    })
end

return Safety
