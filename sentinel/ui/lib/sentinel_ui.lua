-- Shared Rotation Settings Custom UI
-- A reusable custom window module for displaying rotation settings across all classes

---@private
---@param module_name string
---@param fallback any
---@return any
local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then
        return mod
    end
    return fallback
end

---@type color
local color = require_or("common/color", {
    new = function(r, g, b, a)
        return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 }
    end,
    white = function(a)
        return { r = 255, g = 255, b = 255, a = a or 255 }
    end,
})

---@type vec2
local vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y)
        return { x = x or 0, y = y or 0 }
    end,
})

---@type enums
local enums = require_or("common/enums", {
    window_enums = {
        font_id = {
            FONT_SMALL = 0,
            FONT_SEMI_BIG = 0,
        },
        window_resizing_flags = {
            RESIZE_BOTH_AXIS = 0,
        },
        window_cross_visuals = {
            DEFAULT = 0,
        },
        window_behaviour_flags = {
            NO_SCROLLBAR = 0,
        },
    },
})

-- ============================================================================
-- HELPER FUNCTIONS (Menu API Compatibility)
-- ============================================================================

local function menu_slider_int(min_value, max_value, default_value, id)
    if core and core.menu and core.menu.slider_int then
        return core.menu.slider_int(min_value, max_value, default_value, id)
    end
    if core and core.menu and core.menu.slider then
        local slider = core.menu.slider(min_value, max_value, default_value, id)
        if slider and slider.as_int then
            return slider:as_int()
        end
        return slider
    end
    if core and core.menu and core.menu.new_slider then
        local slider = core.menu.new_slider(min_value, max_value, default_value, id)
        if slider and slider.as_int then
            return slider:as_int()
        end
        return slider
    end
    return nil
end

local function menu_checkbox(default_value, id)
    if core and core.menu and core.menu.checkbox then
        return core.menu.checkbox(default_value, id)
    end
    -- Fallback when core.menu is unavailable (avoids nil dereference in _is_enabled)
    return { get_state = function() return default_value end, set = function() end }
end

-- ============================================================================
-- LAYOUT CONSTANTS
-- ============================================================================

local LAYOUT = {
    padding_top = 14,
    padding_side = 16,
    padding_bottom = 18,

    -- Tab system
    tab_bar_height = 38,
    tab_button_height = 32,
    tab_button_min_width = 90,
    tab_button_max_width = 160,
    tab_button_spacing = 4,
    tab_bar_padding_top = 6,
    tab_content_padding_top = 18,

    -- Section settings
    section_spacing = 22,
    section_header_height = 0,
    section_padding_top = 12,
    section_padding_bottom = 14,
    element_height = 30,
    element_spacing = 10,
    column_spacing = 28,
    slider_bar_height = 8,
    checkbox_size = 18,
    keybind_badge_width = 64,
    keybind_status_width = 48,
    keybind_clear_width = 64,
    separator_height = 1,

    -- Progress bar
    progress_bar_height = 8,
    progress_bar_corner_radius = 4,
    progress_bar_label_gap = 6,

    -- Text input
    text_input_height = 28,
    text_input_padding = 8,

    -- Dropdown
    dropdown_max_visible = 8,
    dropdown_item_height = 26,
    dropdown_min_width = 120,

    -- Listbox
    listbox_default_rows = 6,
    listbox_row_height = 24,
    listbox_scrollbar_width = 6,

    -- Tooltip
    tooltip_offset_x = 12,
    tooltip_offset_y = 8,
    tooltip_padding = 8,
    tooltip_max_width = 280,

    -- Card-based sections (Apple HIG)
    card_corner_radius = 10,
    card_padding_h = 16,
    card_padding_v = 8,
    section_gap = 20,
    section_label_gap = 8,
    section_footer_gap = 6,

    -- Row system (inside cards)
    row_height = 36,
    row_separator_inset = 16,
    row_separator_height = 1,

    -- Toggle switch
    toggle_width = 44,
    toggle_height = 24,
    toggle_thumb_size = 20,
    toggle_thumb_margin = 2,

    -- Stepper (inline)
    stepper_button_size = 24,
    stepper_value_width = 60,
    stepper_gap = 4,

    -- Metric grid
    metric_card_gap = 12,
    metric_number_size = 24,
    metric_label_size = 10,

    -- Typography sizes (for render_text_custom_size)
    font_title = 18,
    font_heading = 13,
    font_body = 12,
    font_caption = 10,
    font_metric = 24,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Helper to lighten color for hover states
local function lighten_color(base_color, amount)
    local r, g, b, a = base_color:get()
    return color.new(
        math.min(255, r + amount),
        math.min(255, g + amount),
        math.min(255, b + amount),
        a
    )
end

local function clamp_number(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function infer_decimals(step)
    local s = tostring(step or 1)
    local dot = s:find("%.")
    if not dot then return 0 end
    local count = #s - dot
    if count < 0 then return 0 end
    if count > 4 then return 4 end
    return count
end

local function render_text_sized(window, x, y, col, size, text)
    if window.render_text_custom_size then
        window:render_text_custom_size(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), col, size, text)
    else
        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), col, text)
    end
end

-- ============================================================================
-- COLOR THEMES
-- ============================================================================

local THEMES = {
    rogue = {
        background = color.new(18, 18, 22, 220),
        border = color.new(140, 30, 30, 255),
        section_bg = color.new(25, 25, 30, 180),
        section_border = color.new(140, 30, 30, 200),
        primary_accent = color.new(180, 35, 35, 255),
        secondary_accent = color.new(220, 180, 60, 255),
        text_primary = color.white(245),
        text_secondary = color.new(200, 200, 210, 255),
        text_disabled = color.new(120, 120, 125, 255),
        slider_fill = color.new(180, 35, 35, 220),
        slider_bg = color.new(40, 40, 45, 200),
        checkbox_active = color.new(180, 35, 35, 255),
        checkbox_inactive = color.new(80, 80, 85, 200),
        checkbox_border = color.new(140, 30, 30, 200),
        keybind_bg = color.new(35, 35, 40, 220),
        keybind_border = color.new(140, 30, 30, 180),
        keybind_active = color.new(220, 180, 60, 255),
        keybind_inactive = color.new(60, 60, 65, 200),
        separator = color.new(140, 30, 30, 200)
    },
    neutral = {
        background = color.new(20, 24, 28, 220),
        border = color.new(80, 120, 160, 255),
        section_bg = color.new(28, 32, 38, 180),
        section_border = color.new(80, 120, 160, 200),
        primary_accent = color.new(100, 150, 200, 255),
        secondary_accent = color.new(150, 200, 100, 255),
        text_primary = color.white(245),
        text_secondary = color.new(200, 200, 210, 255),
        text_disabled = color.new(120, 120, 125, 255),
        slider_fill = color.new(100, 150, 200, 220),
        slider_bg = color.new(40, 44, 50, 200),
        checkbox_active = color.new(100, 150, 200, 255),
        checkbox_inactive = color.new(80, 84, 90, 200),
        checkbox_border = color.new(80, 120, 160, 200),
        keybind_bg = color.new(35, 39, 45, 220),
        keybind_border = color.new(80, 120, 160, 180),
        keybind_active = color.new(150, 200, 100, 255),
        keybind_inactive = color.new(60, 64, 70, 200),
        separator = color.new(80, 120, 160, 200)
    },
    hunter = {
        background = color.new(20, 24, 22, 220),
        border = color.new(90, 140, 70, 255),
        section_bg = color.new(28, 32, 30, 180),
        section_border = color.new(90, 140, 70, 200),
        primary_accent = color.new(120, 180, 90, 255),
        secondary_accent = color.new(200, 160, 80, 255),
        text_primary = color.white(245),
        text_secondary = color.new(200, 205, 200, 255),
        text_disabled = color.new(120, 125, 120, 255),
        slider_fill = color.new(120, 180, 90, 220),
        slider_bg = color.new(40, 44, 42, 200),
        checkbox_active = color.new(120, 180, 90, 255),
        checkbox_inactive = color.new(80, 84, 82, 200),
        checkbox_border = color.new(90, 140, 70, 200),
        keybind_bg = color.new(35, 39, 37, 220),
        keybind_border = color.new(90, 140, 70, 180),
        keybind_active = color.new(200, 160, 80, 255),
        keybind_inactive = color.new(60, 64, 62, 200),
        separator = color.new(90, 140, 70, 200)
    },
    astro = {
        background = color.new(10, 15, 28, 220),
        border = color.new(100, 140, 220, 255),
        section_bg = color.new(18, 25, 40, 180),
        section_border = color.new(80, 120, 200, 200),
        primary_accent = color.new(100, 180, 255, 255),
        secondary_accent = color.new(200, 120, 255, 255),
        text_primary = color.white(245),
        text_secondary = color.new(200, 210, 230, 255),
        text_disabled = color.new(100, 110, 130, 255),
        slider_fill = color.new(100, 180, 255, 220),
        slider_bg = color.new(25, 30, 45, 200),
        checkbox_active = color.new(100, 180, 255, 255),
        checkbox_inactive = color.new(50, 60, 80, 200),
        checkbox_border = color.new(80, 120, 200, 200),
        keybind_bg = color.new(20, 28, 42, 220),
        keybind_border = color.new(80, 120, 200, 180),
        keybind_active = color.new(200, 120, 255, 255),
        keybind_inactive = color.new(40, 50, 70, 200),
        separator = color.new(80, 120, 200, 200)
    },
    apple = {
        -- Background hierarchy (Apple HIG dark mode)
        background       = color.new(0, 0, 0, 245),
        border           = color.new(56, 56, 58, 200),
        section_bg       = color.new(28, 28, 30, 255),
        section_border   = color.new(56, 56, 58, 100),
        primary_accent   = color.new(10, 132, 255, 255),
        secondary_accent = color.new(48, 209, 88, 255),
        text_primary     = color.new(255, 255, 255, 255),
        text_secondary   = color.new(235, 235, 245, 153),
        text_disabled    = color.new(235, 235, 245, 76),
        slider_fill      = color.new(10, 132, 255, 230),
        slider_bg        = color.new(120, 120, 128, 92),
        checkbox_active  = color.new(10, 132, 255, 255),
        checkbox_inactive = color.new(120, 120, 128, 92),
        checkbox_border  = color.new(84, 84, 88, 153),
        keybind_bg       = color.new(44, 44, 46, 220),
        keybind_border   = color.new(56, 56, 58, 180),
        keybind_active   = color.new(48, 209, 88, 255),
        keybind_inactive = color.new(58, 58, 60, 200),
        separator        = color.new(84, 84, 88, 92),
        bg_card          = color.new(28, 28, 30, 255),
        bg_elevated      = color.new(44, 44, 46, 255),
        bg_hover         = color.new(58, 58, 60, 255),
        bg_tooltip       = color.new(28, 28, 30, 245),
        bg_input         = color.new(44, 44, 46, 255),
        bg_input_focused = color.new(58, 58, 60, 255),
        border_input     = color.new(84, 84, 88, 153),
        border_input_focused = color.new(10, 132, 255, 255),
        text_placeholder = color.new(235, 235, 245, 76),
        dropdown_hover   = color.new(10, 132, 255, 40),
        listbox_selected = color.new(10, 132, 255, 50),
        progress_track   = color.new(44, 44, 46, 255),
        status_green     = color.new(48, 209, 88, 255),
        status_red       = color.new(255, 69, 58, 255),
        status_orange    = color.new(255, 159, 10, 255),
        status_yellow    = color.new(255, 214, 10, 255),
        status_purple    = color.new(191, 90, 242, 255),
        toggle_track_on  = color.new(48, 209, 88, 255),
        toggle_track_off = color.new(120, 120, 128, 92),
        toggle_thumb     = color.new(255, 255, 255, 255),
        row_separator    = color.new(84, 84, 88, 61),
        text_footer      = color.new(235, 235, 245, 102),
    },
    sentinel = {
        background        = color.new(14, 16, 20, 240),
        border            = color.new(52, 60, 72, 200),
        section_bg        = color.new(22, 26, 32, 230),
        section_border    = color.new(44, 52, 64, 170),
        primary_accent    = color.new(86, 140, 210, 255),
        secondary_accent  = color.new(210, 160, 80, 255),
        text_primary      = color.new(220, 225, 232, 245),
        text_secondary    = color.new(160, 170, 182, 210),
        text_disabled     = color.new(100, 108, 118, 170),
        slider_fill       = color.new(86, 140, 210, 230),
        slider_bg         = color.new(36, 42, 50, 215),
        checkbox_active   = color.new(86, 140, 210, 255),
        checkbox_inactive = color.new(48, 54, 64, 210),
        checkbox_border   = color.new(72, 82, 96, 200),
        keybind_bg        = color.new(28, 32, 40, 220),
        keybind_border    = color.new(52, 60, 72, 190),
        keybind_active    = color.new(210, 160, 80, 255),
        keybind_inactive  = color.new(48, 54, 64, 210),
        separator         = color.new(80, 90, 105, 100),
        bg_tooltip        = color.new(18, 20, 26, 245),
        bg_input          = color.new(28, 32, 40, 255),
        bg_input_focused  = color.new(34, 40, 48, 255),
        border_input      = color.new(52, 60, 72, 255),
        border_input_focused = color.new(86, 140, 210, 255),
        text_placeholder  = color.new(100, 108, 118, 170),
        dropdown_hover    = color.new(86, 140, 210, 35),
        listbox_selected  = color.new(86, 140, 210, 45),
        progress_track    = color.new(36, 42, 50, 255),
        bg_card           = color.new(22, 26, 32, 255),
        bg_elevated       = color.new(30, 36, 44, 255),
        bg_hover          = color.new(38, 44, 52, 255),
        status_green      = color.new(72, 200, 110, 255),
        status_red        = color.new(230, 80, 70, 255),
        status_orange     = color.new(235, 150, 40, 255),
        status_yellow     = color.new(235, 200, 50, 255),
        status_purple     = color.new(170, 100, 230, 255),
        toggle_track_on   = color.new(86, 140, 210, 255),
        toggle_track_off  = color.new(100, 100, 110, 85),
        toggle_thumb      = color.new(240, 242, 245, 255),
        row_separator     = color.new(80, 90, 105, 45),
        text_footer       = color.new(160, 170, 182, 120),
    }
}

-- ============================================================================
-- KEY NAME MAPPING
-- ============================================================================

local KEY_NAMES = {
    -- Windows virtual-key codes
    [1] = "LMB",
    [2] = "RMB",
    [4] = "MMB",
    [5] = "Mouse4",
    [6] = "Mouse5",
    [16] = "Shift",
    [17] = "Ctrl",
    [18] = "Alt",
    [160] = "L-Shift",
    [161] = "R-Shift",
    [162] = "L-Ctrl",
    [163] = "R-Ctrl",
    [164] = "L-Alt",
    [165] = "R-Alt",
    [112] = "F1",
    [113] = "F2",
    [114] = "F3",
    [115] = "F4",
    [116] = "F5",
    [117] = "F6",
    [118] = "F7",
    [119] = "F8",
    [120] = "F9",
    [121] = "F10",
    [122] = "F11",
    [123] = "F12",
    [999] = "None"
}

-- ============================================================================
-- WIDGET CLASS
-- ============================================================================

---@class rotation_settings_ui
---@field id string
---@field title string
---@field window any
---@field sections table[]
---@field theme_name string
---@field colors table
---@field menu table
---@field _pos_x any
---@field _pos_y any
---@field _size_x any
---@field _size_y any
---@field _window_epoch integer
---@field _window_id string
---@field _tooltip_pos table|nil
---@field _overlay_queue function[]
---@field _dropdown_open_id string|nil
---@field _dropdown_scroll table
---@field _text_input_focus_id string|nil
---@field _text_input_buffers table
---@field _text_input_cursor table
---@field _text_input_blink number
---@field _listbox_scroll table
---@field _listbox_selected table
---@field _listbox_consumed_scroll boolean
---@field _card_heights table
local RotationSettingsUI = {}
RotationSettingsUI.__index = RotationSettingsUI

local function is_mouse_pressed_left(window)
    if not window then
        return false
    end
    -- ImGui: button 0 = left, button 1 = right. Only accept left click.
    return window:is_mouse_button_pressed(0)
end

local function is_mouse_clicked_left(window)
    if not window then
        return false
    end
    return window:is_mouse_button_clicked(0)
end

local function render_toggle_switch(window, colors, x, y, is_on)
    local w = LAYOUT.toggle_width
    local h = LAYOUT.toggle_height
    local thumb_size = LAYOUT.toggle_thumb_size
    local margin = LAYOUT.toggle_thumb_margin
    local radius = h / 2
    local start_pos = vec2.new(x, y)
    local end_pos = vec2.new(x + w, y + h)
    local track_color = is_on
        and (colors.toggle_track_on or colors.secondary_accent)
        or (colors.toggle_track_off or colors.checkbox_inactive)
    window:render_rect_filled(start_pos, end_pos, track_color, radius)
    local thumb_x = is_on and (x + w - thumb_size - margin) or (x + margin)
    local thumb_y = y + margin
    local thumb_color = colors.toggle_thumb or color.new(255, 255, 255, 255)
    window:render_rect_filled(
        vec2.new(thumb_x, thumb_y),
        vec2.new(thumb_x + thumb_size, thumb_y + thumb_size),
        thumb_color, thumb_size / 2)
    local hovered = window:is_mouse_hovering_rect(start_pos, end_pos)
    if hovered then
        window:is_mouse_hovering_rect_block_movement(start_pos, end_pos)
    end
    if hovered and is_mouse_clicked_left(window) then
        window:block_input_capture()
        return not is_on
    end
    return nil
end

function RotationSettingsUI:_get_window_local_mouse_pos(space_hint)
    if not self.window then
        return nil
    end

    local ok_mouse, mouse_pos = pcall(function()
        return self.window:get_mouse_pos()
    end)
    if not ok_mouse or not mouse_pos then
        return nil
    end

    local ok_pos, window_pos = pcall(function()
        return self.window:get_position()
    end)

    local adjusted = nil
    if ok_pos and window_pos then
        adjusted = vec2.new(mouse_pos.x - window_pos.x, mouse_pos.y - window_pos.y)
    end

    if space_hint == "raw" then
        return mouse_pos, "raw"
    end
    if space_hint == "adjusted" and adjusted then
        return adjusted, "adjusted"
    end

    local ok_size, window_size = pcall(function()
        return self.window:get_size()
    end)

    local function is_inside_window(pos)
        if not ok_size or not window_size then
            return true
        end
        return pos.x >= 0 and pos.y >= 0 and pos.x <= window_size.x and pos.y <= window_size.y
    end

    local last = self._active_slider and self._active_slider.last_mouse_pos
    local best = nil
    local best_score = nil
    local best_space = nil

    local candidates = {
        { pos = mouse_pos, space = "raw" }
    }
    if adjusted then
        table.insert(candidates, { pos = adjusted, space = "adjusted" })
    end

    for _, candidate in ipairs(candidates) do
        local pos = candidate.pos
        local inside = is_inside_window(pos) and 0 or 1000000
        local delta = 0
        if last then
            local dx = pos.x - last.x
            local dy = pos.y - last.y
            delta = (dx * dx) + (dy * dy)
        end

        local score = inside + delta
        if best_score == nil or score < best_score then
            best_score = score
            best = pos
            best_space = candidate.space
        end
    end

    return best, best_space
end

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

---Creates a new rotation settings UI instance
---@param config table Configuration table {id, title, default_x, default_y, default_w, default_h, theme}
---@return rotation_settings_ui
function RotationSettingsUI.new(config)
    local self = setmetatable({}, RotationSettingsUI)

    self.id = config.id or "rotation_ui"
    self.title = config.title or "Rotation Settings"
    self.theme_name = config.theme or "astro"
    self.colors = THEMES[self.theme_name] or THEMES.astro
    self.sections = {}
    self._render_layer = config.render_layer
    self._window_epoch = 0

    -- Tab state
    self.active_tab_index = 1

    -- Menu elements for persistence and control
    self.menu = {
        enable = menu_checkbox(false, "rotation_ui_enable_" .. self.id),
        pos_x = menu_slider_int(0, 10000, config.default_x or 700, "rotation_ui_x_" .. self.id),
        pos_y = menu_slider_int(0, 10000, config.default_y or 200, "rotation_ui_y_" .. self.id),
        size_x = menu_slider_int(0, 10000, config.default_w or 450, "rotation_ui_w_" .. self.id),
        size_y = menu_slider_int(0, 10000, config.default_h or 600, "rotation_ui_h_" .. self.id),
        active_tab = menu_slider_int(0, 100, 1, "rotation_ui_tab_" .. self.id)
    }

    self._pos_x = self.menu.pos_x
    self._pos_y = self.menu.pos_y
    self._size_x = self.menu.size_x
    self._size_y = self.menu.size_y

    self._active_slider = nil
    self._active_key_capture = nil
    self._before_tabs_fn = nil
    self._tooltip = nil
    self._tooltip_pos = nil
    self._scroll_y = 0
    self._content_height = 0
    self._scroll_drag = false
    self._prev_window_scroll = 0

    -- Overlay queue (renders after pop_clip_rect for dropdowns/tooltips)
    self._overlay_queue = {}

    -- Dropdown state
    self._dropdown_open_id = nil
    self._dropdown_scroll = {}

    -- Text input state
    self._text_input_focus_id = nil
    self._text_input_buffers = {}
    self._text_input_cursor = {}
    self._text_input_blink = 0
    self._text_input_prev_keys = {}

    -- Listbox state
    self._listbox_scroll = {}
    self._listbox_selected = {}
    self._listbox_consumed_scroll = false
    self._listbox_hover_id = nil
    self._prev_engine_scroll_y = nil

    -- Card height cache (previous-frame heights for pre-drawing bg)
    self._card_heights = {}

    return self
end

-- ============================================================================
-- SECTION REGISTRATION
-- ============================================================================

---Registers a section to be displayed in the UI
---@param section table Section configuration {id, label, type, elements, labels, columns, visible_when}
function RotationSettingsUI:register_section(section)
    if not section or not section.id or not section.type then
        return
    end

    table.insert(self.sections, section)
end

-- ============================================================================
-- BUILDER API (Reusable UI Library Layer)
-- ============================================================================

---@class rotation_settings_ui_tab_builder
---@field _ui rotation_settings_ui
---@field _section table
local TabBuilder = {}
TabBuilder.__index = TabBuilder

---@param ui rotation_settings_ui
---@param section table
---@return rotation_settings_ui_tab_builder
function TabBuilder.new(ui, section)
    return setmetatable({ _ui = ui, _section = section }, TabBuilder)
end

function TabBuilder:_add_group(group)
    if not group or not group.type then
        return self
    end
    self._section.groups = self._section.groups or {}
    table.insert(self._section.groups, group)
    return self
end

---@param opts table {label?, columns?, elements, visible_when?}
function TabBuilder:checkbox_grid(opts)
    return self:_add_group({
        type = "checkbox_grid",
        label = opts and opts.label or nil,
        columns = opts and opts.columns or nil,
        elements = opts and opts.elements or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, visible_when?}
function TabBuilder:slider_list(opts)
    return self:_add_group({
        type = "slider_list",
        label = opts and opts.label or nil,
        elements = opts and opts.elements or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, visible_when?}
function TabBuilder:combo_list(opts)
    return self:_add_group({
        type = "combo_list",
        label = opts and opts.label or nil,
        elements = opts and opts.elements or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, element, options, tooltip?, visible_when?}
function TabBuilder:segmented_control(opts)
    return self:_add_group({
        type = "segmented_control",
        label = opts and opts.label or nil,
        element = opts and opts.element or nil,
        options = opts and opts.options or {},
        tooltip = opts and opts.tooltip or nil,
        visible_when = opts and opts.visible_when or nil,
    })
end

---@param opts table {elements, labels?, visible_when?}
function TabBuilder:keybind_grid(opts)
    return self:_add_group({
        type = "keybind_grid",
        elements = opts and opts.elements or nil,
        labels = opts and opts.labels or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, visible_when?}
function TabBuilder:progress_bar_list(opts)
    return self:_add_group({
        type = "progress_bar_list",
        label = opts and opts.label or nil,
        elements = opts and opts.elements or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, visible_when?}
function TabBuilder:dropdown_list(opts)
    return self:_add_group({
        type = "dropdown_list",
        label = opts and opts.label or nil,
        id = opts and opts.id or nil,
        elements = opts and opts.elements or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, visible_when?}
function TabBuilder:text_input_list(opts)
    return self:_add_group({
        type = "text_input_list",
        label = opts and opts.label or nil,
        id = opts and opts.id or nil,
        elements = opts and opts.elements or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, visible_when?}
function TabBuilder:listbox(opts)
    return self:_add_group({
        type = "listbox",
        label = opts and opts.label or nil,
        id = opts and opts.id or nil,
        elements = opts and opts.elements or nil,
        footer = opts and opts.footer or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, columns, visible_when?}
function TabBuilder:hrow(opts)
    return self:_add_group({
        type = "hrow",
        label = opts and opts.label or nil,
        columns = opts and opts.columns or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, col_defs, visible_when?}
function TabBuilder:columns(opts)
    return self:_add_group({
        type = "columns",
        label = opts and opts.label or nil,
        col_defs = opts and opts.col_defs or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, render_fn, card?, visible_when?}
function TabBuilder:custom_render(opts)
    return self:_add_group({
        type = "custom",
        label = opts and opts.label or nil,
        render_fn = opts and opts.render_fn or nil,
        card = opts and opts.card,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {label?, elements, footer?, visible_when?, card?}
function TabBuilder:row_list(opts)
    return self:_add_group({
        type = "row_list",
        label = opts and opts.label or nil,
        elements = opts and opts.elements or nil,
        footer = opts and opts.footer or nil,
        visible_when = opts and opts.visible_when or nil,
        card = opts and opts.card,
    })
end

---@param opts table {label?, elements, footer?, visible_when?, card?}
function TabBuilder:metric_grid(opts)
    return self:_add_group({
        type = "metric_grid",
        label = opts and opts.label or nil,
        elements = opts and opts.elements or nil,
        footer = opts and opts.footer or nil,
        visible_when = opts and opts.visible_when or nil,
        card = opts and opts.card,
    })
end

---@param tab table {id, label, visible_when?}
---@param build_fn fun(t:rotation_settings_ui_tab_builder)
function RotationSettingsUI:add_tab(tab, build_fn)
    if not tab or not tab.id or not tab.label then
        return
    end
    local section = {
        id = tab.id,
        label = tab.label,
        type = "tab",
        groups = {},
        visible_when = tab.visible_when
    }
    if build_fn and type(build_fn) == "function" then
        local builder = TabBuilder.new(self, section)
        pcall(build_fn, builder)
    end
    self:register_section(section)
end

-- Example:
-- ui:add_tab({ id = "core", label = "Core" }, function(t)
--     t:keybind_grid({ elements = { menu.enable_toggle }, labels = { "Enable" } })
--     t:checkbox_grid({ label = "Toggles", columns = 2, elements = { { element = menu.auto_feint_enabled, label = "Auto Feint" } } })
--     t:slider_list({ label = "Thresholds", elements = { { element = menu.auto_pot_threshold, label = "Potion HP%", suffix = "%" } } })
-- end)

-- Convenience: bulk replace existing tabs (useful when rebuilding a UI dynamically)
---@param tabs table[]
function RotationSettingsUI:set_tabs(tabs)
    self.sections = {}
    if not tabs then
        return
    end
    for _, tab in ipairs(tabs) do
        if tab then
            self:register_section(tab)
        end
    end
end

-- Export builder for advanced external usage/debugging.
RotationSettingsUI.TabBuilder = TabBuilder

-- ============================================================================
-- WINDOW MANAGEMENT
-- ============================================================================

function RotationSettingsUI:_build_window()
    self._window_epoch = (self._window_epoch or 0) + 1
    self._window_id = string.format("%s##%d", self.title, self._window_epoch)
    self.window = core.menu.window(self._window_id)

    if self._pos_x and self._pos_y then
        self.window:set_initial_position(vec2.new(self._pos_x:get(), self._pos_y:get()))
    end
    if self._size_x and self._size_y then
        self.window:set_initial_size(vec2.new(self._size_x:get(), self._size_y:get()))
    end
end

function RotationSettingsUI:_sync_window_state()
    if not self.window then
        return
    end

    local ok_pos, pos = pcall(function()
        return self.window:get_position()
    end)
    if ok_pos and pos and self._pos_x and self._pos_y then
        local x = math.floor(pos.x + 0.5)
        local y = math.floor(pos.y + 0.5)
        if x ~= self._pos_x:get() then
            self._pos_x:set(x)
        end
        if y ~= self._pos_y:get() then
            self._pos_y:set(y)
        end
    end

    local ok_size, size = pcall(function()
        return self.window:get_size()
    end)
    if ok_size and size and self._size_x and self._size_y then
        local sx = math.floor(size.x + 0.5)
        local sy = math.floor(size.y + 0.5)
        if sx ~= self._size_x:get() then
            self._size_x:set(sx)
        end
        if sy ~= self._size_y:get() then
            self._size_y:set(sy)
        end
    end
end

function RotationSettingsUI:_is_enabled()
    if self.menu and self.menu.enable then
        return self.menu.enable:get_state()
    end
    return false
end

-- ============================================================================
-- KEY NAME HELPER
-- ============================================================================

function RotationSettingsUI:_get_key_name(key_code)
    if KEY_NAMES[key_code] then
        return KEY_NAMES[key_code]
    end

    if key_code >= 48 and key_code <= 57 then
        return string.char(key_code)
    end

    if key_code >= 65 and key_code <= 90 then
        return string.char(key_code)
    end

    return "Key" .. key_code
end

-- ============================================================================
-- SECTION VISIBILITY
-- ============================================================================

function RotationSettingsUI:_is_section_visible(section)
    if section.visible_when and type(section.visible_when) == "function" then
        local ok, result = pcall(section.visible_when)
        if ok then
            return result == true
        end
        return false
    end
    return true
end

-- ============================================================================
-- TAB STATE MANAGEMENT
-- ============================================================================

function RotationSettingsUI:_sync_tab_state()
    if self.menu.active_tab then
        local saved_tab = self.menu.active_tab:get()
        if saved_tab >= 1 and saved_tab <= #self.sections then
            self.active_tab_index = saved_tab
        end
    end
end

-- ============================================================================
-- TAB BAR RENDERING
-- ============================================================================

function RotationSettingsUI:_render_tab_bar(y_start_override)
    local window_size = self.window:get_size()
    -- Reserve space on the right for the engine's window close button (X)
    local close_btn_reserve = 50
    local content_width = window_size.x - (2 * LAYOUT.padding_side) - close_btn_reserve
    local x_start = LAYOUT.padding_side
    local y_start = y_start_override or LAYOUT.padding_top

    -- Calculate tab button width
    local num_tabs = #self.sections
    if num_tabs == 0 then
        return y_start
    end

    local total_spacing = (num_tabs - 1) * LAYOUT.tab_button_spacing
    local available_width = content_width - total_spacing
    local tab_width = math.min(LAYOUT.tab_button_max_width,
                                math.max(LAYOUT.tab_button_min_width,
                                         available_width / num_tabs))

    local current_x = x_start

    for i, section in ipairs(self.sections) do
        if self:_is_section_visible(section) then
            local is_active = (i == self.active_tab_index)

            -- Tab button bounds
            local tab_start = vec2.new(current_x, y_start)
            local tab_end = vec2.new(current_x + tab_width, y_start + LAYOUT.tab_button_height)

            -- Check hover state
            local is_hovered = self.window:is_mouse_hovering_rect(tab_start, tab_end)
            self.window:is_mouse_hovering_rect_block_movement(tab_start, tab_end)

            -- Determine colors based on state
            local bg_color, text_color, border_color
            if is_active then
                bg_color = self.colors.primary_accent
                text_color = color.white(255)
                border_color = nil
            elseif is_hovered then
                bg_color = lighten_color(self.colors.section_bg, 20)
                text_color = self.colors.text_primary
                border_color = self.colors.section_border
            else
                bg_color = self.colors.section_bg
                text_color = self.colors.text_secondary
                border_color = self.colors.section_border
            end

            -- Render tab button background
            self.window:render_rect_filled(tab_start, tab_end, bg_color, 6.0)

            -- Render border (skip for active tab — solid accent fill is sufficient)
            if border_color then
                self.window:render_rect(tab_start, tab_end, border_color, 6.0, 1.0)
            end

            -- Render tab label (centered, truncated if needed)
            local label = section.label or ("Tab " .. i)
            local text_size = self.window:get_text_size(label)

            -- Truncate label if too long
            local max_text_width = tab_width - 10
            if text_size.x > max_text_width then
                local truncated_label = label
                while #truncated_label > 0 do
                    local test_label = truncated_label .. "..."
                    local test_size = self.window:get_text_size(test_label)
                    if test_size.x <= max_text_width then
                        label = test_label
                        text_size = test_size
                        break
                    end
                    truncated_label = string.sub(truncated_label, 1, -2)
                end
            end

            local text_x = current_x + (tab_width - text_size.x) / 2
            local text_y = y_start + (LAYOUT.tab_button_height - text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(text_x, text_y), text_color, label)

            -- Handle click
            if self.window:is_rect_clicked(tab_start, tab_end) then
                self.active_tab_index = i
                if self.menu.active_tab then
                    self.menu.active_tab:set(i)
                end
            end

            current_x = current_x + tab_width + LAYOUT.tab_button_spacing
        end
    end

    return y_start + LAYOUT.tab_button_height + LAYOUT.tab_bar_padding_top
end

-- ============================================================================
-- ACTIVE TAB CONTENT RENDERING
-- ============================================================================

function RotationSettingsUI:_render_active_tab_content(y_offset)
    if self.active_tab_index < 1 or self.active_tab_index > #self.sections then
        return y_offset
    end

    local section = self.sections[self.active_tab_index]
    if not section or not self:_is_section_visible(section) then
        -- Auto-select first visible tab instead of showing blank content
        for i, s in ipairs(self.sections) do
            if self:_is_section_visible(s) then
                self.active_tab_index = i
                section = s
                break
            end
        end
        if not section or not self:_is_section_visible(section) then
            return y_offset
        end
    end

    -- Render section content (NO header, just content)
    if section.type == "keybind_grid" then
        return self:_render_keybind_grid(section, y_offset)
    elseif section.type == "checkbox_grid" then
        return self:_render_checkbox_grid(section, y_offset)
    elseif section.type == "slider_list" then
        return self:_render_slider_list(section, y_offset)
    elseif section.type == "combo_list" then
        return self:_render_combo_list(section, y_offset)
    elseif section.type == "tab" then
        return self:_render_tab_groups(section, y_offset)
    end

    return y_offset
end

-- ============================================================================
-- SECTION HEADER RENDERING (DEPRECATED - replaced by tabs)
-- ============================================================================

function RotationSettingsUI:_render_section_header(section, y_offset)
    if not section.label then
        return
    end

    local window_size = self.window:get_size()
    local x_start = LAYOUT.padding_side
    local x_end = window_size.x - LAYOUT.padding_side

    -- Section background
    local section_bg_start = vec2.new(x_start, y_offset)
    local section_bg_end = vec2.new(x_end, y_offset + LAYOUT.section_header_height)
    self.window:render_rect_filled(section_bg_start, section_bg_end, self.colors.section_bg, 8.0)
    self.window:render_rect(section_bg_start, section_bg_end, self.colors.section_border, 8.0, 1.0)

    -- Section label (centered)
    local text_size = self.window:get_text_size(section.label)
    local text_x = x_start + ((x_end - x_start) - text_size.x) / 2
    local text_y = y_offset + (LAYOUT.section_header_height - text_size.y) / 2
    self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(text_x, text_y),
        self.colors.secondary_accent, section.label)
end

-- ============================================================================
-- KEYBIND GRID RENDERING (Custom + Interactive)
-- ============================================================================

function RotationSettingsUI:_render_keybind_grid(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    for i, element in ipairs(section.elements) do
        if element then
            local label = (section.labels and section.labels[i]) or ("Keybind " .. i)

            local ok_key, key_code = pcall(function()
                return element:get_key_code()
            end)
            if not ok_key then
                key_code = 999
            end

            local ok_state, is_enabled = pcall(function()
                if element.get_toggle_state then
                    return element:get_toggle_state()
                end
                if element.get_state then
                    return element:get_state()
                end
                return false
            end)
            if not ok_state or is_enabled == nil then
                is_enabled = false
            end

            local key_name = self:_get_key_name(key_code)

            -- Define rectangles
            local key_box_start = vec2.new(x_start, y_offset)
            local key_box_end = vec2.new(x_start + LAYOUT.keybind_badge_width, y_offset + LAYOUT.element_height - 2)

            local clear_action_width = LAYOUT.keybind_clear_width
            local clear_box_end = vec2.new(x_start + content_width, y_offset + LAYOUT.element_height - 2)
            local clear_box_start = vec2.new(clear_box_end.x - clear_action_width, y_offset)
            local status_box_end = vec2.new(clear_box_start.x, y_offset + LAYOUT.element_height - 2)
            local status_box_start = vec2.new(status_box_end.x - LAYOUT.keybind_status_width, y_offset)

            -- Hover states for visual feedback
            local is_key_hovered = self.window:is_mouse_hovering_rect(key_box_start, key_box_end)
            local is_status_hovered = self.window:is_mouse_hovering_rect(status_box_start, status_box_end)
            local is_clear_hovered = self.window:is_mouse_hovering_rect(clear_box_start, clear_box_end)

            -- Prevent window dragging while interacting with this row
            self.window:is_mouse_hovering_rect_block_movement(key_box_start, key_box_end)
            self.window:is_mouse_hovering_rect_block_movement(status_box_start, status_box_end)
            self.window:is_mouse_hovering_rect_block_movement(clear_box_start, clear_box_end)

            -- Custom Rendering - Key badge (left)
            local is_capturing_keybind = self._active_key_capture and self._active_key_capture.element == element

            local key_bg_color = is_key_hovered and lighten_color(self.colors.keybind_bg, 30) or self.colors.keybind_bg
            if is_capturing_keybind then
                key_bg_color = self.colors.keybind_active
            end
            self.window:render_rect_filled(key_box_start, key_box_end, key_bg_color, 4.0)
            self.window:render_rect(key_box_start, key_box_end, self.colors.keybind_border, 4.0, 1.0)

            local key_text_size = self.window:get_text_size(key_name)
            local key_text_x = x_start + (LAYOUT.keybind_badge_width - key_text_size.x) / 2
            local key_text_y = y_offset + (LAYOUT.element_height - 2 - key_text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(key_text_x, key_text_y),
                self.colors.text_primary, key_name)

            if self.window:is_rect_clicked(key_box_start, key_box_end) then
                self:_start_key_capture(element, label)
            end

            -- Label (middle)
            local label_x = x_start + LAYOUT.keybind_badge_width + 12
            local label_y = y_offset + (LAYOUT.element_height - 2 - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(label_x, label_y),
                self.colors.text_primary, label)

            -- Status badge (right)
            local status_text = is_enabled and "ON" or "OFF"
            local status_color = is_enabled and self.colors.keybind_active or self.colors.keybind_inactive
            local status_hover_color = is_status_hovered and lighten_color(status_color, 30) or status_color
            self.window:render_rect_filled(status_box_start, status_box_end, status_hover_color, 4.0)

            local status_text_size = self.window:get_text_size(status_text)
            local status_text_x = status_box_start.x + (LAYOUT.keybind_status_width - status_text_size.x) / 2
            local status_text_y = y_offset + (LAYOUT.element_height - 2 - status_text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(status_text_x, status_text_y),
                color.white(255), status_text)

            -- Clear badge
            local clear_bg = is_clear_hovered and lighten_color(self.colors.slider_bg, 20) or self.colors.slider_bg
            self.window:render_rect_filled(clear_box_start, clear_box_end, clear_bg, 4.0)
            self.window:render_rect(clear_box_start, clear_box_end, self.colors.section_border, 4.0, 1.0)
            local clear_text = "Clear"
            local clear_text_size = self.window:get_text_size(clear_text)
            local clear_text_x = clear_box_start.x + (LAYOUT.keybind_clear_width - clear_text_size.x) / 2
            local clear_text_y = y_offset + (LAYOUT.element_height - 2 - clear_text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(clear_text_x, clear_text_y),
                self.colors.text_secondary, clear_text)
            if self.window:is_rect_clicked(clear_box_start, clear_box_end) then
                pcall(function()
                    if element.set_key then
                        element:set_key(999)
                    end
                end)
            end

            -- INPUT HANDLING
            -- Click on Status Badge → Toggle Enable State
            if self.window:is_rect_clicked(status_box_start, status_box_end) then
                pcall(function()
                    if element.set_toggle_state then
                        element:set_toggle_state(not is_enabled)
                    elseif element.set_state then
                        element:set_state(not is_enabled)
                    end
                end)
            end

            y_offset = y_offset + LAYOUT.element_height + LAYOUT.element_spacing
        end
    end

    return y_offset + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- CHECKBOX GRID RENDERING (Custom + Interactive)
-- ============================================================================

function RotationSettingsUI:_render_checkbox_grid(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    local columns = section.columns or 2
    local column_width = (content_width - ((columns - 1) * LAYOUT.column_spacing)) / columns

    y_offset = y_offset + LAYOUT.section_padding_top

    local row = 0
    local col = 0

    for i, item in ipairs(section.elements) do
        if item and item.element and self:_is_entry_visible(item) then
            local element = item.element
            local label = item.label or ("Option " .. i)

            local ok_state, is_checked = pcall(function()
                return element:get_state()
            end)
            if not ok_state then
                is_checked = false
            end

            local x_pos = x_start + (col * (column_width + LAYOUT.column_spacing))

            -- Checkbox rectangle
            local checkbox_start = vec2.new(x_pos, y_offset)
            local checkbox_end = vec2.new(x_pos + LAYOUT.checkbox_size, y_offset + LAYOUT.checkbox_size)

            -- Hover state
            local is_hovered = self.window:is_mouse_hovering_rect(checkbox_start, checkbox_end)

            -- Custom Rendering
            local checkbox_color = is_checked and self.colors.checkbox_active or self.colors.checkbox_inactive
            if is_hovered then
                checkbox_color = lighten_color(checkbox_color, 30)
            end

            self.window:render_rect_filled(checkbox_start, checkbox_end, checkbox_color, 4.0)
            local cb_border = is_hovered and lighten_color(self.colors.checkbox_border, 30) or self.colors.checkbox_border
            self.window:render_rect(checkbox_start, checkbox_end, cb_border, 4.0, 1.0)

            -- Checkmark if enabled
            if is_checked then
                local check_padding = 4
                local check_start = vec2.new(x_pos + check_padding, y_offset + check_padding)
                local check_end = vec2.new(x_pos + LAYOUT.checkbox_size - check_padding, y_offset + LAYOUT.checkbox_size - check_padding)
                self.window:render_rect_filled(check_start, check_end, color.white(255), 2.0)
            end

            -- Label
            local label_x = x_pos + LAYOUT.checkbox_size + 8
            local label_y = y_offset + (LAYOUT.checkbox_size - self.window:get_text_size(label).y) / 2
            local label_color = is_checked and self.colors.text_primary or self.colors.text_secondary
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(label_x, label_y),
                label_color, label)

            -- INPUT HANDLING
            -- Click → Toggle
            local row_click_start = vec2.new(x_pos, y_offset)
            local row_click_end = vec2.new(x_pos + column_width, y_offset + LAYOUT.checkbox_size)
            self.window:is_mouse_hovering_rect_block_movement(row_click_start, row_click_end)
            if self.window:is_mouse_hovering_rect(row_click_start, row_click_end) and item.tooltip then
                self._tooltip = item.tooltip
            end
            if self.window:is_rect_clicked(row_click_start, row_click_end) then
                pcall(function()
                    if element.set then
                        element:set(not is_checked)
                    elseif element.set_state then
                        element:set_state(not is_checked)
                    end
                end)
            end

            col = col + 1
            if col >= columns then
                col = 0
                row = row + 1
                y_offset = y_offset + LAYOUT.element_height + LAYOUT.element_spacing
            end
        end
    end

    if col > 0 then
        y_offset = y_offset + LAYOUT.element_height + LAYOUT.element_spacing
    end

    return y_offset + LAYOUT.section_padding_bottom
end

function RotationSettingsUI:_is_entry_visible(entry)
    if not entry or not entry.visible_when then
        return true
    end
    local ok, result = pcall(entry.visible_when)
    if not ok then
        return false
    end
    return result == true
end

function RotationSettingsUI:_get_slider_bounds(element)
    if not element then
        return 0, 100
    end

    local function normalize_number(value, fallback)
        if type(value) == "number" then
            return value
        end
        if type(value) == "string" then
            local parsed = tonumber(value)
            if parsed then
                return parsed
            end
        end
        if type(value) == "table" then
            if value.min then
                return normalize_number(value.min, fallback)
            end
            if value.max then
                return normalize_number(value.max, fallback)
            end
        end
        return fallback
    end

    local ok_min, min_from_api = pcall(function()
        if element.get_min then
            return element:get_min()
        end
        return nil
    end)
    local ok_max, max_from_api = pcall(function()
        if element.get_max then
            return element:get_max()
        end
        return nil
    end)

    local min_value = ok_min and normalize_number(min_from_api, 0) or 0
    local max_value = ok_max and normalize_number(max_from_api, 100) or 100

    if type(min_value) ~= "number" then
        min_value = 0
    end
    if type(max_value) ~= "number" then
        max_value = min_value
    end

    if max_value < min_value then
        max_value = min_value
    end

    if ok_min and ok_max then
        return min_value, max_value
    end

    local ok_bounds, bounds = pcall(function()
        if element.get_widget_bounds then
            return element:get_widget_bounds()
        end
        return nil
    end)

    if ok_bounds and bounds then
        local normalized_min = normalize_number(bounds.min or bounds.min_value, 0)
        local normalized_max = normalize_number(bounds.max or bounds.max_value, 100)
        if type(normalized_min) ~= "number" then
            normalized_min = 0
        end
        if type(normalized_max) ~= "number" then
            normalized_max = normalized_min
        end
        if normalized_max < normalized_min then
            normalized_max = normalized_min
        end
        return normalized_min, normalized_max
    end

    return 0, 100
end

function RotationSettingsUI:_apply_active_slider_from_mouse()
    if not self._active_slider or not self.window then
        return
    end

    local slider = self._active_slider
    if not slider.bar_width or slider.bar_width <= 0 or slider.min_value == slider.max_value then
        return
    end

    local mouse_pos = self:_get_window_local_mouse_pos(slider.mouse_space)
    if not mouse_pos then
        return
    end

    slider.last_mouse_pos = vec2.new(mouse_pos.x, mouse_pos.y)

    local local_mouse_x = mouse_pos.x - slider.bar_x_start
    local clamped_x = math.max(0, math.min(slider.bar_width, local_mouse_x))
    local progress = clamped_x / slider.bar_width
    local new_value = slider.min_value + (slider.max_value - slider.min_value) * progress
    local rounded_value = math.floor(new_value + 0.5)
    local clamped_value = math.max(slider.min_value, math.min(slider.max_value, rounded_value))

    pcall(function()
        slider.element:set(clamped_value)
    end)
end

function RotationSettingsUI:_start_key_capture(element, label)
    if not element then
        return
    end

    if self.window then
        self.window:set_focus()
        self.window:block_input_capture()
    end

    self._active_key_capture = {
        element = element,
        label = label,
        wait_for_release = true
    }
end

function RotationSettingsUI:_process_key_capture_input()
    if not self._active_key_capture then
        return
    end

    if self._active_key_capture.wait_for_release then
        if not is_mouse_pressed_left(self.window) then
            self._active_key_capture.wait_for_release = false
        end
        return
    end

    if self.window then
        -- Allow binding mouse buttons except LMB/RMB.
        -- Map window button index -> Windows VK code.
        local mouse_vk_by_button_index = {
            [0] = 1, -- LMB
            [1] = 2, -- RMB
            [2] = 4, -- MMB
            [3] = 5, -- Mouse4 (XBUTTON1)
            [4] = 6  -- Mouse5 (XBUTTON2)
        }

        for button_index, vk_code in pairs(mouse_vk_by_button_index) do
            if button_index ~= 0 and button_index ~= 1 then
                if self.window:is_mouse_button_clicked(button_index) then
                    pcall(function()
                        if self._active_key_capture and self._active_key_capture.element and self._active_key_capture.element.set_key then
                            self._active_key_capture.element:set_key(vk_code)
                        end
                    end)
                    self._active_key_capture = nil
                    return
                end
            end
        end
    end

    for key_code = 1, 255 do
        if key_code ~= 1 and key_code ~= 2 then
            if core.input.is_key_pressed(key_code) then
                if key_code == 27 then
                    self._active_key_capture = nil
                    return
                end

                pcall(function()
                    if key_code == 8 or key_code == 46 then
                        if self._active_key_capture.element.set_key then
                            self._active_key_capture.element:set_key(999)
                        end
                    elseif self._active_key_capture.element.set_key then
                        self._active_key_capture.element:set_key(key_code)
                    end
                end)

                self._active_key_capture = nil
                return
            end
        end
    end
end

function RotationSettingsUI:_render_key_capture_prompt()
    if not self._active_key_capture or not self.window then
        return
    end

    local prompt_label = self._active_key_capture.label or "keybind"
    local prompt_text = string.format("Press a key for %s (Esc to cancel, Del to clear)", prompt_label)
    local window_size = self.window:get_size()
    local text_size = self.window:get_text_size(prompt_text)
    local prompt_pos = vec2.new(LAYOUT.padding_side, window_size.y - LAYOUT.padding_bottom - text_size.y - 4)
    self.window:render_text(enums.window_enums.font_id.FONT_SMALL, prompt_pos, self.colors.secondary_accent, prompt_text)
end

-- ============================================================================
-- SLIDER LIST RENDERING (Custom + Interactive)
-- ============================================================================

function RotationSettingsUI:_render_slider_list(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local label_width = 180
    local bar_width = content_width - label_width - 60

    for i, item in ipairs(section.elements) do
        if item and item.element and self:_is_entry_visible(item) then
            local element = item.element
            local label = item.label or ("Slider " .. i)
            local suffix = item.suffix or ""

            local ok_val, value = pcall(function()
                return element:get()
            end)
            if not ok_val or value == nil then
                value = 0
            end

            local min_value, max_value
            if item.min and item.max then
                min_value, max_value = item.min, item.max
            else
                min_value, max_value = self:_get_slider_bounds(element)
            end
            if max_value < min_value then
                max_value = min_value
            end

            if item.use_stepper == true then
                -- Stepper mode: [-] value [+] buttons
                local row_h = 20
                local btn_w = 24
                local gap = 4
                local value_w = 86
                local step = tonumber(item.step) or 1
                local decimals = item.decimals
                if type(decimals) ~= "number" then
                    decimals = infer_decimals(step)
                end
                if decimals < 0 then decimals = 0 end
                if decimals > 4 then decimals = 4 end

                local is_integer = item.integer == true
                    or (math.floor(min_value) == min_value and math.floor(max_value) == max_value and math.floor(step) == step and decimals == 0)

                local row_hover_start = vec2.new(x_start, y_offset)
                local row_hover_end = vec2.new(x_start + content_width, y_offset + row_h)
                if self.window:is_mouse_hovering_rect(row_hover_start, row_hover_end) and item.tooltip then
                    self._tooltip = item.tooltip
                end

                self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x_start, y_offset + 2), self.colors.text_primary, label)

                local bx = x_start + content_width - (btn_w + gap + value_w + gap + btn_w)

                local function draw_step_button(button_x, button_label)
                    local start = vec2.new(button_x, y_offset)
                    local finish = vec2.new(button_x + btn_w, y_offset + row_h)
                    local hovered = self.window:is_mouse_hovering_rect(start, finish)
                    self.window:is_mouse_hovering_rect_block_movement(start, finish)
                    local bg = hovered and lighten_color(self.colors.primary_accent, 15) or self.colors.primary_accent
                    self.window:render_rect_filled(start, finish, bg, 4.0)
                    local txt = self.window:get_text_size(button_label)
                    self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(button_x + (btn_w - txt.x) / 2, y_offset + (row_h - txt.y) / 2),
                        self.colors.text_primary, button_label)
                    return hovered and self.window:is_rect_clicked(start, finish)
                end

                local minus_clicked = draw_step_button(bx, "-")

                local value_text
                if decimals > 0 then
                    value_text = string.format("%." .. tostring(decimals) .. "f%s", tonumber(value) or 0, suffix)
                else
                    value_text = string.format("%d%s", math.floor((tonumber(value) or 0) + 0.5), suffix)
                end
                local tx = bx + btn_w + gap + ((value_w - self.window:get_text_size(value_text).x) / 2)
                self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(tx, y_offset + 2), self.colors.text_secondary, value_text)

                local plus_x = bx + btn_w + gap + value_w + gap
                local plus_clicked = draw_step_button(plus_x, "+")

                if minus_clicked or plus_clicked then
                    local raw_new = (tonumber(value) or 0) + (plus_clicked and step or -step)
                    local clamped = clamp_number(raw_new, min_value, max_value)
                    if is_integer then
                        clamped = math.floor(clamped + 0.5)
                    elseif decimals > 0 then
                        local mult = 10 ^ decimals
                        clamped = math.floor((clamped * mult) + 0.5) / mult
                    end
                    pcall(function()
                        if element.set then element:set(clamped) end
                    end)
                end

                y_offset = y_offset + row_h + 4
            else
            -- Standard drag slider
            local bar_x_start = x_start + label_width
            local bar_start = vec2.new(bar_x_start, y_offset)
            local bar_end = vec2.new(bar_x_start + bar_width, y_offset + LAYOUT.slider_bar_height)

            -- Hover/Press state
            local is_hovered = self.window:is_mouse_hovering_rect(bar_start, bar_end)
            self.window:is_mouse_hovering_rect_block_movement(bar_start, bar_end)

            -- Tooltip on row hover
            local row_hover_start = vec2.new(x_start, y_offset)
            local row_hover_end = vec2.new(x_start + content_width, y_offset + LAYOUT.slider_bar_height)
            if self.window:is_mouse_hovering_rect(row_hover_start, row_hover_end) and item.tooltip then
                self._tooltip = item.tooltip
            end

            -- Custom Rendering - Label
            local label_y = y_offset + (LAYOUT.slider_bar_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, label_y),
                self.colors.text_primary, label)

            -- Progress bar background
            local bg_color = is_hovered and lighten_color(self.colors.slider_bg, 15) or self.colors.slider_bg
            self.window:render_rect_filled(bar_start, bar_end, bg_color, 4.0)

            -- Progress bar fill
            local fill_progress = max_value > min_value and ((value - min_value) / (max_value - min_value)) or 0
            local clamped_progress = math.max(0, math.min(1, fill_progress))
            local fill_width = bar_width * clamped_progress
            local fill_end = vec2.new(bar_x_start + fill_width, y_offset + LAYOUT.slider_bar_height)
            self.window:render_rect_filled(bar_start, fill_end, self.colors.slider_fill, 4.0)

            -- Progress bar border
            local is_active_slider = self._active_slider and self._active_slider.element == element
            local border_color = is_active_slider and self.colors.primary_accent or self.colors.section_border
            self.window:render_rect(bar_start, bar_end, border_color, 4.0, 1.0)

            -- Value text
            local value_text = string.format("%d%s", value, suffix)
            local value_x = bar_x_start + bar_width + 10
            local value_y = y_offset + (LAYOUT.slider_bar_height - self.window:get_text_size(value_text).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(value_x, value_y),
                self.colors.text_secondary, value_text)

            -- INPUT HANDLING
            if is_hovered and is_mouse_clicked_left(self.window) then
                self.window:block_input_capture()

                local raw_pos = select(1, self:_get_window_local_mouse_pos("raw"))
                local adjusted_pos = select(1, self:_get_window_local_mouse_pos("adjusted"))

                local function score(pos)
                    if not pos then
                        return 1e30
                    end
                    local local_x = pos.x - bar_x_start
                    local dx = 0
                    if local_x < 0 then
                        dx = -local_x
                    elseif local_x > bar_width then
                        dx = local_x - bar_width
                    end

                    local dy = 0
                    if pos.y < bar_start.y then
                        dy = bar_start.y - pos.y
                    elseif pos.y > bar_end.y then
                        dy = pos.y - bar_end.y
                    end

                    return (dx * dx) + (dy * dy)
                end

                local use_space = "raw"
                local chosen_pos = raw_pos
                if score(adjusted_pos) < score(raw_pos) then
                    use_space = "adjusted"
                    chosen_pos = adjusted_pos
                end

                self._active_slider = {
                    element = element,
                    min_value = min_value,
                    max_value = max_value,
                    bar_x_start = bar_x_start,
                    bar_width = bar_width,
                    last_mouse_pos = chosen_pos,
                    mouse_space = use_space
                }
                self:_apply_active_slider_from_mouse()
            end

            y_offset = y_offset + LAYOUT.slider_bar_height + LAYOUT.element_spacing + 4
            end -- end else (stepper vs drag slider)
        end
    end

    if self._active_slider then
        if is_mouse_pressed_left(self.window) then
            self.window:block_input_capture()
            self:_apply_active_slider_from_mouse()
        else
            self._active_slider = nil
        end
    end

    return y_offset + LAYOUT.section_padding_bottom
end

function RotationSettingsUI:_render_combo_list(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local label_width = 180
    local value_box_width = 160

    for i, item in ipairs(section.elements) do
        if item and item.element and self:_is_entry_visible(item) then
            local element = item.element
            local label = item.label or ("Option " .. i)
            local suffix = item.suffix or ""

            local ok_val, current_index = pcall(function()
                return element:get()
            end)
            if not ok_val or current_index == nil then
                current_index = 1
            end

            local options = item.options or {}
            local option_text = options[current_index] or tostring(current_index)
            if #suffix > 0 then
                option_text = option_text .. suffix
            end

            local box_start = vec2.new(x_start + label_width, y_offset)
            local box_end = vec2.new(x_start + label_width + value_box_width, y_offset + LAYOUT.slider_bar_height)

            local is_hovered = self.window:is_mouse_hovering_rect(box_start, box_end)
            self.window:is_mouse_hovering_rect_block_movement(box_start, box_end)

            -- Tooltip on row hover
            local combo_row_start = vec2.new(x_start, y_offset)
            local combo_row_end = vec2.new(x_start + content_width, y_offset + LAYOUT.slider_bar_height)
            if self.window:is_mouse_hovering_rect(combo_row_start, combo_row_end) and item.tooltip then
                self._tooltip = item.tooltip
            end

            local label_y = y_offset + (LAYOUT.slider_bar_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, label_y),
                self.colors.text_primary, label)

            local bg_color = is_hovered and lighten_color(self.colors.slider_bg, 15) or self.colors.slider_bg
            self.window:render_rect_filled(box_start, box_end, bg_color, 4.0)
            local border_color = is_hovered and self.colors.primary_accent or self.colors.section_border
            self.window:render_rect(box_start, box_end, border_color, 4.0, 1.0)

            local value_text_size = self.window:get_text_size(option_text)
            local value_x = box_start.x + (value_box_width - value_text_size.x) / 2
            local value_y = y_offset + (LAYOUT.slider_bar_height - value_text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(value_x, value_y),
                self.colors.text_secondary, option_text)

            if self.window:is_rect_clicked(box_start, box_end) then
                if #options > 0 then
                    local next_index = ((current_index - 1 + 1) % #options) + 1
                    pcall(function()
                        if element.set then
                            element:set(next_index)
                        end
                    end)
                end
            end

            y_offset = y_offset + LAYOUT.slider_bar_height + LAYOUT.element_spacing + 4
        end
    end

    return y_offset + LAYOUT.section_padding_bottom
end

function RotationSettingsUI:_render_segmented_control(group, y_offset)
    local element = group.element
    local options = group.options
    if not element or not options or #options == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local ok_val, current_index = pcall(function() return element:get() end)
    if not ok_val or current_index == nil then current_index = 1 end

    local height = LAYOUT.element_height
    local seg_width = content_width / #options

    -- Tooltip on hover over entire control
    local ctrl_start = vec2.new(x_start, y_offset)
    local ctrl_end = vec2.new(x_start + content_width, y_offset + height)
    if self.window:is_mouse_hovering_rect(ctrl_start, ctrl_end) and group.tooltip then
        self._tooltip = group.tooltip
    end

    -- Background pill
    self.window:render_rect_filled(ctrl_start, ctrl_end, self.colors.slider_bg, 8.0)

    for i, option_name in ipairs(options) do
        local seg_x = x_start + (i - 1) * seg_width
        local seg_start = vec2.new(seg_x, y_offset)
        local seg_end = vec2.new(seg_x + seg_width, y_offset + height)
        local is_selected = (i == current_index)
        local is_hovered = self.window:is_mouse_hovering_rect(seg_start, seg_end)
        self.window:is_mouse_hovering_rect_block_movement(seg_start, seg_end)

        if is_selected then
            -- Selected: accent blue pill on top, inset 2px for floating effect
            local sel_start = vec2.new(seg_x + 2, y_offset + 2)
            local sel_end = vec2.new(seg_x + seg_width - 2, y_offset + height - 2)
            self.window:render_rect_filled(sel_start, sel_end, self.colors.primary_accent, 6.0)
        elseif is_hovered then
            -- Hovered unselected: subtle lighten
            local hov_start = vec2.new(seg_x + 1, y_offset + 1)
            local hov_end = vec2.new(seg_x + seg_width - 1, y_offset + height - 1)
            self.window:render_rect_filled(hov_start, hov_end, lighten_color(self.colors.slider_bg, 15), 6.0)
        end

        -- Divider: 1px line between unselected adjacent segments
        if i < #options then
            local next_selected = ((i + 1) == current_index)
            if not is_selected and not next_selected then
                local div_x = seg_x + seg_width
                local div_start = vec2.new(div_x, y_offset + 6)
                local div_end = vec2.new(div_x + 1, y_offset + height - 6)
                self.window:render_rect_filled(div_start, div_end, self.colors.section_border, 0)
            end
        end

        -- Centered text
        local text_color = is_selected and self.colors.text_primary or self.colors.text_secondary
        local text_size = self.window:get_text_size(option_name)
        local text_x = seg_x + (seg_width - text_size.x) / 2
        local text_y = y_offset + (height - text_size.y) / 2
        self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(text_x, text_y), text_color, option_name)

        -- Click
        if self.window:is_rect_clicked(seg_start, seg_end) and not is_selected then
            pcall(function()
                if element.set then element:set(i) end
            end)
        end
    end

    return y_offset + height + LAYOUT.element_spacing + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- OVERLAY QUEUE (Phase 1)
-- ============================================================================

function RotationSettingsUI:_queue_overlay(draw_fn)
    if type(draw_fn) == "function" then
        self._overlay_queue[#self._overlay_queue + 1] = draw_fn
    end
end

function RotationSettingsUI:_flush_overlays()
    for i = 1, #self._overlay_queue do
        pcall(self._overlay_queue[i])
    end
    self._overlay_queue = {}
end

-- ============================================================================
-- PROGRESS BAR LIST RENDERING (Phase 2)
-- ============================================================================

function RotationSettingsUI:_render_progress_bar_list(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local label_width = 180
    local bar_width = content_width - label_width - 60

    for i, item in ipairs(section.elements) do
        if item and self:_is_entry_visible(item) then
            local label = item.label or ("Bar " .. i)
            local value_fn = item.value_fn
            local value = 0
            if type(value_fn) == "function" then
                local ok_v, v = pcall(value_fn)
                if ok_v and type(v) == "number" then
                    value = math.max(0, math.min(1, v))
                end
            end

            local bar_color = item.color or self.colors.primary_accent
            local track_color = self.colors.progress_track or self.colors.slider_bg
            local format_fn = item.format_fn or function(v) return math.floor(v * 100) .. "%" end

            local bar_x_start = x_start + label_width
            local bar_y_top = y_offset
            local bar_y_bottom = y_offset + LAYOUT.progress_bar_height

            -- Tooltip on row hover
            local row_start = vec2.new(x_start, bar_y_top)
            local row_end = vec2.new(x_start + content_width, bar_y_bottom)
            if self.window:is_mouse_hovering_rect(row_start, row_end) and item.tooltip then
                self._tooltip = item.tooltip
            end

            -- Label
            local label_y = bar_y_top + (LAYOUT.progress_bar_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x_start, label_y), self.colors.text_primary, label)

            -- Track background
            local track_start = vec2.new(bar_x_start, bar_y_top)
            local track_end = vec2.new(bar_x_start + bar_width, bar_y_bottom)
            self.window:render_rect_filled(track_start, track_end, track_color, LAYOUT.progress_bar_corner_radius)

            -- Fill
            local fill_width = bar_width * value
            if fill_width > 0 then
                local fill_end = vec2.new(bar_x_start + fill_width, bar_y_bottom)
                self.window:render_rect_filled(track_start, fill_end, bar_color, LAYOUT.progress_bar_corner_radius)
            end

            -- Value text
            local ok_fmt, value_text = pcall(format_fn, value)
            if not ok_fmt then value_text = math.floor(value * 100) .. "%" end
            local value_x = bar_x_start + bar_width + 10
            local value_y = bar_y_top + (LAYOUT.progress_bar_height - self.window:get_text_size(value_text).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(value_x, value_y), self.colors.text_secondary, value_text)

            y_offset = bar_y_bottom + LAYOUT.element_spacing + LAYOUT.progress_bar_label_gap
        end
    end

    return y_offset + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- DROPDOWN LIST RENDERING (Phase 4)
-- ============================================================================

function RotationSettingsUI:_render_dropdown_list(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local label_width = 180
    local dropdown_width = math.max(LAYOUT.dropdown_min_width, content_width - label_width - 20)

    for i, item in ipairs(section.elements) do
        if item and self:_is_entry_visible(item) then
            local label = item.label or ("Dropdown " .. i)
            local dd_id = item.id or (section.id .. "_dd_" .. i)
            local options = item.options or {}
            local selected_fn = item.selected_fn
            local on_change = item.on_change

            local current_value = nil
            if type(selected_fn) == "function" then
                local ok_s, s = pcall(selected_fn)
                if ok_s then current_value = s end
            end

            -- Find selected label
            local selected_label = tostring(current_value or "")
            for _, opt in ipairs(options) do
                if type(opt) == "table" and opt.value == current_value then
                    selected_label = opt.label or tostring(opt.value)
                    break
                end
            end

            local box_x = x_start + label_width
            local box_start = vec2.new(box_x, y_offset)
            local box_end = vec2.new(box_x + dropdown_width, y_offset + LAYOUT.element_height)

            local is_open = self._dropdown_open_id == dd_id
            local is_hovered = self.window:is_mouse_hovering_rect(box_start, box_end)
            self.window:is_mouse_hovering_rect_block_movement(box_start, box_end)

            -- Tooltip
            local row_start = vec2.new(x_start, y_offset)
            local row_end = vec2.new(x_start + content_width, y_offset + LAYOUT.element_height)
            if self.window:is_mouse_hovering_rect(row_start, row_end) and item.tooltip then
                self._tooltip = item.tooltip
            end

            -- Label
            local label_y = y_offset + (LAYOUT.element_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x_start, label_y), self.colors.text_primary, label)

            -- Dropdown button
            local bg = is_hovered and lighten_color(self.colors.slider_bg, 15) or self.colors.slider_bg
            local border = is_open and self.colors.primary_accent or (is_hovered and self.colors.primary_accent or self.colors.section_border)
            self.window:render_rect_filled(box_start, box_end, bg, 4.0)
            self.window:render_rect(box_start, box_end, border, 4.0, 1.0)

            -- Selected text
            local sel_text_size = self.window:get_text_size(selected_label)
            local sel_x = box_x + 8
            local sel_y = y_offset + (LAYOUT.element_height - sel_text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(sel_x, sel_y), self.colors.text_primary, selected_label)

            -- Chevron (small triangle)
            local chev_x = box_x + dropdown_width - 16
            local chev_y = y_offset + LAYOUT.element_height / 2
            local chev_size = 4
            if is_open then
                -- Up chevron
                self.window:render_rect_filled(
                    vec2.new(chev_x - chev_size, chev_y + 1),
                    vec2.new(chev_x + chev_size, chev_y + 3),
                    self.colors.text_secondary, 0)
            else
                -- Down chevron
                self.window:render_rect_filled(
                    vec2.new(chev_x - chev_size, chev_y - 1),
                    vec2.new(chev_x + chev_size, chev_y + 1),
                    self.colors.text_secondary, 0)
            end

            -- Toggle open on click
            if self.window:is_rect_clicked(box_start, box_end) then
                if is_open then
                    self._dropdown_open_id = nil
                else
                    self._dropdown_open_id = dd_id
                    self._dropdown_scroll[dd_id] = self._dropdown_scroll[dd_id] or 0
                end
            end

            -- Render dropdown overlay when open
            if is_open and #options > 0 then
                local vis_count = math.min(#options, LAYOUT.dropdown_max_visible)
                local dd_height = vis_count * LAYOUT.dropdown_item_height
                local dd_top = y_offset + LAYOUT.element_height + 2
                local dd_scroll = self._dropdown_scroll[dd_id] or 0
                local max_dd_scroll = math.max(0, (#options - vis_count) * LAYOUT.dropdown_item_height)
                dd_scroll = math.max(0, math.min(dd_scroll, max_dd_scroll))
                self._dropdown_scroll[dd_id] = dd_scroll

                -- Capture vars for overlay closure
                local cap_box_x = box_x
                local cap_dd_width = dropdown_width
                local cap_dd_top = dd_top
                local cap_dd_height = dd_height
                local cap_options = options
                local cap_current = current_value
                local cap_on_change = on_change
                local cap_dd_scroll = dd_scroll

                self:_queue_overlay(function()
                    local dd_start = vec2.new(cap_box_x, cap_dd_top)
                    local dd_end = vec2.new(cap_box_x + cap_dd_width, cap_dd_top + cap_dd_height)

                    -- Background
                    self.window:render_rect_filled(dd_start, dd_end,
                        self.colors.bg_tooltip or color.new(28, 28, 30, 240), 6.0)
                    self.window:render_rect(dd_start, dd_end,
                        self.colors.section_border, 6.0, 1.0)

                    -- Clip to dropdown bounds
                    self.window:push_clip_rect(dd_start, dd_end, true)

                    local item_y = cap_dd_top - cap_dd_scroll
                    for _, opt in ipairs(cap_options) do
                        local opt_value = type(opt) == "table" and opt.value or opt
                        local opt_label = type(opt) == "table" and (opt.label or tostring(opt.value)) or tostring(opt)

                        local item_start = vec2.new(cap_box_x, item_y)
                        local item_end = vec2.new(cap_box_x + cap_dd_width, item_y + LAYOUT.dropdown_item_height)

                        if item_y + LAYOUT.dropdown_item_height > cap_dd_top and item_y < cap_dd_top + cap_dd_height then
                            local is_selected = (opt_value == cap_current)
                            local item_hovered = self.window:is_mouse_hovering_rect(item_start, item_end)
                            self.window:is_mouse_hovering_rect_block_movement(item_start, item_end)

                            if item_hovered then
                                self.window:render_rect_filled(item_start, item_end,
                                    self.colors.dropdown_hover or color.new(10, 132, 255, 40), 0)
                            end
                            if is_selected then
                                self.window:render_rect_filled(item_start, item_end,
                                    self.colors.listbox_selected or color.new(10, 132, 255, 50), 0)
                            end

                            local opt_text_size = self.window:get_text_size(opt_label)
                            local opt_text_y = item_y + (LAYOUT.dropdown_item_height - opt_text_size.y) / 2
                            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                                vec2.new(cap_box_x + 8, opt_text_y),
                                is_selected and self.colors.primary_accent or self.colors.text_primary, opt_label)

                            if self.window:is_rect_clicked(item_start, item_end) then
                                if type(cap_on_change) == "function" then
                                    pcall(cap_on_change, opt_value)
                                end
                                self._dropdown_open_id = nil
                            end
                        end

                        item_y = item_y + LAYOUT.dropdown_item_height
                    end

                    self.window:pop_clip_rect()

                    -- Scroll dropdown with mouse wheel when hovering
                    if self.window:is_mouse_hovering_rect(dd_start, dd_end) then
                        self._listbox_consumed_scroll = true
                        self.window:block_input_capture()
                    end

                    -- Close if clicked outside
                    if is_mouse_clicked_left(self.window) and not self.window:is_mouse_hovering_rect(dd_start, dd_end) then
                        -- Check we aren't clicking the toggle button itself
                        local toggle_start = vec2.new(cap_box_x, cap_dd_top - LAYOUT.element_height - 2)
                        local toggle_end = vec2.new(cap_box_x + cap_dd_width, cap_dd_top - 2)
                        if not self.window:is_mouse_hovering_rect(toggle_start, toggle_end) then
                            self._dropdown_open_id = nil
                        end
                    end
                end)
            end

            y_offset = y_offset + LAYOUT.element_height + LAYOUT.element_spacing + 4
        end
    end

    return y_offset + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- TEXT INPUT LIST RENDERING (Phase 5)
-- ============================================================================

-- Virtual key code → character mapping (US keyboard layout)
local VK_CHAR_MAP = {}
-- A-Z
for vk = 65, 90 do VK_CHAR_MAP[vk] = { lower = string.char(vk + 32), upper = string.char(vk) } end
-- 0-9 and shift symbols
local DIGIT_SHIFT = { [48]=")", [49]="!", [50]="@", [51]="#", [52]="$", [53]="%", [54]="^", [55]="&", [56]="*", [57]="(" }
for vk = 48, 57 do VK_CHAR_MAP[vk] = { lower = string.char(vk), upper = DIGIT_SHIFT[vk] or string.char(vk) } end
-- Common symbols
VK_CHAR_MAP[32]  = { lower = " ",  upper = " " }   -- Space
VK_CHAR_MAP[190] = { lower = ".",  upper = ">" }   -- Period
VK_CHAR_MAP[188] = { lower = ",",  upper = "<" }   -- Comma
VK_CHAR_MAP[191] = { lower = "/",  upper = "?" }   -- Slash
VK_CHAR_MAP[186] = { lower = ";",  upper = ":" }   -- Semicolon
VK_CHAR_MAP[222] = { lower = "'",  upper = "\"" }  -- Quote
VK_CHAR_MAP[219] = { lower = "[",  upper = "{" }   -- Left bracket
VK_CHAR_MAP[221] = { lower = "]",  upper = "}" }   -- Right bracket
VK_CHAR_MAP[220] = { lower = "\\", upper = "|" }   -- Backslash
VK_CHAR_MAP[189] = { lower = "-",  upper = "_" }   -- Minus
VK_CHAR_MAP[187] = { lower = "=",  upper = "+" }   -- Equals
VK_CHAR_MAP[192] = { lower = "`",  upper = "~" }   -- Backtick

function RotationSettingsUI:_render_text_input_list(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local label_width = 180
    local input_width = content_width - label_width - 10

    -- Update blink timer
    local now = (core and core.time and core.time()) or 0
    self._text_input_blink = now

    local any_input_clicked = false

    for i, item in ipairs(section.elements) do
        if item and self:_is_entry_visible(item) then
            local label = item.label or ("Input " .. i)
            local input_id = item.id or (section.id .. "_input_" .. i)
            local value_fn = item.value_fn
            local on_change = item.on_change
            local placeholder = item.placeholder or ""
            local max_length = item.max_length or 256

            -- Sync buffer from value_fn if not focused
            local is_focused = self._text_input_focus_id == input_id
            if not is_focused then
                local current = ""
                if type(value_fn) == "function" then
                    local ok_v, v = pcall(value_fn)
                    if ok_v and v ~= nil then current = tostring(v) end
                end
                self._text_input_buffers[input_id] = current
                self._text_input_cursor[input_id] = #current
            end

            local buffer = self._text_input_buffers[input_id] or ""
            local cursor_pos = self._text_input_cursor[input_id] or #buffer

            local input_x = x_start + label_width
            local box_start = vec2.new(input_x, y_offset)
            local box_end = vec2.new(input_x + input_width, y_offset + LAYOUT.text_input_height)

            local is_hovered = self.window:is_mouse_hovering_rect(box_start, box_end)
            self.window:is_mouse_hovering_rect_block_movement(box_start, box_end)

            -- Tooltip
            if is_hovered and item.tooltip then
                self._tooltip = item.tooltip
            end

            -- Label
            local label_y = y_offset + (LAYOUT.text_input_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x_start, label_y), self.colors.text_primary, label)

            -- Input box
            local bg_color = is_focused and (self.colors.bg_input_focused or self.colors.slider_bg) or (self.colors.bg_input or self.colors.slider_bg)
            local border_color = is_focused and (self.colors.border_input_focused or self.colors.primary_accent) or (self.colors.border_input or self.colors.section_border)
            self.window:render_rect_filled(box_start, box_end, bg_color, 4.0)
            self.window:render_rect(box_start, box_end, border_color, 4.0, 1.0)

            -- Text content or placeholder
            local display_text = #buffer > 0 and buffer or placeholder
            local text_color = #buffer > 0 and self.colors.text_primary or (self.colors.text_placeholder or self.colors.text_disabled)
            local text_y = y_offset + (LAYOUT.text_input_height - self.window:get_text_size(display_text).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(input_x + LAYOUT.text_input_padding, text_y), text_color, display_text)

            -- Blinking cursor when focused
            if is_focused then
                local blink_on = (math.floor(now * 2) % 2) == 0
                if blink_on then
                    local before_cursor = string.sub(buffer, 1, cursor_pos)
                    local cursor_x = input_x + LAYOUT.text_input_padding + self.window:get_text_size(before_cursor).x
                    local cursor_top = y_offset + 4
                    local cursor_bottom = y_offset + LAYOUT.text_input_height - 4
                    self.window:render_rect_filled(
                        vec2.new(cursor_x, cursor_top),
                        vec2.new(cursor_x + 1, cursor_bottom),
                        self.colors.text_primary, 0)
                end
            end

            -- Click to focus
            if self.window:is_rect_clicked(box_start, box_end) then
                self._text_input_focus_id = input_id
                self._text_input_cursor[input_id] = #buffer
                self.window:block_input_capture()
                any_input_clicked = true
            end

            -- Handle keyboard input when focused
            if is_focused then
                self.window:block_input_capture()
                local shift_held = core.input.is_input_bit_active(16)

                -- Sample all tracked keys once this frame
                local curr = {}
                local control_vks = {27, 13, 8, 46, 37, 39, 36, 35}
                for _, vk in ipairs(control_vks) do
                    curr[vk] = core.input.is_key_pressed(vk) or false
                end
                for vk, _ in pairs(VK_CHAR_MAP) do
                    curr[vk] = core.input.is_key_pressed(vk) or false
                end

                local prev = self._text_input_prev_keys
                local function key_edge(vk)
                    return curr[vk] and not prev[vk]
                end

                -- Escape → unfocus
                if key_edge(27) then
                    -- Revert to original value
                    self._text_input_focus_id = nil
                -- Enter → commit
                elseif key_edge(13) then
                    if type(on_change) == "function" then
                        pcall(on_change, buffer)
                    end
                    self._text_input_focus_id = nil
                -- Backspace
                elseif key_edge(8) then
                    if cursor_pos > 0 then
                        buffer = string.sub(buffer, 1, cursor_pos - 1) .. string.sub(buffer, cursor_pos + 1)
                        cursor_pos = cursor_pos - 1
                    end
                -- Delete
                elseif key_edge(46) then
                    if cursor_pos < #buffer then
                        buffer = string.sub(buffer, 1, cursor_pos) .. string.sub(buffer, cursor_pos + 2)
                    end
                -- Left arrow
                elseif key_edge(37) then
                    cursor_pos = math.max(0, cursor_pos - 1)
                -- Right arrow
                elseif key_edge(39) then
                    cursor_pos = math.min(#buffer, cursor_pos + 1)
                -- Home
                elseif key_edge(36) then
                    cursor_pos = 0
                -- End
                elseif key_edge(35) then
                    cursor_pos = #buffer
                else
                    -- Character input
                    for vk, chars in pairs(VK_CHAR_MAP) do
                        if key_edge(vk) then
                            local ch = shift_held and chars.upper or chars.lower
                            if #buffer < max_length then
                                buffer = string.sub(buffer, 1, cursor_pos) .. ch .. string.sub(buffer, cursor_pos + 1)
                                cursor_pos = cursor_pos + 1
                            end
                            break
                        end
                    end
                end

                -- Save current key state as prev for next frame
                self._text_input_prev_keys = curr

                self._text_input_buffers[input_id] = buffer
                self._text_input_cursor[input_id] = cursor_pos
            else
                -- Clear prev key state when not focused
                self._text_input_prev_keys = {}
            end

            y_offset = y_offset + LAYOUT.text_input_height + LAYOUT.element_spacing
        end
    end

    -- Click outside any input → unfocus and commit
    if self._text_input_focus_id and not any_input_clicked and is_mouse_clicked_left(self.window) then
        local focus_id = self._text_input_focus_id
        -- Find the matching item to commit
        for _, item in ipairs(section.elements) do
            local input_id = item.id or ""
            if input_id == focus_id and type(item.on_change) == "function" then
                pcall(item.on_change, self._text_input_buffers[focus_id] or "")
                break
            end
        end
        self._text_input_focus_id = nil
    end

    return y_offset + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- LISTBOX RENDERING (Phase 6)
-- ============================================================================

function RotationSettingsUI:_render_listbox(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    for i, item in ipairs(section.elements) do
        if item and self:_is_entry_visible(item) then
            local lb_id = item.id or ((section.id or "listbox") .. "_lb_" .. i)
            local entries_fn = item.entries_fn
            local on_select = item.on_select
            local visible_rows = item.visible_rows or LAYOUT.listbox_default_rows
            local row_height = item.row_height or LAYOUT.listbox_row_height

            local entries = {}
            if type(entries_fn) == "function" then
                local ok_e, e = pcall(entries_fn)
                if ok_e and type(e) == "table" then entries = e end
            end

            local box_height = visible_rows * row_height
            local box_start = vec2.new(x_start, y_offset)
            local box_end = vec2.new(x_start + content_width, y_offset + box_height)

            -- Background
            self.window:render_rect_filled(box_start, box_end,
                self.colors.bg_input or self.colors.slider_bg, 4.0)
            self.window:render_rect(box_start, box_end,
                self.colors.border_input or self.colors.section_border, 4.0, 1.0)

            -- Scroll state
            local scroll = self._listbox_scroll[lb_id] or 0
            local total_height = #entries * row_height
            local max_scroll = math.max(0, total_height - box_height)
            scroll = math.max(0, math.min(scroll, max_scroll))
            self._listbox_scroll[lb_id] = scroll

            local selected_idx = self._listbox_selected[lb_id]

            -- Check if mouse is over the listbox (for consuming scroll)
            local is_over_listbox = self.window:is_mouse_hovering_rect(box_start, box_end)
            if is_over_listbox then
                self._listbox_consumed_scroll = true
                self._listbox_hover_id = lb_id
                self.window:is_mouse_hovering_rect_block_movement(box_start, box_end)
            end

            -- Clip content
            self.window:push_clip_rect(box_start, box_end, true)

            local item_y = y_offset - scroll
            for entry_i, entry in ipairs(entries) do
                local entry_top = item_y
                local entry_bottom = item_y + row_height

                if entry_bottom > y_offset and entry_top < y_offset + box_height then
                    local entry_start = vec2.new(x_start, entry_top)
                    local entry_end = vec2.new(x_start + content_width - LAYOUT.listbox_scrollbar_width - 2, entry_bottom)

                    -- Selection highlight
                    if entry_i == selected_idx then
                        self.window:render_rect_filled(entry_start, entry_end,
                            self.colors.listbox_selected or color.new(10, 132, 255, 50), 0)
                    end

                    -- Hover highlight
                    local entry_hovered = self.window:is_mouse_hovering_rect(entry_start, entry_end)
                    if entry_hovered and entry_i ~= selected_idx then
                        self.window:render_rect_filled(entry_start, entry_end,
                            self.colors.dropdown_hover or color.new(10, 132, 255, 25), 0)
                    end

                    -- Entry text
                    local entry_label = type(entry) == "table" and entry.label or tostring(entry)
                    local entry_color = type(entry) == "table" and entry.color or self.colors.text_primary
                    local text_y = entry_top + (row_height - self.window:get_text_size(entry_label).y) / 2
                    self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x_start + 8, text_y), entry_color, entry_label)

                    -- Sublabel (right-aligned)
                    if type(entry) == "table" and entry.sublabel then
                        local sub_size = self.window:get_text_size(entry.sublabel)
                        local sub_x = x_start + content_width - LAYOUT.listbox_scrollbar_width - 10 - sub_size.x
                        local sub_y = entry_top + (row_height - sub_size.y) / 2
                        self.window:render_text(enums.window_enums.font_id.FONT_SMALL,
                            vec2.new(sub_x, sub_y), self.colors.text_secondary, entry.sublabel)
                    end

                    -- Click to select
                    if self.window:is_rect_clicked(entry_start, entry_end) then
                        self._listbox_selected[lb_id] = entry_i
                        if type(on_select) == "function" then
                            pcall(on_select, entry_i, entry)
                        end
                    end
                end

                item_y = item_y + row_height
            end

            self.window:pop_clip_rect()

            -- Mini scrollbar with drag support
            if total_height > box_height and max_scroll > 0 then
                local sb_x = x_start + content_width - LAYOUT.listbox_scrollbar_width
                local sb_track_height = box_height
                local sb_thumb_height = math.max(12, (box_height / total_height) * sb_track_height)
                local sb_thumb_y = y_offset + (scroll / max_scroll) * (sb_track_height - sb_thumb_height)

                -- Track
                local sb_track_start = vec2.new(sb_x - 2, y_offset)
                local sb_track_end = vec2.new(sb_x + LAYOUT.listbox_scrollbar_width + 2, y_offset + box_height)
                self.window:render_rect_filled(
                    vec2.new(sb_x, y_offset),
                    vec2.new(sb_x + LAYOUT.listbox_scrollbar_width, y_offset + box_height),
                    color.new(255, 255, 255, 10), 3)

                -- Thumb
                local sb_thumb_start = vec2.new(sb_x, sb_thumb_y)
                local sb_thumb_end = vec2.new(sb_x + LAYOUT.listbox_scrollbar_width, sb_thumb_y + sb_thumb_height)
                local sb_hovered = self.window:is_mouse_hovering_rect(sb_thumb_start, sb_thumb_end)
                local drag_key = "lb_drag_" .. lb_id
                self.window:render_rect_filled(sb_thumb_start, sb_thumb_end,
                    (sb_hovered or self[drag_key]) and color.new(255, 255, 255, 120) or color.new(255, 255, 255, 70), 3)

                -- Scrollbar drag interaction
                self.window:is_mouse_hovering_rect_block_movement(sb_track_start, sb_track_end)
                if self.window:is_mouse_hovering_rect(sb_track_start, sb_track_end) and is_mouse_clicked_left(self.window) then
                    self[drag_key] = true
                end
                if self[drag_key] then
                    if is_mouse_pressed_left(self.window) then
                        local mouse_pos = self:_get_window_local_mouse_pos("raw")
                        if mouse_pos then
                            local track_progress = (mouse_pos.y - y_offset - sb_thumb_height / 2) / (sb_track_height - sb_thumb_height)
                            track_progress = math.max(0, math.min(1, track_progress))
                            self._listbox_scroll[lb_id] = track_progress * max_scroll
                        end
                        self.window:block_input_capture()
                    else
                        self[drag_key] = false
                    end
                end
            end

            y_offset = y_offset + box_height + LAYOUT.element_spacing
        end
    end

    return y_offset + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- LAYOUT HELPERS (Phase 7)
-- ============================================================================

function RotationSettingsUI:_render_hrow(section, y_offset)
    if not section.columns or #section.columns == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local max_bottom = y_offset
    local current_x = x_start

    for _, col_def in ipairs(section.columns) do
        local width_pct = col_def.width_pct or (1 / #section.columns)
        local col_width = content_width * width_pct
        local render_fn = col_def.render_fn

        if type(render_fn) == "function" then
            local ok, new_y = pcall(render_fn, self, current_x, y_offset, col_width, self.window, self.colors)
            if ok and type(new_y) == "number" then
                max_bottom = math.max(max_bottom, new_y)
            end
        end

        current_x = current_x + col_width
    end

    return max_bottom + LAYOUT.section_padding_bottom
end

function RotationSettingsUI:_render_columns(section, y_offset)
    if not section.col_defs or #section.col_defs == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local max_bottom = y_offset
    local current_x = x_start
    local col_gap = 12

    for col_i, col_def in ipairs(section.col_defs) do
        local width_pct = col_def.width_pct or (1 / #section.col_defs)
        local col_width = content_width * width_pct - (col_i < #section.col_defs and col_gap or 0)
        local groups = col_def.groups or {}

        local col_y = y_offset
        for _, group in ipairs(groups) do
            if self:_is_entry_visible(group) then
                if group.label then
                    -- Use current_x instead of LAYOUT.padding_side for column-local rendering
                    self.window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG,
                        vec2.new(current_x, col_y), self.colors.text_secondary, group.label)
                    col_y = col_y + self.window:get_text_size(group.label).y + 10
                end

                -- Dispatch to existing renderers (they use LAYOUT.padding_side internally,
                -- so columns work best with custom render fns)
                if group.type == "custom" and group.render_fn then
                    local ok, new_y = pcall(group.render_fn, self, col_y)
                    if ok and type(new_y) == "number" then
                        col_y = new_y
                    end
                end
            end
        end

        max_bottom = math.max(max_bottom, col_y)
        current_x = current_x + col_width + col_gap
    end

    return max_bottom + LAYOUT.section_padding_bottom
end

-- ============================================================================
-- ROW LIST RENDERER (Apple-style inline rows)
-- ============================================================================

function RotationSettingsUI:_render_row_list(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_x_left = LAYOUT.padding_side + LAYOUT.card_padding_h
    local content_x_right = window_size.x - LAYOUT.padding_side - LAYOUT.card_padding_h

    -- Count visible items for separator logic
    local visible_items = {}
    for _, item in ipairs(section.elements) do
        if item and self:_is_entry_visible(item) then
            visible_items[#visible_items + 1] = item
        end
    end

    if #visible_items == 0 then
        return y_offset
    end

    for vi, item in ipairs(visible_items) do
        local row_y = y_offset
        local row_center_y = row_y + LAYOUT.row_height / 2
        local item_type = item.type or "info"

        -- Row hover detection
        local row_start = vec2.new(content_x_left, row_y)
        local row_end_pos = vec2.new(content_x_right, row_y + LAYOUT.row_height)
        local is_hovered = self.window:is_mouse_hovering_rect(row_start, row_end_pos)
        if is_hovered then
            self.window:is_mouse_hovering_rect_block_movement(row_start, row_end_pos)
        end

        -- Tooltip
        if is_hovered and item.tooltip then
            self._tooltip = item.tooltip
        end

        -- Render label on left
        local label_text = item.label or ""
        local label_y = row_center_y - LAYOUT.font_body / 2
        render_text_sized(self.window, content_x_left, label_y,
            self.colors.text_primary, LAYOUT.font_body, label_text)

        -- Render control on right based on item.type
        if item_type == "toggle" then
            -- Apple toggle switch
            local element = item.element
            local ok_state, is_on = pcall(function()
                return element:get_state()
            end)
            if not ok_state then
                is_on = false
            end

            local toggle_x = content_x_right - LAYOUT.toggle_width
            local toggle_y = row_center_y - LAYOUT.toggle_height / 2
            local new_state = render_toggle_switch(self.window, self.colors, toggle_x, toggle_y, is_on)
            if new_state ~= nil then
                pcall(function()
                    element:set(new_state)
                end)
                if item.on_change then
                    pcall(item.on_change, new_state)
                end
            end

        elseif item_type == "stepper" then
            -- [-] value [+] inline stepper
            local element = item.element
            local ok_val, current_val = pcall(function() return element:get() end)
            if not ok_val then current_val = 0 end

            local min_val = item.min or 0
            local max_val = item.max or 100
            local step = item.step or 1
            local decimals = item.decimals or infer_decimals(step)
            local suffix = item.suffix or ""

            local btn_size = LAYOUT.stepper_button_size
            local val_w = LAYOUT.stepper_value_width
            local gap = LAYOUT.stepper_gap
            local total_w = btn_size + gap + val_w + gap + btn_size
            local stepper_x = content_x_right - total_w
            local btn_y = row_center_y - btn_size / 2

            -- [-] button
            local minus_start = vec2.new(stepper_x, btn_y)
            local minus_end = vec2.new(stepper_x + btn_size, btn_y + btn_size)
            local minus_hovered = self.window:is_mouse_hovering_rect(minus_start, minus_end)
            local minus_bg = minus_hovered and lighten_color(self.colors.slider_bg, 20) or self.colors.slider_bg
            self.window:render_rect_filled(minus_start, minus_end, minus_bg, 6)
            local minus_label = "-"
            local minus_label_y = btn_y + (btn_size - LAYOUT.font_body) / 2
            local minus_label_x = stepper_x + (btn_size - LAYOUT.font_body * 0.5) / 2
            render_text_sized(self.window, minus_label_x, minus_label_y,
                self.colors.text_primary, LAYOUT.font_body, minus_label)
            if minus_hovered then
                self.window:is_mouse_hovering_rect_block_movement(minus_start, minus_end)
            end
            if minus_hovered and is_mouse_clicked_left(self.window) then
                self.window:block_input_capture()
                local new_val = clamp_number(current_val - step, min_val, max_val)
                pcall(function() element:set(new_val) end)
                if item.on_change then pcall(item.on_change, new_val) end
            end

            -- Value display
            local val_x = stepper_x + btn_size + gap
            local format_str = "%." .. decimals .. "f"
            local val_text = string.format(format_str, current_val) .. suffix
            local val_label_y = btn_y + (btn_size - LAYOUT.font_body) / 2
            -- Center the value text within val_w
            local val_text_w = self.window:get_text_size(val_text).x
            local val_text_x = val_x + (val_w - val_text_w) / 2
            render_text_sized(self.window, val_text_x, val_label_y,
                self.colors.text_secondary, LAYOUT.font_body, val_text)

            -- [+] button
            local plus_x = val_x + val_w + gap
            local plus_start = vec2.new(plus_x, btn_y)
            local plus_end = vec2.new(plus_x + btn_size, btn_y + btn_size)
            local plus_hovered = self.window:is_mouse_hovering_rect(plus_start, plus_end)
            local plus_bg = plus_hovered and lighten_color(self.colors.slider_bg, 20) or self.colors.slider_bg
            self.window:render_rect_filled(plus_start, plus_end, plus_bg, 6)
            local plus_label = "+"
            local plus_label_y = btn_y + (btn_size - LAYOUT.font_body) / 2
            local plus_label_x = plus_x + (btn_size - LAYOUT.font_body * 0.5) / 2
            render_text_sized(self.window, plus_label_x, plus_label_y,
                self.colors.text_primary, LAYOUT.font_body, plus_label)
            if plus_hovered then
                self.window:is_mouse_hovering_rect_block_movement(plus_start, plus_end)
            end
            if plus_hovered and is_mouse_clicked_left(self.window) then
                self.window:block_input_capture()
                local new_val = clamp_number(current_val + step, min_val, max_val)
                pcall(function() element:set(new_val) end)
                if item.on_change then pcall(item.on_change, new_val) end
            end

        elseif item_type == "info" then
            -- Right-aligned value text
            local value_text = ""
            if item.value_fn and type(item.value_fn) == "function" then
                local ok_v, v = pcall(item.value_fn)
                if ok_v then value_text = tostring(v) end
            elseif item.value ~= nil then
                value_text = tostring(item.value)
            end

            local val_color = item.color or self.colors.text_secondary
            if item.color_fn and type(item.color_fn) == "function" then
                local ok_cf, cf = pcall(item.color_fn, value_text)
                if ok_cf and cf then val_color = type(cf) == "string" and self.colors[cf] or cf end
            end
            local val_size = self.window:get_text_size(value_text)
            local val_x = content_x_right - val_size.x
            local val_y = row_center_y - LAYOUT.font_body / 2
            render_text_sized(self.window, val_x, val_y, val_color, LAYOUT.font_body, value_text)

        elseif item_type == "slider" then
            -- Compact inline slider (120px)
            local element = item.element
            local ok_val, current_val = pcall(function() return element:get() end)
            if not ok_val then current_val = 0 end

            local min_val = item.min or 0
            local max_val = item.max or 100
            local suffix = item.suffix or ""

            local slider_w = 120
            local slider_h = 6
            local slider_x = content_x_right - slider_w
            local slider_y = row_center_y - slider_h / 2

            local bar_start = vec2.new(slider_x, slider_y)
            local bar_end_pos = vec2.new(slider_x + slider_w, slider_y + slider_h)

            -- Track background
            local bar_hovered = self.window:is_mouse_hovering_rect(
                vec2.new(slider_x, slider_y - 6), vec2.new(slider_x + slider_w, slider_y + slider_h + 6))
            local bg_col = bar_hovered and lighten_color(self.colors.slider_bg, 10) or self.colors.slider_bg
            self.window:render_rect_filled(bar_start, bar_end_pos, bg_col, 3)

            -- Track fill
            local progress = (max_val > min_val) and ((current_val - min_val) / (max_val - min_val)) or 0
            progress = math.max(0, math.min(1, progress))
            local fill_w = slider_w * progress
            self.window:render_rect_filled(bar_start,
                vec2.new(slider_x + fill_w, slider_y + slider_h),
                self.colors.slider_fill, 3)

            -- Active slider highlight
            local is_active = self._active_slider and self._active_slider.element == element
            local border_col = is_active and self.colors.primary_accent or self.colors.section_border
            self.window:render_rect(bar_start, bar_end_pos, border_col, 3, 1.0)

            -- Value text to the left of the slider
            local val_text = string.format("%d%s", current_val, suffix)
            local val_size = self.window:get_text_size(val_text)
            local val_x = slider_x - val_size.x - 8
            local val_y = row_center_y - LAYOUT.font_body / 2
            render_text_sized(self.window, val_x, val_y,
                self.colors.text_secondary, LAYOUT.font_body, val_text)

            -- Click-to-drag interaction
            if bar_hovered then
                self.window:is_mouse_hovering_rect_block_movement(
                    vec2.new(slider_x, slider_y - 6), vec2.new(slider_x + slider_w, slider_y + slider_h + 6))
            end
            if bar_hovered and is_mouse_clicked_left(self.window) then
                self.window:block_input_capture()

                local raw_pos = select(1, self:_get_window_local_mouse_pos("raw"))
                local adjusted_pos = select(1, self:_get_window_local_mouse_pos("adjusted"))

                local function slider_score(pos)
                    if not pos then return 1e30 end
                    local local_x = pos.x - slider_x
                    local dx = 0
                    if local_x < 0 then dx = -local_x
                    elseif local_x > slider_w then dx = local_x - slider_w end
                    return dx * dx
                end

                local use_space = "raw"
                local chosen_pos = raw_pos
                if slider_score(adjusted_pos) < slider_score(raw_pos) then
                    use_space = "adjusted"
                    chosen_pos = adjusted_pos
                end

                self._active_slider = {
                    element = element,
                    min_value = min_val,
                    max_value = max_val,
                    bar_x_start = slider_x,
                    bar_width = slider_w,
                    last_mouse_pos = chosen_pos,
                    mouse_space = use_space
                }
                self:_apply_active_slider_from_mouse()
            end

        elseif item_type == "button" then
            -- Right-aligned small button
            local btn_text = item.text or "Action"
            local btn_color = item.color or self.colors.primary_accent
            local btn_text_size = self.window:get_text_size(btn_text)
            local btn_pad_h = 12
            local btn_w = btn_text_size.x + btn_pad_h * 2
            local btn_h = LAYOUT.stepper_button_size
            local btn_x = content_x_right - btn_w
            local btn_y = row_center_y - btn_h / 2

            local btn_start = vec2.new(btn_x, btn_y)
            local btn_end_pos = vec2.new(btn_x + btn_w, btn_y + btn_h)
            local btn_hovered = self.window:is_mouse_hovering_rect(btn_start, btn_end_pos)

            local bg = btn_hovered and lighten_color(btn_color, 25) or btn_color
            self.window:render_rect_filled(btn_start, btn_end_pos, bg, 6)

            local text_x = btn_x + (btn_w - btn_text_size.x) / 2
            local text_y = btn_y + (btn_h - LAYOUT.font_body) / 2
            render_text_sized(self.window, text_x, text_y,
                self.colors.text_primary, LAYOUT.font_body, btn_text)

            if btn_hovered then
                self.window:is_mouse_hovering_rect_block_movement(btn_start, btn_end_pos)
            end
            if btn_hovered and is_mouse_clicked_left(self.window) then
                self.window:block_input_capture()
                if item.on_click then
                    pcall(item.on_click)
                end
            end
        end

        -- Advance y by row_height
        y_offset = y_offset + LAYOUT.row_height

        -- Draw separator between rows (not after the last visible row)
        if vi < #visible_items then
            local sep_x_left = content_x_left + LAYOUT.row_separator_inset
            local sep_color = self.colors.row_separator or self.colors.separator
            self.window:render_rect_filled(
                vec2.new(sep_x_left, y_offset),
                vec2.new(content_x_right, y_offset + LAYOUT.row_separator_height),
                sep_color, 0)
            y_offset = y_offset + LAYOUT.row_separator_height
        end
    end

    -- Handle active slider drag (for inline sliders in this row_list)
    if self._active_slider then
        if is_mouse_pressed_left(self.window) then
            self.window:block_input_capture()
            self:_apply_active_slider_from_mouse()
        else
            self._active_slider = nil
        end
    end

    return y_offset
end

-- ============================================================================
-- METRIC GRID RENDERER (2-column stat cards)
-- ============================================================================

function RotationSettingsUI:_render_metric_grid(section, y_offset)
    if not section.elements or #section.elements == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local content_x_left = LAYOUT.padding_side + LAYOUT.card_padding_h
    local content_x_right = window_size.x - LAYOUT.padding_side - LAYOUT.card_padding_h
    local content_width = content_x_right - content_x_left
    local gap = LAYOUT.metric_card_gap
    local cell_width = (content_width - gap) / 2
    local cell_height = LAYOUT.metric_number_size + LAYOUT.metric_label_size + 16

    -- Collect visible items
    local visible_items = {}
    for _, item in ipairs(section.elements) do
        if item and self:_is_entry_visible(item) then
            visible_items[#visible_items + 1] = item
        end
    end

    if #visible_items == 0 then
        return y_offset
    end

    local col = 0
    local row_y = y_offset

    for _, item in ipairs(visible_items) do
        local cell_x = content_x_left + col * (cell_width + gap)
        local cell_y = row_y

        -- Cell background
        local cell_bg = self.colors.bg_elevated or self.colors.section_bg
        self.window:render_rect_filled(
            vec2.new(cell_x, cell_y),
            vec2.new(cell_x + cell_width, cell_y + cell_height),
            cell_bg, 8)

        -- Get value
        local raw_value = 0
        if item.value_fn and type(item.value_fn) == "function" then
            local ok_v, v = pcall(item.value_fn)
            if ok_v then raw_value = v end
        end

        -- Format value
        local display_value
        if item.format_fn and type(item.format_fn) == "function" then
            local ok_f, formatted = pcall(item.format_fn, raw_value)
            if ok_f then
                display_value = tostring(formatted)
            else
                display_value = tostring(raw_value)
            end
        else
            display_value = tostring(raw_value)
        end

        -- Render large number (centered)
        local number_color = item.color or self.colors.text_primary
        if item.color_fn and type(item.color_fn) == "function" then
            local ok_cf, cf = pcall(item.color_fn, display_value)
            if ok_cf and cf then number_color = type(cf) == "string" and self.colors[cf] or cf end
        end
        local number_text_w = self.window:get_text_size(display_value).x
        local number_x = cell_x + (cell_width - number_text_w) / 2
        local number_y = cell_y + 6
        render_text_sized(self.window, number_x, number_y,
            number_color, LAYOUT.metric_number_size, display_value)

        -- Render caption label (centered below number)
        local label_text = item.label or ""
        local label_text_w = self.window:get_text_size(label_text).x
        local label_x = cell_x + (cell_width - label_text_w) / 2
        local label_y = number_y + LAYOUT.metric_number_size + 2
        render_text_sized(self.window, label_x, label_y,
            self.colors.text_secondary, LAYOUT.metric_label_size, label_text)

        -- Advance grid position
        col = col + 1
        if col >= 2 then
            col = 0
            row_y = row_y + cell_height + gap
        end
    end

    -- If the last row was incomplete (odd number), still advance past it
    if col > 0 then
        row_y = row_y + cell_height
    end

    return row_y
end

function RotationSettingsUI:_dispatch_group_renderer(group, y_offset)
    if group.type == "checkbox_grid" then
        return self:_render_checkbox_grid(group, y_offset)
    elseif group.type == "slider_list" then
        return self:_render_slider_list(group, y_offset)
    elseif group.type == "combo_list" then
        return self:_render_combo_list(group, y_offset)
    elseif group.type == "segmented_control" then
        return self:_render_segmented_control(group, y_offset)
    elseif group.type == "keybind_grid" then
        return self:_render_keybind_grid(group, y_offset)
    elseif group.type == "progress_bar_list" then
        return self:_render_progress_bar_list(group, y_offset)
    elseif group.type == "dropdown_list" then
        return self:_render_dropdown_list(group, y_offset)
    elseif group.type == "text_input_list" then
        return self:_render_text_input_list(group, y_offset)
    elseif group.type == "listbox" then
        return self:_render_listbox(group, y_offset)
    elseif group.type == "hrow" then
        return self:_render_hrow(group, y_offset)
    elseif group.type == "columns" then
        return self:_render_columns(group, y_offset)
    elseif group.type == "row_list" then
        return self:_render_row_list(group, y_offset)
    elseif group.type == "metric_grid" then
        return self:_render_metric_grid(group, y_offset)
    elseif group.type == "custom" and group.render_fn then
        local ok, new_y = pcall(group.render_fn, self, y_offset)
        if ok and type(new_y) == "number" then
            return new_y
        end
    end
    return y_offset
end

function RotationSettingsUI:_render_tab_groups(section, y_offset)
    if not section.groups or #section.groups == 0 then
        return y_offset
    end

    local window_size = self.window:get_size()
    local card_x = LAYOUT.padding_side
    local card_w = window_size.x - LAYOUT.padding_side * 2

    for gi, group in ipairs(section.groups) do
        if self:_is_entry_visible(group) then
            local use_card = group.card ~= false
            local card_key = (section.id or "") .. "_g" .. tostring(gi)

            -- Section label ABOVE card (uppercase heading style)
            if group.label then
                local label_upper = string.upper(group.label)
                local label_color = self.colors.text_secondary
                render_text_sized(self.window, card_x + LAYOUT.card_padding_h,
                    y_offset, label_color, LAYOUT.font_heading, label_upper)
                y_offset = y_offset + LAYOUT.font_heading + LAYOUT.section_label_gap
            end

            if use_card then
                -- Pre-draw card background using cached height from previous frame
                local cached_h = self._card_heights[card_key] or 0
                if cached_h > 0 then
                    local bg_color = self.colors.bg_card or self.colors.section_bg
                    self.window:render_rect_filled(
                        vec2.new(card_x, y_offset),
                        vec2.new(card_x + card_w, y_offset + cached_h),
                        bg_color, LAYOUT.card_corner_radius)
                end

                -- Add top padding inside card
                local card_top = y_offset
                y_offset = y_offset + LAYOUT.card_padding_v

                -- Dispatch content renderer
                y_offset = self:_dispatch_group_renderer(group, y_offset)

                -- Add bottom padding inside card
                y_offset = y_offset + LAYOUT.card_padding_v

                -- Cache actual card height for next frame
                self._card_heights[card_key] = y_offset - card_top
            else
                -- No card wrapping, render content directly
                y_offset = self:_dispatch_group_renderer(group, y_offset)
            end

            -- Footer text below the card
            if group.footer then
                y_offset = y_offset + LAYOUT.section_footer_gap
                local footer_color = self.colors.text_footer or self.colors.text_disabled
                render_text_sized(self.window, card_x + LAYOUT.card_padding_h,
                    y_offset, footer_color, LAYOUT.font_caption, group.footer)
                y_offset = y_offset + LAYOUT.font_caption
            end

            -- Gap between sections
            y_offset = y_offset + LAYOUT.section_gap
        end
    end

    return y_offset
end
-- ============================================================================
-- FLOATING TOOLTIP RENDERING (Phase 3)
-- ============================================================================

function RotationSettingsUI:_render_floating_tooltip()
    if not self._tooltip or not self.window then return end

    local win = self.window
    local text = self._tooltip
    local window_size = win:get_size()

    -- Get mouse position for floating placement
    local mouse_pos = self:_get_window_local_mouse_pos("raw")
    if not mouse_pos then return end

    local text_size = win:get_text_size(text)
    local pad = LAYOUT.tooltip_padding
    local max_w = LAYOUT.tooltip_max_width

    -- Word-wrap: if text is wider than max_w, truncate with ellipsis for now
    local display_text = text
    if text_size.x > max_w then
        -- Simple truncation (full word-wrap would require line splitting)
        while #display_text > 3 do
            display_text = string.sub(display_text, 1, -2)
            local test_size = win:get_text_size(display_text .. "...")
            if test_size.x <= max_w then
                display_text = display_text .. "..."
                text_size = win:get_text_size(display_text)
                break
            end
        end
    end

    local tip_w = text_size.x + pad * 2
    local tip_h = text_size.y + pad * 2

    -- Position: offset from cursor, clamped to window
    local tip_x = mouse_pos.x + LAYOUT.tooltip_offset_x
    local tip_y = mouse_pos.y + LAYOUT.tooltip_offset_y
    if tip_x + tip_w > window_size.x - 4 then
        tip_x = mouse_pos.x - tip_w - 4
    end
    if tip_y + tip_h > window_size.y - 4 then
        tip_y = mouse_pos.y - tip_h - 4
    end
    tip_x = math.max(4, tip_x)
    tip_y = math.max(4, tip_y)

    local bg_color = self.colors.bg_tooltip or color.new(28, 28, 30, 240)

    -- Queue as overlay so it renders above clip rects
    self:_queue_overlay(function()
        win:render_rect_filled(
            vec2.new(tip_x, tip_y),
            vec2.new(tip_x + tip_w, tip_y + tip_h),
            bg_color, 6.0)
        win:render_rect(
            vec2.new(tip_x, tip_y),
            vec2.new(tip_x + tip_w, tip_y + tip_h),
            self.colors.section_border, 6.0, 1.0)
        win:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(tip_x + pad, tip_y + pad),
            self.colors.text_secondary, display_text)
    end)
end

-- ============================================================================
-- MAIN SECTION RENDERING
-- ============================================================================

function RotationSettingsUI:_render_sections()
    self._tooltip = nil
    self._overlay_queue = {}

    -- Before-tabs hook (e.g. "Show Advanced" toggle)
    local y_before = LAYOUT.padding_top
    if self._before_tabs_fn then
        local ok, new_y = pcall(self._before_tabs_fn, self, y_before)
        if ok and type(new_y) == "number" then
            y_before = new_y
        end
    end

    -- Render tab bar
    local y_offset = self:_render_tab_bar(y_before)

    -- Add separator line below tabs
    local window_size = self.window:get_size()
    local separator_start = vec2.new(LAYOUT.padding_side, y_offset)
    local separator_end = vec2.new(window_size.x - LAYOUT.padding_side, y_offset + LAYOUT.separator_height)
    self.window:render_rect_filled(separator_start, separator_end, self.colors.separator, 0)

    y_offset = y_offset + LAYOUT.separator_height + LAYOUT.tab_content_padding_top

    -- Scrollable tab content area
    local tab_content_top = y_offset
    local tab_content_bottom = window_size.y - LAYOUT.padding_bottom
    local visible_height = tab_content_bottom - tab_content_top

    -- Register artificial bounds so the engine tracks mouse wheel for us.
    -- Bounds start at tab_content_top (not 0) so max_scroll maps directly
    -- to the content overflow amount.
    if self._content_height > visible_height then
        pcall(function()
            self.window:add_artificial_item_bounds(
                vec2.new(0, tab_content_top),
                vec2.new(window_size.x, tab_content_top + self._content_height),
                "scroll_content"
            )
        end)
    end

    -- ---- Scroll routing (delta-based) ----
    -- Read engine scroll position. Compute delta from previous frame.
    -- Use PREVIOUS frame's listbox hover state to decide routing:
    --   If a listbox was hovered last frame, route delta to its internal scroll.
    --   Otherwise, apply engine scroll position to the parent scroll.
    local ok_scroll, current_scroll = pcall(function() return self.window:get_scroll() end)
    local engine_scroll_y = (ok_scroll and current_scroll) and (current_scroll.y or 0) or 0

    if self._prev_engine_scroll_y == nil then
        self._prev_engine_scroll_y = engine_scroll_y
    end

    local scroll_delta = engine_scroll_y - self._prev_engine_scroll_y

    if self._listbox_consumed_scroll and self._listbox_hover_id and math.abs(scroll_delta) > 0.01 then
        -- Route delta to the hovered listbox
        local lb_id = self._listbox_hover_id
        local lb_scroll = (self._listbox_scroll[lb_id] or 0) + scroll_delta
        self._listbox_scroll[lb_id] = math.max(0, lb_scroll)
        -- Restore engine scroll to prevent parent movement
        pcall(function() self.window:set_scroll_y(self._prev_engine_scroll_y) end)
        -- _prev_engine_scroll_y stays at the restored value
    else
        self._scroll_y = math.max(0, engine_scroll_y)
        self._prev_engine_scroll_y = engine_scroll_y
    end

    -- Reset listbox hover state for this frame (will be set again during render)
    self._listbox_consumed_scroll = false
    self._listbox_hover_id = nil

    -- Clamp scroll to content bounds
    local max_scroll = math.max(0, self._content_height - visible_height)
    self._scroll_y = math.min(self._scroll_y, max_scroll)

    -- If content fits, ensure no scroll
    if self._content_height <= visible_height then
        self._scroll_y = 0
        pcall(function() self.window:set_scroll_y(0) end)
        self._prev_engine_scroll_y = 0
    end

    -- Clip content area
    self.window:push_clip_rect(
        vec2.new(0, tab_content_top),
        vec2.new(window_size.x, tab_content_bottom),
        true)

    -- Render content with scroll offset
    local scrolled_y = y_offset - self._scroll_y
    local final_y = self:_render_active_tab_content(scrolled_y)
    self._content_height = final_y - scrolled_y

    self.window:pop_clip_rect()

    -- Queue floating tooltip (rendered as overlay above clip rects)
    self:_render_floating_tooltip()

    -- Flush all overlay draws (tooltips, dropdowns) above the clip rect
    self:_flush_overlays()

    -- Custom scrollbar (only if content overflows)
    if self._content_height > visible_height and max_scroll > 0 then
        local sb_width = 6
        local sb_x = window_size.x - LAYOUT.padding_side
        local sb_track_height = visible_height
        local sb_thumb_height = math.max(20, (visible_height / self._content_height) * sb_track_height)
        local sb_thumb_y = tab_content_top + (self._scroll_y / max_scroll) * (sb_track_height - sb_thumb_height)

        -- Track background
        self.window:render_rect_filled(
            vec2.new(sb_x, tab_content_top),
            vec2.new(sb_x + sb_width, tab_content_bottom),
            color.new(255, 255, 255, 15), 3)

        -- Thumb
        local sb_thumb_start = vec2.new(sb_x, sb_thumb_y)
        local sb_thumb_end = vec2.new(sb_x + sb_width, sb_thumb_y + sb_thumb_height)
        local sb_hovered = self.window:is_mouse_hovering_rect(sb_thumb_start, sb_thumb_end)
        local sb_thumb_color = sb_hovered and color.new(255, 255, 255, 140) or color.new(255, 255, 255, 100)
        self.window:render_rect_filled(sb_thumb_start, sb_thumb_end, sb_thumb_color, 3)

        -- Scrollbar drag interaction
        local sb_track_start = vec2.new(sb_x - 4, tab_content_top)
        local sb_track_end = vec2.new(sb_x + sb_width + 4, tab_content_bottom)
        self.window:is_mouse_hovering_rect_block_movement(sb_track_start, sb_track_end)

        if self.window:is_mouse_hovering_rect(sb_track_start, sb_track_end) and is_mouse_clicked_left(self.window) then
            self._scroll_drag = true
        end

        if self._scroll_drag then
            if is_mouse_pressed_left(self.window) then
                local mouse_pos = self:_get_window_local_mouse_pos("raw")
                if mouse_pos then
                    local track_progress = (mouse_pos.y - tab_content_top - sb_thumb_height / 2) / (sb_track_height - sb_thumb_height)
                    track_progress = math.max(0, math.min(1, track_progress))
                    self._scroll_y = track_progress * max_scroll
                    pcall(function() self.window:set_scroll_y(self._scroll_y) end)
                end
                self.window:block_input_capture()
            else
                self._scroll_drag = false
            end
        end
    else
        self._scroll_y = 0
    end

    if self._active_key_capture then
        self.window:block_input_capture()
    end
    self:_process_key_capture_input()
    self:_render_key_capture_prompt()
end

-- ============================================================================
-- PUBLIC API - LIFECYCLE HOOKS
-- ============================================================================

---Called in rotation's on_menu_render() to show toggle button
function RotationSettingsUI:on_menu_render()
    if not self.menu or not self.menu.enable then
        return
    end

    -- Simple checkbox in classic menu to toggle custom window
    if self.menu.enable:get_state() then
        -- Window is enabled, could add a button here if needed
    end
end

---Called in rotation's on_render() to render the custom window
function RotationSettingsUI:on_render()
    if not self:_is_enabled() then
        return
    end

    if not self.window then
        self:_build_window()
    end

    -- Sync tab state from saved value
    self:_sync_tab_state()

    -- Register window render callback
    local function render_window_content()
        self:_render_sections()
    end

    if self._render_layer then
        self.window:set_render_layer(self._render_layer)
    end

    self.window:begin(
        enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS,
        true,
        self.colors.background,
        self.colors.border,
        enums.window_enums.window_cross_visuals.DEFAULT,
        enums.window_enums.window_behaviour_flags.NO_SCROLLBAR,
        render_window_content
    )

    self:_sync_window_state()
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return {
    new = RotationSettingsUI.new,
    LAYOUT = LAYOUT,
    THEMES = THEMES,
}
