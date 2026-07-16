-- Quest UI Window System
-- Modern, clean window management for questing-focused UI

local Design = require("ui/quest_ui/design_system")
local SentinelUI = require("ui/lib/sentinel_ui")
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")

local QuestWindow = {}
QuestWindow.__index = QuestWindow

-- Window state
local _app = nil
local _window = nil
local _menu = nil
local _menu_tree = nil
local _open_button = nil
local _initialized = false
local _current_tab = 1

-- Tab definitions (questing-focused only)
local TABS = {
    { id = "dashboard", label = "Dashboard", icon = "📋" },
    { id = "planner", label = "Planner", icon = "🗺️" },
    { id = "profiles", label = "Profiles", icon = "📁" },
    { id = "settings", label = "Settings", icon = "⚙️" },
}

-- ============================================================================
-- MENU CONTROL HELPERS
-- ============================================================================

local function menu_slider_int(min_value, max_value, default_value, id)
    if core and core.menu and core.menu.slider_int then
        return core.menu.slider_int(min_value, max_value, default_value, id)
    end
    if core and core.menu and core.menu.slider then
        local slider = core.menu.slider(min_value, max_value, default_value, id)
        if slider and slider.as_int then return slider:as_int() end
        return slider
    end
    if core and core.menu and core.menu.new_slider then
        local slider = core.menu.new_slider(min_value, max_value, default_value, id)
        if slider and slider.as_int then return slider:as_int() end
        return slider
    end
    return nil
end

local function menu_checkbox(default_value, id)
    if core and core.menu and core.menu.checkbox then
        return core.menu.checkbox(default_value, id)
    end
    return { get_state = function() return default_value end, set = function() end }
end

local function menu_combo(default_value, options, id)
    if core and core.menu and core.menu.combo then
        return core.menu.combo(default_value, options, id)
    end
    return { get = function() return default_value end, set = function() end }
end

local function menu_input_text(default_value, id)
    if core and core.menu and core.menu.input_text then
        return core.menu.input_text(default_value, id)
    end
    return { get = function() return default_value end, set = function() end }
end

-- ============================================================================
-- MENU STATE
-- ============================================================================

local function create_menu_elements()
    return {
        -- Global Questing
        quest_enabled = menu_checkbox(false, "sentinel_ui_quest_enabled"),
        quest_auto_start = menu_checkbox(true, "sentinel_ui_quest_auto_start"),
        quest_auto_replan = menu_checkbox(true, "sentinel_ui_quest_auto_replan"),
        quest_replan_interval = menu_slider_int(1, 30, 5, "sentinel_ui_quest_replan_interval"),

        -- Quest Selection
        quest_max_active = menu_slider_int(1, 5, 3, "sentinel_ui_quest_max_active"),
        quest_skip_elites = menu_checkbox(true, "sentinel_ui_quest_skip_elites"),
        quest_skip_escorts = menu_checkbox(false, "sentinel_ui_quest_skip_escorts"),
        quest_skip_dungeons = menu_checkbox(true, "sentinel_ui_quest_skip_dungeons"),
        quest_skip_pvp = menu_checkbox(true, "sentinel_ui_quest_skip_pvp"),
        quest_max_travel = menu_slider_int(500, 5000, 1800, "sentinel_ui_quest_max_travel"),
        quest_min_xp_per_min = menu_slider_int(100, 2000, 500, "sentinel_ui_quest_min_xp_per_min"),

        -- Combat Integration
        quest_combat_enabled = menu_checkbox(true, "sentinel_ui_quest_combat_enabled"),
        quest_combat_health_flee = menu_slider_int(10, 50, 20, "sentinel_ui_quest_combat_health_flee"),
        quest_combat_max_hostiles = menu_slider_int(1, 5, 3, "sentinel_ui_quest_combat_max_hostiles"),

        -- Inventory Management
        quest_min_bag_slots = menu_slider_int(2, 10, 4, "sentinel_ui_quest_min_bag_slots"),
        quest_vendor_threshold = menu_slider_int(50, 95, 80, "sentinel_ui_quest_vendor_threshold"),
        quest_repair_threshold = menu_slider_int(10, 80, 40, "sentinel_ui_quest_repair_threshold"),
        quest_min_food = menu_slider_int(0, 20, 2, "sentinel_ui_quest_min_food"),
        quest_min_water = menu_slider_int(0, 20, 2, "sentinel_ui_quest_min_water"),

        -- Travel Optimization
        quest_use_flight_paths = menu_checkbox(true, "sentinel_ui_quest_use_flight_paths"),
        quest_hearthstone_threshold = menu_slider_int(5, 30, 10, "sentinel_ui_quest_hearthstone_threshold"),
        quest_max_walk_distance = menu_slider_int(200, 2000, 800, "sentinel_ui_quest_max_walk_distance"),

        -- Rewards
        quest_reward_policy = menu_combo(1, {"Vendor Value", "Upgrade (ilvl)", "Keep All"}, "sentinel_ui_quest_reward_policy"),
        quest_always_keep_quest_items = menu_checkbox(true, "sentinel_ui_quest_keep_quest_items"),

        -- Visual
        quest_show_overlay = menu_checkbox(true, "sentinel_ui_quest_show_overlay"),
        quest_show_path = menu_checkbox(true, "sentinel_ui_quest_show_path"),
        quest_show_objectives = menu_checkbox(true, "sentinel_ui_quest_show_objectives"),
        quest_overlay_scale = menu_slider_int(80, 150, 100, "sentinel_ui_quest_overlay_scale"),

        -- Debug
        quest_debug_logging = menu_checkbox(false, "sentinel_ui_quest_debug_logging"),
        quest_verbose = menu_checkbox(false, "sentinel_ui_quest_verbose"),
    }
end

-- ============================================================================
-- WINDOW CREATION
-- ============================================================================

function QuestWindow.init(app)
    if _initialized then return end

    _app = app
    local bb = app:get_blackboard()

    -- Ensure menu controls exist
    ensure_menu_controls()

    -- Create menu state
    _menu = create_menu_elements()
    _menu_tree = core.menu.tree_node()

    -- Create window
    _window = SentinelUI.new({
        id = "sentinel_quest_control",
        title = "Sentinel Questing",
        default_x = 200,
        default_y = 100,
        default_w = 880,
        default_h = 680,
        theme = "sentinel",
        render_layer = 1,
    })

    -- Seed runtime defaults
    seed_runtime_defaults(bb)

    _initialized = true
    print("[QuestUI] Initialized")
end

function ensure_menu_controls()
    if not core or not core.menu then return end
    if not _menu_tree and type(core.menu.tree_node) == "function" then
        _menu_tree = core.menu.tree_node()
    end
    if not _open_button and type(core.menu.button) == "function" then
        _open_button = core.menu.button("sentinel_quest_open_ui")
    end
end

function seed_runtime_defaults(bb)
    local defaults = {
        ["module.quest.enabled"] = false,
        ["module.quest.auto_start"] = true,
        ["module.quest.auto_replan"] = true,
        ["module.quest.replan_interval"] = 5,
        ["module.quest.max_active"] = 3,
        ["module.quest.skip_elites"] = true,
        ["module.quest.skip_escorts"] = false,
        ["module.quest.skip_dungeons"] = true,
        ["module.quest.skip_pvp"] = true,
        ["module.quest.max_travel"] = 1800,
        ["module.quest.min_xp_per_min"] = 500,
        ["module.quest.combat_enabled"] = true,
        ["module.quest.combat_health_flee"] = 0.20,
        ["module.quest.combat_max_hostiles"] = 3,
        ["module.quest.min_bag_slots"] = 4,
        ["module.quest.vendor_threshold_pct"] = 80,
        ["module.quest.repair_threshold_pct"] = 40,
        ["module.quest.min_food_stacks"] = 2,
        ["module.quest.min_water_stacks"] = 2,
        ["module.quest.use_flight_paths"] = true,
        ["module.quest.hearthstone_threshold_minutes"] = 10,
        ["module.quest.max_walk_distance"] = 800,
        ["module.quest.reward_policy"] = "vendor_value",
        ["module.quest.keep_quest_items"] = true,
        ["module.quest.show_overlay"] = true,
        ["module.quest.show_path"] = true,
        ["module.quest.show_objectives"] = true,
        ["module.quest.overlay_scale"] = 1.0,
    }
    for key, value in pairs(defaults) do
        if not bb:has(key) then
            bb:set(key, value)
        end
    end
end

-- ============================================================================
-- RENDER HELPERS
-- ============================================================================

local function render_text(window, x, y, col, size, text)
    if window.render_text_custom_size then
        window:render_text_custom_size(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), col, size, text)
    else
        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), col, text)
    end
end

local function render_text_bold(window, x, y, col, size, text)
    if window.render_text_custom_size then
        window:render_text_custom_size(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x, y), col, size, text)
    else
        window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x, y), col, text)
    end
end

-- ============================================================================
-- CARD COMPONENT
-- ============================================================================

local function begin_card(window, x, y, w, h, variant, title, subtitle)
    variant = variant or "default"
    local style = Design.Components.card[variant] or Design.Components.card.default

    local bg = style.bg
    local border = style.border
    local radius = style.radius or 10
    local pad_h = style.padding_h or 16
    local pad_v = style.padding_v or 12

    -- Background
    window:render_rect(vec2.new(x, y), vec2.new(w, h), bg, radius)

    -- Border
    window:render_rect_outline(vec2.new(x, y), vec2.new(w, h), border, 1, radius)

    -- Title
    if title then
        local title_y = y + pad_v
        render_text_bold(window, x + pad_h, title_y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_medium, title)
        if subtitle then
            render_text(window, x + pad_h, title_y + Design.Typography.size.heading_medium + 2,
                Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium, subtitle)
        end
        return pad_v * 2 + (subtitle and (Design.Typography.size.heading_medium + Design.Typography.size.caption_medium + 4) or Design.Typography.size.heading_medium) + 4
    end

    return pad_v
end

local function end_card(window, x, y, w, h)
    -- Card content area is implicit
end

-- ============================================================================
-- BUTTON COMPONENT
-- ============================================================================

local function render_button(window, x, y, w, h, label, variant, enabled, icon)
    variant = variant or "primary"
    enabled = enabled ~= false

    local style = Design.Components.button[variant] or Design.Components.button.primary
    local bg = enabled and style.bg or Design.Colors.neutral.bg_disabled
    local text_col = enabled and style.text or Design.Colors.neutral.text_disabled
    local border = style.border or color.new(0, 0, 0, 0)
    local radius = style.radius or 6
    local pad_h = style.padding_h or 16
    local pad_v = style.padding_v or 8
    local icon_gap = style.icon_gap or 6

    -- Hover detection
    local mouse = core.input.get_mouse_pos()
    local hover = enabled and mouse.x >= x and mouse.x <= x + w and mouse.y >= y and mouse.y <= y + h

    if hover and enabled then
        bg = style.bg_hover or bg
    end

    -- Background
    window:render_rect(vec2.new(x, y), vec2.new(w, h), bg, radius)

    -- Border
    if border.a > 0 then
        window:render_rect_outline(vec2.new(x, y), vec2.new(w, h), border, 1, radius)
    end

    -- Content
    local content_x = x + pad_h
    local content_w = w - pad_h * 2
    local label = icon and (icon .. " " .. label) or label

    local text_size = Design.Typography.size.button
    local text_w, text_h = window:get_text_size(enums.window_enums.font_id.FONT_SMALL, text_size, label)
    local text_x = x + (w - text_w) / 2
    local text_y = y + (h - text_h) / 2

    render_text(window, text_x, text_y, text_col, text_size, label)

    return hover and enabled
end

-- ============================================================================
-- INPUT COMPONENTS
-- ============================================================================

local function render_checkbox(window, x, y, size, label, checked, enabled, id)
    enabled = enabled ~= false
    local box_size = size or 20

    local mouse = core.input.get_mouse_pos()
    local hover = enabled and mouse.x >= x and mouse.x <= x + box_size and mouse.y >= y and mouse.y <= y + box_size

    -- Box
    local bg = checked and Design.Colors.neutral.accent or Design.Colors.neutral.bg_tertiary
    if hover and enabled then bg = Design.lighten_color(bg, 15) end
    if not enabled then bg = Design.Colors.neutral.bg_disabled end

    window:render_rect(vec2.new(x, y), vec2.new(box_size, box_size), bg, 4)
    window:render_rect_outline(vec2.new(x, y), vec2.new(box_size, box_size),
        checked and Design.Colors.neutral.accent or Design.Colors.neutral.border_primary, 1, 4)

    -- Checkmark
    if checked then
        local check_col = Design.Colors.neutral.bg_primary
        -- Simple checkmark using lines
        local cx, cy = x + 4, y + box_size / 2
        window:render_line(vec2.new(cx, cy), vec2.new(cx + 4, cy + 4), check_col, 2)
        window:render_line(vec2.new(cx + 4, cy + 4), vec2.new(cx + 12, cy - 4), check_col, 2)
    end

    -- Label
    if label then
        render_text(window, x + box_size + 10, y + (box_size - 14) / 2,
            enabled and Design.Colors.neutral.text_primary or Design.Colors.neutral.text_disabled,
            Design.Typography.size.body_medium, label)
    end

    if hover and enabled and core.input.is_key_pressed(1) then
        return not checked
    end
    return checked
end

local function render_slider(window, x, y, w, min_v, max_v, value, label, format, id)
    local track_h = 6
    local track_y = y + 20
    local handle_r = 10

    local label_h = 18
    if label then
        render_text(window, x, y, Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium, label)
    end

    local val_text = format and string.format(format, value) or tostring(value)
    local val_w, _ = window:get_text_size(enums.window_enums.font_id.FONT_SMALL, Design.Typography.size.caption_medium, val_text)
    render_text(window, x + w - val_w, y, Design.Colors.neutral.text_primary, Design.Typography.size.caption_medium, val_text)

    -- Track
    window:render_rect(vec2.new(x, track_y), vec2.new(w, track_h), Design.Colors.neutral.bg_tertiary, 3)
    local fill_w = ((value - min_v) / (max_v - min_v)) * w
    window:render_rect(vec2.new(x, track_y), vec2.new(fill_w, track_h), Design.Colors.neutral.accent, 3)

    -- Handle
    local handle_x = x + fill_w
    window:render_circle(vec2.new(handle_x, track_y + track_h / 2), handle_r, Design.Colors.neutral.bg_primary)

    -- Interaction
    local mouse = core.input.get_mouse_pos()
    local dragging = core.input.is_key_down(1) and
        mouse.x >= x and mouse.x <= x + w and
        mouse.y >= track_y - 10 and mouse.y <= track_y + track_h + 10

    if dragging then
        local new_val = min_v + ((mouse.x - x) / w) * (max_v - min_v)
        new_val = math.floor(math.max(min_v, math.min(max_v, new_val)))
        return new_val
    end

    return value
end

local function render_combo(window, x, y, w, h, options, selected_idx, label)
    -- Simple combo box rendering
    local mouse = core.input.get_mouse_pos()
    local hover = mouse.x >= x and mouse.x <= x + w and mouse.y >= y and mouse.y <= y + h

    local bg = hover and Design.Colors.neutral.bg_hover or Design.Colors.neutral.bg_tertiary
    window:render_rect(vec2.new(x, y), vec2.new(w, h), bg, 6)
    window:render_rect_outline(vec2.new(x, y), vec2.new(w, h),
        hover and Design.Colors.neutral.border_focus or Design.Colors.neutral.border_primary, 1, 6)

    local text = options[selected_idx] or "Select..."
    render_text(window, x + 12, y + (h - 14) / 2, Design.Colors.neutral.text_primary, Design.Typography.size.body_medium, text)

    -- Arrow
    local arrow_x = x + w - 24
    local arrow_y = y + h / 2
    window:render_line(vec2.new(arrow_x, arrow_y - 3), vec2.new(arrow_x + 6, arrow_y + 3), Design.Colors.neutral.text_secondary, 1.5)
    window:render_line(vec2.new(arrow_x + 12, arrow_y - 3), vec2.new(arrow_x + 6, arrow_y + 3), Design.Colors.neutral.text_secondary, 1.5)

    if hover and core.input.is_key_pressed(1) then
        -- Would open dropdown
    end

    return selected_idx
end

-- ============================================================================
-- TAB BAR
-- ============================================================================

local function render_tab_bar(window, x, y, w, tab_h)
    local tab_w = w / #TABS
    local mouse = core.input.get_mouse_pos()

    for i, tab in ipairs(TABS) do
        local tx = x + (i - 1) * tab_w
        local active = i == _current_tab
        local hover = mouse.x >= tx and mouse.x <= tx + tab_w and mouse.y >= y and mouse.y <= y + tab_h

        local bg = active and Design.Colors.neutral.accent_bg or (hover and Design.Colors.neutral.bg_hover or color.new(0, 0, 0, 0))
        if active or hover then
            window:render_rect(vec2.new(tx, y), vec2.new(tab_w, tab_h), bg, 8)
        end

        if active then
            -- Active indicator
            window:render_rect(vec2.new(tx + tab_w / 2 - 20, y + tab_h - 3), vec2.new(40, 3), Design.Colors.neutral.accent, 1.5)
        end

        -- Icon + Label
        local label = (tab.icon and (tab.icon .. "  ") or "") .. tab.label
        local text_w, text_h = window:get_text_size(enums.window_enums.font_id.FONT_SMALL,
            active and Design.Typography.size.heading_small or Design.Typography.size.body_medium,
            label)
        local text_x = tx + (tab_w - text_w) / 2
        local text_y = y + (tab_h - text_h) / 2
        local text_col = active and Design.Colors.neutral.text_primary or (hover and Design.Colors.neutral.text_primary or Design.Colors.neutral.text_secondary)
        render_text(window, text_x, text_y, text_col,
            active and Design.Typography.size.heading_small or Design.Typography.size.body_medium, label)

        if hover and core.input.is_key_pressed(1) then
            _current_tab = i
        end
    end
end

-- ============================================================================
-- MAIN WINDOW RENDER
-- ============================================================================

function QuestWindow.on_render()
    if not _initialized or not _window then return end

    local window = _window
    local w, h = window:get_size()
    local pad = 16
    local tab_bar_h = 48
    local content_y = tab_bar_h + 8
    local content_h = h - content_y - 16

    -- Background
    window:render_rect(vec2.new(0, 0), vec2.new(w, h), Design.Colors.neutral.bg_primary, 12)
    window:render_rect_outline(vec2.new(0, 0), vec2.new(w, h), Design.Colors.neutral.border_primary, 1, 12)

    -- Tab bar
    render_tab_bar(window, 0, 0, w, tab_bar_h)

    -- Content area
    local tab = TABS[_current_tab]
    if tab then
        if tab.id == "dashboard" then
            render_dashboard_tab(window, pad, content_y, w - pad * 2, content_h)
        elseif tab.id == "planner" then
            render_planner_tab(window, pad, content_y, w - pad * 2, content_h)
        elseif tab.id == "profiles" then
            render_profiles_tab(window, pad, content_y, w - pad * 2, content_h)
        elseif tab.id == "settings" then
            render_settings_tab(window, pad, content_y, w - pad * 2, content_h)
        end
    end
end

-- ============================================================================
-- TAB CONTENT RENDERERS
-- ============================================================================

function render_dashboard_tab(window, x, y, w, h)
    local pad = 16
    local gap = 16
    local card_h = 120

    -- Header
    render_text_bold(window, x, y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_large, "Quest Dashboard")
    render_text(window, x, y + 30, Design.Colors.neutral.text_secondary, Design.Typography.size.body_medium,
        "Active quests, progress, and current objectives")

    local content_y = y + 60

    -- Active Quests Section
    local quests = get_active_quests()
    if #quests > 0 then
        render_text_bold(window, x, content_y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_medium, "Active Quests")
        content_y = content_y + 30

        for i, quest in ipairs(quests) do
            local card_y = content_y + (i - 1) * (card_h + gap)
            render_quest_card(window, x, card_y, w - pad * 2, card_h, quest)
        end
    else
        -- Empty state
        local empty_y = content_y + 40
        window:render_rect(vec2.new(x + 20, empty_y), vec2.new(w - pad * 2 - 40, 120),
            Design.Colors.neutral.bg_tertiary, 12)
        window:render_rect_outline(vec2.new(x + 20, empty_y), vec2.new(w - pad * 2 - 40, 120),
            Design.Colors.neutral.border_secondary, 1, 12)

        render_text_bold(window, x + w / 2 - 80, empty_y + 30, Design.Colors.neutral.text_secondary, Design.Typography.size.heading_medium, "No Active Quests")
        render_text(window, x + w / 2 - 100, empty_y + 65, Design.Colors.neutral.text_muted, Design.Typography.size.body_medium,
            "Enable questing and a profile to start")
    end

    -- Bottom metrics row
    render_metrics_row(window, x, y + h - 100, w - pad * 2)
end

function render_quest_card(window, x, y, w, h, quest)
    local pad = 16
    local radius = 10

    -- Card background
    local is_active = quest.is_current or false
    local bg = is_active and Design.Colors.semantic.quest.bg or Design.Colors.neutral.bg_secondary
    local border = is_active and Design.Colors.semantic.quest.border or Design.Colors.neutral.border_primary

    window:render_rect(vec2.new(x, y), vec2.new(w, h), bg, radius)
    window:render_rect_outline(vec2.new(x, y), vec2.new(w, h), border, 1, radius)

    -- Quest icon
    local icon = get_quest_type_icon(quest.type)
    render_text(window, x + pad, y + pad, Design.Colors.neutral.text_primary, 20, icon)

    -- Title & Level
    render_text_bold(window, x + pad + 30, y + pad, Design.Colors.neutral.text_primary, Design.Typography.size.heading_medium, quest.title)
    render_text(window, x + pad + 30, y + pad + 24, Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium,
        string.format("Lv.%d  |  %s  |  %d/%d objectives", quest.level, quest.zone or "Unknown",
            quest.completed_objectives or 0, quest.total_objectives or 0))

    -- Progress bar
    local progress_w = w - pad * 2 - 30
    local progress_y = y + h - 30
    local progress = (quest.completed_objectives or 0) / math.max(1, quest.total_objectives or 1)

    window:render_rect(vec2.new(x + pad + 30, progress_y), vec2.new(progress_w, 6),
        Design.Colors.neutral.bg_tertiary, 3)
    window:render_rect(vec2.new(x + pad + 30, progress_y), vec2.new(progress_w * progress, 6),
        is_active and Design.Colors.semantic.quest.border or Design.Colors.neutral.accent, 3)

    -- XP & Time
    local xp_text = string.format("XP: %s  |  Est: %dm", format_number(quest.xp or 0), quest.estimated_time or 0)
    render_text(window, x + w - pad - 120, progress_y - 18, Design.Colors.neutral.text_muted,
        Design.Typography.size.caption_medium, xp_text)

    -- Turn-in indicator
    if quest.can_turn_in then
        render_text_bold(window, x + w - pad - 80, y + pad, Design.Colors.semantic.success.text, Design.Typography.size.caption_medium, "READY TO TURN IN")
    end
end

function render_planner_tab(window, x, y, w, h)
    local pad = 16
    local gap = 16

    render_text_bold(window, x, y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_large, "Quest Planner")
    render_text(window, x, y + 30, Design.Colors.neutral.text_secondary, Design.Typography.size.body_medium,
        "View and manage the current quest plan, queue, and execution")

    local content_y = y + 60

    -- Plan Summary Card
    local plan = get_current_plan()
    if plan then
        local card_h = 100
        begin_card(window, x, content_y, w - pad * 2, card_h, "quest_active", "Current Plan", string.format("%d quests · %d min est.", #plan.quests, plan.estimated_time or 0))
        content_y = content_y + 38

        -- Quest queue
        local qx = x + 20
        for i, q in ipairs(plan.quests) do
            local qy = content_y + (i - 1) * 22
            local prefix = i == plan.current_quest and "▶ " or string.format("%d. ", i)
            local status = q.status == "complete" and " ✓" or (q.status == "active" and " ◉" or "")
            render_text(window, qx, qy, i == plan.current_quest and Design.Colors.neutral.accent or Design.Colors.neutral.text_primary,
                Design.Typography.size.body_medium, prefix .. q.title .. status .. " (" .. q.zone .. ")")
        end
        end_card(window, x, content_y, w - pad * 2, card_h)
        content_y = content_y + card_h + gap
    else
        -- No plan
        local card_h = 80
        begin_card(window, x, content_y, w - pad * 2, card_h, "default", "No Active Plan", "Click 'Generate Plan' to create a quest plan")
        local btn_clicked = render_button(window, x + w - pad * 2 - 140, content_y + 20, 140, 36, "Generate Plan", "primary", true, "⚡")
        if btn_clicked then
            -- Trigger plan generation
            local bb = _app and _app:get_blackboard()
            if bb then bb:set("module.quest.force_replan", true) end
        end
        end_card(window, x, content_y, w - pad * 2, card_h)
        content_y = content_y + card_h + gap
    end

    -- Controls row
    local btn_y = content_y + 20
    local btn_w = 160
    local btn_h = 36
    local btn_gap = 12

    render_button(window, x, btn_y, btn_w, btn_h, "Generate Plan", "primary", true, "⚡")
    render_button(window, x + btn_w + btn_gap, btn_y, btn_w, btn_h, "Clear Plan", "secondary", false, "🗑️")
    render_button(window, x + (btn_w + btn_gap) * 2, btn_y, btn_w, btn_h, "Force Replan", "secondary", true, "🔄")

    -- Plan Visualization
    content_y = btn_y + btn_h + gap
    render_plan_visualization(window, x, content_y, w - pad * 2, h - (content_y - y) - pad)
end

function render_profiles_tab(window, x, y, w, h)
    local pad = 16
    local gap = 16

    render_text_bold(window, x, y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_large, "Quest Profiles")
    render_text(window, x, y + 30, Design.Colors.neutral.text_secondary, Design.Typography.size.body_medium,
        "Manage zone-specific quest profiles and auto-load settings")

    local content_y = y + 60

    -- Auto-load section
    local card_h = 100
    begin_card(window, x, content_y, w - pad * 2, card_h, "default", "Auto-Load Settings", "Automatically select profile based on zone/level/faction")
    content_y = content_y + 38

    local enabled = render_checkbox(window, x + 20, content_y + 10, 20, "Enable Auto-Load", get_setting("quest.auto_load", true))
    if enabled ~= get_setting("quest.auto_load", true) then
        set_setting("quest.auto_load", enabled)
    end

    content_y = content_y + 30
    render_text(window, x + 20, content_y, Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium,
        "Faction: " .. (get_player_faction() or "Unknown") .. "  |  Level: " .. get_player_level() .. "  |  Zone: " .. get_current_zone())
    end_card(window, x, content_y, w - pad * 2, card_h)
    content_y = content_y + card_h + gap

    -- Profile list
    render_text_bold(window, x, content_y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_medium, "Available Profiles")
    content_y = content_y + 30

    local profiles = get_available_profiles()
    for i, profile in ipairs(profiles) do
        local card_y = content_y + (i - 1) * (60 + 8)
        local is_active = profile.active
        local card_bg = is_active and Design.Colors.semantic.quest.bg or Design.Colors.neutral.bg_secondary
        local card_border = is_active and Design.Colors.semantic.quest.border or Design.Colors.neutral.border_primary

        local p_w = w - pad * 2
        local p_h = 60
        local p_x = x
        local p_y = card_y

        window:render_rect(vec2.new(p_x, p_y), vec2.new(p_w, p_h), is_active and Design.Colors.semantic.quest.bg or Design.Colors.neutral.bg_secondary, 10)
        window:render_rect_outline(vec2.new(p_x, p_y), vec2.new(p_w, p_h), is_active and Design.Colors.semantic.quest.border or Design.Colors.neutral.border_primary, 1, 10)

        -- Profile info
        render_text_bold(window, p_x + 20, p_y + 10, Design.Colors.neutral.text_primary, Design.Typography.size.body_medium, profile.zone)
        render_text(window, p_x + 20, p_y + 30, Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium,
            string.format("Lv.%d-%d  |  %s  |  %s", profile.level_min, profile.level_max, profile.faction, profile.strategy or "cluster"))

        -- Action button
        local btn_text = is_active and "Active" or "Load"
        local btn_variant = is_active and "primary" or "secondary"
        local clicked = render_button(window, p_x + p_w - 120, p_y + 12, 100, 36, btn_text, btn_variant, not is_active)
        if clicked then
            load_profile(profile.id)
        end
    end
end

function render_settings_tab(window, x, y, w, h)
    local pad = 16
    local gap = 24
    local section_w = (w - pad * 2) / 2 - gap / 2

    render_text_bold(window, x, y, Design.Colors.neutral.text_primary, Design.Typography.size.heading_large, "Quest Settings")
    render_text(window, x, y + 30, Design.Colors.neutral.text_secondary, Design.Typography.size.body_medium,
        "Configure quest behavior, filters, and integration settings")

    local content_y = y + 60
    local left_x = x
    local right_x = x + section_w + gap

    -- LEFT COLUMN
    -- Quest Selection
    local card_h = render_section_quest_selection(window, left_x, content_y, section_w)
    content_y = content_y + card_h + gap

    -- Combat Integration
    card_h = render_section_combat(window, left_x, content_y, section_w)
    content_y = content_y + card_h + gap

    -- Inventory
    card_h = render_section_inventory(window, left_x, content_y, section_w)
    content_y = content_y + card_h + gap

    -- RIGHT COLUMN
    content_y = y + 60

    -- Travel Optimization
    card_h = render_section_travel(window, right_x, content_y, section_w)
    content_y = content_y + card_h + gap

    -- Rewards
    card_h = render_section_rewards(window, right_x, content_y, section_w)
    content_y = content_y + card_h + gap

    -- Visual/Debug
    card_h = render_section_visual(window, right_x, content_y, section_w)
end

function render_section_quest_selection(window, x, y, w)
    local pad = 16
    local card_h = 260

    begin_card(window, x, y, w, card_h, "default", "Quest Selection", "Filters and thresholds for quest acceptance")
    local cy = y + 38

    -- Checkboxes row 1
    local c1 = render_checkbox(window, x + pad, cy, 20, "Skip Elite Quests", get_setting("quest.skip_elites", true))
    local c2 = render_checkbox(window, x + w/2, cy, 20, "Skip Escort Quests", get_setting("quest.skip_escorts", false))
    if c1 ~= get_setting("quest.skip_elites", true) then set_setting("quest.skip_elites", c1) end
    if c2 ~= get_setting("quest.skip_escorts", false) then set_setting("quest.skip_escorts", c2) end

    cy = cy + 28
    local c3 = render_checkbox(window, x + pad, cy, 20, "Skip Dungeon Chains", get_setting("quest.skip_dungeons", true))
    local c4 = render_checkbox(window, x + w/2, cy, 20, "Skip PvP Zones", get_setting("quest.skip_pvp", true))
    if c3 ~= get_setting("quest.skip_dungeons", true) then set_setting("quest.skip_dungeons", c3) end
    if c4 ~= get_setting("quest.skip_pvp", true) then set_setting("quest.skip_pvp", c4) end

    cy = cy + 28
    -- Max travel distance
    local travel = render_slider(window, x + pad, cy, w - pad * 2, 500, 5000, get_setting("quest.max_travel", 1800),
        "Max Travel Distance", "%d yd", "quest.max_travel")
    if travel ~= get_setting("quest.max_travel", 1800) then set_setting("quest.max_travel", travel) end

    cy = cy + 36
    -- Min XP/min
    local xpm = render_slider(window, x + pad, cy, w - pad * 2, 100, 2000, get_setting("quest.min_xp_per_min", 500),
        "Min XP/Minute", "%d XP/min", "quest.min_xp_per_min")
    if xpm ~= get_setting("quest.min_xp_per_min", 500) then set_setting("quest.min_xp_per_min", xpm) end

    end_card(window, x, y, w, card_h)
    return card_h
end

function render_section_combat(window, x, y, w)
    local pad = 16
    local card_h = 140

    begin_card(window, x, y, w, card_h, "default", "Combat Integration", "Combat behavior during questing")
    local cy = y + 38

    local c1 = render_checkbox(window, x + pad, cy, 20, "Enable Combat During Quests", get_setting("quest.combat_enabled", true))
    if c1 ~= get_setting("quest.combat_enabled", true) then set_setting("quest.combat_enabled", c1) end

    cy = cy + 28
    local flee = render_slider(window, x + pad, cy, w - pad * 2, 5, 50, math.floor(get_setting("quest.combat_health_flee", 0.20) * 100),
        "Flee Health Threshold", "%d%%", "quest.combat_health_flee")
    if flee ~= math.floor(get_setting("quest.combat_health_flee", 0.20) * 100) then
        set_setting("quest.combat_health_flee", flee / 100)
    end

    cy = cy + 28
    local max_h = render_slider(window, x + pad, cy, w - pad * 2, 1, 5, get_setting("quest.combat_max_hostiles", 3),
        "Max Simultaneous Hostiles", "%d", "quest.combat_max_hostiles")
    if max_h ~= get_setting("quest.combat_max_hostiles", 3) then set_setting("quest.combat_max_hostiles", max_h) end

    end_card(window, x, y, w, card_h)
    return card_h
end

function render_section_inventory(window, x, y, w)
    local pad = 16
    local card_h = 180

    begin_card(window, x, y, w, card_h, "default", "Inventory Management", "Auto-vendor, repair, and consumable thresholds")
    local cy = y + 38

    -- Min bag slots
    local bags = render_slider(window, x + pad, cy, w - pad * 2, 2, 10, get_setting("quest.min_bag_slots", 4),
        "Min Free Bag Slots", "%d", "quest.min_bag_slots")
    if bags ~= get_setting("quest.min_bag_slots", 4) then set_setting("quest.min_bag_slots", bags) end

    cy = cy + 36
    local vendor = render_slider(window, x + pad, cy, (w - pad * 2) / 2 - 8, 50, 95, get_setting("quest.vendor_threshold", 80),
        "Vendor Threshold", "%d%%", "quest.vendor_threshold")
    if vendor ~= get_setting("quest.vendor_threshold", 80) then set_setting("quest.vendor_threshold", vendor) end

    local repair = render_slider(window, x + w/2 + 8, cy, (w - pad * 2) / 2 - 8, 10, 80, get_setting("quest.repair_threshold", 40),
        "Repair Threshold", "%d%%", "quest.repair_threshold")
    if repair ~= get_setting("quest.repair_threshold", 40) then set_setting("quest.repair_threshold", repair) end

    cy = cy + 36
    local food = render_slider(window, x + pad, cy, (w - pad * 2) / 2 - 8, 0, 20, get_setting("quest.min_food", 2),
        "Min Food Stacks", "%d", "quest.min_food")
    if food ~= get_setting("quest.min_food", 2) then set_setting("quest.min_food", food) end

    local water = render_slider(window, x + w/2 + 8, cy, (w - pad * 2) / 2 - 8, 0, 20, get_setting("quest.min_water", 2),
        "Min Water Stacks", "%d", "quest.min_water")
    if water ~= get_setting("quest.min_water", 2) then set_setting("quest.min_water", water) end

    end_card(window, x, y, w, card_h)
    return card_h
end

function render_section_travel(window, x, y, w)
    local pad = 16
    local card_h = 140

    begin_card(window, x, y, w, card_h, "default", "Travel Optimization", "Flight paths, hearthstone, and walking preferences")
    local cy = y + 38

    local c1 = render_checkbox(window, x + pad, cy, 20, "Use Flight Paths", get_setting("quest.use_flight_paths", true))
    if c1 ~= get_setting("quest.use_flight_paths", true) then set_setting("quest.use_flight_paths", c1) end

    cy = cy + 28
    local hearth = render_slider(window, x + pad, cy, w - pad * 2, 5, 30, get_setting("quest.hearthstone_threshold", 10),
        "Hearthstone Threshold", "%d min", "quest.hearthstone_threshold")
    if hearth ~= get_setting("quest.hearthstone_threshold", 10) then set_setting("quest.hearthstone_threshold", hearth) end

    cy = cy + 28
    local walk = render_slider(window, x + pad, cy, w - pad * 2, 200, 2000, get_setting("quest.max_walk_distance", 800),
        "Max Walk Before Mount/Flight", "%d yd", "quest.max_walk_distance")
    if walk ~= get_setting("quest.max_walk_distance", 800) then set_setting("quest.max_walk_distance", walk) end

    end_card(window, x, y, w, card_h)
    return card_h
end

function render_section_rewards(window, x, y, w)
    local pad = 16
    local card_h = 120

    begin_card(window, x, y, w, card_h, "default", "Reward Selection", "How to choose quest rewards automatically")
    local cy = y + 38

    local policy = render_combo(window, x + pad, cy, w - pad * 2, 36,
        {"Vendor Value", "Upgrade (ilvl)", "Keep All"},
        get_setting("quest.reward_policy", 1) == "vendor_value" and 1 or
        get_setting("quest.reward_policy", 1) == "upgrade" and 2 or 3,
        "Reward Policy")
    if policy == 1 then set_setting("quest.reward_policy", "vendor_value")
    elseif policy == 2 then set_setting("quest.reward_policy", "upgrade")
    else set_setting("quest.reward_policy", "keep_all") end

    cy = cy + 42
    local c1 = render_checkbox(window, x + pad, cy, 20, "Always Keep Quest Items", get_setting("quest.keep_quest_items", true))
    if c1 ~= get_setting("quest.keep_quest_items", true) then set_setting("quest.keep_quest_items", c1) end

    end_card(window, x, y, w, card_h)
    return card_h
end

function render_section_visual(window, x, y, w)
    local pad = 16
    local card_h = 140

    begin_card(window, x, y, w, card_h, "default", "Visual & Debug", "Overlay, logging, and debug options")
    local cy = y + 38

    local c1 = render_checkbox(window, x + pad, cy, 20, "Show Quest Overlay", get_setting("quest.show_overlay", true))
    local c2 = render_checkbox(window, x + w/2, cy, 20, "Show Path Visualization", get_setting("quest.show_path", true))
    if c1 ~= get_setting("quest.show_overlay", true) then set_setting("quest.show_overlay", c1) end
    if c2 ~= get_setting("quest.show_path", true) then set_setting("quest.show_path", c2) end

    cy = cy + 28
    local c3 = render_checkbox(window, x + pad, cy, 20, "Show Objectives on Map", get_setting("quest.show_objectives", true))
    local c4 = render_checkbox(window, x + w/2, cy, 20, "Debug Logging", get_setting("quest.debug_logging", false))
    if c3 ~= get_setting("quest.show_objectives", true) then set_setting("quest.show_objectives", c3) end
    if c4 ~= get_setting("quest.debug_logging", false) then set_setting("quest.debug_logging", c4) end

    cy = cy + 28
    local scale = render_slider(window, x + pad, cy, w - pad * 2, 80, 150, get_setting("quest.overlay_scale", 100),
        "Overlay Scale", "%d%%", "quest.overlay_scale")
    if scale ~= get_setting("quest.overlay_scale", 100) then set_setting("quest.overlay_scale", scale / 100) end

    end_card(window, x, y, w, card_h)
    return card_h
end

-- ============================================================================
-- PLAN VISUALIZATION
-- ============================================================================

function render_plan_visualization(window, x, y, w, h)
    local pad = 16
    local radius = 10

    window:render_rect(vec2.new(x, y), vec2.new(w, h), Design.Colors.neutral.bg_tertiary, radius)
    window:render_rect_outline(vec2.new(x, y), vec2.new(w, h), Design.Colors.neutral.border_secondary, 1, radius)

    render_text_bold(window, x + pad, y + pad, Design.Colors.neutral.text_primary, Design.Typography.size.heading_medium, "Plan Visualization")
    render_text(window, x + pad, y + pad + 24, Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium,
        "Quest flow, travel routes, and objective clusters")

    -- Placeholder for actual visualization
    local viz_y = y + pad + 50
    local viz_h = h - pad * 2 - 50
    window:render_rect(vec2.new(x + pad, viz_y), vec2.new(w - pad * 2, viz_h), Design.Colors.neutral.bg_primary, 6)
    window:render_rect_outline(vec2.new(x + pad, viz_y), vec2.new(w - pad * 2, viz_h), Design.Colors.neutral.border_secondary, 1, 6)

    render_text(window, x + w / 2 - 80, viz_y + viz_h / 2 - 7, Design.Colors.neutral.text_muted, Design.Typography.size.body_medium,
        "Map visualization coming soon")
end

function render_metrics_row(window, x, y, w)
    local metric_w = (w - 16 * 3) / 4
    local gap = 16
    local metric_h = 80

    local metrics = {
        { label = "Active Quests", value = get_active_quest_count(), icon = "📋" },
        { label = "XP/Hr", value = format_number(get_xp_per_hour()) .. " XP", icon = "⚡" },
        { label = "Current Plan", value = get_current_plan() and #get_current_plan().quests or 0 .. " quests", icon = "🗺️" },
        { label = "Status", value = is_questing_enabled() and "Running" or "Stopped", icon = is_questing_enabled() and "▶" or "⏸" },
    }

    for i, m in ipairs(metrics) do
        local mx = x + (i - 1) * (metric_w + gap)
        window:render_rect(vec2.new(x + (i - 1) * (metric_w + gap), y), vec2.new(metric_w, metric_h),
            Design.Colors.neutral.bg_secondary, 10)
        window:render_rect_outline(vec2.new(x + (i - 1) * (metric_w + gap), y), vec2.new(metric_w, metric_h),
            Design.Colors.neutral.border_secondary, 1, 10)

        render_text(window, x + (i - 1) * (metric_w + gap) + 16, y + 12, Design.Colors.neutral.text_secondary, Design.Typography.size.caption_medium, m.label)
        render_text_bold(window, x + (i - 1) * (metric_w + gap) + 16, y + 32, Design.Colors.neutral.text_primary, Design.Typography.size.metric_large, m.value)
        render_text(window, x + (i - 1) * (metric_w + gap) + metric_w - 24, y + 12, Design.Colors.neutral.text_muted, 18, m.icon)
    end
end

-- ============================================================================
-- DATA ACCESS HELPERS
-- ============================================================================

function get_active_quests()
    local bb = _app and _app:get_blackboard()
    if not bb then return {} end

    local tracker = bb:get("module.quest.tracker")
    if not tracker then return {} end

    local quests = {}
    local active = tracker:all() or {}
    for qid, q in pairs(active) do
        quests[#quests + 1] = {
            id = qid,
            title = q.title or "Unknown",
            level = q.level or 0,
            zone = q.zone or "Unknown",
            type = q.type or "KILL",
            is_complete = q.is_complete or false,
            completed_objectives = q.completed_objectives or 0,
            total_objectives = q.total_objectives or 0,
            xp = q.xp or 0,
            estimated_time = q.estimated_time or 0,
            can_turn_in = q.can_turn_in or false,
            is_current = qid == get_current_quest_id(),
        }
    end
    return quests
end

function get_current_plan()
    local bb = _app and _app:get_blackboard()
    if not bb then return nil end
    return bb:get("module.quest.current_plan")
end

function get_current_quest_id()
    local bb = _app and _app:get_blackboard()
    if not bb then return nil end
    local plan = bb:get("module.quest.current_plan")
    if plan and plan.quests and plan.current_quest then
        return plan.quests[plan.current_quest] and plan.quests[plan.current_quest].id
    end
    return nil
end

function get_quest_type_icon(qtype)
    local icons = {
        KILL = "⚔️",
        COLLECT = "📦",
        ESCORT = "🛡️",
        INTERACT = "💬",
        CAST = "✨",
    }
    return icons[qtype] or "📋"
end

function format_number(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end

function get_active_quest_count()
    local quests = get_active_quests()
    return #quests
end

function get_xp_per_hour()
    -- Would track actual XP gain
    return 0
end

function is_questing_enabled()
    local bb = _app and _app:get_blackboard()
    if not bb then return false end
    return bb:get("module.quest.enabled") == true
end

function get_available_profiles()
    -- Would load from profile manager
    return {
        { id = "westfall", zone = "Westfall", level_min = 12, level_max = 18, faction = "Alliance", active = false },
        { id = "redridge", zone = "Redridge", level_min = 16, level_max = 22, faction = "Alliance", active = false },
        { id = "the_barrens", zone = "The Barrens", level_min = 10, level_max = 25, faction = "Horde", active = true },
        { id = "darkshore", zone = "Darkshore", level_min = 12, level_max = 20, faction = "Alliance", active = false },
    }
end

function load_profile(profile_id)
    local bb = _app and _app:get_blackboard()
    if bb then
        bb:set("module.quest.profile_override", profile_id)
    end
end

function get_current_zone()
    if core and core.get_map_name then
        return core.get_map_name() or "Unknown"
    end
    return "Unknown"
end

function get_player_level()
    if core and core.object_manager then
        local player = core.object_manager.get_local_player()
        if player and player.get_level then
            local ok, lvl = pcall(player.get_level, player)
            if ok and lvl then return lvl end
        end
    end
    return 1
end

function get_player_faction()
    local bb = _app and _app:get_blackboard()
    if bb then return bb:get("player.faction") or "Alliance" end
    return "Alliance"
end

-- ============================================================================
-- SETTINGS HELPERS
-- ============================================================================

function get_setting(key, default)
    local bb = _app and _app:get_blackboard()
    if not bb then return default end
    local val = bb:get(key)
    return val ~= nil and val or default
end

function set_setting(key, value)
    local bb = _app and _app:get_blackboard()
    if bb then bb:set(key, value) end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function QuestWindow.shutdown()
    _initialized = false
    _app = nil
    _window = nil
    _menu = nil
    _menu_tree = nil
    _open_button = nil
end

function QuestWindow.get_window()
    return _window
end

function QuestWindow.get_menu()
    return _menu
end

return {
    init = QuestWindow.init,
    shutdown = QuestWindow.shutdown,
    on_render = QuestWindow.on_render,
    on_update = QuestWindow.on_update,
    get_window = QuestWindow.get_window,
    get_menu = QuestWindow.get_menu,
    render_dashboard_tab = render_dashboard_tab,
    render_planner_tab = render_planner_tab,
    render_profiles_tab = render_profiles_tab,
    render_settings_tab = render_settings_tab,
}