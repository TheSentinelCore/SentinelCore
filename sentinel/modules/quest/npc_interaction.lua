local NPCInteraction = {}
NPCInteraction.__index = NPCInteraction

local function call(fn, ...)
    if not fn then return false end
    local ok, result = pcall(fn, ...)
    return ok and result or false
end

---Create new NPCInteraction
---@param blackboard table
---@return table
function NPCInteraction.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _queue = {},
        _current = 1,
        _state = "IDLE",
        _gossip_opened = false,
        _retry_count = 0,
        _max_retries = 3,
    }, NPCInteraction)
end

---Build service queue for an NPC
---@param npc_id integer
---@param blackboard table
---@param quest_engine table
---@return table[] services
function NPCInteraction.build_service_queue(npc_id, blackboard, quest_engine)
    local queue = {}
    
    -- 1. TURNIN: All completable quests at this NPC
    local tracker = blackboard:get("module.quest.tracker")
    if tracker then
        local active = tracker:all()
        for _, quest in pairs(active) do
            if quest.is_complete and quest.turnin_npc == npc_id then
                local choice = 1 -- Will be overridden by RewardSelector
                queue[#queue + 1] = {
                    type = "TURNIN",
                    quest_id = quest.quest_id,
                    reward_choice = choice,
                }
            end
        end
    end
    
    -- 2. ACCEPT: All available quests at this NPC (filtered)
    local engine = blackboard:get("module.quest.engine")
    if engine and engine.get_available_quests then
        local available = engine:get_available_quests()
        for _, quest in ipairs(available) do
            if quest.start_npc and quest.start_npc.id == npc_id then
                local rule_engine = blackboard:get("module.quest.rule_engine")
                local profile = blackboard:get("module.quest.current_profile")
                if not rule_engine or not profile or rule_engine.evaluate(profile, quest, blackboard) then
                    queue[#queue + 1] = {
                        type = "ACCEPT",
                        quest_id = quest.quest_id,
                    }
                end
            end
        end
    end
    
    -- 3. TRAIN: Missing spells at trainer
    if NPCInteraction._is_trainer(npc_id) then
        local missing = NPCInteraction._get_missing_spells(npc_id, blackboard)
        for _, spell_id in ipairs(missing) do
            queue[#queue + 1] = {
                type = "TRAIN",
                spell_id = spell_id,
            }
        end
    end
    
    -- 4. VENDOR/REPAIR: Delegate to VendorStateMachine
    if NPCInteraction._is_vendor(npc_id) then
        queue[#queue + 1] = {
            type = "VENDOR",
            npc_id = npc_id,
            delegate = true,
        }
    end
    
    return queue
end

---Execute the service queue
---@return string "SUCCESS" | "FAILURE" | "RUNNING"
function NPCInteraction:execute()
    if #self._queue == 0 then
        return "SUCCESS"
    end
    
    local svc = self._queue[self._current]
    if not svc then
        return "SUCCESS"
    end
    
    local result
    if svc.type == "TURNIN" then
        result = self:_turn_in(svc.quest_id, svc.reward_choice)
    elseif svc.type == "ACCEPT" then
        result = self:_accept_quest(svc.quest_id)
    elseif svc.type == "TRAIN" then
        result = self:_train_spell(svc.spell_id)
    elseif svc.type == "VENDOR" then
        result = self:_vendor_repair(svc.npc_id)
    else
        result = "SUCCESS"
    end
    
    if result == "SUCCESS" then
        self._current = self._current + 1
        self._retry_count = 0
        return "RUNNING" -- Continue to next service
    elseif result == "FAILURE" then
        self._retry_count = self._retry_count + 1
        if self._retry_count >= self._max_retries then
            self._current = self._current + 1 -- Skip failed service
            self._retry_count = 0
            return "RUNNING"
        end
        return "RUNNING" -- Retry
    else
        return "RUNNING" -- Still in progress
    end
end

---Turn in quest and select reward
---@param quest_id integer
---@param reward_choice integer
---@return string
function NPCInteraction:_turn_in(quest_id, reward_choice)
    -- Ensure gossip frame is open
    if not self:_ensure_gossip_open(quest_id) then
        return "FAILURE"
    end
    
    -- Select active quest
    if not call(core.quests.select_gossip_active_quest, quest_id) then
        return "FAILURE"
    end
    
    -- Complete quest
    if not call(core.quests.complete_quest) then
        return "FAILURE"
    end
    
    -- Select reward
    if reward_choice and reward_choice > 0 then
        if not call(core.quests.get_quest_reward, reward_choice) then
            return "FAILURE"
        end
    end
    
    return "SUCCESS"
end

---Accept available quest
---@param quest_id integer
---@return string
function NPCInteraction:_accept_quest(quest_id)
    if not self:_ensure_gossip_open(quest_id) then
        return "FAILURE"
    end
    
    if not call(core.quests.select_gossip_available_quest, quest_id) then
        return "FAILURE"
    end
    
    if not call(core.quests.accept_quest) then
        return "FAILURE"
    end
    
    return "SUCCESS"
end

---Buy trainer spell
---@param spell_id integer
---@return string
function NPCInteraction:_train_spell(spell_id)
    if not core.quests.get_num_trainer_services then return "SUCCESS" end
    
    local num = call(core.quests.get_num_trainer_services)
    if not num then return "SUCCESS" end
    
    for i = 1, num do
        local info = call(core.quests.get_trainer_service_info, i)
        if info and info.spell_id == spell_id then
            local cost = call(core.quests.get_trainer_service_cost, i)
            local gold = call(core.inventory.get_gold) or 0
            if gold >= (cost or 0) then
                call(core.quests.buy_trainer_service, i)
                return "SUCCESS"
            end
        end
    end
    
    return "SUCCESS" -- Skip if can't afford or not found
end

---Vendor/Repair delegate
---@param npc_id integer
---@return string
function NPCInteraction:_vendor_repair(npc_id)
    -- Delegate to existing VendorStateMachine
    local vendor_sm = self._blackboard:get("module.grind.vendor_state_machine")
    if vendor_sm then
        vendor_sm:start(npc_id)
        -- Wait for completion
        if vendor_sm:is_running() then
            return "RUNNING"
        end
        return "SUCCESS"
    end
    return "SUCCESS"
end

---Ensure gossip frame is open for NPC
---@param npc_id integer
---@return boolean
function NPCInteraction:_ensure_gossip_open(npc_id)
    if call(core.quests.is_gossip_frame_shown) then
        return true
    end
    
    -- Try to interact with NPC
    local om = core and core.object_manager
    if om then
        local npcs = om.get_objects_by_type("unit") or {}
        for _, npc in ipairs(npcs) do
            local ok, id = pcall(npc.get_entry, npc)
            if ok and id == npc_id then
                local interact = call(npc.interact, npc)
                if interact then
                    -- Wait for gossip frame
                    local start = self._blackboard:get("system.now_ms", 0)
                    while not call(core.quests.is_gossip_frame_shown) do
                        if self._blackboard:get("system.now_ms", 0) - start > 2000 then
                            return false
                        end
                    end
                    return true
                end
            end
        end
    end
    
    return false
end

---Check if NPC is trainer
---@param npc_id integer
---@return boolean
function NPCInteraction._is_trainer(npc_id)
    -- Would query Mangos DB via QueryClient
    -- For now, check NPCFlags if available
    return false
end

---Check if NPC is vendor
---@param npc_id integer
---@return boolean
function NPCInteraction._is_vendor(npc_id)
    return false
end

---Get missing trainer spells
---@param npc_id integer
---@param blackboard table
---@return integer[]
function NPCInteraction._get_missing_spells(npc_id, blackboard)
    -- Would query trainer spells from DB and compare to known spells
    return {}
end

---Set queue for this interaction
---@param queue table[]
function NPCInteraction:set_queue(queue)
    self._queue = queue
    self._current = 1
    self._state = "RUNNING"
end

---Get current state
---@return string
function NPCInteraction:get_state()
    return self._state
end

return NPCInteraction