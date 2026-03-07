local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local Rest = {}

---Build the rest phase sub-tree.
---@param event_bus table EventBus instance
---@return table BT node
function Rest.build(event_bus)
    return BT.sequence("rest", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: must not be in combat
        BT.condition("not_in_combat", function(bb)
            return bb:get("player.in_combat") ~= true
        end),

        -- At least one rest trigger must fire
        BT.selector("needs_rest", {
            BT.condition("health_below_eat_threshold", function(bb)
                local pct = bb:get("player.health_pct", 1)
                local threshold = bb:get("module.grind.health_eat_pct", 0.50)
                return pct < threshold
            end),
            BT.condition("mana_below_drink_threshold", function(bb)
                local pct = bb:get("player.mana_pct", 1)
                local threshold = bb:get("module.grind.mana_drink_pct", 0.40)
                return pct < threshold
            end),
        }),

        -- Call profile:prepare_rest() if available (e.g. mage conjuring)
        BT.action("prepare_rest", function(bb)
            local profile = bb:get("module.combat.profile")
            if profile and type(profile.prepare_rest) == "function" then
                profile:prepare_rest(bb)
            end
            return Status.SUCCESS
        end),

        -- Wait for HP/mana to recover above 90%
        BT.action("sit_and_consume", function(bb)
            local hp = bb:get("player.health_pct", 1)
            local mana = bb:get("player.mana_pct", 1)
            local needs_food = bb:get("module.grind.needs_food", true)
            local needs_water = bb:get("module.grind.needs_water", true)

            local hp_ok = not needs_food or hp >= 0.90
            local mana_ok = not needs_water or mana >= 0.90

            if hp_ok and mana_ok then
                return Status.SUCCESS
            end
            return Status.RUNNING
        end),

        -- Publish rest complete event
        BT.action("publish_rest_complete", function(bb)
            event_bus:publish("grind:rest_complete", {})
            return Status.SUCCESS
        end),
    })
end

return Rest
