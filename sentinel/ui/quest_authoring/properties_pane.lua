-- sentinel/ui/quest_authoring/properties_pane.lua
-- Context-sensitive properties editor for the current selection. Shows editable
-- metadata, allows reordering/deleting actions, and surfaces validation
-- messages scoped to the selection.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local PropertiesPane = setmetatable({}, { __index = Panel })
PropertiesPane.__index = PropertiesPane

function PropertiesPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Properties"), PropertiesPane)
    return self
end

-- Collect compile errors that reference the current selection.
local function errors_for(ctx)
    local out = {}
    local res = ctx.compileResult
    if not res or not res.errors then return out end
    local sel = ctx.selection
    for _i, e in ipairs(res.errors) do
        local hit = false
        if sel.kind == "operation" and e.operation == sel.id then hit = true end
        if sel.kind == "action" and e.operation == sel.opName and e.action_index == sel.id then hit = true end
        if sel.kind == "blueprint" and e.blueprint == sel.id then hit = true end
        if sel.kind == "project" and not e.operation and not e.blueprint then hit = true end
        if hit then table.insert(out, e) end
    end
    return out
end

function PropertiesPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local cy = py + 24

    local sel = ctx.selection
    if not sel or not sel.kind then
        w:render_text(px + pad, cy, "Nothing selected", Theme.colors.text_dim)
        w:render_text(px + pad, cy + 18, "Pick an item in the Explorer", Theme.colors.text_dim)
        return
    end

    if sel.kind == "operation" then
        local op = ctx:getOperation(sel.id)
        if not op then
            w:render_text(px + pad, cy, "Operation not found", Theme.colors.red)
            return
        end
        w:render_text(px + pad, cy, "Operation: " .. tostring(sel.id), Theme.colors.text)
        cy = cy + 22
        w:render_text(px + pad, cy, "Actions: " .. (#(op.actions or {})), Theme.colors.text_dim)
        cy = cy + 20
        if op.variables then
            w:render_text(px + pad, cy, "Variables: " .. (#op.variables), Theme.colors.text_dim)
            cy = cy + 20
        end
        w:render_text(px + pad, cy, "Add actions via the Palette ->", Theme.colors.accent)

    elseif sel.kind == "action" then
        local act, idx = ctx:getAction(sel.opName, sel.id)
        if not act then
            w:render_text(px + pad, cy, "Action not found", Theme.colors.red)
            return
        end
        w:render_text(px + pad, cy, "Action #" .. tostring(idx), Theme.colors.text)
        cy = cy + 22
        w:render_text(px + pad, cy, "Type: " .. tostring(act.action_type or act.type or "?"), Theme.colors.accent)
        cy = cy + 22

        w:render_text(px + pad, cy, "Args:", Theme.colors.text_dim)
        cy = cy + 18
        if act.args then
            for k, v in pairs(act.args) do
                local vs = type(v) == "table" and Theme.tbl_to_str(v) or tostring(v)
                w:render_text(px + pad + 8, cy, k .. " = " .. vs, Theme.colors.text)
                cy = cy + 16
            end
        else
            w:render_text(px + pad + 8, cy, "(none)", Theme.colors.text_dim)
            cy = cy + 16
        end
        cy = cy + 8

        -- Reorder / delete controls
        if w:is_rect_clicked(px + pad, cy, 70, 20) then
            ctx:moveAction(sel.opName, idx, idx - 1)
        end
        w:render_rect_filled(px + pad, cy, 70, 20, Theme.colors.button)
        w:render_text(px + pad + 6, cy + 3, "Up", Theme.colors.text)

        if w:is_rect_clicked(px + pad + 80, cy, 70, 20) then
            ctx:moveAction(sel.opName, idx, idx + 1)
        end
        w:render_rect_filled(px + pad + 80, cy, 70, 20, Theme.colors.button)
        w:render_text(px + pad + 86, cy + 3, "Down", Theme.colors.text)

        if w:is_rect_clicked(px + pad + 160, cy, 70, 20) then
            ctx:deleteAction(sel.opName, idx)
        end
        w:render_rect_filled(px + pad + 160, cy, 70, 20, Theme.colors.red)
        w:render_text(px + pad + 166, cy + 3, "Delete", Theme.colors.text)

    elseif sel.kind == "blueprint" then
        w:render_text(px + pad, cy, "Blueprint: " .. tostring(sel.id), Theme.colors.accent)
        cy = cy + 22
        w:render_text(px + pad, cy, "Expandable template (read-only in v1)", Theme.colors.text_dim)

    else
        w:render_text(px + pad, cy, "Project root", Theme.colors.text)
    end

    -- Validation messages for this selection
    local errs = errors_for(ctx)
    if #errs > 0 then
        cy = cy + 30
        w:render_text(px + pad, cy, "Validation:", Theme.colors.red)
        cy = cy + 18
        for _i, e in ipairs(errs) do
            local msg = (e.message or "?"):sub(1, 40)
            w:render_text(px + pad + 8, cy, "- " .. msg, Theme.colors.red)
            cy = cy + 16
        end
    end
end

return PropertiesPane
