-- sentinel/modules/quest/quest_graph.lua
-- QuestGraph: Read-only data accessor for quest/NPC data (replaces planning logic with on-demand queries)

local QueryClient = require("modules/quest/query_client")

local QuestGraph = {}
QuestGraph.__index = QuestGraph

local CACHE_TTL_S = 3600 -- 1 hour for graph data

---@class QuestNode
---@field id integer
---@field title string
---@field level integer
---@field zone string
---@field zone_or_sort integer
---@field start_npc table|nil {id, name, x, y, z, map_id}
---@field end_npc table|nil {id, name, x, y, z, map_id}
---@field objectives table[] -- {type, target_id, count, text, spawn_clusters}
---@field rewards table {xp, money, choices[], fixed[]}
---@field suggested_players integer
---@field is_elite boolean
---@field is_dungeon boolean
---@field prev_quest_id integer
---@field next_quest_id integer
---@field next_in_chain integer
---@field breadcrumb_for integer
---@field exclusive_group integer
---@field required_classes integer
---@field required_races integer
---@field min_level integer
---@field max_level integer
---@field required_level integer

---@class QuestGraph
---@field nodes table<integer, QuestNode>
---@field edges table<integer, {requires:integer[], follows:integer[], continues:integer[], breadcrumbs:integer[], excludes:integer[]}>
---@field available table<integer, boolean>
---@field completed table<integer, boolean>
---@field _cache table
---@field _client QueryClient

---Create new QuestGraph instance
---@param blackboard table
---@return QuestGraph
function QuestGraph.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _client = QueryClient.new(blackboard),
        _cache = {},
        nodes = {},
        edges = {},
        available = {},
        completed = {},
    }, QuestGraph)
end

---Load completed quests from Sylvannas API
function QuestGraph:_load_completed_quests()
    self.completed = {}
end

---Check if a quest is completed
---@param quest_id integer
---@return boolean
function QuestGraph:is_completed(quest_id)
    if self.completed[quest_id] ~= nil then
        return self.completed[quest_id]
    end
    if core and core.quests and core.quests.is_quest_flagged_completed then
        local ok, result = pcall(core.quests.is_quest_flagged_completed, tonumber(quest_id))
        if ok and result == true then
            self.completed[quest_id] = true
            return true
        end
    end
    self.completed[quest_id] = false
    return false
end

---Get quest IDs for a zone/level from Questie or fallback
---@return integer[]
function QuestGraph:_get_quest_ids_for_zone(zone, min_level, max_level, faction)
    -- Try Questie first
    if Questie and Questie.is_ready and Questie.is_ready() and Questie.get_quest_ids then
        local ok, ids = pcall(Questie.get_quest_ids)
        if ok and ids then
            local filtered = {}
            for _, qid in ipairs(ids) do
                local qdata = self._client:fetch_quest(qid)
                if qdata then
                    local ql = tonumber(qdata.quest_level) or 0
                    local qzone = tonumber(qdata.zone_or_sort) or 0
                    local req_r = tonumber(qdata.required_races) or 0
                    local req_c = tonumber(qdata.required_classes) or 0
                    
                    local zone_match = not zone or qzone == self:_zone_name_to_id(zone)
                    local level_match = ql >= min_level and ql <= max_level
                    local faction_match = self:_faction_matches(req_r, faction)
                    local class_match = self:_class_matches(req_c)
                    
                    if zone_match and level_match and faction_match and class_match then
                        filtered[#filtered + 1] = qid
                    end
                end
            end
            return filtered
        end
    end
    
    -- Fallback: query a range of known quest IDs
    return {}
end

---Convert zone name to map ID
function QuestGraph:_zone_name_to_id(zone_name)
    local zone_map = {
        ["Westfall"] = 0, ["Redridge Mountains"] = 0, ["Duskwood"] = 0,
        ["Loch Modan"] = 0, ["Silverpine Forest"] = 0, ["Darkshore"] = 1,
        ["Elwynn Forest"] = 0, ["Tirisfal Glades"] = 0, ["Silverpine Forest"] = 0,
        ["The Barrens"] = 1, ["Stonetalon Mountains"] = 1, ["Ashenvale"] = 1,
    }
    return zone_map[zone_name] or 0
end

---Check if quest faction matches player
function QuestGraph:_faction_matches(required_races, faction)
    if not faction or faction == "Both" then return true end
    if required_races == 0 then return true end
    
    local alliance_mask = 1 + 4 + 8 + 16 + 128 -- Human=1, Dwarf=4, NightElf=8, Gnome=16, Draenei=128
    local horde_mask = 2 + 8 + 32 + 128 + 512 -- Orc=2, Undead=8, Tauren=32, Troll=128, BloodElf=512
    
    if faction == "Alliance" then
        return bit.band(required_races, alliance_mask) ~= 0
    elseif faction == "Horde" then
        return bit.band(required_races, horde_mask) ~= 0
    end
    return true
end

---Check if quest class matches player
function QuestGraph:_class_matches(required_classes)
    if required_classes == 0 then return true end
    -- Would need player class from blackboard
    return true
end

---Build graph from database for a zone/level range
---@param zone string|nil Zone name
---@param level_range table|nil {min, max}
---@param faction string|nil "Alliance"|"Horde"|"Both"
---@return QuestGraph self
function QuestGraph:build_from_db(zone, level_range, faction)
    local min_level = level_range and level_range.min or 1
    local max_level = level_range and level_range.max or 80
    faction = faction or self._blackboard:get("player.faction", "Both")
    
    self.nodes = {}
    self.edges = {}
    self.available = {}
    self.completed = {}
    
    local quest_ids = self:_get_quest_ids_for_zone(zone, min_level, max_level, faction)
    
    for _, quest_id in ipairs(quest_ids) do
        local node = self:_build_node(quest_id)
        if node then
            self.nodes[quest_id] = node
            self:_build_edges(node)
        end
    end
    
    self:_filter_available(faction)
    return self
end

---Build a QuestNode from raw quest data
function QuestGraph:_build_node(quest_id)
    local qdata = self._client:fetch_quest(quest_id)
    if not qdata then return nil end
    
    local objectives = self:_parse_objectives(qdata)
    local rewards = self:_parse_rewards(qdata)
    local start_npc = self:_get_npc(quest_id, "giver")
    local end_npc = self:_get_npc(quest_id, "turnin")
    
    return {
        id = quest_id,
        title = qdata.title or "",
        level = tonumber(qdata.quest_level) or 0,
        zone = self:_zone_id_to_name(tonumber(qdata.zone_or_sort) or 0),
        zone_or_sort = tonumber(qdata.zone_or_sort) or 0,
        start_npc = start_npc,
        end_npc = end_npc,
        objectives = objectives,
        rewards = rewards,
        suggested_players = tonumber(qdata.suggested_players) or 1,
        is_elite = (tonumber(qdata.suggested_players) or 1) > 1,
        is_dungeon = self:_is_dungeon_zone(tonumber(qdata.zone_or_sort) or 0),
        prev_quest_id = tonumber(qdata.prev_quest_id) or 0,
        next_quest_id = tonumber(qdata.next_quest_id) or 0,
        next_in_chain = tonumber(qdata.next_quest_in_chain) or 0,
        breadcrumb_for = tonumber(qdata.breadcrumb_for_quest_id) or 0,
        exclusive_group = tonumber(qdata.exclusive_group) or 0,
        required_classes = tonumber(qdata.required_classes) or 0,
        required_races = tonumber(qdata.required_races) or 0,
        min_level = tonumber(qdata.min_level) or 0,
        max_level = tonumber(qdata.max_level) or 0,
        required_level = tonumber(qdata.quest_level) or 0,
    }
end

---Parse objectives from quest data
function QuestGraph:_parse_objectives(qdata)
    local objectives = {}
    for i = 1, 4 do
        local item_id = tonumber(qdata["req_item_id" .. i]) or 0
        local item_count = tonumber(qdata["req_item_count" .. i]) or 0
        local creature_id = tonumber(qdata["req_creature_or_go_id" .. i]) or 0
        local creature_count = tonumber(qdata["req_creature_or_go_count" .. i]) or 0
        local spell_id = tonumber(qdata["req_spell_cast" .. i]) or 0
        local text = qdata["objective_text" .. i]
        
        if item_id > 0 or creature_id > 0 or spell_id > 0 then
            local obj = {index = i, text = text or ""}
            if creature_id > 0 then
                obj.type = "KILL"
                obj.target_id = creature_id
                obj.count = creature_count > 0 and creature_count or 1
            elseif item_id > 0 then
                obj.type = "COLLECT"
                obj.item_id = item_id
                obj.count = item_count > 0 and item_count or 1
            elseif spell_id > 0 then
                obj.type = "CAST"
                obj.spell_id = spell_id
                obj.count = 1
            end
            objectives[#objectives + 1] = obj
        end
    end
    return objectives
end

---Parse rewards from quest data
function QuestGraph:_parse_rewards(qdata)
    local rewards = {xp = 0, money = 0, choices = {}, fixed = {}}
    rewards.xp = tonumber(qdata.rew_xp) or 0
    rewards.money = tonumber(qdata.rew_money_max_level) or tonumber(qdata.rew_or_req_money) or 0
    
    for i = 1, 6 do
        local item_id = tonumber(qdata["rew_choice_item_id" .. i]) or 0
        local item_count = tonumber(qdata["rew_choice_item_count" .. i]) or 0
        if item_id > 0 then
            rewards.choices[#rewards.choices + 1] = {
                item_id = item_id,
                count = item_count > 0 and item_count or 1,
                index = i,
            }
        end
    end
    
    for i = 1, 4 do
        local item_id = tonumber(qdata["rew_item_id" .. i]) or 0
        local item_count = tonumber(qdata["rew_item_count" .. i]) or 0
        if item_id > 0 then
            rewards.fixed[#rewards.fixed + 1] = {
                item_id = item_id,
                count = item_count > 0 and item_count or 1,
            }
        end
    end
    
    return rewards
end

---Get NPC data for quest relation
function QuestGraph:_get_npc(quest_id, relation)
    local npcs = self._client:fetch_quest_npcs(quest_id, relation)
    if npcs and #npcs > 0 then
        local npc = npcs[1]
        return {
            id = npc.npc_id,
            name = npc.name,
            x = npc.x,
            y = npc.y,
            z = npc.z,
            map_id = npc.map_id,
        }
    end
    return nil
end

---Build edges for a node
function QuestGraph:_build_edges(node)
    local qid = node.id
    self.edges[qid] = {
        requires = {},
        follows = {},
        continues = {},
        breadcrumbs = {},
        excludes = {},
    }
    
    if node.prev_quest_id > 0 then
        self.edges[qid].requires[#self.edges[qid].requires + 1] = node.prev_quest_id
    end
    if node.next_quest_id > 0 then
        self.edges[qid].follows[#self.edges[qid].follows + 1] = node.next_quest_id
    end
    if node.next_in_chain > 0 then
        self.edges[qid].continues[#self.edges[qid].continues + 1] = node.next_in_chain
    end
    if node.breadcrumb_for > 0 then
        self.edges[qid].breadcrumbs[#self.edges[qid].breadcrumbs + 1] = node.breadcrumb_for
    end
    if node.exclusive_group > 0 then
        for other_id, other_node in pairs(self.nodes) do
            if other_node.exclusive_group == node.exclusive_group and other_id ~= qid then
                self.edges[qid].excludes[#self.edges[qid].excludes + 1] = other_id
            end
        end
    end
end

---Filter available quests based on completion, race, class, level
---Uses two-pass approach to avoid non-determinism from pairs() iteration order
function QuestGraph:_filter_available(faction)
    local player_level = self._blackboard:get("player.level", 1)
    local player_class = self._blackboard:get("player.class_name", "WARRIOR")
    local player_race_id = self._blackboard:get("player.race_id", 0)
    
    -- PASS 1: Evaluate level/race/class limits and completion
    -- (No dependency on other quests' availability)
    for qid, node in pairs(self.nodes) do
        local available = true
        
        if self:is_completed(qid) then
            available = false
        end
        
        if available and node.min_level > 0 and player_level < node.min_level then
            available = false
        end
        if available and node.max_level > 0 and player_level > node.max_level then
            available = false
        end
        
        if available and node.required_races > 0 then
            available = self:_faction_matches(node.required_races, faction)
        end
        
        if available and node.required_classes > 0 then
            available = self:_class_matches(node.required_classes)
        end
        
        -- Store preliminary availability (will be refined in pass 2)
        self.available[qid] = available
    end
    
    -- PASS 2: Resolve dependency chains iteratively
    -- Repeat until no changes (handles any order dependencies)
    local changed = true
    while changed do
        changed = false
        for qid, node in pairs(self.nodes) do
            if self.available[qid] then
                for _, req_id in ipairs(self.edges[qid].requires) do
                    -- Check both completed AND available (in case prerequisite was marked false)
                    if self:is_completed(req_id) or self.available[req_id] then
                        -- Prerequisite satisfied, keep available
                    else
                        self.available[qid] = false
                        changed = true
                        break
                    end
                end
            end
        end
    end
end

---Convert zone ID to name
function QuestGraph:_zone_id_to_name(zone_id)
    local zones = {
        [0] = "Eastern Kingdoms", [1] = "Kalimdor",
    }
    return zones[zone_id] or "Unknown"
end

---Check if zone is a dungeon
function QuestGraph:_is_dungeon_zone(zone_id)
    local dungeon_zones = {
        [48] = true, [90] = true, [129] = true, [189] = true, [209] = true,
        [229] = true, [269] = true, [289] = true, [309] = true, [329] = true,
        [349] = true, [369] = true, [389] = true, [409] = true, [429] = true,
        [449] = true, [469] = true, [489] = true, [509] = true, [529] = true,
        [531] = true, [533] = true,
    }
    return dungeon_zones[zone_id] or false
end

---Count total nodes in the graph
function QuestGraph:count_nodes()
    local n = 0
    for _ in pairs(self.nodes) do n = n + 1 end
    return n
end

---Get all available quest nodes
function QuestGraph:get_available_quests()
    local result = {}
    for qid, node in pairs(self.nodes) do
        if self.available[qid] then
            result[#result + 1] = node
        end
    end
    return result
end

---Get full chain for a quest (backwards and forwards)
function QuestGraph:get_chain(quest_id)
    local backwards = {}
    local forwards = {}
    
    local current = quest_id
    while current > 0 do
        local node = self.nodes[current]
        if not node then break end
        backwards[#backwards + 1] = node
        current = node.prev_quest_id
    end
    
    current = quest_id
    while current > 0 do
        local node = self.nodes[current]
        if not node then break end
        forwards[#forwards + 1] = node
        current = node.next_in_chain
    end
    
    return {backwards = backwards, forwards = forwards}
end

---Get all quests that share objectives (spatial overlap)
function QuestGraph:get_overlapping_quests(quest_id)
    local node = self.nodes[quest_id]
    if not node then return {} end
    
    local overlapping = {}
    local target_ids = {}
    
    for _, obj in ipairs(node.objectives) do
        if obj.target_id then target_ids[obj.target_id] = true end
        if obj.item_id then target_ids[obj.item_id] = true end
    end
    
    for other_id, other_node in pairs(self.nodes) do
        if other_id ~= quest_id and self.available[other_id] then
            for _, obj in ipairs(other_node.objectives) do
                if target_ids[obj.target_id] or target_ids[obj.item_id] then
                    overlapping[#overlapping + 1] = other_node
                    break
                end
            end
        end
    end
    
    return overlapping
end

---Check if quest is blocked by exclusive group
function QuestGraph:is_exclusive_blocked(quest_id)
    local node = self.nodes[quest_id]
    if not node or node.exclusive_group == 0 then return false, nil end
    
    for other_id, available in pairs(self.available) do
        if available and other_id ~= quest_id then
            local other = self.nodes[other_id]
            if other and other.exclusive_group == node.exclusive_group then
                return true, other_id
            end
        end
    end
    return false, nil
end

return QuestGraph