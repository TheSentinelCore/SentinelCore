-- sentinel/ui/quest_authoring/panel.lua
-- Base class for Quest Authoring IDE panes.
-- Provides shared drawing/input helpers over the Sylvannas window API so each
-- pane only deals with its own content. Each pane is positioned by begin() and
-- draws in absolute window coordinates (self._x/self._y + its own layout).

local Theme = require("ui/quest_authoring/theme")

local Panel = {}
Panel.__index = Panel

function Panel.new(ctx, id, title)
  local self = setmetatable({}, Panel)
  self.ctx = ctx
  self.id = id
  self.title = title or id
  self.window = nil
  self._x, self._y, self._w, self._h = 0, 0, 0, 0
  return self
end

--- Position the pane and store its absolute rect. Does not draw.
function Panel:begin(window, x, y, w, h)
  self.window = window
  self._x, self._y, self._w, self._h = x, y, w, h
  self._visible = true
end

--- Draw the chrome (background + title). Subclasses call this at the top of
--- their own draw() so the title stays consistent.
function Panel:draw()
  local w = self.window
  if not w then return end
  local theme = Theme.theme
  self:_panel_bg(w, self._x, self._y, self._w, self._h, theme)
  if self.title then
    self:_text(w, self._x + 8, self._y + 6, theme.text, self.title)
  end
end

-- ---- Drawing helpers ----
function Panel:_panel_bg(window, x, y, w, h, theme)
  local v2 = Theme.vec2
  window:render_rect_filled(v2.new(x, y), v2.new(x + w, y + h), theme.panel_bg, 6.0)
  window:render_rect(v2.new(x, y), v2.new(x + w, y + h), theme.panel_border, 6.0, 1.0)
end

function Panel:_rect(window, x, y, w, h, color, radius)
  local v2 = Theme.vec2
  window:render_rect_filled(v2.new(x, y), v2.new(x + w, y + h), color, radius or 4.0)
end

function Panel:_border(window, x, y, w, h, color, radius)
  local v2 = Theme.vec2
  window:render_rect(v2.new(x, y), v2.new(x + w, y + h), color, radius or 4.0, 1.0)
end

function Panel:_text(window, x, y, color, text)
  window:render_text(x, y, text, color)
end

function Panel:_text_size(window, text)
  return window:get_text_size(text)
end

--- A clickable button. Returns true on the frame it was clicked.
function Panel:_button(window, x, y, w, h, label, theme, opts)
  opts = opts or {}
  local v2 = Theme.vec2
  local hovered = window:is_mouse_hovering_rect(v2.new(x, y), v2.new(x + w, y + h))
  window:is_mouse_hovering_rect_block_movement(v2.new(x, y), v2.new(x + w, y + h))
  local bg = hovered and theme.hover or (opts.active and theme.selected or theme.panel_bg)
  self:_rect(window, x, y, w, h, bg, 4.0)
  self:_border(window, x, y, w, h, theme.panel_border, 4.0)
  local ts = window:get_text_size(label)
  local tx = x + (w - ts.x) / 2
  local ty = y + (h - ts.y) / 2
  self:_text(window, tx, ty, theme.text, label)
  if hovered and window:is_mouse_button_clicked(0) then
    return true
  end
  return false
end

function Panel:_hit(window, x, y, w, h)
  local v2 = Theme.vec2
  return window:is_rect_clicked(v2.new(x, y), v2.new(x + w, y + h))
end

function Panel:_hover(window, x, y, w, h)
  local v2 = Theme.vec2
  return window:is_mouse_hovering_rect(v2.new(x, y), v2.new(x + w, y + h))
end

--- Clip + simple vertical scroll: returns the y offset to apply to content.
function Panel:_begin_scroll(window, x, y, w, h, content_h, scroll_state, theme)
  scroll_state.value = scroll_state.value or 0
  local max_scroll = math.max(0, content_h - h)
  if scroll_state.value > max_scroll then scroll_state.value = max_scroll end
  if scroll_state.value < 0 then scroll_state.value = 0 end
  local wheel = window.get_mouse_wheel and window:get_mouse_wheel() or 0
  if self:_hover(window, x, y, w, h) and wheel ~= 0 then
    scroll_state.value = scroll_state.value + wheel * 16
  end
  if window.push_clip_rect then
    window:push_clip_rect(Theme.vec2.new(x, y), Theme.vec2.new(x + w, y + h))
  end
  return -scroll_state.value
end

function Panel:_end_scroll(window)
  if window.pop_clip_rect then window:pop_clip_rect() end
end

--- Draw a scrollbar on the right edge.
function Panel:_scrollbar(window, x, y, w, h, content_h, scroll_state, theme)
  local max_scroll = math.max(1, content_h - h)
  local bar_h = math.max(16, (h / content_h) * h)
  local ratio = scroll_state.value / max_scroll
  local bar_y = y + ratio * (h - bar_h)
  self:_rect(window, x + w - 4, bar_y, 3, bar_h, theme.panel_border, 2.0)
end

-- ── Form widgets ──────────────────────────────────────────────────────
-- Reusable input widgets for the Properties pane. Each returns its new
-- value and a boolean indicating whether the value changed.

--- Text input field. Returns (new_value, changed).
--- @param focused_field string|nil  key of the currently focused field in the parent pane
--- @param my_key string  this field's key (compared against focused_field)
function Panel:_text_input(window, x, y, w, h, value, focused_field, my_key, theme)
  theme = theme or Theme.theme
  local is_focused = (focused_field == my_key)
  local display = tostring(value or "")
  -- Background
  self:_rect(window, x, y, w, h, theme.input_bg, 3.0)
  self:_border(window, x, y, w, h, is_focused and theme.accent or theme.input_border, 3.0)
  -- Text + cursor
  local cursor = is_focused and "_" or ""
  self:_text(window, x + 4, y + 3, theme.text, display .. cursor)
  -- Click to focus
  local clicked = self:_hit(window, x, y, w, h)
  local changed = false
  -- Keyboard input when focused (build our own char map since Sylvannas lacks VK_CHAR_MAP)
  if is_focused and core and core.input and core.input.is_key_pressed then
    local ip = core.input
    -- Alphanumeric keys (VK codes: 0x30-0x39 = 0-9, 0x41-0x5A = A-Z)
    for vk = 0x30, 0x39 do -- 0-9
      if ip.is_key_pressed(vk) then
        display = display .. string.char(vk)
        changed = true
      end
    end
    for vk = 0x41, 0x5A do -- A-Z
      if ip.is_key_pressed(vk) then
        local ch = string.char(vk)
        -- Shift for lowercase (VK_SHIFT = 0x10)
        if not (ip.is_key_pressed(0x10) or ip.is_key_pressed(0xA0) or ip.is_key_pressed(0xA1)) then
          ch = ch:lower()
        end
        display = display .. ch
        changed = true
      end
    end
    -- Space (0x20), minus (0xBD), period (0xBE), slash (0xBF), semicolon (0xBA), equals (0xBB), bracket left (0xDB), bracket right (0xDD), backslash (0xDC), quote (0xDE), backtick (0xC0)
    local special = {
      [0x20] = " ", [0xBD] = "-", [0xBB] = "=", [0xDB] = "[", [0xDD] = "]",
      [0xDC] = "\\", [0xBA] = ";", [0xDE] = "'", [0xC0] = "`", [0xBE] = ".", [0xBF] = "/",
    }
    for vk, ch in pairs(special) do
      if ip.is_key_pressed(vk) then
        display = display .. ch
        changed = true
      end
    end
    -- Backspace (0x08)
    if ip.is_key_pressed(0x08) then
      display = display:sub(1, -2)
      changed = true
    end
    -- Enter (0x0D) → commit & unfocus (handled by caller)
    -- Escape (0x1B) → unfocus without commit (handled by caller)
  end
  return display, changed, clicked
end

--- Checkbox. Returns (new_value, clicked).
function Panel:_checkbox(window, x, y, label, value, theme)
  theme = theme or Theme.theme
  local box = 14
  -- Box
  self:_rect(window, x, y, box, box, value and theme.accent or theme.input_bg, 2.0)
  self:_border(window, x, y, box, box, theme.input_border, 2.0)
  if value then
    self:_text(window, x + 2, y, theme.text, "\xE2\x9C\x93") -- UTF-8 checkmark
  end
  -- Label
  self:_text(window, x + box + 4, y + 1, theme.text, label)
  -- Click anywhere on box+label area
  local ts = self:_text_size(window, label)
  local clicked = self:_hit(window, x, y, box + 4 + ts.x, box)
  return clicked and (not value) or value, clicked
end

--- Section header (small accent bar + title).
function Panel:_section_header(window, x, y, w, title, theme)
  theme = theme or Theme.theme
  self:_rect(window, x, y, w, 1, theme.accent, 0)
  self:_text(window, x, y + 4, theme.accent, title)
end

return Panel
