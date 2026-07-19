-- sentinel/ui/panels/timeline_panel.lua
-- Vertical action list for selected Operation. Color coded by action type.
-- Built on SentinelUI primitives.

local SentinelUI = require("shared/ui/sentinel_ui")

local TimelinePanel = {}
TimelinePanel.__index = TimelinePanel

function TimelinePanel:new(blackboard, event_bus)
    local o = setmetatable({}, TimelinePanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._operation = nil
    o._actions = {}
    o._selected_action_idx = nil
    o._item_height = 32
    o._item_spacing = 4
    return o
end

function TimelinePanel:init()
    self._ui = SentinelUI.new({
        id = "timeline_panel",
        title = "Timeline",
        default_x = 800,
        default_y = 500,
        default_w = 300,
        default_h = 500,
        theme = "sentinel",
    })

    self._ui:add_tab({ id = "actions", label = "Actions" }, function(t)
        t:custom_render({
            label = "Operation Timeline",
            render_fn = function(ui, y)
                return self:_render_timeline(ui, y)
            end
        })
    end)

    return true
end

function TimelinePanel:_render_timeline(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._operation then
        local text = "No operation selected"
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.text_disabled, text)
        return y + text_size.y + 8
    end

    -- Get operation name
    local op_name = self._operation.name or self._operation.id or "Unnamed"
    local header = "Operation: " .. op_name
    local header_size = window:get_text_size(header)
    window:render_text(0, { x = 16, y = y }, colors.text_primary, header)
    y = y + header_size.y + 12

    -- Render action items
    local actions = self._operation.actions or {}
    if #actions == 0 then
        local empty_text = "  (no actions)"
        window:render_text(0, { x = 16, y = y }, colors.text_disabled, empty_text)
        y = y + 20
        return y
    end

    for i, action in ipairs(actions) do
        y = self:_render_action_item(ui, action, i, y)
    end

    return y
end

function TimelinePanel:_render_action_item(ui, action, index, y)
    local window = ui.window
    local colors = ui.colors

    local x_start = 16
    local item_y = y
    local item_height = self._item_height

    -- Get action info
    local action_type = action.type or "unknown"
    local action_name = action.name or ("Action " .. index)
    local action_id = action.id or ("action_" .. index)

    -- Background based on selection
    if self._selected_action_idx == index then
        window:render_rect_filled(
            { x = x_start - 4, y = item_y },
            { x = x_start + 260, y = item_y + item_height },
            { r = 86, g = 140, b = 210, a = 45 }, 4.0
        )
    end

    -- Color indicator bar
    local type_color = self:_get_action_color(action_type)
    window:render_rect_filled(
        { x = x_start, y = item_y + 4 },
        { x = x_start + 4, y = item_y + item_height - 4 },
        type_color, 2.0
    )

    -- Action number
    local num_text = tostring(index) .. "."
    local num_size = window:get_text_size(num_text)
    window:render_text(0, { x = x_start + 12, y = item_y + 6 }, { r = 200, g = 200, b = 200, a = 255 }, num_text)

    -- Action type badge
    local type_text = "[" .. action_type .. "]"
    local type_size = window:get_text_size(type_text)
    window:render_text(0, { x = x_start + 32, y = item_y + 6 },
        { r = type_color.r, g = type_color.g, b = type_color.b, a = 255 },
        type_text
    )

    -- Action name
    local name_x = x_start + 32 + type_size.x + 8
    window:render_text(0, { x = name_x, y = item_y + 6 }, { r = 220, g = 225, b = 232, a = 245 }, action_name)

    -- Handle click to select
    local clicked = false
    if window.is_rect_clicked then
        clicked = window:is_rect_clicked(
            { x = x_start, y = item_y },
            { x = x_start + 260, y = item_y + item_height }
        )
    end
    if clicked then
        self._selected_action_idx = index
        if self._event_bus and self._event_bus.publish then
            self._event_bus:publish("timeline:selected_action", {
                action = action,
                index = index
            })
        end
    end

    y = y + item_height + self._item_spacing
    return y
end

function TimelinePanel:_get_action_color(action_type)
    local type_colors = {
        movement = { r = 86, g = 140, b = 210 },
        spell = { r = 210, g = 160, b = 80 },
        interact = { r = 72, g = 200, b = 110 },
        wait = { r = 235, g = 150, b = 40 },
        condition = { r = 170, g = 100, b = 230 },
    }

    if not action_type then
        return { r = 200, g = 200, b = 200 }
    end

    return type_colors[action_type:lower()] or { r = 200, g = 200, b = 200 }
end

function TimelinePanel:set_operation(operation)
    self._operation = operation
    self._actions = operation and (operation.actions or {}) or {}
    self._selected_action_idx = nil
end

function TimelinePanel:set_actions(actions)
    self._actions = actions or {}
end

function TimelinePanel:get_selected_index()
    return self._selected_action_idx
end

function TimelinePanel:get_selected_action()
    if self._selected_action_idx and self._actions then
        return self._actions[self._selected_action_idx]
    end
    return nil
end

function TimelinePanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
    -- Refresh selection from blackboard
    self:_refresh_selection()
end

function TimelinePanel:_refresh_selection()
    if self._blackboard then
        local selected_op = self._blackboard.get and self._blackboard:get("module.ui.selected_operation")
        if selected_op and selected_op ~= self._operation then
            self:set_operation(selected_op)
        end
    end
end

function TimelinePanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function TimelinePanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function TimelinePanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function TimelinePanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function TimelinePanel:shutdown()
    self._ui = nil
    self._blackboard = nil
    self._event_bus = nil
    self._operation = nil
    self._actions = {}
end

return TimelinePanel