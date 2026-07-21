--- Sentinel Questing Module
--- Handles quest execution for a leveling route
---
--- Responsibilities:
--- - Load compiled profiles (Runtime JSON)
--- - Execute actions via Sylvanas APIs
--- - Track quest state and progress
--- - Navigate between objectives
--- - In-game editor (optional, toggled via /qe or toggle_editor())

local RuntimeProfile = require("modules/questing/runtime_profile")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")

local QuestingModule = {}
QuestingModule.__index = QuestingModule

function QuestingModule:new(blackboard, event_bus)
    local o = setmetatable({}, QuestingModule)
    o._blackboard = blackboard or Blackboard:new()
    o._event_bus = event_bus or EventBus:new(function(msg)
        if core and core.print then core.print(msg) end
    end)
    o._executor = nil
    o._enabled = false
    -- Editor (lazy-loaded on first toggle)
    o._editor = nil
    return o
end

function QuestingModule:initialize(profile_json_path)
    self._executor = RuntimeProfile:new(profile_json_path)
    local success, err = self._executor:load()
    if not success then
        self._event_bus:publish("questing:error", { error = err })
        return false
    end
    self._enabled = true
    self._blackboard:set("questing.enabled", true)
    return true
end

function QuestingModule:tick(delta)
    if not self._enabled or not self._executor then return end

    local status, message = self._executor:execute()
    self._blackboard:set("questing.status", status)
    self._blackboard:set("questing.message", message)

    if status == "finished" then
        self._enabled = false
        self._blackboard:set("questing.enabled", false)
        self._event_bus:publish("questing:finished", {
            path = self._executor._json_path
        })
    end
end

function QuestingModule:shutdown()
    self._enabled = false
    self._blackboard:set("questing.enabled", false)
end

function QuestingModule:is_enabled()
    return self._enabled
end

-- ======================================================================
-- Editor integration
-- ======================================================================

--- Get or create the editor instance (lazy).
function QuestingModule:_get_editor()
    if not self._editor then
        local QuestingEditor = require("modules/questing/editor_ui")
        self._editor = QuestingEditor:new()
    end
    return self._editor
end

--- Toggle the in-game quest profile editor.
function QuestingModule:toggle_editor()
    local editor = self:_get_editor()
    editor:toggle()
    if editor:is_visible() then
        self._event_bus:publish("questing:editor_opened", {})
    else
        self._event_bus:publish("questing:editor_closed", {})
    end
end

--- Reload the current executor from a compiled profile.
--- Useful after the editor compiles a project — the new profile JSON
--- can be loaded directly.
---@param profile_json string Compiled RuntimeProfile JSON
function QuestingModule:load_compiled_profile(profile_json)
    -- Create a temporary executor that loads from a JSON string
    -- (by writing to a temp file and loading it)
    local temp_path = "SentinelCore/questing/_editor_compile.json"
    if core and core.write_file then
        core.write_file(temp_path, profile_json)
    end
    return self:initialize(temp_path)
end

return QuestingModule