--[[
    Statistics Tab - Custom rendered statistics display
    Shows session stats and current path info using window:render_* APIs.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")

local StatsTab = {}

---Render a labeled stat row
---@param window any The window object
---@param x number X position
---@param y number Y position
---@param label string The label text
---@param value string The value text
---@param label_color any Color for label
---@param value_color any Color for value
---@return number New y position
local function render_stat_row(window, x, y, label, value, label_color, value_color)
    local LAYOUT = require("shared/rotation_settings_ui").LAYOUT
    local label_width = 140

    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x, y), label_color, label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + label_width, y), value_color, value)

    return y + LAYOUT.element_height
end

---Render the statistics tab content
---@param ui rotation_settings_ui The UI instance
---@param y_offset number Current y position
---@return number New y_offset
function StatsTab.render(ui, y_offset)
    local GatherBuddy = require("init")
    local window = ui.window
    local colors = ui.colors
    local LAYOUT = require("shared/rotation_settings_ui").LAYOUT
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    -- Section header: Session Statistics
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start, y_offset), colors.primary_accent, "Session Statistics")
    y_offset = y_offset + LAYOUT.element_height + 4

    local stats = GatherBuddy:get_statistics()

    if stats then
        y_offset = render_stat_row(window, x_start, y_offset,
            "Duration:", stats.duration_formatted or "0:00",
            colors.text_secondary, colors.text_primary)

        y_offset = render_stat_row(window, x_start, y_offset,
            "Nodes Gathered:", tostring(stats.nodes_gathered or 0),
            colors.text_secondary, colors.text_primary)

        y_offset = render_stat_row(window, x_start, y_offset,
            "Nodes/Hour:", string.format("%.1f", stats.nodes_per_hour or 0),
            colors.text_secondary, colors.text_primary)

        y_offset = render_stat_row(window, x_start, y_offset,
            "Total Items:", tostring(stats.total_items or 0),
            colors.text_secondary, colors.text_primary)

        local deaths = stats.deaths or 0
        local death_color = deaths > 0 and color.new(255, 100, 100, 255) or colors.text_primary
        y_offset = render_stat_row(window, x_start, y_offset,
            "Deaths:", tostring(deaths),
            colors.text_secondary, death_color)
    else
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, y_offset), colors.text_disabled, "No statistics available")
        y_offset = y_offset + LAYOUT.element_height
    end

    y_offset = y_offset + LAYOUT.section_spacing

    -- Section header: Current Path
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start, y_offset), colors.primary_accent, "Current Path")
    y_offset = y_offset + LAYOUT.element_height + 4

    local bot_mgr = GatherBuddy:get_bot_manager()
    local movement = bot_mgr and bot_mgr._modules and bot_mgr._modules.Movement

    if movement and movement:get_current_path() then
        local path_count = #movement:get_current_path()
        local path_idx = movement:get_path_index()

        -- Progress bar
        local window_size = window:get_size()
        local bar_width = window_size.x - (2 * LAYOUT.padding_side)
        local bar_height = 14
        local bar_start = vec2.new(x_start, y_offset)
        local bar_end = vec2.new(x_start + bar_width, y_offset + bar_height)

        -- Background
        window:render_rect_filled(bar_start, bar_end, colors.slider_bg, 2.0)

        -- Fill
        local progress = path_count > 0 and (path_idx / path_count) or 0
        local fill_width = bar_width * math.max(0, math.min(1, progress))
        window:render_rect_filled(bar_start,
            vec2.new(x_start + fill_width, y_offset + bar_height),
            colors.slider_fill, 2.0)

        -- Border
        window:render_rect(bar_start, bar_end, colors.primary_accent, 2.0, 1.0)

        -- Progress text centered
        local progress_text = string.format("%d / %d", path_idx, path_count)
        local text_size = window:get_text_size(progress_text)
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start + (bar_width - text_size.x) / 2, y_offset + (bar_height - text_size.y) / 2),
            colors.text_primary, progress_text)

        y_offset = y_offset + bar_height + LAYOUT.element_spacing

        -- Target coordinates
        if movement._current_destination then
            local dest = movement._current_destination
            local target_text = string.format("Target: (%.0f, %.0f, %.0f)", dest.x, dest.y, dest.z)
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x_start, y_offset), colors.text_secondary, target_text)
            y_offset = y_offset + LAYOUT.element_height
        end
    else
        window:render_text(enums.window_enums.font_id.FONT_SMALL,
            vec2.new(x_start, y_offset), colors.text_disabled, "No active path")
        y_offset = y_offset + LAYOUT.element_height
    end

    return y_offset + LAYOUT.section_padding_bottom
end

---Register the stats tab with the UI
---@param ui any RotationSettingsUI instance
function StatsTab.register(ui)
    ui:add_tab({ id = "stats", label = "Stats" }, function(t)
        t:custom_render({ render_fn = StatsTab.render })
    end)
end

return StatsTab
