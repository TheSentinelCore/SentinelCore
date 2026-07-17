-- sentinel/ui/quest_authoring/timeline_pane.lua
-- Horizontal timeline of operations. Each operation is a block whose width is
-- proportional to its action count. Color-coded by dominant action category,
-- clickable to select, wheel to zoom.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local TimelinePane = setmetatable({}, { __index = Panel })
TimelinePane.__index = TimelinePane

function TimelinePane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Timeline"), TimelinePane)
    self._zoom = 1.0
    self._scrollX = 0
    return self
end

local function dominant_category(op)
    if not op or not op.actions then return nil end
    local counts = {}
    for _k, a in ipairs(op.actions) do
        local cat = Theme.category_for_type(a.action_type)
        counts[cat] = (counts[cat] or 0) + 1
    end
    local best, bestN = nil, 0
    for cat, n in pairs(counts) do
        if n > bestN then best, bestN = cat, n end
    end
    return best
end

function TimelinePane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8

    w:render_text(px + pad, py + 22, "Timeline", Theme.colors.text)

    local proj = ctx.project
    if not proj or not proj.operations then
        w:render_text(px + pad, py + 44, "No operations", Theme.colors.text_dim)
        return
    end

    -- Zoom via wheel
    local wheel = w.get_mouse_wheel and w:get_mouse_wheel() or 0
    if wheel ~= 0 then self._zoom = math.max(0.3, math.min(3.0, self._zoom - wheel * 0.1)) end

    local unit = 24 * self._zoom
    local ly = py + 50
    local laneH = 26
    local totalW = 0

    for oid, op in pairs(proj.operations) do
        local n = op.actions and #op.actions or 0
        local bw = math.max(unit, n * unit)
        local bx = px + pad + totalW - self._scrollX
        totalW = totalW + bw + 6

        -- Off-screen cull
        if bx + bw > px + pad and bx < px + pw then
            local cat = dominant_category(op)
            local col = Theme.colors.timeline_block
            if cat == "movement" then col = Theme.colors.cat_movement
            elseif cat == "combat" then col = Theme.colors.cat_combat
            elseif cat == "interaction" then col = Theme.colors.cat_interaction
            elseif cat == "quest" then col = Theme.colors.cat_quest end

            local selected = (ctx.selection and ctx.selection.kind == "operation" and ctx.selection.id == oid)
            w:render_rect_filled(bx, ly, bw, laneH, selected and Theme.colors.timeline_sel or col)
            w:render_rect(bx, ly, bw, laneH, Theme.colors.border)
            w:render_text(bx + 4, ly + 6, (op.name or oid) .. " (" .. n .. ")", Theme.colors.text)

            if w:is_rect_clicked(bx, ly, bw, laneH) then
                ctx:select("operation", oid)
            end
        end
    end

    -- Scroll hint
    if self._scrollX ~= 0 then
        w:render_text(px + pad, py + ph - 18, "scroll> " .. math.floor(self._scrollX), Theme.colors.text_dim)
    end
end

return TimelinePane
