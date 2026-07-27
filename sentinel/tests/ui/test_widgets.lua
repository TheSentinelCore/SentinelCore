-- tests/ui/test_widgets.lua
-- The widget library's contract (ADR 09b §3.1, §5.4).
--
-- Everything here is driven through the fake window, so what is actually asserted is the draw
-- tape: which rects were painted at which bounds in which colour, and which hover/click probes
-- were issued. That is the only observation an immediate-mode UI offers outside the client.
--
-- Three properties are swept across EVERY widget rather than spot-checked, because each of them
-- is the kind of thing that is correct on the day it is written and quietly wrong on the widget
-- added six months later: every interactive region probes hover, every disabled widget renders
-- differently and refuses activation, and nothing in the library reaches for the SDK at render
-- time.

local Widgets = require("ui/widgets")
local Theme = require("ui/theme")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 40, y = 60, w = 160, h = 32 }

--- A stand-in for a pre-constructed `core.menu.*` element.
--- Stock elements are built in the tick callback and handed to the widget; this records whether
--- the widget rendered it, which is the whole of the wrapping contract.
local function stock_element(value)
    local e = { renders = 0, labels = {}, _value = value }
    function e:render(label) self.renders = self.renders + 1; self.labels[#self.labels + 1] = label; return false end
    function e:get() return self._value end
    function e:get_state() return self._value end
    return e
end

--- A stable fingerprint of everything the widget painted: call names plus every colour alpha.
--- Used to prove "visually distinct" without pinning any single widget's internal layout.
local function tape_signature(fake)
    local parts = {}
    for _, call in ipairs(fake.calls) do
        parts[#parts + 1] = call.name
        for _, arg in ipairs(call.args) do
            if type(arg) == "table" and arg.a ~= nil and arg.r ~= nil then
                parts[#parts + 1] = string.format("%d/%d/%d/%d", arg.r, arg.g, arg.b, arg.a)
            end
        end
    end
    return table.concat(parts, "|")
end

--- Every widget in the library, invoked at the same bounds, with and without `disabled`.
--- The sweeps below iterate this so a new widget cannot be added without inheriting the rules.
local function invocations()
    return {
        { name = "button", interactive = true,
          call = function(w, b, o) return Widgets.button(w, b, o) end,
          opts = function(o) o.label = "Compile"; return o end },
        { name = "icon_button", interactive = true,
          call = function(w, b, o) return Widgets.icon_button(w, b, o) end,
          opts = function(o) o.glyph = "+"; return o end },
        { name = "list_row", interactive = true,
          call = function(w, b, o) return Widgets.list_row(w, b, o) end,
          opts = function(o) o.label = "Deputy Willem"; return o end },
        { name = "chip", interactive = true,
          call = function(w, b, o) return Widgets.chip(w, b, o) end,
          opts = function(o) o.label = "Elwynn"; return o end },
        { name = "search_field", interactive = true,
          call = function(w, b, o) return Widgets.search_field(w, b, o) end,
          opts = function(o) o.element = stock_element(""); o.placeholder = "Search"; return o end },
        -- `interactive = false` here means "the region this is rendered into is not itself a
        -- control". Both of these are containers whose only clickable part is a nested action, so
        -- hovering their centre correctly changes nothing; the action's own hover response is
        -- covered by the targeted cases further down using the returned action bounds.
        { name = "section_header", interactive = false,
          call = function(w, b, o) return Widgets.section_header(w, b, o) end,
          opts = function(o) o.title = "Steps"; o.action_label = "Add"; return o end },
        { name = "empty_state", interactive = false,
          call = function(w, b, o) return Widgets.empty_state(w, b, o) end,
          opts = function(o)
              o.title = "No campaign open"
              o.message = "Record one, or open an existing route"
              o.action_label = "Record"
              return o
          end },
        { name = "toast", interactive = true,
          call = function(w, b, o) return Widgets.toast(w, b, o) end,
          opts = function(o) o.message = "Profile compiled"; return o end },
        { name = "badge", interactive = false,
          call = function(w, b, o) return Widgets.badge(w, b, o) end,
          opts = function(o) o.label = "12"; return o end },
        { name = "checkbox", interactive = true,
          call = function(w, b, o) return Widgets.checkbox(w, b, o) end,
          opts = function(o) o.element = stock_element(false); o.label = "Loop"; return o end },
        { name = "slider", interactive = true,
          call = function(w, b, o) return Widgets.slider(w, b, o) end,
          opts = function(o) o.element = stock_element(5); o.label = "Radius"; return o end },
        { name = "combobox", interactive = true,
          call = function(w, b, o) return Widgets.combobox(w, b, o) end,
          opts = function(o) o.element = stock_element(1); o.label = "Zone"; o.options = { "A" }; return o end },
    }
end

-- ============================================================================
-- Sweep: hover (ADR 09b §5.4 — "immediate-mode UIs feel dead without it")
-- ============================================================================

function M.test_every_widget_probes_hover_for_its_region()
    for _, w in ipairs(invocations()) do
        local fake = FakeWindow.new()
        w.call(fake, BOUNDS, w.opts({}))
        T.assert_true(#fake:hover_tests() >= 1,
            w.name .. " never asked whether it was hovered")
    end
end

function M.test_every_widget_still_probes_hover_when_disabled()
    -- A pointer that goes dead over a disabled control is how a user concludes the whole panel
    -- has hung. Disabled changes the treatment and the outcome, never the feedback.
    for _, w in ipairs(invocations()) do
        local fake = FakeWindow.new()
        w.call(fake, BOUNDS, w.opts({ disabled = true }))
        T.assert_true(#fake:hover_tests() >= 1,
            w.name .. " stopped reporting hover once disabled")
    end
end

-- ============================================================================
-- Sweep: disabled
-- ============================================================================

function M.test_no_disabled_widget_reports_activation_when_clicked()
    for _, w in ipairs(invocations()) do
        local fake = FakeWindow.new()
        fake:click(BOUNDS)
        local activated = w.call(fake, BOUNDS, w.opts({ disabled = true }))
        T.assert_false(activated == true, w.name .. " activated while disabled")
    end
end

function M.test_no_disabled_widget_even_asks_whether_it_was_clicked()
    -- `is_rect_clicked` is the click's only consumer in an immediate-mode frame. A disabled
    -- widget that probes it swallows the click from whatever sits behind, which reads as the UI
    -- being broken rather than the control being inert.
    for _, w in ipairs(invocations()) do
        local fake = FakeWindow.new()
        fake:click(BOUNDS)
        w.call(fake, BOUNDS, w.opts({ disabled = true }))
        T.assert_equal(#fake:click_tests(), 0,
            w.name .. " probed for a click while disabled")
    end
end

function M.test_every_widget_renders_disabled_differently_from_resting()
    for _, w in ipairs(invocations()) do
        local resting = FakeWindow.new()
        w.call(resting, BOUNDS, w.opts({}))

        local disabled = FakeWindow.new()
        w.call(disabled, BOUNDS, w.opts({ disabled = true }))

        T.assert_true(tape_signature(resting) ~= tape_signature(disabled),
            w.name .. " looks identical enabled and disabled")
    end
end

function M.test_no_disabled_widget_renders_its_stock_element()
    -- Stock `core.menu.*` elements have no disabled mode: rendering one greyed-out is not
    -- possible, so the wrapper draws an inert facsimile instead. If it rendered the real element
    -- the control would still be operable while claiming to be disabled.
    for _, name in ipairs({ "checkbox", "slider", "combobox", "search_field" }) do
        local fake = FakeWindow.new()
        local element = stock_element(false)
        Widgets[name](fake, BOUNDS, {
            element = element, disabled = true, label = "x", options = { "A" }, placeholder = "p",
        })
        T.assert_equal(element.renders, 0, name .. " rendered its live stock element while disabled")
    end
end

-- ============================================================================
-- Sweep: hover treatment actually changes the paint
-- ============================================================================

function M.test_every_widget_paints_differently_when_hovered()
    for _, w in ipairs(invocations()) do
        if w.interactive then
            local resting = FakeWindow.new()
            w.call(resting, BOUNDS, w.opts({}))

            local hovered = FakeWindow.new()
            hovered:hover(BOUNDS)
            w.call(hovered, BOUNDS, w.opts({}))

            T.assert_true(tape_signature(resting) ~= tape_signature(hovered),
                w.name .. " renders identically hovered and unhovered")
        end
    end
end

-- ============================================================================
-- button
-- ============================================================================

function M.test_button_border_carries_the_resting_alpha_when_unhovered()
    local fake = FakeWindow.new()
    Widgets.button(fake, BOUNDS, { label = "Compile" })
    local border = fake:calls_of("render_rect")[1]
    T.assert_not_nil(border, "a button must outline itself")
    T.assert_equal(border.args[3].a, Theme.interaction.resting.border,
        "an unhovered button must sit at the resting border alpha")
end

function M.test_button_border_carries_the_hover_alpha_when_hovered()
    local fake = FakeWindow.new()
    fake:hover(BOUNDS)
    Widgets.button(fake, BOUNDS, { label = "Compile" })
    local border = fake:calls_of("render_rect")[1]
    T.assert_equal(border.args[3].a, Theme.interaction.hover.border,
        "a hovered button must lift to the hover border alpha")
end

function M.test_button_paints_its_surface_at_its_own_bounds()
    local fake = FakeWindow.new()
    Widgets.button(fake, BOUNDS, { label = "Compile" })
    T.assert_not_nil(fake:filled_rect_at(BOUNDS), "the fill must land on the bounds it was given")
end

function M.test_button_draws_its_label()
    local fake = FakeWindow.new()
    Widgets.button(fake, BOUNDS, { label = "Compile" })
    T.assert_true(fake:drew_text("Compile"), "the label must be drawn")
end

function M.test_button_reports_activation_when_clicked()
    local fake = FakeWindow.new()
    fake:click(BOUNDS)
    local activated = Widgets.button(fake, BOUNDS, { label = "Compile" })
    T.assert_true(activated, "a clicked button activates")
end

function M.test_button_does_not_activate_when_the_click_lands_elsewhere()
    local fake = FakeWindow.new()
    fake:click({ x = 500, y = 500, w = 10, h = 10 })
    local activated = Widgets.button(fake, BOUNDS, { label = "Compile" })
    T.assert_false(activated, "a click outside the bounds must not activate")
end

function M.test_button_returns_its_interaction_state()
    local fake = FakeWindow.new()
    fake:hover(BOUNDS)
    local _, state = Widgets.button(fake, BOUNDS, { label = "Compile" })
    T.assert_equal(state, "hover", "the state is returned so callers can drive tooltips from it")
end

function M.test_danger_button_uses_the_danger_token()
    local fake = FakeWindow.new()
    Widgets.button(fake, BOUNDS, { label = "Delete", variant = "danger" })
    local border = fake:calls_of("render_rect")[1]
    T.assert_equal(border.args[3].r, Theme.rgba.danger[1], "a danger button borders in danger")
end

function M.test_button_enforces_the_minimum_hit_height()
    -- A caller that lays out a 12px button gets a 12px CLICK TARGET unless the widget refuses.
    local squashed = { x = 0, y = 0, w = 100, h = 12 }
    local fake = FakeWindow.new()
    fake:set_mouse(50, Theme.metrics.hit_min - 2)
    local _, state = Widgets.button(fake, squashed, { label = "Go" })
    T.assert_equal(state, "hover",
        "the hit region must be grown to hit_min even when the caller under-sizes it")
end

-- ============================================================================
-- icon_button
-- ============================================================================

function M.test_icon_button_draws_its_glyph_in_the_icon_font()
    local fake = FakeWindow.new()
    Widgets.icon_button(fake, { x = 0, y = 0, w = 30, h = 30 }, { glyph = "+" })
    local entry = fake:find_text("+")
    T.assert_not_nil(entry, "the glyph must be drawn")
    T.assert_equal(entry.font_id, Theme.font.icon, "glyphs use the icon font from the type scale")
end

function M.test_icon_button_activates_on_click()
    local b = { x = 0, y = 0, w = 30, h = 30 }
    local fake = FakeWindow.new()
    fake:click(b)
    T.assert_true(Widgets.icon_button(fake, b, { glyph = "+" }), "a clicked icon button activates")
end

-- ============================================================================
-- list_row — resting / hover / selected / disabled must all be distinguishable
-- ============================================================================

function M.test_resting_list_row_paints_no_fill()
    -- A list of forty rows each painting a resting background is visual noise, and it removes the
    -- only channel hover and selection have to speak through.
    local fake = FakeWindow.new()
    Widgets.list_row(fake, BOUNDS, { label = "Deputy Willem" })
    T.assert_nil(fake:filled_rect_at(BOUNDS), "a resting row must not paint a background")
end

function M.test_hovered_list_row_paints_a_raised_fill()
    local fake = FakeWindow.new()
    fake:hover(BOUNDS)
    Widgets.list_row(fake, BOUNDS, { label = "Deputy Willem" })
    local fill = fake:filled_rect_at(BOUNDS)
    T.assert_not_nil(fill, "a hovered row must paint a background")
    T.assert_equal(fill.args[3].r, Theme.rgba.surface_raised[1], "hover uses the raised surface")
end

function M.test_selected_list_row_is_distinct_from_hover()
    local hovered = FakeWindow.new()
    hovered:hover(BOUNDS)
    Widgets.list_row(hovered, BOUNDS, { label = "Deputy Willem" })

    local selected = FakeWindow.new()
    Widgets.list_row(selected, BOUNDS, { label = "Deputy Willem", selected = true })

    T.assert_true(tape_signature(hovered) ~= tape_signature(selected),
        "selection and hover must not look the same, or the current row is unfindable")
end

function M.test_selected_list_row_paints_the_accent_surface()
    local fake = FakeWindow.new()
    Widgets.list_row(fake, BOUNDS, { label = "Deputy Willem", selected = true })
    local fill = fake:filled_rect_at(BOUNDS)
    T.assert_not_nil(fill, "a selected row must paint a background")
    T.assert_equal(fill.args[3].r, Theme.rgba.accent_soft[1], "selection uses the accent surface")
end

function M.test_selected_list_row_carries_an_accent_marker()
    -- The accent-tinted fill is deliberately low-contrast so a long list stays calm; the edge
    -- marker is what survives being scanned at speed.
    local fake = FakeWindow.new()
    Widgets.list_row(fake, BOUNDS, { label = "Deputy Willem", selected = true })
    local marker = fake:filled_rect_at({
        x = BOUNDS.x, y = BOUNDS.y, w = Theme.metrics.selection_marker, h = BOUNDS.h,
    })
    T.assert_not_nil(marker, "a selected row must carry its leading accent marker")
    T.assert_equal(marker.args[3].r, Theme.rgba.accent[1], "the marker is the full accent")
end

function M.test_list_row_draws_its_label_and_its_resolved_secondary()
    -- ADR 09b §5.6: the author writes `Deputy Willem`; the row shows what it resolved to.
    local fake = FakeWindow.new()
    Widgets.list_row(fake, BOUNDS, { label = "Deputy Willem", secondary = "npc:823" })
    T.assert_true(fake:drew_text("Deputy Willem"), "the intent must be drawn")
    T.assert_true(fake:drew_text("npc:823"), "the resolved value must be drawn beside it")
end

function M.test_list_row_activates_on_click()
    local fake = FakeWindow.new()
    fake:click(BOUNDS)
    T.assert_true(Widgets.list_row(fake, BOUNDS, { label = "row" }), "a clicked row activates")
end

function M.test_disabled_list_row_never_activates_even_when_selected()
    local fake = FakeWindow.new()
    fake:click(BOUNDS)
    local activated = Widgets.list_row(fake, BOUNDS,
        { label = "row", selected = true, disabled = true })
    T.assert_false(activated, "disabled outranks selection")
end

-- ============================================================================
-- search_field — wraps the stock text_input
-- ============================================================================

function M.test_search_field_renders_the_stock_element_it_was_handed()
    -- ADR 09b §3.1: we do not re-implement what exists. The widget's job is the frame and the
    -- theme; the text editing stays the SDK's.
    local element = stock_element("")
    local fake = FakeWindow.new()
    Widgets.search_field(fake, BOUNDS, { element = element, placeholder = "Search NPCs" })
    T.assert_equal(element.renders, 1, "the stock element must be rendered exactly once")
end

function M.test_search_field_constructs_nothing()
    -- Sylvannas forbids constructing menu elements in a render callback. Handing `nil` proves the
    -- widget has no fallback that would quietly build one every frame.
    local fake = FakeWindow.new()
    local ok = pcall(Widgets.search_field, fake, BOUNDS, { element = nil, placeholder = "Search" })
    T.assert_true(ok, "a missing element must degrade to the frame, never to construction")
    T.assert_true(fake:drew_text("Search"), "the frame still renders without its element")
end

function M.test_search_field_shows_its_placeholder_only_while_empty()
    local empty = FakeWindow.new()
    Widgets.search_field(empty, BOUNDS, { element = stock_element(""), placeholder = "Search NPCs" })
    T.assert_true(empty:drew_text("Search NPCs"), "an empty field instructs")

    local filled = FakeWindow.new()
    Widgets.search_field(filled, BOUNDS, { element = stock_element("wolf"), placeholder = "Search NPCs" })
    T.assert_false(filled:drew_text("Search NPCs"), "a filled field must not draw over its value")
end

function M.test_search_field_returns_the_current_value()
    local fake = FakeWindow.new()
    local value = Widgets.search_field(fake, BOUNDS, { element = stock_element("wolf") })
    T.assert_equal(value, "wolf", "the field reports what the stock element holds")
end

-- ============================================================================
-- chip
-- ============================================================================

function M.test_chip_is_fully_rounded()
    local fake = FakeWindow.new()
    Widgets.chip(fake, { x = 0, y = 0, w = 80, h = 28 }, { label = "Elwynn" })
    local fill = fake:filled_rect_at({ x = 0, y = 0, w = 80, h = 28 })
    T.assert_not_nil(fill, "a chip paints a fill")
    T.assert_equal(fill.args[4], Theme.radius.pill, "a chip is a pill, not a rectangle")
end

function M.test_selected_chip_uses_the_accent_token()
    local fake = FakeWindow.new()
    Widgets.chip(fake, BOUNDS, { label = "Elwynn", selected = true })
    local fill = fake:filled_rect_at(BOUNDS)
    T.assert_equal(fill.args[3].r, Theme.rgba.accent_soft[1], "a selected chip reads as accent")
end

function M.test_chip_tone_selects_a_semantic_token()
    local fake = FakeWindow.new()
    Widgets.chip(fake, BOUNDS, { label = "unresolved", tone = "danger" })
    T.assert_true(fake:drew_text("unresolved"), "the chip label is drawn")
    local entry = fake:find_text("unresolved")
    T.assert_equal(entry.color.r, Theme.rgba.danger[1], "tone drives the label colour")
end

-- ============================================================================
-- toolbar
-- ============================================================================

function M.test_toolbar_lays_its_items_out_left_to_right()
    local fake = FakeWindow.new()
    local _, results = Widgets.toolbar(fake, { x = 0, y = 0, w = 400, h = Theme.metrics.toolbar_height }, {
        items = {
            { id = "open", kind = "button", label = "Open" },
            { id = "save", kind = "button", label = "Save" },
        },
    })
    T.assert_equal(#results, 2, "both items are laid out")
    T.assert_true(results[2].bounds.x > results[1].bounds.x, "items advance along the bar")
    T.assert_true(results[1].bounds.x >= Theme.space.sm, "items are inset from the bar edge")
end

function M.test_toolbar_reports_which_item_was_activated()
    local bar = { x = 0, y = 0, w = 400, h = Theme.metrics.toolbar_height }
    local fake = FakeWindow.new()
    local _, layout = Widgets.toolbar(fake, bar, {
        items = { { id = "open", kind = "button", label = "Open" },
                  { id = "save", kind = "button", label = "Save" } },
    })

    local clicked = FakeWindow.new()
    clicked:click(layout[2].bounds)
    local activated = Widgets.toolbar(clicked, bar, {
        items = { { id = "open", kind = "button", label = "Open" },
                  { id = "save", kind = "button", label = "Save" } },
    })
    T.assert_equal(activated, "save", "the toolbar reports the id, not the index")
end

function M.test_toolbar_spacer_pushes_the_rest_to_the_right()
    local fake = FakeWindow.new()
    local _, results = Widgets.toolbar(fake, { x = 0, y = 0, w = 400, h = Theme.metrics.toolbar_height }, {
        items = { { id = "open", kind = "button", label = "Open" },
                  { kind = "spacer" },
                  { id = "help", kind = "icon", glyph = "?" } },
    })
    local help = results[#results]
    T.assert_true(help.bounds.x + help.bounds.w >= 400 - Theme.space.sm - 1,
        "a spacer must push trailing items to the far edge")
end

function M.test_toolbar_disabled_item_never_activates()
    local bar = { x = 0, y = 0, w = 400, h = Theme.metrics.toolbar_height }
    local items = { { id = "save", kind = "button", label = "Save", disabled = true } }

    local probe = FakeWindow.new()
    local _, layout = Widgets.toolbar(probe, bar, { items = items })

    local fake = FakeWindow.new()
    fake:click(layout[1].bounds)
    T.assert_nil(Widgets.toolbar(fake, bar, { items = items }),
        "a disabled toolbar item must not report activation")
end

function M.test_toolbar_honours_an_items_own_bounds_width_first()
    -- `bounds.w` is the most explicit per-item declaration: the graph actions row carries
    -- measured rects, and a toolbar that read only `item.width` made those declarations inert.
    local fake = FakeWindow.new()
    local _, layout = Widgets.toolbar(fake, { x = 0, y = 0, w = 600, h = Theme.metrics.toolbar_height }, {
        items = { { id = "wide", kind = "button", label = "Go",
                    bounds = { x = 0, y = 0, w = 180, h = 28 }, width = 40 } },
    })
    T.assert_equal(layout[1].bounds.w, 180, "an item's own bounds.w beats item.width")
end

function M.test_toolbar_honours_item_width_over_measuring()
    local fake = FakeWindow.new()
    local _, layout = Widgets.toolbar(fake, { x = 0, y = 0, w = 600, h = Theme.metrics.toolbar_height }, {
        items = { { id = "explicit", kind = "button", label = "A Rather Long Label", width = 140 } },
    })
    T.assert_equal(layout[1].bounds.w, 140, "an explicit width beats the measured fallback")
end

function M.test_toolbar_measures_a_label_that_would_clip_the_kind_default()
    -- 23 chars * 7 + 2 * space.md = 185, well past the 96 button default: before measuring,
    -- this item clipped to "Generat...".
    local label = "Generate from Recording"
    local fake = FakeWindow.new()
    local _, layout = Widgets.toolbar(fake, { x = 0, y = 0, w = 600, h = Theme.metrics.toolbar_height }, {
        items = { { id = "gen", kind = "button", label = label } },
    })
    T.assert_equal(layout[1].bounds.w, #label * 7 + 2 * Theme.space.md,
        "a label too long for the default width must be measured, not clipped")
end

function M.test_toolbar_measured_width_never_shrinks_below_the_kind_default()
    -- Measuring is a floor-raiser only: short labels keep the strip they have always had, so
    -- existing toolbars do not reflow.
    local fake = FakeWindow.new()
    local _, layout = Widgets.toolbar(fake, { x = 0, y = 0, w = 400, h = Theme.metrics.toolbar_height }, {
        items = { { id = "open", kind = "button", label = "Open" } },
    })
    T.assert_equal(layout[1].bounds.w, 96, "a short label keeps the button default width")
end

-- ============================================================================
-- section_header / empty_state / toast / badge
-- ============================================================================

function M.test_section_header_draws_its_title_in_the_heading_role()
    local fake = FakeWindow.new()
    Widgets.section_header(fake, BOUNDS, { title = "Steps" })
    local entry = fake:find_text("Steps")
    T.assert_not_nil(entry, "the title is drawn")
    T.assert_equal(entry.font_id, Theme.font.heading, "a section title uses the heading role")
end

function M.test_section_header_action_activates_independently_of_the_header()
    local fake = FakeWindow.new()
    fake:click({ x = BOUNDS.x, y = BOUNDS.y, w = 8, h = 8 })   -- the title, not the action
    local activated = Widgets.section_header(fake, BOUNDS, { title = "Steps", action_label = "Add" })
    T.assert_false(activated, "clicking the title must not fire the action")
end

function M.test_section_header_action_responds_to_hover_and_activates()
    local opts = { title = "Steps", action_label = "Add" }
    local probe = FakeWindow.new()
    local _, _, action = Widgets.section_header(probe, BOUNDS, opts)
    T.assert_not_nil(action, "the action bounds must come back so callers can anchor to them")

    local fake = FakeWindow.new()
    fake:click(action)
    local activated, state = Widgets.section_header(fake, BOUNDS, opts)
    T.assert_true(activated, "clicking the action fires it")
    T.assert_equal(state, "active", "the action reports its own interaction state")
end

function M.test_empty_state_action_activates_when_clicked()
    local opts = { title = "No campaign open", message = "Record one", action_label = "Record" }
    local pane = { x = 0, y = 0, w = 400, h = 200 }
    local probe = FakeWindow.new()
    local _, _, action = Widgets.empty_state(probe, pane, opts)
    T.assert_not_nil(action, "an empty state with an action must report where it put it")

    local fake = FakeWindow.new()
    fake:click(action)
    T.assert_true(Widgets.empty_state(fake, pane, opts), "the call to action must be clickable")
end

function M.test_empty_state_draws_its_instructional_text()
    -- ADR 09b §5.5 verbatim: "No campaign open - record one, or open an existing route" beats a
    -- blank pane, especially while the corpus is empty.
    local fake = FakeWindow.new()
    Widgets.empty_state(fake, { x = 0, y = 0, w = 400, h = 200 }, {
        title = "No campaign open",
        message = "Record one, or open an existing route",
    })
    T.assert_true(fake:drew_text("No campaign open"), "the empty state names the situation")
    T.assert_true(fake:drew_text("Record one, or open an existing route"),
        "the empty state instructs rather than apologising")
end

function M.test_empty_state_without_an_action_never_activates()
    local fake = FakeWindow.new()
    fake:click({ x = 0, y = 0, w = 400, h = 200 })
    local activated = Widgets.empty_state(fake, { x = 0, y = 0, w = 400, h = 200 },
        { title = "Nothing here", message = "Do a thing" })
    T.assert_false(activated, "an empty state with no action is not a giant button")
end

function M.test_toast_colours_itself_from_its_tone()
    local fake = FakeWindow.new()
    Widgets.toast(fake, BOUNDS, { message = "Compile failed", tone = "danger" })
    local border = fake:calls_of("render_rect")[1]
    T.assert_equal(border.args[3].r, Theme.rgba.danger[1], "a danger toast borders in danger")
    T.assert_true(fake:drew_text("Compile failed"), "the message is drawn")
end

function M.test_toast_sits_at_the_overlay_elevation()
    -- A toast that shares the panel's surface reads as part of the panel and gets ignored.
    local fake = FakeWindow.new()
    Widgets.toast(fake, BOUNDS, { message = "Saved" })
    local fill = fake:filled_rect_at(BOUNDS)
    T.assert_equal(fill.args[3].r, Theme.rgba.surface_overlay[1], "a toast floats above the panel")
end

function M.test_toast_progress_draws_a_remaining_life_bar()
    local without = FakeWindow.new()
    Widgets.toast(without, BOUNDS, { message = "Saved" })
    local with = FakeWindow.new()
    Widgets.toast(with, BOUNDS, { message = "Saved", progress = 0.5 })
    T.assert_true(#with.calls > #without.calls, "progress must add the life bar")
end

function M.test_badge_draws_its_label_and_reports_hover_without_activating()
    -- The first return means "was this activated" for EVERY widget in the library, badge
    -- included. Hover is reported through the state, so a caller looping over mixed widgets never
    -- has to remember which one returns something else.
    local fake = FakeWindow.new()
    fake:click(BOUNDS)
    local activated, state = Widgets.badge(fake, BOUNDS, { label = "12" })
    T.assert_true(fake:drew_text("12"), "the count is drawn")
    T.assert_false(activated, "a badge never activates, however hard it is clicked")
    T.assert_equal(state, "hover", "it still reports hover so a caller can hang a tooltip on it")
    T.assert_equal(#fake:click_tests(), 0, "a badge is not clickable")
end

function M.test_badge_tone_selects_a_semantic_token()
    local fake = FakeWindow.new()
    Widgets.badge(fake, BOUNDS, { label = "3", tone = "warning" })
    local fill = fake:filled_rect_at(BOUNDS)
    T.assert_equal(fill.args[3].r, Theme.rgba.warning[1], "tone drives the badge fill")
end

-- ============================================================================
-- Stock wrappers
-- ============================================================================

function M.test_stock_wrappers_render_the_element_they_were_handed()
    for _, name in ipairs({ "checkbox", "slider", "combobox" }) do
        local element = stock_element(1)
        local fake = FakeWindow.new()
        Widgets[name](fake, BOUNDS, { element = element, label = "Loop", options = { "A", "B" } })
        T.assert_equal(element.renders, 1, name .. " must render its stock element once")
    end
end

function M.test_stock_wrappers_position_the_element_at_their_bounds()
    -- Stock elements draw at the window's dynamic cursor, not at a rect. Without an explicit
    -- offset the wrapper would paint a themed frame in one place and the control in another.
    for _, name in ipairs({ "checkbox", "slider", "combobox" }) do
        local fake = FakeWindow.new()
        Widgets[name](fake, BOUNDS, { element = stock_element(1), label = "Loop", options = { "A" } })
        T.assert_true(#fake:calls_of("add_menu_element_pos_offset") >= 1,
            name .. " never positioned its stock element")
    end
end

function M.test_disabled_stock_wrapper_still_shows_its_label()
    -- Inert is not invisible: the author has to be able to see what is unavailable.
    local fake = FakeWindow.new()
    Widgets.checkbox(fake, BOUNDS, { element = stock_element(false), label = "Loop", disabled = true })
    T.assert_true(fake:drew_text("Loop"), "a disabled control keeps its label")
end

-- ============================================================================
-- split_pane (ADR 09b §3.1)
-- ============================================================================

function M.test_split_pane_divides_along_the_requested_ratio()
    local fake = FakeWindow.new()
    local layout = Widgets.split_pane(fake, { x = 0, y = 0, w = 400, h = 200 },
        { ratio = 0.25, axis = "x" })
    T.assert_true(math.abs(layout.first.w - 100) <= Theme.metrics.split_handle,
        "the first pane takes its share")
    T.assert_true(layout.second.x > layout.first.x + layout.first.w - 1, "panes do not overlap")
    T.assert_true(layout.first.h == 200 and layout.second.h == 200, "an x split keeps full height")
end

function M.test_split_pane_honours_its_minimum_pane_sizes()
    local fake = FakeWindow.new()
    local layout = Widgets.split_pane(fake, { x = 0, y = 0, w = 400, h = 200 },
        { ratio = 0.01, axis = "x", min_first = 120 })
    T.assert_true(layout.first.w >= 120, "a pane must not be collapsible below its minimum")
end

function M.test_split_pane_reports_its_divider_state()
    local bounds = { x = 0, y = 0, w = 400, h = 200 }
    local probe = FakeWindow.new()
    local layout = Widgets.split_pane(probe, bounds, { ratio = 0.5, axis = "x" })

    local fake = FakeWindow.new()
    fake:hover(layout.divider)
    local hovered = Widgets.split_pane(fake, bounds, { ratio = 0.5, axis = "x" })
    T.assert_equal(hovered.divider_state, "hover", "the divider reports hover so it can be grabbed")
end

-- ============================================================================
-- Structural audits — the rules that only a source scan can enforce
-- ============================================================================

---`widgets.lua` with its comments removed.
---
---The header of that file NAMES the things it must never do ("no `core.menu.*`", "no
---`http_get`"), so an audit that scanned the raw text would fire on the prose documenting the
---rule and never on a real violation. Long comments go first so a `--[[ ]]` block containing a
---`--` line cannot leave a dangling fragment behind.
---
---This deliberately does not parse Lua: a string literal containing `--` would be truncated. No
---widget has one, and the alternative — a parser in a test — is a second implementation to keep
---correct.
local function widgets_source()
    local handle = assert(io.open("sentinel/ui/widgets.lua", "r"),
        "widgets.lua must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " ")
    source = source:gsub("%-%-[^\n]*", " ")
    return source
end

function M.test_the_source_audit_actually_reads_code()
    -- If the comment stripper ever ate the whole file, every audit below would pass vacuously.
    local source = widgets_source()
    T.assert_true(source:find("function Widgets.button", 1, true) ~= nil,
        "the stripped source must still contain the library's code")
    T.assert_nil(source:find("ADR 09b", 1, true), "the stripped source must not contain prose")
end

function M.test_widgets_never_construct_a_menu_element()
    -- Sylvannas creates windows and menu elements in the tick callback ONLY. A `core.menu.*` call
    -- inside this library would fail in the injector and pass every offline test, which is why it
    -- is caught structurally rather than behaviourally.
    local source = widgets_source()
    T.assert_nil(source:find("core%.menu%."), "widgets.lua must never touch core.menu.*")
end

function M.test_widgets_perform_no_io_on_the_render_path()
    -- `register_on_render_window_callback` runs every frame (ADR 09b §2.4).
    local source = widgets_source()
    for _, forbidden in ipairs({ "http_get", "http_post", "read_data_file", "write_data_file",
                                "object_manager", "get_all_objects" }) do
        T.assert_nil(source:find(forbidden, 1, true),
            "widgets.lua reaches for " .. forbidden .. " on the render path")
    end
end

function M.test_widgets_hardcode_no_colour()
    -- Every colour must come from the theme, or five panels stop looking like one product.
    local source = widgets_source()
    T.assert_nil(source:find("[Cc]olor%.new%s*%("), "widgets.lua constructs a raw colour")
    T.assert_nil(source:find("[Cc]olor%.white%s*%("), "widgets.lua uses an SDK preset colour")
    T.assert_nil(source:find("[Cc]olor%.black%s*%("), "widgets.lua uses an SDK preset colour")
end

function M.test_widgets_hold_no_module_state()
    -- "Stateless by construction" (ADR 09b §3.1). A widget that remembers is a widget whose
    -- behaviour depends on which panel rendered first.
    local source = widgets_source()
    T.assert_nil(source:find("\nlocal%s+_?state%s*="), "widgets.lua declares module-level state")
    T.assert_nil(source:find("\nlocal%s+cache%s*="), "widgets.lua declares a module-level cache")
end

return M
