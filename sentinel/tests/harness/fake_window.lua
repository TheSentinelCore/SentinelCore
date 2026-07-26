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

-- ============================================================================
-- Argument typing — because the thing being faked is a TYPED C API
-- ============================================================================
-- Every `window:*` method is a C binding. Handing one the wrong type does not degrade; it raises
-- `bad argument #N to '<fn>' (<expected> expected, got <actual>)` from inside
-- `register_on_render_window_callback`, aborting the frame wherever it happened to be.
--
-- A fake that accepted anything CERTIFIED that code, and it did exactly that: `shell.lua` passed a
-- string animation id and two bare coordinates where `animate_widget` documents an integer and two
-- vec2 (`api/ui-custom.md`, "Animate Widget"). The suite stayed green through every commit while
-- the live client logged the throw on every frame the tab marker moved, and the operator saw the
-- shell's chrome drawn over a body that had never been repainted.
--
-- So the types the SDK enforces are enforced here. Only the documented ones: a check the docs do
-- not state would fail code the injector accepts, which is the same lie in the other direction.

--- Word-for-word the shape the injector raises, so a test failure here reads the same as the client
--- log that sent you looking.
local function type_error(index, method, expected, got)
    return string.format("bad argument #%d to '%s' (%s expected, got %s)",
        index, method, expected, type(got))
end

local function expect_integer(value, index, method)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value ~= math.floor(value) then
        return type_error(index, method, "number", value)
    end
end

local function expect_number(value, index, method)
    if type(value) ~= "number" then return type_error(index, method, "number", value) end
end

local function expect_boolean(value, index, method)
    if type(value) ~= "boolean" then return type_error(index, method, "boolean", value) end
end

--- A vec2 is duck-typed rather than checked against `common/geometry/vector_2`: that module exists
--- only inside the injector, so requiring it here would make the harness unloadable offline — the
--- one place it has to work.
local function expect_vec2(value, index, method)
    if type(value) ~= "table" or type(value.x) ~= "number" or type(value.y) ~= "number" then
        return type_error(index, method, "vec2", value)
    end
end

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

local CHECKS = {
    int = expect_integer, num = expect_number, vec2 = expect_vec2, bool = expect_boolean,
}

--- Positional argument types, transcribed from `api/ui-custom.md`. A `false` slot is one whose type
--- the docs leave open (colours, optional flags, text) and is deliberately unchecked — a rule the
--- docs do not state would reject code the injector accepts, which is the same lie inverted.
local SIGNATURES = {
    render_text                        = { "int", "vec2" },
    render_rect                        = { "vec2", "vec2" },
    render_rect_filled                 = { "vec2", "vec2" },
    render_rect_filled_multicolor      = { "vec2", "vec2" },
    render_circle                      = { "vec2", "num" },
    render_circle_filled               = { "vec2", "num" },
    render_circle_percentage           = { "vec2", "vec2" },
    render_line                        = { "vec2", "vec2" },
    render_triangle                    = { "vec2", "vec2", "vec2" },
    render_triangle_filled             = { "vec2", "vec2", "vec2" },
    render_triangle_filled_multi_color = { "vec2", "vec2", "vec2" },
    render_bezier_quadratic            = { "vec2", "vec2", "vec2" },
    render_bezier_cubic                = { "vec2", "vec2", "vec2", "vec2" },
    push_font                          = { "int" },
    is_mouse_hovering_rect             = { "vec2", "vec2" },
    is_rect_clicked                    = { "vec2", "vec2" },
    is_rect_double_clicked             = { "vec2", "vec2" },
    set_initial_size                   = { "vec2" },
    set_initial_position               = { "vec2" },
    set_visibility                     = { "bool" },
    add_menu_element_pos_offset        = { "vec2" },
    set_next_close_cross_pos_offset    = { "vec2" },
    force_next_begin_window_pos        = { "vec2" },
    set_next_window_items_spacing      = { "vec2" },
    set_next_window_items_inner_spacing = { "vec2" },
    set_next_window_padding            = { "vec2" },
    set_next_window_min_size           = { "vec2" },
    make_loading_circle_animation      = { "int", "vec2", "num" },
    animate_widget = { "int", "vec2", "vec2", "int", "int", "num", "num", "bool" },
}

--- Raise on the first argument whose type the SDK would refuse. Called from the method itself so
--- `error(_, 2)` blames the render code that passed the argument rather than the harness.
local function check_args(method, ...)
    local signature = SIGNATURES[method]
    if not signature then return end
    for index, kind in ipairs(signature) do
        local message = CHECKS[kind](select(index, ...), index, method)
        if message then error(message, 3) end
    end
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
    check_args("is_mouse_hovering_rect", rect_min, rect_max)
    self:_record("is_mouse_hovering_rect", rect_min, rect_max)
    return contains(self._mouse, rect_min, rect_max)
end

function FakeWindow:is_rect_clicked(rect_min, rect_max)
    check_args("is_rect_clicked", rect_min, rect_max)
    self:_record("is_rect_clicked", rect_min, rect_max)
    return contains(self._click, rect_min, rect_max)
end

function FakeWindow:is_rect_double_clicked(rect_min, rect_max)
    check_args("is_rect_double_clicked", rect_min, rect_max)
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
        check_args(name, ...)
        self:_record(name, ...)
    end
end

function FakeWindow:add_text_on_dynamic_pos(color, text)
    self:_record("add_text_on_dynamic_pos", color, text)
    self._dynamic.y = self._dynamic.y + self._line_height
end

function FakeWindow:add_menu_element_pos_offset(pos_offset)
    check_args("add_menu_element_pos_offset", pos_offset)
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

function FakeWindow:set_initial_size(size)
    check_args("set_initial_size", size); self:_record("set_initial_size", size)
end

function FakeWindow:set_initial_position(pos)
    check_args("set_initial_position", pos); self:_record("set_initial_position", pos)
end

function FakeWindow:set_visibility(v)
    check_args("set_visibility", v)
    self:_record("set_visibility", v)
    self.visible = v
end

function FakeWindow:is_being_shown() return self.visible end
function FakeWindow:get_type() return 0 end

---Deterministic stand-in for `animate_widget`: reports the animation already finished, so a test
---observes the settled frame rather than an arbitrary point on a curve.
---
---The full signature is type-checked. This is the one call whose permissiveness was PROVEN to have
---shipped a crash: a string id and two scalar positions passed every offline run and threw on every
---animating frame in the injector.
function FakeWindow:animate_widget(id, from, to, start_alpha, max_alpha, alpha_speed,
                                   movement_speed, only_once)
    check_args("animate_widget", id, from, to, start_alpha, max_alpha, alpha_speed,
        movement_speed, only_once)
    self:_record("animate_widget", id, from, to, start_alpha, max_alpha, alpha_speed,
        movement_speed, only_once)
    -- A COPY, not the caller's table. Returning `to` itself let a render layer mutate the argument
    -- it had just passed and see the change reflected in the "result".
    return { current_position = { x = to.x, y = to.y }, alpha = max_alpha }
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
