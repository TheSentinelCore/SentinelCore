local BagScanner = require("modules/grind/bag_scanner")
local ConsumableIds = require("modules/grind/consumable_ids")
local ClassService = require("modules/quest/class_service")

local InventoryAuditor = {}
InventoryAuditor.__index = InventoryAuditor

---Create new InventoryAuditor
---@param blackboard table
---@return InventoryAuditor
function InventoryAuditor.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _warnings = {},
        _critical = false,
    }, InventoryAuditor)
end

---Run pre-departure audit
---@param quest_plan table QuestPlan from QuestPlanner
---@return table audit_report
function InventoryAuditor:audit(quest_plan)
    self._warnings = {}
    self._critical = false
    
    local report = {
        free_slots = 0,
        quest_items = 0,
        consumables = {},
        class_reagents = {},
        warnings = {},
        critical = false,
        timestamp = self._blackboard:get("system.now_ms", 0),
    }
    
    -- Bag space
    local free_slots = BagScanner.count_free_slots()
    local total_slots = BagScanner.count_total_slots()
    report.free_slots = free_slots
    report.total_slots = total_slots
    
    -- Quest items
    report.quest_items = BagScanner.count_quest_items()
    
    -- Consumables
    report.consumables = {
        food = BagScanner.count_by_ids(ConsumableIds.FOOD or {}),
        water = BagScanner.count_by_ids(ConsumableIds.WATER or {}),
        health_pots = BagScanner.count_by_ids(ConsumableIds.HEALTH_POTIONS or {}),
        mana_pots = BagScanner.count_by_ids(ConsumableIds.MANA_POTIONS or {}),
    }
    
    -- Class reagents
    local _, class = UnitClass("player")
    local reqs = ClassService.get_quest_requirements(class)
    for name, ids in pairs(reqs.reagent_consumption or {}) do
        report.class_reagents[name] = BagScanner.count_by_ids(ids)
    end
    
    -- Get thresholds from profile
    local profile = self._blackboard:get("module.quest.active_profile")
    local min_free = profile and profile.rules and profile.rules.min_bag_slots or 4
    local min_food = profile and profile.rules and profile.rules.min_food_stacks or 2
    local min_water = profile and profile.rules and profile.rules.min_water_stacks or 2
    local min_pots = profile and profile.rules and profile.rules.min_potion_stacks or 1
    
    -- Check bag space
    if free_slots < min_free then
        report.warnings[#report.warnings + 1] = string.format("BAG_SPACE_LOW: %d/%d free", free_slots, min_free)
        report.critical = true
    end
    
    -- Check consumables
    if report.consumables.food < min_food then
        report.warnings[#report.warnings + 1] = string.format("FOOD_LOW: %d/%d", report.consumables.food, min_food)
    end
    if report.consumables.water < min_water then
        report.warnings[#report.warnings + 1] = string.format("WATER_LOW: %d/%d", report.consumables.water, min_water)
    end
    if (report.consumables.health_pots + report.consumables.mana_pots) < min_pots then
        report.warnings[#report.warnings + 1] = "POTIONS_LOW"
    end
    
    -- Check quest plan lookahead for upcoming COLLECT objectives
    if quest_plan and quest_plan.phases then
        for _, phase in ipairs(quest_plan.phases) do
            if phase.type == "OBJECTIVE_COLLECT" then
                local item_id = phase.item_id
                local needed = phase.count
                local have = BagScanner.count_item(item_id) or 0
                if needed > have and free_slots < (needed - have) then
                    report.warnings[#report.warnings + 1] = string.format("NEED_%d_SLOTS_FOR_%s", needed - have, item_id)
                    report.critical = true
                end
            end
        end
    end
    
    report.critical = report.critical or #report.warnings > 0
    return report
end

---Inject RETURN_TO_TOWN phase if critical
---@param quest_plan table
---@param report table
---@return table modified_plan
function InventoryAuditor.inject_town_phase(quest_plan, report)
    if not report.critical then return quest_plan end
    
    local town_phase = {
        type = "RETURN_TO_TOWN",
        reason = report.warnings,
        priority = "CRITICAL",
        services = {"VENDOR", "REPAIR", "MAIL", "TRAIN"},
        inserted_at = self._blackboard:get("system.now_ms", 0),
    }
    
    -- Insert at beginning of phases
    table.insert(quest_plan.phases, 1, town_phase)
    
    -- Adjust current_phase index
    if quest_plan.current_phase then
        quest_plan.current_phase = quest_plan.current_phase + 1
    end
    
    return quest_plan
end

---Quick check if town return needed
---@return boolean
function InventoryAuditor.needs_town()
    local bb = self._blackboard
    local free = BagScanner.count_free_slots()
    local min_free = bb:get("module.quest.min_bag_slots", 4)
    if free < min_free then return true end
    
    local durability = bb:get("module.grind.avg_durability_pct", 100)
    if durability < 40 then return true end
    
    return false
end

return InventoryAuditor