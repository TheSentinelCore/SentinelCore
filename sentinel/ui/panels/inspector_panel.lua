-- sentinel/ui/panels/inspector_panel.lua
-- Property editor for selected object.
-- Reads selection from blackboard module.ui.selected.
-- Built on SentinelUI primitives.

local SentinelUI = require("shared/ui/sentinel_ui")

local InspectorPanel = {}
InspectorPanel.__index = InspectorPanel

function InspectorPanel:new(blackboard, event_bus)
    local o = setmetatable({}, InspectorPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._selected_object = nil
    o._property_values = {} -- For editable properties
    return o
end

function InspectorPanel:init()
    self._ui = SentinelUI.new({
        id = "inspector_panel",
        title = "Inspector",
        default_x = 450,
        default_y = 500,
        default_w = 350,
        default_h = 500,
        theme = "sentinel",
    })

    self._ui:add_tab({ id = "properties", label = "Properties" }, function(t)
        t:custom_render({
            label = "Property Editor",
            render_fn = function(ui, y)
                return self:_render_properties(ui, y)
            end
        })
    end)

    self._ui:add_tab({ id = "metadata", label = "Metadata" }, function(t)
        t:custom_render({
            label = "Object Info",
            render_fn = function(ui, y)
                return self:_render_metadata(ui, y)
            end
        })
    end)

    return true
end

function InspectorPanel:_render_properties(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._selected_object then
        local text = "No object selected"
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, { r = 100, g = 108, b = 118, a = 170 }, text)
        return y + text_size.y + 8
    end

    -- Get properties to display
    local properties = self:_get_object_properties(self._selected_object)

    for _, prop in ipairs(properties) do
        y = self:_render_property_row(ui, prop, y)
    end

    return y
end

function InspectorPanel:_render_property_row(ui, prop, y)
    local window = ui.window
    local colors = ui.colors
    local LAYOUT = { element_height = 24, element_spacing = 4, checkbox_size = 18 }

    local label = prop.label or prop.key
    local value = prop.value
    local value_type = prop.type or "text"

    -- Label
    local label_x = 16
    local label_y = y + (LAYOUT.element_height - window:get_text_size(label).y) / 2
    window:render_text(0, { x = label_x, y = label_y }, { r = 220, g = 225, b = 232, a = 245 }, label)

    -- Value display
    local value_x = 120
    if value_type == "boolean" then
        local is_checked = value == true
        local box_start = { x = value_x, y = y }
        local box_end = { x = value_x + LAYOUT.checkbox_size, y = y + LAYOUT.checkbox_size }
        local box_color = is_checked and { r = 86, g = 140, b = 210, a = 255 } or { r = 48, g = 54, b = 64, a = 210 }
        window:render_rect_filled(box_start, box_end, box_color, 4.0)
        window:render_rect(box_start, box_end, { r = 72, g = 82, b = 96, a = 200 }, 4.0, 1.0)
    else
        local value_str = tostring(value or "")
        window:render_text(0, { x = value_x, y = label_y }, { r = 160, g = 170, b = 182, a = 210 }, value_str)
    end

    y = y + LAYOUT.element_height + LAYOUT.element_spacing
    return y
end

function InspectorPanel:_render_metadata(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._selected_object then
        local text = "No object selected"
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, { r = 100, g = 108, b = 118, a = 170 }, text)
        return y + text_size.y + 8
    end

    -- Display metadata about the selected object
    local obj_type = self._selected_object.type or "unknown"
    local obj_name = self._selected_object.name or self._selected_object.id or "unnamed"

    -- Type line
    local type_text = "Type: " .. obj_type
    local type_size = window:get_text_size(type_text)
    window:render_text(0, { x = 16, y = y }, { r = 220, g = 225, b = 232, a = 245 }, type_text)
    y = y + type_size.y + 6

    -- Name line
    local name_text = "Name: " .. obj_name
    local name_size = window:get_text_size(name_text)
    window:render_text(0, { x = 16, y = y }, { r = 160, g = 170, b = 182, a = 210 }, name_text)
    y = y + name_size.y + 6

    return y
end

function InspectorPanel:_get_object_properties(obj)
    local props = {}

    if not obj then
        return props
    end

    -- Common properties
    if obj.id then
        table.insert(props, {
            key = "id",
            label = "ID",
            value = obj.id,
            type = "text"
        })
    end

    if obj.name then
        table.insert(props, {
            key = "name",
            label = "Name",
            value = obj.name,
            type = "text"
        })
    end

    if obj.type then
        table.insert(props, {
            key = "type",
            label = "Type",
            value = obj.type,
            type = "text"
        })
    end

    -- Operation-specific properties
    if obj.conditions then
        table.insert(props, {
            key = "conditions",
            label = "Conditions",
            value = #obj.conditions .. " defined",
            type = "text"
        })
    end

    if obj.recovery then
        table.insert(props, {
            key = "recovery",
            label = "Recovery",
            value = obj.recovery,
            type = "text"
        })
    end

    return props
end

function InspectorPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end

    -- Refresh selection from blackboard
    self:_refresh_selection()
end

function InspectorPanel:_refresh_selection()
    if self._blackboard then
        local selected = self._blackboard.get and self._blackboard:get("module.ui.selected")
        if selected then
            self._selected_object = selected
        end
    end
end

function InspectorPanel:set_selected(obj)
    self._selected_object = obj
end

function InspectorPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function InspectorPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function InspectorPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function InspectorPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function InspectorPanel:shutdown()
    self._ui = nil
    self._blackboard = nil
    self._event_bus = nil
    self._selected_object = nil
    self._property_values = {}
end

return InspectorPanel