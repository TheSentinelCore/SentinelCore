--[[
    GatherBuddy UI Window Orchestrator

    Creates and manages the RotationSettingsUI instance, registers all tabs,
    renders the control bar above the tab bar, and handles overlay toggle.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local rotation_settings_ui = require("shared/rotation_settings_ui")

-- Tab modules
local ProfileTab = require("ui/tabs/profile_tab")
local GatherTab = require("ui/tabs/gather_tab")
local NavTab = require("ui/tabs/nav_tab")
local SafetyTab = require("ui/tabs/safety_tab")
local StatsTab = require("ui/tabs/stats_tab")

-- Settings sync
local SettingsSync = require("ui/SettingsSync")

local LAYOUT = rotation_settings_ui.LAYOUT

local Window = {}

-- Private state
local _ui = nil           -- RotationSettingsUI instance
local _initialized = false
local _menu_elements = nil
local _ui_state = nil
local _gatherbuddy = nil

-- Status colors
local STATUS_COLORS = {
    running = color.new(80, 200, 80, 255),
    paused = color.new(220, 200, 60, 255),
    stopped = color.new(200, 80, 80, 255),
}

---Render a control bar button and return true if clicked
---@return boolean clicked
local function render_ctrl_button(window, x, y, width, height, text, colors, bg_color)
    local btn_start = vec2.new(x, y)
    local btn_end = vec2.new(x + width, y + height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local bg = is_hovered and bg_color or colors.section_bg
    window:render_rect_filled(btn_start, btn_end, bg, 3.0)
    window:render_rect(btn_start, btn_end, bg_color, 3.0, 1.0)

    local text_size = window:get_text_size(text)
    local text_x = x + (width - text_size.x) / 2
    local text_y = y + (height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), color.white(255), text)

    return window:is_rect_clicked(btn_start, btn_end)
end

---Render the control bar above the tab bar
---@param ui rotation_settings_ui The UI instance (self)
---@param y_offset number Starting y position
---@return number New y_offset after control bar
local function render_control_bar(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)

    local running = _gatherbuddy:is_running()
    local paused = _gatherbuddy:is_paused()

    -- Row 1: Profile name (if loaded)
    local bot_mgr = _gatherbuddy:get_bot_manager()
    local profile_mgr = bot_mgr and bot_mgr._modules and bot_mgr._modules.ProfileManager
    if profile_mgr and profile_mgr._profile_name then
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, y_offset), colors.text_secondary,
            "Profile: " .. profile_mgr._profile_name)
        y_offset = y_offset + 20
    end

    -- Row 2: [Start/Stop] [Pause/Resume] + Status
    local btn_h = 24
    local btn_w = 70
    local gap = 6

    -- Start/Stop button
    if not running then
        local start_color = color.new(60, 160, 60, 255)
        if render_ctrl_button(window, x_start, y_offset, btn_w, btn_h, "Start", colors, start_color) then
            local selected_idx = _menu_elements.profile_combo:get()
            local profile = _ui_state.profiles[selected_idx]
            if profile and profile.path then
                _gatherbuddy:start(profile.path)
            else
                _gatherbuddy:start()
            end
        end
    else
        local stop_color = color.new(180, 50, 50, 255)
        if render_ctrl_button(window, x_start, y_offset, btn_w, btn_h, "Stop", colors, stop_color) then
            _gatherbuddy:stop()
        end
    end

    -- Pause/Resume button
    local pause_x = x_start + btn_w + gap
    local pause_text = paused and "Resume" or "Pause"
    local pause_color = paused and color.new(60, 160, 60, 255) or color.new(180, 160, 40, 255)
    if render_ctrl_button(window, pause_x, y_offset, btn_w, btn_h, pause_text, colors, pause_color) then
        if running then
            _gatherbuddy:toggle_pause()
        end
    end

    -- Status text (to the right of buttons)
    local state = _gatherbuddy:get_state()
    local status_text = "Stopped"
    local status_color = STATUS_COLORS.stopped
    if running then
        status_text = paused and "Paused" or "Running"
        status_color = paused and STATUS_COLORS.paused or STATUS_COLORS.running
    end

    local full_status = string.format("%s | %s", status_text, state)
    local status_x = pause_x + btn_w + gap + 8
    local status_y = y_offset + (btn_h - window:get_text_size(full_status).y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(status_x, status_y), status_color, full_status)

    y_offset = y_offset + btn_h + 6

    -- Row 3: Overlay toggle
    local cb_size = 14
    local cb_start = vec2.new(x_start, y_offset)
    local cb_end = vec2.new(x_start + cb_size, y_offset + cb_size)

    local overlay_on = _menu_elements.overlay_enabled_cb:get_state()
    local cb_hovered = window:is_mouse_hovering_rect(cb_start, cb_end)
    window:is_mouse_hovering_rect_block_movement(cb_start, cb_end)

    local cb_bg = overlay_on and colors.checkbox_active or colors.checkbox_inactive
    window:render_rect_filled(cb_start, cb_end, cb_bg, 1.0)
    window:render_rect(cb_start, cb_end, colors.checkbox_border, 1.0, 1.0)

    if overlay_on then
        local pad = 3
        window:render_rect_filled(
            vec2.new(x_start + pad, y_offset + pad),
            vec2.new(x_start + cb_size - pad, y_offset + cb_size - pad),
            color.white(255), 0.5)
    end

    -- Click area for checkbox + label
    local cb_label = "Show Overlay"
    local cb_label_end_x = x_start + cb_size + 8 + window:get_text_size(cb_label).x
    local click_start = vec2.new(x_start, y_offset)
    local click_end = vec2.new(cb_label_end_x, y_offset + cb_size)
    window:is_mouse_hovering_rect_block_movement(click_start, click_end)

    if window:is_rect_clicked(click_start, click_end) then
        _menu_elements.overlay_enabled_cb:set(not overlay_on)
    end

    local label_y = y_offset + (cb_size - window:get_text_size(cb_label).y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start + cb_size + 8, label_y),
        overlay_on and colors.text_primary or colors.text_secondary, cb_label)

    y_offset = y_offset + cb_size + 8

    -- Separator line before tabs
    local sep_start = vec2.new(x_start, y_offset)
    local sep_end = vec2.new(x_start + content_width, y_offset + 2)
    window:render_rect_filled(sep_start, sep_end, colors.separator, 0)
    y_offset = y_offset + 6

    return y_offset
end

---Initialize the UI (called once)
---@param gatherbuddy table The GatherBuddy module
---@param menu_elements table The menu elements table
---@param ui_state table The shared UI state (profiles, etc.)
function Window.init(gatherbuddy, menu_elements, ui_state)
    if _initialized then return end

    _gatherbuddy = gatherbuddy
    _menu_elements = menu_elements
    _ui_state = ui_state

    -- Create the RotationSettingsUI instance
    _ui = rotation_settings_ui.new({
        id = "gatherbuddy",
        title = "GatherBuddy",
        default_x = 100,
        default_y = 100,
        default_w = 480,
        default_h = 550,
        theme = "neutral",
    })

    -- Set the before_tabs hook for the control bar
    _ui._before_tabs_fn = render_control_bar

    -- Register all tabs in order
    ProfileTab.register(_ui, menu_elements, ui_state)
    GatherTab.register(_ui, menu_elements)
    NavTab.register(_ui, menu_elements)
    SafetyTab.register(_ui, menu_elements)
    StatsTab.register(_ui)

    _initialized = true
end

---Called every render frame
function Window.on_render()
    if not _initialized or not _ui then return end

    -- Sync settings from menu elements to Settings persistence
    if _menu_elements then
        SettingsSync.sync(_menu_elements)
    end

    -- Render the UI
    _ui:on_render()
end

---Called in the menu render callback
function Window.on_menu_render()
    if not _initialized or not _ui then return end
    _ui:on_menu_render()
end

---Check if overlay should be shown
---@return boolean
function Window.is_overlay_enabled()
    if _menu_elements then
        return _menu_elements.overlay_enabled_cb:get_state()
    end
    return true
end

---Get the UI instance (for external access if needed)
---@return rotation_settings_ui|nil
function Window.get_ui()
    return _ui
end

return Window
