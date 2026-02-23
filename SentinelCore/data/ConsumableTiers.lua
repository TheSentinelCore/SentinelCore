-- Generated from tbcmangos.item_template
-- Vendor-purchasable food and water organized by minimum player level
-- Higher tiers first for quick lookup

local ConsumableTiers = {}

-- Water items (mana restoration)
ConsumableTiers.water = {
    { min_level = 65, ids = { 27860, 32453 } },        -- Purified Draenic Water, Star's Tears
    { min_level = 60, ids = { 28399 } },                -- Filtered Draenic Water
    { min_level = 45, ids = { 8766 } },                 -- Morning Glory Dew
    { min_level = 35, ids = { 1645 } },                 -- Moonberry Juice
    { min_level = 25, ids = { 1708 } },                 -- Sweet Nectar
    { min_level = 15, ids = { 1205 } },                 -- Melon Juice
    { min_level = 5,  ids = { 1179 } },                 -- Ice Cold Milk
    { min_level = 1,  ids = { 159 } },                  -- Refreshing Spring Water
}

-- Food items (health restoration)
ConsumableTiers.food = {
    { min_level = 65, ids = { 29451 } },                -- Clefthoof Ribs
    { min_level = 55, ids = { 27854, 27855 } },         -- Smoked Talbuk Venison, Mag'har Grainbread
    { min_level = 45, ids = { 8952, 8950 } },           -- Roasted Quail, Homemade Cherry Pie
    { min_level = 35, ids = { 4599, 4601 } },           -- Cured Ham Steak, Soft Banana Bread
    { min_level = 25, ids = { 3771 } },                 -- Wild Hog Shank
    { min_level = 15, ids = { 4542, 3770 } },           -- Moist Cornbread, Mutton Chop
    { min_level = 5,  ids = { 4541, 2287 } },           -- Freshly Baked Bread, Haunch of Meat
    { min_level = 1,  ids = { 4540, 117, 2070 } },      -- Tough Hunk of Bread, Tough Jerky, Darnassian Bleu
}

---@param kind string "food" or "water"
---@param player_level number
---@return number[]|nil
function ConsumableTiers.get_tier_ids(kind, player_level)
    local tiers = ConsumableTiers[kind]
    if not tiers then return nil end
    for i = 1, #tiers do
        if player_level >= tiers[i].min_level then
            return tiers[i].ids
        end
    end
    return nil
end

---@param item_id number
---@return string|nil "food", "water", or nil
function ConsumableTiers.classify(item_id)
    for _, tier in ipairs(ConsumableTiers.food) do
        for _, id in ipairs(tier.ids) do
            if id == item_id then return "food" end
        end
    end
    for _, tier in ipairs(ConsumableTiers.water) do
        for _, id in ipairs(tier.ids) do
            if id == item_id then return "water" end
        end
    end
    return nil
end

return ConsumableTiers
