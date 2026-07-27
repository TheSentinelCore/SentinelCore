-- sentinel/ui/panel_layout.lua
-- Shared layout primitives and accessibility vocabulary for IDE panels (ADR 09b §3).
--
-- The Runner panel established the design language: a single spacing ramp, a single colour
-- vocabulary, control sizes that respect the input floor, and non-colour carriers for every state.
-- This module exports the constants and helpers that let other panels speak the same language
-- without copying the Runner source.

local Theme = require("ui/theme")

local PanelLayout = {}

-- ============================================================================
-- Derived constants (same rhythm Runner uses)
-- ============================================================================

PanelLayout.PAD = Theme.space.lg
PanelLayout.CONTROL_H = Theme.metrics.control_height
PanelLayout.ROW_H = Theme.metrics.row_height
PanelLayout.TOOLBAR_H = Theme.metrics.toolbar_height
PanelLayout.BUTTON_MIN_W = Theme.metrics.control_height * 3
PanelLayout.SECTION_H = Theme.line_height.heading + Theme.space.xs
PanelLayout.CHAR_W = 7

-- ============================================================================
-- Text fitting
-- ============================================================================

---Truncate `text` to fit `width` in fixed-width characters.
function PanelLayout.fit(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / PanelLayout.CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

-- ============================================================================
-- Accessibility glyphs — non-colour carriers for severity and state.
-- ============================================================================

PanelLayout.GLYPH = {
    -- Severities
    error   = "X",
    warn    = "!",
    warning = "!",
    info    = "-",
    success = "+",
    danger  = "X",

    -- Generic states
    empty   = "--",
    loading = "..",
    blocked = "!!",
    waiting = "..",

    -- Objective / entity kinds
    kill       = "K",
    collect    = "C",
    interact   = "I",
    creature   = "C",
    patrol     = "P",
    loot       = "L",
    vendor     = "V",
    herb       = "H",
    mining     = "M",
    treasure   = "T",
    flight     = "F",
    gameobject = "O",
}

---Return the glyph for a key, defaulting to a safe fallback.
function PanelLayout.glyph(key)
    return PanelLayout.GLYPH[key] or "?"
end

-- ============================================================================
-- Vertical centring inside a bounds box for a font role.
-- ============================================================================

function PanelLayout.centred_y(bounds, role)
    return bounds.y + (bounds.h - Theme.line_height[role]) * 0.5
end

-- ============================================================================
-- High-level plan helpers.
-- These emit the same item kinds the render-layer handler tables expect.
-- ============================================================================

---A filled toolbar strip with a top border, like Runner's transport bar.
function PanelLayout.toolbar_plan(items, bounds)
    local out = {
        { kind = "rect", bounds = bounds, token = "surface_raised", alpha = 255, rounding = Theme.radius.none },
        { kind = "rect", bounds = { x = bounds.x, y = bounds.y, w = bounds.w, h = Theme.metrics.divider }, token = "border", alpha = 255, rounding = Theme.radius.none },
    }
    for _, item in ipairs(items) do out[#out + 1] = item end
    return out
end

---An actionable empty state that always offers a next step.
function PanelLayout.empty_state_plan(opts)
    return {{
        kind = "empty_state",
        bounds = opts.bounds,
        id = opts.id,
        title = opts.title,
        message = opts.message,
        action_label = opts.action_label,
    }}
end

---A severity alert banner: filled surface, outline, marker, heading, optional body lines.
function PanelLayout.alert_banner_plan(opts)
    local items = {}
    local b = opts.bounds
    local token = opts.token or "warning"
    local body_h = (#opts.lines * Theme.line_height.caption)
    local height = Theme.space.md * 2 + Theme.line_height.heading + body_h

    -- Filled surface
    items[#items + 1] = { kind = "rect", bounds = b, token = "surface_overlay", alpha = 255, rounding = Theme.radius.md }
    -- Outline
    items[#items + 1] = { kind = "outline", bounds = b, token = token, alpha = Theme.interaction.active.border, rounding = Theme.radius.md, thickness = Theme.metrics.focus_thickness }
    -- Left marker
    items[#items + 1] = { kind = "rect", bounds = { x = b.x, y = b.y, w = Theme.metrics.selection_marker, h = b.h }, token = token, alpha = 255, rounding = Theme.radius.none }

    local text_x = b.x + Theme.metrics.selection_marker + Theme.space.md
    local title_glyph = (opts.glyph or PanelLayout.glyph(token) or "!")
    items[#items + 1] = {
        kind = "text", x = text_x, y = b.y + Theme.space.md,
        font = Theme.font.heading, token = token,
        alpha = Theme.interaction.resting.text,
        text = PanelLayout.fit(title_glyph .. "  " .. (opts.title or ""), b.w - Theme.metrics.selection_marker - Theme.space.md * 2),
    }

    local line_y = b.y + Theme.space.md + Theme.line_height.heading
    for _, line in ipairs(opts.lines or {}) do
        items[#items + 1] = {
            kind = "text", x = text_x, y = line_y,
            font = Theme.font.caption, token = "text_secondary",
            alpha = Theme.interaction.resting.text,
            text = PanelLayout.fit(line, b.w - Theme.metrics.selection_marker - Theme.space.md * 2),
        }
        line_y = line_y + Theme.line_height.caption
    end

    return items
end

return PanelLayout
