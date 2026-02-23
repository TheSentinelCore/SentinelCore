--[[
    Gather Tab - AstroUI card-based gathering settings
    Uses row_list (toggle, stepper) and custom_render for profession badges.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("lib/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local GatherTab = {}

---Render profession status badges (custom render callback)
---@param ui_inst table The AstroUI instance (self)
---@param y_offset number Current y position
---@return number New y_offset
function GatherTab.render_status(ui_inst, y_offset)
    local SentinelGather = require("init")
    local node_scanner = SentinelGather:get_module("NodeScanner")
    local has_herb = node_scanner and node_scanner:has_herbalism() or false
    local has_mining = node_scanner and node_scanner:has_mining() or false

    local window = ui_inst.window
    local colors = ui_inst.colors
    local window_size = window:get_size()
    local x_start = LAYOUT.padding_side + LAYOUT.card_padding_h
    local content_width = window_size.x - 2 * (LAYOUT.padding_side + LAYOUT.card_padding_h)

    -- Badge rendering helper
    local function render_badge(label, is_learned, y)
        local status_text = is_learned and "LEARNED" or "NOT LEARNED"
        local badge_color = is_learned
            and (colors.status_green or color.new(48, 209, 88, 255))
            or (colors.status_red or color.new(255, 69, 58, 255))

        -- Label on left
        local label_y = y + (LAYOUT.row_height - window:get_text_size(label).y) / 2
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, label_y), colors.text_primary, label)

        -- Status badge on right
        local badge_w = 100
        local badge_h = 22
        local badge_x = x_start + content_width - badge_w
        local badge_y = y + (LAYOUT.row_height - badge_h) / 2

        window:render_rect_filled(
            vec2.new(badge_x, badge_y),
            vec2.new(badge_x + badge_w, badge_y + badge_h),
            badge_color, 6.0)

        local text_size = window:get_text_size(status_text)
        local text_x = badge_x + (badge_w - text_size.x) / 2
        local text_y = badge_y + (badge_h - text_size.y) / 2
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(text_x, text_y), color.white(255), status_text)

        return y + LAYOUT.row_height
    end

    y_offset = render_badge("Herbalism", has_herb, y_offset)

    -- Separator between rows
    local sep_color = colors.row_separator or colors.separator
    local sep_x = x_start + LAYOUT.row_separator_inset
    window:render_rect_filled(
        vec2.new(sep_x, y_offset),
        vec2.new(x_start + content_width, y_offset + LAYOUT.row_separator_height),
        sep_color, 0)
    y_offset = y_offset + LAYOUT.row_separator_height

    y_offset = render_badge("Mining", has_mining, y_offset)

    -- Apply skill settings if scanner available
    if node_scanner then
        node_scanner:_apply_skill_settings()
    end

    return y_offset
end

---Register the gather tab with the UI
---@param ui any AstroUI instance
---@param menu_elements table Menu elements table
function GatherTab.register(ui, menu_elements)
    ui:add_tab({ id = "gather", label = "Gather" }, function(t)
        -- Profession status (custom rendered badges)
        t:custom_render({
            label = "Professions",
            render_fn = GatherTab.render_status,
        })

        -- Gathering types (Apple toggle switches)
        t:row_list({
            label = "Gathering Types",
            elements = {
                { type = "toggle", label = "Gather Herbs", element = menu_elements.gather_herbs_cb },
                { type = "toggle", label = "Gather Ores", element = menu_elements.gather_ores_cb },
                { type = "toggle", label = "Auto-disable if no skill", element = menu_elements.check_skills_cb },
            },
        })

        -- Gathering parameters (stepper controls)
        t:row_list({
            label = "Parameters",
            elements = {
                {
                    type = "stepper", label = "Search Radius",
                    element = menu_elements.node_search_radius_slider,
                    min = 20, max = 150, step = 5, suffix = " yd",
                },
                {
                    type = "stepper", label = "Gather Timeout",
                    element = menu_elements.gather_timeout_slider,
                    min = 5, max = 30, step = 0.5, suffix = "s",
                },
                {
                    type = "stepper", label = "Mount Distance",
                    element = menu_elements.mount_threshold_slider,
                    min = 10, max = 100, step = 5, suffix = " yd",
                },
            },
        })
    end)
end

return GatherTab
