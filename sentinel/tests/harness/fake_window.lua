-- sentinel/tests/harness/fake_window.lua
-- A recording stand-in for a Sylvannas custom window (ADR 09b §7).
--
-- WHY THIS IS PART OF U1 AND NOT A LATER CONVENIENCE
-- --------------------------------------------------
-- Code inside `register_on_render_window_callback` cannot be executed outside the injector, so
-- without a fake the only way to check a panel is to inject and look at it. That makes the
-- state/render split in ADR 09b §2.1 unenforceable: nothing stops decision logic drifting into a
-- render function, because nothing can observe a render function. This file is what makes the
-- rule checkable, which is why it ships with the widgets rather than after them.
--
-- WHAT IT IS
-- ----------
-- Every documented `window:*` call is recorded with its arguments, in order, and the pointer
-- predicates (`is_mouse_hovering_rect`, `is_rect_clicked`) are driven by a simulated cursor. A
-- test therefore asserts on the DRAW TAPE — what was painted, where, in what colour — which is
-- precisely the observable an immediate-mode UI has and nothing more.
--
-- WHAT IT DELIBERATELY DOES NOT DO
-- --------------------------------
--  * It implements ONLY the surface documented in `docs/SylvannasAPI/dev/api/ui-custom.md`. A
--    metatable that answered every call would let a panel invoke a method Sylvannas does not
--    have, pass offline, and error in the injector — the exact class of bug offline tests exist
--    to catch. Unknown methods are absent, so they raise here.
--  * It does not lay anything out. Dynamic-position calls are recorded and the cursor is
--    advanced arithmetically; it makes no claim to reproduce ImGui's real geometry.
--  * Its text metrics are a fixed character box, not a font. Layout maths that DEPENDS on real
--    glyph widths is not testable here and should not pretend to be.

local FakeWindow = {}
FakeWindow.__index = FakeWindow

-- Off-screen by a wide margin. A fake whose pointer starts at (0,0) would hover every widget
-- anchored at the origin, and the resting half of every widget test would silently pass.
local NOWHERE = { x = -1e6, y = -1e6 }

---@param opts table|nil { size, position, char_width, line_height }
function FakeWindow.new(opts)
    opts = opts or {}
    local self = setmetatable({}, FakeWindow)
    self.calls = {}
    self.size = opts.size or { x = 800, y = 600 }
    self.position = opts.position or { x = 0, y = 0 }
    self.visible = true
    self._mouse = { x = NOWHERE.x, y = NOWHERE.y }
    self._click = nil
    self._double_click = nil
    self._char_width = opts.char_width or 7
    self._line_height = opts.line_height or 14
    self._dynamic = { x = 0, y = 0 }
    return self
end

-- ============================================================================
-- Recording
-- ============================================================================

function FakeWindow:_record(name, ...)
    local call = { name = name, args = { ... }, n = select("#", ...) }
    self.calls[#self.calls + 1] = call
    return call
end

function FakeWindow:reset()
    self.calls = {}
    self._dynamic = { x = 0, y = 0 }
end

-- ============================================================================
-- Pointer simulation
-- ============================================================================

local function centre_of(bounds)
    return bounds.x + bounds.w * 0.5, bounds.y + bounds.h * 0.5
end

function FakeWindow:set_mouse(x, y)
    self._mouse = { x = x, y = y }
end

---Place the pointer at the centre of `bounds`.
function FakeWindow:hover(bounds)
    local x, y = centre_of(bounds)
    self:set_mouse(x, y)
end

function FakeWindow:set_click(x, y)
    -- A click implies the pointer is there. Letting them diverge would let a widget report
    -- activation while claiming it was never hovered, which no real frame can produce.
    self._click = { x = x, y = y }
    self:set_mouse(x, y)
end

---Click the centre of `bounds`.
function FakeWindow:click(bounds)
    local x, y = centre_of(bounds)
    self:set_click(x, y)
end

function FakeWindow:clear_click()
    self._click = nil
end

function FakeWindow:set_double_click(x, y)
    self._double_click = { x = x, y = y }
    self:set_click(x, y)
end

local function contains(point, mn, mx)
    if not point then return false end
    return point.x >= mn.x and point.x <= mx.x and point.y >= mn.y and point.y <= mx.y
end

-- ============================================================================
-- Window surface — predicates
-- ============================================================================

function FakeWindow:is_mouse_hovering_rect(rect_min, rect_max)
    self:_record("is_mouse_hovering_rect", rect_min, rect_max)
    return contains(self._mouse, rect_min, rect_max)
end

function FakeWindow:is_rect_clicked(rect_min, rect_max)
    self:_record("is_rect_clicked", rect_min, rect_max)
    return contains(self._click, rect_min, rect_max)
end

function FakeWindow:is_rect_double_clicked(rect_min, rect_max)
    self:_record("is_rect_double_clicked", rect_min, rect_max)
    return contains(self._double_click, rect_min, rect_max)
end

-- ============================================================================
-- Window surface — drawing
-- ============================================================================

local DRAW_CALLS = {
    "render_text", "render_rect", "render_rect_filled", "render_rect_filled_multicolor",
    "render_circle", "render_circle_filled", "render_circle_percentage",
    "render_line", "render_triangle", "render_triangle_filled",
    "render_triangle_filled_multi_color", "render_bezier_quadratic", "render_bezier_cubic",
    "add_separator", "add_artificial_item_bounds", "push_font", "center_text",
    "draw_next_dynamic_widget_on_same_line", "draw_next_dynamic_widget_on_new_line",
    "set_next_window_items_spacing", "set_next_window_items_inner_spacing",
    "set_next_window_padding", "set_next_window_min_size", "set_next_window_cross_round",
    "set_next_close_cross_pos_offset", "force_next_begin_window_pos", "stop_forcing_position",
    "set_background_multicolored", "set_end_called_state", "make_loading_circle_animation",
}

for _, name in ipairs(DRAW_CALLS) do
    FakeWindow[name] = function(self, ...)
        self:_record(name, ...)
    end
end

function FakeWindow:add_text_on_dynamic_pos(color, text)
    self:_record("add_text_on_dynamic_pos", color, text)
    self._dynamic.y = self._dynamic.y + self._line_height
end

function FakeWindow:add_menu_element_pos_offset(pos_offset)
    self:_record("add_menu_element_pos_offset", pos_offset)
    if pos_offset then
        self._dynamic.x = self._dynamic.x + (pos_offset.x or 0)
        self._dynamic.y = self._dynamic.y + (pos_offset.y or 0)
    end
end

function FakeWindow:get_current_context_dynamic_drawing_offset()
    return { x = self._dynamic.x, y = self._dynamic.y }
end

-- ============================================================================
-- Window surface — frames, measurement, lifecycle
-- ============================================================================

---`window:begin(resizing, cross, bg, border, cross_style, [flags...], callback)`.
---The callback is always last, so it is found by scanning rather than by a fixed index.
function FakeWindow:begin(...)
    local args = { ... }
    self:_record("begin", ...)
    for i = #args, 1, -1 do
        if type(args[i]) == "function" then
            args[i]()
            return true
        end
    end
    return true
end

function FakeWindow:begin_group(callback)
    self:_record("begin_group")
    if type(callback) == "function" then callback() end
end

---`window:begin_popup(bg, border, size, pos, close_on_release, from_button, callback)`.
---Returns true so a caller's "the popup is still open" branch is the one exercised; a test that
---wants the closed branch sets `fake.popup_open = false`.
function FakeWindow:begin_popup(...)
    local args = { ... }
    self:_record("begin_popup", ...)
    if self.popup_open == false then return false end
    for i = #args, 1, -1 do
        if type(args[i]) == "function" then
            args[i]()
            break
        end
    end
    return true
end

function FakeWindow:get_size() return { x = self.size.x, y = self.size.y } end
function FakeWindow:get_position() return { x = self.position.x, y = self.position.y } end
function FakeWindow:get_mouse_pos() return { x = self._mouse.x, y = self._mouse.y } end

function FakeWindow:get_text_size(str)
    local text = tostring(str or "")
    return { x = #text * self._char_width, y = self._line_height }
end

function FakeWindow:get_text_centered_x_pos(text)
    return (self.size.x - self:get_text_size(text).x) * 0.5
end

function FakeWindow:set_initial_size(size) self:_record("set_initial_size", size) end
function FakeWindow:set_initial_position(pos) self:_record("set_initial_position", pos) end
function FakeWindow:set_visibility(v) self:_record("set_visibility", v); self.visible = v and true or false end
function FakeWindow:is_being_shown() return self.visible end
function FakeWindow:get_type() return 0 end

---Deterministic stand-in for `animate_widget`: reports the animation already finished, so a test
---observes the settled frame rather than an arbitrary point on a curve.
function FakeWindow:animate_widget(id, from, to, start_alpha, max_alpha, ...)
    self:_record("animate_widget", id, from, to, start_alpha, max_alpha, ...)
    return { current_position = to, alpha = max_alpha }
end

function FakeWindow:is_animation_finished() return true end

-- ============================================================================
-- Assertions
-- ============================================================================

---Every recorded call named `name`, in order.
function FakeWindow:calls_of(name)
    local out = {}
    for _, call in ipairs(self.calls) do
        if call.name == name then out[#out + 1] = call end
    end
    return out
end

function FakeWindow:hover_tests() return self:calls_of("is_mouse_hovering_rect") end
function FakeWindow:click_tests() return self:calls_of("is_rect_clicked") end

---Every string this window was asked to draw, static or dynamic, as
---`{ text, color, font_id, pos, dynamic }`.
function FakeWindow:text_calls()
    local out = {}
    for _, call in ipairs(self.calls) do
        if call.name == "render_text" then
            out[#out + 1] = {
                text = tostring(call.args[4]), font_id = call.args[1],
                pos = call.args[2], color = call.args[3], dynamic = false,
            }
        elseif call.name == "add_text_on_dynamic_pos" then
            out[#out + 1] = {
                text = tostring(call.args[2]), font_id = nil,
                pos = nil, color = call.args[1], dynamic = true,
            }
        end
    end
    return out
end

---The first drawn string containing `needle`. Matched PLAIN, not as a Lua pattern: UI copy is
---full of `(`, `)`, `-` and `.`, so pattern matching would make `drew_text("npc:823 (-8933.5)")`
---either silently true or an outright error.
function FakeWindow:find_text(needle)
    for _, entry in ipairs(self:text_calls()) do
        if entry.text:find(needle, 1, true) then return entry end
    end
    return nil
end

function FakeWindow:drew_text(needle)
    return self:find_text(needle) ~= nil
end

local RECT_CALLS = {
    render_rect = "outline",
    render_rect_filled = "filled",
    render_rect_filled_multicolor = "filled",
}

local function matches_bounds(call, bounds, tolerance)
    local mn, mx = call.args[1], call.args[2]
    if type(mn) ~= "table" or type(mx) ~= "table" then return false end
    return math.abs(mn.x - bounds.x) <= tolerance
        and math.abs(mn.y - bounds.y) <= tolerance
        and math.abs(mx.x - (bounds.x + bounds.w)) <= tolerance
        and math.abs(mx.y - (bounds.y + bounds.h)) <= tolerance
end

---The first rect drawn at `bounds` (`{ x, y, w, h }`), or nil.
---@param kind string|nil "filled" or "outline"; nil accepts either
function FakeWindow:rect_at(bounds, kind, tolerance)
    tolerance = tolerance or 0.5
    for _, call in ipairs(self.calls) do
        local call_kind = RECT_CALLS[call.name]
        if call_kind and (kind == nil or call_kind == kind) and matches_bounds(call, bounds, tolerance) then
            return call
        end
    end
    return nil
end

function FakeWindow:filled_rect_at(bounds, tolerance)
    return self:rect_at(bounds, "filled", tolerance)
end

function FakeWindow:outline_rect_at(bounds, tolerance)
    return self:rect_at(bounds, "outline", tolerance)
end

return FakeWindow
