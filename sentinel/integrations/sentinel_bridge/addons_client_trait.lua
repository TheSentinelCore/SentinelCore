-- sentinel/integrations/sentinel_bridge/addons_client_trait.lua
-- AddonsClient trait interface - ADR 009 §5
-- Defines the contract for unit queries, position, and event subscriptions

local AddonsClientTrait = {}

---Unit handle structure (wraps game object GUID)
---@class UnitHandle
---@field guid string Unit GUID
---@field object table Original game object reference

---Waypoint structure
---@class Waypoint
---@field x number X coordinate
---@field y number Y coordinate
---@field z number Z coordinate
AddonsClientTrait.Waypoint = {
    x = 0,
    y = 0,
    z = 0,
}

---Unit info structure
---@class UnitInfo
---@field guid string Unit GUID
---@field npc_id number NPC entry ID (0 if player/other)
---@field name string Unit name
---@field level number Unit level
---@field position table Waypoint position
---@field is_dead boolean Whether unit is dead
---@field is_vendor boolean Whether unit is a vendor
---@field is_quest_giver boolean Whether unit is a quest giver
---@field is_trainer boolean Whether unit is a trainer
AddonsClientTrait.UnitInfo = {
    guid = "",
    npc_id = 0,
    name = "",
    level = 0,
    position = { x = 0, y = 0, z = 0 },
    is_dead = false,
    is_vendor = false,
    is_quest_giver = false,
    is_trainer = false,
}

---Subscribe to game events
---@param event string Event name (e.g., "QUEST_LOG_UPDATE", "BAG_UPDATE", "PLAYER_MOVED")
---@param handler function Handler function receiving event data
---@return string subscription_id
function AddonsClientTrait.subscribe(event, handler)
    error("AddonsClientTrait.subscribe: must be implemented by concrete class")
end

---Unsubscribe from a game event
---@param subscription_id string The subscription ID to remove
function AddonsClientTrait.unsubscribe(subscription_id)
    error("AddonsClientTrait.unsubscribe: must be implemented by concrete class")
end

---Get the currently targeted unit
---@return table|nil unit UnitHandle or nil
function AddonsClientTrait.current_target()
    error("AddonsClientTrait.current_target: must be implemented by concrete class")
end

---Get the local player position
---@return table position Waypoint
function AddonsClientTrait.player_position()
    error("AddonsClientTrait.player_position: must be implemented by concrete class")
end

---Get nearby units within radius
---@param radius number Search radius in yards
---@return table units Array of UnitHandle
function AddonsClientTrait.nearby_units(radius)
    error("AddonsClientTrait.nearby_units: must be implemented by concrete class")
end

---Get nearby game objects within radius
---@param radius number Search radius in yards
---@return table objects Array of game object handles
function AddonsClientTrait.nearby_game_objects(radius)
    error("AddonsClientTrait.nearby_game_objects: must be implemented by concrete class")
end

---Get detailed info about a unit
---@param unit table UnitHandle or game object
---@return table info UnitInfo
function AddonsClientTrait.unit_info(unit)
    error("AddonsClientTrait.unit_info: must be implemented by concrete class")
end

---Poll for quest log state (for event bridge diffing)
---@return table quest_log { [quest_id] = is_complete }
function AddonsClientTrait.poll_quest_log()
    error("AddonsClientTrait.poll_quest_log: must be implemented by concrete class")
end

---Get all completed quest IDs
---@return table quest_ids Array of completed quest IDs
function AddonsClientTrait.get_completed_quest_ids()
    error("AddonsClientTrait.get_completed_quest_ids: must be implemented by concrete class")
end

return AddonsClientTrait