local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local ConsumeManager = require("modules/grind/consume_manager")
local bag_scanner = require("modules/grind/bag_scanner")
local ConsumableIds = require("modules/grind/consumable_ids")
local ProfileInterface = require("modules/combat/profile_interface")

local Rest = {}

local FOOD_ITEMS = ConsumableIds.FOOD_ITEMS
local WATER_ITEMS = ConsumableIds.WATER_ITEMS

-- Diagnostic: throttled rest-gate logging
local _last_rest_diag_ms = 0
local DIAG_INTERVAL_MS = 3000

---Scan bags for an item matching the lookup set.
---@param lookup table<number, boolean>
---@return number|nil item_id of the first match, or nil
local function find_consumable_in_bags(lookup)
    local found_id = nil
    bag_scanner.for_each_item(function(obj)
        if found_id then return end
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id)
            if item_id and lookup[item_id] then
                found_id = item_id
            end
        end
    end)
    return found_id
end

---Build the rest phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Rest.build(event_bus, nav_adapter)
    local food_manager = ConsumeManager:new()
    local water_manager = ConsumeManager:new()
    
    return BT.sequence("rest", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: combat module must not be actively engaged.
        -- Uses combat.source instead of player.in_combat because WoW's combat
        -- timer lingers 5-6s after a kill, blocking rest entirely.
        BT.condition("not_engaged", function(bb)
            local source = bb:get("combat.source")
            if source ~= nil then
                local now = bb:get("system.now_ms", 0)
                if now - _last_rest_diag_ms >= DIAG_INTERVAL_MS then
                    _last_rest_diag_ms = now
                    if core and core.log then
                        pcall(core.log, "[Rest] blocked: combat.source=" .. tostring(source))
                    end
                end
                return false
            end
            return true
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
            -- Diagnostic: both thresholds passed, log actual values
            BT.action("rest_diag_skip", function(bb)
                local now = bb:get("system.now_ms", 0)
                if now - _last_rest_diag_ms >= DIAG_INTERVAL_MS then
                    _last_rest_diag_ms = now
                    if core and core.log then
                        pcall(core.log, string.format(
                            "[Rest] skip: hp=%.2f(>=%.2f) mana=%.2f(>=%.2f)",
                            bb:get("player.health_pct", 1),
                            bb:get("module.grind.health_eat_pct", 0.50),
                            bb:get("player.mana_pct", 1),
                            bb:get("module.grind.mana_drink_pct", 0.40)))
                    end
                end
                return Status.FAILURE
            end),
        }),

        -- Call profile:prepare_rest() if available (e.g. mage conjuring)
        -- Respects RUNNING from profile (e.g. mage waiting for spirit regen to conjure)
        -- and stays RUNNING while casting to avoid sitting mid-conjure.
        BT.action("prepare_rest", function(bb)
            local profile = bb:get("module.combat.profile")
            local profile_result = Status.SUCCESS
            if profile then
                local ok, result = pcall(ProfileInterface.call_optional, profile, "prepare_rest", bb)
                if ok then
                    profile_result = result or Status.SUCCESS
                end
            end
            if bb:get("player.is_casting", false) == true
            or bb:get("player.is_channeling", false) == true then
                return Status.RUNNING
            end
            return profile_result
        end),

        -- Set resting flag so other phases know we're resting
        BT.action("set_resting_flag", function(bb)
            bb:set("module.grind.is_resting", true)
            if core and core.log then
                pcall(core.log, string.format("[Rest] STARTED: hp=%.2f mana=%.2f",
                    bb:get("player.health_pct", 1), bb:get("player.mana_pct", 1)))
            end
            return Status.SUCCESS
        end),

        -- Eat food / drink water and wait for recovery
        BT.action("sit_and_consume", function(bb)
            -- Re-check engagement (Sequence _running_index skips the gate condition).
            -- If the combat module engaged an attacker, abort rest so we fight back.
            if bb:get("combat.source") ~= nil then
                bb:set("module.grind.is_resting", false)
                food_manager:reset()
                water_manager:reset()
                return Status.FAILURE
            end

            -- Stop movement so eating/drinking buffs aren't cancelled
            if nav_adapter and nav_adapter:is_active() then
                nav_adapter:stop("rest")
            end

            local hp = bb:get("player.health_pct", 1)
            local mana = bb:get("player.mana_pct", 1)

            -- Scan bags once for food and water IDs (avoids 4 scans per tick)
            local food_id = find_consumable_in_bags(FOOD_ITEMS)
            local water_id = find_consumable_in_bags(WATER_ITEMS)

            -- With consumables: wait for 95% recovery.
            -- Without consumables: wait for threshold + 15% hysteresis so we
            -- don't busy-loop (rest triggers at threshold, needs to regen past
            -- it before re-triggering).
            local eat_threshold = bb:get("module.grind.health_eat_pct", 0.50)
            local drink_threshold = bb:get("module.grind.mana_drink_pct", 0.40)
            local no_food_target = math.min(eat_threshold + 0.15, 0.95)
            local no_water_target = math.min(drink_threshold + 0.15, 0.95)
            local hp_ok = hp >= 0.95 or (not food_id and hp >= no_food_target)
            local mana_ok = mana >= 0.95 or (not water_id and mana >= no_water_target)

            if hp_ok and mana_ok then
                food_manager:reset()
                water_manager:reset()
                return Status.SUCCESS
            end

            -- Don't try to eat/drink while casting (maintenance buff, etc.)
            if bb:get("player.is_casting", false) == true
            or bb:get("player.is_channeling", false) == true then
                return Status.RUNNING
            end

            -- Consume food if needed
            if not hp_ok and food_id then
                local result = food_manager:consume(food_id, {
                    resource_type = "health",
                    threshold = eat_threshold,
                    target_pct = 0.95
                }, bb)
                hp_ok = bb:get("player.health_pct", 1) >= 0.95
            end

            -- Consume water if needed
            if not mana_ok and water_id then
                local result = water_manager:consume(water_id, {
                    resource_type = "mana",
                    threshold = drink_threshold,
                    target_pct = 0.95
                }, bb)
                mana_ok = bb:get("player.mana_pct", 1) >= 0.95
            end

            if hp_ok and mana_ok then
                return Status.SUCCESS
            end

            return Status.RUNNING
        end),

        -- Cancel sitting state from eating/drinking so the next phase
        -- (loot, pull) doesn't fail while the character is still seated.
        BT.action("stand_up", function(_bb)
            if core and core.input then
                if type(core.input.move_forward_start) == "function" then
                    pcall(core.input.move_forward_start)
                end
                if type(core.input.move_forward_stop) == "function" then
                    pcall(core.input.move_forward_stop)
                end
            end
            return Status.SUCCESS
        end),

        -- Clear resting flag and publish rest complete event
        BT.action("publish_rest_complete", function(bb)
            bb:set("module.grind.is_resting", false)
            food_manager:reset()
            water_manager:reset()
            if core and core.log then
                pcall(core.log, string.format("[Rest] DONE: hp=%.2f mana=%.2f",
                    bb:get("player.health_pct", 1), bb:get("player.mana_pct", 1)))
            end
            event_bus:publish("grind:rest_complete", {})
            return Status.SUCCESS
        end),
    })
end

return Rest