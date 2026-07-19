-- sentinel/ui/panels/validation_panel.lua
-- Displays compiler/validation errors with severity icons

local SentinelUI = require("shared/ui/sentinel_ui")

local ValidationPanel = {}
ValidationPanel.__index = ValidationPanel

-- Severity constants
local SEVERITY = {
    ERROR = "error",
    WARNING = "warning",
    INFO = "info",
    SUCCESS = "success",
}

function ValidationPanel:new(blackboard, event_bus)
    local o = setmetatable({}, ValidationPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._errors = {} -- List of { severity, code, message, entity_ref }
    o._show_errors = true
    o._show_warnings = true
    o._show_info = true
    return o
end

function ValidationPanel:init()
    self._ui = SentinelUI.new({
        id = "validation",
        title = function()
            local count = self:_get_filtered_count()
            return "Validation (" .. count .. ")"
        end,
        default_x = 800,
        default_y = 100,
        default_w = 500,
        default_h = 300,
        theme = "sentinel",
    })
    
    self._ui:add_tab({ id = "validation_tab", label = "Issues" }, function(t)
        -- Filter toggles
        t:checkbox_grid({
            label = "Show",
            columns = 3,
            elements = {
                { element = { get = function() return self._show_errors end, set = function(v) self._show_errors = v end }, label = "Errors" },
                { element = { get = function() return self._show_warnings end, set = function(v) self._show_warnings = v end }, label = "Warnings" },
                { element = { get = function() return self._show_info end, set = function(v) self._show_info = v end }, label = "Info" },
            },
        })
        
        t:listbox({
            id = "issues_list",
            entries_fn = function()
                return self:_get_filtered_entries()
            end,
            on_select = function(idx, entry)
                self:_on_entry_selected(entry)
            end,
            visible_rows = 12,
        })
    end)
    
    -- Subscribe to validation updates
    if self._event_bus and self._event_bus.subscribe then
        self._event_bus:subscribe("validation:add", function(payload)
            self:add_error(payload.severity, payload.code, payload.message, payload.entity_ref)
        end)
        self._event_bus:subscribe("validation:clear", function()
            self:clear()
        end)
    end
    
    return true
end

function ValidationPanel:_get_filtered_count()
    local count = 0
    for _, entry in ipairs(self._errors) do
        if self:_is_entry_visible(entry) then
            count = count + 1
        end
    end
    return count
end

function ValidationPanel:_is_entry_visible(entry)
    if entry.severity == SEVERITY.ERROR then
        return self._show_errors
    elseif entry.severity == SEVERITY.WARNING then
        return self._show_warnings
    elseif entry.severity == SEVERITY.INFO then
        return self._show_info
    end
    return true
end

function ValidationPanel:_get_filtered_entries()
    local entries = {}
    
    for _, entry in ipairs(self._errors) do
        if self:_is_entry_visible(entry) then
            local icon, color = self:_get_severity_display(entry.severity)
            table.insert(entries, {
                label = icon .. " " .. entry.message,
                sublabel = entry.code or "",
                severity = entry.severity,
                entity_ref = entry.entity_ref,
                color = color,
            })
        end
    end
    
    -- Empty state
    if #entries == 0 then
        table.insert(entries, {
            label = "✓ No issues found. Profile is valid.",
            sublabel = "",
            disabled = true,
        })
    end
    
    return entries
end

function ValidationPanel:_get_severity_display(severity)
    if self._ui and self._ui.colors then
        if severity == SEVERITY.ERROR then
            return "●", self._ui.colors.status_red
        elseif severity == SEVERITY.WARNING then
            return "●", self._ui.colors.status_yellow
        elseif severity == SEVERITY.INFO then
            return "●", self._ui.colors.text_secondary
        elseif severity == SEVERITY.SUCCESS then
            return "●", self._ui.colors.status_green
        end
    end
    return "●", nil
end

function ValidationPanel:_on_entry_selected(entry)
    if entry.entity_ref and self._event_bus then
        self._event_bus:publish("entity:navigate", entry.entity_ref)
    end
end

function ValidationPanel:add_warning(code, message, entity_ref)
    self:add("warning", code, message, entity_ref)
end

function ValidationPanel:add_info(code, message, entity_ref)
    self:add("info", code, message, entity_ref)
end

function ValidationPanel:add_success(code, message, entity_ref)
    self:add("success", code, message, entity_ref)
end

function ValidationPanel:add(severity, code, message, entity_ref)
    table.insert(self._errors, {
        severity = severity,
        code = code,
        message = message,
        entity_ref = entity_ref,
    })
    self:_refresh_title()
end

function ValidationPanel:clear()
    self._errors = {}
    self:_refresh_title()
end

function ValidationPanel:_refresh_title()
    -- Force title refresh via blackboard or direct update
    if self._event_bus then
        self._event_bus:publish("validation:updated", {
            count = self:_get_filtered_count(),
        })
    end
end

function ValidationPanel:get_errors()
    return self._errors
end

function ValidationPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function ValidationPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function ValidationPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function ValidationPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function ValidationPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function ValidationPanel:shutdown()
    self._ui = nil
end

return ValidationPanel