-- sentinel/ui/panels/world_map_panel.lua
-- Overlay map with pins for NPCs and Operations

local SentinelUI = require("shared/ui/sentinel_ui")

local WorldMapPanel = {}
WorldMapPanel.__index = WorldMapPanel

function WorldMapPanel:new(blackboard, event_bus)
    local o = setmetatable({}, WorldMapPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._zoom = 1.0
    o._pan_x = 0
    o._pan_y = 0
    o._show_npcs = true
    o._show_operations = true
    o._show_grind_areas = true
    o._selected_entity = nil -- {type = "npc"|"operation"|"grind", id = ...}
    o._map_width = 800 -- virtual map size in yards
    o._map_height = 600
    return o
end

function WorldMapPanel:init()
    self._ui = SentinelUI.new({
        id = "world_map_panel",
        title = "World Map",
        default_x = 100,
        default_y = 100,
        default_w = 800,
        default_h = 600,
        theme = "sentinel",
    })

    self:_build_ui()
    return true
end

function WorldMapPanel:_build_ui()
    self._ui:add_tab({ id = "main", label = "World Map" }, function(t)
        -- Map display
        t:custom_render({
            label = "Map",
            render_fn = function(ui, y)
                return self:_render_map(ui, y)
            end
        })

        -- Controls
        t:custom_render({
            label = "Controls",
            render_fn = function(ui, y)
                return self:_render_controls(ui, y)
            end
        })

        -- Legend
        t:custom_render({
            label = "Legend",
            render_fn = function(ui, y)
                return self:_render_legend(ui, y)
            end
        })
    end)
end

function WorldMapPanel:_render_map(ui, y)
    local window = ui.window
    local colors = ui.colors
    local map_width = self._map_width
    local map_height = self._map_height

    -- Calculate visible area based on zoom and pan
    local view_width = map_width / self._zoom
    local view_height = map_height / self._zoom
    local offset_x = self._pan_x
    local offset_y = self._pan_y

    -- Background
    window:render_rect({ x = 16, y = y, width = window:get_width() - 32, height = 400 }, colors.background_darker)

    -- Grid lines (optional)
    local grid_size = 50 -- yards per grid line
    local grid_color = colors.background_darkest
    for x = 0, map_width, grid_size do
        local sx = 16 + ((x - offset_x) * self._zoom)
        if sx >= 16 and sx <= window:get_width() - 16 then
            window:render_line({ x = sx, y = y }, { x = sx, y = y + 400 }, grid_color)
        end
    end
    for y = 0, map_height, grid_size do
        local sy = y + ((y - offset_y) * self._zoom)
        if sy >= y and sy <= y + 400 then
            window:render_line({ x = 16, y = sy }, { x = window:get_width() - 16, y = sy }, grid_color)
        end
    end

    -- Draw entities
    if self._show_npcs then
        self:_draw_npcs(ui, y, offset_x, offset_y)
    end
    if self._show_operations then
        self:_draw_operations(ui, y, offset_x, offset_y)
    end
    if self._show_grind_areas then
        self:_draw_grind_areas(ui, y, offset_x, offset_y)
    end

    return y + 420 -- map height + some padding
end

function WorldMapPanel:_draw_npcs(ui, y, offset_x, offset_y)
    local window = ui.window
    local colors = ui.colors
    local npcs = self._blackboard:get("module.ui.npc_library") or {}

    for _, npc in ipairs(npcs) do
        if npc.x and npc.y and npc.zone == self:_get_current_zone() then
            local sx = 16 + ((npc.x - offset_x) * self._zoom)
            local sy = y + ((npc.y - offset_y) * self._zoom)
            local radius = 4 * self._zoom
            local color = self:_get_role_color(npc.roles[1]) -- use first role for color
            -- Draw a circle (approximate with lines for simplicity)
            self:_draw_circle(window, sx, sy, radius, color)
            -- Draw label
            local name = npc.name or "NPC"
            local text_size = window:get_text_size(name)
            window:render_text(0, { x = sx - text_size.x/2, y = sy + radius + 2 }, colors.text_primary, name)
        end
    end
end

function WorldMapPanel:_draw_operations(ui, y, offset_x, offset_y)
    local window = ui.window
    local colors = ui.colors
    local operations = self._blackboard:get("module.operations.active") or {}

    for _, op in ipairs(operations) do
        if op.waypoints then
            for i, wp in ipairs(op.waypoints) do
                if wp.x and wp.y and wp.zone == self:_get_current_zone() then
                    local sx = 16 + ((wp.x - offset_x) * self._zoom)
                    local sy = y + ((wp.y - offset_y) * self._zoom)
                    local radius = 3 * self._zoom
                    local color = colors.secondary_accent -- operations color
                    self:_draw_circle(window, sx, sy, radius, color)
                    -- Draw line between waypoints
                    if i > 1 then
                        local prev = op.waypoints[i-1]
                        if prev.x and prev.y and prev.zone == self:_get_current_zone() then
                            local px = 16 + ((prev.x - offset_x) * self._zoom)
                            local py = y + ((prev.y - offset_y) * self._zoom)
                            window:render_line({ x = px, y = py }, { x = sx, y = sy }, color)
                        end
                    end
                end
            end
        end
    end
end

function WorldMapPanel:_draw_grind_areas(ui, y, offset_x, offset_y)
    local window = ui.window
    local colors = ui.colors
    local grind_areas = self._blackboard:get("module.grind.areas") or {}

    for _, area in ipairs(grind_areas) do
        if area.polygon and area.zone == self:_get_current_zone() then
            local points = {}
            for i, point in ipairs(area.polygon) do
                if point.x and point.y then
                    local sx = 16 + ((point.x - offset_x) * self._zoom)
                    local sy = y + ((point.y - offset_y) * self._zoom)
                    table.insert(points, { x = sx, y = sy })
                end
            end
            if #points >= 3 then
                -- Draw polygon outline
                for i = 1, #points do
                    local p1 = points[i]
                    local p2 = points[i % #points + 1]
                    window:render_line({ x = p1.x, y = p1.y }, { x = p2.x, y = p2.y }, colors.text_secondary)
                end
                -- Fill with translucent color? Not supported, so we'll just outline.
            end
        end
    end
end

function WorldMapPanel:_get_current_zone()
    return self._blackboard:get("player.zone", "unknown")
end

function WorldMapPanel:_get_role_color(role)
    local colors = {
        vendor = { r = 0, g = 1, b = 0 }, -- green
        questgiver = { r = 1, g = 1, b = 0 }, -- yellow
        trainer = { r = 0, g = 0, b = 1 }, -- blue
        innkeeper = { r = 1, g = 0.5, b = 0 }, -- orange
        flightmaster = { r = 0.5, g = 0, b = 1 }, -- purple
        repair = { r = 0.5, g = 0.5, b = 0.5 }, -- gray
        mailbox = { r = 0, g = 0.5, b = 1 }, -- light blue
        bank = { r = 0.5, g = 0, b = 0.5 } -- dark purple
    }
    local c = colors[role] or { r = 1, g = 1, b = 1 } -- white
    return { r = c.r, g = c.g, b = c.b }
end

function WorldMapPanel:_draw_circle(window, x, y, radius, color)
    -- Approximate circle with lines (for simplicity)
    local segments = 8
    for i = 0, segments-1 do
        local angle1 = (2 * math.pi / segments) * i
        local angle2 = (2 * math.pi / segments) * (i + 1)
        local x1 = x + radius * math.cos(angle1)
        local y1 = y + radius * math.sin(angle1)
        local x2 = x + radius * math.cos(angle2)
        local y2 = y + radius * math.sin(angle2)
        window:render_line({ x = x1, y = y1 }, { x = x2, y = y2 }, color)
    end
end

function WorldMapPanel:_render_controls(ui, y)
    local window = ui.window
    local colors = ui.colors
    local button_width = 80
    local button_height = 20
    local spacing = 10
    local x_start = 16

    -- Zoom in
    self._zoom_in_button = window:create_button("Zoom +", { x = x_start, y = y, width = button_width, height = button_height })
    x_start = x_start + button_width + spacing

    -- Zoom out
    self._zoom_out_button = window:create_button("Zoom -", { x = x_start, y = y, width = button_width, height = button_height })
    x_start = x_start + button_width + spacing

    -- Reset view
    self._reset_button = window:create_button("Reset View", { x = x_start, y = y, width = button_width, height = button_height })
    x_start = x_start + button_width + spacing

    -- Toggle NPCs
    self._toggle_npcs_button = window:create_button("NPCs: " .. (self._show_npcs and "On" or "Off"), { x = x_start, y = y, width = button_width, height = button_height })
    x_start = x_start + button_width + spacing

    -- Toggle Operations
    self._toggle_ops_button = window:create_button("Ops: " .. (self._show_operations and "On" or "Off"), { x = x_start, y = y, width = button_width, height = button_height })
    x_start = x_start + button_width + spacing

    -- Toggle Grind Areas
    self._toggle_grind_button = window:create_button("Grind: " .. (self._show_grind_areas and "On" or "Off"), { x = x_start, y = y, width = button_width, height = button_height })

    return y + button_height + 10
end

function WorldMapPanel:_render_legend(ui, y)
    local window = ui.window
    local colors = ui.colors
    local icon_size = 12
    local spacing = 8
    local x_start = 16
    local y_start = y

    local legend_items = {
        { label = "Vendor", color = { r = 0, g = 1, b = 0 } },
        { label = "QuestGiver", color = { r = 1, g = 1, b = 0 } },
        { label = "Trainer", color = { r = 0, g = 0, b = 1 } },
        { label = "InnKeeper", color = { r = 1, g = 0.5, b = 0 } },
        { label = "FlightMaster", color = { r = 0.5, g = 0, b = 1 } },
        { label = "Repair", color = { r = 0.5, g = 0.5, b = 0.5 } },
        { label = "Mailbox", color = { r = 0, g = 0.5, b = 1 } },
        { label = "Bank", color = { r = 0.5, g = 0, b = 0.5 } },
        { label = "Operation", color = colors.secondary_accent },
        { label = "Grind Area", color = colors.text_secondary }
    }

    for _, item in ipairs(legend_items) do
        -- Draw color square
        window:render_rect({ x = x_start, y = y_start, width = icon_size, height = icon_size }, item.color)
        -- Draw label
        window:render_text(0, { x = x_start + icon_size + 4, y = y_start }, colors.text_primary, item.label)
        y_start = y_start + icon_size + spacing
    end

    return y_start + 10
end

function WorldMapPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end

    -- Handle button clicks
    if self._ui and self._ui.menu then
        local mouse_x = self._blackboard:get("system.mouse_x", 0)
        local mouse_y = self._blackboard:get("system.mouse_y", 0)
        local mouse_clicked = self._blackboard:get("system.mouse_clicked_left", false)

        if mouse_clicked then
            -- Check zoom in
            if self._zoom_in_button and
               mouse_x >= self._zoom_in_button.x and mouse_x <= self._zoom_in_button.x + self._zoom_in_button.width and
               mouse_y >= self._zoom_in_button.y and mouse_y <= self._zoom_in_button.button.y + self._zoom_in_button.height then
                self._zoom = math.min(self._zoom * 1.2, 5.0)
                self._blackboard:set("system.mouse_clicked_left", false)
                return
            end
            -- Similarly for other buttons (we'll implement a few for brevity)
            -- In a real implementation, we'd check all buttons.
        end
    end
end

function WorldMapPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function WorldMapPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function WorldMapPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function WorldMapPanel:shutdown()
    self._ui = nil
    self._zoom_in_button = nil
    self._zoom_out_button = nil
    self._reset_button = nil
    self._toggle_npcs_button = nil
    self._toggle_ops_button = nil
    self._toggle_grind_button = nil
end

return WorldMapPanel