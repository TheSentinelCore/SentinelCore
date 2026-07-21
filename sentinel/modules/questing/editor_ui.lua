// Sentinel Questing Editor UI
// XML UI definition for in-game editor

local QuestingEditor = {}
QuestingEditor.__index = QuestingEditor

function QuestingEditor:new()
    local o = setmetatable({}, QuestingEditor)
    o._visible = false
    o._selected_profile = nil
    return o
end

function QuestingEditor:show()
    self._visible = true
    if GameTooltip and GameTooltip.SetOwner then
        -- Show UI frame
    end
end

function QuestingEditor:hide()
    self._visible = false
end

function QuestingEditor:is_visible()
    return self._visible
end

-- Load profile for editing
function QuestingEditor:load_profile(path)
    self._selected_profile = path
    -- Would trigger editor UI to load project
end

-- Save current project
function QuestingEditor:save_project()
    -- Would call sentinel-editor crate API
end

-- Compile selected profile
function QuestingEditor:compile()
    if not self._selected_profile then
        return false, "No profile selected"
    end
    -- Would call sentinel-compile CLI or editor API
    return true
end

return QuestingEditor