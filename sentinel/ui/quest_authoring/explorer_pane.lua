-- sentinel/ui/quest_authoring/explorer_pane.lua
-- Left-hand project tree: operations (expandable), action rows, blueprints.
-- Shows error badges, supports add-operation, expand/collapse, selection, and
-- drag-of-action reorder.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local ExplorerPane = setmetatable({}, { __index = Panel })
ExplorerPane.__index = ExplorerPane

function ExplorerPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Explorer"), ExplorerPane)
    self._expanded = {}
    self._scroll = { value = 0 }
    self._drag = nil
    return self
end

local function op_error_count(ctx, opName)
    local n = 0
    local res = ctx.compileResult
    if not res or not res.errors then return 0 end
    for _i, e in ipairs(res.errors) do
        if e.operation == opName then n = n + 1 end
    end
    return n
end

function ExplorerPane:draw()
    Panel.draw(self)
    local ctx = self.ctx
    local window = self.window
    if not window then return end
    local x, y, w, h = self._x, self._y, self._w, self._h
    local theme = Theme.theme

    if not ctx.project then
        self:_text(window, x + 8, y + 28, theme.text_dim, "(no project loaded)")
        return
    end

    local header_y = y + 22
    if self:_button(window, x + 8, header_y, 70, 20, "+ Operation", theme) then
        ctx:addOperation("NewOperation" .. tostring(#ctx.project.operations + 1))
    end

    local content_x = x + 6
    local content_y = header_y + 28
    local row_h = 20
    local pad = self:_begin_scroll(window, x, content_y, w, h - (content_y - y) - 4, self:_content_height(), self._scroll, theme)

    local cy = content_y + pad
    local ops = ctx.project.operations

    for opName, op in pairs(ops) do
        local sel = ctx.selection.kind == "operation" and ctx.selection.id == opName
        if sel then
            self:_rect(window, content_x, cy, w - 14, row_h, theme.selected, 3.0)
        end
        local expand = self._expanded[opName]
        local toggle = expand and "-" or "+"
        self:_text(window, content_x, cy + 3, theme.text, toggle .. " " .. opName)
        local ec = op_error_count(ctx, opName)
        if ec > 0 then
            self:_rect(window, content_x + w - 60, cy + 3, 16, 14, theme.red, 3.0)
            self:_text(window, content_x + w - 58, cy + 4, Theme.color.white(), tostring(ec))
        end
        if self:_hit(window, content_x, cy, w - 14, row_h) then
            ctx:select("operation", opName)
            if window.is_mouse_button_pressed and window:is_mouse_button_pressed(0) then
                self._drag = { kind = "operation", opName = opName }
            end
        end
        cy = cy + row_h

        if expand then
            local acts = op.actions or {}
            for i, action in ipairs(acts) do
                local atype = action.action_type or action.type or "?"
                local asel = ctx.selection.kind == "action" and ctx.selection.opName == opName and ctx.selection.id == i
                if asel then
                    self:_rect(window, content_x + 16, cy, w - 30, row_h, theme.selected, 3.0)
                end
                local gen = action._debug and action._debug.generated_by and " *" or ""
                self:_text(window, content_x + 18, cy + 3, theme.text_dim, "  " .. i .. ". " .. atype .. gen)
                if self:_hit(window, content_x + 16, cy, w - 30, row_h) then
                    ctx:select("action", i, { opName = opName })
                    if window.is_mouse_button_pressed and window:is_mouse_button_pressed(0) then
                        self._drag = { kind = "action", opName = opName, index = i }
                    end
                end
                cy = cy + row_h
            end
        end
        cy = cy + 4
    end

    if ctx.project.blueprints then
        self:_text(window, content_x, cy + 3, theme.accent, "Blueprints")
        cy = cy + row_h
        for bpName, _ in pairs(ctx.project.blueprints) do
            local bsel = ctx.selection.kind == "blueprint" and ctx.selection.id == bpName
            if bsel then
                self:_rect(window, content_x, cy, w - 14, row_h, theme.selected, 3.0)
            end
            self:_text(window, content_x + 4, cy + 3, theme.text_dim, bpName)
            if self:_hit(window, content_x, cy, w - 14, row_h) then
                ctx:select("blueprint", bpName)
            end
            cy = cy + row_h
        end
    end

    self:_end_scroll(window)
    self:_scrollbar(window, x, content_y, w, h - (content_y - y) - 4, self:_content_height(), self._scroll, theme)

    self:_handle_drop(window, ops)
end

function ExplorerPane:_content_height()
    local n = 0
    local proj = self.ctx.project
    if proj then
        for opName, op in pairs(proj.operations) do
            n = n + 1
            if self._expanded[opName] then
                n = n + #(op.actions or {})
            end
        end
        if proj.blueprints then
            n = n + 1
            for _ in pairs(proj.blueprints) do n = n + 1 end
        end
    end
    return n * 24 + 40
end

function ExplorerPane:_handle_drop(window, ops)
    if not self._drag then return end
    local pressed = window.is_mouse_button_pressed and window:is_mouse_button_pressed(0)
    if pressed then return end

    local d = self._drag
    self._drag = nil
    if d.kind == "operation" then
        -- Operation-level positional DnD is not wired in v1; the source row is
        -- simply deselected. (Future: hit-test a target row and call a
        -- ctx:moveOperation helper.)
    elseif d.kind == "action" then
        local sel = self.ctx.selection
        if sel.kind == "action" and sel.opName == d.opName and sel.id ~= d.index then
            self.ctx:moveAction(d.opName, d.index, sel.id)
        end
    end
end

return ExplorerPane
