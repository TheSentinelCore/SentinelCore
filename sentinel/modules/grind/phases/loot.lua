local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Loot = {}

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Scan nearby dead units for lootable corpses.
---@param player_pos table { x, y, z }
---@return table|nil The closest lootable unit, or nil
local function find_lootable_nearby(player_pos)
    if not core or not core.object_manager then return nil end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end

    local best = nil
    local best_dist = math.huge
    for _, obj in ipairs(objects) do
        local is_dead = type(obj.is_dead) == "function" and obj:is_dead()
        local can_loot = type(obj.can_be_looted) == "function" and obj:can_be_looted()
        if is_dead and can_loot then
            local ok_pos, pos = pcall(obj.get_position, obj)
            if ok_pos and type(pos) == "table" then
                local dist = distance_3d(player_pos, pos)
                if dist < 50 and dist < best_dist then
                    best_dist = dist
                    best = obj
                end
            end
        end
    end
    return best
end

---Build the loot phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Loot.build(event_bus, nav_adapter)
    return BT.sequence("loot_nearby", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: must not be in combat
        BT.condition("not_in_combat", function(bb)
            return bb:get("player.in_combat") ~= true
        end),

        -- Scan for lootable corpses nearby
        BT.condition("has_lootable_nearby", function(bb)
            local player_pos = bb:get("player.position")
            local target = find_lootable_nearby(player_pos)
            if target then
                bb:set("module.grind.loot_target", target)
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

            if not nav_adapter:is_active() then
                nav_adapter:move_to(target_pos)
            end
            return Status.RUNNING
        end),

        -- Interact with the corpse to loot it
        BT.action("loot_corpse", function(bb)
            local target = bb:get("module.grind.loot_target")
            if target and core and core.input and core.input.interact_with_object then
                core.input.interact_with_object(target)
            end
            bb:set("module.grind.loot_target", nil)
            bb:set("module.grind.current_target", nil)
            return Status.SUCCESS
        end),

        -- Publish loot complete event
        BT.action("publish_loot", function(bb)
            event_bus:publish("grind:loot_complete", {})
            return Status.SUCCESS
        end),
    })
end

return Loot
