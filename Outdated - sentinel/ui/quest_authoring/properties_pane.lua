-- sentinel/ui/quest_authoring/properties_pane.lua
-- Context-sensitive properties editor for the current selection. Generates
-- dynamic editable forms from ActionSchema for action fields, and provides
-- read-only metadata views for operations, blueprints, and project root.

local Panel          = require("ui/quest_authoring/panel")
local Theme          = require("ui/quest_authoring/theme")
local ActionSchema   = require("ui/quest_authoring/action_schema")

local PropertiesPane = setmetatable({}, { __index = Panel })
PropertiesPane.__index = PropertiesPane

function PropertiesPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Properties"), PropertiesPane)
    self._focused_field = nil   -- key of the currently focused text input
    self._scroll = { value = 0 }
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

-- Estimate content height for the action form.
local function form_height(schema)
    if not schema then return 0 end
    local h = 60  -- type header + spacing
    for _ in ipairs(schema.fields) do
        h = h + 34  -- label (14) + input (18) + gap (2)
    end
    return h + 40  -- validation section + padding
end

function PropertiesPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local theme = Theme.theme
    local cy = py + 24

    local sel = ctx.selection
    if not sel or not sel.kind then
        w:render_text(px + pad, cy, "Nothing selected", theme.text_dim)
        w:render_text(px + pad, cy + 18, "Pick an item in the Explorer", theme.text_dim)
        return
    end

    -- ── Operation selected ───────────────────────────────────────────
    if sel.kind == "operation" then
        local op = ctx:getOperation(sel.id)
        if not op then
            w:render_text(px + pad, cy, "Operation not found", theme.red)
            return
        end
        w:render_text(px + pad, cy, "Operation", theme.accent)
        cy = cy + 18
        w:render_text(px + pad, cy, sel.id, theme.text)
        cy = cy + 20
        w:render_text(px + pad, cy, "Actions: " .. (#(op.actions or {})), theme.text_dim)
        cy = cy + 16
        if op.variables then
            w:render_text(px + pad, cy, "Variables: " .. (#op.variables), theme.text_dim)
            cy = cy + 16
        end
        if op.description then
            w:render_text(px + pad, cy, op.description:sub(1, 40), theme.text_dim)
            cy = cy + 16
        end
        w:render_text(px + pad, cy + 8, "Select an action to edit", theme.accent)

    -- ── Action selected ──────────────────────────────────────────────
    elseif sel.kind == "action" then
        local act, idx = ctx:getAction(sel.opName, sel.id)
        if not act then
            w:render_text(px + pad, cy, "Action not found", theme.red)
            return
        end

        local action_type = act.action_type or act.type or "?"
        local schema = ActionSchema.get(action_type)

        -- Header: type + index
        w:render_text(px + pad, cy, "Action #" .. tostring(idx), theme.text_dim)
        cy = cy + 16
        w:render_text(px + pad, cy, action_type, theme.accent)
        cy = cy + 18

        -- Show description if schema exists
        if schema then
            w:render_text(px + pad, cy, schema.desc, theme.text_dim)
            cy = cy + 16
        end

        cy = cy + 4

        -- ── Scrollable form area ─────────────────────────────────
        local form_h = schema and form_height(schema) or 80
        local content_h = form_h
        local scroll_area_h = ph - (cy - py) - 60  -- leave room for reorder buttons
        local pad2 = self:_begin_scroll(w, px, cy, pw, scroll_area_h,
            content_h, self._scroll, theme)
        local fy = cy + pad2

        if schema then
            -- Ensure args table exists
            act.args = act.args or {}

            -- Dynamic form fields
            for _, field in ipairs(schema.fields) do
                local val = act.args[field.key]
                local display_val = (val ~= nil) and tostring(val) or (field.default ~= nil and tostring(field.default) or "")

                -- Label
                self:_text(w, px + pad, fy, theme.text_dim, field.label .. (field.required and " *" or ""))
                fy = fy + 14

                if field.type == "boolean" then
                    -- Checkbox
                    local bool_val = (val == true) or (val == "true") or (val == 1)
                    local new_val, _clicked = self:_checkbox(w, px + pad, fy, field.label, bool_val, theme)
                    if _clicked then
                        act.args[field.key] = new_val
                        ctx:markDirty()
                    end
                    fy = fy + 18
                else
                    -- Text input (string, number, or anything else)
                    local input_w = pw - pad * 2
                    local new_val, changed, clicked = self:_text_input(
                        w, px + pad, fy, input_w, 18,
                        display_val, self._focused_field, field.key, theme)
                    if clicked then
                        self._focused_field = field.key
                    end
                    -- Enter = commit & unfocus, Escape = cancel & unfocus
                    if self._focused_field == field.key and core and core.input and core.input.is_key_pressed then
                        if core.input.is_key_pressed(0x0D) then -- Enter
                            self._focused_field = nil
                        elseif core.input.is_key_pressed(0x1B) then -- Escape
                            self._focused_field = nil
                        end
                    end
                    if changed then
                        -- Auto-convert numbers
                        if field.type == "number" then
                            local n = tonumber(new_val)
                            act.args[field.key] = n or new_val
                        else
                            act.args[field.key] = new_val
                        end
                        ctx:markDirty()
                    end
                    fy = fy + 20
                end

                -- Description tooltip
                if field.desc and field.desc ~= "" then
                    self:_text(w, px + pad + 4, fy, theme.text_dim, field.desc)
                    fy = fy + 14
                end
                fy = fy + 2
            end

            -- Unfocus when clicking outside any input
            if self._focused_field and self:_hit(w, px, cy, pw, scroll_area_h) then
                local clicked_any = false
                for _, field in ipairs(schema.fields) do
                    if self:_hover(w, px + pad, cy, pw - pad * 2, 18) then
                        clicked_any = true
                        break
                    end
                end
                if not clicked_any then
                    self._focused_field = nil
                end
            end
        else
            -- Unknown action type — show raw args
            self:_text(w, px + pad, fy, theme.text_dim, "Args:")
            fy = fy + 14
            if act.args then
                for k, v in pairs(act.args) do
                    local vs = type(v) == "table" and Theme.tbl_to_str(v) or tostring(v)
                    self:_text(w, px + pad + 4, fy, theme.text, k .. " = " .. vs)
                    fy = fy + 16
                end
            else
                self:_text(w, px + pad + 4, fy, theme.text_dim, "(none)")
                fy = fy + 16
            end
        end

        self:_end_scroll(w)

        -- ── Reorder / delete buttons (always visible) ────────────
        local btn_y = py + ph - 26
        if self:_button(w, px + pad, btn_y, 60, 20, "Up", theme) then
            ctx:moveAction(sel.opName, idx, idx - 1)
            self._focused_field = nil
        end
        if self:_button(w, px + pad + 66, btn_y, 60, 20, "Down", theme) then
            ctx:moveAction(sel.opName, idx, idx + 1)
            self._focused_field = nil
        end
        if self:_button(w, px + pad + 136, btn_y, 60, 20, "Delete", theme, { danger = true }) then
            ctx:deleteAction(sel.opName, idx)
            self._focused_field = nil
        end

        -- ── Validation errors ────────────────────────────────────
        local errs = errors_for(ctx)
        if #errs > 0 then
            local ey = btn_y - 16 * #errs - 14
            self:_text(w, px + pad, ey, theme.red, "Validation:")
            ey = ey + 14
            for _i, e in ipairs(errs) do
                local msg = (e.message or "?"):sub(1, 40)
                self:_text(w, px + pad + 4, ey, theme.red, "- " .. msg)
                ey = ey + 14
            end
        end

    -- ── Blueprint selected ───────────────────────────────────────────
    elseif sel.kind == "blueprint" then
        w:render_text(px + pad, cy, "Blueprint: " .. tostring(sel.id), theme.accent)
        cy = cy + 22
        w:render_text(px + pad, cy, "Expandable template (read-only in v1)", theme.text_dim)
        cy = cy + 18
        local bp = ctx.project and ctx.project.blueprints and ctx.project.blueprints[sel.id]
        if bp and bp.description then
            w:render_text(px + pad, cy, bp.description:sub(1, 45), theme.text_dim)
        end

    else
        w:render_text(px + pad, cy, "Project root", theme.text)
    end
end

return PropertiesPane
