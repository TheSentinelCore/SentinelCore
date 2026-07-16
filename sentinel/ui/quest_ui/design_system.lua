--[[
    QuestUI Design System
    Modern, clean, questing-focused UI design system
    Based on Apple HIG / Material Design 3 principles adapted for in-game overlay
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")

---@class QuestDesignSystem
local Design = {}

-- ============================================================================
-- COLOR PALETTE - Modern, accessible, game-friendly
-- ============================================================================

Design.Colors = {
    -- Base neutrals (dark theme optimized for game overlay)
    neutral = {
        bg_primary      = color.new(18, 20, 24, 230),    -- Main window background
        bg_secondary    = color.new(24, 26, 32, 220),    -- Card/section background
        bg_tertiary     = color.new(30, 33, 40, 200),    -- Elevated surfaces
        bg_hover        = color.new(38, 42, 52, 220),    -- Hover states
        bg_active       = color.new(45, 50, 62, 240),    -- Active/pressed states
        bg_disabled     = color.new(30, 32, 38, 180),    -- Disabled states

        border_primary  = color.new(60, 65, 78, 200),    -- Main borders
        border_secondary = color.new(50, 54, 66, 160),   -- Subtle borders
        border_focus    = color.new(90, 140, 255, 255),  -- Focus rings

        text_primary    = color.new(235, 238, 245, 255), -- Primary text
        text_secondary  = color.new(170, 175, 185, 255), -- Secondary text
        text_muted      = color.new(110, 115, 125, 255), -- Disabled/muted text
        text_disabled   = color.new(80, 84, 90, 200),    -- Disabled text
        text_on_accent  = color.new(255, 255, 255, 255), -- Text on colored backgrounds

        -- Accent colors for interactive elements
        accent          = Design.Colors.semantic.quest.border,
        accent_bg       = Design.Colors.semantic.quest.bg,
        accent_hover    = Design.Colors.semantic.quest.bg_light,
    },

    -- Semantic colors - Quest-themed
    semantic = {
        -- Quest Blue - primary actions, active quests
        quest = {
            bg          = color.new(25, 45, 85, 200),
            bg_light    = color.new(35, 60, 110, 220),
            border      = color.new(70, 120, 200, 255),
            text        = color.new(180, 210, 255, 255),
            icon        = color.new(120, 180, 255, 255),
        },

        -- Success Green - completed quests, ready to turn in
        success = {
            bg          = color.new(20, 70, 40, 200),
            bg_light    = color.new(30, 90, 50, 220),
            border      = color.new(60, 160, 90, 255),
            text        = color.new(160, 240, 200, 255),
            icon        = color.new(100, 220, 140, 255),
        },

        -- Warning Amber - objectives in progress, low resources
        warning = {
            bg          = color.new(85, 65, 20, 200),
            bg_light    = color.new(105, 85, 30, 220),
            border      = color.new(190, 155, 50, 255),
            text        = color.new(255, 220, 140, 255),
            icon        = color.new(240, 200, 80, 255),
        },

        -- Danger Red - failed, dead, critical issues
        danger = {
            bg          = color.new(85, 25, 30, 200),
            bg_light    = color.new(110, 35, 40, 220),
            border      = color.new(200, 70, 80, 255),
            text        = color.new(255, 170, 180, 255),
            icon        = color.new(255, 100, 110, 255),
        },

        -- Neutral Gray - completed/turned in, disabled
        neutral = {
            bg          = color.new(40, 42, 48, 200),
            border      = color.new(70, 72, 80, 200),
            text        = color.new(140, 142, 150, 255),
            icon        = color.new(100, 102, 110, 255),
        },
    },

    -- Objective type colors
    objective = {
        kill        = { bg = color.new(85, 30, 30, 200), border = color.new(180, 70, 70, 255), icon = color.new(255, 120, 120, 255) },
        collect     = { bg = color.new(30, 70, 45, 200), border = color.new(70, 170, 100, 255), icon = color.new(120, 230, 150, 255) },
        talk        = { bg = color.new(30, 55, 85, 200), border = color.new(70, 130, 200, 255), icon = color.new(120, 180, 255, 255) },
        escort      = { bg = color.new(70, 50, 25, 200), border = color.new(180, 130, 60, 255), icon = color.new(255, 200, 100, 255) },
        use_item    = { bg = color.new(60, 35, 75, 200), border = color.new(150, 90, 190, 255), icon = color.new(220, 150, 255, 255) },
        area_trigger = { bg = color.new(25, 65, 75, 200), border = color.new(60, 160, 180, 255), icon = color.new(100, 220, 240, 255) },
    },

    -- Difficulty tiers
    difficulty = {
        trivial     = { text = color.new(120, 220, 140, 255), icon = color.new(100, 200, 120, 255) },
        easy        = { text = color.new(100, 180, 255, 255), icon = color.new(80, 160, 240, 255) },
        normal      = { text = color.new(255, 220, 100, 255), icon = color.new(240, 200, 80, 255) },
        hard        = { text = color.new(255, 160, 80, 255), icon = color.new(255, 140, 60, 255) },
        elite       = { text = color.new(255, 100, 100, 255), icon = color.new(255, 80, 80, 255) },
        dungeon     = { text = color.new(220, 100, 255, 255), icon = color.new(200, 80, 240, 255) },
    },
}

-- ============================================================================
-- TYPOGRAPHY - Clear hierarchy, readable at small sizes
-- ============================================================================

Design.Typography = {
    -- Font IDs (map to game's font system)
    font = {
        mono       = 0,  -- FONT_SMALL
        ui         = 0,  -- FONT_SMALL
        heading    = 1,  -- FONT_SEMI_BIG (if available)
    },

    -- Font sizes (in pixels, for render_text_custom_size)
    size = {
        display_large   = 28,  -- Page titles
        display_medium  = 22,  -- Section headers
        display_small   = 18,  -- Sub-section headers
        heading_large   = 24,  -- Large headings
        heading_medium  = 18,  -- Medium headings
        heading_small   = 16,  -- Small headings
        headline_large  = 16,  -- Card titles
        headline_medium = 14,  -- List item titles
        headline_small  = 13,  -- Small card titles
        body_large      = 13,  -- Primary body text
        body_medium     = 12,  -- Standard body text
        body_small      = 11,  -- Secondary text
        button          = 13,  -- Button text
        caption_medium  = 11,  -- Medium captions
        caption         = 10,  -- Labels, hints
        overline        = 9,   -- Category labels, tags
        metric_large    = 28,  -- Metric numbers
    },

    -- Font weights (simulated via color/opacity)
    weight = {
        regular = 255,
        medium  = 255,
        bold    = 255,
    },

    -- Line heights (multipliers)
    line_height = {
        tight   = 1.2,
        normal  = 1.5,
        relaxed = 1.75,
    },
}

-- ============================================================================
-- SPACING SYSTEM - 4px base unit
-- ============================================================================

Design.Spacing = {
    -- Base unit
    unit = 4,

    -- Named spacings
    none     = 0,
    xs       = 4,   -- 1u
    sm       = 8,   -- 2u
    md       = 12,  -- 3u
    lg       = 16,  -- 4u
    xl       = 20,  -- 5u
    xxl      = 24,  -- 6u
    xxxl     = 32,  -- 8u

    -- Component-specific
    card_padding_h   = 16,
    card_padding_v   = 12,
    section_gap      = 24,
    element_gap      = 8,
    inline_gap       = 8,
    tab_bar_height   = 40,
    tab_content_gap  = 16,
    sidebar_width    = 260,
    header_height    = 48,
}

-- ============================================================================
-- BORDER RADIUS - Modern rounded corners
-- ============================================================================

Design.Radius = {
    none   = 0,
    xs     = 4,
    sm     = 6,
    md     = 8,
    lg     = 12,
    xl     = 16,
    xxl    = 20,
    full   = 9999,
    card   = 10,
    button = 6,
    badge  = 4,
}

-- ============================================================================
-- SHADOWS / ELEVATION - Subtle depth
-- ============================================================================

Design.Shadow = {
    -- Since we can't do true shadows, we use layered backgrounds
    elevation = {
        none     = { bg = nil, border = nil },
        low      = { bg = color.new(12, 14, 18, 180), border = color.new(40, 44, 52, 120) },
        medium   = { bg = color.new(15, 17, 22, 200), border = color.new(50, 55, 65, 160) },
        high     = { bg = color.new(18, 20, 26, 220), border = color.new(60, 66, 78, 200) },
    }
}

-- ============================================================================
-- ICON SIZES
-- ============================================================================

Design.IconSize = {
    xs   = 12,
    sm   = 16,
    md   = 20,
    lg   = 24,
    xl   = 28,
    xxl  = 32,
}

-- ============================================================================
-- ANIMATION / TRANSITION TIMINGS
-- ============================================================================

Design.Motion = {
    instant  = 0,
    fast     = 100,   -- ms
    normal   = 200,
    slow     = 300,
    easing   = "ease_out",
}

-- ============================================================================
-- COMPONENT TOKENS - Pre-computed styles for common components
-- ============================================================================

Design.Components = {
    -- Button variants
    button = {
        primary = {
            bg = Design.Colors.semantic.quest.bg,
            bg_hover = Design.Colors.semantic.quest.bg_light,
            bg_active = Design.Colors.semantic.quest.border,
            text = Design.Colors.semantic.quest.text,
            border = Design.Colors.semantic.quest.border,
            radius = Design.Radius.button,
            padding_h = 16,
            padding_v = 8,
            icon_gap = 8,
        },
        secondary = {
            bg = Design.Colors.neutral.bg_tertiary,
            bg_hover = Design.Colors.neutral.bg_hover,
            bg_active = Design.Colors.neutral.bg_active,
            text = Design.Colors.neutral.text_primary,
            border = Design.Colors.neutral.border_primary,
            radius = Design.Radius.button,
            padding_h = 14,
            padding_v = 8,
            icon_gap = 8,
        },
        ghost = {
            bg = color.new(0, 0, 0, 0),
            bg_hover = Design.Colors.neutral.bg_hover,
            text = Design.Colors.neutral.text_secondary,
            text_hover = Design.Colors.neutral.text_primary,
            border = color.new(0, 0, 0, 0),
            radius = Design.Radius.button,
            padding_h = 12,
            padding_v = 6,
            icon_gap = 6,
        },
        danger = {
            bg = Design.Colors.semantic.danger.bg,
            bg_hover = Design.Colors.semantic.danger.bg_light,
            text = Design.Colors.semantic.danger.text,
            border = Design.Colors.semantic.danger.border,
            radius = Design.Radius.button,
            padding_h = 14,
            padding_v = 8,
        },
    },

    -- Card variants
    card = {
        default = {
            bg = Design.Colors.neutral.bg_secondary,
            border = Design.Colors.neutral.border_primary,
            radius = Design.Radius.card,
            padding_h = Design.Spacing.card_padding_h,
            padding_v = Design.Spacing.card_padding_v,
        },
        elevated = {
            bg = Design.Colors.neutral.bg_tertiary,
            border = Design.Colors.neutral.border_secondary,
            radius = Design.Radius.card,
            padding_h = Design.Spacing.card_padding_h,
            padding_v = Design.Spacing.card_padding_v,
        },
        interactive = {
            bg = Design.Colors.neutral.bg_secondary,
            bg_hover = Design.Colors.neutral.bg_hover,
            border = Design.Colors.neutral.border_primary,
            border_focus = Design.Colors.neutral.border_focus,
            radius = Design.Radius.card,
            padding_h = Design.Spacing.card_padding_h,
            padding_v = Design.Spacing.card_padding_v,
        },
        quest_active = {
            bg = Design.Colors.semantic.quest.bg,
            border = Design.Colors.semantic.quest.border,
            radius = Design.Radius.card,
            padding_h = Design.Spacing.card_padding_h,
            padding_v = Design.Spacing.card_padding_v,
        },
        quest_complete = {
            bg = Design.Colors.semantic.success.bg,
            border = Design.Colors.semantic.success.border,
            radius = Design.Radius.card,
            padding_h = Design.Spacing.card_padding_h,
            padding_v = Design.Spacing.card_padding_v,
        },
    },

    -- Input fields
    input = {
        bg = Design.Colors.neutral.bg_tertiary,
        bg_hover = Design.Colors.neutral.bg_hover,
        bg_focus = Design.Colors.neutral.bg_tertiary,
        text = Design.Colors.neutral.text_primary,
        placeholder = Design.Colors.neutral.text_muted,
        border = Design.Colors.neutral.border_primary,
        border_focus = Design.Colors.neutral.border_focus,
        radius = Design.Radius.button,
        padding_h = 12,
        padding_v = 8,
    },

    -- Progress bar
    progress = {
        bg = Design.Colors.neutral.bg_tertiary,
        fill = Design.Colors.semantic.quest.border,
        fill_success = Design.Colors.semantic.success.border,
        fill_warning = Design.Colors.semantic.warning.border,
        fill_danger = Design.Colors.semantic.danger.border,
        radius = Design.Radius.full,
        height = 6,
    },

    -- Badge / Tag
    badge = {
        radius = Design.Radius.badge,
        padding_h = 8,
        padding_v = 2,
        font_size = Design.Typography.size.overline,
    },

    -- Divider
    divider = {
        color = Design.Colors.neutral.border_secondary,
        height = 1,
    },

    -- Tooltip
    tooltip = {
        bg = Design.Colors.neutral.bg_tertiary,
        border = Design.Colors.neutral.border_primary,
        text = Design.Colors.neutral.text_primary,
        radius = Design.Radius.sm,
        padding_h = 10,
        padding_v = 6,
        max_width = 280,
    },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Get color with alpha modifier
function Design.with_alpha(c, alpha)
    local r, g, b, _ = c:get()
    return color.new(r, g, b, math.floor(alpha * 255))
end

---Lighten a color
function Design.lighten_color(c, amount)
    local r, g, b, a = c:get()
    r = math.min(255, r + amount)
    g = math.min(255, g + amount)
    b = math.min(255, b + amount)
    return color.new(r, g, b, a)
end

---Darken a color
function Design.darken_color(c, amount)
    local r, g, b, a = c:get()
    r = math.max(0, r - amount)
    g = math.max(0, g - amount)
    b = math.max(0, b - amount)
    return color.new(r, g, b, a)
end

---Get spacing value
function Design.space(key)
    return Design.Spacing[key] or 0
end

---Get typography size
function Design.text_size(key)
    return Design.Typography.size[key] or Design.Typography.size.body_medium
end

---Get component token
function Design.token(category, variant, property)
    local cat = Design.Components[category]
    if not cat then return nil end
    local var = cat[variant]
    if not var then return nil end
    return var[property]
end

return Design