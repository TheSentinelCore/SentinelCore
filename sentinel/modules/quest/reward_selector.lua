local RewardSelector = {}
RewardSelector.__index = RewardSelector

---Default policy per item class
---@type table<string, string>
RewardSelector.POLICIES = {
    Armor = "upgrade",
    Weapon = "upgrade",
    Consumable = "vendor_value",
    TradeGoods = "vendor_value",
    Quest = "keep",
    Recipe = "vendor_value",
    Gem = "vendor_value",
    Misc = "vendor_value",
    Reagent = "vendor_value",
}

---Configure policy for item class
---@param item_class string
---@param policy string "vendor_value" | "upgrade" | "keep"
function RewardSelector.set_policy(item_class, policy)
    RewardSelector.POLICIES[item_class] = policy
end

---Get policy for item class
---@param item_class string
---@return string
function RewardSelector.get_policy(item_class)
    return RewardSelector.POLICIES[item_class] or "vendor_value"
end

---Choose best reward from quest choices
---@param rewards table[] {item_id, count, index}
---@param blackboard table
---@param class string|nil Player class
---@return integer choice_index (1-based, 0 = no choice)
function RewardSelector.choose(rewards, blackboard, class)
    if not rewards or #rewards == 0 then return 0 end
    
    -- Get player class if not provided
    if not class and core and core.character then
        _, class = UnitClass("player")
    end
    class = class or "WARRIOR"
    
    -- Get equipped items for upgrade comparison
    local equipped = RewardSelector._get_equipped_items(blackboard)
    
    local best_choice = 0
    local best_score = -1
    
    for i, reward in ipairs(rewards) do
        local score = RewardSelector._score_reward(reward, equipped, class, blackboard)
        if score > best_score then
            best_score = score
            best_choice = i
        end
    end
    
    return best_choice
end

---Score a reward based on policy
---@param reward table {item_id, count, index}
---@param equipped table slot -> item_level
---@param class string
---@param blackboard table
---@return number score
function RewardSelector._score_reward(reward, equipped, class, blackboard)
    local item_id = reward.item_id
    if not item_id or item_id == 0 then return 0 end
    
    local item_info = RewardSelector._get_item_info(item_id)
    if not item_info then return 0 end
    
    -- Quest items - always keep
    if item_info.class == "Quest" then
        return 10000
    end
    
    -- Check if quest item via Sylvannas API
    if blackboard and blackboard.get then
        local quest_items = blackboard:get("module.quest.quest_items", {})
        if quest_items[item_id] then
            return 10000
        end
    end
    
    local policy = RewardSelector.POLICIES[item_info.class] or "vendor_value"
    
    if policy == "keep" then
        return 10000
    elseif policy == "upgrade" then
        return RewardSelector._score_upgrade(reward, item_info, equipped)
    else
        -- vendor_value
        return (item_info.sell_price or 0) * (reward.count or 1)
    end
end

---Score upgrade potential
---@param reward table
---@param item_info table
---@param equipped table
---@return number
function RewardSelector._score_upgrade(reward, item_info, equipped)
    local item_level = item_info.item_level or 0
    local slot = item_info.equip_slot or item_info.inventory_type
    
    if not slot or slot == 0 or slot == "" then 
        return (item_info.sell_price or 0) * (reward.count or 1)
    end
    
    local current_ilvl = equipped[slot] or 0
    local upgrade = item_level - current_ilvl
    
    if upgrade > 5 then
        return 5000 + upgrade * 50
    elseif upgrade > 0 then
        return 2000 + upgrade * 20
    else
        return (item_info.sell_price or 0) * (reward.count or 1)
    end
end

---Get item info from Sylvannas API
---@param item_id integer
---@return table|nil
function RewardSelector._get_item_info(item_id)
    if not core or not core.quests or not core.quests.get_item_info then
        return nil
    end
    
    local ok, info = pcall(core.quests.get_item_info, item_id)
    if ok and info then
        -- Parse Sylvannas item info format
        return {
            item_id = info.id or item_id,
            name = info.name,
            class = info.class,
            subclass = info.subclass,
            item_level = info.item_level,
            equip_slot = info.equip_slot or info.inventory_type,
            sell_price = info.sell_price or info.vendor_price,
            quality = info.quality,
        }
    end
    return nil
end

---Get currently equipped item levels per slot
---@param blackboard table
---@return table slot -> item_level
function RewardSelector._get_equipped_items(blackboard)
    local equipped = {}
    
    if not core or not core.inventory then return equipped end
    
    -- Scan equipment slots (0-18 for player)
    for slot = 0, 18 do
        local item = call(core.inventory.get_equipped_item, slot)
        if item then
            local ok, info = pcall(core.quests.get_item_info, item.id)
            if ok and info and info.item_level then
                equipped[slot] = info.item_level
            end
        end
    end
    
    return equipped
end

---Get vendor sell price
---@param item_id integer
---@return integer copper
function RewardSelector.get_vendor_price(item_id)
    local info = RewardSelector._get_item_info(item_id)
    return info and info.sell_price or 0
end

---Check if item is quest item
---@param item_id integer
---@param blackboard table
---@return boolean
function RewardSelector.is_quest_item(item_id, blackboard)
    if blackboard and blackboard.get then
        local quest_items = blackboard:get("module.quest.quest_items", {})
        return quest_items[item_id] == true
    end
    return false
end

return RewardSelector