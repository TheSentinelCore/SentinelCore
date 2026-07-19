-- sentinel/integrations/sentinel_bridge/quest_client_trait.lua
-- QuestClient trait interface - ADR 009 §4
-- Defines the contract for quest interaction operations

local QuestClientTrait = {}

---Quest log entry structure
---@class QuestLogEntry
---@field quest_id number Quest ID
---@field title string Quest title
---@field level number Quest level
---@field is_complete boolean Whether quest is complete
QuestClientTrait.QuestLogEntry = {
    quest_id = 0,
    title = "",
    level = 0,
    is_complete = false,
}

---Objective status structure
---@class ObjectiveStatus
---@field text string Objective text description
---@field fulfilled number? Current progress count (nil if parseable)
---@field required number? Required count (nil if parseable)
QuestClientTrait.ObjectiveStatus = {
    text = "",
    fulfilled = nil,
    required = nil,
}

---Gossip option structure
---@class GossipOption
---@field id number Option ID
---@field text string Option text
---@field icon number Icon ID
QuestClientTrait.GossipOption = {
    id = 0,
    text = "",
    icon = 0,
}

---Trainer menu structure
---@class TrainerMenu
---@field services table Array of trainer service info
QuestClientTrait.TrainerMenu = {
    services = {},
}

---Trainer service structure
---@class TrainerService
---@field index number Service index
---@field name string Spell/name
---@field spell_id number Spell ID
---@field cost number Cost in copper
QuestClientTrait.TrainerService = {
    index = 0,
    name = "",
    spell_id = 0,
    cost = 0,
}

---Accept a quest from an NPC
---@param npc table NpcHandle (game_object with get_guid)
---@param quest_id number Quest ID to accept
---@return boolean success, string? error
function QuestClientTrait.accept_quest(npc, quest_id)
    error("QuestClientTrait.accept_quest: must be implemented by concrete class")
end

---Turn in a quest to an NPC
---@param npc table NpcHandle (game_object with get_guid)
---@param quest_id number Quest ID to turn in
---@param reward_choice number? Optional reward choice index
---@return boolean success, string? error
function QuestClientTrait.turn_in_quest(npc, quest_id, reward_choice)
    error("QuestClientTrait.turn_in_quest: must be implemented by concrete class")
end

---Get quest log entry for a specific quest
---@param quest_id number Quest ID to look up
---@return table? quest_log_entry QuestLogEntry or nil if not found
function QuestClientTrait.quest_log_entry(quest_id)
    error("QuestClientTrait.quest_log_entry: must be implemented by concrete class")
end

---Get objective status for a quest
---@param quest_id number Quest ID
---@return table objectives Array of ObjectiveStatus
function QuestClientTrait.objective_status(quest_id)
    error("QuestClientTrait.objective_status: must be implemented by concrete class")
end

---Get gossip options from an NPC
---@param npc table NpcHandle (game_object with get_guid)
---@return table options Array of GossipOption
function QuestClientTrait.gossip_options(npc)
    error("QuestClientTrait.gossip_options: must be implemented by concrete class")
end

---Select a gossip option
---@param npc table NpcHandle (game_object with get_guid)
---@param option table GossipOption or option_id number
---@return boolean success, string? error
function QuestClientTrait.select_gossip(npc, option)
    error("QuestClientTrait.select_gossip: must be implemented by concrete class")
end

---Interact with trainer NPC and get menu
---@param npc table NpcHandle (game_object with get_guid)
---@return table? trainer_menu TrainerMenu or nil on error
function QuestClientTrait.trainer_interact(npc)
    error("QuestClientTrait.trainer_interact: must be implemented by concrete class")
end

---Check if quest is in log
---@param quest_id number Quest ID to check
---@return boolean in_log
function QuestClientTrait.is_on_quest(quest_id)
    error("QuestClientTrait.is_on_quest: must be implemented by concrete class")
end

---Check if quest was completed (distinct from just flagged complete)
---@param quest_id number Quest ID to check
---@return boolean completed
function QuestClientTrait.is_quest_completed(quest_id)
    error("QuestClientTrait.is_quest_completed: must be implemented by concrete class")
end

return QuestClientTrait