--- Sentinel Questing Module
--- Handles quest execution for a leveling route
---
--- Responsibilities:
--- - Load compiled profiles (Runtime JSON)
--- - Execute actions via Sylvanas APIs
--- - Track quest state and progress
--- - Navigate between objectives

local RuntimeProfileExecutor = require("runtime/lua/runtime_profile")
local RuntimeAction = require("runtime/lua/runtime_action")

local QuestingModule = {}
QuestingModule.__index = QuestingModule

function QuestingModule:new(blackboard, event_bus)
    local o = setmetatable({}, QuestingModule)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._executor = nil
    o._current_operation = 1
    o._completed_operations = {}
    return o
end

function QuestingModule:initialize(profile_json_path)
    self._executor = RuntimeProfileExecutor:new(profile_json_path)
    local success, err = self._executor:load()
    if not success then
        if core and core.log_error then
            core.log_error("[Questing] Failed to load profile: " .. tostring(err))
        end
        return false
    end

    self._blackboard:set("questing.enabled", true)
    return true
end

function QuestingModule:tick(delta)
    if not self._executor then return end

    local status, message = self._executor:execute()
    self._blackboard:set("questing.status", status)
    self._blackboard:set("questing.message", message)

    if status == "finished" then
        self._event_bus:publish("questing:finished", {
            path = self._executor._json_path
        })
    end
end

function QuestingModule:shutdown()
    self._blackboard:set("questing.enabled", false)
end

return QuestingModule