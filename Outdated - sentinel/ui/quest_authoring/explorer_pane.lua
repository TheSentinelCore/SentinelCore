-- sentinel/ui/quest_authoring/explorer_pane.lua
-- Left-hand project tree: operations (expandable), action rows, blueprints.
-- Features: sorted deterministic ordering, right-click context menu (New
-- Operation / Rename / Delete), dirty/error status indicators, and
-- drag-of-action reorder.

local Panel = require("ui/quest_authoring/panel")
local Theme = require("ui/quest_authoring/theme")

local ExplorerPane = setmetatable({}, { __index = Panel })
ExplorerPane.__index = ExplorerPane

function ExplorerPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Explorer"), ExplorerPane)
    self._expanded = {}
    self._scroll = { value = 0 }
    self._drag = nil
    self._ctx_menu = nil  -- { x, y, kind, target }
    self._rename_state = nil -- { opName } when renaming
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

-- Sorted key iterator for deterministic order
local function sorted_pairs(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local i = 0
    return function()
        i = i + 1
        if keys[i] then return keys[i], t[keys[i]] end
    end
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

    -- Project name header
    local proj_name = ctx.project.name or "Untitled"
    self:_text(window, x + 8, y + 6, theme.accent, proj_name)
    if ctx:isDirty() then
        self:_text(window, x + 8 + #proj_name * 7 + 4, y + 6, theme.warning, "*")
    end

    -- Toolbar buttons
    local header_y = y + 22
    if self:_button(window, x + 8, header_y, 70, 20, "+ Operation", theme) then
        local n = 1
        while ctx.project.operations["NewOp" .. n] do n = n + 1 end
        ctx:addOperation("NewOp" .. n)
        ctx:select("operation", "NewOp" .. n)
    end

    local content_x = x + 6
    local content_y = header_y + 28
    local row_h = 20
    local pad = self:_begin_scroll(window, x, content_y, w, h - (content_y - y) - 4,
        self:_content_height(), self._scroll, theme)

    local cy = content_y + pad

    -- Operations (sorted)
    for opName, op in sorted_pairs(ctx.project.operations) do
        local sel = ctx.selection.kind == "operation" and ctx.selection.id == opName
        if sel then
            self:_rect(window, content_x, cy, w - 14, row_h, theme.selected, 3.0)
        end
        local expand = self._expanded[opName]
        local toggle = expand and "-" or "+"

        -- Status indicator
        local status = " "
        local ec = op_error_count(ctx, opName)
        if ec > 0 then
            status = "!"
        elseif ctx:isDirty() then
            status = "~"
        end
        local status_col = ec > 0 and theme.red or (ctx:isDirty() and theme.warning or theme.text_dim)
        self:_text(window, content_x + 2, cy + 3, status_col, status)
        self:_text(window, content_x + 14, cy + 3, theme.text, toggle .. " " .. opName)

        -- Error badge
        if ec > 0 then
            self:_rect(window, content_x + w - 38, cy + 3, 16, 14, theme.red, 3.0)
            self:_text(window, content_x + w - 36, cy + 4, Theme.color.white(), tostring(ec))
        end

        if self:_hit(window, content_x, cy, w - 14, row_h) then
            ctx:select("operation", opName)
            -- Right-click = context menu
            if window.is_mouse_button_clicked and window:is_mouse_button_clicked(2) then
                self._ctx_menu = { x = self:_mouse_pos_x(window), y = self:_mouse_pos_y(window),
                                   kind = "operation", target = opName }
            end
            if window.is_mouse_button_pressed and window:is_mouse_button_pressed(0) then
                self._drag = { kind = "operation", opName = opName }
            end
        end
        cy = cy + row_h

        -- Expanded actions
        if expand then
            local acts = op.actions or {}
            for i, action in ipairs(acts) do
                local atype = action.action_type or action.type or "?"
                local asel = ctx.selection.kind == "action"
                    and ctx.selection.opName == opName and ctx.selection.id == i
                if asel then
                    self:_rect(window, content_x + 16, cy, w - 30, row_h, theme.selected, 3.0)
                end

                -- Category color dot
                local cat = Theme.category_for_type(atype)
                local dot_col = theme.text_dim
                if cat == "movement"    then dot_col = theme.cat_movement end
                if cat == "combat"      then dot_col = theme.cat_combat end
                if cat == "interaction" then dot_col = theme.cat_interaction end
                if cat == "quest"       then dot_col = theme.cat_quest end
                self:_rect(window, content_x + 18, cy + 7, 6, 6, dot_col, 3.0)

                local gen = action._debug and action._debug.generated_by and " *" or ""
                self:_text(window, content_x + 28, cy + 3, theme.text_dim,
                    i .. ". " .. atype .. gen)

                if self:_hit(window, content_x + 16, cy, w - 30, row_h) then
                    ctx:select("action", i, { opName = opName })
                    -- Right-click on action
                    if window.is_mouse_button_clicked and window:is_mouse_button_clicked(2) then
                        self._ctx_menu = { x = self:_mouse_pos_x(window), y = self:_mouse_pos_y(window),
                                           kind = "action", target = opName, index = i }
                    end
                    if window.is_mouse_button_pressed and window:is_mouse_button_pressed(0) then
                        self._drag = { kind = "action", opName = opName, index = i }
                    end
                end
                cy = cy + row_h
            end
        end
        cy = cy + 4
    end

    -- Blueprints (sorted)
    if ctx.project.blueprints and next(ctx.project.blueprints) then
        self:_text(window, content_x, cy + 3, theme.accent, "Blueprints")
        cy = cy + row_h
        for bpName, _ in sorted_pairs(ctx.project.blueprints) do
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
    self:_scrollbar(window, x, content_y, w, h - (content_y - y) - 4,
        self:_content_height(), self._scroll, theme)

    self:_handle_drop(window)

    -- ── Context menu (rendered last so it's on top) ─────────────────
    self:_draw_ctx_menu(window, ctx)
end

-- Context menu rendering
function ExplorerPane:_draw_ctx_menu(window, ctx)
    local menu = self._ctx_menu
    if not menu then return end

    local mx, my = menu.x, menu.y
    local mw, mh = 120, 0
    local items = {}

    if menu.kind == "operation" then
        items = {
            { label = "New Operation", action = function()
                local n = 1
                while ctx.project.operations["NewOp" .. n] do n = n + 1 end
                ctx:addOperation("NewOp" .. n)
            end },
            { label = "Rename", action = function()
                self._rename_state = { opName = menu.target }
                self._focused_field = "rename_" .. menu.target
            end },
            { separator = true },
            { label = "Delete", action = function()
                ctx:removeOperation(menu.target)
            end, danger = true },
        }
    elseif menu.kind == "action" then
        items = {
            { label = "Delete Action", action = function()
                ctx:removeAction(menu.target, menu.index)
            end, danger = true },
        }
    end

    mh = #items * 22 + 8
    self:_rect(window, mx, my, mw, mh, Theme.theme.panel_bg, 4.0)
    self:_border(window, mx, my, mw, mh, Theme.theme.panel_border, 4.0)

    local iy = my + 4
    for _, item in ipairs(items) do
        if item.separator then
            self:_rect(window, mx + 4, iy + 10, mw - 8, 1, Theme.theme.panel_border, 0)
            iy = iy + 12
        else
            local col = item.danger and Theme.theme.red or Theme.theme.text
            if self:_hover(window, mx, iy, mw, 20) then
                self:_rect(window, mx + 2, iy, mw - 4, 20, Theme.theme.hover, 2.0)
            end
            self:_text(window, mx + 8, iy + 3, col, item.label)
            if self:_hit(window, mx, iy, mw, 20) then
                item.action()
                self._ctx_menu = nil
            end
            iy = iy + 22
        end
    end

    -- Click outside to close
    if not self:_hover(window, mx, my, mw, mh) and window:is_mouse_button_clicked(0) then
        self._ctx_menu = nil
    end
end

function ExplorerPane:_mouse_pos_x(window)
    local ok, p = pcall(function() return window:get_mouse_pos() end)
    return ok and p and p.x or 0
end
function ExplorerPane:_mouse_pos_y(window)
    local ok, p = pcall(function() return window:get_mouse_pos() end)
    return ok and p and p.y or 0
end

function ExplorerPane:_content_height()
    local n = 0
    local proj = self.ctx.project
    if proj then
        for opName, op in sorted_pairs(proj.operations) do
            n = n + 1
            if self._expanded[opName] then
                n = n + #(op.actions or {})
            end
        end
        if proj.blueprints and next(proj.blueprints) then
            n = n + 1
            for _ in pairs(proj.blueprints) do n = n + 1 end
        end
    end
    return n * 24 + 40
end

function ExplorerPane:_handle_drop(window)
    if not self._drag then return end
    local pressed = window.is_mouse_button_pressed and window:is_mouse_button_pressed(0)
    if pressed then return end

    local d = self._drag
    self._drag = nil
    if d.kind == "action" then
        local sel = self.ctx.selection
        if sel.kind == "action" and sel.opName == d.opName and sel.id ~= d.index then
            self.ctx:moveAction(d.opName, d.index, sel.id)
        end
    end
end

return ExplorerPane
