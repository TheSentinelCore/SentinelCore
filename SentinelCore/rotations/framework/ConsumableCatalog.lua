---@class ConsumableCatalog
local ConsumableCatalog = {}

-- Ordered highest value to lowest for TBC environments.
ConsumableCatalog.TBC_FOOD_ITEM_IDS = {
    34062, -- Conjured Mana Biscuit (food+drink)
    27854, -- Smoked Talbuk Venison
    8952,  -- Roasted Quail
    4601,  -- Soft Banana Bread
    4544,  -- Mulgore Spice Bread
    4542,  -- Moist Cornbread
    4541,  -- Freshly Baked Bread
    4540,  -- Tough Hunk of Bread
    22895, -- Conjured Cinnamon Roll
    8076,  -- Conjured Sweet Roll
    8075,  -- Conjured Sourdough
    1487,  -- Conjured Pumpernickel
    1114,  -- Conjured Rye
    1113,  -- Conjured Bread
}

-- Ordered highest value to lowest for TBC environments.
ConsumableCatalog.TBC_WATER_ITEM_IDS = {
    34062, -- Conjured Mana Biscuit (food+drink)
    27860, -- Purified Draenic Water
    28399, -- Filtered Draenic Water
    22018, -- Conjured Glacier Water
    19300, -- Bottled Winterspring Water
    8766,  -- Morning Glory Dew
    1645,  -- Moonberry Juice
    1708,  -- Sweet Nectar
    1205,  -- Melon Juice
    1179,  -- Ice Cold Milk
    8079,  -- Conjured Crystal Water
    3772,  -- Conjured Spring Water
    8078,  -- Conjured Sparkling Water
    2136,  -- Conjured Purified Water
    2288,  -- Conjured Fresh Water
    5350,  -- Conjured Water
}

return ConsumableCatalog
