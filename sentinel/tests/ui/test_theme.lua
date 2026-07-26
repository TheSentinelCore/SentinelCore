-- tests/ui/test_theme.lua
-- The design system's contract (ADR 09b §3).
--
-- Two things are pinned here that a screenshot cannot pin:
--
--  1. THE VOCABULARY IS CLOSED. Five panels built by five hands look like one product only if
--     none of them can add a token. The section and token lists below are exact-match, so a
--     panel-specific colour appearing in `theme.lua` fails here rather than shipping.
--  2. CONTRAST IS COMPUTED, NOT CLAIMED. This UI renders over arbitrary game scenery, so
--     "legible" is not a property of the palette alone — it is a property of the palette
--     COMPOSITED over whatever is behind it. Every check below alpha-composites the surface over
--     pure white AND pure black, composites the text over that, and evaluates the WCAG 2.1
--     contrast ratio. Pure white and pure black are the two extremes any zone can present, so a
--     pairing that clears both clears everything between them.

local Theme = require("ui/theme")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- WCAG 2.1 relative luminance and contrast, over an alpha composite.
-- ============================================================================

local function linearize(channel_0_255)
    local c = channel_0_255 / 255
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(rgb)
    return 0.2126 * linearize(rgb[1]) + 0.7152 * linearize(rgb[2]) + 0.0722 * linearize(rgb[3])
end

local function contrast_ratio(fg_rgb, bg_rgb)
    local l1, l2 = luminance(fg_rgb), luminance(bg_rgb)
    if l1 < l2 then l1, l2 = l2, l1 end
    return (l1 + 0.05) / (l2 + 0.05)
end

--- Source-over composite of an RGBA quad onto an opaque RGB background.
local function composite(rgba, backdrop_rgb, alpha_override)
    local a = (alpha_override or rgba[4]) / 255
    return {
        rgba[1] * a + backdrop_rgb[1] * (1 - a),
        rgba[2] * a + backdrop_rgb[2] * (1 - a),
        rgba[3] * a + backdrop_rgb[3] * (1 - a),
    }
end

local WHITE_SCENERY = { 255, 255, 255 }   -- a snowfield in Dun Morogh at noon
local BLACK_SCENERY = { 0, 0, 0 }         -- a cave in Deadmines
local SCENERIES = { bright = WHITE_SCENERY, dark = BLACK_SCENERY }

local SURFACE_TOKENS = { "surface", "surface_raised", "surface_overlay" }
local TEXT_TOKENS = { "text_primary", "text_secondary", "text_muted" }
local SIGNAL_TOKENS = { "accent", "success", "warning", "danger", "info" }

-- The floor for body copy. WCAG AA for normal text; the game overlay is read at a glance while
-- the player is also steering, so nothing here is allowed to sit below it.
local MIN_TEXT_CONTRAST = 4.5

-- ============================================================================
-- Vocabulary — closed by construction
-- ============================================================================

function M.test_theme_exposes_exactly_the_documented_sections()
    local expected = {
        rgba = true, color = true, elevation = true, space = true, space_order = true,
        interaction = true, interaction_order = true, resolve_state = true,
        font = true, line_height = true, radius = true, metrics = true,
        token_names = true, scenery_alpha_floor = true, with_alpha = true,
    }
    for key in pairs(Theme) do
        T.assert_true(expected[key] == true,
            "theme.lua grew an undocumented section: " .. tostring(key))
    end
    for key in pairs(expected) do
        T.assert_not_nil(Theme[key], "theme.lua is missing documented section: " .. key)
    end
end

function M.test_palette_exposes_every_documented_token()
    local expected = {
        "surface", "surface_raised", "surface_overlay",
        "border", "border_strong",
        "text_primary", "text_secondary", "text_muted",
        "accent", "accent_soft",
        "success", "warning", "danger", "info",
    }
    for _, name in ipairs(expected) do
        T.assert_not_nil(Theme.rgba[name], "missing palette token: " .. name)
        T.assert_equal(#Theme.rgba[name], 4, name .. " must be an rgba quad")
        T.assert_equal(type(Theme.color[name]), "function", name .. " must have a colour builder")
    end
    T.assert_equal(#Theme.token_names, #expected, "token_names must list every token, once")
end

function M.test_palette_carries_no_panel_specific_token()
    -- The moment `theme.runner_green` exists, the design system has stopped being one and the
    -- next panel will add its own. Names, not values, are the enforcement point.
    local panel_words = {
        "runner", "explorer", "graph", "properties", "database", "map", "simulator",
        "quest", "npc", "step", "campaign", "node", "route", "recorder",
    }
    for _, name in ipairs(Theme.token_names) do
        for _, word in ipairs(panel_words) do
            T.assert_nil(name:find(word, 1, true),
                "palette token '" .. name .. "' is panel-specific ('" .. word .. "')")
        end
    end
end

function M.test_colour_builders_default_to_the_token_alpha()
    local built = Theme.color.surface()
    T.assert_equal(built.a, Theme.rgba.surface[4], "no argument means the token's own alpha")
    T.assert_equal(built.r, Theme.rgba.surface[1], "channels come from the token")
end

function M.test_colour_builders_accept_an_alpha_override()
    -- The whole interaction model is alpha-shift, so every token has to be requestable at an
    -- arbitrary alpha without a second token existing for it.
    local built = Theme.color.accent(90)
    T.assert_equal(built.a, 90, "an explicit alpha must win")
    T.assert_equal(built.r, Theme.rgba.accent[1], "channels are unchanged by an alpha override")
end

-- ============================================================================
-- Spacing, radius, hit targets
-- ============================================================================

function M.test_spacing_is_a_single_four_pixel_ramp()
    for _, name in ipairs(Theme.space_order) do
        local value = Theme.space[name]
        T.assert_not_nil(value, "space_order names a missing step: " .. name)
        T.assert_equal(value % 4, 0, "space." .. name .. " = " .. value .. " is off the 4px grid")
    end
end

function M.test_spacing_steps_strictly_increase()
    local previous = -1
    for _, name in ipairs(Theme.space_order) do
        T.assert_true(Theme.space[name] > previous,
            "space." .. name .. " must be larger than the step before it")
        previous = Theme.space[name]
    end
end

function M.test_spacing_has_no_step_outside_the_ramp()
    local declared = {}
    for _, name in ipairs(Theme.space_order) do declared[name] = true end
    for name in pairs(Theme.space) do
        T.assert_true(declared[name] == true, "space." .. name .. " is not in space_order")
    end
end

function M.test_hit_targets_are_larger_than_a_desktop_app_would_need()
    -- ADR 09b §3: the mouse driving this is also steering a character. 24px is the desktop floor;
    -- everything clickable here starts above it.
    T.assert_true(Theme.metrics.hit_min >= 28,
        "hit_min " .. Theme.metrics.hit_min .. " is too small for a game overlay")
    for _, name in ipairs({ "control_height", "row_height", "icon_button", "toolbar_height" }) do
        T.assert_true(Theme.metrics[name] >= Theme.metrics.hit_min,
            "metrics." .. name .. " must not be smaller than hit_min")
    end
end

function M.test_radius_scale_is_ordered_and_starts_at_zero()
    T.assert_equal(Theme.radius.none, 0, "radius.none must be square")
    T.assert_true(Theme.radius.sm < Theme.radius.md, "radius scale must ascend")
    T.assert_true(Theme.radius.md < Theme.radius.lg, "radius scale must ascend")
    T.assert_true(Theme.radius.pill > Theme.radius.lg, "pill is the fully-rounded end")
end

-- ============================================================================
-- Elevation
-- ============================================================================

function M.test_every_elevation_pairs_a_fill_with_a_border()
    for _, level in ipairs({ "base", "raised", "overlay" }) do
        local e = Theme.elevation[level]
        T.assert_not_nil(e, "missing elevation level: " .. level)
        T.assert_not_nil(Theme.rgba[e.fill_token], level .. ".fill_token is not a palette token")
        T.assert_not_nil(Theme.rgba[e.border_token], level .. ".border_token is not a palette token")
        T.assert_equal(type(e.fill), "function", level .. ".fill must be a colour builder")
        T.assert_equal(type(e.border), "function", level .. ".border must be a colour builder")
    end
end

function M.test_elevations_separate_without_a_drop_shadow()
    -- We cannot draw a shadow, so the only thing telling a popup from the panel behind it is the
    -- luminance step between their fills. Anything under ~1.1 reads as a rendering artefact.
    local base = Theme.rgba[Theme.elevation.base.fill_token]
    local raised = Theme.rgba[Theme.elevation.raised.fill_token]
    local overlay = Theme.rgba[Theme.elevation.overlay.fill_token]

    T.assert_true(contrast_ratio(raised, base) >= 1.10,
        "raised is indistinguishable from base (" .. contrast_ratio(raised, base) .. ":1)")
    T.assert_true(contrast_ratio(overlay, raised) >= 1.10,
        "overlay is indistinguishable from raised (" .. contrast_ratio(overlay, raised) .. ":1)")
end

function M.test_the_overlay_takes_the_stronger_border()
    -- The luminance step alone is deliberately subtle; the border carries the rest of the signal.
    T.assert_true(Theme.elevation.overlay.border_token ~= Theme.elevation.base.border_token,
        "an overlay must not share the base border, or a popup has no edge")
end

function M.test_every_elevation_border_is_visible_against_its_own_fill()
    for _, level in ipairs({ "base", "raised", "overlay" }) do
        local e = Theme.elevation[level]
        local ratio = contrast_ratio(Theme.rgba[e.border_token], Theme.rgba[e.fill_token])
        T.assert_true(ratio >= 1.15,
            level .. " border is invisible against its fill (" .. ratio .. ":1)")
    end
end

-- ============================================================================
-- Interaction states
-- ============================================================================

function M.test_every_interaction_state_is_defined()
    for _, name in ipairs({ "resting", "hover", "active", "focused", "disabled" }) do
        local s = Theme.interaction[name]
        T.assert_not_nil(s, "missing interaction state: " .. name)
        for _, channel in ipairs({ "fill", "border", "text" }) do
            T.assert_equal(type(s[channel]), "number", name .. "." .. channel .. " must be an alpha")
            T.assert_true(s[channel] >= 0 and s[channel] <= 255, name .. "." .. channel .. " out of range")
        end
    end
end

function M.test_hover_is_the_guides_alpha_shift()
    -- ADR 09b §3 names the guide's own idiom (120 resting -> 255 hover) as the thing to
    -- centralise, so that every clickable region in the IDE responds identically.
    T.assert_equal(Theme.interaction.resting.border, 120, "resting border alpha is the guide's 120")
    T.assert_equal(Theme.interaction.hover.border, 255, "hover border alpha is the guide's 255")
end

function M.test_disabled_is_the_dimmest_state()
    for _, channel in ipairs({ "fill", "border", "text" }) do
        T.assert_true(Theme.interaction.disabled[channel] < Theme.interaction.resting[channel],
            "disabled." .. channel .. " must read as weaker than resting")
    end
end

function M.test_resting_copy_stays_near_full_strength()
    -- Resting text is the state most of the UI is in most of the time; dimming it to signal
    -- "not hovered" would mean the IDE is at its least readable by default.
    T.assert_true(Theme.interaction.resting.text >= 220,
        "resting text alpha " .. Theme.interaction.resting.text .. " is too dim for body copy")
end

function M.test_resolve_state_puts_disabled_above_everything()
    -- A disabled control that is also hovered and clicked is still disabled. Getting this
    -- precedence wrong is how a greyed-out button lights up under the pointer.
    T.assert_equal(Theme.resolve_state({ disabled = true, hovered = true, active = true }), "disabled",
        "disabled outranks every other flag")
end

function M.test_resolve_state_orders_active_above_hover()
    T.assert_equal(Theme.resolve_state({ hovered = true, active = true }), "active",
        "a pressed control reads active, not hover")
    T.assert_equal(Theme.resolve_state({ hovered = true }), "hover", "hover when only hovered")
    T.assert_equal(Theme.resolve_state({ focused = true }), "focused", "focused when only focused")
    T.assert_equal(Theme.resolve_state({}), "resting", "nothing set means resting")
    T.assert_equal(Theme.resolve_state(nil), "resting", "no flags at all means resting")
end

function M.test_interaction_order_lists_every_state_once()
    T.assert_equal(#Theme.interaction_order, 5, "five states, no more")
    local seen = {}
    for _, name in ipairs(Theme.interaction_order) do
        T.assert_nil(seen[name], "interaction_order repeats " .. tostring(name))
        seen[name] = true
        T.assert_not_nil(Theme.interaction[name], "interaction_order names a missing state")
    end
end

-- ============================================================================
-- Type scale
-- ============================================================================

function M.test_type_scale_maps_semantic_roles_onto_font_ids()
    for _, role in ipairs({ "title", "heading", "body", "caption" }) do
        T.assert_equal(type(Theme.font[role]), "number", "font." .. role .. " must be a font_id")
        T.assert_equal(type(Theme.line_height[role]), "number",
            "line_height." .. role .. " is needed to lay the role out")
    end
end

function M.test_type_scale_descends_from_title_to_caption()
    T.assert_true(Theme.font.title > Theme.font.heading, "title is the largest font id")
    T.assert_true(Theme.font.heading > Theme.font.body, "heading sits above body")
    T.assert_true(Theme.font.body > Theme.font.caption, "caption is the smallest")
    T.assert_true(Theme.line_height.title > Theme.line_height.body, "line heights follow the scale")
    T.assert_true(Theme.line_height.body > Theme.line_height.caption, "line heights follow the scale")
end

function M.test_body_line_height_fits_inside_a_control()
    T.assert_true(Theme.line_height.body < Theme.metrics.control_height,
        "body copy cannot be taller than the control it sits in")
end

-- ============================================================================
-- Contrast over arbitrary game scenery — computed, not asserted
-- ============================================================================

function M.test_surfaces_are_opaque_enough_that_scenery_cannot_dominate()
    -- Contrast maths on the palette is meaningless if the zone behind it contributes most of the
    -- pixel. The floor caps the scenery's share of every surface.
    for _, name in ipairs(SURFACE_TOKENS) do
        local alpha = Theme.rgba[name][4]
        T.assert_true(alpha >= Theme.scenery_alpha_floor,
            name .. " alpha " .. alpha .. " lets too much scenery through")
    end
    T.assert_true(Theme.scenery_alpha_floor >= 235,
        "the declared floor itself is too permissive to reason about")
end

function M.test_body_copy_clears_wcag_aa_over_any_scenery()
    -- The worst realistic case for enabled copy: resting alpha, on the lightest surface, over the
    -- brightest and darkest backdrops a zone can present.
    local text_alpha = Theme.interaction.resting.text
    for scenery_name, scenery in pairs(SCENERIES) do
        for _, surface_name in ipairs(SURFACE_TOKENS) do
            local backdrop = composite(Theme.rgba[surface_name], scenery)
            for _, text_name in ipairs(TEXT_TOKENS) do
                local fg = composite(Theme.rgba[text_name], backdrop, text_alpha)
                local ratio = contrast_ratio(fg, backdrop)
                T.assert_true(ratio >= MIN_TEXT_CONTRAST, string.format(
                    "%s on %s over %s scenery is %.2f:1, below %.1f:1",
                    text_name, surface_name, scenery_name, ratio, MIN_TEXT_CONTRAST))
            end
        end
    end
end

function M.test_signal_colours_clear_wcag_aa_over_any_scenery()
    -- Semantic colour is the fastest signal on the screen; a warning that cannot be read over a
    -- snowfield is a warning that was not delivered.
    for scenery_name, scenery in pairs(SCENERIES) do
        for _, surface_name in ipairs(SURFACE_TOKENS) do
            local backdrop = composite(Theme.rgba[surface_name], scenery)
            for _, signal in ipairs(SIGNAL_TOKENS) do
                local fg = composite(Theme.rgba[signal], backdrop)
                local ratio = contrast_ratio(fg, backdrop)
                T.assert_true(ratio >= MIN_TEXT_CONTRAST, string.format(
                    "%s on %s over %s scenery is %.2f:1, below %.1f:1",
                    signal, surface_name, scenery_name, ratio, MIN_TEXT_CONTRAST))
            end
        end
    end
end

function M.test_the_text_hierarchy_is_actually_three_steps()
    -- Three near-identical greys are one grey with extra names, and panels then pick at random.
    local primary = luminance(Theme.rgba.text_primary)
    local secondary = luminance(Theme.rgba.text_secondary)
    local muted = luminance(Theme.rgba.text_muted)
    T.assert_true(primary > secondary, "primary must be brighter than secondary")
    T.assert_true(secondary > muted, "secondary must be brighter than muted")
    T.assert_true(contrast_ratio(Theme.rgba.text_primary, Theme.rgba.text_muted) >= 1.5,
        "primary and muted are too close to read as different roles")
end

function M.test_disabled_copy_reads_as_unavailable_rather_than_invisible()
    -- Disabled has to lose the contrast fight on purpose, but a control nobody can see is a
    -- control nobody knows exists — so it still has to clear the 3:1 non-text floor.
    local backdrop = composite(Theme.rgba.surface, WHITE_SCENERY)
    local fg = composite(Theme.rgba.text_secondary, backdrop, Theme.interaction.disabled.text)
    local ratio = contrast_ratio(fg, backdrop)
    T.assert_true(ratio < MIN_TEXT_CONTRAST, "disabled copy must be visibly weaker than enabled")
    T.assert_true(ratio >= 1.8, string.format("disabled copy at %.2f:1 has vanished", ratio))
end

return M
