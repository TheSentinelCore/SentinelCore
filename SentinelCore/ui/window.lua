--[[
    SentinelCore UI Window Orchestrator

    Uses AstroUI (Apple HIG card-based design) to provide a
    dedicated runtime control and diagnostics window for SentinelCore.
]]

local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local color = require("common/color")
local AstroUI = require("lib/AstroUI")
local get_now = require("lib/TimeHelper").get_now

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
local _selected_runtime_mode = "grind"
local PALADIN_CLASS_ID = 2
local WARLOCK_CLASS_ID = 9

local MODE_LABELS = {
    grind = "Grind",
    quest = "Quest",
    gather = "Gather",
    bg = "BG",
}

local TOOLTIPS = {
    runtime_state = "Current HSM state and substate for SentinelCore's execution pipeline.",
    runtime_health = "Quick dependency health: world data, navigation, and inventory pressure.",
    runtime_actions = "Start/Pause/Resume/Stop control the currently selected mode state machine.",
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
    ret_flash_hp = "Flash of Light health threshold (used only in very-low-mana fallback mode).",
    ret_flash_oom = "Maximum mana threshold where Flash of Light is allowed as the low-mana fallback heal.",
    ret_holy_hp = "Cast Holy Light as the primary sustain heal at or below this threshold.",
    ret_low_mana = "Below this mana threshold, the routine can downrank Flash of Light for efficiency.",
    ret_health_pot = "Use best health potion when HP is at or below this threshold in combat.",
    ret_mana_pot = "Use best mana potion when mana is at or below this threshold in combat.",
    ret_consec = "Minimum mana required to cast Consecration in single-target combat.",
    wl_section = "Affliction sustain and survivability settings for Life Tap, Drain Life, pet funneling, and consumables.",
    wl_drink = "Out-of-combat drink threshold for Warlock.",
    wl_eat = "Out-of-combat eat threshold for Warlock.",
    wl_lifetap_min_hp = "Minimum HP required before Life Tap is allowed.",
    wl_lifetap_max_mana = "In-combat mana cap up to which Life Tap is used.",
    wl_lifetap_ooc_max_mana = "Out-of-combat mana cap up to which Life Tap is used.",
    wl_death_coil_hp = "Emergency HP threshold for Death Coil.",
    wl_drain_life_hp = "HP threshold for defensive Drain Life usage.",
    wl_funnel_pet_hp = "Pet HP threshold for Health Funnel.",
    wl_health_pot = "Combat HP threshold for health potion usage.",
    wl_mana_pot = "Combat mana threshold for mana potion usage.",
    wl_mana_pot_min_hp = "Minimum HP required to allow mana potion usage.",
    wl_wand_mana = "Mana floor before wand fallback is preferred.",
    target_base = "Preferred baseline pull radius for target selection.",
    target_max = "Hard cap for target acquisition distance.",
    legacy_quality = "Backward-compat fallback. Used only when explicit quality toggles are missing.",
    save_settings = "Persists current runtime + policy values to the active profile JSON.",
    profile_manager = "Create, rename, switch, save, and delete profile snapshots.",
}

local CLASS_NAMES = {
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [6] = "Death Knight",
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
    [11] = "Druid",
}

---@param class_id number|nil
---@return string
local function class_label(class_id)
    local normalized = tonumber(class_id) or 0
    if normalized <= 0 then
        return "Unknown"
    end
    return CLASS_NAMES[normalized] or ("Class " .. tostring(normalized))
end

---@param client SentinelClient|nil
---@return number
local function get_active_class_id(client)
    if not client or type(client.get_blackboard) ~= "function" then
        return 0
    end

    local ok_bb, bb = pcall(client.get_blackboard, client)
    if not ok_bb or not bb or type(bb.get) ~= "function" then
        return 0
    end

    return tonumber(bb:get("player.class_id", 0)) or 0
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

---@param entry table
---@return string
local function format_feed_entry(entry)
    local ts = tonumber(entry and entry.timestamp) or 0
    local level = tostring(entry and entry.level or "info"):upper()
    local message = tostring(entry and entry.message or "")
    return string.format("[%.1f] %-5s %s", ts, level, message)
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

-- ============================================================================
-- LIGHTWEIGHT WRAPPER OBJECTS FOR ROW_LIST
-- ============================================================================

--- Creates a toggle wrapper that reads/writes a policy setting via the client.
---@param key string
---@return table element with get_state/set
local function policy_toggle(key)
    return {
        get_state = function()
            local p = _client and _client.get_policy_config and _client:get_policy_config() or {}
            return p[key] == true
        end,
        set = function(_, v)
            local ok, err = _client:set_policy_setting(key, v, false)
            _last_settings_result = ok and ("Updated " .. key) or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a toggle wrapper that reads/writes a policy setting, defaulting to true.
---@param key string
---@return table element with get_state/set
local function policy_toggle_default_on(key)
    return {
        get_state = function()
            local p = _client and _client.get_policy_config and _client:get_policy_config() or {}
            return p[key] ~= false
        end,
        set = function(_, v)
            local ok, err = _client:set_policy_setting(key, v, true)
            _last_settings_result = ok and ("Updated " .. key) or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a toggle wrapper for a runtime setting path.
---@param domain string
---@param key string
---@param default boolean
---@return table element with get_state/set
local function runtime_toggle(domain, key, default)
    return {
        get_state = function()
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local section = rt[domain] or {}
            if section[key] == nil then return default end
            return section[key] == true
        end,
        set = function(_, v)
            local ok, err = _client:set_runtime_setting(domain, key, v, false)
            _last_settings_result = ok and ("Updated " .. domain .. "." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a policy integer setting.
---@param key string
---@param default number
---@return table element with get/set
local function policy_stepper(key, default)
    return {
        get = function()
            local p = _client and _client.get_policy_config and _client:get_policy_config() or {}
            return tonumber(p[key]) or default
        end,
        set = function(_, v)
            local ok, err = _client:set_policy_setting(key, math.floor(v), false)
            _last_settings_result = ok and ("Updated " .. key) or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a runtime setting.
---@param domain string
---@param key string
---@param default number
---@return table element with get/set
local function runtime_stepper(domain, key, default)
    return {
        get = function()
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local section = rt[domain] or {}
            return tonumber(section[key]) or default
        end,
        set = function(_, v)
            local ok, err = _client:set_runtime_setting(domain, key, v, false)
            _last_settings_result = ok and ("Updated " .. domain .. "." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a nested rotation setting (paladin.retribution.*).
---@param key string
---@param default number
---@return table element with get/set
local function retri_stepper(key, default)
    return {
        get = function()
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local paladin = rotation.paladin or {}
            local retri = paladin.retribution or {}
            return tonumber(retri[key]) or default
        end,
        set = function(_, v)
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local paladin_src = rotation.paladin or {}
            local retri_src = paladin_src.retribution or {}

            -- Shallow copy to avoid mutating cached config
            local new_paladin = {}
            for k2, v2 in pairs(paladin_src) do new_paladin[k2] = v2 end
            local new_retri = {}
            for k2, v2 in pairs(retri_src) do new_retri[k2] = v2 end
            new_retri[key] = v
            new_paladin.retribution = new_retri

            local ok, err = _client:set_runtime_setting("rotation", "paladin", new_paladin, false)
            _last_settings_result = ok and ("Updated retribution." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a nested rotation setting (warlock.affliction.*).
---@param key string
---@param default number
---@return table element with get/set
local function affli_stepper(key, default)
    return {
        get = function()
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local warlock = rotation.warlock or {}
            local affli = warlock.affliction or {}
            return tonumber(affli[key]) or default
        end,
        set = function(_, v)
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local warlock_src = rotation.warlock or {}
            local affli_src = warlock_src.affliction or {}

            local new_warlock = {}
            for k2, v2 in pairs(warlock_src) do new_warlock[k2] = v2 end
            local new_affli = {}
            for k2, v2 in pairs(affli_src) do new_affli[k2] = v2 end
            new_affli[key] = v
            new_warlock.affliction = new_affli

            local ok, err = _client:set_runtime_setting("rotation", "warlock", new_warlock, false)
            _last_settings_result = ok and ("Updated affliction." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper for targeting settings with clamping against the paired bound.
---@param key string "base_radius" or "max_radius"
---@param paired_key string the other key
---@param default number
---@return table element with get/set
local function targeting_stepper(key, paired_key, default)
    return {
        get = function()
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local targeting = rt.targeting or {}
            return tonumber(targeting[key]) or default
        end,
        set = function(_, v)
            local rt = _client and _client.get_runtime_config and _client:get_runtime_config() or {}
            local targeting = rt.targeting or {}
            local paired = tonumber(targeting[paired_key]) or v
            local clamped = v
            if key == "base_radius" then
                clamped = math.min(v, paired)
            else
                clamped = math.max(v, paired)
            end
            local ok, err = _client:set_runtime_setting("targeting", key, clamped, false)
            _last_settings_result = ok and ("Updated targeting." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

-- ============================================================================
-- HELPER: sorted blocked spells for Cast Guard section
-- ============================================================================

---@param client SentinelClient
---@return table[]|nil
local function _get_sorted_blocked_spells(client)
    local snap = client and client.get_snapshot and client:get_snapshot() or nil
    if not snap or not snap.telemetry or not snap.telemetry.rates then return nil end
    local by_spell = snap.telemetry.rates.cast_guard_blocked_per_min_by_spell
    if not by_spell then return nil end

    local rows = {}
    for spell_id, rate in pairs(by_spell) do
        local sid = tonumber(spell_id)
        local per_min = tonumber(rate) or 0
        if sid and sid > 0 and per_min > 0 then
            rows[#rows + 1] = { spell_id = sid, per_min = per_min }
        end
    end
    if #rows == 0 then return nil end

    table.sort(rows, function(a, b)
        if a.per_min == b.per_min then
            return a.spell_id < b.spell_id
        end
        return a.per_min > b.per_min
    end)
    return rows
end

-- ============================================================================
-- TAB REGISTRATION
-- ============================================================================

---@param ui any
---@param client SentinelClient
local function register_tabs(ui, client)

    -- ================================================================
    -- TAB 1: DASHBOARD
    -- ================================================================
    ui:add_tab({ id = "dashboard", label = "Dashboard" }, function(t)

        -- 1. Status (custom_render, card=false)
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

                -- Tooltip
                if self.window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + width, y_offset + 18)) then
                    self._tooltip = TOOLTIPS.runtime_state
                end

                return y_offset + 22
            end,
        })

        -- 2. Resources (progress_bar_list)
        t:progress_bar_list({
            label = "Resources",
            elements = {
                {
                    label = "Health",
                    tooltip = "Current health percentage",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.resources then return 0 end
                        return tonumber(snap.resources.health_pct) or 0
                    end,
                    color = color.new(48, 209, 88, 255),
                },
                {
                    label = "Mana",
                    tooltip = "Current mana percentage",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.resources then return 0 end
                        return tonumber(snap.resources.mana_pct) or 0
                    end,
                    color = color.new(10, 132, 255, 255),
                },
                {
                    label = "XP",
                    tooltip = "Experience progress to next level",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.resources then return 0 end
                        return tonumber(snap.resources.xp_pct) or 0
                    end,
                    color = color.new(191, 90, 242, 255),
                },
                {
                    label = "Durability",
                    tooltip = "Average equipment durability",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.resources then return 1 end
                        return tonumber(snap.resources.durability_pct) or 1
                    end,
                    color = color.new(255, 159, 10, 255),
                },
            },
        })

        -- 3. Dependencies (row_list type=info)
        local dep_color = function(val) return val == "Connected" and "status_green" or "status_red" end
        t:row_list({
            label = "Dependencies",
            elements = {
                {
                    type = "info",
                    label = "Navigation Server",
                    tooltip = TOOLTIPS.runtime_health,
                    color_fn = dep_color,
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        local deps = snap and snap.dependencies or {}
                        return deps.nav_server_available and "Connected" or "Offline"
                    end,
                },
                {
                    type = "info",
                    label = "World Data",
                    tooltip = TOOLTIPS.runtime_health,
                    color_fn = dep_color,
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        local deps = snap and snap.dependencies or {}
                        return deps.world_data_healthy and "Connected" or "Offline"
                    end,
                },
                {
                    type = "info",
                    label = "Dataset",
                    tooltip = TOOLTIPS.runtime_health,
                    color_fn = dep_color,
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        local deps = snap and snap.dependencies or {}
                        return deps.world_dataset_ok and "Connected" or "Offline"
                    end,
                },
            },
        })

        -- 4. Mode (custom_render segmented pill, rebuilt each frame for dynamic modes)
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

        -- 5. Controls (custom_render)
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

                -- Run Tests button
                local run_tests_enabled = _G and _G.SentinelCore and type(_G.SentinelCore.run_tests) == "function"
                local test_start = vec2.new(x, y_offset)
                local test_end = vec2.new(x + width, y_offset + button_h)
                local test_hovered = window:is_mouse_hovering_rect(test_start, test_end)
                if test_hovered then
                    window:is_mouse_hovering_rect_block_movement(test_start, test_end)
                end
                local test_bg = run_tests_enabled
                    and (test_hovered and lighten_color(colors.primary_accent, 15) or colors.primary_accent)
                    or colors.checkbox_inactive
                window:render_rect_filled(test_start, test_end, test_bg, 8)
                local test_label = "Run SentinelCore Tests"
                local test_ts = window:get_text_size(test_label)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + (width - test_ts.x) / 2, y_offset + (button_h - test_ts.y) / 2),
                    run_tests_enabled and colors.text_primary or colors.text_disabled, test_label)
                if run_tests_enabled and test_hovered and window:is_rect_clicked(test_start, test_end) then
                    local ok, result = pcall(_G.SentinelCore.run_tests)
                    if ok and type(result) == "table" then
                        _last_action_result = string.format("Tests: passed=%s failed=%s",
                            tostring(result.passed), tostring(result.failed))
                    else
                        _last_action_result = "Tests: failed to execute"
                    end
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

        -- 6a. Feed filter + clear (custom_render, card=false)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)

                local filter_h = 24
                local clear_w = 60
                local filter_area_w = width - clear_w - 8
                local filters = { "all", "warn", "error" }
                local filter_labels = { all = "All", warn = "Warn+", error = "Error" }
                local seg_w = filter_area_w / #filters

                -- Filter pills
                window:render_rect_filled(
                    vec2.new(x, y_offset), vec2.new(x + filter_area_w, y_offset + filter_h),
                    colors.slider_bg, 6)

                for i = 1, #filters do
                    local fx = x + (i - 1) * seg_w
                    local f_start = vec2.new(fx, y_offset)
                    local f_end = vec2.new(fx + seg_w, y_offset + filter_h)
                    local is_sel = (filters[i] == _runtime_feed_filter)
                    local is_hov = window:is_mouse_hovering_rect(f_start, f_end)
                    window:is_mouse_hovering_rect_block_movement(f_start, f_end)

                    if is_sel then
                        window:render_rect_filled(
                            vec2.new(fx + 2, y_offset + 2),
                            vec2.new(fx + seg_w - 2, y_offset + filter_h - 2),
                            colors.primary_accent, 4)
                    elseif is_hov then
                        window:render_rect_filled(
                            vec2.new(fx + 1, y_offset + 1),
                            vec2.new(fx + seg_w - 1, y_offset + filter_h - 1),
                            lighten_color(colors.slider_bg, 15), 4)
                    end

                    local label = filter_labels[filters[i]] or filters[i]
                    local tc = is_sel and colors.text_primary or colors.text_secondary
                    local ts = window:get_text_size(label)
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(fx + (seg_w - ts.x) / 2, y_offset + (filter_h - ts.y) / 2),
                        tc, label)

                    if not is_sel and window:is_rect_clicked(f_start, f_end) then
                        _runtime_feed_filter = filters[i]
                    end
                end

                -- Clear button
                local clear_x = x + width - clear_w
                local cs = vec2.new(clear_x, y_offset)
                local ce = vec2.new(clear_x + clear_w, y_offset + filter_h)
                local ch = window:is_mouse_hovering_rect(cs, ce)
                if ch then window:is_mouse_hovering_rect_block_movement(cs, ce) end
                local cbg = ch and lighten_color(colors.primary_accent, 15) or colors.primary_accent
                window:render_rect_filled(cs, ce, cbg, 6)
                local cl = "Clear"
                local cls = window:get_text_size(cl)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(clear_x + (clear_w - cls.x) / 2, y_offset + (filter_h - cls.y) / 2),
                    colors.text_primary, cl)
                if ch and window:is_rect_clicked(cs, ce) then
                    if client and client.clear_log_feed then
                        client:clear_log_feed()
                    end
                end

                -- Tooltip
                if window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + filter_area_w, y_offset + filter_h)) then
                    self._tooltip = TOOLTIPS.runtime_feed
                end

                return y_offset + filter_h + 4
            end,
        })

        -- 6b. Recent Events (listbox)
        t:listbox({
            label = "Recent Events",
            id = "dashboard_events",
            elements = {
                {
                    id = "event_feed",
                    visible_rows = 12,
                    entries_fn = function()
                        local raw_entries = client and client.get_log_feed and client:get_log_feed(40) or {}
                        local entries = {}
                        for i = 1, #raw_entries do
                            if feed_entry_allowed(raw_entries[i]) then
                                local lvl = tostring(raw_entries[i].level or "info"):lower()
                                local entry_color = nil
                                if lvl == "error" then
                                    entry_color = color.new(255, 69, 58, 255)
                                elseif lvl == "warn" or lvl == "warning" then
                                    entry_color = color.new(255, 214, 10, 255)
                                end
                                entries[#entries + 1] = {
                                    label = format_feed_entry(raw_entries[i]),
                                    color = entry_color,
                                }
                            end
                        end
                        -- Show most recent at top (reverse)
                        local reversed = {}
                        for i = #entries, 1, -1 do
                            reversed[#reversed + 1] = entries[i]
                        end
                        return reversed
                    end,
                    on_select = function() end,
                },
            },
        })
    end)

    -- ================================================================
    -- TAB 2: SETTINGS
    -- ================================================================
    ui:add_tab({ id = "settings", label = "Settings" }, function(t)

        -- 1. Vendoring (row_list)
        t:row_list({
            label = "Vendoring",
            footer = "Controls when the bot visits a vendor and which items are sold.",
            elements = {
                {
                    type = "toggle",
                    label = "Auto-Vendor",
                    tooltip = TOOLTIPS.vendor_enabled,
                    element = policy_toggle_default_on("vendor_enabled"),
                },
                {
                    type = "toggle",
                    label = "Repair Gear",
                    tooltip = TOOLTIPS.repair_enabled,
                    element = policy_toggle("repair_enabled"),
                },
                {
                    type = "toggle",
                    label = "Return to Anchor",
                    tooltip = TOOLTIPS.return_to_anchor,
                    element = runtime_toggle("vendor", "return_to_anchor", true),
                },
                {
                    type = "stepper",
                    label = "Min Free Slots",
                    tooltip = TOOLTIPS.min_free_slots,
                    element = policy_stepper("min_free_slots", 2),
                    min = 0, max = 20, step = 1, decimals = 0,
                },
                {
                    type = "stepper",
                    label = "Search Radius",
                    tooltip = TOOLTIPS.search_radius,
                    element = runtime_stepper("vendor", "search_radius", 250),
                    min = 50, max = 1000, step = 10, decimals = 0,
                },
            },
        })

        -- 2. Quality Filters (row_list type=toggle)
        t:row_list({
            label = "Quality Filters",
            footer = "Items matching enabled qualities will be sold at vendors.",
            elements = {
                {
                    type = "toggle",
                    label = "Gray (Trash)",
                    tooltip = TOOLTIPS.quality_filters,
                    element = policy_toggle("sell_gray"),
                },
                {
                    type = "toggle",
                    label = "White (Common)",
                    tooltip = TOOLTIPS.quality_filters,
                    element = policy_toggle("sell_white"),
                },
                {
                    type = "toggle",
                    label = "Green (Uncommon)",
                    tooltip = TOOLTIPS.quality_filters,
                    element = policy_toggle("sell_green"),
                },
                {
                    type = "toggle",
                    label = "Blue (Rare)",
                    tooltip = TOOLTIPS.quality_filters,
                    element = policy_toggle("sell_blue"),
                },
                {
                    type = "toggle",
                    label = "Epic",
                    tooltip = TOOLTIPS.quality_filters,
                    element = policy_toggle("sell_epic"),
                },
            },
        })

        -- Quality presets (custom_render, compact row of buttons)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)

                local preset_gap = 8
                local preset_h = 28
                local preset_w = math.floor((width - (preset_gap * 2)) / 3)

                local function render_preset_btn(bx, bw, label)
                    local s = vec2.new(bx, y_offset)
                    local e = vec2.new(bx + bw, y_offset + preset_h)
                    local hov = window:is_mouse_hovering_rect(s, e)
                    if hov then window:is_mouse_hovering_rect_block_movement(s, e) end
                    local bg = hov and lighten_color(colors.primary_accent, 15) or colors.primary_accent
                    window:render_rect_filled(s, e, bg, 8)
                    local ts = window:get_text_size(label)
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(bx + (bw - ts.x) / 2, y_offset + (preset_h - ts.y) / 2),
                        colors.text_primary, label)
                    return hov and window:is_rect_clicked(s, e)
                end

                if render_preset_btn(x, preset_w, "Trash Only") then
                    local ok, err = apply_quality_preset(client, true, false, false, false, false)
                    _last_settings_result = ok and "Applied preset: Trash Only" or ("Update failed: " .. tostring(err))
                end
                if render_preset_btn(x + preset_w + preset_gap, preset_w, "Common+") then
                    local ok, err = apply_quality_preset(client, true, true, false, false, false)
                    _last_settings_result = ok and "Applied preset: Common+" or ("Update failed: " .. tostring(err))
                end
                if render_preset_btn(x + (preset_w * 2) + (preset_gap * 2), preset_w, "Uncommon+") then
                    local ok, err = apply_quality_preset(client, true, true, true, false, false)
                    _last_settings_result = ok and "Applied preset: Uncommon+" or ("Update failed: " .. tostring(err))
                end

                if window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + width, y_offset + preset_h)) then
                    self._tooltip = TOOLTIPS.quality_preset
                end

                return y_offset + preset_h + 4
            end,
        })

        -- 3. Combat -- Paladin (Retribution)
        t:row_list({
            label = "Combat -- Paladin",
            footer = "Thresholds for healing, potions, and resource management.",
            visible_when = function()
                return get_active_class_id(client) == PALADIN_CLASS_ID
            end,
            elements = {
                {
                    type = "stepper", label = "Holy Light HP",
                    tooltip = TOOLTIPS.ret_holy_hp,
                    element = retri_stepper("holy_light_hp_pct", 0.60),
                    min = 0.10, max = 0.90, step = 0.02, decimals = 2,
                },
                {
                    type = "stepper", label = "Flash Heal HP",
                    tooltip = TOOLTIPS.ret_flash_hp,
                    element = retri_stepper("flash_light_hp_pct", 0.45),
                    min = 0.10, max = 0.80, step = 0.02, decimals = 2,
                },
                {
                    type = "stepper", label = "Flash OOM Mana",
                    tooltip = TOOLTIPS.ret_flash_oom,
                    element = retri_stepper("flash_light_very_oom_mana_pct", 0.12),
                    min = 0.03, max = 0.40, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Low Mana Downrank",
                    tooltip = TOOLTIPS.ret_low_mana,
                    element = retri_stepper("heal_low_mana_threshold", 0.22),
                    min = 0.05, max = 0.60, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Health Potion HP",
                    tooltip = TOOLTIPS.ret_health_pot,
                    element = retri_stepper("health_potion_hp_pct", 0.30),
                    min = 0.10, max = 0.90, step = 0.02, decimals = 2,
                },
                {
                    type = "stepper", label = "Mana Potion Mana",
                    tooltip = TOOLTIPS.ret_mana_pot,
                    element = retri_stepper("mana_potion_mana_pct", 0.15),
                    min = 0.05, max = 0.80, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Consecration ST Mana",
                    tooltip = TOOLTIPS.ret_consec,
                    element = retri_stepper("consecration_st_min_mana_pct", 0.35),
                    min = 0.10, max = 0.90, step = 0.02, decimals = 2,
                },
            },
        })

        -- 3b. Combat -- Warlock (Affliction)
        t:row_list({
            label = "Combat -- Warlock",
            footer = "Thresholds for healing, potions, and resource management.",
            visible_when = function()
                return get_active_class_id(client) == WARLOCK_CLASS_ID
            end,
            elements = {
                {
                    type = "stepper", label = "Drink Mana",
                    tooltip = TOOLTIPS.wl_drink,
                    element = affli_stepper("drink_mana_pct", 0.40),
                    min = 0.05, max = 0.95, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Eat Health",
                    tooltip = TOOLTIPS.wl_eat,
                    element = affli_stepper("eat_health_pct", 0.65),
                    min = 0.10, max = 0.95, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Life Tap Min HP",
                    tooltip = TOOLTIPS.wl_lifetap_min_hp,
                    element = affli_stepper("life_tap_min_health_pct", 0.50),
                    min = 0.10, max = 0.95, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Life Tap Max Mana",
                    tooltip = TOOLTIPS.wl_lifetap_max_mana,
                    element = affli_stepper("life_tap_max_mana_pct", 0.60),
                    min = 0.05, max = 0.95, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Life Tap OOC Mana",
                    tooltip = TOOLTIPS.wl_lifetap_ooc_max_mana,
                    element = affli_stepper("life_tap_ooc_max_mana_pct", 0.85),
                    min = 0.10, max = 0.99, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Death Coil HP",
                    tooltip = TOOLTIPS.wl_death_coil_hp,
                    element = affli_stepper("death_coil_hp_pct", 0.25),
                    min = 0.05, max = 0.80, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Drain Life HP",
                    tooltip = TOOLTIPS.wl_drain_life_hp,
                    element = affli_stepper("drain_life_hp_pct", 0.45),
                    min = 0.10, max = 0.90, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Health Funnel Pet HP",
                    tooltip = TOOLTIPS.wl_funnel_pet_hp,
                    element = affli_stepper("health_funnel_pet_hp_pct", 0.30),
                    min = 0.05, max = 0.90, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Health Potion HP",
                    tooltip = TOOLTIPS.wl_health_pot,
                    element = affli_stepper("health_potion_hp_pct", 0.25),
                    min = 0.05, max = 0.90, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Mana Potion Mana",
                    tooltip = TOOLTIPS.wl_mana_pot,
                    element = affli_stepper("mana_potion_mana_pct", 0.15),
                    min = 0.05, max = 0.80, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Mana Potion Min HP",
                    tooltip = TOOLTIPS.wl_mana_pot_min_hp,
                    element = affli_stepper("mana_potion_min_hp_pct", 0.35),
                    min = 0.05, max = 0.90, step = 0.01, decimals = 2,
                },
                {
                    type = "stepper", label = "Wand Mana Floor",
                    tooltip = TOOLTIPS.wl_wand_mana,
                    element = affli_stepper("wand_mana_pct", 0.08),
                    min = 0.00, max = 0.50, step = 0.01, decimals = 2,
                },
            },
        })

        -- 3c. Combat -- unsupported class placeholder
        t:row_list({
            label = "Combat",
            visible_when = function()
                local cid = get_active_class_id(client)
                return cid ~= PALADIN_CLASS_ID and cid ~= WARLOCK_CLASS_ID
            end,
            elements = {
                {
                    type = "info", label = "Active Class",
                    value_fn = function()
                        return class_label(get_active_class_id(client))
                    end,
                },
                {
                    type = "info", label = "Routine Settings",
                    value_fn = function()
                        local cid = get_active_class_id(client)
                        if cid <= 0 then
                            return "Waiting for class context"
                        end
                        return "No settings for current class"
                    end,
                },
            },
        })

        -- 4. Advanced (row_list)
        t:row_list({
            label = "Advanced",
            elements = {
                {
                    type = "toggle",
                    label = "Show Advanced",
                    tooltip = TOOLTIPS.expert_panel,
                    element = {
                        get_state = function() return _show_expert_settings == true end,
                        set = function(_, v) _show_expert_settings = v == true end,
                    },
                },
                {
                    type = "stepper", label = "Target Base Radius",
                    tooltip = TOOLTIPS.target_base,
                    element = targeting_stepper("base_radius", "max_radius", 45),
                    min = 10, max = 100, step = 1, decimals = 0,
                    visible_when = function() return _show_expert_settings end,
                },
                {
                    type = "stepper", label = "Target Max Radius",
                    tooltip = TOOLTIPS.target_max,
                    element = targeting_stepper("max_radius", "base_radius", 75),
                    min = 10, max = 140, step = 1, decimals = 0,
                    visible_when = function() return _show_expert_settings end,
                },
                {
                    type = "stepper", label = "Legacy Sell Quality",
                    tooltip = TOOLTIPS.legacy_quality,
                    element = policy_stepper("sell_quality_max", 1),
                    min = 0, max = 6, step = 1, decimals = 0,
                    visible_when = function() return _show_expert_settings end,
                },
            },
        })

        -- 5. Save (custom_render)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local width = window:get_size().x - (2 * LAYOUT.padding_side)
                local button_h = 32

                local btn_start = vec2.new(x, y_offset)
                local btn_end = vec2.new(x + width, y_offset + button_h)
                local hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
                if hovered then
                    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)
                    self._tooltip = TOOLTIPS.save_settings
                end

                local bg = hovered and lighten_color(colors.primary_accent, 15) or colors.primary_accent
                window:render_rect_filled(btn_start, btn_end, bg, 8)

                local label = "Save to Active Profile"
                local ts = window:get_text_size(label)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + (width - ts.x) / 2, y_offset + (button_h - ts.y) / 2),
                    colors.text_primary, label)

                if hovered and window:is_rect_clicked(btn_start, btn_end) then
                    local active = client and client.get_active_profile_id and client:get_active_profile_id() or ""
                    local ok, err = false, "not_available"
                    if client and client.save_profile then
                        ok, err = client:save_profile(active)
                    end
                    _last_settings_result = ok and "Settings saved" or ("Save failed: " .. tostring(err))
                end

                y_offset = y_offset + button_h + 6

                if _last_settings_result then
                    local fb = "Status: " .. tostring(_last_settings_result)
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, fb)
                    y_offset = y_offset + window:get_text_size(fb).y + 4
                end

                return y_offset
            end,
        })
    end)

    -- ================================================================
    -- TAB 3: TELEMETRY
    -- ================================================================
    ui:add_tab({ id = "telemetry", label = "Telemetry" }, function(t)

        -- 1. Performance (metric_grid)
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

        -- 2. Uptime (progress_bar_list)
        t:progress_bar_list({
            label = "Uptime",
            elements = {
                {
                    label = "Combat",
                    tooltip = "Fraction of session spent in active combat",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                        return tonumber(snap.telemetry.rates.combat_uptime_pct) or 0
                    end,
                    color = color.new(255, 69, 58, 230),
                },
                {
                    label = "Idle (Full Res)",
                    tooltip = "Fraction of idle time at full resources (wasted regen)",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.rates then return 0 end
                        return tonumber(snap.telemetry.rates.idle_full_resource_pct) or 0
                    end,
                    color = color.new(255, 214, 10, 230),
                },
            },
        })

        -- 3. Counters (row_list type=info)
        t:row_list({
            label = "Counters",
            elements = {
                {
                    type = "info", label = "Kills",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.counters then return "0" end
                        return tostring(snap.telemetry.counters.kills or 0)
                    end,
                },
                {
                    type = "info", label = "Deaths",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.counters then return "0" end
                        return tostring(snap.telemetry.counters.deaths or 0)
                    end,
                },
                {
                    type = "info", label = "Vendor Trips",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.counters then return "0" end
                        return tostring(snap.telemetry.counters.vendor_trips or 0)
                    end,
                },
                {
                    type = "info", label = "Failed Pulls",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.counters then return "0" end
                        return tostring(snap.telemetry.counters.failed_pulls or 0)
                    end,
                },
                {
                    type = "info", label = "Cast Guard Blocks",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.counters then return "0" end
                        return tostring(snap.telemetry.counters.cast_guard_blocked or 0)
                    end,
                },
                {
                    type = "info", label = "Unreachable Targets",
                    value_fn = function()
                        local snap = client and client.get_snapshot and client:get_snapshot() or nil
                        if not snap or not snap.telemetry or not snap.telemetry.counters then return "0" end
                        return tostring(snap.telemetry.counters.unreachable_targets or 0)
                    end,
                },
            },
        })

        -- 4. Cast Guard Top Blocks (row_list type=info, visible when data exists)
        t:row_list({
            label = "Cast Guard -- Top Blocks",
            visible_when = function()
                local snap = client and client.get_snapshot and client:get_snapshot() or nil
                if not snap or not snap.telemetry or not snap.telemetry.rates then return false end
                local by_spell = snap.telemetry.rates.cast_guard_blocked_per_min_by_spell
                if not by_spell then return false end
                for _ in pairs(by_spell) do return true end
                return false
            end,
            elements = {
                {
                    type = "info", label = "#1",
                    value_fn = function()
                        local rows = _get_sorted_blocked_spells(client)
                        if not rows or #rows < 1 then return "-" end
                        return string.format("Spell %d  %.2f/min", rows[1].spell_id, rows[1].per_min)
                    end,
                    visible_when = function()
                        local rows = _get_sorted_blocked_spells(client)
                        return rows and #rows >= 1
                    end,
                },
                {
                    type = "info", label = "#2",
                    value_fn = function()
                        local rows = _get_sorted_blocked_spells(client)
                        if not rows or #rows < 2 then return "-" end
                        return string.format("Spell %d  %.2f/min", rows[2].spell_id, rows[2].per_min)
                    end,
                    visible_when = function()
                        local rows = _get_sorted_blocked_spells(client)
                        return rows and #rows >= 2
                    end,
                },
                {
                    type = "info", label = "#3",
                    value_fn = function()
                        local rows = _get_sorted_blocked_spells(client)
                        if not rows or #rows < 3 then return "-" end
                        return string.format("Spell %d  %.2f/min", rows[3].spell_id, rows[3].per_min)
                    end,
                    visible_when = function()
                        local rows = _get_sorted_blocked_spells(client)
                        return rows and #rows >= 3
                    end,
                },
            },
        })
    end)

    -- ================================================================
    -- TAB 4: PROFILES
    -- ================================================================
    ui:add_tab({ id = "profiles", label = "Profiles" }, function(t)

        -- 1. Active Profile (row_list type=info)
        t:row_list({
            label = "Active Profile",
            elements = {
                {
                    type = "info",
                    label = "Profile ID",
                    tooltip = TOOLTIPS.profile_manager,
                    value_fn = function()
                        return client and client.get_active_profile_id and client:get_active_profile_id() or "default"
                    end,
                },
            },
        })

        -- 2. Saved Profiles (listbox)
        t:listbox({
            label = "Saved Profiles",
            id = "profiles_list",
            elements = {
                {
                    id = "profile_listbox",
                    visible_rows = 8,
                    entries_fn = function()
                        local profiles = client and client.list_profiles and client:list_profiles() or {}
                        local entries = {}
                        for i = 1, #profiles do
                            local p = profiles[i]
                            local active_id = client and client.get_active_profile_id and client:get_active_profile_id() or ""
                            local is_active = tostring(p.profile_id) == tostring(active_id)
                            entries[#entries + 1] = {
                                label = tostring(p.name or p.profile_id),
                                sublabel = is_active and "Active" or "",
                                color = is_active and color.new(48, 209, 88, 255) or nil,
                            }
                        end
                        return entries
                    end,
                    on_select = function(idx, _entry)
                        _selected_profile_index = idx
                    end,
                },
            },
        })

        -- 3. Actions (custom_render)
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

                local button_h = 28
                local gap = 8
                local btn_w = math.floor((width - gap * 4) / 5)

                local function make_btn(bx, bw, label, enabled)
                    local s = vec2.new(bx, y_offset)
                    local e = vec2.new(bx + bw, y_offset + button_h)
                    local hov = enabled and window:is_mouse_hovering_rect(s, e) or false
                    if hov then window:is_mouse_hovering_rect_block_movement(s, e) end
                    local bg = enabled
                        and (hov and lighten_color(colors.primary_accent, 15) or colors.primary_accent)
                        or colors.checkbox_inactive
                    window:render_rect_filled(s, e, bg, 8)
                    local ts = window:get_text_size(label)
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(bx + (bw - ts.x) / 2, y_offset + (button_h - ts.y) / 2),
                        enabled and colors.text_primary or colors.text_disabled, label)
                    return enabled and hov and window:is_rect_clicked(s, e)
                end

                local bx = x
                if make_btn(bx, btn_w, "Load", true) then
                    local ok, err = client:load_profile(selected.profile_id)
                    _last_profile_result = ok and ("Loaded " .. tostring(selected.name))
                        or ("Load failed: " .. tostring(err))
                end

                bx = bx + btn_w + gap
                if make_btn(bx, btn_w, "Save", true) then
                    local ok, err = client:save_profile(selected.profile_id, selected.name)
                    _last_profile_result = ok and ("Saved " .. tostring(selected.name))
                        or ("Save failed: " .. tostring(err))
                end

                bx = bx + btn_w + gap
                if make_btn(bx, btn_w, "Create", true) then
                    local stamp = math.floor(get_now())
                    local name = "Profile " .. tostring(stamp)
                    local ok, err, new_id = client:create_profile(name)
                    _last_profile_result = ok and ("Created " .. tostring(name))
                        or ("Create failed: " .. tostring(err))
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

                bx = bx + btn_w + gap
                if make_btn(bx, btn_w, "Rename", true) then
                    local stamp = math.floor(get_now())
                    local new_name = string.format("%s %d", tostring(selected.name), stamp)
                    local ok, err = client:rename_profile(selected.profile_id, new_name)
                    _last_profile_result = ok and ("Renamed to " .. tostring(new_name))
                        or ("Rename failed: " .. tostring(err))
                end

                bx = bx + btn_w + gap
                if make_btn(bx, btn_w, "Delete", #profiles > 1) then
                    local ok, err = client:delete_profile(selected.profile_id)
                    _last_profile_result = ok and ("Deleted " .. tostring(selected.name))
                        or ("Delete failed: " .. tostring(err))
                    if ok then
                        local refreshed = client:list_profiles()
                        if _selected_profile_index > #refreshed then
                            _selected_profile_index = #refreshed
                        end
                    end
                end

                y_offset = y_offset + button_h + 8

                if _last_profile_result then
                    local fb = "Status: " .. tostring(_last_profile_result)
                    window:render_text(enums.window_enums.font_id.FONT_SMALL,
                        vec2.new(x, y_offset), colors.text_secondary, fb)
                    y_offset = y_offset + window:get_text_size(fb).y + 4
                end

                return y_offset
            end,
        })
    end)
end

-- ============================================================================
-- MODULE API
-- ============================================================================

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
