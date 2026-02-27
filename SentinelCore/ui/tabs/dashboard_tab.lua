--[[
    SentinelCore Dashboard Tab

    Status bar with dependency indicators, performance metrics,
    mode selector, and Start/Pause/Resume/Stop controls.
]]

local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local color = require("common/color")
local AstroUI = require("lib/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local dashboard_tab = {}

local _selected_runtime_mode = "grind"
local _last_action_result = nil

local MODE_LABELS = {
    grind = "Grind",
    quest = "Quest",
    gather = "Gather",
    bg = "BG",
}

local TOOLTIPS = {
    runtime_state = "Current HSM state and substate for SentinelCore's execution pipeline.",
    runtime_actions = "Start/Pause/Resume/Stop control the currently selected mode state machine.",
}

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
function dashboard_tab.render(t, client)

    -- 1. Status + dependency indicators (custom_render, card=false)
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local state = client and client.get_state and client:get_state() or "unknown"
            local full_state = client and client.get_full_state and client:get_full_state() or ""

            -- Status dot color
            local dot_color = colors.text_disabled
            if state == "running" then
                dot_color = color.new(48, 209, 88, 255)
            elseif state == "paused" then
                dot_color = color.new(255, 214, 10, 255)
            elseif state == "failed" then
                dot_color = color.new(255, 69, 58, 255)
            end

            -- Dot
            local dot_size = 10
            local dot_y = y_offset + 2
            window:render_rect_filled(
                vec2.new(x, dot_y),
                vec2.new(x + dot_size, dot_y + dot_size),
                dot_color, dot_size / 2)

            -- State text
            local state_text = tostring(state):upper()
            window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG,
                vec2.new(x + dot_size + 8, y_offset),
                colors.text_primary, state_text)

            -- Full state on same line, offset right
            local state_w = window:get_text_size(state_text).x
            if full_state and full_state ~= "" then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + dot_size + 8 + state_w + 12, y_offset + 2),
                    colors.text_secondary, tostring(full_state))
            end

            -- Dependency indicators (right-aligned)
            local snap = client and client.get_snapshot and client:get_snapshot() or nil
            local deps = snap and snap.dependencies or {}
            local nav_ok = deps.nav_server_available == true
            local qs_ok = (deps.world_data_healthy == true) and (deps.world_dataset_ok ~= false)
            local green = color.new(48, 209, 88, 255)
            local red = color.new(255, 69, 58, 255)
            local dep_dot = 8
            local right_x = x + width

            -- QueryServer label + dot
            local qs_label = "QueryServer"
            local qs_lw = window:get_text_size(qs_label).x
            right_x = right_x - dep_dot
            window:render_rect_filled(
                vec2.new(right_x, y_offset + 3),
                vec2.new(right_x + dep_dot, y_offset + 3 + dep_dot),
                qs_ok and green or red, dep_dot / 2)
            right_x = right_x - qs_lw - 4
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(right_x, y_offset + 1),
                colors.text_secondary, qs_label)

            right_x = right_x - 14

            -- NavServer label + dot
            local nav_label = "NavServer"
            local nav_lw = window:get_text_size(nav_label).x
            right_x = right_x - dep_dot
            window:render_rect_filled(
                vec2.new(right_x, y_offset + 3),
                vec2.new(right_x + dep_dot, y_offset + 3 + dep_dot),
                nav_ok and green or red, dep_dot / 2)
            right_x = right_x - nav_lw - 4
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(right_x, y_offset + 1),
                colors.text_secondary, nav_label)

            -- Tooltip
            if self.window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + width, y_offset + 18)) then
                self._tooltip = TOOLTIPS.runtime_state
            end

            return y_offset + 22
        end,
    })

    -- 2. Performance (metric_grid)
    t:metric_grid({
        label = "Performance",
        elements = {
            {
                label = "XP/hr",
                value_fn = function()
                    local snap = client and client.get_snapshot and client:get_snapshot() or nil
                    if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                    return tonumber(snap.telemetry.rates.xp_per_hour) or 0
                end,
                format_fn = function(v) return string.format("%.0f", v) end,
            },
            {
                label = "Kills/hr",
                value_fn = function()
                    local snap = client and client.get_snapshot and client:get_snapshot() or nil
                    if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                    return tonumber(snap.telemetry.rates.kills_per_hour) or 0
                end,
                format_fn = function(v) return string.format("%.1f", v) end,
            },
            {
                label = "Deaths/hr",
                value_fn = function()
                    local snap = client and client.get_snapshot and client:get_snapshot() or nil
                    if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                    return tonumber(snap.telemetry.rates.deaths_per_hour) or 0
                end,
                format_fn = function(v) return string.format("%.2f", v) end,
                color = color.new(255, 69, 58, 255),
            },
            {
                label = "Gold/hr",
                value_fn = function()
                    local snap = client and client.get_snapshot and client:get_snapshot() or nil
                    if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                    return tonumber(snap.telemetry.rates.gold_per_hour) or 0
                end,
                format_fn = function(v) return string.format("%.1f", v) end,
                color = color.new(255, 214, 10, 255),
            },
            {
                label = "Combat Gap",
                value_fn = function()
                    local snap = client and client.get_snapshot and client:get_snapshot() or nil
                    if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                    return tonumber(snap.telemetry.rates.combat_downtime_avg_secs) or 0
                end,
                format_fn = function(v) return string.format("%.1fs", v) end,
            },
            {
                label = "Loot Events",
                value_fn = function()
                    local snap = client and client.get_snapshot and client:get_snapshot() or nil
                    if not snap or not snap.telemetry or not snap.telemetry.counters then return 0 end
                    return tonumber(snap.telemetry.counters.loot_events) or 0
                end,
                format_fn = function(v) return string.format("%d", v) end,
            },
        },
    })

    -- 3. Mode (custom_render segmented pill)
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            -- Build mode list dynamically
            local mode_options = {}
            local mode_labels = {}
            if client and client.list_modes then
                local list = client:list_modes()
                for i = 1, #list do
                    if list[i].functional == true then
                        local mode_id = tostring(list[i].id or "")
                        if mode_id ~= "" then
                            mode_options[#mode_options + 1] = mode_id
                            mode_labels[mode_id] = MODE_LABELS[mode_id] or mode_id
                        end
                    end
                end
            end
            if #mode_options < 1 then
                mode_options = { "grind" }
                mode_labels.grind = MODE_LABELS.grind
            end
            table.sort(mode_options)

            -- Validate current selection
            local valid = false
            for i = 1, #mode_options do
                if mode_options[i] == _selected_runtime_mode then
                    valid = true
                    break
                end
            end
            if not valid then
                _selected_runtime_mode = mode_options[1]
            end

            -- Sync to running mode if bot is active
            local state = client and client.get_state and client:get_state() or "idle"
            if state == "running" or state == "paused" then
                local snap = client and client.get_snapshot and client:get_snapshot() or nil
                local active_mode = snap and snap.mode
                    or (client and client.get_active_mode_id and client:get_active_mode_id())
                if active_mode then
                    _selected_runtime_mode = tostring(active_mode)
                end
            end

            -- Draw segmented pill
            local seg_h = 30
            local count = #mode_options
            local seg_w = width / count

            -- Background pill
            window:render_rect_filled(
                vec2.new(x, y_offset), vec2.new(x + width, y_offset + seg_h),
                colors.slider_bg, 8)

            for i = 1, count do
                local seg_x = x + (i - 1) * seg_w
                local seg_start = vec2.new(seg_x, y_offset)
                local seg_end = vec2.new(seg_x + seg_w, y_offset + seg_h)
                local is_selected = (mode_options[i] == _selected_runtime_mode)
                local is_hovered = window:is_mouse_hovering_rect(seg_start, seg_end)
                window:is_mouse_hovering_rect_block_movement(seg_start, seg_end)

                if is_selected then
                    window:render_rect_filled(
                        vec2.new(seg_x + 2, y_offset + 2),
                        vec2.new(seg_x + seg_w - 2, y_offset + seg_h - 2),
                        colors.primary_accent, 6)
                elseif is_hovered then
                    window:render_rect_filled(
                        vec2.new(seg_x + 1, y_offset + 1),
                        vec2.new(seg_x + seg_w - 1, y_offset + seg_h - 1),
                        lighten_color(colors.slider_bg, 15), 6)
                end

                -- Divider
                if i < count then
                    local next_selected = (mode_options[i + 1] == _selected_runtime_mode)
                    if not is_selected and not next_selected then
                        window:render_rect_filled(
                            vec2.new(seg_x + seg_w, y_offset + 6),
                            vec2.new(seg_x + seg_w + 1, y_offset + seg_h - 6),
                            colors.section_border, 0)
                    end
                end

                -- Label
                local label = mode_labels[mode_options[i]] or mode_options[i]
                local text_color = is_selected and colors.text_primary or colors.text_secondary
                local ts = window:get_text_size(label)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(seg_x + (seg_w - ts.x) / 2, y_offset + (seg_h - ts.y) / 2),
                    text_color, label)

                -- Click
                if not is_selected and window:is_rect_clicked(seg_start, seg_end) then
                    _selected_runtime_mode = mode_options[i]
                end
            end

            -- Tooltip
            if window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + width, y_offset + seg_h)) then
                self._tooltip = "Select the bot operating mode."
            end

            return y_offset + seg_h + 6
        end,
    })

    -- 4. Controls (custom_render)
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local state = client and client.get_state and client:get_state() or "unknown"

            local start_enabled = state == "idle" or state == "failed"
            local pause_enabled = state == "running"
            local resume_enabled = state == "paused"
            local stop_enabled = (state == "running" or state == "paused")

            local button_h = 28
            local gap = 8
            local button_w = (width - (gap * 3)) / 4

            -- Tooltip row
            if window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + width, y_offset + button_h)) then
                self._tooltip = TOOLTIPS.runtime_actions
            end

            local function render_action_button(bx, bw, label, enabled, accent)
                local start_pos = vec2.new(bx, y_offset)
                local end_pos = vec2.new(bx + bw, y_offset + button_h)
                local hovered = window:is_mouse_hovering_rect(start_pos, end_pos)
                if hovered then
                    window:is_mouse_hovering_rect_block_movement(start_pos, end_pos)
                end

                local bg = enabled
                    and (hovered and lighten_color(accent, 20) or accent)
                    or colors.checkbox_inactive
                window:render_rect_filled(start_pos, end_pos, bg, 8)

                local text_size = window:get_text_size(label)
                local tx = bx + (bw - text_size.x) / 2
                local ty = y_offset + (button_h - text_size.y) / 2
                local tc = enabled and colors.text_primary or colors.text_disabled
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(tx, ty), tc, label)

                return enabled and hovered and window:is_rect_clicked(start_pos, end_pos)
            end

            local bx = x
            if render_action_button(bx, button_w, "Start", start_enabled, colors.primary_accent) then
                local ok, err = client:start(_selected_runtime_mode)
                _last_action_result = ok and "Start: ok" or ("Start: " .. tostring(err))
            end

            bx = bx + button_w + gap
            if render_action_button(bx, button_w, "Pause", pause_enabled, color.new(255, 159, 10, 255)) then
                local ok = client:pause("ui_pause")
                _last_action_result = ok and "Pause: ok" or "Pause: rejected"
            end

            bx = bx + button_w + gap
            if render_action_button(bx, button_w, "Resume", resume_enabled, color.new(48, 209, 88, 255)) then
                local ok = client:resume()
                _last_action_result = ok and "Resume: ok" or "Resume: rejected"
            end

            bx = bx + button_w + gap
            if render_action_button(bx, button_w, "Stop", stop_enabled, color.new(255, 69, 58, 255)) then
                local ok = client:stop("ui_stop")
                _last_action_result = ok and "Stop: ok" or "Stop: rejected"
            end

            y_offset = y_offset + button_h + 6

            -- Last action feedback
            if _last_action_result then
                local fb_text = "Last: " .. tostring(_last_action_result)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_secondary, fb_text)
                y_offset = y_offset + window:get_text_size(fb_text).y + 4
            end

            return y_offset
        end,
    })
end

return dashboard_tab
