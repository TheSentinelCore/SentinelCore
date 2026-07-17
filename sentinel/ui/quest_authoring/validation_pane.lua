-- sentinel/ui/quest_authoring/validation_pane.lua
-- Surfaces all compiler errors/warnings with severity filtering and
-- click-to-source navigation.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local ValidationPane = setmetatable({}, { __index = Panel })
ValidationPane.__index = ValidationPane

function ValidationPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Validation"), ValidationPane)
    self._showErr = true
    self._showWarn = true
    self._scroll = 0
    return self
end

function ValidationPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local cy = py + 24

    local res = ctx.compileResult
    local errs = res and res.errors or {}

    -- Severity summary
    local nErr, nWarn = 0, 0
    for _i, e in ipairs(errs) do
        if e.severity == "warning" then nWarn = nWarn + 1 else nErr = nErr + 1 end
    end
    w:render_text(px + pad, cy, string.format("Errors: %d   Warnings: %d", nErr, nWarn), Theme.colors.text)
    cy = cy + 20

    -- Filter toggles
    local function toggle(x, label, state, key)
        w:render_rect_filled(x, cy, 70, 18, state and Theme.colors.button_hover or Theme.colors.button)
        w:render_text(x + 6, cy + 2, label, Theme.colors.text)
        if w:is_rect_clicked(x, cy, 70, 18) then self[key] = not self[key] end
    end
    toggle(px + pad, "Errors", self._showErr, "_showErr")
    toggle(px + pad + 80, "Warnings", self._showWarn, "_showWarn")
    cy = cy + 26

    -- List
    local content_y = cy
    local row_h = 28
    for _i, e in ipairs(errs) do
        local isErr = (e.severity ~= "warning")
        if (isErr and self._showErr) or (not isErr and self._showWarn) then
            local col = isErr and Theme.colors.red or Theme.colors.warning
            w:render_rect_filled(px + pad, content_y, pw - pad * 2, row_h - 4, Theme.colors.bg_alt)
            w:render_rect(px + pad, content_y, pw - pad * 2, row_h - 4, col)
            local msg = (e.message or "?"):sub(1, 50)
            w:render_text(px + pad + 4, content_y + 2, msg, Theme.colors.text)
            local where = e.operation and ("@" .. tostring(e.operation) ..
                (e.action_index and ("#" .. e.action_index) or "")) or "project"
            w:render_text(px + pad + 4, content_y + 15, where, Theme.colors.text_dim)
            if w:is_rect_clicked(px + pad, content_y, pw - pad * 2, row_h - 4) and e.operation then
                ctx:select("operation", e.operation)
            end
            content_y = content_y + row_h
        end
    end

    if #errs == 0 then
        w:render_text(px + pad, cy, "No issues - profile compiles cleanly.", Theme.colors.green or Theme.colors.text)
    end
end

return ValidationPane
