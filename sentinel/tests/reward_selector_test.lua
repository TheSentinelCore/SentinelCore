--- Unit tests for RewardSelector
--- Run with: _G.SentinelCore.run_tests()

local RewardSelector = require("modules/quest/reward_selector")

local tests = {}

function tests.test_choose_upgrade()
    local rewards = {
        {item_id = 1001, count = 1, index = 1}, -- ilvl 20 weapon
        {item_id = 1002, count = 1, index = 2}, -- ilvl 15 weapon
    }
    
    local blackboard = {
        get = function(self, key)
            if key == "module.quest.quest_items" then return {} end
            return nil
        end
    }
    
    -- Mock _get_item_info
    local original = RewardSelector._get_item_info
    RewardSelector._get_item_info = function(item_id)
        if item_id == 1001 then
            return {item_id = 1001, class = "Weapon", item_level = 20, equip_slot = 16, sell_price = 100}
        elseif item_id == 1002 then
            return {item_id = 1002, class = "Weapon", item_level = 15, equip_slot = 16, sell_price = 50}
        end
    end
    
    local choice = RewardSelector.choose(rewards, blackboard, "WARRIOR")
    
    -- Should pick ilvl 20 upgrade
    assert(choice == 1, "Should choose first reward (ilvl 20)")
    
    RewardSelector._get_item_info = original
    print("✓ test_choose_upgrade passed")
end

function tests.test_choose_vendor_value()
    local rewards = {
        {item_id = 2001, count = 1, index = 1}, -- sell 500 copper
        {item_id = 2002, count = 1, index = 2}, -- sell 1000 copper
    }
    
    local blackboard = {get = function() return {} end}
    
    local original = RewardSelector._get_item_info
    RewardSelector._get_item_info = function(item_id)
        if item_id == 2001 then
            return {item_id = 2001, class = "Consumable", sell_price = 500}
        elseif item_id == 2002 then
            return {item_id = 2002, class = "Consumable", sell_price = 1000}
        end
    end
    
    local choice = RewardSelector.choose(rewards, blackboard)
    
    assert(choice == 2, "Should choose higher vendor value")
    
    RewardSelector._get_item_info = original
    print("✓ test_choose_vendor_value passed")
end

function tests.test_quest_item_priority()
    local rewards = {
        {item_id = 3001, count = 1, index = 1}, -- quest item
        {item_id = 3002, count = 1, index = 2}, -- regular item
    }
    
    local blackboard = {
        get = function(self, key)
            if key == "module.quest.quest_items" then
                return {[3001] = true}
            end
            return {}
        end
    }
    
    local original = RewardSelector._get_item_info
    RewardSelector._get_item_info = function(item_id)
        if item_id == 3001 then
            return {item_id = 3001, class = "Quest", sell_price = 10}
        elseif item_id == 3002 then
            return {item_id = 3002, class = "Consumable", sell_price = 1000}
        end
    end
    
    local choice = RewardSelector.choose(rewards, blackboard)
    
    assert(choice == 1, "Should choose quest item even if lower vendor value")
    
    RewardSelector._get_item_info = original
    print("✓ test_quest_item_priority passed")
end

function tests.test_policy_override()
    local rewards = {
        {item_id = 4001, count = 1, index = 1}, -- Armor
        {item_id = 4002, count = 1, index = 2}, -- Armor
    }
    
    local blackboard = {get = function() return {} end}
    
    local original = RewardSelector._get_item_info
    RewardSelector._get_item_info = function(item_id)
        if item_id == 4001 then
            return {item_id = 4001, class = "Armor", item_level = 25, equip_slot = 1, sell_price = 200}
        elseif item_id == 4002 then
            return {item_id = 4002, class = "Armor", item_level = 30, equip_slot = 1, sell_price = 100}
        end
    end
    
    -- Default: upgrade policy should pick ilvl 30
    local choice1 = RewardSelector.choose(rewards, blackboard)
    assert(choice1 == 2, "Default upgrade policy picks higher ilvl")
    
    -- Change to vendor_value
    RewardSelector.set_policy("Armor", "vendor_value")
    local choice2 = RewardSelector.choose(rewards, blackboard)
    assert(choice2 == 1, "vendor_value policy picks higher sell price")
    
    RewardSelector.set_policy("Armor", "upgrade")
    RewardSelector._get_item_info = original
    print("✓ test_policy_override passed")
end

function tests.run_all()
    print("Running RewardSelector tests...")
    tests.test_choose_upgrade()
    tests.test_choose_vendor_value()
    tests.test_quest_item_priority()
    tests.test_policy_override()
    print("All RewardSelector tests passed!")
end

return tests