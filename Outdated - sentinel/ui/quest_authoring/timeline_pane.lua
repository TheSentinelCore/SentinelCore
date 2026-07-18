-- sentinel/ui/quest_authoring/timeline_pane.lua
-- Horizontal timeline of operations. Operations are rendered as expandable
-- cards; expanding reveals individual action chips color-coded by category.
-- Clicking an action chip selects it. Mouse wheel scrolls, click to select.

local Panel        = require("ui/quest_authoring/panel")
local Theme        = require("ui/quest_authoring/theme")
local ActionSchema = require("ui/quest_authoring/action_schema")

local TimelinePane = setmetatable({}, { __index = Panel })
TimelinePane.__index = TimelinePane

function TimelinePane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Timeline"), TimelinePane)
    self._scrollX = 0
    self._expanded = {}  -- opName -> true
    self._scroll = { value = 0 }
    return self
end

local function op_action_count(op)
    return op and op.actions and #op.actions or 0
end

function TimelinePane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local theme = Theme.theme

    w:render_text(px + pad, py + 6, "Timeline", theme.text)

    local proj = ctx.project
    if not proj or not proj.operations then
        w:render_text(px + pad, py + 24, "No operations", theme.text_dim)
        return
    end

    -- Horizontal scroll via wheel
    local wheel = w.get_mouse_wheel and w:get_mouse_wheel() or 0
    if self:_hover(w, px, py + 22, pw, ph - 22) and wheel ~= 0 then
        self._scrollX = math.max(0, self._scrollX - wheel * 30)
    end

    -- Sort operations by name for deterministic order
    local op_names = {}
    for name in pairs(proj.operations) do op_names[#op_names + 1] = name end
    table.sort(op_names)

    local chip_h = 20
    local chip_gap = 4
    local card_pad = 6
    local row_y = py + 24
    local cx = px + pad - self._scrollX

    for _, op_name in ipairs(op_names) do
        local op = proj.operations[op_name]
        local n = op_action_count(op)
        local expanded = self._expanded[op_name]

        -- Card dimensions
        local card_w = math.max(120, n * (60 + chip_gap) + card_pad * 2)
        if expanded then card_w = math.max(card_w, pw - pad * 2) end
        local card_h = 22 + (expanded and (n * (chip_h + chip_gap) + chip_gap) or 0)

        -- Off-screen cull (generous margin for scrolling)
        if cx + card_w > px - 200 and cx < px + pw + 200 then
            local selected = (ctx.selection and ctx.selection.kind == "operation" and ctx.selection.id == op_name)
            local has_errors = false
            if ctx.compileResult and ctx.compileResult.errors then
                for _, e in ipairs(ctx.compileResult.errors) do
                    if e.operation == op_name then has_errors = true; break end
                end
            end

            -- Card background
            local bg = selected and theme.selected or theme.panel_bg
            self:_rect(w, cx, row_y, card_w, card_h, bg, 4.0)
            self:_border(w, cx, row_y, card_w, card_h,
                has_errors and theme.red or theme.panel_border, 4.0)

            -- Header row: name + count + expand toggle
            local header_h = 20
            local toggle = expanded and "-" or "+"
            local name_text = (op.name or op_name) .. " [" .. n .. "] " .. toggle
            self:_text(w, cx + card_pad, row_y + 3, theme.text, name_text)

            -- Click header to select operation or toggle expand
            if self:_hit(w, cx, row_y, card_w, header_h) then
                ctx:select("operation", op_name)
                -- Double-click territory: toggle expand
                self._expanded[op_name] = not expanded
            end

            -- Action chips (when expanded)
            if expanded and op.actions then
                local chip_x = cx + card_pad
                local chip_y = row_y + header_h + chip_gap
                for i, act in ipairs(op.actions) do
                    local act_type = act.action_type or act.type or "?"
                    local cat = Theme.category_for_type(act_type)
                    local chip_w = math.max(56, #act_type * 7 + 12)

                    -- Chip color by category
                    local chip_bg = theme.button
                    if cat == "movement"    then chip_bg = theme.cat_movement end
                    if cat == "combat"      then chip_bg = theme.cat_combat end
                    if cat == "interaction" then chip_bg = theme.cat_interaction end
                    if cat == "quest"       then chip_bg = theme.cat_quest end

                    -- Highlight if selected
                    local act_selected = (ctx.selection and ctx.selection.kind == "action"
                        and ctx.selection.opName == op_name and ctx.selection.id == i)
                    if act_selected then
                        chip_bg = theme.accent
                    end

                    self:_rect(w, chip_x, chip_y, chip_w, chip_h, chip_bg, 3.0)
                    self:_border(w, chip_x, chip_y, chip_w, chip_h, theme.panel_border, 3.0)

                    -- Truncate long type names
                    local display = act_type
                    if #display > 7 then display = display:sub(1, 6) .. "~" end
                    self:_text(w, chip_x + 3, chip_y + 3, theme.text, display)

                    -- Click chip to select action
                    if self:_hit(w, chip_x, chip_y, chip_w, chip_h) then
                        ctx:select("action", i, { opName = op_name })
                    end

                    chip_x = chip_x + chip_w + chip_gap
                    -- Wrap to next row if overflows
                    if chip_x + chip_w > cx + card_w then
                        chip_x = cx + card_pad
                        chip_y = chip_y + chip_h + chip_gap
                    end
                end
            end
        end

        cx = cx + card_w + 12
    end

    -- Scroll hint
    if self._scrollX > 0 then
        self:_text(w, px + pad, py + ph - 14, theme.text_dim,
            "scroll: " .. math.floor(self._scrollX))
    end

    -- Total width indicator
    local total_w = cx + self._scrollX - px - pad
    if total_w > pw then
        local bar_w = math.max(30, (pw / total_w) * pw)
        local bar_x = px + pad + (self._scrollX / total_w) * pw
        self:_rect(w, bar_x, py + ph - 4, bar_w, 3, theme.panel_border, 1.0)
    end
end

return TimelinePane
