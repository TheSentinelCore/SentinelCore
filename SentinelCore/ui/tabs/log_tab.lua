--[[
    SentinelCore Log Tab

    Scrollable runtime log viewer with Clear button.
]]

local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local color = require("common/color")
local AstroUI = require("lib/AstroUI")
local Logger = require("core/Logger")

local LAYOUT = AstroUI.LAYOUT

local log_tab = {}

local LOG_COLORS = {
    DEBUG   = color.new(128, 128, 128, 255),
    INFO    = color.new(255, 255, 255, 255),
    WARN    = color.new(255, 204,   0, 255),
    WARNING = color.new(255, 204,   0, 255),
    ERROR   = color.new(255,  77,  77, 255),
}

local function format_hms_log(secs)
    local s = math.floor(secs or 0)
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
end

---@param base_color color
---@param amount number
---@return color
local function lighten_color(base_color, amount)
    local r, g, b, a = base_color:get()
    return color.new(
        math.min(255, r + amount),
        math.min(255, g + amount),
        math.min(255, b + amount),
        a
    )
end

---@param t any AstroUI tab builder
---@param client SentinelClient
function log_tab.render(t, client)

    -- 1. Clear button
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)
            local button_h = 26

            local btn_start = vec2.new(x, y_offset)
            local btn_end = vec2.new(x + width, y_offset + button_h)
            local hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
            if hovered then
                window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)
            end

            local bg = hovered and lighten_color(colors.primary_accent, 15) or colors.primary_accent
            window:render_rect_filled(btn_start, btn_end, bg, 8)

            local label = "Clear Log"
            local ts = window:get_text_size(label)
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x + (width - ts.x) / 2, y_offset + (button_h - ts.y) / 2),
                colors.text_primary, label)

            if hovered and window:is_rect_clicked(btn_start, btn_end) then
                Logger.clear_history()
            end

            return y_offset + button_h + 6
        end,
    })

    -- 2. Log entries
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)
            local line_h = 16

            local win_h = window:get_size().y
            local available_h = math.max(line_h, win_h - y_offset - LAYOUT.padding_bottom)
            local max_lines = math.floor(available_h / line_h)

            local entries = Logger.get_history(50)
            local shown = {}
            for i = #entries, 1, -1 do
                shown[#shown + 1] = entries[i]
                if #shown >= max_lines then break end
            end

            for i = 1, #shown do
                local entry = shown[i]
                local lvl = tostring(entry.level or "INFO"):upper()
                local line = string.format("[%s] [%s] %s: %s",
                    format_hms_log(entry.timestamp),
                    lvl,
                    tostring(entry.source or ""),
                    tostring(entry.message or ""))
                local col = LOG_COLORS[lvl] or colors.text_secondary
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), col, line)
                y_offset = y_offset + line_h
            end

            if #shown == 0 then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_disabled, "No log entries")
                y_offset = y_offset + line_h
            end

            return y_offset
        end,
    })
end

return log_tab
