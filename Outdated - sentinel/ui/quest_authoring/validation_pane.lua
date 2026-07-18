-- sentinel/ui/quest_authoring/validation_pane.lua
-- Surfaces all compiler errors/warnings with severity filtering,
-- click-to-source navigation (action-level), scrollable list, and
-- pass-origin indicators.

local Panel = require("ui/quest_authoring/panel")
local Theme = require("ui/quest_authoring/theme")

local ValidationPane = setmetatable({}, { __index = Panel })
ValidationPane.__index = ValidationPane

function ValidationPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Validation"), ValidationPane)
    self._showErr = true
    self._showWarn = true
    self._showInfo = true
    self._scroll = { value = 0 }
    return self
end

function ValidationPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local theme = Theme.theme
    local cy = py + 24

    local res = ctx.compileResult
    local errs = res and res.errors or {}

    -- Count by severity
    local nErr, nWarn, nInfo = 0, 0, 0
    for _i, e in ipairs(errs) do
        if e.severity == "warning" then nWarn = nWarn + 1
        elseif e.severity == "info" then nInfo = nInfo + 1
        else nErr = nErr + 1 end
    end

    -- Summary
    self:_text(w, px + pad, cy, string.format("E:%d  W:%d", nErr, nWarn),
        nErr > 0 and theme.red or (nWarn > 0 and theme.warning or theme.green))
    cy = cy + 16

    -- Filter toggles
    local function toggle(x, label, state, col)
        local bg = state and col or theme.button
        self:_rect(w, x, cy, 54, 16, bg, 3.0)
        self:_text(w, x + 4, cy + 1, state and theme.text or theme.text_dim, label)
        if self:_hit(w, x, cy, 54, 16) then return true end
        return false
    end
    if toggle(px + pad, "Err", self._showErr, theme.red) then self._showErr = not self._showErr end
    if toggle(px + pad + 58, "Warn", self._showWarn, theme.warning) then self._showWarn = not self._showWarn end
    if toggle(px + pad + 116, "Info", self._showInfo, theme.accent) then self._showInfo = not self._showInfo end
    cy = cy + 22

    -- Build filtered list
    local filtered = {}
    for _i, e in ipairs(errs) do
        local show = false
        if e.severity == "warning" and self._showWarn then show = true end
        if e.severity == "info" and self._showInfo then show = true end
        if not e.severity or e.severity == "error" then
            if self._showErr then show = true end
        end
        if show then filtered[#filtered + 1] = e end
    end

    -- Scrollable error list
    local row_h = 26
    local content_h = #filtered * row_h
    local scroll_area_h = ph - (cy - py) - 4
    if scroll_area_h < 40 then scroll_area_h = 40 end
    local pad2 = self:_begin_scroll(w, px, cy, pw, scroll_area_h,
        content_h, self._scroll, theme)
    local ry = cy + pad2

    for _i, e in ipairs(filtered) do
        local isErr = (e.severity ~= "warning" and e.severity ~= "info")
        local isWarn = (e.severity == "warning")
        local col = isErr and theme.red or (isWarn and theme.warning or theme.accent)

        -- Row background
        self:_rect(w, px + pad, ry, pw - pad * 2, row_h - 2, theme.panel_bg, 2.0)
        self:_border(w, px + pad, ry, pw - pad * 2, row_h - 2, col, 2.0, 1.0)

        -- Severity indicator
        local sev_char = isErr and "!" or (isWarn and "?" or "i")
        self:_text(w, px + pad + 3, ry + 2, col, sev_char)

        -- Message
        local msg = (e.message or "?"):sub(1, 45)
        self:_text(w, px + pad + 14, ry + 2, theme.text, msg)

        -- Source location with action-level click-to-source
        local where = ""
        if e.operation then
            where = e.operation
            if e.action_index then
                where = where .. "#" .. e.action_index
            end
        else
            where = "project"
        end
        self:_text(w, px + pad + 14, ry + 14, theme.text_dim, where)

        -- Pass indicator
        if e.pass then
            self:_text(w, px + pw - pad - 20, ry + 2, theme.text_dim, "P" .. e.pass)
        end

        -- Click to navigate
        if self:_hit(w, px + pad, ry, pw - pad * 2, row_h - 2) then
            if e.operation then
                if e.action_index then
                    -- Action-level click-to-source
                    ctx:select("action", e.action_index, { opName = e.operation })
                else
                    ctx:select("operation", e.operation)
                end
            else
                ctx:select("project")
            end
        end

        ry = ry + row_h
    end

    self:_end_scroll(w)

    if #filtered == 0 then
        if #errs == 0 then
            self:_text(w, px + pad, cy, theme.green, "No issues - compiles cleanly")
        else
            self:_text(w, px + pad, cy, theme.text_dim, "All filtered out")
        end
    end

    -- Scrollbar
    if content_h > scroll_area_h then
        self:_scrollbar(w, px, cy, pw, scroll_area_h, content_h, self._scroll, theme)
    end
end

return ValidationPane
