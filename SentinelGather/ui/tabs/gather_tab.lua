--[[
    Gather Tab - TabBuilder configuration for gathering settings
    Uses checkbox_grid and slider_list widgets from the shared UI library.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")

local GatherTab = {}

---Render profession status badges (custom render callback)
---@param ui rotation_settings_ui The UI instance (self)
---@param y_offset number Current y position
---@return number New y_offset
function GatherTab.render_status(ui, y_offset)
    local GatherBuddy = require("init")
    local node_scanner = GatherBuddy:get_module("NodeScanner")
    local has_herb = node_scanner and node_scanner:has_herbalism() or false
    local has_mining = node_scanner and node_scanner:has_mining() or false

    local window = ui.window
    local colors = ui.colors
    local LAYOUT = require("shared/rotation_settings_ui").LAYOUT
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    -- Herbalism status
    local herb_label = "Herbalism"
    local herb_status = has_herb and "LEARNED" or "NOT LEARNED"
    local herb_color = has_herb and color.new(100, 200, 100, 255) or color.new(200, 100, 100, 255)

    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start, y_offset), colors.text_primary, herb_label)

    local badge_x = x_start + 100
    local badge_start = vec2.new(badge_x, y_offset)
    local badge_end = vec2.new(badge_x + 100, y_offset + 18)
    window:render_rect_filled(badge_start, badge_end, herb_color, 2.0)
    local text_size = window:get_text_size(herb_status)
    local text_x = badge_x + (100 - text_size.x) / 2
    local text_y = y_offset + (18 - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), color.white(255), herb_status)

    y_offset = y_offset + LAYOUT.element_height + 2

    -- Mining status
    local mining_label = "Mining"
    local mining_status = has_mining and "LEARNED" or "NOT LEARNED"
    local mining_color = has_mining and color.new(100, 200, 100, 255) or color.new(200, 100, 100, 255)

    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start, y_offset), colors.text_primary, mining_label)

    badge_start = vec2.new(badge_x, y_offset)
    badge_end = vec2.new(badge_x + 100, y_offset + 18)
    window:render_rect_filled(badge_start, badge_end, mining_color, 2.0)
    text_size = window:get_text_size(mining_status)
    text_x = badge_x + (100 - text_size.x) / 2
    text_y = y_offset + (18 - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(text_x, text_y), color.white(255), mining_status)

    y_offset = y_offset + LAYOUT.element_height + LAYOUT.section_padding_bottom

    -- Apply skill settings if scanner available
    if node_scanner then
        node_scanner:_apply_skill_settings()
    end

    return y_offset
end

---Register the gather tab with the UI
---@param ui any RotationSettingsUI instance
---@param menu_elements table Menu elements table
function GatherTab.register(ui, menu_elements)
    ui:add_tab({ id = "gather", label = "Gather" }, function(t)
        -- Profession status (custom rendered)
        t:custom_render({ render_fn = GatherTab.render_status })

        -- Gathering types
        t:checkbox_grid({
            label = "Gathering Types",
            columns = 1,
            elements = {
                { element = menu_elements.gather_herbs_cb, label = "Gather Herbs" },
                { element = menu_elements.gather_ores_cb, label = "Gather Ores" },
                { element = menu_elements.check_skills_cb, label = "Auto-disable if no skill" },
            }
        })

        -- Gathering parameters
        t:slider_list({
            label = "Parameters",
            elements = {
                { element = menu_elements.node_search_radius_slider, label = "Search Radius", suffix = " yd" },
                { element = menu_elements.gather_timeout_slider, label = "Gather Timeout", suffix = "s" },
                { element = menu_elements.mount_threshold_slider, label = "Mount Distance", suffix = " yd" },
            }
        })
    end)
end

return GatherTab
