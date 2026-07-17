-- sentinel/ui/quest_authoring/hot_reload.lua
-- Hot-reload control pane. Triggers a recompile + executor hot-swap when the
-- project changes, with debounce, status feedback, and timing.
--
-- In-game there is no filesystem watcher; init.lua wires ctx._reload_fn to a
-- function that re-parses the source path (or recompiles the in-memory model)
-- and pushes the result back via ctx:reload(). This pane just drives it.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local HotReloadPane = setmetatable({}, { __index = Panel })
HotReloadPane.__index = HotReloadPane

function HotReloadPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "HotReload"), HotReloadPane)
    self._auto = false
    self._lastMs = 0
    self._status = "idle"   -- idle | reloading | ok | error
    self._debounceMs = 500
    self._lastDirtyT = 0
    return self
end

local function now_ms(ctx)
    if ctx._getTime then return ctx:_getTime() end
    if os and os.clock then return os.clock() * 1000 end
    return 0
end

-- Perform the reload through the wired callback.
function HotReloadPane:_doReload()
    local ctx = self.ctx
    self._status = "reloading"
    local t0 = now_ms(ctx)
    local ok, err = pcall(function()
        if ctx._reload_fn then ctx._reload_fn() end
    end)
    local t1 = now_ms(ctx)
    self._lastMs = (t1 - t0)
    self._status = ok and "ok" or "error"
    if not ok and ctx.logError then
        ctx:logError("hot_reload: " .. tostring(err))
    end
    -- reset debounce clock
    self._lastDirtyT = t1
end

function HotReloadPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local cy = py + 24

    -- Auto toggle
    w:render_rect_filled(px + pad, cy, 90, 20, self._auto and Theme.colors.button_hover or Theme.colors.button)
    w:render_text(px + pad + 6, cy + 3, self._auto and "Auto: ON" or "Auto: OFF", Theme.colors.text)
    if w:is_rect_clicked(px + pad, cy, 90, 20) then self._auto = not self._auto end

    -- Manual reload
    if w:is_rect_clicked(px + pad + 100, cy, 100, 20) then self:_doReload() end
    w:render_rect_filled(px + pad + 100, cy, 100, 20, Theme.colors.button)
    w:render_text(px + pad + 106, cy + 3, "Reload Now", Theme.colors.text)

    cy = cy + 30

    -- Status line
    local status_col = self._status == "error" and Theme.colors.red
        or self._status == "ok" and (Theme.colors.green or Theme.colors.text)
        or self._status == "reloading" and Theme.colors.warning
        or Theme.colors.text_dim
    w:render_text(px + pad, cy, "Status: " .. self._status, status_col)
    cy = cy + 18
    w:render_text(px + pad, cy, string.format("Last reload: %.0f ms", self._lastMs), Theme.colors.text_dim)
    cy = cy + 18

    -- Auto-mode: debounce on dirty
    if self._auto then
        if ctx:isDirty() then
            local t = now_ms(ctx)
            if self._lastDirtyT == 0 then self._lastDirtyT = t end
            if (t - self._lastDirtyT) >= self._debounceMs then
                self:_doReload()
            end
        else
            self._lastDirtyT = 0
        end
        w:render_text(px + pad, cy, "Auto: watching dirty flag", Theme.colors.text_dim)
    end
end

return HotReloadPane
