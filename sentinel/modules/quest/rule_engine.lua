local RuleEngine = {}
RuleEngine.__index = RuleEngine

---@class QuestProfile
---@field zone string
---@field level_range table {min, max}
---@field faction string
---@field rules table
---@field scoring table

---Evaluate a quest against profile rules
---@param profile QuestProfile
---@param quest_node table QuestNode from QuestGraph
---@param context table
---@return boolean pass
---@return string|nil reason
function RuleEngine.evaluate(profile, quest_node, context)
    local rules = profile.rules
    if not rules then return true, nil end
    
    -- Skip elites
    if rules.skip_elites and quest_node.is_elite then
        return false, "elite"
    end
    
    -- Skip escorts (type check)
    if rules.skip_escort then
        for _, obj in ipairs(quest_node.objectives) do
            if obj.type == "ESCORT" then
                return false, "escort"
            end
        end
    end
    
    -- Skip dungeon chains
    if rules.skip_dungeon_chains and quest_node.is_dungeon then
        return false, "dungeon"
    end
    
    -- Skip PvP zones (would need zone data)
    if rules.skip_pvp and context.zone_pvp then
        return false, "pvp"
    end
    
    -- Max travel distance
    if rules.max_travel_yards and context.nav_adapter then
        local dist = context.nav_adapter:estimate_distance(context.player_pos, quest_node.start_npc)
        if dist and dist > rules.max_travel_yards then
            return false, "travel"
        end
    end
    
    -- Min XP per minute
    if rules.min_xp_per_minute and context.scorer then
        local score = context.scorer:score(quest_node, context)
        if score < rules.min_xp_per_minute then
            return false, "xp_rate"
        end
    end
    
    return true, nil
end

---Filter quests by profile rules
---@param quests table[] QuestNodes
---@param profile QuestProfile
---@param context table
---@return table[]
function RuleEngine.filter_quests(quests, profile, context)
    local filtered = {}
    for _, quest in ipairs(quests) do
        local pass, reason = RuleEngine.evaluate(profile, quest, context)
        if pass then
            filtered[#filtered + 1] = quest
        end
    end
    return filtered
end

---Check if player should return to town
---@param profile QuestProfile
---@param blackboard table
---@return boolean should_town
---@return string|nil reason
function RuleEngine.should_return_to_town(profile, blackboard)
    local rules = profile.rules
    if not rules then return false, nil end
    
    -- Bag space
    local free_slots = blackboard:get("module.grind.bag_free_slots", 0)
    local total_slots = blackboard:get("module.grind.bag_total_slots", 16)
    local bag_pct = (free_slots / total_slots) * 100
    
    if rules.vendor_threshold_pct and (100 - bag_pct) >= rules.vendor_threshold_pct then
        return true, "vendor"
    end
    
    if rules.min_bag_slots and free_slots < rules.min_bag_slots then
        return true, "bags"
    end
    
    -- Durability
    local durability = blackboard:get("module.grind.avg_durability_pct", 100)
    if rules.repair_threshold_pct and durability <= rules.repair_threshold_pct then
        return true, "repair"
    end
    
    return false, nil
end

---Get scoring weights from profile
---@param profile QuestProfile
---@return table
function RuleEngine.get_scoring_weights(profile)
    if profile and profile.scoring then
        return profile.scoring
    end
    return {
        xp_per_minute = 0.35,
        travel_efficiency = 0.25,
        objective_overlap = 0.20,
        reward_value = 0.10,
        chain_priority = 0.10,
    }
end

return RuleEngine