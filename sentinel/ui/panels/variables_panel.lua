-- sentinel/ui/panels/variables_panel.lua
-- Variable management panel with Global/Operation tabs

local SentinelUI = require("shared/ui/sentinel_ui")
local VariableStore = require("runtime/variable_store")

local VariablesPanel = {}
VariablesPanel.__index = VariablesPanel

function VariablesPanel:new(blackboard, event_bus)
    local o = setmetatable({}, VariablesPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._variable_store = nil
    o._active_scope = "global" -- "global" or operation_id
    o._selected_variable = nil
    o._show_create_dialog = false
    return o
end

function VariablesPanel:init()
    self._variable_store = VariableStore:new(self._blackboard)
    
    self._ui = SentinelUI.new({
        id = "variables",
        title = "Variables",
        default_x = 400,
        default_y = 100,
        default_w = 400,
        default_h = 400,
        theme = "sentinel",
    })
    
    -- Initialize UI state
    self._ui.menu = {
        scope_tab = {
            get = function() return self._active_scope == "global" and 1 or 2 end,
            set = function(v) self._active_scope = v == 1 and "global" or "operation" end,
        },
    }
    
    -- Scope selection segmented control
    self._ui:add_tab({ id = "variables_tab", label = "Variables" }, function(t)
        t:segmented_control({
            element = self._ui.menu.scope_tab,
            options = { "Global", "Operation" },
            label = "Scope",
            on_change = function()
                -- Update scope when tab changes
                local scope_idx = self._ui.menu.scope_tab.get()
                self._active_scope = scope_idx == 1 and "global" or "current_operation"
            end,
        })
        
        t:row_list({
            id = "create_btn_row",
            elements = {
                {
                    type = "button",
                    label = "",
                    text = "Create Variable",
                    on_click = function()
                        self._show_create_dialog = true
                    end,
                },
            },
        })
        
        t:listbox({
            id = "variables_list",
            entries_fn = function()
                return self:_get_variable_entries()
            end,
            on_select = function(idx, entry)
                self._selected_variable = entry.key
                self:_on_variable_selected(entry.key)
            end,
            render_fn = function(ui, y_offset)
                return ui:_render_listbox({
                    id = "variables_list",
                    entries_fn = function()
                        return self:_get_variable_entries()
                    end,
                    on_select = function(idx, entry)
                        self._selected_variable = entry.key
                        self:_on_variable_selected(entry.key)
                    end,
                    visible_rows = 10,
                }, y_offset)
            end,
        })
    end)
    
    -- Watch tab (during execution)
    self._ui:add_tab({ id = "watch", label = "Watch" }, function(t)
        t:listbox({
            id = "watch_list",
            entries_fn = function()
                return self:_get_watch_entries()
            end,
            visible_rows = 10,
        })
    end)
    
    return true
end

function VariablesPanel:_get_variable_entries()
    local entries = {}
    local keys = self._variable_store:list(self._active_scope)
    
    for _, key in ipairs(keys) do
        local value = self._variable_store:get(self._active_scope, key)
        local type_name = self._variable_store:get_type(self._active_scope, key)
        local display_value = self:_format_value(value, type_name)
        
        table.insert(entries, {
            label = key,
            sublabel = type_name .. ": " .. display_value,
            key = key,
            value = value,
            type = type_name,
        })
    end
    
    -- Empty state
    if #entries == 0 then
        table.insert(entries, {
            label = "No variables defined.",
            sublabel = "Create one to use in Branch/SetVariable actions.",
            disabled = true,
        })
    end
    
    return entries
end

function VariablesPanel:_get_watch_entries()
    local entries = {}
    
    -- Show all global variables and current operation variables
    local scopes = { "global", self._active_scope }
    local seen = {}
    
    for _, scope in ipairs(scopes) do
        if scope ~= "global" then
            local keys = self._variable_store:list(scope)
            for _, key in ipairs(keys) do
                if not seen[key] then
                    seen[key] = true
                    local value = self._variable_store:get(scope, key)
                    local type_name = self._variable_store:get_type(scope, key)
                    local display_value = self:_format_value(value, type_name)
                    
                    table.insert(entries, {
                        label = key .. " (" .. scope .. ")",
                        sublabel = tostring(display_value),
                        value = value,
                    })
                end
            end
        end
    end
    
    -- Also add global variables
    local global_keys = self._variable_store:list("global")
    for _, key in ipairs(global_keys) do
        if not seen[key] then
            local value = self._variable_store:get("global", key)
            local type_name = self._variable_store:get_type("global", key)
            local display_value = self:_format_value(value, type_name)
            
            table.insert(entries, {
                label = key .. " (global)",
                sublabel = tostring(display_value),
                value = value,
            })
        end
    end
    
    return entries
end

function VariablesPanel:_format_value(value, type_name)
    if type_name == "position" then
        return string.format("(%d, %d, %d)", value.x or 0, value.y or 0, value.z or 0)
    end
    return tostring(value)
end

function VariablesPanel:_on_variable_selected(key)
    if self._event_bus and self._event_bus.publish then
        self._event_bus:publish("variable:selected", {
            scope = self._active_scope,
            key = key,
        })
    end
end

function VariablesPanel:create_variable(scope, key, type_name, value)
    return self._variable_store:set(scope, key, value)
end

function VariablesPanel:delete_variable(scope, key)
    return self._variable_store:delete(scope, key)
end

function VariablesPanel:get_variables(scope)
    return self._variable_store:list(scope)
end

function VariablesPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function VariablesPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function VariablesPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function VariablesPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function VariablesPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function VariablesPanel:shutdown()
    self._ui = nil
    self._variable_store = nil
end

return VariablesPanel