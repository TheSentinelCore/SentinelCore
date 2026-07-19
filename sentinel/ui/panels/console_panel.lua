-- sentinel/ui/panels/console_panel.lua
-- Multi-tab log viewer (Editor, Compiler, Runtime)

local SentinelUI = require("shared/ui/sentinel_ui")

local ConsolePanel = {}
ConsolePanel.__index = ConsolePanel

function ConsolePanel:new(blackboard, event_bus)
    local o = setmetatable({}, ConsolePanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._logs = {
        editor = {},
        compiler = {},
        runtime = {},
    }
    o._auto_scroll = {
        editor = true,
        compiler = true,
        runtime = true,
    }
    o._active_tab = 1
    return o
end

function ConsolePanel:init()
    self._ui = SentinelUI.new({
        id = "console",
        title = "Console",
        default_x = 100,
        default_y = 600,
        default_w = 600,
        default_h = 300,
        theme = "sentinel",
    })
    
    self._ui.menu = {
        active_tab = {
            get = function() return self._active_tab end,
            set = function(v) self._active_tab = v end,
        },
    }
    
    -- Editor tab
    self._ui:add_tab({ id = "editor", label = "Editor" }, function(t)
        t:row_list({
            id = "editor_controls",
            elements = {
                {
                    type = "toggle",
                    label = "Auto-scroll",
                    element = { get_state = function() return self._auto_scroll.editor end, set = function(v) self._auto_scroll.editor = v end },
                },
                {
                    type = "button",
                    label = "",
                    text = "Clear",
                    on_click = function() self:clear("editor") end,
                },
                {
                    type = "button",
                    label = "",
                    text = "Export",
                    on_click = function() self:export("editor") end,
                },
            },
        })
        
        t:listbox({
            id = "editor_log",
            entries_fn = function()
                local entries = {}
                for _, entry in ipairs(self._logs.editor) do
                    table.insert(entries, {
                        label = self:_format_log_entry(entry),
                        timestamp = entry.timestamp,
                        level = entry.level,
                    })
                end
                return entries
            end,
            visible_rows = 10,
        })
    end)
    
    -- Compiler tab
    self._ui:add_tab({ id = "compiler", label = "Compiler" }, function(t)
        t:row_list({
            id = "compiler_controls",
            elements = {
                {
                    type = "toggle",
                    label = "Auto-scroll",
                    element = { get_state = function() return self._auto_scroll.compiler end, set = function(v) self._auto_scroll.compiler = v end },
                },
                {
                    type = "button",
                    label = "",
                    text = "Clear",
                    on_click = function() self:clear("compiler") end,
                },
                {
                    type = "button",
                    label = "",
                    text = "Export",
                    on_click = function() self:export("compiler") end,
                },
            },
        })
        
        t:listbox({
            id = "compiler_log",
            entries_fn = function()
                local entries = {}
                for _, entry in ipairs(self._logs.compiler) do
                    table.insert(entries, {
                        label = self:_format_log_entry(entry),
                        timestamp = entry.timestamp,
                        level = entry.level,
                    })
                end
                return entries
            end,
            visible_rows = 10,
        })
    end)
    
    -- Runtime tab
    self._ui:add_tab({ id = "runtime", label = "Runtime" }, function(t)
        t:row_list({
            id = "runtime_controls",
            elements = {
                {
                    type = "toggle",
                    label = "Auto-scroll",
                    element = { get_state = function() return self._auto_scroll.runtime end, set = function(v) self._auto_scroll.runtime = v end },
                },
                {
                    type = "button",
                    label = "",
                    text = "Clear",
                    on_click = function() self:clear("runtime") end,
                },
                {
                    type = "button",
                    label = "",
                    text = "Export",
                    on_click = function() self:export("runtime") end,
                },
            },
        })
        
        t:listbox({
            id = "runtime_log",
            entries_fn = function()
                local entries = {}
                for _, entry in ipairs(self._logs.runtime) do
                    table.insert(entries, {
                        label = self:_format_log_entry(entry),
                        timestamp = entry.timestamp,
                        level = entry.level,
                    })
                end
                return entries
            end,
            visible_rows = 10,
        })
    end)
    
    -- Subscribe to log events
    if self._event_bus and self._event_bus.subscribe then
        self._event_bus:subscribe("log:editor", function(payload)
            self:log("editor", payload.level or "INFO", payload.message)
        end)
        self._event_bus:subscribe("log:compiler", function(payload)
            self:log("compiler", payload.level or "INFO", payload.message)
        end)
        self._event_bus:subscribe("log:runtime", function(payload)
            self:log("runtime", payload.level or "INFO", payload.message)
        end)
    end
    
    return true
end

function ConsolePanel:_format_log_entry(entry)
    local time_str = ""
    if entry.timestamp then
        local dt = os.date("*t", entry.timestamp)
        time_str = string.format("[%02d:%02d:%02d] ", dt.hour or 0, dt.min or 0, dt.sec or 0)
    end
    return time_str .. "[" .. (entry.level or "INFO") .. "] " .. (entry.message or "")
end

function ConsolePanel:log(tab, level, message)
    if not self._logs[tab] then return end
    
    table.insert(self._logs[tab], {
        timestamp = os.time(),
        level = level,
        message = message,
    })
end

function ConsolePanel:clear(tab)
    if tab then
        self._logs[tab] = {}
    else
        for k, _ in pairs(self._logs) do
            self._logs[k] = {}
        end
    end
end

function ConsolePanel:export(tab)
    if not core or not core.write_data_file then return end
    
    local content_lines = {}
    for _, entry in ipairs(self._logs[tab] or {}) do
        table.insert(content_lines, self:_format_log_entry(entry))
    end
    
    local content = table.concat(content_lines, "\n")
    local path = "sentinel/logs/" .. tab .. "_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
    
    core.write_data_file(path, content)
    
    if self._event_bus then
        self._event_bus:publish("log:exported", { path = path })
    end
end

function ConsolePanel:get_logs(tab)
    return self._logs[tab] or {}
end

function ConsolePanel:clear_all()
    self:clear()
end

function ConsolePanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function ConsolePanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function ConsolePanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function ConsolePanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function ConsolePanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function ConsolePanel:shutdown()
    self._ui = nil
end

return ConsolePanel