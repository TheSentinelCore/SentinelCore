-- sentinel/ui/quest_authoring/action_palette.lua
-- Ticket 009: IDE Action Palette
-- Panel listing available action types grouped by category, with search/filter,
-- tooltips (description + parameter requirements), and click-to-add to the
-- currently selected operation. Suggestions narrow to the current selection.

local Panel = require("ui.quest_authoring.panel")
local Theme = require("ui.quest_authoring.theme")

local ActionPalette = setmetatable({}, { __index = Panel })
ActionPalette.__index = ActionPalette

-- The action registry: category -> { {type, description, params={...}} }
local REGISTRY = {
  Movement = {
    { type = "TravelTo", description = "Move to coordinates or NPC", params = { "method", "to", "from" } },
    { type = "Wait", description = "Wait for a duration (e.g. travel/zeppelin)", params = { "duration_s" } },
    { type = "Fish", description = "Fish at a fishing node", params = {} },
  },
  Combat = {
    { type = "KillCreature", description = "Kill a creature by name/id", params = { "creature_name", "quest_id" } },
    { type = "Loot", description = "Loot required quest items", params = { "item_id", "count" } },
  },
  Interaction = {
    { type = "TalkToNPC", description = "Talk to an NPC", params = { "npc_name" } },
    { type = "AcceptQuest", description = "Accept/pick up a quest", params = { "quest_id" } },
    { type = "TurnIn", description = "Turn in a completed quest", params = { "quest_id" } },
    { type = "Vendor", description = "Use a vendor (sell/buy/repair)", params = {} },
    { type = "Repair", description = "Repair gear (durability guarded)", params = { "durability_threshold" } },
  },
  Quest = {
    { type = "CollectItem", description = "Collect an item from the world", params = { "item_name" } },
    { type = "GoToGameObject", description = "Interact with a game object", params = { "gameobject_name" } },
  },
}

-- Context-aware suggestion map: selected action type -> suggested next actions.
local SUGGESTIONS = {
  KillCreature = { "Loot", "TravelTo" },
  AcceptQuest = { "TurnIn", "TravelTo" },
  Vendor = { "Repair" },
  TravelTo = { "Wait", "Fish" },
}

function ActionPalette.new(ctx, id)
  local self = Panel.new(ctx, id or "palette", "Action Palette")
  self._scroll = { value = 0 }
  self._search = ""
  self._tooltip = nil
  return self
end

local function matches_search(entry, q)
  if q == "" then return true end
  return entry.type:lower():find(q, 1, true) ~= nil
    or (entry.description and entry.description:lower():find(q, 1, true) ~= nil)
end

function ActionPalette:draw()
  Panel.draw(self)
  local ctx = self.ctx
  local window = self.window
  if not window then return end
  local x, y, w, h = self._x, self._y, self._w, self._h
  local theme = Theme.theme

  local content_y = y + 22
  -- Search box (live text input). Click to focus, then type to filter.
  local sb_x, sb_y, sb_w, sb_h = x + 8, content_y, w - 16, 18
  local focused = self._search_focused
  self:_rect(window, sb_x, sb_y, sb_w, sb_h, theme.input_bg, 3.0)
  self:_border(window, sb_x, sb_y, sb_w, sb_h, focused and theme.accent or theme.input_border, 3.0)
  self:_text(window, sb_x + 4, sb_y + 3, theme.text_dim, "Search: " .. self._search .. (focused and "_" or ""))
  if window.is_rect_clicked and window:is_rect_clicked(sb_x, sb_y, sb_w, sb_h) then
    self._search_focused = not self._search_focused
  end
  if self._search_focused then self:_handle_text_input() end

  local q = self._search:lower()
  local pad = self:_begin_scroll(window, x, content_y + 24, w, h - (content_y - y) - 28,
    self:_content_height(q), self._scroll, theme)

  local cy = content_y + 24 + pad
  local cx = x + 8
  local row_h = 22

  -- Determine suggested action types for the current selection.
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

  for category, entries in pairs(REGISTRY) do
    self:_text(window, cx, cy, theme.accent, category)
    cy = cy + row_h
    for _, entry in ipairs(entries) do
      if matches_search(entry, q) then
        local suggested = sugg_set and sugg_set[entry.type]
        local bg = suggested and theme.selected or theme.panel_bg
        self:_rect(window, cx, cy, w - 16, row_h - 2, bg, 3.0)
        self:_border(window, cx, cy, w - 16, row_h - 2, theme.panel_border, 3.0)
        self:_text(window, cx + 6, cy + 3, suggested and Theme.color.white() or theme.text, entry.type)
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
  self:_scrollbar(window, x, content_y + 24, w, h - (content_y - y) - 28, self:_content_height(q), self._scroll, theme)

  -- Tooltip
  if self._tooltip then
    local t = self._tooltip
    local lines = { t.type, t.description or "", "Params: " .. table.concat(t.params, ", ") }
    local tw = 200
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

-- Live text input for the search box. Mirrors the sentinel_ui text-input
-- pattern: poll core.input.VK_CHAR_MAP (key -> char) and the backspace key.
-- No-op outside the game runtime where core.input is unavailable.
function ActionPalette:_handle_text_input()
  if not core or not core.input then return end
  local ip = core.input
  if ip.VK_CHAR_MAP then
    for key, ch in pairs(ip.VK_CHAR_MAP) do
      if ip.is_key_pressed and ip.is_key_pressed(key) then
        self._search = self._search .. tostring(ch)
      end
    end
  end
  if ip.is_key_pressed and ip.is_key_pressed(0x08) then
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
  local args = {}
  self.ctx:addAction(opName, { type = entry.type, action_type = entry.type, args = args })
end

function ActionPalette:_content_height(q)
  q = q or ""
  local n = 0
  for _category, entries in pairs(REGISTRY) do
    n = n + 1 -- category header
    for _i, e in ipairs(entries) do
      if matches_search(e, q) then n = n + 1 end
    end
  end
  return n * 26 + 20
end

return ActionPalette
