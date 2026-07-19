-- sentinel/ui/panels/explorer_panel.lua
-- Hierarchical tree: Profile → Operations → Actions
-- Built on SentinelUI primitives

local SentinelUI = require("shared/ui/sentinel_ui")

local ExplorerPanel = {}
ExplorerPanel.__index = ExplorerPanel

function ExplorerPanel:new(blackboard, event_bus)
    local o = setmetatable({}, ExplorerPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._profile = nil
    o._operations = {}
    o._selected_operation = nil
    o._expanded_ops = {} -- op_id -> bool
    o._indent_width = 20
    return o
end

function ExplorerPanel:init()
    self._ui = SentinelUI.new({
        id = "explorer_panel",
        title = "Explorer",
        default_x = 100,
        default_y = 500,
        default_w = 350,
        default_h = 500,
        theme = "sentinel",
    })

    self._ui:add_tab({ id = "structure", label = "Structure" }, function(t)
        t:custom_render({
            label = "Explorer Tree",
            render_fn = function(ui, y)
                return self:_render_tree(ui, y)
            end
        })
    end)

    return true
end

function ExplorerPanel:_render_tree(ui, y)
    local window = ui.window
    local colors = ui.colors

    -- Get active profile from blackboard
    local profile = nil
    if self._blackboard then
        profile = self._blackboard.get("module.runtime.active_profile")
    end

    if not profile then
        local text = "No profile loaded"
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.text_disabled, text)
        return y + text_size.y + 8
    end

    self._profile = profile

    -- Render profile header
    local profile_name = profile.name or "Unnamed Profile"
    local header_text = "📁 " .. profile_name
    local name_size = window:get_text_size(header_text)
    window:render_text(0, { x = 16, y = y }, colors.text_primary, header_text)
    y = y + name_size.y + 6

    -- Render operations
    local ops = profile.operations or {}
    for i, op in ipairs(ops) do
        y = self:_render_operation(ui, op, i, 1, y)
    end

    return y
end

function ExplorerPanel:_render_operation(ui, op, op_index, depth, y)
    local window = ui.window
    local colors = ui.colors

    local op_id = op.id or ("op_" .. op_index)
    local op_name = op.name or ("Operation " .. op_index)
    local is_expanded = self._expanded_ops[op_id] ~= false
    local is_selected = self._selected_operation == op_id

    local indent = depth * self._indent_width
    local expand_text = is_expanded and "▼" or "▶"

    -- Render expand/collapse icon
    local icon_x = indent + 4
    local icon_y = y
    local icon_size = window:get_text_size(expand_text)
    window:render_text(0, { x = icon_x, y = icon_y + 2 }, colors.text_secondary, expand_text)

    -- Click on expand icon
    local expand_clicked = false
    if window.is_rect_clicked then
        expand_clicked = window:is_rect_clicked(
            { x = icon_x, y = icon_y },
            { x = icon_x + icon_size.x, y = icon_y + icon_size.y + 4 }
        )
    end
    if expand_clicked then
        self._expanded_ops[op_id] = not is_expanded
        if self._event_bus and self._event_bus.publish then
            self._event_bus:publish("explorer:toggle_operation", {
                operation_id = op_id,
                expanded = self._expanded_ops[op_id]
            })
        end
    end

    -- Render operation title with background selection
    local title_x = indent + 22
    local title_text = is_expanded and ("📂 " .. op_name) or ("📁 " .. op_name)
    local bg_start = { x = title_x - 4, y = icon_y }
    local bg_end = { x = title_x + window:get_text_size(op_name).x + 30, y = icon_y + 22 }

    if is_selected then
        window:render_rect_filled(bg_start, bg_end, colors.listbox_selected or colors.primary_accent, 4.0)
    end

    window:render_text(0, { x = title_x, y = icon_y + 2 },
        is_selected and colors.text_primary or colors.text_secondary,
        title_text
    )

    -- Click on operation to select
    local title_width = window:get_text_size(op_name).x + 30
    local row_clicked = false
    if window.is_rect_clicked then
        row_clicked = window:is_rect_clicked(
            { x = title_x - 4, y = icon_y },
            { x = title_x + title_width, y = icon_y + 22 }
        )
    end
    if row_clicked then
        self._selected_operation = op_id
        if self._event_bus and self._event_bus.publish then
            self._event_bus:publish("explorer:selected_operation", {
                operation_id = op_id,
                operation = op
            })
        end
    end

    y = y + 26

    -- Render actions if expanded
    if is_expanded then
        local actions = op.actions or {}
        for j, action in ipairs(actions) do
            y = self:_render_action(ui, action, depth + 1, j, y)
        end

        -- Show empty state if no actions
        if #actions == 0 then
            local empty_text = "  (no actions)"
            window:render_text(0, { x = indent + 30, y = y }, colors.text_disabled, empty_text)
            y = y + 20
        end
    end

    return y
end

function ExplorerPanel:_render_action(ui, action, depth, index, y)
    local window = ui.window
    local colors = ui.colors

    local indent = depth * self._indent_width
    local action_id = action.id or ("action_" .. index)
    local action_type = action.type or "unknown"
    local action_name = action.name or ("Action " .. index)

    -- Get color for action type
    local action_color = self:_get_action_color(action_type, colors)

    -- Render action icon (circle)
    local icon_x = indent + 4
    local icon_y = y + 8
    window:render_rect_filled(
        { x = icon_x, y = icon_y },
        { x = icon_x + 8, y = icon_y + 8 },
        action_color, 4.0
    )

    -- Render action name
    local name_x = indent + 18
    window:render_text(0, { x = name_x, y = y + 4 }, colors.text_secondary, action_name)

    -- Click to select action
    local action_clicked = false
    if window.is_rect_clicked then
        action_clicked = window:is_rect_clicked(
            { x = icon_x, y = icon_y },
            { x = icon_x + 100, y = icon_y + 12 }
        )
    end
    if action_clicked then
        if self._event_bus and self._event_bus.publish then
            self._event_bus:publish("explorer:selected_action", {
                action = action,
                action_id = action_id
            })
        end
    end

    y = y + 20
    return y
end

function ExplorerPanel:_get_action_color(action_type, colors)
    local type_colors = {
        movement = { r = 170, g = 100, b = 230 },
        spell = { r = 86, g = 140, b = 210 },
        interact = { r = 72, g = 200, b = 110 },
        wait = { r = 235, g = 150, b = 40 },
        condition = { r = 210, g = 160, b = 80 },
    }

    if not action_type then
        return { r = 200, g = 200, b = 200 }
    end

    return type_colors[action_type:lower()] or { r = 200, g = 200, b = 200 }
end

function ExplorerPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function ExplorerPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
    -- Refresh profile from blackboard
    self:_refresh_profile()
end

function ExplorerPanel:_refresh_profile()
    if self._blackboard then
        local profile = self._blackboard.get and self._blackboard:get("module.runtime.active_profile")
        if profile then
            self._profile = profile
        end
    end
end

function ExplorerPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function ExplorerPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function ExplorerPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function ExplorerPanel:shutdown()
    self._ui = nil
    self._blackboard = nil
    self._event_bus = nil
end

return ExplorerPanel