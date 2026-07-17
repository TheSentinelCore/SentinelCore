-- sentinel/ui/quest_authoring/panel.lua
-- Base class for Quest Authoring IDE panes.
-- Provides shared drawing/input helpers over the Sylvannas window API so each
-- pane only deals with its own content. Each pane is positioned by begin() and
-- draws in absolute window coordinates (self._x/self._y + its own layout).

local Theme = require("ui.quest_authoring.theme")

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
  window:render_text(x, y, color, text)
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

return Panel
