-- sentinel/ui/quest_authoring/world_selection.lua
-- In-game world selector: pick NPCs/objects in the world to populate action
-- fields, filter by zone, estimate travel time, and jump to a location.
--
-- The actual in-world picking is wired by init.lua via ctx._pick_fn (starts a
-- pick mode that fills ctx._pendingPick) and ctx._jump_fn(target). This pane is
-- the orchestration surface.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local WorldSelectionPane = setmetatable({}, { __index = Panel })
WorldSelectionPane.__index = WorldSelectionPane

function WorldSelectionPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "WorldSel"), WorldSelectionPane)
    self._zoneFilter = nil
    self._picking = false
    return self
end

local function cur_zone(ctx)
    local ok, core = pcall(require, "core")
    if ok and core and core.object_manager then
        local p = core.object_manager.get_player and core.object_manager:get_player()
        if p and p.zone then return p.zone end
    end
    return ctx._currentZone or "Unknown"
end

local function travel_estimate(ctx, target)
    local ok, core = pcall(require, "core")
    if ok and core and core.object_manager then
        local p = core.object_manager.get_player and core.object_manager:get_player()
        if p and p.position and target and target.x then
            local d = math.sqrt((p.position.x - target.x) ^ 2 + (p.position.y - target.y) ^ 2)
            return math.max(1, math.floor(d / 7)) .. "s (walking @7yd/s)"
        end
    end
    return "n/a"
end

function WorldSelectionPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local cy = py + 24

    w:render_text(px + pad, cy, "Zone: " .. cur_zone(ctx), Theme.colors.text)
    cy = cy + 22

    -- Pick-in-world button (polls for a newly targeted unit)
    w:render_rect_filled(px + pad, cy, 120, 20, self._picking and Theme.colors.button_hover or Theme.colors.button)
    w:render_text(px + pad + 6, cy + 3, self._picking and "Picking..." or "Pick in World", Theme.colors.text)
    if w:is_rect_clicked(px + pad, cy, 120, 20) then
        self._picking = not self._picking
        if ctx._pick_fn then ctx:_pick_fn(self._picking) end
    end

    -- Pick Target button (captures the unit you currently have targeted)
    w:render_rect_filled(px + pad + 130, cy, 120, 20, Theme.colors.button)
    w:render_text(px + pad + 136, cy + 3, "Pick Target", Theme.colors.text)
    if w:is_rect_clicked(px + pad + 130, cy, 120, 20) then
        if ctx._tryPickTarget then ctx:_tryPickTarget() end
    end
    cy = cy + 28

    -- Pending pick result
    if ctx._pendingPick then
        local pk = ctx._pendingPick
        w:render_text(px + pad, cy, "Picked: " .. tostring(pk.name or pk.type or "?"), Theme.colors.accent)
        cy = cy + 18
        w:render_text(px + pad, cy, "Travel: " .. travel_estimate(ctx, pk), Theme.colors.text_dim)
        cy = cy + 18
        if w:is_rect_clicked(px + pad, cy, 120, 20) then
            if ctx._jump_fn then ctx:_jump_fn(pk) end
        end
        w:render_rect_filled(px + pad, cy, 120, 20, Theme.colors.button)
        w:render_text(px + pad + 6, cy + 3, "Jump to", Theme.colors.text)
        cy = cy + 28
    else
        w:render_text(px + pad, cy, "No selection from world", Theme.colors.text_dim)
        cy = cy + 22
    end

    -- Zone filter (simple toggle list placeholder)
    w:render_text(px + pad, cy, "Zone filter: " .. (self._zoneFilter or "all"), Theme.colors.text_dim)
    cy = cy + 20
    if w:is_rect_clicked(px + pad, cy, 80, 18) then
        self._zoneFilter = self._zoneFilter and nil or "current"
    end
    w:render_rect_filled(px + pad, cy, 80, 18, Theme.colors.button)
    w:render_text(px + pad + 6, cy + 2, "Toggle", Theme.colors.text)
end

return WorldSelectionPane
