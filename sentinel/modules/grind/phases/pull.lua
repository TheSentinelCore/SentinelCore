local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local ProfileInterface = require("modules/combat/profile_interface")

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
local RETARGET_DIST = 3
local PULL_RANGE_RESUME_BUFFER = 3

function Pull.build(blackboard, event_bus, nav_adapter)
    local last_pull_target_pos = nil
    local entered_pull_range = false
    local last_pull_guid = nil

    return BT.sequence("pull_target", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: combat must be enabled (don't pull if combat is off)
        BT.condition("combat_enabled", function(bb)
            return bb:get("module.combat.enabled", true) == true
        end),

        -- Gate: must have a grind target
        BT.condition("has_grind_target", function(bb)
            return bb:get("module.grind.current_target") ~= nil
        end),

        -- Gate: combat module must not be actively engaged
        BT.condition("not_engaged", function(bb)
            return bb:get("combat.source") == nil
        end),

        -- Gate: don't pull if we need to rest (prevents OOM pull chains)
        BT.condition("rest_not_needed", function(bb)
            local hp = bb:get("player.health_pct", 1)
            local mana = bb:get("player.mana_pct", 1)
            return hp >= bb:get("module.grind.health_eat_pct", 0.50)
                and mana >= bb:get("module.grind.mana_drink_pct", 0.40)
        end),

        -- Dismount if mounted before pulling
        BT.action("ensure_dismounted", function(bb)
            local player = bb:get("player.object")
            if not player then return Status.SUCCESS end
            local ok, mounted = pcall(player.is_mounted, player)
            if ok and mounted == true then
                if core and core.input and type(core.input.dismount) == "function" then
                    pcall(core.input.dismount)
                end
                local mount_ctrl = bb:get("module.grind.mount_controller")
                if mount_ctrl then mount_ctrl:clear() end
                return Status.RUNNING
            end
            return Status.SUCCESS
        end),

        -- Execute pull: approach within range, then cast pull spell
        BT.action("execute_pull", function(bb)
            local target = bb:get("module.grind.current_target")
            if not target then return Status.FAILURE end
            if bb:get("module.grind.is_resting") == true then
                return Status.FAILURE
            end

            -- Validate target is still a live, accessible game object.
            -- pcall failure means the userdata is stale (object deallocated).
            local ok_alive, alive = pcall(target.is_alive, target)
            if not ok_alive or not alive then
                bb:set("module.grind.current_target", nil)
                entered_pull_range = false
                last_pull_target_pos = nil
                last_pull_guid = nil
                return Status.FAILURE
            end

            -- Reset hysteresis when target changes
            local current_guid = nil
            local ok_guid, raw_guid = pcall(target.get_guid, target)
            if ok_guid and raw_guid then current_guid = tostring(raw_guid) end
            if current_guid ~= last_pull_guid then
                entered_pull_range = false
                last_pull_target_pos = nil
                last_pull_guid = current_guid
            end

            -- Set combat.target so spell actions can find the pull target
            bb:set("combat.target", target)

            -- Get positions for range check
            local ok_pos, target_pos = pcall(target.get_position, target)
            if not ok_pos or type(target_pos) ~= "table" then
                bb:set("module.grind.current_target", nil)
                entered_pull_range = false
                last_pull_target_pos = nil
                last_pull_guid = nil
                return Status.FAILURE
            end
            local player_pos = bb:get("player.position")
            if not player_pos then return Status.FAILURE end

            local dist = distance_3d(player_pos, target_pos)
            local pull_range = bb:get("module.combat.combat_range", 28)

            -- Hysteresis: once in range, only resume navigating if target moves well beyond pull range
            local out_of_range = dist > pull_range
            if entered_pull_range then
                out_of_range = dist > pull_range + PULL_RANGE_RESUME_BUFFER
            end

            -- Approach within pull range first
            if out_of_range then
                entered_pull_range = false
                -- Stuck detection while approaching
                local stuck = bb:get("module.grind.stuck_detector")
                if stuck then
                    local now = bb:get("system.now_ms", 0)
                    stuck:sample(now, player_pos, "pull")
                    if stuck:is_stuck() then
                        nav_adapter:stop("pull_stuck")
                        stuck:reset()
                        event_bus:publish("grind:stuck_recovery", { phase = "pull" })
                        bb:set("module.grind.current_target", nil)
                        entered_pull_range = false
                        last_pull_target_pos = nil
                        last_pull_guid = nil
                        return Status.FAILURE
                    end
                end

                -- Don't start nav while casting (nav client defers and invalidates session)
                local casting = bb:get("player.is_casting", false) or bb:get("player.is_channeling", false)
                if not casting then
                    local should_move = not nav_adapter:is_active()
                    if not should_move and last_pull_target_pos then
                        should_move = distance_3d(last_pull_target_pos, target_pos) > RETARGET_DIST
                    end
                    if should_move then
                        nav_adapter:move_to(target_pos)
                        last_pull_target_pos = target_pos
                    end
                end
                return Status.RUNNING
            end

            last_pull_target_pos = nil
            entered_pull_range = true

            -- In range: stop movement, face target, set game target
            nav_adapter:stop("pull_in_range")
            if core and core.input then
                if core.input.set_target then
                    pcall(core.input.set_target, target)
                end
                if core.input.look_at then
                    pcall(core.input.look_at, target_pos)
                end
            end

            -- Try profile tick_pull hook
            local profile = bb:get("module.combat.profile")
            local result = ProfileInterface.call_optional(profile, "tick_pull", bb, target)
            if result == Status.SUCCESS then
                -- Hand off to combat module so it transitions from IDLE
                event_bus:publish("combat:engage_requested", {
                    target = target,
                    source = "grind",
                    leash_center = player_pos,
                    leash_radius = 40,
                })
                return Status.SUCCESS
            end

            -- Spell not ready yet (GCD, cooldown) -- keep trying
            return Status.RUNNING
        end),

        -- Default fallback: request combat engagement
        BT.action("request_combat_engage", function(bb)
            local target = bb:get("module.grind.current_target")
            local player_pos = bb:get("player.position")
            event_bus:publish("combat:engage_requested", {
                target = target,
                source = "grind",
                leash_center = player_pos,
                leash_radius = 40,
            })
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