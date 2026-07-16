local QueryClient = require("modules/quest/query_client")

local QuestGraph = {}
QuestGraph.__index = QuestGraph

local CACHE_TTL_S = 3600 -- 1 hour for graph

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

---Build graph from database for a zone/level range
---@param zone string|nil Zone name (e.g., "Westfall")
---@param level_range table|nil {min, max}
---@param faction string|nil "Alliance" | "Horde" | "Both"
---@return QuestGraph self
function QuestGraph:build_from_db(zone, level_range, faction)
    local min_level = level_range and level_range.min or 1
    local max_level = level_range and level_range.max or 80
    
    -- Fetch all quests in level range (we'll filter by zone after)
    -- QueryClient doesn't have a "list all quests" endpoint, so we need to query by known IDs
    -- For now, we'll fetch quests from a pre-known list or query the DB directly
    
    -- Since we don't have a list endpoint, we'll use a different approach:
    -- Query all quest templates from the DB via a new endpoint, or use Questie's data
    -- For this implementation, we'll build from Questie's known quests + DB queries
    
    self.nodes = {}
    self.edges = {}
    self.available = {}
    self.completed = {}
    
    -- Load completed quests from API
    self:_load_completed_quests()
    
    -- Get all quest IDs from Questie for the zone/level
    local quest_ids = self:_get_quest_ids_for_zone(zone, min_level, max_level, faction)
    
    -- Fetch each quest and build nodes
    for _, quest_id in ipairs(quest_ids) do
        local node = self:_build_node(quest_id)
        if node then
            self.nodes[quest_id] = node
            self:_build_edges(node)
        end
    end
    
    -- Filter available
    self:_filter_available(faction)
    
    return self
end

---Load completed quests from Sylvannas API
function QuestGraph:_load_completed_quests()
    -- core.quests.is_quest_flagged_completed(quest_id) - but we don't know all IDs
    -- Instead, we'll check on-demand when filtering
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
    
    -- Fallback: query a range of known quest IDs (expensive, but works)
    -- In production, we'd want a /api/v1/quests?zone=X&level_min=Y&level_max=Z endpoint
    return {}
end

---Convert zone name to map ID
---@param zone_name string
---@return integer
function QuestGraph:_zone_name_to_id(zone_name)
    local zone_map = {
        ["Westfall"] = 0,
        ["Redridge Mountains"] = 0,
        ["Duskwood"] = 0,
        ["Loch Modan"] = 0,
        ["Darkshore"] = 1,
        ["Elwynn Forest"] = 0,
        ["Tirisfal Glades"] = 0,
        ["Silverpine Forest"] = 0,
        ["The Barrens"] = 1,
        ["Stonetalon Mountains"] = 1,
        ["Ashenvale"] = 1,
        -- Add more as needed
    }
    return zone_map[zone_name] or 0
end

---Check if quest faction matches player
---@param required_races integer bitmask
---@param faction string
---@return boolean
function QuestGraph:_faction_matches(required_races, faction)
    if not faction or faction == "Both" then return true end
    if required_races == 0 then return true end
    
    -- Race bitmasks: Alliance=1101 (Human=1, Dwarf=4, NightElf=8, Gnome=16, Draenei=128)
    -- Horde=690 (Orc=2, Undead=8, Tauren=32, Troll=128, BloodElf=512)
    -- Simplified: check if any alliance/horde race bit is set
    local alliance_mask = 1 + 4 + 8 + 16 + 128 -- 157
    local horde_mask = 2 + 8 + 32 + 128 + 512 -- 682 (actually: 2+8+32+128+512=682)
    
    if faction == "Alliance" then
        return bit.band(required_races, alliance_mask) ~= 0
    elseif faction == "Horde" then
        return bit.band(required_races, horde_mask) ~= 0
    end
    return true
end

---Check if quest class matches player
---@param required_classes integer bitmask
---@return boolean
function QuestGraph:_class_matches(required_classes)
    if required_classes == 0 then return true end
    -- Would need player class from blackboard
    -- For now, accept all
    return true
end

---Build a QuestNode from raw quest data
---@param quest_id integer
---@return QuestNode|nil
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
---@param qdata table
---@return table[]
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
            local obj = {
                index = i,
                text = text or "",
            }
            
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
---@param qdata table
---@return table
function QuestGraph:_parse_rewards(qdata)
    local rewards = {
        xp = tonumber(qdata.rew_xp) or 0,
        money = tonumber(qdata.rew_money_max_level) or tonumber(qdata.rew_or_req_money) or 0,
        choices = {},
        fixed = {},
    }
    
    -- Choice rewards (RewChoiceItemId1-6)
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
    
    -- Fixed rewards (RewItemId1-4)
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
---@param quest_id integer
---@param relation string "giver" | "turnin"
---@return table|nil
function QuestGraph:_get_npc(quest_id, relation)
    local npcs = self._client:fetch_quest_npcs(quest_id, relation)
    if npcs and #npcs > 0 then
        local npc = npcs[1] -- Take first match
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
---@param node QuestNode
function QuestGraph:_build_edges(node)
    local qid = node.id
    self.edges[qid] = {
        requires = {},
        follows = {},
        continues = {},
        breadcrumbs = {},
        excludes = {},
    }
    
    -- Prerequisite chain
    if node.prev_quest_id > 0 then
        self.edges[qid].requires[#self.edges[qid].requires + 1] = node.prev_quest_id
    end
    
    -- Follow-up chain
    if node.next_quest_id > 0 then
        self.edges[qid].follows[#self.edges[qid].follows + 1] = node.next_quest_id
    end
    
    -- Chain continuation
    if node.next_in_chain > 0 then
        self.edges[qid].continues[#self.edges[qid].continues + 1] = node.next_in_chain
    end
    
    -- Breadcrumb
    if node.breadcrumb_for > 0 then
        self.edges[qid].breadcrumbs[#self.edges[qid].breadcrumbs + 1] = node.breadcrumb_for
    end
    
    -- Exclusive group
    if node.exclusive_group > 0 then
        -- Find all quests with same exclusive group
        for other_id, other_node in pairs(self.nodes) do
            if other_node.exclusive_group == node.exclusive_group and other_id ~= qid then
                self.edges[qid].excludes[#self.edges[qid].excludes + 1] = other_id
            end
        end
    end
end

---Filter available quests based on completion, race, class, level
---@param faction string
function QuestGraph:_filter_available(faction)
    local player_level = self._blackboard:get("player.level", 1)
    local _, player_class = UnitClass("player")
    local _, player_race = UnitRace("player")
    
    for qid, node in pairs(self.nodes) do
        local available = true
        
        -- Not completed
        if self:is_completed(qid) then
            available = false
        end
        
        -- Level requirements
        if available and node.min_level > 0 and player_level < node.min_level then
            available = false
        end
        if available and node.max_level > 0 and player_level > node.max_level then
            available = false
        end
        
        -- Race requirement
        if available and node.required_races > 0 then
            available = self:_faction_matches(node.required_races, faction)
        end
        
        -- Class requirement
        if available and node.required_classes > 0 then
            available = self:_class_matches(node.required_classes)
        end
        
        -- Prerequisites met
        if available then
            for _, req_id in ipairs(self.edges[qid] and self.edges[qid].requires or {}) do
                if not self:is_completed(req_id) and not self.available[req_id] then
                    available = false
                    break
                end
            end
        end
        
        self.available[qid] = available
    end
end

---Convert zone ID to name
---@param zone_id integer
---@return string
function QuestGraph:_zone_id_to_name(zone_id)
    local zones = {
        [0] = "Eastern Kingdoms",
        [1] = "Kalimdor",
    }
    return zones[zone_id] or "Unknown"
end

---Check if zone is a dungeon
---@param zone_id integer
---@return boolean
function QuestGraph:_is_dungeon_zone(zone_id)
    local dungeon_zones = {
        [48] = true,  -- Ragefire Chasm
        [90] = true,  -- The Deadmines
        [129] = true, -- Razorfen Kraul
        [189] = true, -- Shadowfang Keep
        [209] = true, -- Wailing Caverns
        [229] = true, -- Blackfathom Deeps
        [269] = true, -- Razorfen Downs
        [289] = true, -- Gnomeregan
        [309] = true, -- Scarlet Monastery
        [329] = true, -- Razorfen Downs
        [349] = true, -- Maraudon
        [369] = true, -- Dire Maul
        [389] = true, -- Scholomance
        [409] = true, -- Stratholme
        [429] = true, -- Blackrock Depths
        [449] = true, -- Blackrock Spire
        [469] = true, -- Onyxia's Lair
        [489] = true, -- Molten Core
        [509] = true, -- Zul'Gurub
        [529] = true, -- Ruins of Ahn'Qiraj
        [531] = true, -- Temple of Ahn'Qiraj
        [533] = true, -- Naxxramas
    }
    return dungeon_zones[zone_id] or false
end

---Get all available quest nodes
---@return QuestNode[]
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
---@param quest_id integer
---@return {backwards: QuestNode[], forwards: QuestNode[]}
function QuestGraph:get_chain(quest_id)
    local backwards = {}
    local forwards = {}
    
    -- Walk backwards via prev_quest_id
    local current = quest_id
    while current > 0 do
        local node = self.nodes[current]
        if not node then break end
        backwards[#backwards + 1] = node
        current = node.prev_quest_id
    end
    
    -- Walk forwards via next_in_chain
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
---@param quest_id integer
---@return QuestNode[]
function QuestGraph:get_overlapping_quests(quest_id)
    local node = self.nodes[quest_id]
    if not node then return {} end
    
    local overlapping = {}
    local target_ids = {}
    
    -- Collect all target IDs from this quest's objectives
    for _, obj in ipairs(node.objectives) do
        if obj.target_id then target_ids[obj.target_id] = true end
        if obj.item_id then target_ids[obj.item_id] = true end
    end
    
    -- Find other quests with same targets
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
---@param quest_id integer
---@return boolean, integer|nil
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