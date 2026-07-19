-- sentinel/integrations/sentinel_bridge/quest_bridge.lua
-- Quest interaction bridge to Sylvanas core.quests API
-- Implements QuestClientTrait - ADR 009 §4

local BridgeError = require("integrations/sentinel_bridge/bridge_error")
local QuestClientTrait = require("integrations/sentinel_bridge/quest_client_trait")

local QuestBridge = {}
QuestBridge.__index = QuestBridge

setmetatable(QuestBridge, { __index = QuestClientTrait })

---Create a new QuestBridge
---@param event_bus table SentinelCore event bus
---@return table QuestBridge instance
function QuestBridge:new(event_bus)
    local o = setmetatable({}, QuestBridge)
    o._event_bus = event_bus
    o._target_npc = nil
    o._dialog_open = false
    return o
end

---Accept a quest from an NPC
---@param npc table NpcHandle with get_guid method
---@param quest_id number Quest ID to accept
---@return boolean success, string? error
function QuestBridge:accept_quest(npc, quest_id)
    if not npc or type(npc.get_guid) ~= "function" then
        return false, BridgeError.format(BridgeError.npc_not_found(npc and tostring(npc)))
    end

    local ok = core and core.quests and type(core.quests.accept_quest) == "function"
    if not ok then
        return false, BridgeError.format(BridgeError.api_unavailable())
    end

    self:_interact_npc(npc)

    local success = pcall(core.quests.accept_quest)
    if success then
        if core.quests.get_active_title then
            local active = core.quests.get_active_title(1) or {}
            local active_quest_id = type(active.quest_id) == "number" and active.quest_id or quest_id
            if active_quest_id and self._event_bus then
                self._event_bus:publish("quest_accepted", { quest_id = active_quest_id })
            end
        end
    end

    return success, success and nil or "accept_failed"
end

---Turn in a quest to an NPC
---@param npc table NpcHandle with get_guid method
---@param quest_id number Quest ID to turn in
---@param reward_choice number? Optional reward choice
---@return boolean success, string? error
function QuestBridge:turn_in_quest(npc, quest_id, reward_choice)
    if not npc or type(npc.get_guid) ~= "function" then
        return false, BridgeError.format(BridgeError.npc_not_found(npc and tostring(npc)))
    end

    local ok = core and core.quests and type(core.quests.complete_quest) == "function"
    if not ok then
        return false, BridgeError.format(BridgeError.api_unavailable())
    end

    self:_interact_npc(npc)

    if reward_choice and core.quests.get_quest_reward then
        pcall(core.quests.get_quest_reward, reward_choice)
    end

    local success = pcall(core.quests.complete_quest)
    if success then
        if self._event_bus then
            self._event_bus:publish("quest_completed", { quest_id = quest_id })
        end
    end

    return success, success and nil or "turn_in_failed"
end

---Get quest log entry for a quest
---@param quest_id number Quest ID
---@return table? entry QuestLogEntry or nil
function QuestBridge:quest_log_entry(quest_id)
    if not core or not core.game_ui or not core.quests then
        return nil
    end

    local count = pcall(core.game_ui.get_quest_log_count)
    if type(count) ~= "number" then
        return nil
    end

    for i = 1, math.min(count, 50) do
        local ok, info = pcall(function()
            return core.quests.get_quest_log_title(i)
        end)
        if ok and info and info.quest_id == quest_id and not info.is_header then
            return {
                quest_id = info.quest_id or 0,
                title = info.title or "",
                level = info.level or 0,
                is_complete = info.is_complete == 1,
            }
        end
    end

    return nil
end

---Get objective status for a quest
---@param quest_id number Quest ID
---@return table objectives Array of ObjectiveStatus
function QuestBridge:objective_status(quest_id)
    local objectives = {}

    if not core or not core.quests then
        return objectives
    end

    local count = pcall(core.game_ui.get_quest_log_count)
    if type(count) ~= "number" then
        return objectives
    end

    for i = 1, count do
        local ok, info = pcall(function()
            return core.quests.get_quest_log_title(i)
        end)
        if ok and info and info.quest_id == quest_id then
            local quest_index = i
            local num_obj = pcall(core.quests.get_num_quest_leader_boards, quest_index)
            if type(num_obj) == "number" then
                for j = 1, num_obj do
                    local obj_ok, text = pcall(function()
                        return core.quests.get_quest_log_leader_board(j, quest_index)
                    end)
                    if obj_ok and text then
                        local status = {
                            text = text,
                            fulfilled = nil,
                            required = nil,
                        }
                        local num, total = string.match(text, ":(%d+)/(%d+)$")
                        if num and total then
                            status.fulfilled = tonumber(num)
                            status.required = tonumber(total)
                        end
                        table.insert(objectives, status)
                    end
                end
            end
            break
        end
    end

    return objectives
end

---Get gossip options from an NPC
---@param npc table NpcHandle with get_guid method
---@return table options Array of GossipOption
function QuestBridge:gossip_options(npc)
    if not npc or type(npc.get_guid) ~= "function" then
        return {}
    end

    self:_interact_npc(npc)

    local options = {}

    if core and core.quests and type(core.quests.get_gossip_options) == "function" then
        local ok, result = pcall(core.quests.get_gossip_options)
        if ok and type(result) == "table" then
            options = result
        end
    end

    return options
end

---Select a gossip option
---@param npc table NpcHandle with get_guid method
---@param option table GossipOption or number option ID
---@return boolean success, string? error
function QuestBridge:select_gossip(npc, option)
    if not npc or type(npc.get_guid) ~= "function" then
        return false, BridgeError.format(BridgeError.npc_not_found(npc and tostring(npc)))
    end

    self:_interact_npc(npc)

    local option_id = type(option) == "table" and option.id or option
    if core and core.quests and type(core.quests.select_gossip_option) == "function" then
        local ok = pcall(core.quests.select_gossip_option, option_id)
        return ok, ok and nil or "gossip_select_failed"
    end

    return false, "api_unavailable"
end

---Interact with trainer NPC
---@param npc table NpcHandle with get_guid method
---@return table? trainer_menu TrainerMenu or nil
function QuestBridge:trainer_interact(npc)
    if not npc or type(npc.get_guid) ~= "function" then
        return nil
    end

    self:_interact_npc(npc)

    local services = {}

    if not core or not core.quests then
        return { services = services }
    end

    local count = pcall(core.quests.get_num_trainer_services)
    if type(count) ~= "number" then
        return { services = services }
    end

    for i = 1, math.min(count, 100) do
        local ok, info = pcall(function()
            return core.quests.get_trainer_service_info(i)
        end)
        if ok and info then
            table.insert(services, {
                index = i,
                name = info.name or "",
                spell_id = info.spell_id or 0,
                cost = info.cost or 0,
            })
        end
    end

    return { services = services }
end

-- Legacy methods for backward compatibility

function QuestBridge:accept_active_quest(npc_guid)
    return self:accept_quest({ get_guid = function() return npc_guid end }, nil)
end

function QuestBridge:turn_in_active_quest(quest_id, reward_choice)
    return self:turn_in_quest({ get_guid = function() return "mock" end }, quest_id, reward_choice)
end

function QuestBridge:get_quest_log()
    local quests = {}

    if not core or not core.game_ui or not core.quests then
        return quests
    end

    local count = pcall(core.game_ui.get_quest_log_count)
    if type(count) ~= "number" then
        return quests
    end

    for i = 1, math.min(count, 50) do
        local ok, info = pcall(function()
            return core.quests.get_quest_log_title(i)
        end)
        if ok and info and not info.is_header then
            table.insert(quests, {
                quest_id = info.quest_id or 0,
                title = info.title or "",
                level = info.level or 0,
                is_complete = info.is_complete == 1,
            })
        end
    end

    return quests
end

function QuestBridge:get_gossip_options(npc)
    return self:gossip_options(npc)
end

function QuestBridge:get_trainer_services()
    return (self:trainer_interact({ get_guid = function() return "mock" end }) or {}).services
end

function QuestBridge:buy_trainer_service(index)
    if core and core.quests and type(core.quests.buy_trainer_service) == "function" then
        local ok = pcall(core.quests.buy_trainer_service, index)
        return ok
    end
    return false
end

function QuestBridge:close_dialog()
    if core and core.quests then
        if type(core.quests.close_gossip) == "function" then
            pcall(core.quests.close_gossip)
        elseif type(core.quests.close_quest) == "function" then
            pcall(core.quests.close_quest)
        end
    end
end

---Target and interact with an NPC
---@param npc table NPC to interact with
---@return boolean success, string? error
function QuestBridge:_interact_npc(npc)
    if not npc or type(npc.get_guid) ~= "function" then
        return false, "invalid_npc"
    end

    if core and core.input and type(core.input.set_target) == "function" then
        local ok = pcall(core.input.set_target, npc)
        if not ok then
            return false, "set_target_failed"
        end
    end

    if core and core.input and type(core.input.use_object) == "function" then
        local ok = pcall(core.input.use_object, npc)
        if not ok then
            return false, "interact_failed"
        end
    end

    self._target_npc = npc
    return true, nil
end

return QuestBridge