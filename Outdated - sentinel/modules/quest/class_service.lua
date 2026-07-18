local ClassService = {}
ClassService.__index = ClassService

---@class ClassData
---@field reagent_consumption table<string, integer[]> Item IDs per reagent type
---@field trainer_frequency string "high" | "medium" | "low"
---@field special_needs table<string, boolean>
---@field mount_level integer

---TBC Class Data (9 classes)
---@type table<string, ClassData>
ClassService.CLASS_DATA = {
    WARRIOR = {
        reagent_consumption = {
            food = true,
        },
        trainer_frequency = "high",
        special_needs = {},
        mount_level = 40,
    },
    PALADIN = {
        reagent_consumption = {
            food = true,
            water = true,
        },
        trainer_frequency = "high",
        special_needs = {},
        mount_level = 40,
    },
    HUNTER = {
        reagent_consumption = {
            ammo = {2512, 2515, 3033, 2516, 2517, 3033}, -- Arrows/bullets
            pet_food = {2287, 2672, 2673, 3602, 3726, 3603}, -- Pet food
        },
        trainer_frequency = "medium",
        special_needs = {stable = true, pet_happiness = true},
        mount_level = 40,
    },
    ROGUE = {
        reagent_consumption = {
            poisons = {2892, 2893, 3775, 3776, 8984, 8985, 9186, 9187, 9188}, -- Instant, Deadly, Wound, Crippling, Mind-numbing
        },
        trainer_frequency = "medium",
        special_needs = {},
        mount_level = 40,
    },
    PRIEST = {
        reagent_consumption = {
            food = true,
            water = true,
        },
        trainer_frequency = "high",
        special_needs = {},
        mount_level = 40,
    },
    SHAMAN = {
        reagent_consumption = {
            food = true,
            water = true,
            reagents = {17030, 17031, 17032, 17033}, -- Ankhs, etc.
        },
        trainer_frequency = "high",
        special_needs = {},
        mount_level = 40,
    },
    MAGE = {
        reagent_consumption = {
            food = true,
            water = true,
            teleport_runes = {17031, 17032, 17033, 17034}, -- Teleport runes
            portal_runes = {17035, 17036, 17037}, -- Portal runes
        },
        trainer_frequency = "high",
        special_needs = {teleport = true, portal = true},
        mount_level = 40,
    },
    WARLOCK = {
        reagent_consumption = {
            soul_shards = {6265}, -- Soul Shard
        },
        trainer_frequency = "medium",
        special_needs = {summon_ritual = true, soul_shards = true},
        mount_level = 40,
    },
    DRUID = {
        reagent_consumption = {
            food = true,
            water = true,
        },
        trainer_frequency = "high",
        special_needs = {},
        mount_level = 40,
    },
}

---Get quest requirements for class
---@param class string Uppercase class name (e.g., "WARRIOR")
---@return ClassData
function ClassService.get_quest_requirements(class)
    return ClassService.CLASS_DATA[class:upper()] or ClassService.CLASS_DATA.WARRIOR
end

---Get missing reagents for class
---@param class string
---@param blackboard table
---@return table<string, integer[]> missing_by_type
function ClassService.get_missing_reagents(class, blackboard)
    local data = ClassService.get_quest_requirements(class)
    local missing = {}
    
    for reagent_type, item_ids in pairs(data.reagent_consumption or {}) do
        if type(item_ids) == "table" then
            local count = 0
            for _, id in ipairs(item_ids) do
                -- Would need BagScanner to check actual counts
                count = count + 1
            end
            if count == 0 then
                missing[reagent_type] = item_ids
            end
        end
    end
    
    return missing
end

---Get trainer spells for class at level
---@param class string
---@param level integer
---@return integer[] spell_ids
function ClassService.get_trainer_spells(class, level)
    local data = ClassService.get_quest_requirements(class)
    local spells = {}
    
    -- This would need a spell database - placeholder
    -- Returns spell IDs that should be trained at this level
    return spells
end

---Get mount training level for class
---@param class string
---@return integer
function ClassService.get_mount_level(class)
    local data = ClassService.get_quest_requirements(class)
    return data.mount_level or 40
end

---Check if class has special need
---@param class string
---@param need string
---@return boolean
function ClassService.has_special_need(class, need)
    local data = ClassService.get_quest_requirements(class)
    return data.special_needs[need] == true
end

---Get all classes
---@return string[]
function ClassService.get_all_classes()
    local classes = {}
    for class, _ in pairs(ClassService.CLASS_DATA) do
        classes[#classes + 1] = class
    end
    return classes
end

return ClassService