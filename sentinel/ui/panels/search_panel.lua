-- sentinel/ui/panels/search_panel.lua
-- Search Everywhere modal (Ctrl+P)

local SentinelUI = require("shared/ui/sentinel_ui")

local SearchPanel = {}
SearchPanel.__index = SearchPanel

function SearchPanel:new(blackboard, event_bus)
    local o = setmetatable({}, SearchPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._is_open = false
    o._search_text = ""
    o._selected_index = 1
    o._results = {}
    return o
end

function SearchPanel:init()
    self._ui = SentinelUI.new({
        id = "search",
        title = "Search",
        default_x = 400,
        default_y = 200,
        default_w = 500,
        default_h = 400,
        theme = "sentinel",
    })
    
    -- Subscribe to open events
    if self._event_bus and self._event_bus.subscribe then
        self._event_bus:subscribe("search:open", function()
            self:open()
        end)
    end
    
    return true
end

function SearchPanel:open()
    self._is_open = true
    self._search_text = ""
    self._selected_index = 1
    self._results = {}
end

function SearchPanel:close()
    self._is_open = false
end

function SearchPanel:is_open()
    return self._is_open
end

function SearchPanel:set_search_text(text)
    self._search_text = text or ""
    self:_perform_search()
end

function SearchPanel:_perform_search()
    self._results = {}
    
    if self._search_text == "" then
        return
    end
    
    local search = string.lower(self._search_text)
    
    -- Search NPCs
    if self._blackboard and self._blackboard.snapshot then
        local npcs = self._blackboard:snapshot("module.runtime.npcs.")
        for key, npc in pairs(npcs or {}) do
            if npc.name and string.find(string.lower(npc.name), search, 1, true) then
                table.insert(self._results, {
                    type = "npc",
                    label = npc.name,
                    sublabel = "NPC #" .. (npc.entry or "?"),
                    data = npc,
                })
            end
        end
    end
    
    -- Search Variables
    if self._blackboard and self._blackboard.snapshot then
        local vars = self._blackboard:snapshot("module.runtime.variables.")
        for key, value in pairs(vars or {}) do
            local var_name = key:match("[^%.]+$") or key
            if string.find(string.lower(var_name), search, 1, true) then
                table.insert(self._results, {
                    type = "variable",
                    label = var_name,
                    sublabel = tostring(value),
                    data = { key = var_name, value = value },
                })
            end
        end
    end
    
    -- Search Operations (from active profile)
    local profile = self._blackboard and self._blackboard.get and self._blackboard:get("module.runtime.active_profile_data")
    if profile and profile.operations then
        for _, op in ipairs(profile.operations) do
            if op.name and string.find(string.lower(op.name), search, 1, true) then
                table.insert(self._results, {
                    type = "operation",
                    label = op.name,
                    sublabel = op.id or "unknown",
                    data = op,
                })
            end
            
            -- Search actions within operations
            if op.actions then
                for _, action in ipairs(op.actions) do
                    if action.type and string.find(string.lower(action.type), search, 1, true) then
                        table.insert(self._results, {
                            type = "action",
                            label = action.type,
                            sublabel = op.name .. " / " .. (action.id or "?"),
                            data = { operation = op, action = action },
                        })
                    end
                end
            end
        end
    end
end

function SearchPanel:_get_icon_for_type(result_type)
    if result_type == "npc" then return "👤" end
    if result_type == "operation" then return "🔧" end
    if result_type == "action" then return "⚡" end
    if result_type == "variable" then return "🔤" end
    return "❓"
end

function SearchPanel:_navigate_to_result(result)
    if self._event_bus and self._event_bus.publish then
        if result.type == "npc" then
            self._event_bus:publish("entity:navigate", { type = "npc", id = result.data.entry })
        elseif result.type == "operation" then
            self._event_bus:publish("entity:navigate", { type = "operation", id = result.data.id })
        elseif result.type == "action" then
            self._event_bus:publish("entity:navigate", {
                type = "action",
                operation_id = result.data.operation.id,
                action_id = result.data.action.id,
            })
        elseif result.type == "variable" then
            self._event_bus:publish("entity:navigate", {
                type = "variable",
                key = result.data.key,
            })
        end
    end
end

function SearchPanel:select_next()
    if #self._results > 0 then
        self._selected_index = math.min(self._selected_index + 1, #self._results)
    end
end

function SearchPanel:select_prev()
    if #self._results > 0 then
        self._selected_index = math.max(1, self._selected_index - 1)
    end
end

function SearchPanel:confirm_selection()
    if self._selected_index >= 1 and self._selected_index <= #self._results then
        local result = self._results[self._selected_index]
        self:_navigate_to_result(result)
        self:close()
        return true
    end
    return false
end

function SearchPanel:get_results()
    local entries = {}
    for _, result in ipairs(self._results) do
        table.insert(entries, {
            label = self:_get_icon_for_type(result.type) .. " " .. result.label,
            sublabel = result.sublabel,
            data = result,
        })
    end
    return entries
end

function SearchPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function SearchPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function SearchPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function SearchPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function SearchPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function SearchPanel:shutdown()
    self._ui = nil
end

return SearchPanel