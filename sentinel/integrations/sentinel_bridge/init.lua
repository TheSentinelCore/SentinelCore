-- sentinel/integrations/sentinel_bridge/init.lua
-- SentinelBridge - Main entry point for Sylvanas API integration
-- Implements trait-based architecture per ADR 009

local QuestBridge = require("integrations/sentinel_bridge/quest_bridge")
local AddonsBridge = require("integrations/sentinel_bridge/addons_bridge")
local RenderBridge = require("integrations/sentinel_bridge/render_bridge")
local EventBridge = require("integrations/sentinel_bridge/event_bridge")
local BridgeError = require("integrations/sentinel_bridge/bridge_error")
local ApiVersion = require("integrations/sentinel_bridge/api_version")

local SentinelBridge = {}
SentinelBridge.__index = SentinelBridge

---Create a new SentinelBridge
---@param blackboard table SentinelCore blackboard
---@param event_bus table SentinelCore event bus
---@return table SentinelBridge instance
function SentinelBridge:new(blackboard, event_bus)
    local o = setmetatable({}, SentinelBridge)
    o._blackboard = blackboard
    o._event_bus = event_bus

    o._quest = QuestBridge:new(event_bus)
    o._addons = AddonsBridge:new(event_bus)
    o._render = RenderBridge:new()

    o._event_bridge = EventBridge.create_translator(event_bus)
    o._addons:set_event_bridge(o._event_bridge)

    o._poll_timer = 0
    return o
end

---Initialize the bridge - register event callbacks
function SentinelBridge:init()
    if not core then
        self._render = RenderBridge.create_headless()
        return
    end

    self._addons:subscribe("PLAYER_STOPPED_MOVING", function()
        self:_check_npc_reached()
    end)

    if core.register_on_update_callback then
        core.register_on_update_callback(function()
            self._poll_timer = self._poll_timer + 1
            if self._poll_timer >= 30 then
                self:_poll_quest_log()
                self._poll_timer = 0
            end
        end)
    end
end

---Poll quest log and publish semantic events via EventBridge
function SentinelBridge:_poll_quest_log()
    if self._event_bridge then
        self._event_bridge:poll_and_publish_quest_log(self._addons)
    end
end

---Accept a quest from an NPC
---@param npc table NPC handle or GUID
---@param quest_id number Quest ID to accept
---@return boolean success, string? error
function SentinelBridge:accept_quest(npc, quest_id)
    if type(npc) == "string" then
        npc = { get_guid = function() return npc end }
    end
    return self._quest:accept_quest(npc, quest_id)
end

---Turn in a quest to an NPC
---@param npc table NPC handle or GUID
---@param quest_id number Quest ID to turn in
---@param reward_choice number? Reward choice index
---@return boolean success, string? error
function SentinelBridge:turn_in_quest(npc, quest_id, reward_choice)
    if type(npc) == "string" then
        npc = { get_guid = function() return npc end }
    end
    return self._quest:turn_in_quest(npc, quest_id, reward_choice)
end

---Check quest log for a quest
---@param quest_id number Quest ID
---@return boolean in_log, boolean is_complete
function SentinelBridge:quest_log_entry(quest_id)
    local entry = self._quest:quest_log_entry(quest_id)
    if entry then
        return true, entry.is_complete
    end
    return false, false
end

---Get objective status
---@param quest_id number Quest ID
---@return table objectives
function SentinelBridge:objective_status(quest_id)
    return self._quest:objective_status(quest_id)
end

---Get gossip options
---@param npc table NPC handle
---@return table options
function SentinelBridge:gossip_options(npc)
    return self._quest:gossip_options(npc)
end

---Select gossip option
---@param npc table NPC handle
---@param option table or number
---@return boolean success, string? error
function SentinelBridge:select_gossip(npc, option)
    return self._quest:select_gossip(npc, option)
end

---Get trainer menu
---@param npc table NPC handle
---@return table? trainer_menu
function SentinelBridge:trainer_interact(npc)
    return self._quest:trainer_interact(npc)
end

---Get current target
---@return table|nil
function SentinelBridge:current_target()
    return self._addons:current_target()
end

---Get player position
---@return table position
function SentinelBridge:player_position()
    return self._addons:player_position()
end

---Get nearby units
---@param radius number
---@return table units
function SentinelBridge:nearby_units(radius)
    return self._addons:nearby_units(radius or 40)
end

---Get nearby game objects
---@param radius number
---@return table objects
function SentinelBridge:nearby_game_objects(radius)
    return self._addons:nearby_game_objects(radius or 40)
end

---Get unit info
---@param unit table Unit handle
---@return table info
function SentinelBridge:unit_info(unit)
    return self._addons:unit_info(unit)
end

---Draw a panel
---@param descriptor table
---@param render_fn function
function SentinelBridge:draw_panel(descriptor, render_fn)
    self._render:register_panel(descriptor, render_fn)
end

---Draw map overlay
---@param elements table
function SentinelBridge:draw_map_overlay(elements)
    self._render:draw_map_overlay(elements)
end

---Tick - update internal state
---@param delta number
function SentinelBridge:tick(delta)
    self._render:draw()
end

---Check if NPC was reached
---@private
function SentinelBridge:_check_npc_reached()
    local active_goals = self._blackboard and self._blackboard.get("nav.active_goals")
    if not active_goals then return end
end

---Shutdown - cleanup
function SentinelBridge:shutdown()
    self._render:set_visible(false)
end

---Static method to create with mock implementations
---@param event_bus table
---@return table bridge
function SentinelBridge.create_mock(event_bus)
    local MockBridge = require("integrations/sentinel_bridge/mock_bridge")
    local mock = MockBridge:new(event_bus)
    local o = SentinelBridge:new(nil, event_bus)
    o._quest = mock:get_quest_client()
    o._addons = mock:get_addons_client()
    o._render = RenderBridge.create_headless()
    return o
end

---Create real implementations (used when Sylvanas API is available)
---@param blackboard table
---@param event_bus table
---@return table bridge
function SentinelBridge.create_real(blackboard, event_bus)
    return SentinelBridge:new(blackboard, event_bus)
end

return SentinelBridge