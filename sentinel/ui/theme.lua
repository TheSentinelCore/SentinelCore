-- sentinel/ui/theme.lua
-- The single source of visual truth for the in-game IDE (ADR 09b §3).
--
-- Nothing downstream of this file may write a colour literal or a pixel offset. That is not
-- tidiness: seven panels are specified in ADR 09b §6 and they are built by different hands at
-- different times, so the only thing that can make them look like one product is a vocabulary
-- small enough that there is nothing to disagree about. `tests/ui/test_theme.lua` holds the
-- section and token lists to an EXACT match for the same reason — a token added for one panel is
-- the first step back to seven bespoke panels.
--
-- WHY THE PALETTE IS SHAPED THE WAY IT IS
-- --------------------------------------
-- This UI renders over arbitrary game scenery: a snowfield at noon and a cave in Deadmines are
-- both legitimate backdrops. Two consequences drive every number below.
--
--  1. SURFACES ARE NEAR-OPAQUE (alpha >= `scenery_alpha_floor`). Contrast maths over a
--     translucent surface is meaningless, because most of the pixel comes from the zone. The
--     floor caps the scenery's share at ~4% so the palette's own contrast is the contrast the
--     user gets.
--  2. TEXT PAIRINGS CLEAR WCAG AA *COMPOSITED*, not in isolation. `test_theme.lua` composites
--     each surface over pure white and pure black, composites the text over that at its resting
--     alpha, and evaluates the ratio. White and black are the extremes any zone can present, so
--     clearing both clears everything between them.
--
-- The neutral ramp is a single slightly-cool hue family rather than ad-hoc greys. Ad-hoc greys
-- are how an immediate-mode UI ends up with four backgrounds that are almost the same and none
-- of which mean anything.

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then return mod end
    return fallback
end

-- Offline (and in every test in this repo) `common/color` does not exist. The shim keeps the same
-- shape so `theme.lua` is loadable and inspectable without the injector — see
-- `tests/ui/test_offline_loadable.lua`, which proves the guard is still there.
local Color = require_or("common/color", {
    new = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end,
})
local Enums = require_or("common/enums", nil)

local Theme = {}

-- ============================================================================
-- Palette
-- ============================================================================
-- Stored as raw `{r, g, b, a}` quads rather than colour objects so the values stay arithmetic:
-- the contrast suite needs numbers, and a `color` userdata in the injector cannot be read back.

Theme.rgba = {
    -- Neutral ramp. Three surfaces, two borders, three text weights — one step per job, no more.
    surface         = {  20,  22,  28, 244 },
    surface_raised  = {  30,  33,  42, 248 },
    surface_overlay = {  44,  48,  60, 252 },

    border          = {  56,  62,  78, 255 },
    border_strong   = {  88,  96, 118, 255 },

    text_primary    = { 236, 239, 245, 255 },
    text_secondary  = { 190, 196, 212, 255 },
    text_muted      = { 166, 173, 191, 255 },

    -- Accent. `accent` is for marks and copy; `accent_soft` is the tinted SURFACE behind a
    -- selected row. They are separate tokens because a selected row filled with full accent is
    -- unreadable, and every panel would otherwise invent its own dilution of it.
    accent          = { 110, 170, 255, 255 },
    accent_soft     = {  38,  62, 104, 255 },

    -- Semantic states. Chosen so each clears AA over every surface over both scenery extremes,
    -- and so they stay distinguishable from one another for a red-green colour-blind reader by
    -- luminance as well as hue.
    success         = {  74, 222, 128, 255 },
    warning         = { 251, 191,  36, 255 },
    danger          = { 250, 128, 128, 255 },
    info            = {  96, 165, 250, 255 },
}

Theme.token_names = {
    "surface", "surface_raised", "surface_overlay",
    "border", "border_strong",
    "text_primary", "text_secondary", "text_muted",
    "accent", "accent_soft",
    "success", "warning", "danger", "info",
}

--- The opacity below which a surface stops being a surface and starts being a tint on the game.
--- Named rather than inlined because the contrast suite has to assert against the same number the
--- palette was built from, or the two can drift apart without either looking wrong.
Theme.scenery_alpha_floor = 240

---Build a colour from a raw quad at an optional alpha.
function Theme.with_alpha(quad, alpha)
    return Color.new(quad[1], quad[2], quad[3], alpha or quad[4])
end

-- `Theme.color.<token>(alpha)` — the only way a panel is allowed to obtain a colour.
Theme.color = {}
for _, name in ipairs(Theme.token_names) do
    local quad = Theme.rgba[name]
    Theme.color[name] = function(alpha) return Theme.with_alpha(quad, alpha) end
end

-- ============================================================================
-- Elevation
-- ============================================================================
-- We cannot draw a drop shadow, so depth is carried by a luminance step in the fill PLUS a
-- change of border. The step is deliberately small (~1.12:1) — a popup that is dramatically
-- lighter than its parent reads as a different application, not as a layer above it — which is
-- why the overlay also takes `border_strong`. Neither signal is sufficient alone.

Theme.elevation = {
    base = {
        fill_token = "surface", border_token = "border",
        fill = Theme.color.surface, border = Theme.color.border,
    },
    raised = {
        fill_token = "surface_raised", border_token = "border",
        fill = Theme.color.surface_raised, border = Theme.color.border,
    },
    overlay = {
        fill_token = "surface_overlay", border_token = "border_strong",
        fill = Theme.color.surface_overlay, border = Theme.color.border_strong,
    },
}

-- ============================================================================
-- Spacing
-- ============================================================================
-- One 4px ramp, and nothing else is legal. ADR 09b §3 names arbitrary pixel offsets as the reason
-- immediate-mode UIs drift into visual noise: with no ramp, every panel picks 7 or 9 or 13 and the
-- eye reads the result as misalignment without being able to say why.

Theme.space = {
    none = 0, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32,
}
Theme.space_order = { "none", "xs", "sm", "md", "lg", "xl", "xxl" }

-- ============================================================================
-- Interaction states
-- ============================================================================
-- The alpha-shift idiom from `guides/custom-ui.md` (`alpha = 120` at rest, `255` on hover),
-- centralised. ADR 09b §3 asks for exactly this: every clickable thing in the IDE responds
-- identically, because they all read the same table.
--
-- `text` is a separate channel from `fill`/`border` because dimming resting COPY to signal "not
-- hovered" would leave the IDE at its least readable in the state it spends most of its time in.
-- Resting text therefore stays near full strength while resting chrome recedes.

Theme.interaction = {
    resting  = { fill = 120, border = 120, text = 235 },
    hover    = { fill = 190, border = 255, text = 255 },
    active   = { fill = 255, border = 255, text = 255 },
    focused  = { fill = 150, border = 255, text = 255 },
    -- Disabled has to lose the contrast fight on purpose, but a control nobody can see is a
    -- control nobody knows exists. These land around 2.4:1 composited — visibly unavailable,
    -- still legible.
    disabled = { fill = 40,  border = 55,  text = 90 },
}
Theme.interaction_order = { "resting", "hover", "active", "focused", "disabled" }

---Resolve interaction flags to exactly one state name.
---
---Precedence is `disabled > active > hover > focused > resting`. Disabled outranking everything
---is the load-bearing part: a greyed-out control that lights up under the pointer tells the user
---it is available, and they click it.
---@param flags table|nil { disabled, active, hovered, focused }
---@return string
function Theme.resolve_state(flags)
    if not flags then return "resting" end
    if flags.disabled then return "disabled" end
    if flags.active then return "active" end
    if flags.hovered then return "hover" end
    if flags.focused then return "focused" end
    return "resting"
end

-- ============================================================================
-- Type scale
-- ============================================================================
-- Semantic roles onto Sylvannas font ids. The numeric fallbacks are the ids documented in
-- `api/ui-custom.md` (FONT_SMALL = 0 ... FONT_ICONS_VERY_BIG = 6), so offline layout maths uses
-- the same values the injector will.

local FONT = (Enums and Enums.window_enums and Enums.window_enums.font_id) or {
    FONT_SMALL = 0, FONT_NORMAL = 1, FONT_SEMI_BIG = 2, FONT_BIG = 3,
    FONT_ICONS_SMALL = 4, FONT_ICONS_BIG = 5, FONT_ICONS_VERY_BIG = 6,
}

Theme.font = {
    title      = FONT.FONT_BIG,
    heading    = FONT.FONT_SEMI_BIG,
    body       = FONT.FONT_NORMAL,
    caption    = FONT.FONT_SMALL,
    icon       = FONT.FONT_ICONS_SMALL,
    icon_large = FONT.FONT_ICONS_BIG,
    icon_huge  = FONT.FONT_ICONS_VERY_BIG,
}

-- Vertical box per role. Layout needs a number it can add up before anything is measured, and
-- `get_text_size` is only available inside a render callback.
Theme.line_height = {
    title = 24, heading = 20, body = 16, caption = 13,
}

-- ============================================================================
-- Radius and metrics
-- ============================================================================

Theme.radius = {
    none = 0, sm = 3, md = 6, lg = 10,
    -- Larger than any widget we will draw, which is how ImGui-style rounding produces a pill.
    pill = 999,
}

Theme.metrics = {
    -- ADR 09b §3: the mouse driving this is also steering a character, and the window sits over
    -- moving scenery. 24px is the desktop floor; nothing clickable here starts below 30.
    hit_min          = 30,
    control_height   = 32,
    row_height       = 34,
    icon_button      = 32,
    toolbar_height   = 44,

    border_thickness = 1,
    focus_thickness  = 2,
    -- The accent bar on a selected list row. The tinted fill is deliberately low-contrast so a
    -- forty-row list stays calm; this is the part that survives being scanned at speed.
    selection_marker = 3,
    divider          = 1,
    split_handle     = 8,
}

return Theme
