local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("shared/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local OverviewTab = {}

local _controller = nil

local function render_button(window, x, y, width, height, text, colors, accent_color)
    local btn_start = vec2.new(x, y)
    local btn_end = vec2.new(x + width, y + height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local bg = is_hovered and accent_color or colors.section_bg
    window:render_rect_filled(btn_start, btn_end, bg, 3.0)
    window:render_rect(btn_start, btn_end, accent_color, 3.0, 1.0)

    local text_size = window:get_text_size(text)
    local text_x = x + (width - text_size.x) / 2
    local text_y = y + (height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(text_x, text_y), color.white(245), text)

    return window:is_rect_clicked(btn_start, btn_end)
end

local function render_stat_row(window, x, y, label, value, colors)
    local label_width = 185
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.text_secondary, label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + label_width, y), colors.text_primary, value)
    return y + 18
end

function OverviewTab.render(ui, y_offset)
    if not _controller then
        return y_offset
    end

    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local btn_h = 24
    local btn_w = 92
    local btn_gap = 8

    local running = _controller:is_running() == true
    local start_text = running and "Stop" or "Start"
    local start_color = running and color.new(180, 70, 70, 255) or color.new(70, 165, 90, 255)
    if render_button(window, x_start, y_offset, btn_w, btn_h, start_text, colors, start_color) then
        if running then
            _controller:stop()
        else
            _controller:start()
        end
    end

    if render_button(window, x_start + btn_w + btn_gap, y_offset, btn_w + 18, btn_h, "Reset Stats", colors,
            color.new(110, 140, 200, 255)) then
        if _controller.reset_runtime_stats then
            _controller:reset_runtime_stats()
        end
    end

    if render_button(window, x_start + (2 * btn_w) + btn_gap + 18 + btn_gap, y_offset, btn_w + 36, btn_h, "Clear Runtime BL",
            colors, color.new(185, 140, 70, 255)) then
        if _controller.clear_runtime_blacklists then
            local guid_count, zone_count = _controller:clear_runtime_blacklists()
            core.log(string.format("[GrindBuddy] Cleared runtime blacklist: %d guid, %d zones", guid_count or 0,
                zone_count or 0))
        end
    end

    y_offset = y_offset + btn_h + 10

    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.primary_accent, "Session")
    y_offset = y_offset + 20

    local stats = _controller.get_runtime_stats and _controller:get_runtime_stats() or nil
    if not stats then
        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_disabled,
            "No runtime stats available")
        return y_offset + 18 + LAYOUT.section_padding_bottom
    end

    y_offset = render_stat_row(window, x_start, y_offset, "Duration", tostring(stats.duration_formatted or "00:00:00"), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Kills", tostring(stats.kills or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Kills / Hour", string.format("%.1f", stats.kills_per_hour or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Deaths", tostring(stats.deaths or 0), colors)

    y_offset = y_offset + 6
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.primary_accent, "Loot / Vendor")
    y_offset = y_offset + 20
    y_offset = render_stat_row(window, x_start, y_offset, "Loot Attempts", tostring(stats.loot_attempts or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Loot Attempts / Hour",
        string.format("%.1f", stats.loot_attempts_per_hour or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Vendor Runs",
        string.format("%d (%d done)", stats.vendor_runs or 0, stats.vendor_completions or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Junk Sold", tostring(stats.junk_sold or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Repairs", tostring(stats.repairs or 0), colors)

    y_offset = y_offset + 6
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.primary_accent, "Runtime")
    y_offset = y_offset + 20
    local free_slots_text = "unknown"
    if stats.free_slots ~= nil and stats.total_slots ~= nil then
        free_slots_text = string.format("%d / %d", stats.free_slots, stats.total_slots)
    end
    y_offset = render_stat_row(window, x_start, y_offset, "Free Slots", free_slots_text, colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Blacklist GUID", tostring(stats.blacklisted_guid_count or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Blacklist Zones", tostring(stats.blacklisted_zone_count or 0), colors)
    y_offset = render_stat_row(window, x_start, y_offset, "Persistent Blackspots", tostring(stats.blackspot_count or 0), colors)

    return y_offset + LAYOUT.section_padding_bottom
end

function OverviewTab.register(ui, controller)
    _controller = controller
    ui:add_tab({ id = "overview", label = "Overview" }, function(t)
        t:custom_render({ render_fn = OverviewTab.render })
    end)
end

return OverviewTab
