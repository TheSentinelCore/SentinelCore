local T = require("tests/TestUtil")

local function run()
    local item_keep = T.mock_object({ item_id = 6948, stack_count = 1 })
    local item_sell = T.mock_object({ item_id = 1179, stack_count = 1 })
    local item_rule_keep = T.mock_object({ item_id = 17031, stack_count = 5 })
    local item_rule_sell = T.mock_object({ item_id = 4000, stack_count = 6 })
    local item_white_keep = T.mock_object({ item_id = 5000, stack_count = 1, quality = 1 })
    local item_blue_sell = T.mock_object({ item_id = 5001, stack_count = 1, quality = 3 })
    local item_epic_keep = T.mock_object({ item_id = 5002, stack_count = 1, quality = 4 })

    -- Mock bag: 21841 = Netherweave Bag (16 slots) in BAG_SIZES
    local bag_netherweave = T.mock_object({ item_id = 21841 })

    local player = {
        is_valid = function() return true end,
        get_item_at_inventory_slot = function(_, slot_id)
            -- Bag equip slots: 31=bag1, 32=bag2, 33=bag3, 34=bag4
            if slot_id == 31 then
                return { object = bag_netherweave }
            end
            return nil
        end,
    }

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
        },
        inventory = {
            get_items_in_bag = function(bag_id)
                if bag_id == 0 then
                    return {
                        -- Equipment items (slot_id < 36) — must be filtered out
                        { object = T.mock_object({ item_id = 100 }), slot_id = 1 },
                        { object = T.mock_object({ item_id = 101 }), slot_id = 5 },
                        { object = T.mock_object({ item_id = 102 }), slot_id = 15 },
                        -- Bag equip slot (31) — must be filtered out
                        { object = bag_netherweave, slot_id = 31 },
                        -- Actual backpack items (slots 36-51)
                        { object = item_keep, slot_id = 36 },
                        { object = item_sell, slot_id = 37 },
                        { object = item_rule_keep, slot_id = 38 },
                        { object = item_rule_sell, slot_id = 39 },
                        { object = item_white_keep, slot_id = 40 },
                        { object = item_blue_sell, slot_id = 41 },
                        { object = item_epic_keep, slot_id = 42 },
                        -- Bank/keyring slots (60+) — must be filtered out
                        { object = T.mock_object({ item_id = 200 }), slot_id = 60 },
                        { object = T.mock_object({ item_id = 201 }), slot_id = 86 },
                    }
                end
                return {}
            end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local inventory_service_key = "services/InventoryService"
    local previous_inventory_service = package.loaded[inventory_service_key]

    local result = nil
    local ok, run_err = xpcall(function()
        package.loaded[inventory_service_key] = nil
        local InventoryService = require(inventory_service_key)

        local bus = EventBus:new()
        local bb = Blackboard:new(bus)

        local service = InventoryService:new(bus, bb, {}, {
            min_free_slots = 2,
            never_sell = { 6948 },
            always_sell = { 1179 },
            sell_quality_max = 1,
            sell_gray = true,
            sell_white = false,
            sell_green = false,
            sell_blue = true,
            sell_epic = false,
            keep_stack_min = {},
            special_rules = {
                {
                    rule_id = "keep_drink_stock",
                    match = {
                        item_ids = { 17031 },
                        stack_max = 10,
                    },
                    action = "keep",
                },
                {
                    rule_id = "sell_large_stacks",
                    match = {
                        quality_max = 0,
                        stack_min = 5,
                    },
                    action = "sell",
                    keep_stack_min = 2,
                },
            },
        })

        -- Backpack(16) + 1x Netherweave(16) = 32 total, 7 items in bag 0 → 25 free
        local free = service:get_free_slots()
        T.assert_eq(free, 25, "free slot accounting: backpack(16) + netherweave(16) - 7 items = 25 free")

        local items = service:collect_items()
        local keep_decision = service:should_sell_item(items[1])
        local sell_decision = service:should_sell_item(items[2])
        local rule_keep_decision = service:should_sell_item(items[3])
        local rule_sell_decision = service:should_sell_item(items[4])
        local white_keep_decision = service:should_sell_item(items[5])
        local blue_sell_decision = service:should_sell_item(items[6])
        local epic_keep_decision = service:should_sell_item(items[7])

        T.assert_true(keep_decision == false, "never_sell rule must win")
        T.assert_true(sell_decision == true, "always_sell rule expected")
        T.assert_true(rule_keep_decision == false, "special keep rule should match item/stack")
        T.assert_true(rule_sell_decision == true, "special sell rule should match quality/stack")
        T.assert_true(white_keep_decision == false, "quality toggles must override sell_quality_max fallback")
        T.assert_true(blue_sell_decision == true, "blue quality toggle should sell")
        T.assert_true(epic_keep_decision == false, "epic quality toggle should keep when disabled")

        T.assert_true(service:needs_vendor_trip() == false, "vendor trigger should not fire at 25 free (> min 2)")

        -- Missing core.inventory must fail closed → returns -1.
        local saved_inventory = core.inventory
        core.inventory = nil
        package.loaded[inventory_service_key] = nil
        local InventoryService2 = require(inventory_service_key)
        local service2 = InventoryService2:new(bus, bb, {}, service:get_policy())
        T.assert_eq(service2:get_free_slots(), -1, "missing core.inventory returns unknown (-1)")
        core.inventory = saved_inventory

        -- needs_repair_trip tests
        local repair_policy = service:get_policy()
        repair_policy.repair_enabled = true
        service:set_policy(repair_policy)

        bb:set("player.durability_pct", 0.20)
        T.assert_true(service:needs_repair_trip() == true, "should need repair at 20% durability")

        bb:set("player.durability_pct", 0.50)
        T.assert_true(service:needs_repair_trip() == false, "should not need repair at 50% durability")

        result = {
            sc011_inventory_policy = true,
        }
    end, function(err) return tostring(err) end)

    package.loaded[inventory_service_key] = previous_inventory_service

    if not ok then
        error(run_err)
    end

    return result
end

return { run = run }
