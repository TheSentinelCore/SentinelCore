--[[
    Safety Tab - AstroUI card-based safety settings
    Uses row_list (toggle, stepper) with conditional visibility and custom debug section.
]]

local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("lib/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local SafetyTab = {}

---Render debug section (custom render callback)
---@param ui_inst table The AstroUI instance
---@param y_offset number Current y position
---@return number New y_offset
function SafetyTab.render_debug(ui_inst, y_offset)
    local SentinelGather = require("init")
    local window = ui_inst.window
    local colors = ui_inst.colors
    local x_start = LAYOUT.padding_side + LAYOUT.card_padding_h

    -- Run Tests button (Apple HIG rounded rect)
    local btn_width = 120
    local btn_height = 26
    local btn_start = vec2.new(x_start, y_offset)
    local btn_end = vec2.new(x_start + btn_width, y_offset + btn_height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local btn_color = is_hovered
        and colors.primary_accent
        or (colors.bg_elevated or colors.section_bg)
    window:render_rect_filled(btn_start, btn_end, btn_color, 8.0)
    window:render_rect(btn_start, btn_end, colors.primary_accent, 8.0, 1.0)

    local btn_text = "Run Tests"
    local text_size = window:get_text_size(btn_text)
    local text_x = x_start + (btn_width - text_size.x) / 2
    local text_y = y_offset + (btn_height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), colors.text_primary, btn_text)

    if window:is_rect_clicked(btn_start, btn_end) then
        SentinelGather:run_tests()
    end

    y_offset = y_offset + btn_height + 10

    -- Module count
    local bot_mgr = SentinelGather:get_bot_manager()
    if bot_mgr then
        local module_count = bot_mgr:get_module_count() or 0
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, y_offset), colors.text_disabled,
            "Modules loaded: " .. module_count)
        y_offset = y_offset + LAYOUT.element_height
    end

    return y_offset
end

---Register the safety tab with the UI
---@param ui any AstroUI instance
---@param menu_elements table Menu elements table
function SafetyTab.register(ui, menu_elements)
    ui:add_tab({ id = "safety", label = "Safety" }, function(t)
        -- Enemy detection (stepper)
        t:row_list({
            label = "Enemy Detection",
            elements = {
                {
                    type = "stepper", label = "Scan Radius",
                    element = menu_elements.enemy_scan_radius_slider,
                    min = 10, max = 60, step = 5, suffix = " yd",
                },
            },
        })

        -- Avoidance (toggle)
        t:row_list({
            label = "Avoidance",
            elements = {
                { type = "toggle", label = "Skip Node if Enemies Near", element = menu_elements.skip_if_enemies_cb },
            },
        })

        -- Combat response (stepper)
        t:row_list({
            label = "Combat Response",
            elements = {
                {
                    type = "stepper", label = "Flee Health",
                    element = menu_elements.flee_health_slider,
                    min = 10, max = 50, step = 5, suffix = "%",
                },
            },
        })

        -- Anti-detection (toggles)
        t:row_list({
            label = "Anti-Detection",
            elements = {
                { type = "toggle", label = "Random Pauses", element = menu_elements.random_pause_cb },
                { type = "toggle", label = "Random Jumps", element = menu_elements.random_jump_cb },
            },
        })

        -- Pause intervals (conditional on random_pause being on)
        t:row_list({
            label = "Pause Intervals",
            visible_when = function() return menu_elements.random_pause_cb:get_state() end,
            elements = {
                {
                    type = "stepper", label = "Min Seconds",
                    element = menu_elements.pause_interval_min_slider,
                    min = 15, max = 120, step = 5, suffix = "s",
                },
                {
                    type = "stepper", label = "Max Seconds",
                    element = menu_elements.pause_interval_max_slider,
                    min = 30, max = 180, step = 5, suffix = "s",
                },
            },
        })

        -- Debug section
        t:custom_render({
            label = "Debug",
            render_fn = SafetyTab.render_debug,
        })
    end)
end

return SafetyTab
