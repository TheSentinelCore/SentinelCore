-- sentinel/ui/quest_authoring/map_pane.lua
-- Map visualization: labeled coordinate grid, operation markers with labels,
-- marker click-to-select, player position, travel paths, and zoom/scroll.

local Panel = require("ui/quest_authoring/panel")
local Theme = require("ui/quest_authoring/theme")

local MapPane = setmetatable({}, { __index = Panel })
MapPane.__index = MapPane

function MapPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Map"), MapPane)
    self._zoom = 1.0
    self._showPaths = true
    self._showLabels = true
    self._markers = {}
    self._scroll = { value = 0 }
    return self
end

local function player_pos()
    local ok, core = pcall(require, "core")
    if ok and core and core.object_manager then
        local p = core.object_manager.get_player and core.object_manager:get_player()
        if p and p.position then return p.position.x, p.position.y, p.position.z end
    end
    return nil
end

-- Collect markers from all operations, tagged with opName and action index.
local function collect_markers(ctx)
    local markers = {}
    local proj = ctx.project
    if not proj or not proj.operations then return markers end
    for oid, op in pairs(proj.operations) do
        if op.actions then
            for i, act in ipairs(op.actions) do
                local args = act.args or {}
                -- Check common coordinate fields
                local coord = args.target or args.coord
                -- Also check Marker action fields
                if args.x and args.y then
                    coord = { x = args.x, y = args.y, z = args.z }
                end
                if coord and coord.x then
                    local cat = Theme.category_for_type(act.action_type or act.type)
                    local col_key = "marker"
                    if cat == "combat" then col_key = "cat_combat"
                    elseif cat == "movement" then col_key = "cat_movement"
                    elseif cat == "quest" then col_key = "cat_quest" end
                    markers[#markers + 1] = {
                        x = coord.x, y = coord.y, z = coord.z,
                        label = (act.action_type or act.type or "?") .. " " .. (args.npc_name or args.creature_name or args.item_name or ""),
                        opName = oid, actionIndex = i,
                        color_key = col_key,
                    }
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
    local theme = Theme.theme

    -- Header / toggles
    self:_text(w, px + pad, py + 6, theme.text, "Map")

    -- Toggle buttons
    if self:_button(w, px + pw - 180, py + 4, 54, 18,
        self._showLabels and "Labels" or "NoLbl", theme) then
        self._showLabels = not self._showLabels
    end
    if self:_button(w, px + pw - 120, py + 4, 54, 18,
        self._showPaths and "Paths" or "NoPath", theme) then
        self._showPaths = not self._showPaths
    end
    if self:_button(w, px + pw - 60, py + 4, 50, 18, "Zoom+", theme) then
        self._zoom = math.min(5.0, self._zoom * 1.3)
    end
    if self:_button(w, px + pw - 60, py + 22, 50, 18, "Zoom-", theme) then
        self._zoom = math.max(0.2, self._zoom / 1.3)
    end

    -- Map area
    local mx, my = px + pad, py + 44
    local mw, mh = pw - pad * 2, ph - 52
    if mw < 40 then mw = 40 end
    if mh < 40 then mh = 40 end

    self:_rect(w, mx, my, mw, mh, theme.panel_bg, 0)
    self:_border(w, mx, my, mw, mh, theme.panel_border, 0, 1.0)

    -- Scale: map world coords (assume range ~ -2000..2000) into the rect.
    local span = 4000 / self._zoom
    local function to_screen(wx, wy)
        local cx, cy = mx + mw / 2, my + mh / 2
        return cx + (wx / span) * (mw / 2), cy - (wy / span) * (mh / 2)
    end
    local function from_screen(sx, sy)
        local cx, cy = mx + mw / 2, my + mh / 2
        return ((sx - cx) / (mw / 2)) * span, -((sy - cy) / (mh / 2)) * span
    end

    -- Labeled coordinate grid
    local grid_step = 200
    if self._zoom > 2 then grid_step = 100 end
    if self._zoom > 4 then grid_step = 50 end
    if self._zoom < 0.5 then grid_step = 500 end

    for gx = -2000, 2000, grid_step do
        local sx = select(1, to_screen(gx, 0))
        if sx >= mx and sx <= mx + mw then
            self:_rect(w, sx, my, 1, mh, theme.grid, 0, 1.0)
            if self._showLabels then
                self:_text(w, sx + 2, my + mh - 12, theme.text_dim, tostring(gx))
            end
        end
    end
    for gy = -2000, 2000, grid_step do
        local sy = select(2, to_screen(0, gy))
        if sy >= my and sy <= my + mh then
            self:_rect(w, mx, sy, mw, 1, theme.grid, 0, 1.0)
            if self._showLabels then
                self:_text(w, mx + 2, sy - 10, theme.text_dim, tostring(gy))
            end
        end
    end

    -- Player position
    local plx, ply = player_pos()
    if plx then
        local sx, sy = to_screen(plx, ply)
        self:_rect(w, sx - 4, sy - 4, 8, 8, theme.green, 4.0)
        self:_text(w, sx + 6, sy - 6, theme.text, string.format("You (%.0f, %.0f)", plx, ply))
    end

    -- Markers from project actions
    self._markers = collect_markers(ctx)
    for _i, m in ipairs(self._markers) do
        local sx, sy = to_screen(m.x, m.y)
        local col = theme[m.color_key] or theme.marker
        local is_selected = (ctx.selection and ctx.selection.kind == "action"
            and ctx.selection.opName == m.opName and ctx.selection.id == m.actionIndex)
        local dot_r = is_selected and 5 or 3
        self:_rect(w, sx - dot_r, sy - dot_r, dot_r * 2, dot_r * 2, col, 4.0)

        -- Label
        if self._showLabels then
            self:_text(w, sx + 6, sy - 6, theme.text, m.label)
        end

        -- Hover tooltip
        if self:_hover(w, sx - 5, sy - 5, 10, 10) then
            self:_text(w, sx + 6, sy + 6, theme.accent,
                string.format("(%d, %d) %s", m.x, m.y, m.label))
        end

        -- Click to select the action
        if self:_hit(w, sx - 5, sy - 5, 10, 10) then
            ctx:select("action", m.actionIndex, { opName = m.opName })
        end

        -- Path from player to marker
        if self._showPaths and plx then
            local psx, psy = to_screen(plx, ply)
            -- Draw a line by drawing small dots along the path
            local dx, dy = sx - psx, sy - psy
            local dist = math.sqrt(dx * dx + dy * dy)
            local steps = math.max(1, math.floor(dist / 4))
            for s = 0, steps do
                local t = s / steps
                local lx = psx + dx * t
                local ly = psy + dy * t
                self:_rect(w, lx, ly, 2, 2, theme.path, 1.0)
            end
        end
    end

    -- Click to set waypoint (right-click or left-click on empty area)
    if self:_hit(w, mx, my, mw, mh) then
        local mpos = w.get_mouse_pos and w:get_mouse_pos()
        if mpos then
            local wx, wy = from_screen(mpos.x, mpos.y)
            self._clicked = { x = wx, y = wy }
            if ctx.onMapClick then ctx:onMapClick(self._clicked) end
        end
    end

    -- Zoom via wheel
    local wheel = w.get_mouse_wheel and w:get_mouse_wheel() or 0
    if wheel ~= 0 and self:_hover(w, mx, my, mw, mh) then
        self._zoom = math.max(0.2, math.min(5.0, self._zoom * (1 + wheel * 0.1)))
    end

    -- Footer status
    if self._clicked then
        self:_text(w, px + pad, py + ph - 14, theme.text_dim,
            string.format("Waypoint: %.0f, %.0f", self._clicked.x, self._clicked.y))
    else
        self:_text(w, px + pad, py + ph - 14, theme.text_dim, "Click map to set waypoint")
    end

    -- Operation filter (show markers for selected operation only)
    if ctx.selection and ctx.selection.kind == "operation" then
        self:_text(w, px + pad + 200, py + ph - 14, theme.accent,
            "Showing: " .. ctx.selection.id)
    end
end

return MapPane
