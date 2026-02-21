local T = require("tests/TestUtil")

local function run()
    local item_keep = T.mock_object({ item_id = 6948, stack_count = 1 })
    local item_sell = T.mock_object({ item_id = 1179, stack_count = 1 })
    local item_rule_keep = T.mock_object({ item_id = 17031, stack_count = 5 })
    local item_rule_sell = T.mock_object({ item_id = 4000, stack_count = 6 })
    local item_white_keep = T.mock_object({ item_id = 5000, stack_count = 1, quality = 1 })
    local item_blue_sell = T.mock_object({ item_id = 5001, stack_count = 1, quality = 3 })
    local item_epic_keep = T.mock_object({ item_id = 5002, stack_count = 1, quality = 4 })

    local player = {
        is_valid = function() return true end,
        get_item_at_inventory_slot = function(_, slot_id)
            if slot_id == 16 then
                -- Equipped item must not count toward bag occupancy.
                return { object = item_keep }
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
                        { object = item_keep, slot_id = 1 },
                        { object = item_sell, slot_id = 2 },
                        { object = item_rule_keep, slot_id = 3 },
                        { object = item_rule_sell, slot_id = 4 },
                        { object = item_white_keep, slot_id = 5 },
                        { object = item_blue_sell, slot_id = 6 },
                        { object = item_epic_keep, slot_id = 7 },
                    }
                end
                return {}
            end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local helper_module_key = "common/utility/inventory_helper"
    local inventory_service_key = "services/InventoryService"
    local previous_helper_module = package.loaded[helper_module_key]
    local previous_inventory_service = package.loaded[inventory_service_key]
    package.loaded[helper_module_key] = {
        get_character_bag_slots = function()
            return {
                { item = item_keep, bag_id = 0, bag_slot = 0 },
                { item = item_sell, bag_id = 0, bag_slot = 1 },
                { item = item_rule_keep, bag_id = 0, bag_slot = 2 },
                { item = item_rule_sell, bag_id = 0, bag_slot = 3 },
                { item = item_white_keep, bag_id = 0, bag_slot = 4 },
                { item = item_blue_sell, bag_id = 0, bag_slot = 5 },
                { item = item_epic_keep, bag_id = 0, bag_slot = 6 },
            }
        end,
    }

    local result = nil
    local ok, run_err = xpcall(function()
        package.loaded[inventory_service_key] = nil
        local InventoryService = require(inventory_service_key)

        local bus = EventBus:new()
        local bb = Blackboard:new(bus)

        local service = InventoryService:new(bus, bb, { total_bag_slots = 9 }, {
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

        local free = service:get_free_slots()
        T.assert_eq(free, 3, "free slot accounting: total_bag_slots(9) - 6 items (1 equipped filtered) = 3 free")

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

        T.assert_true(service:needs_vendor_trip() == false, "vendor trigger should not fire at 3 free (> min 2)")

        -- No fallback path: missing inventory_helper must fail closed.
        package.loaded[helper_module_key] = nil
        package.loaded[inventory_service_key] = nil
        local InventoryServiceNoHelper = require(inventory_service_key)
        local service_no_helper = InventoryServiceNoHelper:new(bus, bb, { total_bag_slots = 9 }, service:get_policy())
        T.assert_eq(service_no_helper:get_free_slots(), -1, "missing inventory_helper returns unknown (-1)")

        result = {
            sc011_inventory_policy = true,
        }
    end, function(err) return tostring(err) end)

    package.loaded[helper_module_key] = previous_helper_module
    package.loaded[inventory_service_key] = previous_inventory_service

    if not ok then
        error(run_err)
    end

    return result
end

return { run = run }
