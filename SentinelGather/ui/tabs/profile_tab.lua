--[[
    Profile Tab - Custom rendered profile management
    Handles profile selection, loading, waypoint editing, and saving.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")

local ProfileTab = {}

-- Local state for the profile editor collapse
local _editor_open = false

---Render a styled button and return true if clicked
---@param window any Window object
---@param x number X position
---@param y number Y position
---@param width number Button width
---@param height number Button height
---@param text string Button label
---@param colors table Theme colors
---@param accent_color any|nil Optional accent color override
---@return boolean clicked
local function render_button(window, x, y, width, height, text, colors, accent_color)
    local btn_start = vec2.new(x, y)
    local btn_end = vec2.new(x + width, y + height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local bg = is_hovered and (accent_color or colors.primary_accent) or colors.section_bg
    window:render_rect_filled(btn_start, btn_end, bg, 2.0)
    window:render_rect(btn_start, btn_end, accent_color or colors.section_border, 2.0, 1.0)

    local text_size = window:get_text_size(text)
    local text_x = x + (width - text_size.x) / 2
    local text_y = y + (height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), colors.text_primary, text)

    return window:is_rect_clicked(btn_start, btn_end)
end

---Render the profile tab content
---@param ui rotation_settings_ui The UI instance
---@param y_offset number Current y position
---@return number New y_offset
function ProfileTab.render(ui, y_offset)
    local SentinelGather = require("init")
    local window = ui.window
    local colors = ui.colors
    local lib = require("shared/rotation_settings_ui")
    local LAYOUT = lib.LAYOUT
    local x_start = LAYOUT.padding_side
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)

    -- Access shared state from window module
    local ui_state = ProfileTab._ui_state
    local menu_elements = ProfileTab._menu_elements
    if not ui_state or not menu_elements then
        return y_offset
    end

    y_offset = y_offset + LAYOUT.section_padding_top

    -- Profile selector row: [dropdown area] [Load button]
    local load_btn_width = 60
    local combo_width = content_width - load_btn_width - 8

    local profiles = ui_state.profiles or {}
    local profile_names = {}
    for _, p in ipairs(profiles) do
        table.insert(profile_names, p.name)
    end

    local selected_idx = menu_elements.profile_combo:get()
    local selected_name = profile_names[selected_idx] or "Select profile..."
    local profile = profiles[selected_idx]

    -- Combo box (click to cycle)
    local combo_start = vec2.new(x_start, y_offset)
    local combo_end = vec2.new(x_start + combo_width, y_offset + LAYOUT.element_height)

    local combo_hovered = window:is_mouse_hovering_rect(combo_start, combo_end)
    window:is_mouse_hovering_rect_block_movement(combo_start, combo_end)

    local combo_bg = combo_hovered and colors.section_bg or colors.slider_bg
    window:render_rect_filled(combo_start, combo_end, combo_bg, 2.0)
    window:render_rect(combo_start, combo_end, colors.section_border, 2.0, 1.0)

    -- Truncate name if needed
    local max_text_w = combo_width - 20
    local display_name = selected_name
    local name_size = window:get_text_size(display_name)
    if name_size.x > max_text_w then
        while #display_name > 1 do
            display_name = string.sub(display_name, 1, -2)
            if window:get_text_size(display_name .. "...").x <= max_text_w then
                display_name = display_name .. "..."
                break
            end
        end
    end

    local name_y = y_offset + (LAYOUT.element_height - window:get_text_size(display_name).y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start + 8, name_y), colors.text_primary, display_name)

    -- Arrow indicator
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start + combo_width - 18, name_y), colors.text_secondary, "v")

    -- Click to cycle
    if window:is_rect_clicked(combo_start, combo_end) and #profiles > 0 then
        local next_idx = (selected_idx % #profiles) + 1
        menu_elements.profile_combo:set(next_idx)
    end

    -- Load button
    local load_x = x_start + combo_width + 8
    if render_button(window, load_x, y_offset, load_btn_width, LAYOUT.element_height,
        "Load", colors, colors.primary_accent) then
        if profile and profile.path then
            SentinelGather:load_profile(profile.path)
        end
    end

    y_offset = y_offset + LAYOUT.element_height + LAYOUT.element_spacing

    -- Profile info
    if profile and profile.path then
        local info_text = string.format("Zone: %s  |  Waypoints: %d",
            profile.zone or "Unknown", profile.waypoint_count or 0)
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, y_offset), colors.text_secondary, info_text)
        y_offset = y_offset + LAYOUT.element_height + 4
    end

    -- Separator
    local sep_start = vec2.new(x_start, y_offset)
    local sep_end = vec2.new(x_start + content_width, y_offset + 2)
    window:render_rect_filled(sep_start, sep_end, colors.separator, 0)
    y_offset = y_offset + 6

    -- Profile Editor header (collapsible)
    local header_start = vec2.new(x_start, y_offset)
    local header_end = vec2.new(x_start + content_width, y_offset + LAYOUT.element_height)

    local header_hovered = window:is_mouse_hovering_rect(header_start, header_end)
    window:is_mouse_hovering_rect_block_movement(header_start, header_end)

    local header_bg = header_hovered and colors.section_bg or colors.slider_bg
    window:render_rect_filled(header_start, header_end, header_bg, 2.0)
    window:render_rect(header_start, header_end, colors.section_border, 2.0, 1.0)

    local arrow = _editor_open and "v" or ">"
    local header_text = arrow .. "  Profile Editor"
    local ht_y = y_offset + (LAYOUT.element_height - window:get_text_size(header_text).y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start + 8, ht_y), colors.text_primary, header_text)

    if window:is_rect_clicked(header_start, header_end) then
        _editor_open = not _editor_open
    end

    y_offset = y_offset + LAYOUT.element_height + LAYOUT.element_spacing

    -- Editor content (if open)
    if _editor_open then
        local bot_mgr = SentinelGather:get_bot_manager()
        local profile_mgr = bot_mgr and bot_mgr._modules and bot_mgr._modules.ProfileManager
        local player = core.object_manager.get_local_player()

        -- Waypoint count
        local wp_count = profile_mgr and profile_mgr:get_waypoint_count() or 0
        local current_idx_wp = profile_mgr and profile_mgr:get_current_waypoint_index() or 0
        local wp_info = string.format("Waypoints: %d  (current: %d)", wp_count, current_idx_wp)
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + 8, y_offset), colors.text_primary, wp_info)
        y_offset = y_offset + LAYOUT.element_height

        -- Waypoint list (first 10)
        if profile_mgr and wp_count > 0 then
            local waypoints = profile_mgr._waypoints or {}
            local show_count = math.min(wp_count, 10)
            for i = 1, show_count do
                local wp = waypoints[i]
                if wp then
                    local wp_text = string.format("%d: (%.0f, %.0f, %.0f) [%s]",
                        i, wp.x, wp.y, wp.z, wp.type or "path")
                    local wp_color = (i == current_idx_wp) and color.yellow(255) or colors.text_disabled
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x_start + 16, y_offset), wp_color, wp_text)
                    y_offset = y_offset + 18
                end
            end
            if wp_count > 10 then
                local more_text = string.format("... and %d more", wp_count - 10)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x_start + 16, y_offset), colors.text_disabled, more_text)
                y_offset = y_offset + 18
            end
            y_offset = y_offset + 4
        end

        -- Add Waypoints section
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + 8, y_offset), color.new(100, 200, 100, 255), "Add Waypoints")
        y_offset = y_offset + LAYOUT.element_height

        local btn_w = (content_width - 16) / 2
        local btn_h = 22

        -- Add Path Waypoint button
        if render_button(window, x_start + 8, y_offset, btn_w - 4, btn_h,
            "Add Path WP", colors, color.new(100, 200, 100, 200)) then
            if player and player:is_valid() and profile_mgr then
                local pos = player:get_position()
                local id = profile_mgr:add_waypoint_at_position(pos, "path")
                if id then core.log("[SentinelGather] Added path waypoint #" .. id) end
            end
        end

        -- Add Hotspot button
        if render_button(window, x_start + 8 + btn_w + 4, y_offset, btn_w - 4, btn_h,
            "Add Hotspot", colors, color.new(100, 200, 100, 200)) then
            if player and player:is_valid() and profile_mgr then
                local pos = player:get_position()
                local radius = menu_elements.hotspot_radius_slider:get()
                local id = profile_mgr:add_waypoint_at_position(pos, "hotspot", radius)
                if id then core.log("[SentinelGather] Added hotspot #" .. id) end
            end
        end

        y_offset = y_offset + btn_h + LAYOUT.element_spacing

        -- Hotspot radius slider (simple inline)
        local slider_label = "Hotspot Radius"
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + 8, y_offset + 1), colors.text_secondary, slider_label)
        local slider_val = tostring(menu_elements.hotspot_radius_slider:get())
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + content_width - 40, y_offset + 1), colors.text_primary, slider_val)
        y_offset = y_offset + LAYOUT.element_height

        -- Manage Waypoints section
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + 8, y_offset), color.new(255, 100, 100, 255), "Manage Waypoints")
        y_offset = y_offset + LAYOUT.element_height

        -- Remove / Clear buttons
        local danger_color = color.new(200, 60, 60, 200)
        if render_button(window, x_start + 8, y_offset, btn_w - 4, btn_h,
            "Remove Current", colors, danger_color) then
            if profile_mgr then
                local current_wp = profile_mgr:get_current_waypoint()
                if current_wp then
                    profile_mgr:remove_waypoint(current_wp.id, true)
                    core.log("[SentinelGather] Removed waypoint")
                end
            end
        end

        if render_button(window, x_start + 8 + btn_w + 4, y_offset, btn_w - 4, btn_h,
            "Clear All", colors, danger_color) then
            if profile_mgr then
                profile_mgr:clear_waypoints()
                core.log("[SentinelGather] Cleared all waypoints")
            end
        end

        y_offset = y_offset + btn_h + LAYOUT.element_spacing + 4

        -- Save button (full width)
        if render_button(window, x_start + 8, y_offset, content_width - 16, btn_h,
            "Save Profile", colors, colors.primary_accent) then
            if profile_mgr then
                local success = profile_mgr:save_current_profile()
                if success then
                    core.log("[SentinelGather] Profile saved")
                else
                    core.log_error("[SentinelGather] Failed to save profile")
                end
            end
        end

        y_offset = y_offset + btn_h + LAYOUT.element_spacing
    end

    return y_offset + LAYOUT.section_padding_bottom
end

---Register the profile tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu_elements table Menu elements table
---@param ui_state table UI state table (profiles, selected_profile_index, etc.)
function ProfileTab.register(ui, menu_elements, ui_state)
    ProfileTab._menu_elements = menu_elements
    ProfileTab._ui_state = ui_state

    ui:add_tab({ id = "profile", label = "Profile" }, function(t)
        t:custom_render({ render_fn = ProfileTab.render })
    end)
end

return ProfileTab
