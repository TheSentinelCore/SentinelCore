-- sentinel/ui/quest_authoring/action_palette.lua
-- Panel listing available action types grouped by category, with search/filter,
-- tooltips (description + parameter requirements), and click-to-add to the
-- currently selected operation. Uses ActionSchema as the single source of truth
-- for action types, fields, and categories.

local Panel        = require("ui/quest_authoring/panel")
local Theme        = require("ui/quest_authoring/theme")
local ActionSchema = require("ui/quest_authoring/action_schema")

local ActionPalette = setmetatable({}, { __index = Panel })
ActionPalette.__index = ActionPalette

-- Context-aware suggestion map: selected action type -> suggested next actions.
local SUGGESTIONS = {
  KillCreature  = { "Loot", "TravelTo" },
  AcceptQuest   = { "TurnInQuest", "TravelTo" },
  Vendor        = { "Repair" },
  TravelTo      = { "Wait", "Fish" },
  Loot          = { "KillCreature" },
  CollectItem   = { "GoToGameObject" },
  TurnInQuest   = { "AcceptQuest" },
  Repair        = { "Vendor" },
}

function ActionPalette.new(ctx, id)
  local self = Panel.new(ctx, id or "palette", "Action Palette")
  self._scroll = { value = 0 }
  self._search = ""
  self._tooltip = nil
  self._search_focused = false
  return self
end

local function matches_search(entry, q)
  if q == "" then return true end
  local ql = q:lower()
  return entry.type:lower():find(ql, 1, true) ~= nil
    or (entry.desc and entry.desc:lower():find(ql, 1, true) ~= nil)
end

function ActionPalette:draw()
  Panel.draw(self)
  local ctx = self.ctx
  local window = self.window
  if not window then return end
  local x, y, w, h = self._x, self._y, self._w, self._h
  local theme = Theme.theme

  local content_y = y + 22

  -- Search box
  local sb_x, sb_y, sb_w, sb_h = x + 8, content_y, w - 16, 18
  local focused = self._search_focused
  self:_rect(window, sb_x, sb_y, sb_w, sb_h, theme.input_bg, 3.0)
  self:_border(window, sb_x, sb_y, sb_w, sb_h, focused and theme.accent or theme.input_border, 3.0)
  self:_text(window, sb_x + 4, sb_y + 3, theme.text_dim, "Search: " .. self._search .. (focused and "_" or ""))
  if window.is_rect_clicked and window:is_rect_clicked(sb_x, sb_y, sb_w, sb_h) then
    self._search_focused = not self._search_focused
  end
  if self._search_focused then
    self:_handle_text_input()
    -- Enter/Escape to unfocus
    if core and core.input and core.input.is_key_pressed then
      if core.input.is_key_pressed(0x0D) or core.input.is_key_pressed(0x1B) then
        self._search_focused = false
      end
    end
  end

  local q = self._search:lower()
  local pad = self:_begin_scroll(window, x, content_y + 24, w, h - (content_y - y) - 28,
    self:_content_height(q), self._scroll, theme)

  local cy = content_y + 24 + pad
  local cx = x + 8
  local row_h = 22

  -- Suggestion set
  local sel = ctx:getSelected()
  local sugg_set = nil
  if sel and sel.kind == "action" then
    local act = ctx:getSelectedAction()
    local at = act and (act.action_type or act.type)
    if at and SUGGESTIONS[at] then
      sugg_set = {}
      for _, t in ipairs(SUGGESTIONS[at]) do sugg_set[t] = true end
    end
  end

  -- Group by category using schema
  local grouped, cat_order = ActionSchema.by_category()

  for _, cat_key in ipairs(cat_order) do
    local cat_meta = ActionSchema.CATEGORIES[cat_key]
    local cat_label = cat_meta and cat_meta.label or cat_key
    self:_text(window, cx, cy, theme.accent, cat_label)
    cy = cy + row_h

    for _, entry in ipairs(grouped[cat_key]) do
      if matches_search(entry, q) then
        local suggested = sugg_set and sugg_set[entry.type]
        local bg = suggested and theme.selected or theme.panel_bg
        self:_rect(window, cx, cy, w - 16, row_h - 2, bg, 3.0)
        self:_border(window, cx, cy, w - 16, row_h - 2, theme.panel_border, 3.0)

        -- Type name + required field indicator
        local has_required = false
        for _, f in ipairs(entry.fields) do
          if f.required then has_required = true; break end
        end
        local label = entry.type
        if has_required then label = label .. " +" end
        self:_text(window, cx + 6, cy + 3, suggested and Theme.color.white() or theme.text, label)

        if self:_hover(window, cx, cy, w - 16, row_h - 2) then
          self._tooltip = entry
        end
        if self:_hit(window, cx, cy, w - 16, row_h - 2) then
          self:_add_action(entry)
        end
        cy = cy + row_h
      end
    end
    cy = cy + 4
  end

  self:_end_scroll(window)
  self:_scrollbar(window, x, content_y + 24, w, h - (content_y - y) - 28,
    self:_content_height(q), self._scroll, theme)

  -- Tooltip
  if self._tooltip then
    local t = self._tooltip
    local lines = { t.type, t.desc or "" }
    -- Show required fields
    local req = {}
    for _, f in ipairs(t.fields) do
      if f.required then req[#req + 1] = f.label end
    end
    if #req > 0 then
      lines[#lines + 1] = "Required: " .. table.concat(req, ", ")
    end
    -- Show all fields
    local all_fields = {}
    for _, f in ipairs(t.fields) do
      all_fields[#all_fields + 1] = f.label .. " (" .. f.type .. ")"
    end
    if #all_fields > 0 then
      lines[#lines + 1] = "Fields: " .. table.concat(all_fields, ", ")
    end
    local tw = 220
    local th = 14 + #lines * 14
    local mx, my = self:_mouse_pos(window)
    local tx = (mx and mx.x or x + 20) + 12
    local ty = (my and my.y or y + 20) + 8
    self:_rect(window, tx, ty, tw, th, theme.panel_bg, 4.0)
    self:_border(window, tx, ty, tw, th, theme.accent, 4.0)
    for i, ln in ipairs(lines) do
      self:_text(window, tx + 8, ty + 6 + (i - 1) * 14, theme.text, ln)
    end
    self._tooltip = nil
  end
end

function ActionPalette:_mouse_pos(window)
  if window.get_mouse_pos then
    local ok, p = pcall(function() return window:get_mouse_pos() end)
    if ok then return p end
  end
  return nil
end

function ActionPalette:_handle_text_input()
  if not core or not core.input or not core.input.is_key_pressed then return end
  local ip = core.input
  -- Alphanumeric keys (VK codes: 0x30-0x39 = 0-9, 0x41-0x5A = A-Z)
  for vk = 0x30, 0x39 do -- 0-9
    if ip.is_key_pressed(vk) then
      self._search = self._search .. string.char(vk)
    end
  end
  for vk = 0x41, 0x5A do -- A-Z
    if ip.is_key_pressed(vk) then
      local ch = string.char(vk)
      -- Shift for lowercase (VK_SHIFT = 0x10)
      if not (ip.is_key_pressed(0x10) or ip.is_key_pressed(0xA0) or ip.is_key_pressed(0xA1)) then
        ch = ch:lower()
      end
      self._search = self._search .. ch
    end
  end
  -- Space (0x20), minus (0xBD), period (0xBE), slash (0xBF), semicolon (0xBA), equals (0xBB), brackets (0xDB/0xDD), backslash (0xDC), quote (0xDE), backtick (0xC0)
  local special = {
    [0x20] = " ", [0xBD] = "-", [0xBB] = "=", [0xDB] = "[", [0xDD] = "]",
    [0xDC] = "\\", [0xBA] = ";", [0xDE] = "'", [0xC0] = "`", [0xBE] = ".", [0xBF] = "/",
  }
  for vk, ch in pairs(special) do
    if ip.is_key_pressed(vk) then
      self._search = self._search .. ch
    end
  end
  -- Backspace (0x08)
  if ip.is_key_pressed(0x08) then
    self._search = self._search:sub(1, -2)
  end
end

function ActionPalette:_add_action(entry)
  local sel = self.ctx:getSelected()
  local opName
  if sel and sel.kind == "operation" then
    opName = sel.id
  elseif sel and sel.kind == "action" then
    opName = sel.opName
  end
  if not opName then return end

  -- Use schema defaults for args
  local args = ActionSchema.default_args(entry.type)
  local act = { type = entry.type, action_type = entry.type, args = args }
  self.ctx:addAction(opName, act)

  -- Auto-select the newly added action
  local op = self.ctx:getOperation(opName)
  if op and op.actions then
    self.ctx:select("action", #op.actions, { opName = opName })
  end
end

function ActionPalette:_content_height(q)
  q = q or ""
  local n = 0
  local grouped, cat_order = ActionSchema.by_category()
  for _, cat_key in ipairs(cat_order) do
    n = n + 1  -- category header
    for _, entry in ipairs(grouped[cat_key]) do
      if matches_search(entry, q) then n = n + 1 end
    end
  end
  return n * 26 + 20
end

return ActionPalette
