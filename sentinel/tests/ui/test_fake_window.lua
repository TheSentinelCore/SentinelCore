-- tests/ui/test_fake_window.lua
-- The harness itself, under test.
--
-- Registered and written FIRST for the same reason `test_suite_runner` is: every assertion the
-- theme and widget suites make is this file's output. A fake that silently records nothing turns
-- "the hover treatment was drawn" into a tautology, and an immediate-mode UI has no other way to
-- be observed offline. ADR 09b §7 puts the fake in U1 precisely so the state/render split has
-- something to enforce it from day one.

local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local function v2(x, y) return { x = x, y = y } end

-- ============================================================================
-- Recording
-- ============================================================================

function M.test_draw_calls_are_recorded_in_order()
    local fake = FakeWindow.new()
    fake:render_rect_filled(v2(0, 0), v2(10, 10), { r = 1, g = 2, b = 3, a = 4 }, 0)
    fake:render_text(1, v2(2, 2), { r = 5, g = 6, b = 7, a = 8 }, "hello")

    T.assert_equal(#fake.calls, 2, "both draw calls should be recorded")
    T.assert_equal(fake.calls[1].name, "render_rect_filled", "order must be preserved")
    T.assert_equal(fake.calls[2].name, "render_text", "order must be preserved")
end

function M.test_call_arguments_are_recorded_verbatim()
    local fake = FakeWindow.new()
    local col = { r = 9, g = 9, b = 9, a = 77 }
    fake:render_rect(v2(1, 2), v2(3, 4), col, 6, 1.5)

    local call = fake:calls_of("render_rect")[1]
    T.assert_not_nil(call, "render_rect should be recorded")
    T.assert_equal(call.args[3], col, "the colour object must be recorded by identity")
    T.assert_equal(call.args[4], 6, "rounding must be recorded")
    T.assert_equal(call.args[5], 1.5, "thickness must be recorded")
end

function M.test_calls_of_filters_by_name()
    local fake = FakeWindow.new()
    fake:render_text(1, v2(0, 0), {}, "a")
    fake:render_text(1, v2(0, 0), {}, "b")
    fake:render_rect(v2(0, 0), v2(1, 1), {}, 0, 1)

    T.assert_equal(#fake:calls_of("render_text"), 2, "two text calls")
    T.assert_equal(#fake:calls_of("render_rect"), 1, "one outline rect call")
    T.assert_equal(#fake:calls_of("render_circle"), 0, "nothing else was drawn")
end

function M.test_reset_clears_the_recording()
    local fake = FakeWindow.new()
    fake:render_text(1, v2(0, 0), {}, "gone")
    fake:reset()
    T.assert_equal(#fake.calls, 0, "reset must empty the tape")
    T.assert_false(fake:drew_text("gone"), "reset must forget prior text")
end

-- ============================================================================
-- Text assertions — the shape ADR 09b §7 writes out longhand
-- ============================================================================

function M.test_drew_text_matches_a_substring()
    local fake = FakeWindow.new()
    fake:render_text(1, v2(0, 0), {}, "No campaign open - record one, or open an existing route")
    T.assert_true(fake:drew_text("No campaign open"), "substring match is the documented idiom")
end

function M.test_drew_text_is_false_for_copy_that_was_never_drawn()
    local fake = FakeWindow.new()
    fake:render_text(1, v2(0, 0), {}, "Runner")
    T.assert_false(fake:drew_text("Explorer"), "absent copy must not match")
end

function M.test_dynamic_text_counts_as_drawn_text()
    -- Half the repo's existing render code uses `add_text_on_dynamic_pos`, so a fake that only
    -- watched `render_text` would report "nothing was drawn" for a panel that drew everything.
    local fake = FakeWindow.new()
    fake:add_text_on_dynamic_pos({}, "Quest log sync")
    T.assert_true(fake:drew_text("Quest log sync"), "dynamic text must be visible to assertions")
end

function M.test_find_text_returns_the_entry_with_its_colour()
    local fake = FakeWindow.new()
    local col = { r = 1, g = 2, b = 3, a = 200 }
    fake:render_text(3, v2(4, 5), col, "Campaign")

    local entry = fake:find_text("Campaign")
    T.assert_not_nil(entry, "the entry should be found")
    T.assert_equal(entry.color, col, "colour must come back for treatment assertions")
    T.assert_equal(entry.font_id, 3, "font id must come back for type-scale assertions")
end

function M.test_special_characters_in_a_needle_are_matched_literally()
    -- UI copy is full of `(`, `)`, `-` and `.`; a pattern-based match would make
    -- `drew_text("npc:823 (-8933.5)")` silently true or silently an error.
    local fake = FakeWindow.new()
    fake:render_text(1, v2(0, 0), {}, "npc:823 - (-8933.5, -136.5)")
    T.assert_true(fake:drew_text("(-8933.5, -136.5)"), "needle must be treated as plain text")
    T.assert_false(fake:drew_text("npc:823%s+X"), "a Lua pattern must not match as a pattern")
end

-- ============================================================================
-- Geometry assertions
-- ============================================================================

function M.test_rect_at_finds_a_rect_by_its_bounds()
    local fake = FakeWindow.new()
    fake:render_rect_filled(v2(10, 20), v2(110, 50), {}, 6)

    local found = fake:rect_at({ x = 10, y = 20, w = 100, h = 30 })
    T.assert_not_nil(found, "a rect drawn at those bounds must be findable")
    T.assert_equal(found.name, "render_rect_filled", "the matching call is returned")
end

function M.test_rect_at_returns_nil_when_nothing_matches()
    local fake = FakeWindow.new()
    fake:render_rect_filled(v2(10, 20), v2(110, 50), {}, 6)
    T.assert_nil(fake:rect_at({ x = 0, y = 0, w = 10, h = 10 }), "a different rect must not match")
end

function M.test_filled_rect_at_ignores_outline_rects()
    local fake = FakeWindow.new()
    fake:render_rect(v2(0, 0), v2(50, 20), {}, 0, 1)

    T.assert_not_nil(fake:rect_at({ x = 0, y = 0, w = 50, h = 20 }), "rect_at sees outlines")
    T.assert_nil(fake:filled_rect_at({ x = 0, y = 0, w = 50, h = 20 }),
        "filled_rect_at must not report an outline as a fill")
end

-- ============================================================================
-- Pointer simulation
-- ============================================================================

function M.test_nothing_is_hovered_until_the_pointer_is_placed()
    -- A fake that starts at (0,0) would hover every widget anchored at the origin, which is most
    -- of them — so the resting-state half of every widget test would be untestable.
    local fake = FakeWindow.new()
    T.assert_false(fake:is_mouse_hovering_rect(v2(0, 0), v2(100, 40)),
        "a fresh fake must report no hover anywhere")
end

function M.test_hover_follows_the_pointer()
    local fake = FakeWindow.new()
    fake:set_mouse(50, 20)
    T.assert_true(fake:is_mouse_hovering_rect(v2(0, 0), v2(100, 40)), "pointer is inside")
    T.assert_false(fake:is_mouse_hovering_rect(v2(200, 0), v2(300, 40)), "pointer is outside")
end

function M.test_hover_bounds_are_inclusive_of_their_edges()
    local fake = FakeWindow.new()
    fake:set_mouse(100, 40)
    T.assert_true(fake:is_mouse_hovering_rect(v2(0, 0), v2(100, 40)),
        "the bottom-right edge belongs to the rect")
end

function M.test_hover_helper_centres_the_pointer_on_a_rect()
    local fake = FakeWindow.new()
    fake:hover({ x = 300, y = 100, w = 80, h = 30 })
    T.assert_true(fake:is_mouse_hovering_rect(v2(300, 100), v2(380, 130)), "helper hovers the rect")
    T.assert_false(fake:is_mouse_hovering_rect(v2(0, 0), v2(80, 30)), "and nothing else")
end

function M.test_hover_tests_are_recorded()
    -- ADR 09b §5.4 makes "every interactive region reports hover" a rule; the widget suite proves
    -- it by counting these, so the fake has to keep them.
    local fake = FakeWindow.new()
    fake:is_mouse_hovering_rect(v2(0, 0), v2(10, 10))
    T.assert_equal(#fake:hover_tests(), 1, "hover probes must be recorded, not just answered")
end

function M.test_click_only_fires_inside_the_clicked_rect()
    local fake = FakeWindow.new()
    fake:set_click(50, 20)
    T.assert_true(fake:is_rect_clicked(v2(0, 0), v2(100, 40)), "click point is inside")
    T.assert_false(fake:is_rect_clicked(v2(200, 0), v2(300, 40)), "click point is outside")
end

function M.test_click_helper_targets_a_rect()
    local fake = FakeWindow.new()
    fake:click({ x = 10, y = 10, w = 40, h = 20 })
    T.assert_true(fake:is_rect_clicked(v2(10, 10), v2(50, 30)), "helper clicks the rect")
end

function M.test_clicking_also_places_the_pointer()
    -- A real click cannot happen without the pointer being there; a fake that lets them diverge
    -- would let a widget pass its click test while claiming it was never hovered.
    local fake = FakeWindow.new()
    fake:click({ x = 10, y = 10, w = 40, h = 20 })
    T.assert_true(fake:is_mouse_hovering_rect(v2(10, 10), v2(50, 30)),
        "a click implies hover at the same point")
end

function M.test_clear_click_releases_the_button()
    local fake = FakeWindow.new()
    fake:click({ x = 10, y = 10, w = 40, h = 20 })
    fake:clear_click()
    T.assert_false(fake:is_rect_clicked(v2(10, 10), v2(50, 30)), "the click is gone")
end

function M.test_click_probes_are_recorded()
    -- The disabled-widget contract is "never even asks whether it was clicked"; without this the
    -- suite could only observe the return value, which is false for a great many other reasons.
    local fake = FakeWindow.new()
    fake:is_rect_clicked(v2(0, 0), v2(10, 10))
    T.assert_equal(#fake:click_tests(), 1, "click probes must be recorded")
end

-- ============================================================================
-- Window surface parity — the calls a real panel will make
-- ============================================================================

function M.test_begin_runs_its_callback_and_is_recorded()
    local fake = FakeWindow.new()
    local ran = false
    fake:begin(0, true, {}, {}, 0, function() ran = true end)
    T.assert_true(ran, "begin must execute the body so panels can be driven through it")
    T.assert_equal(#fake:calls_of("begin"), 1, "begin itself is recorded")
end

function M.test_begin_group_runs_its_callback()
    local fake = FakeWindow.new()
    local ran = false
    fake:begin_group(function() ran = true end)
    T.assert_true(ran, "group bodies must execute")
end

function M.test_text_measurement_is_deterministic()
    -- Layout code divides by text width. A fake that returned 0 would make every centred element
    -- land at the same place and every overflow test pass.
    local fake = FakeWindow.new()
    local size = fake:get_text_size("abcd")
    T.assert_true(size.x > 0, "measured width must be positive")
    T.assert_equal(fake:get_text_size("abcdabcd").x, size.x * 2, "width must scale with length")
end

-- ============================================================================
-- Argument typing — the fake stands in for a TYPED C API
-- ============================================================================
-- Every `window:*` method is a C binding. A wrong argument type does not degrade, it raises
-- `bad argument #N to '<fn>' (<expected> expected, got <actual>)` from inside
-- `register_on_render_window_callback`, which aborts the frame wherever it happened to be — chrome
-- painted, body not. A fake that accepted anything would certify exactly that code, and it did:
-- `shell.lua` shipped a string animation id and a pair of bare numbers where vec2 are required,
-- the suite stayed green, and the live client logged the throw on every frame the tab marker moved.

function M.test_animate_widget_rejects_a_string_animation_id()
    -- The proven failure, reproduced offline. `guides/custom-ui.md` §Advanceds-1: "parameter 1: the
    -- id of the animation (integer)".
    local fake = FakeWindow.new()
    local ok, err = pcall(function()
        fake:animate_widget("sentinel_ide_tab_marker", v2(0, 0), v2(80, 0), 120, 255, 1, 1, false)
    end)
    T.assert_false(ok, "a string animation id must raise here exactly as it does in the injector")
    T.assert_true(tostring(err):find("animate_widget", 1, true) ~= nil,
        "and name the call, or the failure is unattributable")
end

function M.test_animate_widget_rejects_a_fractional_animation_id()
    -- A number is not enough: the binding takes an integer, so an id derived by arithmetic that
    -- happens to land on a fraction fails in the injector and nowhere else.
    local fake = FakeWindow.new()
    local ok = pcall(function()
        fake:animate_widget(1.5, v2(0, 0), v2(80, 0), 120, 255, 1, 1, false)
    end)
    T.assert_false(ok, "a fractional animation id must be refused")
end

function M.test_animate_widget_rejects_a_scalar_where_a_vec2_is_required()
    -- The second half of the same bug. A marker that only travels along x is still animated
    -- between two POSITIONS, and passing the bare coordinate raises `bad argument #2`.
    local fake = FakeWindow.new()
    T.assert_false(pcall(function()
        fake:animate_widget(1, 0, v2(80, 0), 120, 255, 1, 1, false)
    end), "a scalar start position must be refused")
    T.assert_false(pcall(function()
        fake:animate_widget(1, v2(0, 0), 80, 120, 255, 1, 1, false)
    end), "a scalar end position must be refused")
end

function M.test_animate_widget_accepts_the_documented_signature_and_settles_on_the_end_position()
    local fake = FakeWindow.new()
    local anim = fake:animate_widget(1, v2(0, 4), v2(80, 4), 120, 255, 1, 1, false)
    T.assert_equal(anim.current_position.x, 80, "the settled frame is the end position")
    T.assert_equal(anim.alpha, 255, "carrying the max alpha it was given")
    T.assert_equal(#fake:calls_of("animate_widget"), 1, "and the call is still recorded")
end

function M.test_push_font_rejects_a_font_name()
    -- `api/ui-custom.md` documents `push_font(font_id)` as an integer enum member. A theme that
    -- regressed to a string would paint nothing in the injector and everything offline.
    local fake = FakeWindow.new()
    T.assert_false(pcall(function() fake:push_font("FONT_BIG") end),
        "a font name must be refused; the binding takes the enum's integer")
end

function M.test_positional_draw_calls_reject_a_scalar_position()
    local fake = FakeWindow.new()
    T.assert_false(pcall(function() fake:render_rect_filled(0, v2(10, 10), {}, 0) end),
        "render_rect_filled takes two vec2, not two coordinates")
    T.assert_false(pcall(function() fake:render_text(1, 0, {}, "x") end),
        "render_text takes a vec2 offset")
    T.assert_false(pcall(function() fake:is_mouse_hovering_rect(v2(0, 0), 10) end),
        "the pointer predicates take two vec2")
end

function M.test_unknown_window_methods_are_absent_rather_than_silently_true()
    -- If the fake answered every call, a panel calling a method Sylvannas does not have would pass
    -- offline and error in the injector — the exact class of bug offline tests exist to catch.
    local fake = FakeWindow.new()
    T.assert_nil(rawget(getmetatable(fake).__index, "render_hologram"),
        "the fake must only implement the documented window surface")
end

return M
