local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then
        return mod
    end
    return fallback
end

local vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y)
        return { x = x or 0, y = y or 0 }
    end,
})

local enums = require_or("common/enums", {
    window_enums = {
        font_id = {
            FONT_SMALL = 0,
            FONT_SEMI_BIG = 0,
        },
    },
})

local color = require_or("common/color", {
    new = function(r, g, b, a)
        return {
            r = r or 0,
            g = g or 0,
            b = b or 0,
            a = a or 255,
            get = function(self)
                return self.r, self.g, self.b, self.a
            end,
        }
    end,
})
local SentinelUI = require("lib/SentinelUI")

local LAYOUT = SentinelUI.LAYOUT

local recorder_tab = {}

local _last_action = nil
local _default_path = "StrathDuoMage/profiles/strath_duo_default.json"
local _template_path = "StrathDuoMage/profiles/strath_duo_anniversary_template.json"

local function lighten_color(base_color, amount)
    local r, g, b, a = base_color:get()
    return color.new(
        math.min(255, r + amount),
        math.min(255, g + amount),
        math.min(255, b + amount),
        a
    )
end

local function render_button(ctx, window, colors, x, y, w, h, label, enabled, accent, tooltip)
    local start_pos = vec2.new(x, y)
    local end_pos = vec2.new(x + w, y + h)
    local hovered = window:is_mouse_hovering_rect(start_pos, end_pos)
    if hovered then
        window:is_mouse_hovering_rect_block_movement(start_pos, end_pos)
        if tooltip and tooltip ~= "" then
            ctx._tooltip = tooltip
        end
    end
    local bg = enabled and (hovered and lighten_color(accent, 18) or accent) or colors.checkbox_inactive
    window:render_rect_filled(start_pos, end_pos, bg, 8)
    local ts = window:get_text_size(label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + (w - ts.x) / 2, y + (h - ts.y) / 2),
        enabled and colors.text_primary or colors.text_disabled, label)
    return enabled and hovered and window:is_rect_clicked(start_pos, end_pos)
end

---@param t any
---@param bot StrathDuoBot
function recorder_tab.render(t, bot)
    local snapshot = (bot and bot.get_snapshot and bot:get_snapshot()) or {}
    local record = snapshot.record or {}

    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local headline = string.format(
                "Record: %s | segment %d/%d (%s) | points=%d",
                record.active and "active" or "inactive",
                tonumber(record.segment_index) or 0,
                tonumber(record.segment_count) or 0,
                tostring(record.segment_id or "-"),
                tonumber(record.pull_point_count) or 0
            )
            window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x, y_offset), colors.text_primary, headline)
            y_offset = y_offset + 22

            local path_text = "Profile: " .. tostring(record.profile_path or "")
            window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), colors.text_secondary, path_text)
            y_offset = y_offset + 16

            local msg = tostring(record.last_error or record.last_message or "")
            if msg ~= "" then
                local msg_color = record.last_error and color.new(255, 69, 58, 255) or colors.text_secondary
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), msg_color, msg)
                y_offset = y_offset + 16
            end

            if _last_action then
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), colors.text_secondary, "Last Action: " .. _last_action)
                y_offset = y_offset + 16
            end

            local h = 28
            local gap = 8

            local row1_w = (width - (gap * 3)) / 4
            local bx = x
            if render_button(
                    self, window, colors, bx, y_offset, row1_w, h, "Start Default", not record.active, colors.primary_accent,
                    "Start recording using the default profile path. Use this for a fresh run."
                ) then
                local ok, err = bot:record_start(_default_path)
                _last_action = ok and "record start default" or ("start failed: " .. tostring(err))
            end
            bx = bx + row1_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row1_w, h, "Start Template", not record.active, colors.secondary_accent,
                    "Start recording from the Anniversary template profile with placeholder segments."
                ) then
                local ok, err = bot:record_start(_template_path)
                _last_action = ok and "record start template" or ("start failed: " .. tostring(err))
            end
            bx = bx + row1_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row1_w, h, "Stop+Save", record.active, color.new(48, 209, 88, 255),
                    record.active and "Stop session and persist recorded route changes to disk." or "Disabled: recorder inactive."
                ) then
                local ok, err = bot:record_stop(true)
                _last_action = ok and "record stop save" or ("stop failed: " .. tostring(err))
            end
            bx = bx + row1_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row1_w, h, "Stop Discard", record.active, color.new(255, 69, 58, 255),
                    record.active and "Stop session and discard unsaved changes from this session." or "Disabled: recorder inactive."
                ) then
                local ok, err = bot:record_stop(false)
                _last_action = ok and "record stop discard" or ("stop failed: " .. tostring(err))
            end
            y_offset = y_offset + h + gap

            local row2_w = (width - (gap * 4)) / 5
            bx = x
            if render_button(
                    self, window, colors, bx, y_offset, row2_w, h, "Pull Point", record.active, colors.primary_accent,
                    record.active and "Capture current position as a pull point in the selected segment." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_capture_pull_point()
                _last_action = ok and "captured pull point" or ("capture failed: " .. tostring(err))
            end
            bx = bx + row2_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row2_w, h, "Gather", record.active, colors.primary_accent,
                    record.active and "Capture current position as segment gather anchor." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_capture_gather_anchor()
                _last_action = ok and "captured gather" or ("capture failed: " .. tostring(err))
            end
            bx = bx + row2_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row2_w, h, "Lane Start", record.active, colors.secondary_accent,
                    record.active and "Capture current position as blizzard lane start clamp." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_capture_lane_start()
                _last_action = ok and "captured lane start" or ("capture failed: " .. tostring(err))
            end
            bx = bx + row2_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row2_w, h, "Lane End", record.active, colors.secondary_accent,
                    record.active and "Capture current position as blizzard lane end clamp." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_capture_lane_end()
                _last_action = ok and "captured lane end" or ("capture failed: " .. tostring(err))
            end
            bx = bx + row2_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row2_w, h, "Save", record.active, color.new(48, 209, 88, 255),
                    record.active and "Save current recorder profile without stopping session." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_save()
                _last_action = ok and "saved profile" or ("save failed: " .. tostring(err))
            end
            y_offset = y_offset + h + gap

            local row3_w = (width - (gap * 4)) / 5
            bx = x
            if render_button(
                    self, window, colors, bx, y_offset, row3_w, h, "Prev Seg", record.active, colors.primary_accent,
                    record.active and "Select previous segment to edit/capture." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_prev_segment()
                _last_action = ok and "segment previous" or ("segment failed: " .. tostring(err))
            end
            bx = bx + row3_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row3_w, h, "Next/New Seg", record.active, colors.primary_accent,
                    record.active and "Move to next segment or create a new one when at end." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_next_segment()
                _last_action = ok and "segment next/new" or ("segment failed: " .. tostring(err))
            end
            bx = bx + row3_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row3_w, h, "Toggle Strat", record.active, colors.secondary_accent,
                    record.active and "Toggle blizzard strategy between cluster centroid and lane midpoint." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_toggle_strategy()
                _last_action = ok and ("strategy: " .. tostring(err)) or ("strategy failed: " .. tostring(err))
            end
            bx = bx + row3_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row3_w, h, "Undo", record.active, color.new(255, 159, 10, 255),
                    record.active and "Undo the last recorder edit operation." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_undo()
                _last_action = ok and "undo ok" or ("undo failed: " .. tostring(err))
            end
            bx = bx + row3_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, row3_w, h, "Clear Pulls", record.active, color.new(255, 69, 58, 255),
                    record.active and "Clear all pull points from current segment." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_clear_pull_points()
                _last_action = ok and "pull points cleared" or ("clear failed: " .. tostring(err))
            end
            y_offset = y_offset + h + 10

            local hints = {
                "Workflow: Start -> walk path -> Pull Point captures -> Gather/Lane -> Save.",
                "Use Next/New Seg after each pack train route.",
                "Template profile has placeholder coordinates; replace every value.",
            }
            for i = 1, #hints do
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), colors.text_secondary, hints[i])
                y_offset = y_offset + 14
            end

            return y_offset
        end,
    })
end

return recorder_tab
