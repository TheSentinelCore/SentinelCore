--[[
    Safety Tab - TabBuilder configuration for safety settings
    Uses slider_list and checkbox_grid widgets, plus custom render for debug section.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")

local SafetyTab = {}

---Render debug section (custom render callback)
---@param ui rotation_settings_ui The UI instance
---@param y_offset number Current y position
---@return number New y_offset
function SafetyTab.render_debug(ui, y_offset)
    local GatherBuddy = require("init")
    local window = ui.window
    local colors = ui.colors
    local LAYOUT = require("shared/rotation_settings_ui").LAYOUT
    local x_start = LAYOUT.padding_side
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)

    y_offset = y_offset + LAYOUT.section_padding_top

    -- Run Tests button
    local btn_width = 120
    local btn_height = 24
    local btn_start = vec2.new(x_start, y_offset)
    local btn_end = vec2.new(x_start + btn_width, y_offset + btn_height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local btn_color = is_hovered and colors.primary_accent or colors.section_bg
    window:render_rect_filled(btn_start, btn_end, btn_color, 2.0)
    window:render_rect(btn_start, btn_end, colors.section_border, 2.0, 1.0)

    local btn_text = "Run Tests"
    local text_size = window:get_text_size(btn_text)
    local text_x = x_start + (btn_width - text_size.x) / 2
    local text_y = y_offset + (btn_height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), colors.text_primary, btn_text)

    if window:is_rect_clicked(btn_start, btn_end) then
        GatherBuddy:run_tests()
    end

    y_offset = y_offset + btn_height + LAYOUT.element_spacing

    -- Module count
    local bot_mgr = GatherBuddy:get_bot_manager()
    if bot_mgr then
        local module_count = bot_mgr:get_module_count() or 0
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, y_offset), colors.text_disabled,
            "Modules loaded: " .. module_count)
        y_offset = y_offset + LAYOUT.element_height
    end

    return y_offset + LAYOUT.section_padding_bottom
end

---Register the safety tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu_elements table Menu elements table
function SafetyTab.register(ui, menu_elements)
    ui:add_tab({ id = "safety", label = "Safety" }, function(t)
        -- Enemy detection
        t:slider_list({
            label = "Enemy Detection",
            elements = {
                { element = menu_elements.enemy_scan_radius_slider, label = "Scan Radius", suffix = " yd" },
            }
        })

        t:checkbox_grid({
            label = "Avoidance",
            columns = 1,
            elements = {
                { element = menu_elements.skip_if_enemies_cb, label = "Skip Node if Enemies Near" },
            }
        })

        -- Combat response
        t:slider_list({
            label = "Combat Response",
            elements = {
                { element = menu_elements.flee_health_slider, label = "Flee Health", suffix = "%" },
            }
        })

        -- Debug section
        t:custom_render({ render_fn = SafetyTab.render_debug })
    end)
end

return SafetyTab
