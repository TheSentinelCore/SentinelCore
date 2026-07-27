-- sentinel/ui/widgets.lua
-- The IDE's widget library (ADR 09b §3.1).
--
-- WHAT A WIDGET IS HERE
-- --------------------
-- `Widgets.<name>(window, bounds, opts) -> activated, state`
--
-- `bounds` is an explicit `{ x, y, w, h }` rect and `opts` is data. Nothing is remembered between
-- calls: selection, focus, scroll position and text all live in the caller's model, which is the
-- half ADR 09b §2.1 requires to be offline-testable. A widget that remembered anything would put
-- state back inside a render callback, where nothing can observe it.
--
-- THE THREE RULES THAT ARE SWEPT ACROSS EVERY WIDGET BY THE TESTS
-- ---------------------------------------------------------------
--  1. EVERY interactive region issues exactly one `is_mouse_hovering_rect`, disabled included.
--     A pointer that goes dead over a disabled control is how a user concludes the panel hung.
--  2. A DISABLED widget never calls `is_rect_clicked`. In an immediate-mode frame that predicate
--     is the click's consumer; probing it swallows the click from whatever sits behind, which
--     reads as the UI being broken rather than the control being inert.
--  3. NO `core.menu.*` ANYWHERE IN THIS FILE. Sylvannas constructs windows and menu elements in
--     the tick callback only, so stock elements arrive through `opts.element` already built.
--     Getting this wrong fails in the injector and passes every offline test, which is why
--     `test_widgets.lua` also scans this file's source for it.
--
-- No HTTP, no file IO, no object-manager scan: `register_on_render_window_callback` runs every
-- frame (ADR 09b §2.4).

local Theme = require("ui/theme")
local TextInputState = require("ui/text_input_state")

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then return mod end
    return fallback
end

-- Guarded exactly as `theme.lua` guards its own, so the widget layer stays
-- loadable and renderable with no injector present (`tests/ui/test_offline_loadable.lua`).
local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y) return { x = x or 0, y = y or 0 } end,
})

local Widgets = {}

-- ============================================================================
-- Internals
-- ============================================================================

local function v2(x, y) return Vec2.new(x, y) end

---A widget's hit region, which is NOT always the rect it was asked to draw in.
---A caller that lays out a 12px-tall button would otherwise get a 12px click target; ADR 09b §3
---sets a floor because this window sits over moving scenery and is driven by a mouse that is also
---steering a character.
local function hit_bounds(bounds)
    local h = math.max(bounds.h, Theme.metrics.hit_min)
    local w = math.max(bounds.w, Theme.metrics.hit_min)
    return { x = bounds.x, y = bounds.y, w = w, h = h }
end

local function corners(bounds)
    return v2(bounds.x, bounds.y), v2(bounds.x + bounds.w, bounds.y + bounds.h)
end

---One hover probe, one conditional click probe, one resolved state. Every widget goes through
---here so rules 1 and 2 above hold by construction rather than by review.
---@return boolean clicked, string state, boolean hovered
local function probe(window, bounds, opts)
    local region = hit_bounds(bounds)
    local mn, mx = corners(region)

    local hovered = window:is_mouse_hovering_rect(mn, mx) and true or false
    local disabled = opts.disabled and true or false

    local clicked = false
    if not disabled then
        clicked = window:is_rect_clicked(mn, mx) and true or false
    end

    local state = Theme.resolve_state({
        disabled = disabled,
        active = clicked or opts.active,
        hovered = hovered,
        focused = opts.focused,
    })
    return clicked, state, hovered
end

---Fill + optional outline at `bounds`, both taking their alpha from the interaction state.
---This is the alpha-shift idiom from `guides/custom-ui.md`, applied in exactly one place so that
---every clickable region in the IDE responds identically.
local function draw_surface(window, bounds, state, spec)
    local alphas = Theme.interaction[state]
    local mn, mx = corners(bounds)
    local rounding = spec.rounding or Theme.radius.md

    if spec.fill_token then
        window:render_rect_filled(mn, mx, Theme.color[spec.fill_token](spec.fill_alpha or alphas.fill), rounding)
    end
    if spec.border_token then
        window:render_rect(mn, mx, Theme.color[spec.border_token](alphas.border),
            rounding, spec.thickness or Theme.metrics.border_thickness)
    end
end

---Vertically centred text baseline for a role inside `bounds`.
local function centred_y(bounds, role)
    return bounds.y + (bounds.h - Theme.line_height[role]) * 0.5
end

---Exact text size when the window supports measurement, otherwise the legacy approximation.
---The Sylvannas API exposes `window:get_text_size(str)` (ui-custom.md §Get Text Size); using it
---inside a render callback fixes button labels that looked off-centre on the live font.
---
---`get_text_size` returns a `vec2` userdata, not a Lua table, so we read `.x`/`.y` through the
---metatable rather than rejecting non-tables.
local function measure_text(window, text)
    text = tostring(text or "")
    if type(window.get_text_size) == "function" then
        local ok, size = pcall(window.get_text_size, window, text)
        if ok and size ~= nil and tonumber(size.x) then
            return tonumber(size.x), tonumber(size.y)
        end
    end
    return #text * APPROX_CHAR_WIDTH, Theme.line_height.body
end

local function measure_text_width(window, text)
    local w, _ = measure_text(window, text)
    return w
end

---The semantic token a `tone` maps to, defaulting to the neutral copy colour.
local TONE_TOKENS = {
    neutral = "text_secondary", accent = "accent",
    success = "success", warning = "warning", danger = "danger", info = "info",
}
local function tone_token(tone, fallback)
    return TONE_TOKENS[tone or ""] or fallback or "text_secondary"
end

---`opts.label` truncated to fit `width`, with an ellipsis when it had to be cut.
---Layout maths uses `Theme.line_height`-style constants rather than `get_text_size` because
---measurement is only available inside a render callback and every caller needs to reason about
---widths before one exists.
local APPROX_CHAR_WIDTH = 7
local function fit(text, width)
    text = tostring(text or "")
    local max_chars = math.floor(width / APPROX_CHAR_WIDTH)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

-- ============================================================================
-- button
-- ============================================================================

local BUTTON_VARIANTS = {
    primary   = { fill_token = "accent_soft",     border_token = "accent",        text_token = "text_primary" },
    secondary = { fill_token = "surface_raised",  border_token = "border_strong", text_token = "text_primary" },
    ghost     = { fill_token = nil,               border_token = "border",        text_token = "text_secondary" },
    danger    = { fill_token = "surface_raised",  border_token = "danger",        text_token = "danger" },
}

---@param opts table { label, variant, disabled, active, focused }
---@return boolean activated, string state
function Widgets.button(window, bounds, opts)
    opts = opts or {}
    local clicked, state = probe(window, bounds, opts)
    local variant = BUTTON_VARIANTS[opts.variant or "secondary"] or BUTTON_VARIANTS.secondary

    draw_surface(window, bounds, state, {
        fill_token = variant.fill_token,
        border_token = variant.border_token,
        rounding = Theme.radius.md,
    })

    -- NO TRUNCATION: the caller must provide sufficient width for the label
    local label = tostring(opts.label or "")
    local text_w = measure_text_width(window, label)
    local text_x = bounds.x + (bounds.w - text_w) * 0.5
    window:render_text(Theme.font.body, v2(text_x, centred_y(bounds, "body")),
        Theme.color[variant.text_token](Theme.interaction[state].text), label)

    return clicked, state
end

-- ============================================================================
-- icon_button
-- ============================================================================

---@param opts table { glyph, disabled, active, tone }
---@return boolean activated, string state
function Widgets.icon_button(window, bounds, opts)
    opts = opts or {}
    local clicked, state = probe(window, bounds, opts)

    draw_surface(window, bounds, state, {
        -- No resting fill: a toolbar of six filled squares is heavier than the actions it offers.
        -- The border alone carries the affordance until the pointer arrives.
        fill_token = (state == "resting") and nil or "surface_raised",
        border_token = "border",
        rounding = Theme.radius.sm,
    })

    local glyph = tostring(opts.glyph or "")
    local glyph_w = measure_text_width(window, glyph)
    local x = bounds.x + (bounds.w - glyph_w) * 0.5
    window:render_text(Theme.font.icon, v2(x, centred_y(bounds, "body")),
        Theme.color[tone_token(opts.tone, "text_primary")](Theme.interaction[state].text), glyph)

    return clicked, state
end

-- ============================================================================
-- list_row
-- ============================================================================

---A row in an explorer, a search result, a step list.
---
---Resting rows paint NO background. Forty rows each painting one is visual noise, and it spends
---the only channel hover and selection have to speak through. Selection is a tinted surface PLUS
---a leading accent marker, because the tint is deliberately calm and the marker is what survives
---being scanned at speed.
---@param opts table { label, secondary, selected, disabled, leading, trailing, tone }
---@return boolean activated, string state
function Widgets.list_row(window, bounds, opts)
    opts = opts or {}
    local clicked, state = probe(window, bounds, opts)
    local selected = opts.selected and not opts.disabled

    local fill_token
    if selected then
        fill_token = "accent_soft"
    elseif state == "hover" or state == "active" then
        fill_token = "surface_raised"
    end

    if fill_token then
        draw_surface(window, bounds, state, {
            fill_token = fill_token,
            fill_alpha = selected and 255 or Theme.interaction[state].fill,
            rounding = Theme.radius.sm,
        })
    end

    if selected then
        local mn, mx = corners({
            x = bounds.x, y = bounds.y, w = Theme.metrics.selection_marker, h = bounds.h,
        })
        window:render_rect_filled(mn, mx, Theme.color.accent(), Theme.radius.none)
    end

    local text_x = bounds.x + Theme.space.md
    local label_token = opts.disabled and "text_muted" or (selected and "text_primary" or "text_secondary")
    local alphas = Theme.interaction[state]

    if opts.secondary then
        -- ADR 09b §5.6: the author writes `Deputy Willem`, the row also shows `npc:823`. The
        -- resolved value sits on the caption line so the intent stays the thing being read.
        local top = bounds.y + (bounds.h - Theme.line_height.body - Theme.line_height.caption) * 0.5
        window:render_text(Theme.font.body, v2(text_x, top),
            Theme.color[label_token](alphas.text), fit(opts.label, bounds.w - Theme.space.xl))
        window:render_text(Theme.font.caption, v2(text_x, top + Theme.line_height.body),
            Theme.color.text_muted(alphas.text), fit(opts.secondary, bounds.w - Theme.space.xl))
    else
        window:render_text(Theme.font.body, v2(text_x, centred_y(bounds, "body")),
            Theme.color[label_token](alphas.text), fit(opts.label, bounds.w - Theme.space.xl))
    end

    return clicked, state
end

-- ============================================================================
-- search_field — wraps the stock text_input
-- ============================================================================

---Reads a stock element's current text through whichever accessor it exposes.
---`text_input` is named in ADR 09b §1 as available but is not in `docs/SylvannasAPI`, so the
---accessor is probed rather than assumed. Guessing one and being wrong would show the placeholder
---permanently over a field that already has a value.
local function element_value(element)
    if not element then return "" end
    if type(element.get) == "function" then
        local ok, value = pcall(element.get, element)
        if ok and value ~= nil then return tostring(value) end
    end
    if type(element.get_text) == "function" then
        local ok, value = pcall(element.get_text, element)
        if ok and value ~= nil then return tostring(value) end
    end
    return ""
end

---@param opts table { element, label, placeholder, disabled }
---@return string value, string state
function Widgets.search_field(window, bounds, opts)
    opts = opts or {}
    local _, state, hovered = probe(window, bounds, opts)
    local value = element_value(opts.element)

    draw_surface(window, bounds, state, {
        fill_token = "surface_raised",
        border_token = hovered and "accent" or "border",
        rounding = Theme.radius.md,
    })

    if value == "" and opts.placeholder then
        -- Instructional rather than decorative: an empty search box that says nothing is the same
        -- blank pane ADR 09b §5.5 rules out everywhere else.
        window:render_text(Theme.font.body, v2(bounds.x + Theme.space.md, centred_y(bounds, "body")),
            Theme.color.text_muted(Theme.interaction[state].text),
            fit(opts.placeholder, bounds.w - Theme.space.xl))
    end

    if opts.disabled or not opts.element then
        -- The stock element has no disabled mode, so rendering it greyed-out is not possible; and
        -- constructing a replacement here would violate the tick-only rule. An inert frame is the
        -- only honest option.
        return value, state
    end

    window:add_menu_element_pos_offset(v2(bounds.x, bounds.y))
    opts.element:render(opts.label or "")
    return element_value(opts.element), state
end

-- ============================================================================
-- chip
-- ============================================================================

---@param opts table { label, tone, selected, disabled }
---@return boolean activated, string state
function Widgets.chip(window, bounds, opts)
    opts = opts or {}
    local clicked, state = probe(window, bounds, opts)
    local selected = opts.selected and not opts.disabled

    draw_surface(window, bounds, state, {
        fill_token = selected and "accent_soft" or "surface_raised",
        border_token = selected and "accent" or "border",
        rounding = Theme.radius.pill,
    })

    local label = tostring(opts.label or "")
    local label_w = measure_text_width(window, label)
    local x = bounds.x + (bounds.w - label_w) * 0.5
    window:render_text(Theme.font.caption, v2(x, centred_y(bounds, "caption")),
        Theme.color[tone_token(opts.tone, selected and "text_primary" or "text_secondary")](
            Theme.interaction[state].text),
        label)

    return clicked, state
end

-- ============================================================================
-- toolbar
-- ============================================================================

local TOOLBAR_DEFAULT_WIDTH = {
    button = 96, icon = Theme.metrics.icon_button, chip = 88, spacer = 0,
}

---Lays items left to right inside a raised bar and dispatches each to its widget.
---
---Returns the ACTIVATED ITEM'S ID rather than an index, so a caller's dispatch does not silently
---change meaning when an item is inserted. The second return is the full layout, which is what
---makes a toolbar testable: a test can locate an item's bounds and then click them.
---@param opts table { items = { { id, kind, label, glyph, disabled, width, bounds } }, elevation }
---@return string|nil activated_id, table layout
function Widgets.toolbar(window, bounds, opts)
    opts = opts or {}
    local items = opts.items or {}
    local elevation = Theme.elevation[opts.elevation or "raised"]

    local mn, mx = corners(bounds)
    window:render_rect_filled(mn, mx, elevation.fill(), Theme.radius.none)
    window:render_rect_filled(v2(bounds.x, bounds.y + bounds.h - Theme.metrics.divider),
        v2(bounds.x + bounds.w, bounds.y + bounds.h), elevation.border(), Theme.radius.none)

    -- Two passes. Widths are resolved first so a `spacer` can hand its slack to the items after
    -- it; a single pass would have to guess how much room the trailing items need.
    local widths, fixed_total, spacers = {}, 0, 0
    for i, item in ipairs(items) do
        if item.kind == "spacer" then
            spacers = spacers + 1
            widths[i] = 0
        else
            -- Per-item width, most explicit first: an item that carries its own rect wins over a
            -- bare `width`, and both win over measuring the label. Measuring FLOORS at the kind's
            -- default, so a short label keeps the strip it has always had while a long one can no
            -- longer clip (the Runner panel measures the same way).
            local min_w = TOOLBAR_DEFAULT_WIDTH[item.kind or "button"] or TOOLBAR_DEFAULT_WIDTH.button
            local w = (item.bounds and item.bounds.w) or item.width
                or math.max(min_w, #tostring(item.label or item.glyph or "") * APPROX_CHAR_WIDTH
                    + 2 * Theme.space.md)
            widths[i] = w
            fixed_total = fixed_total + w
        end
    end

    local inset = Theme.space.sm
    local gap = Theme.space.sm
    local gaps = math.max(0, #items - 1) * gap
    local slack = bounds.w - inset * 2 - fixed_total - gaps
    local spacer_width = (spacers > 0) and math.max(0, slack / spacers) or 0

    local item_height = math.min(Theme.metrics.control_height, bounds.h - Theme.space.xs * 2)
    local y = bounds.y + (bounds.h - item_height) * 0.5

    local cursor = bounds.x + inset
    local layout, activated = {}, nil

    for i, item in ipairs(items) do
        local width = (item.kind == "spacer") and spacer_width or widths[i]
        local item_bounds = { x = cursor, y = y, w = width, h = item_height }

        if item.kind ~= "spacer" then
            local fired
            if item.kind == "icon" then
                fired = Widgets.icon_button(window, item_bounds, item)
            elseif item.kind == "chip" then
                fired = Widgets.chip(window, item_bounds, item)
            else
                fired = Widgets.button(window, item_bounds, item)
            end
            if fired and item.id then activated = activated or item.id end
        end

        layout[i] = { id = item.id, kind = item.kind, bounds = item_bounds }
        cursor = cursor + width + gap
    end

    return activated, layout
end

-- ============================================================================
-- section_header
-- ============================================================================

---The title strip is NOT itself clickable — making it activate would turn every section heading
---into a hidden button. Only the optional trailing action is, and its bounds come back as the
---third return so a caller (and a test) can anchor a tooltip or a pointer on it without
---recomputing this function's layout.
---@param opts table { title, subtitle, action_label, disabled }
---@return boolean action_activated, string state, table|nil action_bounds
function Widgets.section_header(window, bounds, opts)
    opts = opts or {}

    local action_width = opts.action_label and (#opts.action_label * APPROX_CHAR_WIDTH + Theme.space.lg) or 0
    local action_bounds = opts.action_label and {
        x = bounds.x + bounds.w - action_width - Theme.space.sm,
        y = bounds.y + (bounds.h - Theme.metrics.control_height) * 0.5,
        w = action_width, h = Theme.metrics.control_height,
    } or nil

    -- The strip still probes hover (rule 1) even though it cannot be activated: a caller uses it
    -- to reveal row affordances, and a dead pointer over a header reads as a frozen panel.
    local mn, mx = corners(bounds)
    window:is_mouse_hovering_rect(mn, mx)

    window:render_text(Theme.font.heading, v2(bounds.x + Theme.space.sm, bounds.y),
        Theme.color.text_primary(Theme.interaction.resting.text),
        fit(opts.title, bounds.w - action_width - Theme.space.lg))

    if opts.subtitle then
        window:render_text(Theme.font.caption,
            v2(bounds.x + Theme.space.sm, bounds.y + Theme.line_height.heading),
            Theme.color.text_muted(Theme.interaction.resting.text),
            fit(opts.subtitle, bounds.w - action_width - Theme.space.lg))
    end

    window:render_rect_filled(
        v2(bounds.x, bounds.y + bounds.h - Theme.metrics.divider),
        v2(bounds.x + bounds.w, bounds.y + bounds.h),
        Theme.color.border(), Theme.radius.none)

    if not action_bounds then return false, "resting", nil end
    local activated, state = Widgets.button(window, action_bounds,
        { label = opts.action_label, variant = "ghost", disabled = opts.disabled })
    return activated, state, action_bounds
end

-- ============================================================================
-- empty_state
-- ============================================================================

---ADR 09b §5.5: "No campaign open - record one, or open an existing route" beats a blank pane,
---especially while the corpus is empty. The pane is NOT itself clickable — a giant invisible
---button is how a user discovers a destructive action by accident.
---@param opts table { title, message, action_label, disabled }
---@return boolean action_activated, string state, table|nil action_bounds
function Widgets.empty_state(window, bounds, opts)
    opts = opts or {}

    local mn, mx = corners(bounds)
    window:is_mouse_hovering_rect(mn, mx)

    local block_height = Theme.line_height.title + Theme.space.sm + Theme.line_height.body
    if opts.action_label then
        block_height = block_height + Theme.space.lg + Theme.metrics.control_height
    end
    local top = bounds.y + (bounds.h - block_height) * 0.5

    local title = tostring(opts.title or "")
    window:render_text(Theme.font.title,
        v2(bounds.x + (bounds.w - #title * APPROX_CHAR_WIDTH) * 0.5, top),
        Theme.color.text_primary(Theme.interaction.resting.text), title)

    local message = tostring(opts.message or "")
    window:render_text(Theme.font.body,
        v2(bounds.x + (bounds.w - #message * APPROX_CHAR_WIDTH) * 0.5,
           top + Theme.line_height.title + Theme.space.sm),
        Theme.color.text_muted(Theme.interaction.resting.text), message)

    if not opts.action_label then return false, "resting", nil end

    local action_width = math.max(#opts.action_label * APPROX_CHAR_WIDTH + Theme.space.xl, 120)
    local action_bounds = {
        x = bounds.x + (bounds.w - action_width) * 0.5,
        y = top + Theme.line_height.title + Theme.space.sm + Theme.line_height.body + Theme.space.lg,
        w = action_width, h = Theme.metrics.control_height,
    }
    local activated, state = Widgets.button(window, action_bounds,
        { label = opts.action_label, variant = "primary", disabled = opts.disabled })
    return activated, state, action_bounds
end

-- ============================================================================
-- toast
-- ============================================================================

---Sits at the OVERLAY elevation: a toast sharing the panel's surface reads as part of the panel
---and gets ignored. Its lifetime belongs to the caller — `progress` is remaining life, drawn as a
---bar, so the widget stays stateless and the timer stays in a model that can be tested.
---@param opts table { message, tone, progress, disabled }
---@return boolean dismissed, string state
function Widgets.toast(window, bounds, opts)
    opts = opts or {}
    local clicked, state = probe(window, bounds, opts)
    local token = tone_token(opts.tone, "border_strong")

    draw_surface(window, bounds, state, {
        fill_token = "surface_overlay",
        fill_alpha = 255,
        border_token = token,
        rounding = Theme.radius.md,
    })

    window:render_text(Theme.font.body, v2(bounds.x + Theme.space.md, centred_y(bounds, "body")),
        Theme.color[opts.tone and token or "text_primary"](Theme.interaction[state].text),
        fit(opts.message, bounds.w - Theme.space.xl))

    if opts.progress then
        local width = math.max(0, math.min(1, opts.progress)) * bounds.w
        window:render_rect_filled(
            v2(bounds.x, bounds.y + bounds.h - Theme.metrics.selection_marker),
            v2(bounds.x + width, bounds.y + bounds.h),
            Theme.color[token](), Theme.radius.none)
    end

    return clicked, state
end

-- ============================================================================
-- badge
-- ============================================================================

---A count or a status pill. NOT clickable: it never probes for a click, so it cannot swallow one
---from the row it sits on.
---
---It returns `false` first like every other widget rather than returning its hover flag, because
---the library's first return means one thing everywhere — "was this activated" — and a caller
---looping over mixed widgets must not have to remember which one is the exception. Hover is still
---available: it is `state == "hover"`.
---@param opts table { label, tone, disabled }
---@return boolean activated, string state
function Widgets.badge(window, bounds, opts)
    opts = opts or {}
    local mn, mx = corners(bounds)
    local hovered = window:is_mouse_hovering_rect(mn, mx) and true or false
    local state = Theme.resolve_state({ disabled = opts.disabled, hovered = hovered })
    local token = tone_token(opts.tone, "accent")

    window:render_rect_filled(mn, mx, Theme.color[token](Theme.interaction[state].fill),
        Theme.radius.pill)

    local label = fit(opts.label, bounds.w - Theme.space.sm * 2)
    local x = bounds.x + (bounds.w - #label * APPROX_CHAR_WIDTH) * 0.5
    window:render_text(Theme.font.caption, v2(x, centred_y(bounds, "caption")),
        Theme.color.surface(Theme.interaction[state].text), label)

    return false, state
end

-- ============================================================================
-- split_pane
-- ============================================================================

---Geometry plus a draggable divider. The RATIO belongs to the caller: persisting it is a ghost
---slider's job (ADR 09b §2.3), and a widget that owned it would lose it on every reload.
---@param opts table { ratio, axis, min_first, min_second }
---@return table layout { first, second, divider, divider_state, dragging }
function Widgets.split_pane(window, bounds, opts)
    opts = opts or {}
    local axis = opts.axis == "y" and "y" or "x"
    local handle = Theme.metrics.split_handle
    local total = (axis == "x") and bounds.w or bounds.h

    local min_first = opts.min_first or Theme.metrics.hit_min
    local min_second = opts.min_second or Theme.metrics.hit_min
    local first_size = (opts.ratio or 0.5) * total
    first_size = math.max(min_first, math.min(first_size, total - min_second - handle))

    local first, second, divider
    if axis == "x" then
        first = { x = bounds.x, y = bounds.y, w = first_size, h = bounds.h }
        divider = { x = bounds.x + first_size, y = bounds.y, w = handle, h = bounds.h }
        second = { x = divider.x + handle, y = bounds.y, w = bounds.w - first_size - handle, h = bounds.h }
    else
        first = { x = bounds.x, y = bounds.y, w = bounds.w, h = first_size }
        divider = { x = bounds.x, y = bounds.y + first_size, w = bounds.w, h = handle }
        second = { x = bounds.x, y = divider.y + handle, w = bounds.w, h = bounds.h - first_size - handle }
    end

    local dmn, dmx = corners(divider)
    local hovered = window:is_mouse_hovering_rect(dmn, dmx) and true or false
    local dragging = hovered and window:is_rect_clicked(dmn, dmx) and true or false
    local state = Theme.resolve_state({ active = dragging, hovered = hovered })

    -- A hairline at rest; the full handle only once the pointer is on it. A permanently visible
    -- 8px gutter between two panes is the single loudest thing on a dense editor screen.
    local line = (axis == "x")
        and { x = divider.x + handle * 0.5 - Theme.metrics.divider * 0.5, y = divider.y,
              w = Theme.metrics.divider, h = divider.h }
        or  { x = divider.x, y = divider.y + handle * 0.5 - Theme.metrics.divider * 0.5,
              w = divider.w, h = Theme.metrics.divider }
    local lmn, lmx = corners(line)
    window:render_rect_filled(lmn, lmx,
        Theme.color[hovered and "accent" or "border"](Theme.interaction[state].border),
        Theme.radius.none)

    return {
        first = first, second = second, divider = divider,
        divider_state = state, dragging = dragging,
    }
end

-- ============================================================================
-- Stock element wrappers
-- ============================================================================
-- ADR 09b §3.1: we do not re-implement checkbox, slider, combobox or text_input. What these add
-- is the themed frame around them and a disabled mode the stock elements do not have.
--
-- The disabled path never renders the real element — there is no way to grey one out, so a
-- "disabled" control that still rendered would still be operable. It draws an inert label
-- instead: unavailable, but not invisible.

local function stock_wrapper(render_element)
    return function(window, bounds, opts)
        opts = opts or {}
        local _, state, hovered = probe(window, bounds, opts)

        draw_surface(window, bounds, state, {
            fill_token = "surface_raised",
            border_token = hovered and "border_strong" or "border",
            rounding = Theme.radius.sm,
        })

        if opts.disabled or not opts.element then
            window:render_text(Theme.font.body,
                v2(bounds.x + Theme.space.md, centred_y(bounds, "body")),
                Theme.color.text_secondary(Theme.interaction.disabled.text),
                fit(opts.label, bounds.w - Theme.space.xl))
            return state
        end

        -- Stock elements draw at the window's dynamic cursor, not at a rect, so the offset is
        -- what keeps the themed frame and the control in the same place.
        window:add_menu_element_pos_offset(v2(bounds.x, bounds.y))
        render_element(opts)
        return state
    end
end

Widgets.checkbox = stock_wrapper(function(opts)
    opts.element:render(opts.label or "", opts.tooltip)
end)

Widgets.slider = stock_wrapper(function(opts)
    opts.element:render(opts.label or "", opts.tooltip)
end)

Widgets.combobox = stock_wrapper(function(opts)
    opts.element:render(opts.label or "", opts.options or {}, opts.tooltip)
end)

-- ============================================================================
-- text_input — the one control with no stock element behind it
-- ============================================================================
--
-- `stock_wrapper` cannot be reused here. ADR 09b §1 lists `text_input` among the stock elements,
-- but `docs/SylvannasAPI/dev/api/ui-custom.md` has no such constructor and `element_value` above
-- probes for an accessor that is never found -- which is why the Explorer's search box has been a
-- rectangle nobody could type into. This widget reads the keyboard itself.
--
-- IT STILL HOLDS NOTHING. `opts.model` is a `ui/text_input_state` owned by the caller's panel
-- state, exactly like every other widget's selection and scroll position. All of the decisions live
-- there; this function draws the projection and forwards keys.
--
-- WHAT IS UNDOCUMENTED HERE, AND WHAT HAPPENS WITHOUT IT
-- -----------------------------------------------------
-- `window:block_input_capture()` keeps the keys out of the game while the field has focus. It is
-- NOT in `ui-custom.md`; the only evidence it exists is `SentinelNavClient/lib/AstroUI.lua:2397`,
-- a plugin that works in the injector. It is therefore called through a type check: where the
-- method is absent the field still types, and the keystrokes also reach the game. That is the
-- focus-gated fallback the design names, and it is the reason this widget must be confirmed live
-- (tasks.md 3.2) before the undocumented half is trusted.

-- `window:is_mouse_button_clicked(0|1)` is as undocumented as `block_input_capture` below; the
-- only in-workspace evidence either exists is `SentinelNavClient/lib/AstroUI.lua:472-478` (some
-- backends number buttons from 0, some from 1, so both are asked). Guarded identically: where the
-- method is absent, focus stays sticky — the pre-fix behaviour — rather than the frame raising.
local function mouse_clicked_anywhere(window)
    if type(window.is_mouse_button_clicked) ~= "function" then return false end
    local ok, hit = pcall(window.is_mouse_button_clicked, window, 0)
    if ok and hit then return true end
    local ok2, hit2 = pcall(window.is_mouse_button_clicked, window, 1)
    return (ok2 and hit2) and true or false
end

---@param opts table { model, placeholder, label, disabled, events, input }
---@return table|nil result `{ kind = "submit"|"cancel", value }` from the model
---@return string state
function Widgets.text_input(window, bounds, opts)
    opts = opts or {}
    local model = opts.model
    if not model then
        -- No model is a caller bug, not a user-visible state. Draw the frame so the layout does not
        -- collapse, and refuse the keyboard rather than inventing a buffer to type into.
        local _, empty_state = probe(window, bounds, opts)
        draw_surface(window, bounds, empty_state, {
            fill_token = "surface_raised", border_token = "border", rounding = Theme.radius.md,
        })
        return nil, empty_state
    end

    local view = model:view()
    local clicked, state, hovered = probe(window, bounds, { disabled = opts.disabled, focused = view.focused })

    draw_surface(window, bounds, state, {
        fill_token = "surface_raised",
        border_token = view.focused and "accent" or (hovered and "border_strong" or "border"),
        rounding = Theme.radius.md,
    })

    local shown = view.placeholder_shown and tostring(opts.placeholder or "") or view.text
    local token = view.placeholder_shown and "text_muted" or "text_primary"
    window:render_text(Theme.font.body,
        v2(bounds.x + Theme.space.md, centred_y(bounds, "body")),
        Theme.color[token](Theme.interaction[state].text),
        fit(shown, bounds.w - Theme.space.xl))

    if view.focused and view.caret then
        -- A solid caret rather than a blinking one: blink needs a clock read on the render path,
        -- and a caret that is invisible half the time is worse at saying "this field has focus"
        -- than the accent border already above it.
        local caret_x = bounds.x + Theme.space.md + view.caret * APPROX_CHAR_WIDTH
        window:render_rect_filled(
            v2(caret_x, bounds.y + Theme.space.xs),
            v2(caret_x + 1, bounds.y + bounds.h - Theme.space.xs),
            Theme.color.text_primary(Theme.interaction[state].text), Theme.radius.none)
    end

    if opts.disabled then return nil, state end

    if clicked then
        model:focus()
        -- Disable game movement while typing in a custom text field.
        -- Uses documented API: core.input.disable_movement(is_lock)
        if type(core) == "table" and type(core.input) == "table"
           and type(core.input.disable_movement) == "function" then
            pcall(core.input.disable_movement, true)
        end
        -- Block input capture so keystrokes don't reach the game.
        -- This is the Sylvannas method for preventing WASD/keyboard passthrough
        -- when a custom text field has focus (see AstroUI.lua:2397).
        if type(window) == "table" and type(window.block_input_capture) == "function" then
            pcall(window.block_input_capture, window)
        end
    elseif model.focused and mouse_clicked_anywhere(window) then
        -- Click-outside blurs (AstroUI.lua:2460-2472). Without it focus was sticky: the guarded
        -- `block_input_capture` below then fired on every frame forever, and WASD stayed dead
        -- until Enter or Escape. `blur` also restores the committed value, so the field never
        -- shows a half-typed string the panel is not acting on.
        model:blur()
        -- Re-enable game movement when focus leaves the text field.
        if type(core) == "table" and type(core.input) == "table"
           and type(core.input.disable_movement) == "function" then
            pcall(core.input.disable_movement, false)
        end
    end
    if not model.focused then return nil, state end

    -- Block input capture so keystrokes don't reach the game.
    -- This is called every frame while focused (see AstroUI.lua:2402) to maintain the block.
    if type(window) == "table" and type(window.block_input_capture) == "function" then
        pcall(window.block_input_capture, window)
    end

    -- `opts.events` is the offline injection point and `opts.input` the live one; both land in the
    -- SAME `apply_keys`, so a test that types "wolf" runs the code the injector runs.
    local events = opts.events
    if events == nil then
        events = TextInputState.collect(opts.input or (type(core) == "table" and core.input) or nil)
    end
    local result = model:apply_keys(events)
    return result, state
end

return Widgets
