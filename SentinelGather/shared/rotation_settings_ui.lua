-- Shared Rotation Settings Custom UI
-- A reusable custom window module for displaying rotation settings across all classes

---@type color
local color = require("common/color")

---@type vec2
local vec2 = require("common/geometry/vector_2")

---@type enums
local enums = require("common/enums")

-- ============================================================================
-- HELPER FUNCTIONS (Menu API Compatibility)
-- ============================================================================

local function menu_slider_int(min_value, max_value, default_value, id)
    if core.menu.slider_int then
        return core.menu.slider_int(min_value, max_value, default_value, id)
    end
    if core.menu.slider then
        local slider = core.menu.slider(min_value, max_value, default_value, id)
        if slider and slider.as_int then
            return slider:as_int()
        end
        return slider
    end
    if core.menu.new_slider then
        local slider = core.menu.new_slider(min_value, max_value, default_value, id)
        if slider and slider.as_int then
            return slider:as_int()
        end
        return slider
    end
    return nil
end

local function menu_checkbox(default_value, id)
    if core.menu.checkbox then
        return core.menu.checkbox(default_value, id)
    end
    return nil
end

-- ============================================================================
-- LAYOUT CONSTANTS
-- ============================================================================

local LAYOUT = {
    padding_top = 10,
    padding_side = 15,
    padding_bottom = 15,

    -- Tab system
    tab_bar_height = 35,
    tab_button_height = 30,
    tab_button_min_width = 80,
    tab_button_max_width = 150,
    tab_button_spacing = 2,
    tab_bar_padding_top = 5,
    tab_content_padding_top = 15,

    -- Section settings
    section_spacing = 18,
    section_header_height = 0,
    section_padding_top = 8,
    section_padding_bottom = 10,
    element_height = 26,
    element_spacing = 6,
    column_spacing = 25,
    slider_bar_height = 16,
    checkbox_size = 16,
    keybind_badge_width = 60,
    keybind_status_width = 45,
    keybind_clear_width = 60,
    separator_height = 2
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
---@field _before_tabs_fn fun(self: rotation_settings_ui, y_offset: number): number|nil
local RotationSettingsUI = {}
RotationSettingsUI.__index = RotationSettingsUI

local function is_mouse_pressed_left(window)
    if not window then
        return false
    end
    -- Some backends use 0-based (ImGui), others 1-based. Accept either.
    return window:is_mouse_button_pressed(0) or window:is_mouse_button_pressed(1)
end

local function is_mouse_clicked_left(window)
    if not window then
        return false
    end
    return window:is_mouse_button_clicked(0) or window:is_mouse_button_clicked(1)
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

---@param opts table {elements, labels?, visible_when?}
function TabBuilder:keybind_grid(opts)
    return self:_add_group({
        type = "keybind_grid",
        elements = opts and opts.elements or nil,
        labels = opts and opts.labels or nil,
        visible_when = opts and opts.visible_when or nil
    })
end

---@param opts table {render_fn, visible_when?}
function TabBuilder:custom_render(opts)
    return self:_add_group({
        type = "custom",
        render_fn = opts and opts.render_fn or nil,
        visible_when = opts and opts.visible_when or nil
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
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
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
                border_color = self.colors.primary_accent
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
            self.window:render_rect_filled(tab_start, tab_end, bg_color, 2.0)

            -- Render borders (all sides for now, active tab will be merged later)
            self.window:render_rect(tab_start, tab_end, border_color, 2.0, 1.0)

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
        return y_offset
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
    self.window:render_rect_filled(section_bg_start, section_bg_end, self.colors.section_bg, 2.0)
    self.window:render_rect(section_bg_start, section_bg_end, self.colors.section_border, 2.0, 1.0)

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
            self.window:render_rect_filled(key_box_start, key_box_end, key_bg_color, 2.0)
            self.window:render_rect(key_box_start, key_box_end, self.colors.keybind_border, 2.0, 1.0)

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
            self.window:render_rect_filled(status_box_start, status_box_end, status_hover_color, 2.0)

            local status_text_size = self.window:get_text_size(status_text)
            local status_text_x = status_box_start.x + (LAYOUT.keybind_status_width - status_text_size.x) / 2
            local status_text_y = y_offset + (LAYOUT.element_height - 2 - status_text_size.y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(status_text_x, status_text_y),
                color.white(255), status_text)

            -- Clear badge
            local clear_bg = is_clear_hovered and lighten_color(self.colors.slider_bg, 20) or self.colors.slider_bg
            self.window:render_rect_filled(clear_box_start, clear_box_end, clear_bg, 1.5)
            self.window:render_rect(clear_box_start, clear_box_end, self.colors.section_border, 1.5, 1.0)
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

            self.window:render_rect_filled(checkbox_start, checkbox_end, checkbox_color, 1.0)
            self.window:render_rect(checkbox_start, checkbox_end, self.colors.checkbox_border, 1.0, 1.0)

            -- Checkmark if enabled
            if is_checked then
                local check_padding = 3
                local check_start = vec2.new(x_pos + check_padding, y_offset + check_padding)
                local check_end = vec2.new(x_pos + LAYOUT.checkbox_size - check_padding, y_offset + LAYOUT.checkbox_size - check_padding)
                self.window:render_rect_filled(check_start, check_end, color.white(255), 0.5)
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
        if key_code == 1 or key_code == 2 then
            goto continue_key
        end
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

        ::continue_key::
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

            local min_value, max_value = self:_get_slider_bounds(element)
            if max_value < min_value then
                max_value = min_value
            end

            -- Define rectangles
            local bar_x_start = x_start + label_width
            local bar_start = vec2.new(bar_x_start, y_offset)
            local bar_end = vec2.new(bar_x_start + bar_width, y_offset + LAYOUT.slider_bar_height)

            -- Hover/Press state
            local is_hovered = self.window:is_mouse_hovering_rect(bar_start, bar_end)
            self.window:is_mouse_hovering_rect_block_movement(bar_start, bar_end)

            -- Custom Rendering - Label
            local label_y = y_offset + (LAYOUT.slider_bar_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, label_y),
                self.colors.text_primary, label)

            -- Progress bar background
            local bg_color = is_hovered and lighten_color(self.colors.slider_bg, 20) or self.colors.slider_bg
            self.window:render_rect_filled(bar_start, bar_end, bg_color, 1.5)

            -- Progress bar fill
            local fill_progress = max_value > min_value and ((value - min_value) / (max_value - min_value)) or 0
            local clamped_progress = math.max(0, math.min(1, fill_progress))
            local fill_width = bar_width * clamped_progress
            local fill_end = vec2.new(bar_x_start + fill_width, y_offset + LAYOUT.slider_bar_height)
            self.window:render_rect_filled(bar_start, fill_end, self.colors.slider_fill, 1.5)

            -- Progress bar border
            local is_active_slider = self._active_slider and self._active_slider.element == element
            local border_color = is_active_slider and self.colors.secondary_accent or self.colors.primary_accent
            self.window:render_rect(bar_start, bar_end, border_color, 1.5, 1.0)

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

            local label_y = y_offset + (LAYOUT.slider_bar_height - self.window:get_text_size(label).y) / 2
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, label_y),
                self.colors.text_primary, label)

            local bg_color = is_hovered and lighten_color(self.colors.slider_bg, 20) or self.colors.slider_bg
            self.window:render_rect_filled(box_start, box_end, bg_color, 1.5)
            local border_color = is_hovered and self.colors.secondary_accent or self.colors.primary_accent
            self.window:render_rect(box_start, box_end, border_color, 1.5, 1.0)

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

function RotationSettingsUI:_render_tab_groups(section, y_offset)
    if not section.groups or #section.groups == 0 then
        return y_offset
    end

    for _, group in ipairs(section.groups) do
        if not self:_is_entry_visible(group) then
            goto continue_group
        end

        if group.label then
            local label_pos = vec2.new(LAYOUT.padding_side, y_offset)
            self.window:render_text(enums.window_enums.font_id.FONT_SMALL, label_pos,
                self.colors.primary_accent, group.label)
            y_offset = y_offset + self.window:get_text_size(group.label).y + 6
        end

        if group.type == "checkbox_grid" then
            y_offset = self:_render_checkbox_grid(group, y_offset)
        elseif group.type == "slider_list" then
            y_offset = self:_render_slider_list(group, y_offset)
        elseif group.type == "combo_list" then
            y_offset = self:_render_combo_list(group, y_offset)
        elseif group.type == "keybind_grid" then
            y_offset = self:_render_keybind_grid(group, y_offset)
        elseif group.type == "custom" and group.render_fn then
            local ok, new_y = pcall(group.render_fn, self, y_offset)
            if ok and type(new_y) == "number" then
                y_offset = new_y
            end
        end

        ::continue_group::
    end

    return y_offset
end
-- ============================================================================
-- MAIN SECTION RENDERING
-- ============================================================================

function RotationSettingsUI:_render_sections()
    -- Hook: render custom content before tabs (e.g. control bar)
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
    local separator_end = vec2.new(window_size.x - LAYOUT.padding_side, y_offset + 2)
    self.window:render_rect_filled(separator_start, separator_end, self.colors.separator, 0)

    y_offset = y_offset + 2 + LAYOUT.tab_content_padding_top

    -- Render active tab content
    self:_render_active_tab_content(y_offset)

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

    self.window:begin(
        enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS,
        true,
        self.colors.background,
        self.colors.border,
        enums.window_enums.window_cross_visuals.DEFAULT,
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
