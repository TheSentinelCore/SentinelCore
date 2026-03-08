local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Loot = {}

local LOOT_BLACKLIST_DURATION_MS = 30000

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Scan nearby dead units for all lootable corpses, sorted by distance.
---@param player_pos table { x, y, z }
---@param blacklist table<userdata, number> guid→expiry_ms blacklist
---@param now_ms number current time
---@return table[] Array of { unit, dist } sorted by distance
local function find_all_lootable(player_pos, blacklist, now_ms)
    if not core or not core.object_manager then return {} end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return {} end

    local results = {}
    for _, obj in ipairs(objects) do
        -- Skip blacklisted corpses
        local bl_expiry = blacklist[obj]
        if bl_expiry and now_ms < bl_expiry then
            -- still blacklisted, skip
        else
            if bl_expiry then blacklist[obj] = nil end

            local ok_dead, is_dead = pcall(obj.is_dead, obj)
            local ok_loot, can_loot = pcall(obj.can_be_looted, obj)
            if (ok_dead and is_dead) and (ok_loot and can_loot) then
                local ok_pos, pos = pcall(obj.get_position, obj)
                if ok_pos and type(pos) == "table" then
                    local dist = distance_3d(player_pos, pos)
                    if dist < 50 then
                        results[#results + 1] = { unit = obj, dist = dist }
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.dist < b.dist end)
    return results
end

---Build the loot phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Loot.build(event_bus, nav_adapter)
    local loot_blacklist = {}

    return BT.sequence("loot_nearby", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Don't loot while combat module is actively engaged (prevents nav
        -- conflict with chase controller). Looting is still allowed during
        -- post-kill combat linger because combat.source is cleared on disengage.
        BT.condition("not_engaged", function(bb)
            return bb:get("combat.source") == nil
        end),

        -- Scan for lootable corpses nearby (picks closest not blacklisted)
        BT.condition("has_lootable_nearby", function(bb)
            local player_pos = bb:get("player.position")
            local now = bb:get("system.now_ms", 0)
            local lootables = find_all_lootable(player_pos, loot_blacklist, now)
            if #lootables > 0 then
                bb:set("module.grind.loot_target", lootables[1].unit)
                return true
            end
            return false
        end),

        -- Move to the lootable corpse
        BT.action("move_to_corpse", function(bb)
            local target = bb:get("module.grind.loot_target")
            if not target then return Status.FAILURE end

            local ok_pos, target_pos = pcall(target.get_position, target)
            if not ok_pos or type(target_pos) ~= "table" then
                return Status.FAILURE
            end

            local player_pos = bb:get("player.position")
            if player_pos and distance_3d(player_pos, target_pos) <= 5 then
                return Status.SUCCESS
            end

            -- Stuck detection while moving to corpse
            local stuck = bb:get("module.grind.stuck_detector")
            if stuck and player_pos then
                local now = bb:get("system.now_ms", 0)
                stuck:sample(now, player_pos)
                if stuck:is_stuck() then
                    nav_adapter:stop("loot_stuck")
                    stuck:reset()
                    event_bus:publish("grind:stuck_recovery", { phase = "loot" })
                    -- Blacklist this corpse so we try the next one
                    loot_blacklist[target] = (bb:get("system.now_ms", 0)) + LOOT_BLACKLIST_DURATION_MS
                    bb:set("module.grind.loot_target", nil)
                    return Status.FAILURE
                end
            end

            if not nav_adapter:is_active() then
                nav_adapter:move_to(target_pos)
            end
            return Status.RUNNING
        end),

        -- Loot the corpse with retry pattern (up to 3 attempts, 500ms between)
        BT.action("loot_corpse", function(bb)
            local target = bb:get("module.grind.loot_target")
            if not target then
                bb:set("module.grind.is_looting", false)
                return Status.FAILURE
            end

            -- Check if target is still lootable
            local ok_loot, can_loot = pcall(target.can_be_looted, target)
            if not ok_loot or not can_loot then
                -- Loot finished or corpse despawned — check for more lootables
                bb:set("module.grind.is_looting", false)
                bb:set("module.grind.loot_target", nil)
                bb:set("module.grind.current_target", nil)
                bb:set("module.grind.loot_attempt", nil)
                bb:set("module.grind.loot_until", nil)
                event_bus:publish("grind:loot", {})
                return Status.SUCCESS
            end

            local now = bb:get("system.now_ms", 0)
            local loot_until = bb:get("module.grind.loot_until", 0)

            -- Still in loot wait period
            if loot_until > 0 and now < loot_until then
                return Status.RUNNING
            end

            local attempt = bb:get("module.grind.loot_attempt", 0)
            if attempt >= 3 then
                -- Max retries, blacklist and skip this corpse
                bb:set("module.grind.is_looting", false)
                loot_blacklist[target] = now + LOOT_BLACKLIST_DURATION_MS
                bb:set("module.grind.loot_target", nil)
                bb:set("module.grind.loot_attempt", nil)
                bb:set("module.grind.loot_until", nil)
                return Status.SUCCESS
            end

            -- Stop movement, flag looting, send loot command
            nav_adapter:stop("looting")
            bb:set("module.grind.is_looting", true)

            if core and core.input and core.input.loot_object then
                pcall(core.input.loot_object, target)
            end

            bb:set("module.grind.loot_attempt", attempt + 1)
            bb:set("module.grind.loot_until", now + 500)
            return Status.RUNNING
        end),

        -- Cleanup and publish
        BT.action("publish_loot", function(bb)
            bb:set("module.grind.is_looting", false)
            bb:set("module.grind.loot_attempt", nil)
            bb:set("module.grind.loot_until", nil)
            event_bus:publish("grind:loot_complete", {})
            return Status.SUCCESS
        end),
    })
end

return Loot
