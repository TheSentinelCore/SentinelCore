-- sentinel/ui/toolbar.lua
-- Horizontal toolbar at top of window for IDE controls
-- Built on SentinelUI primitives

local SentinelUI = require("shared/ui/sentinel_ui")

local Toolbar = {}
Toolbar.__index = Toolbar

-- Action type to color mapping for timeline
Toolbar.ACTION_COLORS = {
    movement = { r = 86, g = 140, b = 210 },     -- Primary accent (blue)
    spell = { r = 210, g = 160, b = 80 },     -- Secondary accent (orange)
    interaction = { r = 72, g = 200, b = 110 }, -- Green
    wait = { r = 235, g = 150, b = 40 },      -- Orange
    condition = { r = 170, g = 100, b = 230 },  -- Purple
    unknown = { r = 200, g = 200, b = 200 },   -- Gray
}

function Toolbar:new(window, event_bus, profile_manager)
    local o = setmetatable({}, Toolbar)
    o._window = window
    o._event_bus = event_bus
    o._profile_manager = profile_manager
    o._ui = nil
    o._is_dry_run = false
    o._button_width = 90
    o._button_height = 28
    o._button_spacing = 4
    o._padding = 8
    o._y_offset = 0 -- For vertical positioning
    o._can_undo = false
    o._can_redo = false
    return o
end

function Toolbar:init()
    self._ui = SentinelUI.new({
        id = "ide_toolbar",
        title = "Toolbar",
        default_x = 100,
        default_y = 10,
        default_w = 800,
        default_h = 40,
        theme = "sentinel",
    })
    -- Reflect undo/redo availability published by the engine's CommandHistory.
    if self._event_bus and self._event_bus.subscribe then
        self._event_bus:subscribe("command_history:changed", function(payload)
            self._can_undo = payload and payload.can_undo or false
            self._can_redo = payload and payload.can_redo or false
        end)
    end
    return true
end

function Toolbar:_get_button_color(is_active, is_hovered)
    if self._ui.colors then
        if is_active then
            return self._ui.colors.primary_accent
        end
        if is_hovered then
            return self._ui.colors.bg_hover or self._ui.colors.section_bg
        end
        return self._ui.colors.section_bg
    end
    return { r = 50, g = 50, b = 50, a = 255 }
end

function Toolbar:render_button(x, y, label, tooltip, onclick, is_active, enabled)
    enabled = enabled ~= false -- default true
    local start_pos = { x = x, y = y }
    local end_pos = { x = x + self._button_width, y = y + self._button_height }

    -- Determine colors based on state
    local bg_color = self:_get_button_color(is_active, false)
    if is_active then
        bg_color = self._ui.colors.primary_accent
    end
    if not enabled then
        bg_color = self._ui.colors.section_bg
    end

    -- Render button background
    self._ui.window:render_rect_filled(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y },
        bg_color,
        4.0
    )

    -- Render border
    self._ui.window:render_rect(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y },
        self._ui.colors.section_border,
        4.0, 1.0
    )

    -- Render label (centered)
    local text_size = self._ui.window:get_text_size(label)
    local text_x = start_pos.x + (self._button_width - text_size.x) / 2
    local text_y = start_pos.y + (self._button_height - text_size.y) / 2
    local text_color = self._ui.colors.text_primary

    if is_active then
        text_color = { r = 255, g = 255, b = 255, a = 255 }
    end
    if not enabled then
        text_color = self._ui.colors.text_disabled or { r = 120, g = 120, b = 120, a = 255 }
    end

    self._ui.window:render_text(
        0,
        { x = text_x, y = text_y },
        text_color,
        label
    )

    -- Block dragging when hovering
    self._ui.window:is_mouse_hovering_rect_block_movement(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y }
    )

    -- Handle click (only when enabled)
    if enabled and self._ui.window:is_rect_clicked(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y }
    ) and onclick then
        onclick()
    end

    return end_pos.x + self._button_spacing
end

function Toolbar:render_toggle(x, y, label, is_toggled, onclick)
    local width = self._button_width
    local height = self._button_height
    local start_pos = { x = x, y = y }
    local end_pos = { x = x + width, y = y + height }

    -- Background based on toggle state
    local bg_color = is_toggled and self._ui.colors.primary_accent or self._ui.colors.checkbox_inactive
    self._ui.window:render_rect_filled(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y },
        bg_color,
        4.0
    )

    -- Render label
    local text_size = self._ui.window:get_text_size(label)
    local text_x = start_pos.x + (width - text_size.x) / 2
    local text_y = start_pos.y + (height - text_size.y) / 2
    self._ui.window:render_text(
        0,
        { x = text_x, y = text_y },
        self._ui.colors.text_primary,
        label
    )

    -- Block dragging
    self._ui.window:is_mouse_hovering_rect_block_movement(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y }
    )

    -- Handle click
    if self._ui.window:is_rect_clicked(
        { x = start_pos.x, y = start_pos.y },
        { x = end_pos.x, y = end_pos.y }
    ) and onclick then
        onclick()
    end

    return end_pos.x + self._button_spacing
end

function Toolbar:_publish_toolbar_event(event_name)
    if self._event_bus and type(self._event_bus.publish) == "function" then
        self._event_bus:publish("toolbar:" .. event_name, {
            source = "toolbar",
            timestamp = core.game_time and core.game_time() or 0
        })
    end
end

function Toolbar:render(window_x, window_y, window_width)
    self._y_offset = window_y + self._padding

    local x = self._padding
    local y = self._y_offset

    -- Save button
    x = self:render_button(x, y, "Save", "Ctrl+S - Save active profile",
        function()
            if self._profile_manager and self._profile_manager.save then
                local profile = self._profile_manager:get_active_profile()
                if profile then
                    self._profile_manager:mark_dirty()
                    -- In real use, this would prompt for path
                end
            end
            self:_publish_toolbar_event("save")
        end
    )

    -- Prepare button (runs the Lua compile pipeline: validate → resolve → merge)
    x = self:render_button(x, y, "Prepare", "Ctrl+Shift+C - Validate, resolve refs, cross-Operation merge",
        function()
            self:_publish_toolbar_event("compile")
        end
    )

    -- Validate button
    x = self:render_button(x, y, "Validate", "Validate profile schema",
        function()
            self:_publish_toolbar_event("validate")
        end
    )

    x = x + 8 -- Extra spacing

    -- Undo button (enabled only when there is something to undo)
    x = self:render_button(x, y, "Undo", "Ctrl+Z - Undo last change",
        function()
            self:_publish_toolbar_event("undo")
        end, false, self._can_undo
    )

    -- Redo button (enabled only when there is something to redo)
    x = self:render_button(x, y, "Redo", "Ctrl+Y - Redo change",
        function()
            self:_publish_toolbar_event("redo")
        end, false, self._can_redo
    )

    x = x + 8

    -- Dry Run toggle
    x = self:render_toggle(x, y, "Dry Run", self._is_dry_run,
        function()
            self._is_dry_run = not self._is_dry_run
            self:_publish_toolbar_event("dry_run_toggle")
        end
    )

    -- Start button
    x = self:render_button(x, y, "Start", "Ctrl+Shift+R - Start runtime",
        function()
            self:_publish_toolbar_event("runtime_start")
        end
    )

    -- Stop button
    x = self:render_button(x, y, "Stop", "Ctrl+Shift+X - Stop runtime",
        function()
            self:_publish_toolbar_event("runtime_stop")
        end
    )

    -- Capture separator
    local sep_x = x
    local sep_width = 4
    local sep_height = self._button_height
    self._ui.window:render_text(
        0,
        { x = sep_x + sep_width, y = y + (height - 10) / 2 },
        self._ui.colors.separator,
        "|"
    )
    x = x + 20

    -- Capture NPC button
    x = self:render_button(x, y, "NPC", "Ctrl+N - Record NPC",
        function()
            self:_publish_toolbar_event("record_npc")
        end
    )

    -- Record Path button
    x = self:render_button(x, y, "Path", "Ctrl+Shift+P - Record Path",
        function()
            self:_publish_toolbar_event("record_path")
        end
    )

    -- Record Area button
    x = self:render_button(x, y, "Area", "Ctrl+Shift+A - Record Area",
        function()
            self:_publish_toolbar_event("record_area")
        end
    )

    -- View dropdown area (span remaining width)
    return y + self._button_height + self._padding * 2
end

function Toolbar:render_panel_dropdown()
    -- Renders a row of compact toggle buttons for each registered panel,
    -- allowing the user to show/hide panels from the toolbar area.
    if not self._window or not self._window._panel_registry then return end

    local panel_names = self._window:get_panel_names()
    if not panel_names or #panel_names == 0 then return end

    -- Use a smaller button size for the panel toggles
    local btn_w = 70
    local btn_h = 20
    local spacing = 4
    local padding = 8
    local x = padding
    local y = self._y_offset + self._button_height + padding + 4

    -- Label
    if self._ui and self._ui.window and self._ui.colors then
        local w = self._ui.window
        local c = self._ui.colors
        local label = "Panels:"
        local label_size = w:get_text_size(label)
        w:render_text(0, { x = x, y = y + (btn_h - label_size.y) / 2 }, c.text_secondary, label)
        x = x + label_size.x + spacing * 2

        -- Sort panel names for stable ordering
        local sorted = {}
        for name in pairs(panel_names) do table.insert(sorted, name) end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
            local panel = self._window._panel_registry:get(name)
            if panel then
                local is_visible = panel.visible
                local bg = is_visible and c.primary_accent or c.checkbox_inactive
                local start_pos = { x = x, y = y }
                local end_pos = { x = x + btn_w, y = y + btn_h }

                w:render_rect_filled(start_pos, end_pos, bg, 3.0)
                w:render_rect(start_pos, end_pos, c.section_border, 3.0, 1.0)

                local text_color = is_visible and { r = 255, g = 255, b = 255, a = 255 } or c.text_secondary
                local text_size = w:get_text_size(name)
                local tx = x + (btn_w - text_size.x) / 2
                local ty = y + (btn_h - text_size.y) / 2
                w:render_text(0, { x = tx, y = ty }, text_color, name)

                w:is_mouse_hovering_rect_block_movement(start_pos, end_pos)

                if w:is_rect_clicked(start_pos, end_pos) then
                    self._window:toggle_panel(name)
                end

                x = x + btn_w + spacing
            end
        end
    end
end

function Toolbar:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function Toolbar:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function Toolbar:shutdown()
    self._ui = nil
    self._window = nil
    self._event_bus = nil
    self._profile_manager = nil
end

return Toolbar