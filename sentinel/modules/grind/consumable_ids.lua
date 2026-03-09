-- All food item IDs (class=0, subclass=5, FoodType>0) from mangos-tbc item_template
local FOOD_ITEMS = {
    [117]=true,[414]=true,[422]=true,[724]=true,[787]=true,[1017]=true,[1113]=true,
    [1114]=true,[1326]=true,[1487]=true,[1707]=true,[2070]=true,[2287]=true,
    [2679]=true,[2680]=true,[2681]=true,[2682]=true,[2683]=true,[2684]=true,
    [2685]=true,[2687]=true,[2888]=true,[3220]=true,[3448]=true,[3662]=true,
    [3664]=true,[3665]=true,[3666]=true,[3726]=true,[3727]=true,[3728]=true,
    [3729]=true,[3770]=true,[3771]=true,[3927]=true,[4457]=true,[4536]=true,
    [4537]=true,[4538]=true,[4539]=true,[4540]=true,[4541]=true,[4542]=true,
    [4544]=true,[4592]=true,[4593]=true,[4594]=true,[4599]=true,[4601]=true,
    [4602]=true,[4604]=true,[4605]=true,[4606]=true,[4607]=true,[4608]=true,
    [4656]=true,[5057]=true,[5095]=true,[5349]=true,[5472]=true,[5474]=true,
    [5476]=true,[5477]=true,[5478]=true,[5479]=true,[5480]=true,[5525]=true,
    [5526]=true,[5527]=true,[6038]=true,[6290]=true,[6316]=true,[6887]=true,
    [6890]=true,[7097]=true,[8075]=true,[8076]=true,[8364]=true,[8932]=true,
    [8948]=true,[8950]=true,[8952]=true,[8953]=true,[8957]=true,[9681]=true,
    [11444]=true,[12209]=true,[12210]=true,[12212]=true,[12213]=true,
    [12215]=true,[12216]=true,[12217]=true,[12218]=true,[12224]=true,
    [12238]=true,[13546]=true,[13755]=true,[13851]=true,[13893]=true,
    [13927]=true,[13928]=true,[13929]=true,[13930]=true,[13931]=true,
    [13932]=true,[13933]=true,[13934]=true,[13935]=true,[16168]=true,
    [16169]=true,[16766]=true,[16971]=true,[17119]=true,[17197]=true,
    [17222]=true,[17406]=true,[18045]=true,[19223]=true,[19224]=true,
    [19304]=true,[19305]=true,[19306]=true,[19696]=true,[19994]=true,
    [19995]=true,[19996]=true,[20074]=true,[20857]=true,[21023]=true,
    [21030]=true,[21031]=true,[21033]=true,[21072]=true,[21217]=true,
    [21235]=true,[21254]=true,[21552]=true,[22019]=true,[22645]=true,
    [22895]=true,[23160]=true,[23495]=true,[24072]=true,[24105]=true,
    [24539]=true,[27635]=true,[27636]=true,[27651]=true,[27655]=true,
    [27657]=true,[27658]=true,[27659]=true,[27660]=true,[27661]=true,
    [27662]=true,[27663]=true,[27664]=true,[27665]=true,[27666]=true,
    [27667]=true,[27854]=true,[27855]=true,[27856]=true,[27857]=true,
    [27858]=true,[27859]=true,[28112]=true,[28486]=true,[29292]=true,
    [29393]=true,[29394]=true,[29448]=true,[29449]=true,[29450]=true,
    [29451]=true,[29452]=true,[30155]=true,[30458]=true,[30610]=true,
    [31673]=true,[33048]=true,[33052]=true,[33053]=true,
}

-- All water/drink item IDs (class=0, subclass=5, FoodType=0) from mangos-tbc item_template
local WATER_ITEMS = {
    [159]=true,[733]=true,[961]=true,[1082]=true,[1179]=true,[1205]=true,
    [1401]=true,[1645]=true,[1708]=true,[2136]=true,[2288]=true,[2593]=true,
    [2594]=true,[2595]=true,[2596]=true,[2686]=true,[2723]=true,[2894]=true,
    [3663]=true,[3703]=true,[3772]=true,[4595]=true,[4600]=true,[4791]=true,
    [5066]=true,[5342]=true,[5350]=true,[5473]=true,[6299]=true,[6522]=true,
    [6657]=true,[6807]=true,[6888]=true,[7228]=true,[7676]=true,[7806]=true,
    [7807]=true,[7808]=true,[8077]=true,[8078]=true,[8079]=true,[8766]=true,
    [9360]=true,[9361]=true,[9451]=true,[10841]=true,[11109]=true,[11415]=true,
    [11584]=true,[11846]=true,[11951]=true,[12003]=true,[12214]=true,
    [13724]=true,[13810]=true,[16166]=true,[16167]=true,[16170]=true,
    [16171]=true,[17196]=true,[17198]=true,[17344]=true,[17402]=true,
    [17403]=true,[17404]=true,[17407]=true,[17408]=true,[18254]=true,
    [18255]=true,[18287]=true,[18288]=true,[18300]=true,[18632]=true,
    [18633]=true,[18635]=true,[19221]=true,[19222]=true,[19225]=true,
    [19299]=true,[19300]=true,[19301]=true,[20031]=true,[20452]=true,
    [20516]=true,[20709]=true,[21114]=true,[21151]=true,[21215]=true,
    [21721]=true,[22018]=true,[22324]=true,[23756]=true,[23848]=true,
    [24008]=true,[24009]=true,[24338]=true,[27656]=true,[27860]=true,
    [28284]=true,[28399]=true,[28501]=true,[29112]=true,[29395]=true,
    [29401]=true,[29412]=true,[29453]=true,[29454]=true,[30355]=true,
    [30357]=true,[30358]=true,[30359]=true,[30361]=true,[30457]=true,
    [30703]=true,[30816]=true,[31672]=true,[32453]=true,[32455]=true,
    [32667]=true,[32668]=true,[32685]=true,[32686]=true,[32721]=true,
    [32722]=true,[33042]=true,[33825]=true,[33866]=true,[33867]=true,
    [33872]=true,[33874]=true,[33924]=true,[34062]=true,[34411]=true,
    [34780]=true,[34832]=true,[35563]=true,[35565]=true,[38427]=true,
    [38428]=true,[38429]=true,[38430]=true,[38431]=true,[38432]=true,
    [38466]=true,
}

local HEALTH_POTIONS = {
    { min_level = 1,  item_id = 118   }, -- Minor Healing Potion
    { min_level = 12, item_id = 858   }, -- Lesser Healing Potion
    { min_level = 21, item_id = 929   }, -- Healing Potion
    { min_level = 35, item_id = 1710  }, -- Greater Healing Potion
    { min_level = 45, item_id = 3928  }, -- Superior Healing Potion
    { min_level = 55, item_id = 13446 }, -- Major Healing Potion
    { min_level = 60, item_id = 22829 }, -- Super Healing Potion
}

local MANA_POTIONS = {
    { min_level = 14, item_id = 2455  }, -- Minor Mana Potion
    { min_level = 22, item_id = 3385  }, -- Lesser Mana Potion
    { min_level = 31, item_id = 3827  }, -- Mana Potion
    { min_level = 41, item_id = 6149  }, -- Greater Mana Potion
    { min_level = 49, item_id = 13443 }, -- Superior Mana Potion
    { min_level = 55, item_id = 13444 }, -- Major Mana Potion
    { min_level = 60, item_id = 22832 }, -- Super Mana Potion
}

local HEALTH_POTION_IDS = {}
for _, entry in ipairs(HEALTH_POTIONS) do HEALTH_POTION_IDS[entry.item_id] = true end

local MANA_POTION_IDS = {}
for _, entry in ipairs(MANA_POTIONS) do MANA_POTION_IDS[entry.item_id] = true end

local VENDOR_FOOD = {
    { min_level = 1,  item_id = 117   }, -- Tough Jerky
    { min_level = 5,  item_id = 2287  }, -- Haunch of Meat
    { min_level = 15, item_id = 3770  }, -- Mutton Chop
    { min_level = 25, item_id = 3771  }, -- Wild Hog Shank
    { min_level = 35, item_id = 4599  }, -- Cured Ham Steak
    { min_level = 45, item_id = 8952  }, -- Roasted Quail
    { min_level = 55, item_id = 27854 }, -- Smoked Talbuk Venison
}

local VENDOR_WATER = {
    { min_level = 1,  item_id = 159   }, -- Refreshing Spring Water
    { min_level = 5,  item_id = 1179  }, -- Ice Cold Milk
    { min_level = 15, item_id = 1205  }, -- Melon Juice
    { min_level = 25, item_id = 1708  }, -- Sweet Nectar
    { min_level = 35, item_id = 1645  }, -- Moonberry Juice
    { min_level = 45, item_id = 8766  }, -- Morning Glory Dew
    { min_level = 55, item_id = 27860 }, -- Purified Draenic Water
}

local function resolve_for_level(table_list, player_level)
    local best = nil
    for _, entry in ipairs(table_list) do
        if player_level >= entry.min_level then
            best = entry.item_id
        end
    end
    return best
end

return {
    FOOD_ITEMS = FOOD_ITEMS,
    WATER_ITEMS = WATER_ITEMS,
    HEALTH_POTIONS = HEALTH_POTIONS,
    MANA_POTIONS = MANA_POTIONS,
    HEALTH_POTION_IDS = HEALTH_POTION_IDS,
    MANA_POTION_IDS = MANA_POTION_IDS,
    VENDOR_FOOD = VENDOR_FOOD,
    VENDOR_WATER = VENDOR_WATER,
    resolve_for_level = resolve_for_level,
}
