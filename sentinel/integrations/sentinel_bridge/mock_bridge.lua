-- sentinel/integrations/sentinel_bridge/mock_bridge.lua
-- Mock Bridge - In-memory implementation for CI/testing - ADR 009 §11

local BridgeError = require("integrations/sentinel_bridge/bridge_error")

local MockBridge = {}
MockBridge.__index = MockBridge

---Create a new MockBridge
---@param event_bus table SentinelCore event bus
---@return table MockBridge instance
function MockBridge:new(event_bus)
    local o = setmetatable({}, MockBridge)
    o._event_bus = event_bus
    o._quest_log = {}
    o._completed_quests = {}
    o._player_position = { x = 0, y = 0, z = 0 }
    o._current_target = nil
    o._units = {}
    o._game_objects = {}
    o._subscriptions = {}
    o._gossip_options = {}
    o._trainer_services = {}
    o._scripted_responses = {}
    o._scripted_responses.accept_quest = {}
    o._scripted_responses.turn_in_quest = {}
    o._scripted_responses.objective_status = {}
    return o
end

---Create mock quest client instance
---@return table
function MockBridge:_create_quest_client()
    local quest_client = { _parent = self }

    function quest_client:accept_quest(npc, quest_id)
        if not quest_id then
            return false, BridgeError.format(BridgeError.quest_not_found(quest_id))
        end

        local script = table.remove(self._parent._scripted_responses.accept_quest)
        if script then
            if script.success then
                self._parent._quest_log[quest_id] = {
                    quest_id = quest_id,
                    title = script.title or "Mock Quest",
                    level = script.level or 1,
                    is_complete = false,
                }
                if self._parent._event_bus then
                    self._parent._event_bus:publish("quest_accepted", { quest_id = quest_id })
                end
                return true, nil
            else
                return false, script.error or "mock error"
            end
        end

        self._parent._quest_log[quest_id] = {
            quest_id = quest_id,
            title = "Mock Quest " .. quest_id,
            level = 1,
            is_complete = false,
        }
        if self._parent._event_bus and self._parent._event_bus.publish then
            self._parent._event_bus:publish("quest_accepted", { quest_id = quest_id })
        end
        return true, nil
    end

    function quest_client:turn_in_quest(npc, quest_id, reward_choice)
        local script = table.remove(self._parent._scripted_responses.turn_in_quest)
        if script then
            if script.success then
                if self._parent._quest_log[quest_id] then
                    self._parent._quest_log[quest_id].is_complete = true
                    self._parent._completed_quests[quest_id] = true
                end
                if self._parent._event_bus then
                    self._parent._event_bus:publish("quest_completed", { quest_id = quest_id })
                end
                return true, nil
            else
                return false, script.error or "mock error"
            end
        end

        if self._parent._quest_log[quest_id] then
            self._parent._quest_log[quest_id].is_complete = true
            self._parent._completed_quests[quest_id] = true
        end
        if self._parent._event_bus and self._parent._event_bus.publish then
            self._parent._event_bus:publish("quest_completed", { quest_id = quest_id })
        end
        return true, nil
    end

    function quest_client:quest_log_entry(quest_id)
        return self._parent._quest_log[quest_id]
    end

    function quest_client:objective_status(quest_id)
        local script = self._parent._scripted_responses.objective_status
        local objectives = {}

        if script and script[quest_id] then
            for _, obj in ipairs(script[quest_id] or {}) do
                table.insert(objectives, {
                    text = obj.text or "Objective",
                    fulfilled = obj.fulfilled,
                    required = obj.required,
                })
            end
        end

        return objectives
    end

    function quest_client:gossip_options(npc)
        local npc_guid = npc and npc.guid
        if not npc_guid and npc and npc.get_guid then
            npc_guid = npc:get_guid()
        end
        return self._parent._gossip_options[npc_guid] or {}
    end

    function quest_client:select_gossip(npc, option)
        local option_id = type(option) == "table" and option.id or option
        return true, nil
    end

    function quest_client:trainer_interact(npc)
        local npc_guid = npc and npc.guid
        if not npc_guid and npc and npc.get_guid then
            npc_guid = npc:get_guid()
        end
        local services = self._parent._trainer_services[npc_guid] or {}
        return { services = services }
    end

    function quest_client:is_on_quest(quest_id)
        return self._parent._quest_log[quest_id] ~= nil
    end

    function quest_client:is_quest_completed(quest_id)
        return self._parent._completed_quests[quest_id] == true or
               (self._parent._quest_log[quest_id] and self._parent._quest_log[quest_id].is_complete)
    end

    function quest_client:poll_quest_log()
        return { accepted = {}, completed = {}, abandoned = {} }
    end

    function quest_client:get_completed_quest_ids()
        local ids = {}
        for qid, _ in pairs(self._parent._completed_quests) do
            table.insert(ids, qid)
        end
        return ids
    end

    return quest_client
end

---Create mock addons client instance
---@return table
function MockBridge:_create_addons_client()
    local addons_client = { _parent = self }

    function addons_client:subscribe(event, handler)
        local id = tostring(event) .. "_" .. tostring(os.time())
        self._parent._subscriptions[id] = { event = event, handler = handler }
        return id
    end

    function addons_client:unsubscribe(subscription_id)
        self._parent._subscriptions[subscription_id] = nil
    end

    function addons_client:current_target()
        return self._parent._current_target
    end

    function addons_client:player_position()
        return {
            x = self._parent._player_position.x,
            y = self._parent._player_position.y,
            z = self._parent._player_position.z,
        }
    end

    function addons_client:nearby_units(radius)
        local units = {}
        for _, unit in pairs(self._parent._units) do
            table.insert(units, unit)
        end
        return units
    end

    function addons_client:nearby_game_objects(radius)
        local objects = {}
        for _, obj in pairs(self._parent._game_objects) do
            table.insert(objects, obj)
        end
        return objects
    end

    function addons_client:unit_info(unit)
        if not unit then
            return {
                guid = "",
                npc_id = 0,
                name = "",
                level = 0,
                position = { x = 0, y = 0, z = 0 },
                is_dead = false,
                is_vendor = false,
                is_quest_giver = false,
            }
        end

        local guid = unit.guid or (unit.get_guid and unit:get_guid()) or ""
        local mock_unit = self._parent._units[guid]

        if mock_unit then
            return {
                guid = guid,
                npc_id = mock_unit.npc_id or 0,
                name = mock_unit.name or "MockUnit",
                level = mock_unit.level or 1,
                position = mock_unit.position or { x = 0, y = 0, z = 0 },
                is_dead = mock_unit.is_dead or false,
                is_vendor = mock_unit.is_vendor or false,
                is_quest_giver = mock_unit.is_quest_giver or false,
            }
        end

        return {
            guid = guid,
            npc_id = unit.npc_id or 0,
            name = unit.name or "Unknown",
            level = unit.level or 1,
            position = unit.position or { x = 0, y = 0, z = 0 },
            is_dead = unit.is_dead or false,
            is_vendor = unit.is_vendor or false,
            is_quest_giver = unit.is_quest_giver or false,
        }
    end

    function addons_client:poll_quest_log()
        local quests = {}
        for qid, entry in pairs(self._parent._quest_log) do
            quests[qid] = entry.is_complete == true
        end
        return quests
    end

    function addons_client:get_completed_quest_ids()
        local ids = {}
        for qid, _ in pairs(self._parent._completed_quests) do
            table.insert(ids, qid)
        end
        return ids
    end

    return addons_client
end

---Add scripted response for testing
---@param operation string "accept_quest", "turn_in_quest", etc.
---@param response table Response configuration
function MockBridge:add_scripted_response(operation, response)
    self._scripted_responses[operation] = self._scripted_responses[operation] or {}
    if operation == "accept_quest" or operation == "turn_in_quest" then
        table.insert(self._scripted_responses[operation], response)
    else
        self._scripted_responses[operation] = response
    end
end

---Set mock quest log state
---@param quest_id number Quest ID
---@param entry table QuestLogEntry
function MockBridge:set_quest_log_entry(quest_id, entry)
    self._quest_log[quest_id] = entry
end

---Add gossip option for NPC
---@param npc_guid string NPC GUID
---@param option table GossipOption
function MockBridge:add_gossip_option(npc_guid, option)
    self._gossip_options[npc_guid] = self._gossip_options[npc_guid] or {}
    table.insert(self._gossip_options[npc_guid], option)
end

---Add trainer service for NPC
---@param npc_guid string NPC GUID
---@param service table TrainerService
function MockBridge:add_trainer_service(npc_guid, service)
    self._trainer_services[npc_guid] = self._trainer_services[npc_guid] or {}
    table.insert(self._trainer_services[npc_guid], service)
end

---Set player position
---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
function MockBridge:set_position(x, y, z)
    self._player_position = { x = x, y = y, z = z }
end

---Add mock unit
---@param guid string Unit GUID
---@param unit table Unit data
function MockBridge:add_unit(guid, unit)
    self._units[guid] = unit
end

---Add mock game object
---@param guid string Object GUID
---@param obj table Object data
function MockBridge:add_game_object(guid, obj)
    self._game_objects[guid] = obj
end

---Get quest client instance
---@return table QuestClient implementation
function MockBridge:get_quest_client()
    return self:_create_quest_client()
end

---Get addons client instance
---@return table AddonsClient implementation
function MockBridge:get_addons_client()
    return self:_create_addons_client()
end

return MockBridge