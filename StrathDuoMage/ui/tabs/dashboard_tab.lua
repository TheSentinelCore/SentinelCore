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

local dashboard_tab = {}

local _last_action = nil

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
    local tx = x + (w - ts.x) / 2
    local ty = y + (h - ts.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(tx, ty),
        enabled and colors.text_primary or colors.text_disabled, label)

    return enabled and hovered and window:is_rect_clicked(start_pos, end_pos)
end

---@param t any
---@param bot StrathDuoBot
function dashboard_tab.render(t, bot)
    local snapshot = (bot and bot.get_snapshot and bot:get_snapshot()) or {}
    local telemetry = snapshot.telemetry or {}
    local record = snapshot.record or {}
    local state = tostring(snapshot.state or "idle")
    local phase = tostring(snapshot.phase or "idle")
    local role = tostring(snapshot.role or "leader")
    local route = snapshot.route or {}

    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local state_color = colors.text_disabled
            if state == "running" then
                state_color = color.new(48, 209, 88, 255)
            elseif state == "paused" then
                state_color = color.new(255, 214, 10, 255)
            elseif state == "failed" then
                state_color = color.new(255, 69, 58, 255)
            end

            local dot = 10
            window:render_rect_filled(vec2.new(x, y_offset + 2), vec2.new(x + dot, y_offset + 2 + dot), state_color, dot / 2)
            local title = string.format("%s | role=%s | phase=%s", string.upper(state), role, phase)
            window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x + dot + 8, y_offset), colors.text_primary, title)

            local right = string.format("Route S:%d P:%d %s", tonumber(route.segment_index) or 0, tonumber(route.pull_index) or 0,
                route.collecting and "collect" or "aoe")
            local rw = window:get_text_size(right).x
            window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + width - rw, y_offset + 2), colors.text_secondary, right)

            y_offset = y_offset + 22
            local rec_text = string.format("Recorder: %s", record.active and "active" or "inactive")
            window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + dot + 8, y_offset), colors.text_secondary, rec_text)
            y_offset = y_offset + 18

            local button_h = 30
            local gap = 8
            local button_w = (width - (gap * 4)) / 5

            local can_start = (state == "idle" or state == "failed")
            local can_pause = (state == "running")
            local can_resume = (state == "paused")
            local can_stop = (state == "running" or state == "paused")

            local bx = x
            if render_button(
                    self, window, colors, bx, y_offset, button_w, button_h, "Start", can_start, colors.primary_accent,
                    can_start and "Start the farm runtime loop." or "Disabled: runtime is already active."
                ) then
                local ok, err = bot:start()
                _last_action = ok and "start: ok" or ("start: " .. tostring(err))
            end
            bx = bx + button_w + gap

            if render_button(
                    self, window, colors, bx, y_offset, button_w, button_h, "Pause", can_pause, color.new(255, 159, 10, 255),
                    can_pause and "Pause decision updates while keeping current context." or "Disabled: runtime is not currently running."
                ) then
                bot:pause()
                _last_action = "pause: ok"
            end
            bx = bx + button_w + gap

            if render_button(
                    self, window, colors, bx, y_offset, button_w, button_h, "Resume", can_resume, color.new(48, 209, 88, 255),
                    can_resume and "Resume updates after pause." or "Disabled: runtime is not paused."
                ) then
                bot:resume()
                _last_action = "resume: ok"
            end
            bx = bx + button_w + gap

            if render_button(
                    self, window, colors, bx, y_offset, button_w, button_h, "Stop", can_stop, color.new(255, 69, 58, 255),
                    can_stop and "Stop runtime and clear movement intent." or "Disabled: runtime is already idle."
                ) then
                bot:stop("ui_stop")
                _last_action = "stop: ok"
            end
            bx = bx + button_w + gap

            if render_button(
                    self, window, colors, bx, y_offset, button_w, button_h, "Switch Role", true, colors.secondary_accent,
                    "Toggle leader/follower role. This changes duo sync role used for turn coordination."
                ) then
                bot:toggle_role()
                _last_action = "role toggled"
            end

            y_offset = y_offset + button_h + 10

            local rec_button_w = (width - (gap * 2)) / 3
            bx = x
            local can_record_start = not record.active
            local can_record_capture = record.active
            local can_record_stop = record.active

            if render_button(
                    self, window, colors, bx, y_offset, rec_button_w, button_h, "Record Start", can_record_start, colors.primary_accent,
                    can_record_start and "Start recorder session and unlock capture controls." or "Disabled: recorder session already active."
                ) then
                local ok, err = bot:record_start()
                _last_action = ok and "record: started" or ("record: " .. tostring(err))
            end
            bx = bx + rec_button_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, rec_button_w, button_h, "Record Point", can_record_capture, colors.secondary_accent,
                    can_record_capture and "Capture one pull point in the current recorder segment." or "Disabled: start recorder first."
                ) then
                local ok, err = bot:record_capture_pull_point()
                _last_action = ok and "record: pull point captured" or ("record: " .. tostring(err))
            end
            bx = bx + rec_button_w + gap
            if render_button(
                    self, window, colors, bx, y_offset, rec_button_w, button_h, "Record Stop+Save", can_record_stop, color.new(48, 209, 88, 255),
                    can_record_stop and "Stop recorder and save profile to disk." or "Disabled: recorder is inactive."
                ) then
                local ok, err = bot:record_stop(true)
                _last_action = ok and "record: stopped and saved" or ("record: " .. tostring(err))
            end

            y_offset = y_offset + button_h + 8
            if _last_action then
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), colors.text_secondary, "Last: " .. _last_action)
                y_offset = y_offset + 16
            end

            return y_offset
        end,
    })

    t:metric_grid({
        label = "Session",
        elements = {
            {
                label = "Kills",
                value_fn = function()
                    return tonumber(telemetry.kills) or 0
                end,
                format_fn = function(v) return string.format("%.0f", v) end,
            },
            {
                label = "Looted",
                value_fn = function()
                    return tonumber(telemetry.looted) or 0
                end,
                format_fn = function(v) return string.format("%.0f", v) end,
            },
            {
                label = "Gold/Hr (c)",
                value_fn = function()
                    return tonumber(telemetry.gold_per_hour_copper) or 0
                end,
                format_fn = function(v) return string.format("%.0f", v) end,
                color = color.new(255, 214, 10, 255),
            },
            {
                label = "Enemy Count",
                value_fn = function()
                    return tonumber(snapshot.enemy_count) or 0
                end,
                format_fn = function(v) return string.format("%.0f", v) end,
            },
        },
    })
end

return dashboard_tab
