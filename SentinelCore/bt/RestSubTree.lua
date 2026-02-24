local BT = require("ai/BehaviorTree")
local S = BT.Status

local RestSubTree = {}

-- Flash of Light ranks: highest first
local FLASH_OF_LIGHT_RANKS = { 27137, 19943, 19942, 19941, 19940, 19939, 19750 }

-- Drink item IDs by RequiredLevel DESC (source: tbcmangos.item_template + npc_vendor)
local DRINK_ITEMS = {
    -- Level 65
    27860, -- Purified Draenic Water
    32453, -- Star's Tears
    33042, -- Black Coffee
    22018, -- Conjured Glacier Water
    34062, -- Conjured Manna Biscuit
    -- Level 60
    28399, -- Filtered Draenic Water
    29454, -- Silverwine
    30703, -- Conjured Mountain Spring Water
    -- Level 55
    32455, -- Star's Lament
    8079,  -- Conjured Crystal Water
    -- Level 45
    8766,  -- Morning Glory Dew
    8078,  -- Conjured Sparkling Water
    -- Level 35
    1645,  -- Moonberry Juice
    8077,  -- Conjured Mineral Water
    -- Level 25
    1708,  -- Sweet Nectar
    3772,  -- Conjured Spring Water
    -- Level 15
    1205,  -- Melon Juice
    2136,  -- Conjured Purified Water
    -- Level 5
    1179,  -- Ice Cold Milk
    2288,  -- Conjured Fresh Water
    -- Level 1
    159,   -- Refreshing Spring Water
    5350,  -- Conjured Water
}
-- Food item IDs by RequiredLevel DESC (source: tbcmangos.item_template + npc_vendor)
local FOOD_ITEMS = {
    -- Level 65
    29451, -- Clefthoof Ribs
    29448, -- Mag'har Mild Cheese
    29449, -- Bladespire Bagel
    29450, -- Telaari Grapes
    29452, -- Zangar Trout
    33052, -- Fisherman's Feast
    22019, -- Conjured Croissant
    -- Level 55
    27854, -- Smoked Talbuk Venison
    27855, -- Mag'har Grainbread
    27856, -- Skethyl Berries
    27857, -- Garadar Sharp
    27858, -- Sunspring Carp
    27859, -- Zangar Caps
    22895, -- Conjured Cinnamon Roll
    -- Level 45
    8952,  -- Roasted Quail
    8950,  -- Homemade Cherry Pie
    8932,  -- Alterac Swiss
    8953,  -- Deep Fried Plantains
    8957,  -- Spinefin Halibut
    8076,  -- Conjured Sweet Roll
    -- Level 35
    4599,  -- Cured Ham Steak
    4601,  -- Soft Banana Bread
    3927,  -- Fine Aged Cheddar
    6887,  -- Spotted Yellowtail
    8075,  -- Conjured Sourdough
    -- Level 25
    3771,  -- Wild Hog Shank
    1707,  -- Stormwind Brie
    4539,  -- Goldenbark Apple
    1487,  -- Conjured Pumpernickel
    -- Level 15
    422,   -- Dwarven Mild
    3770,  -- Mutton Chop
    4538,  -- Snapvine Watermelon
    1114,  -- Conjured Rye
    -- Level 5
    4541,  -- Freshly Baked Bread
    2287,  -- Haunch of Meat
    414,   -- Dalaran Sharp
    1113,  -- Conjured Bread
    -- Level 1
    117,   -- Tough Jerky
    4540,  -- Tough Hunk of Bread
    2070,  -- Darnassian Bleu
    4536,  -- Shiny Red Apple
    5349,  -- Conjured Muffin
}

--- Find the highest learned rank from a list of spell IDs (highest first).
---@param ranks number[]
---@return number|nil
local function best_rank(ranks)
    if not core or not core.spell_book or not core.spell_book.is_spell_learned then
        return ranks[1]
    end
    for i = 1, #ranks do
        if core.spell_book.is_spell_learned(ranks[i]) then
            return ranks[i]
        end
    end
    return nil
end

--- Find the first available drink/food item from a priority list.
--- Uses game_object:has_item() on the player object.
---@param player any game_object
---@param item_ids number[]
---@return number|nil
local function find_consumable(player, item_ids)
    if not player or not player.has_item then return nil end
    for i = 1, #item_ids do
        local ok, found = pcall(function() return player:has_item(item_ids[i]) end)
        if ok and found then
            return item_ids[i]
        end
    end
    return nil
end

--- Use an item by ID.
---@param item_id number
local function use_item(item_id)
    if core.input and core.input.use_item then
        pcall(function() core.input.use_item(item_id) end)
    end
end

--- Get player mana percentage.
---@param player any
---@return number 0.0 to 1.0
local function get_mana_pct(player)
    if not player then return 1 end
    local ok, pct = pcall(function()
        local m = player:get_power(0) or 0
        local mm = player:get_max_power(0) or 1
        return mm > 0 and (m / mm) or 1
    end)
    return ok and pct or 1
end

function RestSubTree.build(bb, navigation)
    local rest_start_time = nil
    local heal_spell_id = best_rank(FLASH_OF_LIGHT_RANKS)
    local drink_applied = false
    local food_applied = false
    local last_heal_time = 0

    return BT.ReactiveSequence:new("rest", {
        -- Gate: needs recovery and not in combat (re-evaluated every tick)
        -- Enters when HP < 50% OR mana < 30%. Stays until HP >= 90% AND mana >= 80%.
        BT.Condition:new("needs_rest", function()
            if bb:get("player.in_combat", false) then
                if rest_start_time then
                    rest_start_time = nil
                    drink_applied = false
                    food_applied = false
                    bb:set("combat.was_resting", false)
                end
                return false
            end

            local hp = bb:get("player.health", 0)
            local max_hp = bb:get("player.max_health", 1)
            local hp_pct = max_hp > 0 and (hp / max_hp) or 1

            local player = bb:get("player.object")
            local mana_pct = get_mana_pct(player)

            -- If already resting, stay until both HP and mana are recovered
            if rest_start_time then
                if hp_pct >= 0.90 and mana_pct >= 0.80 then
                    rest_start_time = nil
                    bb:set("combat.was_resting", false)
                    return false
                end
                return true
            end

            -- Not resting yet — enter rest if HP or mana is low
            return hp_pct < 0.50 or mana_pct < 0.30
        end),

        -- Heal/eat/drink action
        BT.Action:new("eat_drink", function()
            local now = core.time()

            if not rest_start_time then
                rest_start_time = now
                drink_applied = false
                food_applied = false
                bb:set("combat.was_resting", true)
                if navigation and navigation.stop then
                    pcall(function() navigation:stop() end)
                end
            end

            local hp = bb:get("player.health", 0)
            local max_hp = bb:get("player.max_health", 1)
            local hp_pct = max_hp > 0 and (hp / max_hp) or 1

            local player = bb:get("player.object")
            local mana_pct = get_mana_pct(player)

            -- Fully recovered
            if hp_pct >= 0.90 and mana_pct >= 0.80 then
                rest_start_time = nil
                drink_applied = false
                food_applied = false
                bb:set("combat.was_resting", false)
                return S.SUCCESS
            end

            local is_casting = bb:get("player.is_casting", false)

            -- Drink water once per rest session
            if mana_pct < 0.80 and not drink_applied then
                local drink_id = find_consumable(player, DRINK_ITEMS)
                if drink_id then
                    use_item(drink_id)
                    drink_applied = true
                end
            end

            -- Eat food once per rest session
            if hp_pct < 0.90 and not food_applied then
                local food_id = find_consumable(player, FOOD_ITEMS)
                if food_id then
                    use_item(food_id)
                    food_applied = true
                end
            end

            -- Cast self-heal only if food is NOT ticking (casting interrupts eating)
            -- and HP is critically low (< 30%), or no food was available
            if hp_pct < 0.90 and mana_pct > 0.10 and not is_casting
                and heal_spell_id and (now - last_heal_time) > 2.0
                and not food_applied then
                if core.input and core.input.cast_target_spell and player then
                    pcall(function()
                        core.input.cast_target_spell(heal_spell_id, player)
                    end)
                    last_heal_time = now
                end
            end

            -- Timeout: don't rest forever (60s for mana recovery)
            if now - rest_start_time > 60 then
                rest_start_time = nil
                drink_applied = false
                food_applied = false
                bb:set("combat.was_resting", false)
                return S.FAILURE
            end

            return S.RUNNING
        end),
    })
end

return RestSubTree
