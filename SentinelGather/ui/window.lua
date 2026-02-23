--[[
    SentinelGather UI Window Orchestrator

    Creates and manages the AstroUI instance, registers all tabs,
    renders the control bar above the tab bar, and handles overlay toggle.

    Migrated from rotation_settings_ui to AstroUI with Apple HIG theme.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("lib/AstroUI")

-- Tab modules
local ProfileTab = require("ui/tabs/profile_tab")
local GatherTab = require("ui/tabs/gather_tab")
local SafetyTab = require("ui/tabs/safety_tab")
local StatsTab = require("ui/tabs/stats_tab")

-- Settings sync
local SettingsSync = require("ui/SettingsSync")

local LAYOUT = AstroUI.LAYOUT

local Window = {}

-- Private state
local _ui = nil           -- AstroUI instance
local _initialized = false
local _menu_elements = nil
local _ui_state = nil
local _sentinel_gather = nil

-- Status colors
local STATUS_COLORS = {
    running = color.new(48, 209, 88, 255),   -- Apple green
    paused = color.new(255, 214, 10, 255),    -- Apple yellow
    stopped = color.new(255, 69, 58, 255),    -- Apple red
}

---Render a control bar button and return true if clicked
---@return boolean clicked
local function render_ctrl_button(window, x, y, width, height, text, colors, bg_color)
    local btn_start = vec2.new(x, y)
    local btn_end = vec2.new(x + width, y + height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local bg = is_hovered and bg_color or (colors.bg_elevated or colors.section_bg)
    window:render_rect_filled(btn_start, btn_end, bg, 8.0)
    window:render_rect(btn_start, btn_end, bg_color, 8.0, 1.0)

    local text_size = window:get_text_size(text)
    local text_x = x + (width - text_size.x) / 2
    local text_y = y + (height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), color.white(255), text)

    return window:is_rect_clicked(btn_start, btn_end)
end

---Render the control bar above the tab bar (Apple HIG card style)
---@param ui_inst table The AstroUI instance (self)
---@param y_offset number Starting y position
---@return number New y_offset after control bar
local function render_control_bar(ui_inst, y_offset)
    local window = ui_inst.window
    local colors = ui_inst.colors
    local x_start = LAYOUT.padding_side
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)

    local running = _sentinel_gather:is_running()
    local paused = _sentinel_gather:is_paused()

    -- Status card background
    local card_top = y_offset
    local card_padding = 12
    local card_inner_height = 0

    -- Row 1: Profile name (if loaded)
    local profile_text = nil
    local bot_mgr = _sentinel_gather:get_bot_manager()
    local profile_mgr = bot_mgr and bot_mgr._modules and bot_mgr._modules.ProfileManager
    if profile_mgr and profile_mgr._profile_name then
        profile_text = profile_mgr._profile_name
        card_inner_height = card_inner_height + 22
    end

    -- Row 2: buttons + status
    local btn_h = 26
    card_inner_height = card_inner_height + btn_h + 8

    -- Row 3: overlay toggle
    card_inner_height = card_inner_height + 20

    -- Draw card background
    local card_bg = colors.bg_card or colors.section_bg
    window:render_rect_filled(
        vec2.new(x_start, card_top),
        vec2.new(x_start + content_width, card_top + card_inner_height + card_padding * 2),
        card_bg, LAYOUT.card_corner_radius)

    y_offset = card_top + card_padding

    -- Row 1: Profile name
    if profile_text then
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + LAYOUT.card_padding_h, y_offset),
            colors.text_secondary, "Profile: " .. profile_text)
        y_offset = y_offset + 22
    end

    -- Row 2: [Start/Stop] [Pause/Resume] + Status
    local inner_x = x_start + LAYOUT.card_padding_h
    local btn_w = 70
    local gap = 8

    -- Start/Stop button
    if not running then
        local bot_mgr_btn = _sentinel_gather:get_bot_manager()
        local nav_ok = bot_mgr_btn and bot_mgr_btn:is_navigation_available()
        local start_color = nav_ok
            and (colors.status_green or color.new(48, 209, 88, 255))
            or (colors.text_disabled or color.new(80, 80, 80, 255))
        local label = nav_ok and "Start" or "No Nav"
        if render_ctrl_button(window, inner_x, y_offset, btn_w, btn_h, label, colors, start_color) then
            if nav_ok then
                local selected_idx = _menu_elements.profile_combo:get()
                local profile = _ui_state.profiles[selected_idx]
                if profile and profile.path then
                    _sentinel_gather:start(profile.path)
                else
                    _sentinel_gather:start()
                end
            end
        end
    else
        local stop_color = colors.status_red or color.new(255, 69, 58, 255)
        if render_ctrl_button(window, inner_x, y_offset, btn_w, btn_h, "Stop", colors, stop_color) then
            _sentinel_gather:stop()
        end
    end

    -- Pause/Resume button
    local pause_x = inner_x + btn_w + gap
    local pause_text = paused and "Resume" or "Pause"
    local pause_color = paused
        and (colors.status_green or color.new(48, 209, 88, 255))
        or (colors.status_yellow or color.new(255, 214, 10, 255))
    if render_ctrl_button(window, pause_x, y_offset, btn_w, btn_h, pause_text, colors, pause_color) then
        if running then
            _sentinel_gather:toggle_pause()
        end
    end

    -- Status text (to the right of buttons)
    local state = _sentinel_gather:get_state()
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

    y_offset = y_offset + btn_h + 8

    -- Row 3: Overlay toggle (Apple toggle switch style)
    local overlay_on = _menu_elements.overlay_enabled_cb:get_state()
    local toggle_label = "Show Overlay"

    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(inner_x, y_offset + 2),
        overlay_on and colors.text_primary or colors.text_secondary, toggle_label)

    -- Toggle switch on the right side
    local toggle_w = LAYOUT.toggle_width
    local toggle_h = LAYOUT.toggle_height
    local toggle_x = x_start + content_width - LAYOUT.card_padding_h - toggle_w
    local toggle_y = y_offset + (20 - toggle_h) / 2
    local toggle_radius = toggle_h / 2

    local track_color = overlay_on
        and (colors.toggle_track_on or colors.secondary_accent)
        or (colors.toggle_track_off or colors.checkbox_inactive)
    window:render_rect_filled(
        vec2.new(toggle_x, toggle_y),
        vec2.new(toggle_x + toggle_w, toggle_y + toggle_h),
        track_color, toggle_radius)

    local thumb_size = LAYOUT.toggle_thumb_size
    local thumb_margin = LAYOUT.toggle_thumb_margin
    local thumb_x = overlay_on and (toggle_x + toggle_w - thumb_size - thumb_margin) or (toggle_x + thumb_margin)
    local thumb_color = colors.toggle_thumb or color.white(255)
    window:render_rect_filled(
        vec2.new(thumb_x, toggle_y + thumb_margin),
        vec2.new(thumb_x + thumb_size, toggle_y + thumb_margin + thumb_size),
        thumb_color, thumb_size / 2)

    -- Click area for toggle
    local toggle_start = vec2.new(inner_x, toggle_y)
    local toggle_end_pos = vec2.new(toggle_x + toggle_w, toggle_y + toggle_h)
    window:is_mouse_hovering_rect_block_movement(toggle_start, toggle_end_pos)

    if window:is_rect_clicked(toggle_start, toggle_end_pos) then
        _menu_elements.overlay_enabled_cb:set(not overlay_on)
    end

    y_offset = y_offset + 20

    -- End of card
    y_offset = card_top + card_inner_height + card_padding * 2 + LAYOUT.section_gap

    return y_offset
end

---Initialize the UI (called once)
---@param sentinel_gather table The SentinelGather module
---@param menu_elements table The menu elements table
---@param ui_state table The shared UI state (profiles, etc.)
function Window.init(sentinel_gather, menu_elements, ui_state)
    if _initialized then return end

    _sentinel_gather = sentinel_gather
    _menu_elements = menu_elements
    _ui_state = ui_state

    -- Create the AstroUI instance with Apple HIG theme
    _ui = AstroUI.new({
        id = "sentinel_gather",
        title = "Sentinel Gather",
        default_x = 100,
        default_y = 100,
        default_w = 480,
        default_h = 550,
        theme = "apple",
    })

    -- Set the before_tabs hook for the control bar
    _ui._before_tabs_fn = render_control_bar

    -- Register all tabs in order
    ProfileTab.register(_ui, menu_elements, ui_state)
    GatherTab.register(_ui, menu_elements)
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
---@return table|nil
function Window.get_ui()
    return _ui
end

return Window
