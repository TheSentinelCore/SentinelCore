-- sentinel/ui/quest_authoring/map_pane.lua
-- Map visualization: shows spawn points, travel paths, and lets the user
-- click to set a target coordinate. Integrates with whatever nav/position
-- source Sylvannas exposes; degrades gracefully when unavailable.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local MapPane = setmetatable({}, { __index = Panel })
MapPane.__index = MapPane

function MapPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Map"), MapPane)
    self._zoom = 1.0
    self._pannable = false
    self._clicked = nil        -- {x, y} world coords from last click
    self._showPaths = true
    self._markers = {}         -- rebuilt each draw from project
    return self
end

-- Try to read player position from the Sylvannas runtime.
local function player_pos()
    local ok, core = pcall(require, "core")
    if ok and core and core.object_manager then
        local p = core.object_manager.get_player and core.object_manager:get_player()
        if p and p.position then return p.position.x, p.position.y, p.position.z end
    end
    return nil
end

-- Collect markers (NPC / object / waypoint) from the project's actions.
local function collect_markers(ctx)
    local markers = {}
    local proj = ctx.project
    if not proj or not proj.operations then return markers end
    for _oid, op in pairs(proj.operations) do
        if op.actions then
            for _k, act in ipairs(op.actions) do
                local coord = act.args and (act.args.coord or act.args.target)
                if coord and coord.x then
                    table.insert(markers, {
                        x = coord.x, y = coord.y, z = coord.z,
                        label = act.name or act.action_type,
                        kind = act.action_type or "?",
                    })
                end
            end
        end
    end
    return markers
end

function MapPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8

    -- Header / toggles
    w:render_text(px + pad, py + 22, "Quest Map", Theme.colors.text)
    if w:is_rect_clicked(px + pw - 90, py + 18, 80, 18) then
        self._showPaths = not self._showPaths
    end
    w:render_rect_filled(px + pw - 90, py + 18, 80, 18, Theme.colors.button)
    w:render_text(px + pw - 86, py + 21, self._showPaths and "Paths: ON" or "Paths: OFF", Theme.colors.text)

    -- Map area
    local mx, my = px + pad, py + 44
    local mw, mh = pw - pad * 2, ph - 52
    if mw < 40 then mw = 40 end
    if mh < 40 then mh = 40 end

    w:render_rect_filled(mx, my, mw, mh, Theme.colors.bg_alt)
    -- Border
    w:render_rect(mx, my, mw, mh, Theme.colors.border)

    -- Scale: map world coords (assume range ~ -2000..2000) into the rect.
    local span = 4000 / self._zoom
    local function to_screen(wx, wy)
        local cx, cy = mx + mw / 2, my + mh / 2
        return cx + (wx / span) * (mw / 2), cy - (wy / span) * (mh / 2)
    end

    -- Grid
    for g = -2, 2 do
        local gx = mx + mw / 2 + (g / 2) * (mw / 2)
        w:render_rect(gx, my, 1, mh, Theme.colors.grid)
        local gy = my + mh / 2 + (g / 2) * (mh / 2)
        w:render_rect(mx, gy, mw, 1, Theme.colors.grid)
    end

    -- Player position
    local plx, ply = player_pos()
    if plx then
        local sx, sy = to_screen(plx, ply)
        w:render_rect_filled(sx - 4, sy - 4, 8, 8, Theme.colors.player)
        w:render_text(sx + 6, sy - 6, "You", Theme.colors.text)
    end

    -- Markers
    self._markers = collect_markers(ctx)
    for _i, m in ipairs(self._markers) do
        local sx, sy = to_screen(m.x, m.y)
        local col = Theme.colors.marker
        if m.kind == "InteractNPC" then col = Theme.colors.marker_npc end
        w:render_rect_filled(sx - 3, sy - 3, 6, 6, col)
        if w:is_mouse_hovering_rect(sx - 3, sy - 3, 6, 6) then
            w:render_text(sx + 8, sy - 6, m.label, Theme.colors.tooltip_text)
        end
        -- Path from player to marker
        if self._showPaths and plx then
            local psx, psy = to_screen(plx, ply)
            w:render_rect(math.min(psx, sx), math.min(psy, sy), 1, 1, Theme.colors.path)
        end
    end

    -- Click to set waypoint
    if w:is_mouse_button_pressed(0) and w:is_mouse_hovering_rect(mx, my, mw, mh) then
        local mpos = w:get_mouse_pos()
        local cx, cy = mx + mw / 2, my + mh / 2
        local wx = ((mpos.x - cx) / (mw / 2)) * span
        local wy = -((mpos.y - cy) / (mh / 2)) * span
        self._clicked = { x = wx, y = wy }
        if ctx.onMapClick then ctx:onMapClick(self._clicked) end
    end

    -- Footer status
    if self._clicked then
        w:render_text(px + pad, py + ph - 18,
            string.format("Waypoint: %.0f, %.0f", self._clicked.x, self._clicked.y),
            Theme.colors.text_dim)
    else
        w:render_text(px + pad, py + ph - 18, "Click map to set waypoint", Theme.colors.text_dim)
    end
end

return MapPane
