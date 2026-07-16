local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local Geometry = require("core/geometry")

local Safety = {}

local MAX_FLEE_DURATION_MS = 30000 -- 30s maximum flee before giving up

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

            -- Flee to safe point: move until within 5yd (with timeout)
            BT.action("flee_to_safe_point", function(bb)
                -- If player died during flee, exit so corpse_run can handle
                if bb:get("player.is_dead") == true or bb:get("player.is_ghost") == true then
                    nav_adapter:stop("safety_player_died")
                    bb:set("module.grind._flee_start_ms", nil)
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
                    bb:set("module.grind._flee_start_ms", nil)
                    return Status.SUCCESS
                end

                -- Timeout: give up fleeing after MAX_FLEE_DURATION_MS
                local now = bb:get("system.now_ms", 0)
                local flee_start = bb:get("module.grind._flee_start_ms")
                if not flee_start then
                    bb:set("module.grind._flee_start_ms", now)
                    flee_start = now
                end
                if now - flee_start > MAX_FLEE_DURATION_MS then
                    nav_adapter:stop("safety_flee_timeout")
                    bb:set("module.grind._flee_start_ms", nil)
                    return Status.SUCCESS
                end

                local player_pos = bb:get("player.position")

                local flee_pos = bb:get("module.grind.flee_position")
                if not flee_pos then
                    -- No explicit flee point — compute one 30yd AWAY from spot
                    -- center (where mobs are), not toward it.
                    local spot = bb:get("module.grind.current_spot")
                    if spot and spot.center and player_pos then
                        flee_pos = Geometry.away_from(spot.center, player_pos, 30)
                        if not flee_pos then
                            return Status.FAILURE
                        end
                    else
                        return Status.FAILURE
                    end
                end
                if player_pos then
                    local dist = Geometry.distance(player_pos, flee_pos)
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
