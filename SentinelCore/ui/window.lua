--[[
    SentinelCore UI Window Orchestrator

    Uses AstroUI (same base library as SentinelNavClient) to provide a
    dedicated runtime control and diagnostics window for SentinelCore.
]]

local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local color = require("common/color")
local AstroUI = require("lib/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local Window = {}

local _initialized = false
local _client = nil
local _ui = nil
local _last_action_result = nil
local _last_settings_result = nil
local _last_profile_result = nil
local _selected_profile_index = 1
local _show_expert_settings = false
local _runtime_feed_filter = "all"

local FEED_FILTER_LABELS = {
    all = "All",
    warn = "Warn+Error",
    error = "Error",
}

local TOOLTIPS = {
    runtime_state = "Current HSM state and substate for SentinelCore's execution pipeline.",
    runtime_health = "Quick dependency health: world data, navigation, and inventory pressure.",
    runtime_actions = "Start/Pause/Resume/Stop control the grind mode state machine.",
    runtime_feed = "Live event feed from SentinelCore. Use filters to reduce noise.",
    snapshot_world = "Frozen snapshot of world context, dependencies, inventory, and telemetry.",
    settings_profile = "Settings are runtime-only until saved to the active profile.",
    vendor_enabled = "Enable or disable automatic vendoring entirely. When off, the bot will never seek a vendor.",
    min_free_slots = "Triggers vendoring when free bag slots are at or below this threshold.",
    return_to_anchor = "After vendoring, return to the last grind anchor before resuming combat logic.",
    repair_enabled = "If enabled, repair gear during vendor interaction when possible.",
    quality_filters = "Checked item qualities are eligible to be sold when vendoring.",
    quality_preset = "One-click quality presets. You can still fine-tune individual checkboxes after.",
    search_radius = "Max radius for querying nearby vendors from SentinelQueryServer.",
    expert_panel = "Shows advanced targeting and compatibility controls.",
    ret_section = "Retribution combat sustain settings. These values tune healing, potion, and consecration behavior.",
    ret_flash_hp = "Cast Flash of Light when health is at or below this threshold.",
    ret_holy_hp = "Cast Holy Light as emergency sustain at or below this threshold.",
    ret_low_mana = "Below this mana threshold, the routine can downrank Flash of Light for efficiency.",
    ret_health_pot = "Use best health potion when HP is at or below this threshold in combat.",
    ret_mana_pot = "Use best mana potion when mana is at or below this threshold in combat.",
    ret_consec = "Minimum mana required to cast Consecration in single-target combat.",
    target_base = "Preferred baseline pull radius for target selection.",
    target_max = "Hard cap for target acquisition distance.",
    legacy_quality = "Backward-compat fallback. Used only when explicit quality toggles are missing.",
    save_settings = "Persists current runtime + policy values to the active profile JSON.",
    profile_manager = "Create, rename, switch, save, and delete profile snapshots.",
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

---@param window any
---@param colors table
---@param x number
---@param y number
---@param w number
---@param h number
---@param label string
---@param enabled? boolean
---@return boolean
local function render_button(window, colors, x, y, w, h, label, enabled)
    enabled = enabled ~= false
    local start = vec2.new(x, y)
    local finish = vec2.new(x + w, y + h)

    local hovered = window:is_mouse_hovering_rect(start, finish)
    window:is_mouse_hovering_rect_block_movement(start, finish)

    local bg = enabled and (hovered and lighten_color(colors.primary_accent, 15) or colors.primary_accent)
        or colors.checkbox_inactive

    window:render_rect_filled(start, finish, bg, 6)

    local text_size = window:get_text_size(label)
    local tx = x + (w - text_size.x) / 2
    local ty = y + (h - text_size.y) / 2
    local tcolor = enabled and colors.text_primary or colors.text_disabled
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(tx, ty), tcolor, label)

    return enabled and hovered and window:is_rect_clicked(start, finish)
end

---@param ui_ctx any
---@param window any
---@param start vec2
---@param finish vec2
---@param hint string|nil
local function attach_tooltip(ui_ctx, window, start, finish, hint)
    if not hint or hint == "" then
        return
    end
    if ui_ctx and window:is_mouse_hovering_rect(start, finish) then
        ui_ctx._tooltip = hint
    end
end

---@param ui_ctx any
---@param window any
---@param colors table
---@param x number
---@param y number
---@param hint string|nil
---@return number
local function render_help_badge(ui_ctx, window, colors, x, y, hint)
    local label = "?"
    local text_size = window:get_text_size(label)
    local pad_x = 5
    local pad_y = 1
    local w = text_size.x + (pad_x * 2)
    local h = text_size.y + (pad_y * 2)
    local start = vec2.new(x, y)
    local finish = vec2.new(x + w, y + h)
    local hovered = window:is_mouse_hovering_rect(start, finish)
    window:is_mouse_hovering_rect_block_movement(start, finish)

    local bg = hovered and lighten_color(colors.primary_accent, 10) or colors.section_bg
    local fg = hovered and colors.text_primary or colors.text_secondary
    window:render_rect_filled(start, finish, bg, 6)
    window:render_rect(start, finish, colors.section_border, 6, 1)
    window:render_text(
        enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + pad_x, y + pad_y),
        fg,
        label
    )

    attach_tooltip(ui_ctx, window, start, finish, hint)
    return w
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param label string
---@param value any
---@return number
local function render_line(window, colors, x, y, label, value)
    local text = string.format("%s: %s", label, tostring(value))
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.text_secondary, text)
    return y + window:get_text_size(text).y + 2
end

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param width number
---@param label string
---@param value boolean
---@param on_toggle fun(new_value: boolean)
---@param tooltip? string
---@param ui_ctx? any
---@return number
local function render_toggle(window, colors, x, y, width, label, value, on_toggle, tooltip, ui_ctx)
    local button_text = string.format("%s: %s", label, value and "ON" or "OFF")
    local start = vec2.new(x, y)
    local finish = vec2.new(x + width, y + 20)
    if render_button(window, colors, x, y, width, 20, button_text, true) then
        on_toggle(not value)
    end
    attach_tooltip(ui_ctx, window, start, finish, tooltip)
    return y + 24
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param width number
---@param label string
---@return number
local function render_section_title(window, colors, x, y, width, label)
    local text_h = window:get_text_size(label).y
    local line_y = y + text_h + 4
    window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x, y), colors.text_secondary, label)
    window:render_rect_filled(vec2.new(x, line_y), vec2.new(x + width, line_y + 1), colors.section_border, 0)
    return line_y + 8
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param width number
---@param label string
---@param checked boolean
---@param tooltip? string
---@param ui_ctx? any
---@return boolean
local function render_checkbox_button(window, colors, x, y, width, label, checked, tooltip, ui_ctx)
    local row_h = 20
    local box_size = 14
    local start = vec2.new(x, y)
    local finish = vec2.new(x + width, y + row_h)

    local hovered = window:is_mouse_hovering_rect(start, finish)
    window:is_mouse_hovering_rect_block_movement(start, finish)

    local bg = hovered and lighten_color(colors.section_bg, 8) or colors.section_bg
    window:render_rect_filled(start, finish, bg, 4)

    local box_x = x + 4
    local box_y = y + (row_h - box_size) / 2
    local box_start = vec2.new(box_x, box_y)
    local box_end = vec2.new(box_x + box_size, box_y + box_size)
    local box_bg = checked and colors.checkbox_active or colors.checkbox_inactive
    window:render_rect_filled(box_start, box_end, box_bg, 3)
    window:render_rect(box_start, box_end, colors.checkbox_border, 3, 1)

    if checked then
        local check_pad = 3
        window:render_rect_filled(
            vec2.new(box_x + check_pad, box_y + check_pad),
            vec2.new(box_x + box_size - check_pad, box_y + box_size - check_pad),
            color.white(255),
            2
        )
    end

    local label_x = box_x + box_size + 8
    local label_y = y + (row_h - window:get_text_size(label).y) / 2
    local label_color = checked and colors.text_primary or colors.text_secondary
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(label_x, label_y), label_color, label)

    attach_tooltip(ui_ctx, window, start, finish, tooltip)
    return hovered and window:is_rect_clicked(start, finish)
end

---@param level string
---@return number
local function severity_rank(level)
    local normalized = tostring(level or "info"):lower()
    if normalized == "error" then
        return 3
    end
    if normalized == "warn" or normalized == "warning" then
        return 2
    end
    return 1
end

---@param entry table
---@return boolean
local function feed_entry_allowed(entry)
    local mode = tostring(_runtime_feed_filter or "all")
    if mode == "all" then
        return true
    end

    local rank = severity_rank(entry and entry.level or "info")
    if mode == "warn" then
        return rank >= 2
    end
    if mode == "error" then
        return rank >= 3
    end
    return true
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param text string
---@param bg color
---@return number
local function render_chip(window, colors, x, y, text, bg)
    local pad_x = 8
    local pad_y = 3
    local text_size = window:get_text_size(text)
    local w = text_size.x + (pad_x * 2)
    local h = text_size.y + (pad_y * 2)
    window:render_rect_filled(vec2.new(x, y), vec2.new(x + w, y + h), bg, 6)
    window:render_text(
        enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + pad_x, y + pad_y),
        colors.text_primary,
        text
    )
    return w + 6
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param width number
---@param label string
---@param value string
---@param state "good"|"warn"|"bad"|"neutral"
---@return number
local function render_status_card(window, colors, x, y, width, label, value, state)
    local h = 44
    local bg = colors.section_bg
    if state == "good" then
        bg = color.new(48, 140, 88, 170)
    elseif state == "warn" then
        bg = color.new(170, 120, 30, 170)
    elseif state == "bad" then
        bg = color.new(160, 65, 65, 170)
    end

    window:render_rect_filled(vec2.new(x, y), vec2.new(x + width, y + h), bg, 6)
    window:render_rect(vec2.new(x, y), vec2.new(x + width, y + h), colors.section_border, 6, 1)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + 8, y + 6), colors.text_secondary, label)
    window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x + 8, y + 22), colors.text_primary, value)
    return y + h + 6
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param width number
---@param modes string[]
---@param active string
---@return string
local function render_mode_selector(window, colors, x, y, width, modes, active)
    local count = #modes
    if count < 1 then
        return active
    end
    local gap = 4
    local btn_w = (width - ((count - 1) * gap)) / count
    local next_active = active

    for i = 1, count do
        local mode = tostring(modes[i])
        local label = FEED_FILTER_LABELS[mode] or mode
        local bx = x + ((i - 1) * (btn_w + gap))
        if mode == active then
            window:render_rect_filled(vec2.new(bx, y), vec2.new(bx + btn_w, y + 18), lighten_color(colors.primary_accent, 10), 6)
            window:render_text(
                enums.window_enums.font_id.FONT_SMALL,
                vec2.new(bx + 8, y + 2),
                colors.text_primary,
                label
            )
        else
            if render_button(window, colors, bx, y, btn_w, 18, label, true) then
                next_active = mode
            end
        end
    end

    return next_active
end

---@param client SentinelClient
---@param enabled_gray boolean
---@param enabled_white boolean
---@param enabled_green boolean
---@param enabled_blue boolean
---@param enabled_epic boolean
---@return boolean
---@return string|nil
local function apply_quality_preset(client, enabled_gray, enabled_white, enabled_green, enabled_blue, enabled_epic)
    local updates = {
        { "sell_gray", enabled_gray },
        { "sell_white", enabled_white },
        { "sell_green", enabled_green },
        { "sell_blue", enabled_blue },
        { "sell_epic", enabled_epic },
    }

    for i = 1, #updates do
        local update = updates[i]
        local ok, err = client:set_policy_setting(update[1], update[2], false)
        if not ok then
            return false, err
        end
    end

    return true, nil
end

---@param window any
---@param colors table
---@param x number
---@param y number
---@param width number
---@param label string
---@param value number
---@param step number
---@param min number
---@param max number
---@param decimals number
---@param on_change fun(new_value: number)
---@param tooltip? string
---@param ui_ctx? any
---@return number
local function render_stepper(window, colors, x, y, width, label, value, step, min, max, decimals, on_change, tooltip, ui_ctx)
    local row_h = 20
    local btn_w = 24
    local gap = 4
    local value_w = 70

    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y + 2), colors.text_secondary, label)

    local bx = x + width - (btn_w + gap + value_w + gap + btn_w)
    local label_end_x = math.max(x + window:get_text_size(label).x + 8, bx - 8)
    attach_tooltip(ui_ctx, window, vec2.new(x, y), vec2.new(label_end_x, y + row_h), tooltip)
    if render_button(window, colors, bx, y, btn_w, row_h, "-", true) then
        on_change(clamp((tonumber(value) or 0) - step, min, max))
    end

    local value_text = string.format("%." .. tostring(decimals) .. "f", tonumber(value) or 0)
    local tx = bx + btn_w + gap + ((value_w - window:get_text_size(value_text).x) / 2)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(tx, y + 2), colors.text_primary, value_text)

    local px = bx + btn_w + gap + value_w + gap
    if render_button(window, colors, px, y, btn_w, row_h, "+", true) then
        on_change(clamp((tonumber(value) or 0) + step, min, max))
    end

    return y + row_h + 4
end

---@param entry table
---@return string
local function format_feed_entry(entry)
    local ts = tonumber(entry and entry.timestamp) or 0
    local level = tostring(entry and entry.level or "info"):upper()
    local message = tostring(entry and entry.message or "")
    return string.format("[%.1f] %-5s %s", ts, level, message)
end

---@param ui any
---@param client SentinelClient
local function register_tabs(ui, client)
    ui:add_tab({ id = "runtime", label = "Runtime" }, function(t)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)

                local state = client and client.get_state and client:get_state() or "unknown"
                local snapshot = client and client.get_snapshot and client:get_snapshot() or nil
                local substate = snapshot and snapshot.substate or "-"
                local fail_reason = snapshot and snapshot.fail_reason or "-"
                local deps = snapshot and snapshot.dependencies or {}
                local context = snapshot and snapshot.context or {}
                local inventory = snapshot and snapshot.inventory or {}

                local section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "Control Center")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.runtime_state)

                local chip_x = x
                local state_label = "State: " .. tostring(state)
                local state_bg = colors.section_bg
                if state == "running" then
                    state_bg = color.new(48, 140, 88, 170)
                elseif state == "paused" then
                    state_bg = color.new(170, 120, 30, 170)
                elseif state == "failed" then
                    state_bg = color.new(160, 65, 65, 170)
                end
                chip_x = chip_x + render_chip(window, colors, chip_x, y_offset, state_label, state_bg)
                chip_x = chip_x + render_chip(window, colors, chip_x, y_offset, "Sub: " .. tostring(substate), colors.section_bg)
                if fail_reason and tostring(fail_reason) ~= "" and tostring(fail_reason) ~= "-" then
                    chip_x = chip_x + render_chip(window, colors, chip_x, y_offset, "Fail: " .. tostring(fail_reason), color.new(160, 65, 65, 170))
                end
                y_offset = y_offset + 24

                local card_gap = 8
                local card_w = math.floor((width - (card_gap * 2)) / 3)
                local card_h = 44
                local world_ok = deps.world_data_healthy == true and deps.world_dataset_ok == true
                local nav_ok = deps.nav_available == true and deps.nav_server_available == true
                local inv_state = inventory.needs_vendor and "Need Vendor" or "Stable"

                local world_state = world_ok and "good" or "bad"
                local nav_state = nav_ok and "good" or "bad"
                local inv_card_state = inventory.needs_vendor and "warn" or "good"

                local cards_y = y_offset
                render_status_card(window, colors, x, y_offset, card_w,
                    "World Data", world_ok and "Healthy" or "Unavailable", world_state)
                render_status_card(window, colors, x + card_w + card_gap, y_offset, card_w,
                    "Navigation", nav_ok and "Ready" or "Unavailable", nav_state)
                local free_display = (inventory.free_slots and inventory.free_slots >= 0)
                    and tostring(inventory.free_slots)
                    or "?"
                render_status_card(window, colors, x + (card_w * 2) + (card_gap * 2), y_offset, card_w,
                    "Inventory", string.format("%s (%s free)", inv_state, free_display), inv_card_state)
                attach_tooltip(self, window, vec2.new(x, cards_y), vec2.new(x + width, cards_y + card_h), TOOLTIPS.runtime_health)
                y_offset = y_offset + card_h + 8

                local location_text = string.format(
                    "Map %s | Zone %s | Area %s",
                    tostring(context.map_id or "-"),
                    tostring(context.zone_id or "-"),
                    tostring(context.area_id or "-")
                )
                y_offset = render_line(window, colors, x, y_offset, "Location", location_text)

                y_offset = y_offset + 4

                local button_h = 22
                local gap = 6
                local button_w = (width - (gap * 3)) / 4

                local start_enabled = state == "idle" or state == "failed"
                local pause_enabled = state == "running"
                local resume_enabled = state == "paused"
                local stop_enabled = (state == "running" or state == "paused")
                attach_tooltip(self, window, vec2.new(x, y_offset), vec2.new(x + width, y_offset + button_h), TOOLTIPS.runtime_actions)

                local bx = x
                if render_button(window, colors, bx, y_offset, button_w, button_h, "Start", start_enabled) then
                    local ok, err = client:start("grind")
                    _last_action_result = ok and "Start: ok" or ("Start: " .. tostring(err))
                end

                bx = bx + button_w + gap
                if render_button(window, colors, bx, y_offset, button_w, button_h, "Pause", pause_enabled) then
                    local ok = client:pause("ui_pause")
                    _last_action_result = ok and "Pause: ok" or "Pause: rejected"
                end

                bx = bx + button_w + gap
                if render_button(window, colors, bx, y_offset, button_w, button_h, "Resume", resume_enabled) then
                    local ok = client:resume()
                    _last_action_result = ok and "Resume: ok" or "Resume: rejected"
                end

                bx = bx + button_w + gap
                if render_button(window, colors, bx, y_offset, button_w, button_h, "Stop", stop_enabled) then
                    local ok = client:stop("ui_stop")
                    _last_action_result = ok and "Stop: ok" or "Stop: rejected"
                end

                y_offset = y_offset + button_h + 8

                local run_tests_enabled = _G and _G.SentinelCore and type(_G.SentinelCore.run_tests) == "function"
                if render_button(window, colors, x, y_offset, width, button_h, "Run SentinelCore Tests", run_tests_enabled) then
                    local ok, result = pcall(_G.SentinelCore.run_tests)
                    if ok and type(result) == "table" then
                        _last_action_result = string.format("Tests: passed=%s failed=%s",
                            tostring(result.passed), tostring(result.failed))
                    else
                        _last_action_result = "Tests: failed to execute"
                    end
                end

                y_offset = y_offset + button_h + 6

                if _last_action_result then
                    y_offset = render_line(window, colors, x, y_offset, "Last Action", _last_action_result)
                end

                y_offset = y_offset + 6
                section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "Runtime Feed")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.runtime_feed)

                local clear_w = 70
                local clear_h = 18
                local clear_x = x + width - clear_w
                _runtime_feed_filter = render_mode_selector(
                    window,
                    colors,
                    x,
                    y_offset,
                    width - clear_w - 8,
                    { "all", "warn", "error" },
                    _runtime_feed_filter
                )
                attach_tooltip(self, window, vec2.new(x, y_offset), vec2.new(x + width - clear_w - 8, y_offset + clear_h), TOOLTIPS.runtime_feed)
                if render_button(window, colors, clear_x, y_offset, clear_w, clear_h, "Clear", true) then
                    if client and client.clear_log_feed then
                        client:clear_log_feed()
                    end
                end

                y_offset = y_offset + clear_h + 6
                local raw_entries = client and client.get_log_feed and client:get_log_feed(40) or {}
                local entries = {}
                for i = 1, #raw_entries do
                    if feed_entry_allowed(raw_entries[i]) then
                        entries[#entries + 1] = raw_entries[i]
                    end
                end

                if #entries < 1 then
                    y_offset = render_line(window, colors, x, y_offset, "Feed", "No events yet")
                    return y_offset + 6
                end

                local max_lines = 14
                local start_index = math.max(1, #entries - max_lines + 1)
                for i = start_index, #entries do
                    local line = format_feed_entry(entries[i])
                    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), colors.text_secondary, line)
                    y_offset = y_offset + window:get_text_size(line).y + 2
                end

                return y_offset + 6
            end
        })
    end)

    ui:add_tab({ id = "snapshot", label = "Snapshot" }, function(t)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)

                local snapshot = client and client.get_snapshot and client:get_snapshot() or nil
                if not snapshot then
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, "Snapshot unavailable")
                    return y_offset + 20
                end

                local section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "World Snapshot")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.snapshot_world)
                y_offset = render_line(window, colors, x, y_offset, "Session", snapshot.session_id or "-")
                y_offset = render_line(window, colors, x, y_offset, "State", snapshot.full_state or "-")
                y_offset = render_line(window, colors, x, y_offset, "Timestamp", string.format("%.1f", tonumber(snapshot.timestamp) or 0))

                y_offset = y_offset + 6
                y_offset = render_section_title(window, colors, x, y_offset, width, "Context")

                y_offset = render_line(window, colors, x, y_offset, "Map", snapshot.context and snapshot.context.map_id or "-")
                y_offset = render_line(window, colors, x, y_offset, "Zone", snapshot.context and snapshot.context.zone_id or "-")
                y_offset = render_line(window, colors, x, y_offset, "Area", snapshot.context and snapshot.context.area_id or "-")

                local deps = snapshot.dependencies or {}
                y_offset = y_offset + 6
                y_offset = render_section_title(window, colors, x, y_offset, width, "Dependencies")
                local deps_chip_x = x
                deps_chip_x = deps_chip_x + render_chip(window, colors, deps_chip_x, y_offset,
                    "Nav: " .. (deps.nav_available and "OK" or "Down"),
                    deps.nav_available and color.new(48, 140, 88, 170) or color.new(160, 65, 65, 170))
                deps_chip_x = deps_chip_x + render_chip(window, colors, deps_chip_x, y_offset,
                    "Nav Server: " .. (deps.nav_server_available and "OK" or "Down"),
                    deps.nav_server_available and color.new(48, 140, 88, 170) or color.new(160, 65, 65, 170))
                deps_chip_x = deps_chip_x + render_chip(window, colors, deps_chip_x, y_offset,
                    "World: " .. (deps.world_data_healthy and "Healthy" or "Down"),
                    deps.world_data_healthy and color.new(48, 140, 88, 170) or color.new(160, 65, 65, 170))
                deps_chip_x = deps_chip_x + render_chip(window, colors, deps_chip_x, y_offset,
                    "Dataset: " .. (deps.world_dataset_ok and "OK" or "Mismatch"),
                    deps.world_dataset_ok and color.new(48, 140, 88, 170) or color.new(160, 65, 65, 170))
                y_offset = y_offset + 24

                local inventory = snapshot.inventory or {}
                y_offset = y_offset + 6
                y_offset = render_section_title(window, colors, x, y_offset, width, "Inventory")

                y_offset = render_line(window, colors, x, y_offset, "Free Slots", inventory.free_slots)
                y_offset = render_line(window, colors, x, y_offset, "Needs Vendor", inventory.needs_vendor)

                local telemetry = snapshot.telemetry or {}
                local rates = telemetry.rates or {}
                local counters = telemetry.counters or {}

                y_offset = y_offset + 6
                y_offset = render_section_title(window, colors, x, y_offset, width, "Telemetry")

                y_offset = render_line(window, colors, x, y_offset, "XP/hr", string.format("%.1f", tonumber(rates.xp_per_hour) or 0))
                y_offset = render_line(window, colors, x, y_offset, "Kills/hr", string.format("%.1f", tonumber(rates.kills_per_hour) or 0))
                y_offset = render_line(window, colors, x, y_offset, "Gold/hr", string.format("%.1f", tonumber(rates.gold_per_hour) or 0))
                y_offset = render_line(window, colors, x, y_offset, "Uptime (s)", string.format("%.1f", tonumber(telemetry.uptime_secs) or 0))
                y_offset = render_line(window, colors, x, y_offset, "Kills", counters.kills or 0)
                y_offset = render_line(window, colors, x, y_offset, "Loot Events", counters.loot_events or 0)
                y_offset = render_line(window, colors, x, y_offset, "Vendor Trips", counters.vendor_trips or 0)
                y_offset = render_line(window, colors, x, y_offset, "Failures", counters.failures or 0)

                return y_offset + 8
            end
        })
    end)

    ui:add_tab({ id = "settings", label = "Settings" }, function(t)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)

                local runtime = client and client.get_runtime_config and client:get_runtime_config() or {}
                local targeting = runtime.targeting or {}
                local vendor = runtime.vendor or {}
                local rotation = runtime.rotation or {}
                local paladin_rotation = rotation.paladin or {}
                local retri_rotation = paladin_rotation.retribution or {}
                local policy = client and client.get_policy_config and client:get_policy_config() or {}
                local active_profile_id = client and client.get_active_profile_id and client:get_active_profile_id() or "default"

                local function shallow_copy(value)
                    local out = {}
                    for k, v in pairs(value or {}) do
                        out[k] = v
                    end
                    return out
                end

                local function set_retri_policy(key, value)
                    local new_paladin = shallow_copy(rotation.paladin or {})
                    local new_retri = shallow_copy(new_paladin.retribution or {})
                    new_retri[key] = value
                    new_paladin.retribution = new_retri

                    local ok, err = client:set_runtime_setting("rotation", "paladin", new_paladin, false)
                    _last_settings_result = ok and ("Updated retribution." .. tostring(key)) or
                        ("Update failed: " .. tostring(err))
                end

                y_offset = render_line(window, colors, x, y_offset, "Active Profile", active_profile_id)
                y_offset = y_offset + 4

                local section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "Vendoring Policy")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.settings_profile)
                y_offset = render_toggle(window, colors, x, y_offset, width, "Auto-Vendor Enabled",
                    policy.vendor_enabled ~= false,
                    function(new_value)
                        local ok, err = client:set_policy_setting("vendor_enabled", new_value, false)
                        _last_settings_result = ok and "Updated vendor_enabled" or ("Update failed: " .. tostring(err))
                    end,
                    TOOLTIPS.vendor_enabled, self)

                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Min Free Slots", tonumber(policy.min_free_slots) or 2, 1.0, 0.0, 20.0, 0,
                    function(new_value)
                        local ok, err = client:set_policy_setting("min_free_slots", math.floor(new_value), false)
                        _last_settings_result = ok and "Updated min_free_slots" or ("Update failed: " .. tostring(err))
                    end,
                    TOOLTIPS.min_free_slots, self)

                y_offset = render_toggle(window, colors, x, y_offset, width, "Return To Grind Anchor",
                    vendor.return_to_anchor ~= false,
                    function(new_value)
                        local ok, err = client:set_runtime_setting("vendor", "return_to_anchor", new_value, false)
                        _last_settings_result = ok and "Updated return_to_anchor" or ("Update failed: " .. tostring(err))
                    end,
                    TOOLTIPS.return_to_anchor, self)

                y_offset = render_toggle(window, colors, x, y_offset, width, "Repair Gear At Vendor",
                    policy.repair_enabled == true,
                    function(new_value)
                        local ok, err = client:set_policy_setting("repair_enabled", new_value, false)
                        _last_settings_result = ok and "Updated repair_enabled" or ("Update failed: " .. tostring(err))
                    end,
                    TOOLTIPS.repair_enabled, self)

                y_offset = y_offset + 2
                y_offset = render_line(window, colors, x, y_offset, "Quality Filters", "Tick qualities to auto-sell")
                render_help_badge(self, window, colors, x + width - 18, y_offset - 14, TOOLTIPS.quality_filters)
                y_offset = render_line(window, colors, x, y_offset, "Preset", "One click updates all quality checkboxes")
                render_help_badge(self, window, colors, x + width - 18, y_offset - 14, TOOLTIPS.quality_preset)
                y_offset = y_offset + 2

                local preset_gap = 6
                local preset_w = math.floor((width - (preset_gap * 2)) / 3)
                local preset_h = 20

                if render_button(window, colors, x, y_offset, preset_w, preset_h, "Trash Only", true) then
                    local ok, err = apply_quality_preset(client, true, false, false, false, false)
                    _last_settings_result = ok and "Applied preset: Trash Only" or ("Update failed: " .. tostring(err))
                end
                if render_button(window, colors, x + preset_w + preset_gap, y_offset, preset_w, preset_h, "Common+", true) then
                    local ok, err = apply_quality_preset(client, true, true, false, false, false)
                    _last_settings_result = ok and "Applied preset: Common+" or ("Update failed: " .. tostring(err))
                end
                if render_button(window, colors, x + (preset_w * 2) + (preset_gap * 2), y_offset, preset_w, preset_h, "Uncommon+", true) then
                    local ok, err = apply_quality_preset(client, true, true, true, false, false)
                    _last_settings_result = ok and "Applied preset: Uncommon+" or ("Update failed: " .. tostring(err))
                end
                attach_tooltip(self, window, vec2.new(x, y_offset), vec2.new(x + width, y_offset + preset_h), TOOLTIPS.quality_preset)
                y_offset = y_offset + preset_h + 6

                local col_gap = 8
                local col_w = math.floor((width - (col_gap * 2)) / 3)
                local row_h = 22

                if render_checkbox_button(window, colors, x, y_offset, col_w, "Gray", policy.sell_gray == true, TOOLTIPS.quality_filters, self) then
                    local ok, err = client:set_policy_setting("sell_gray", policy.sell_gray ~= true, false)
                    _last_settings_result = ok and "Updated sell_gray" or ("Update failed: " .. tostring(err))
                end
                if render_checkbox_button(window, colors, x + col_w + col_gap, y_offset, col_w, "White", policy.sell_white == true, TOOLTIPS.quality_filters, self) then
                    local ok, err = client:set_policy_setting("sell_white", policy.sell_white ~= true, false)
                    _last_settings_result = ok and "Updated sell_white" or ("Update failed: " .. tostring(err))
                end
                if render_checkbox_button(window, colors, x + (col_w * 2) + (col_gap * 2), y_offset, col_w, "Green", policy.sell_green == true, TOOLTIPS.quality_filters, self) then
                    local ok, err = client:set_policy_setting("sell_green", policy.sell_green ~= true, false)
                    _last_settings_result = ok and "Updated sell_green" or ("Update failed: " .. tostring(err))
                end
                y_offset = y_offset + row_h + 4

                if render_checkbox_button(window, colors, x, y_offset, col_w, "Blue", policy.sell_blue == true, TOOLTIPS.quality_filters, self) then
                    local ok, err = client:set_policy_setting("sell_blue", policy.sell_blue ~= true, false)
                    _last_settings_result = ok and "Updated sell_blue" or ("Update failed: " .. tostring(err))
                end
                if render_checkbox_button(window, colors, x + col_w + col_gap, y_offset, col_w, "Epic", policy.sell_epic == true, TOOLTIPS.quality_filters, self) then
                    local ok, err = client:set_policy_setting("sell_epic", policy.sell_epic ~= true, false)
                    _last_settings_result = ok and "Updated sell_epic" or ("Update failed: " .. tostring(err))
                end
                y_offset = y_offset + row_h + 4
                y_offset = render_line(window, colors, x, y_offset, "Legacy Fallback", "sell_quality_max applies only if explicit toggle missing")
                y_offset = y_offset + 8

                section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "Retribution Combat")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.ret_section)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Flash Heal HP", tonumber(retri_rotation.flash_light_hp_pct) or 0.60, 0.02, 0.20, 0.90, 2,
                    function(new_value)
                        set_retri_policy("flash_light_hp_pct", new_value)
                    end,
                    TOOLTIPS.ret_flash_hp, self)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Holy Light HP", tonumber(retri_rotation.holy_light_hp_pct) or 0.35, 0.02, 0.10, 0.80, 2,
                    function(new_value)
                        set_retri_policy("holy_light_hp_pct", new_value)
                    end,
                    TOOLTIPS.ret_holy_hp, self)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Low Mana Downrank", tonumber(retri_rotation.heal_low_mana_threshold) or 0.22, 0.01, 0.05, 0.60, 2,
                    function(new_value)
                        set_retri_policy("heal_low_mana_threshold", new_value)
                    end,
                    TOOLTIPS.ret_low_mana, self)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Health Potion HP", tonumber(retri_rotation.health_potion_hp_pct) or 0.30, 0.02, 0.10, 0.90, 2,
                    function(new_value)
                        set_retri_policy("health_potion_hp_pct", new_value)
                    end,
                    TOOLTIPS.ret_health_pot, self)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Mana Potion Mana", tonumber(retri_rotation.mana_potion_mana_pct) or 0.15, 0.01, 0.05, 0.80, 2,
                    function(new_value)
                        set_retri_policy("mana_potion_mana_pct", new_value)
                    end,
                    TOOLTIPS.ret_mana_pot, self)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Consecration ST Mana", tonumber(retri_rotation.consecration_st_min_mana_pct) or 0.35, 0.02, 0.10, 0.90, 2,
                    function(new_value)
                        set_retri_policy("consecration_st_min_mana_pct", new_value)
                    end,
                    TOOLTIPS.ret_consec, self)
                y_offset = y_offset + 4

                section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "Navigation & Targeting")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.expert_panel)
                y_offset = render_stepper(window, colors, x, y_offset, width,
                    "Vendor Search Radius", tonumber(vendor.search_radius) or 250.0, 10.0, 50.0, 1000.0, 1,
                    function(new_value)
                        local ok, err = client:set_runtime_setting("vendor", "search_radius", new_value, false)
                        _last_settings_result = ok and "Updated vendor.search_radius" or ("Update failed: " .. tostring(err))
                    end,
                    TOOLTIPS.search_radius, self)

                y_offset = render_toggle(window, colors, x, y_offset, width, "Expert Panel",
                    _show_expert_settings == true,
                    function(new_value)
                        _show_expert_settings = new_value == true
                    end,
                    TOOLTIPS.expert_panel, self)

                if _show_expert_settings then
                    y_offset = render_stepper(window, colors, x, y_offset, width,
                        "Target Base Radius", tonumber(targeting.base_radius) or 45.0, 1.0, 10.0, 100.0, 1,
                        function(new_value)
                            local max_radius = tonumber(targeting.max_radius) or new_value
                            local clamped = math.min(new_value, max_radius)
                            local ok, err = client:set_runtime_setting("targeting", "base_radius", clamped, false)
                            _last_settings_result = ok and "Updated targeting.base_radius" or ("Update failed: " .. tostring(err))
                        end,
                        TOOLTIPS.target_base, self)

                    y_offset = render_stepper(window, colors, x, y_offset, width,
                        "Target Max Radius", tonumber(targeting.max_radius) or 75.0, 1.0, 10.0, 140.0, 1,
                        function(new_value)
                            local base_radius = tonumber(targeting.base_radius) or 10
                            local clamped = math.max(new_value, base_radius)
                            local ok, err = client:set_runtime_setting("targeting", "max_radius", clamped, false)
                            _last_settings_result = ok and "Updated targeting.max_radius" or ("Update failed: " .. tostring(err))
                        end,
                        TOOLTIPS.target_max, self)

                    y_offset = render_stepper(window, colors, x, y_offset, width,
                        "Legacy Sell Quality Max", tonumber(policy.sell_quality_max) or 1, 1.0, 0.0, 6.0, 0,
                        function(new_value)
                            local ok, err = client:set_policy_setting("sell_quality_max", math.floor(new_value), false)
                            _last_settings_result = ok and "Updated sell_quality_max" or ("Update failed: " .. tostring(err))
                        end,
                        TOOLTIPS.legacy_quality, self)
                end

                local button_h = 22
                if render_button(window, colors, x, y_offset, width, button_h, "Save Settings To Active Profile", true) then
                    local active = client and client.get_active_profile_id and client:get_active_profile_id() or ""
                    local ok, err = false, "not_available"
                    if client and client.save_profile then
                        ok, err = client:save_profile(active)
                    end
                    _last_settings_result = ok and "Settings saved" or ("Save failed: " .. tostring(err))
                end
                attach_tooltip(self, window, vec2.new(x, y_offset), vec2.new(x + width, y_offset + button_h), TOOLTIPS.save_settings)

                y_offset = y_offset + button_h + 8
                if _last_settings_result then
                    y_offset = render_line(window, colors, x, y_offset, "Settings", _last_settings_result)
                end

                return y_offset + 8
            end
        })
    end)

    ui:add_tab({ id = "profiles", label = "Profiles" }, function(t)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)

                local profiles = client and client.list_profiles and client:list_profiles() or {}
                if #profiles < 1 then
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, "No profiles available")
                    return y_offset + 20
                end

                if _selected_profile_index < 1 then _selected_profile_index = 1 end
                if _selected_profile_index > #profiles then _selected_profile_index = #profiles end

                local selected = profiles[_selected_profile_index]
                local active_id = client and client.get_active_profile_id and client:get_active_profile_id() or ""

                local section_y = y_offset
                y_offset = render_section_title(window, colors, x, y_offset, width, "Profile Manager")
                render_help_badge(self, window, colors, x + width - 18, section_y, TOOLTIPS.profile_manager)

                y_offset = render_line(window, colors, x, y_offset, "Active", active_id)
                y_offset = render_line(window, colors, x, y_offset, "Selected", string.format("%s (%s)", tostring(selected.name), tostring(selected.profile_id)))
                y_offset = render_line(window, colors, x, y_offset, "Index", string.format("%d/%d", _selected_profile_index, #profiles))
                y_offset = y_offset + 4

                local button_h = 22
                local gap = 6
                local btn_w = (width - gap) / 2

                if render_button(window, colors, x, y_offset, btn_w, button_h, "Prev", _selected_profile_index > 1) then
                    _selected_profile_index = _selected_profile_index - 1
                end
                if render_button(window, colors, x + btn_w + gap, y_offset, btn_w, button_h, "Next", _selected_profile_index < #profiles) then
                    _selected_profile_index = _selected_profile_index + 1
                end
                attach_tooltip(self, window, vec2.new(x, y_offset), vec2.new(x + width, y_offset + button_h), TOOLTIPS.profile_manager)

                y_offset = y_offset + button_h + 6

                if render_button(window, colors, x, y_offset, btn_w, button_h, "Load Selected", true) then
                    local ok, err = client:load_profile(selected.profile_id)
                    _last_profile_result = ok and ("Loaded " .. tostring(selected.name)) or ("Load failed: " .. tostring(err))
                end
                if render_button(window, colors, x + btn_w + gap, y_offset, btn_w, button_h, "Save Selected", true) then
                    local ok, err = client:save_profile(selected.profile_id, selected.name)
                    _last_profile_result = ok and ("Saved " .. tostring(selected.name)) or ("Save failed: " .. tostring(err))
                end

                y_offset = y_offset + button_h + 6

                if render_button(window, colors, x, y_offset, btn_w, button_h, "Create New", true) then
                    local stamp = math.floor((core and core.time and core.time()) or 0)
                    local name = "Profile " .. tostring(stamp)
                    local ok, err, new_id = client:create_profile(name)
                    _last_profile_result = ok and ("Created " .. tostring(name)) or ("Create failed: " .. tostring(err))
                    if ok then
                        local refreshed = client:list_profiles()
                        for i = 1, #refreshed do
                            if tostring(refreshed[i].profile_id) == tostring(new_id) then
                                _selected_profile_index = i
                                break
                            end
                        end
                    end
                end
                if render_button(window, colors, x + btn_w + gap, y_offset, btn_w, button_h, "Rename Selected", true) then
                    local stamp = math.floor((core and core.time and core.time()) or 0)
                    local new_name = string.format("%s %d", tostring(selected.name), stamp)
                    local ok, err = client:rename_profile(selected.profile_id, new_name)
                    _last_profile_result = ok and ("Renamed to " .. tostring(new_name)) or ("Rename failed: " .. tostring(err))
                end

                y_offset = y_offset + button_h + 6

                if render_button(window, colors, x, y_offset, width, button_h, "Delete Selected", #profiles > 1) then
                    local ok, err = client:delete_profile(selected.profile_id)
                    _last_profile_result = ok and ("Deleted " .. tostring(selected.name)) or ("Delete failed: " .. tostring(err))
                    if ok then
                        local refreshed = client:list_profiles()
                        if _selected_profile_index > #refreshed then
                            _selected_profile_index = #refreshed
                        end
                    end
                end

                y_offset = y_offset + button_h + 8
                if _last_profile_result then
                    y_offset = render_line(window, colors, x, y_offset, "Profiles", _last_profile_result)
                end

                return y_offset + 8
            end
        })
    end)
end

---@param client SentinelClient
function Window.init(client)
    if _initialized then
        return
    end

    _client = client

    _ui = AstroUI.new({
        id = "sentinel_core",
        title = "Sentinel Control Center",
        default_x = 560,
        default_y = 100,
        default_w = 760,
        default_h = 760,
        theme = "apple",
        render_layer = 1,
    })

    register_tabs(_ui, _client)

    -- Keep hidden until user toggles from main menu.
    _ui.menu.enable:set(false)

    _initialized = true
end

function Window.on_render()
    if not _initialized or not _ui then
        return
    end

    _ui:on_render()
end

function Window.on_menu_render()
    if not _initialized or not _ui then
        return
    end

    _ui:on_menu_render()
end

---@return any|nil
function Window.get_ui()
    return _ui
end

return Window
