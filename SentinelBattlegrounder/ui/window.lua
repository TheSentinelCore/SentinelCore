local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local rotation_settings_ui = require("shared/rotation_settings_ui")

local LAYOUT = rotation_settings_ui.LAYOUT

local Window = {}

local _ui = nil
local _initialized = false
local _bgbuddy = nil
local _menu = nil
local _rotation_options = { "Warlock (Demo)" }
local _rotation_keys = { "warlock" }
local _bg_options = { "Alterac Valley", "Warsong Gulch", "Arathi Basin", "Eye of the Storm (Cyclone)" }
local _bg_keys = { "alterac", "warsong", "arathi", "eots" }
local MULTIQUEUE_KEYS = { "alterac", "warsong", "arathi" }

local CITY_OPTIONS = { "Stormwind", "Orgrimmar" }
local ROLE_OPTIONS = { "Normal", "Def Last GY" }

local function city_to_index(city)
    if city == "orgrimmar" then
        return 2
    end
    return 1
end

local function index_to_city(index)
    if index == 2 then
        return "orgrimmar"
    end
    return "stormwind"
end

local function role_to_index(role)
    if role == "def_last_gy" then
        return 2
    end
    return 1
end

local function index_to_role(index)
    if index == 2 then
        return "def_last_gy"
    end
    return "normal"
end

local function rotation_key_to_index(key)
    for i, class_key in ipairs(_rotation_keys) do
        if class_key == key then
            return i
        end
    end
    return 1
end

local function index_to_rotation_key(index)
    return _rotation_keys[index] or _rotation_keys[1] or "warlock"
end

local function bg_key_to_index(key)
    for i, bg_key in ipairs(_bg_keys) do
        if bg_key == key then
            return i
        end
    end
    return 1
end

local function index_to_bg_key(index)
    return _bg_keys[index] or _bg_keys[1] or "alterac"
end

local function faction_to_label(faction_key)
    if faction_key == "alliance" then
        return "Alliance"
    end
    if faction_key == "horde" then
        return "Horde"
    end
    return "Unknown"
end

local function render_button(window, x, y, w, h, text, colors, border_color)
    local p1 = vec2.new(x, y)
    local p2 = vec2.new(x + w, y + h)
    local hovered = window:is_mouse_hovering_rect(p1, p2)
    window:is_mouse_hovering_rect_block_movement(p1, p2)

    local bg = hovered and border_color or colors.section_bg
    window:render_rect_filled(p1, p2, bg, 3.0)
    window:render_rect(p1, p2, border_color, 3.0, 1.0)

    local text_size = window:get_text_size(text)
    local tx = x + (w - text_size.x) / 2
    local ty = y + (h - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(tx, ty), color.white(255), text)

    return window:is_rect_clicked(p1, p2)
end

local function apply_ui_selection_once()
    if not _ui or not _menu or not _bgbuddy then
        return
    end

    local desired_bg = index_to_bg_key(_menu.bg_combo:get())
    if _menu._last_bg ~= desired_bg then
        _menu._last_bg = desired_bg
        _bgbuddy:set_selected_bg(desired_bg)
    end

    local desired_multi_queue = _menu.multi_queue_cb:get_state()
    if _menu._last_multi_queue ~= desired_multi_queue then
        _menu._last_multi_queue = desired_multi_queue
        _bgbuddy:set_multi_queue_enabled(desired_multi_queue)
    end

    local desired_mq_alterac = _menu.mq_alterac_cb:get_state()
    local desired_mq_warsong = _menu.mq_warsong_cb:get_state()
    local desired_mq_arathi = _menu.mq_arathi_cb:get_state()

    if desired_multi_queue and (not desired_mq_alterac) and (not desired_mq_warsong) and (not desired_mq_arathi) then
        desired_mq_alterac = true
        _menu.mq_alterac_cb:set(true)
    end

    if _menu._last_mq_alterac ~= desired_mq_alterac then
        _menu._last_mq_alterac = desired_mq_alterac
        _bgbuddy:set_multi_queue_bg_enabled("alterac", desired_mq_alterac)
    end

    if _menu._last_mq_warsong ~= desired_mq_warsong then
        _menu._last_mq_warsong = desired_mq_warsong
        _bgbuddy:set_multi_queue_bg_enabled("warsong", desired_mq_warsong)
    end

    if _menu._last_mq_arathi ~= desired_mq_arathi then
        _menu._last_mq_arathi = desired_mq_arathi
        _bgbuddy:set_multi_queue_bg_enabled("arathi", desired_mq_arathi)
    end

    local desired_role = index_to_role(_menu.role_combo:get())
    if _menu._last_role ~= desired_role then
        _menu._last_role = desired_role
        _bgbuddy:set_bg_role(desired_role)
    end

    local desired_combat = _menu.combat_enabled_cb:get_state()
    if _menu._last_combat_enabled ~= desired_combat then
        _menu._last_combat_enabled = desired_combat
        _bgbuddy:set_combat_enabled(desired_combat)
    end

    local desired_auto_faction = _menu.auto_faction_cb:get_state()
    if _menu._last_auto_faction ~= desired_auto_faction then
        _menu._last_auto_faction = desired_auto_faction
        _bgbuddy:set_auto_faction(desired_auto_faction)
    end

    local desired_debug = _menu.debug_enabled_cb:get_state()
    if _menu._last_debug_enabled ~= desired_debug then
        _menu._last_debug_enabled = desired_debug
        _bgbuddy:set_debug_enabled(desired_debug)
    end

    if not desired_auto_faction then
        local desired_city = index_to_city(_menu.city_combo:get())
        if _menu._last_city ~= desired_city then
            _menu._last_city = desired_city
            _bgbuddy:set_city(desired_city)
        end
    end

    local desired_rotation_class = index_to_rotation_key(_menu.rotation_class_combo:get())
    if _menu._last_rotation_class ~= desired_rotation_class then
        _menu._last_rotation_class = desired_rotation_class
        _bgbuddy:set_rotation_class(desired_rotation_class)
    end
end

local function render_control_bar(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    local running = _bgbuddy:is_running()
    local btn_h = 24
    local btn_w = 72
    local gap = 6

    if running then
        if render_button(window, x_start, y_offset, btn_w, btn_h, "Stop", colors, color.new(180, 60, 60, 255)) then
            _bgbuddy:stop()
        end
    else
        if render_button(window, x_start, y_offset, btn_w, btn_h, "Start", colors, color.new(70, 170, 90, 255)) then
            _bgbuddy:start()
        end
    end

    local status = _bgbuddy:get_status_text() or "Idle"
    local sx = x_start + btn_w + gap + 8
    local sy = y_offset + (btn_h - window:get_text_size(status).y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(sx, sy), colors.text_secondary, status)

    return y_offset + btn_h + 8
end

local function render_anchor_actions(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    local title = "Anchors"
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.primary_accent, title)
    y_offset = y_offset + 18

    local btn_h = 24
    local btn_w = 160
    local gap = 8

    if render_button(window, x_start, y_offset, btn_w, btn_h, "Set SW Anchor Here", colors, color.new(90, 140, 210, 255)) then
        _bgbuddy:set_anchor_from_player("stormwind")
    end

    if render_button(window, x_start + btn_w + gap, y_offset, btn_w, btn_h, "Set Org Anchor Here", colors, color.new(180, 90, 90, 255)) then
        _bgbuddy:set_anchor_from_player("orgrimmar")
    end

    y_offset = y_offset + btn_h + 8

    local selected_bg = _bgbuddy:get_selected_bg() or "alterac"
    local selected_city = _bgbuddy:get_auto_faction() and (_bgbuddy:get_city() or "stormwind") or index_to_city(_menu.city_combo:get())
    local btn_w_bg = 328
    local label = string.format("Set %s/%s BG Anchor Here", selected_city, selected_bg)
    if render_button(window, x_start, y_offset, btn_w_bg, btn_h, label, colors, color.new(120, 120, 210, 255)) then
        _bgbuddy:set_bg_anchor_from_player(selected_city, selected_bg)
    end

    y_offset = y_offset + btn_h + 8

    return y_offset
end

local function render_rotation_note(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    local note_rotation = "Only Warlock (Demo) is runnable for now. Other classes are placeholders."
    local note_strategy = "Scenario engine: Alterac DEF + Warsong mini skirmish are available."
    local faction_label = faction_to_label(_bgbuddy:get_detected_faction())
    local note_faction = "Detected faction: " .. faction_label
    local note_multi = "Multi-queue mode supports max 3 battlegrounds: Alterac / Warsong / Arathi."

    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_secondary, note_rotation)
    y_offset = y_offset + 18
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_secondary, note_strategy)
    y_offset = y_offset + 18
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.secondary_accent, note_faction)
    y_offset = y_offset + 18
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_secondary, note_multi)
    return y_offset + 22
end

local function render_debug_tab(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x = LAYOUT.padding_side
    local snap = _bgbuddy:get_debug_snapshot() or {}

    local lines = {
        string.format("BG: %s (%s)", tostring(snap.selected_bg_label or "?"), tostring(snap.selected_bg or "?")),
        string.format(
            "MultiQueue: %s | AV=%s WSG=%s AB=%s",
            tostring(snap.multi_queue_enabled),
            tostring(snap.multi_queue_alterac),
            tostring(snap.multi_queue_warsong),
            tostring(snap.multi_queue_arathi)
        ),
        string.format(
            "QueueSlots: target=%s | 1=%s 2=%s 3=%s",
            tostring(snap.queue_target_count or "?"),
            tostring(snap.slot1_status or "none"),
            tostring(snap.slot2_status or "none"),
            tostring(snap.slot3_status or "none")
        ),
        string.format("ActiveBG: %s (%s) via %s", tostring(snap.active_bg_label or "?"), tostring(snap.active_bg or "?"), tostring(snap.active_bg_source or "?")),
        string.format("Scenario: %s", tostring(snap.active_scenario_id or "none")),
        string.format(
            "QueueID: %s | City: %s | Faction: %s (%s)",
            tostring(snap.queue_id or "?"),
            tostring(snap.city or "?"),
            tostring(snap.detected_faction or "?"),
            tostring(snap.faction_source or "none")
        ),
        string.format("AutoFaction: %s | Debug: %s | LastAction: %s", tostring(snap.auto_faction), tostring(snap.debug_enabled), tostring(snap.last_action or "?")),
        string.format("ActiveAnchor: %.1f %.1f %.1f", tonumber(snap.active_anchor_x or 0), tonumber(snap.active_anchor_y or 0), tonumber(snap.active_anchor_z or 0)),
        string.format("Scan: %s scanned / %s matched", tostring(snap.scanned_count or 0), tostring(snap.matched_count or 0)),
        string.format("Match: type=%s npc=%s dist=%.1f", tostring(snap.last_match_type or "none"), tostring(snap.last_match_npc_id or 0), tonumber(snap.last_match_distance or 0)),
        string.format("MatchName: %s", tostring(snap.last_match_name or "")),
        string.format("LastStuckRecover: %.1f", tonumber(snap.last_stuck_recover_time or 0)),
        string.format("Status: %s", tostring(snap.status or "")),
    }

    for _, line in ipairs(lines) do
        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y_offset), colors.text_secondary, line)
        y_offset = y_offset + 16
    end

    return y_offset + 6
end

function Window.init(bgbuddy)
    if _initialized then
        return
    end

    _bgbuddy = bgbuddy

    _menu = {
        bg_combo = core.menu.combobox(1, "bgb_ui_bg"),
        city_combo = core.menu.combobox(1, "bgb_ui_city"),
        role_combo = core.menu.combobox(1, "bgb_ui_role"),
        rotation_class_combo = core.menu.combobox(1, "bgb_ui_rotation_class"),
        auto_faction_cb = core.menu.checkbox(true, "bgb_ui_auto_faction"),
        multi_queue_cb = core.menu.checkbox(false, "bgb_ui_multi_queue"),
        mq_alterac_cb = core.menu.checkbox(true, "bgb_ui_mq_alterac"),
        mq_warsong_cb = core.menu.checkbox(true, "bgb_ui_mq_warsong"),
        mq_arathi_cb = core.menu.checkbox(true, "bgb_ui_mq_arathi"),
        combat_enabled_cb = core.menu.checkbox(true, "bgb_ui_combat_enabled"),
        debug_enabled_cb = core.menu.checkbox(true, "bgb_ui_debug_enabled"),
        _last_bg = nil,
        _last_multi_queue = nil,
        _last_mq_alterac = nil,
        _last_mq_warsong = nil,
        _last_mq_arathi = nil,
        _last_city = nil,
        _last_role = nil,
        _last_combat_enabled = nil,
        _last_auto_faction = nil,
        _last_debug_enabled = nil,
        _last_rotation_class = nil,
    }

    _bg_options = _bgbuddy:get_bg_options() or _bg_options
    _rotation_options = _bgbuddy:get_rotation_class_options() or _rotation_options
    _rotation_keys = {
        "warrior",
        "paladin",
        "hunter",
        "rogue",
        "priest",
        "shaman",
        "mage",
        "warlock",
        "druid",
    }

    _ui = rotation_settings_ui.new({
        id = "bgbuddy",
        title = "BgBuddy",
        default_x = 120,
        default_y = 120,
        default_w = 520,
        default_h = 460,
        theme = "astro",
    })

    _ui._before_tabs_fn = render_control_bar

    _ui:add_tab({ id = "queue", label = "Queue" }, function(t)
        t:checkbox_grid({
            label = "Options",
            columns = 1,
            elements = {
                { element = _menu.auto_faction_cb, label = "Auto detect faction and city" },
                { element = _menu.multi_queue_cb, label = "Enable Multi-Queue (AV/WSG/AB)" },
                { element = _menu.mq_alterac_cb, label = "Queue Alterac" },
                { element = _menu.mq_warsong_cb, label = "Queue Warsong" },
                { element = _menu.mq_arathi_cb, label = "Queue Arathi" },
                { element = _menu.combat_enabled_cb, label = "Enable Basic Warlock TBC Rotation" },
                { element = _menu.debug_enabled_cb, label = "Enable Debug Logs" },
            },
        })

        t:combo_list({
            label = "Settings",
            elements = {
                { element = _menu.bg_combo, label = "Queue BG", options = _bg_options },
                { element = _menu.role_combo, label = "BG Role", options = ROLE_OPTIONS },
                {
                    element = _menu.city_combo,
                    label = "Queue City (manual)",
                    options = CITY_OPTIONS,
                    visible_when = function() return _menu.auto_faction_cb:get_state() == false end,
                },
                { element = _menu.rotation_class_combo, label = "Rotation Class", options = _rotation_options },
            },
        })

        t:custom_render({ render_fn = render_rotation_note })
        t:custom_render({ render_fn = render_anchor_actions })
    end)

    _ui:add_tab({ id = "debug", label = "Debug" }, function(t)
        t:custom_render({ render_fn = render_debug_tab })
    end)

    _menu.bg_combo:set(bg_key_to_index(_bgbuddy:get_selected_bg()))
    _menu.city_combo:set(city_to_index(_bgbuddy:get_city()))
    _menu.role_combo:set(role_to_index(_bgbuddy:get_bg_role()))
    _menu.rotation_class_combo:set(rotation_key_to_index(_bgbuddy:get_rotation_class()))
    _menu.auto_faction_cb:set(_bgbuddy:get_auto_faction())
    _menu.multi_queue_cb:set(_bgbuddy:get_multi_queue_enabled())
    _menu.mq_alterac_cb:set(_bgbuddy:get_multi_queue_bg_enabled(MULTIQUEUE_KEYS[1]))
    _menu.mq_warsong_cb:set(_bgbuddy:get_multi_queue_bg_enabled(MULTIQUEUE_KEYS[2]))
    _menu.mq_arathi_cb:set(_bgbuddy:get_multi_queue_bg_enabled(MULTIQUEUE_KEYS[3]))
    _menu.combat_enabled_cb:set(_bgbuddy:get_combat_enabled())
    _menu.debug_enabled_cb:set(_bgbuddy:get_debug_enabled())

    -- Keep window closed on load to avoid stealing mouse input until explicitly opened.
    _ui.menu.enable:set(false)

    _initialized = true
end

function Window.on_render()
    if not _initialized or not _ui then
        return
    end

    apply_ui_selection_once()
    _ui:on_render()
end

function Window.on_menu_render()
    if not _initialized or not _ui then
        return
    end
    _ui:on_menu_render()
end

function Window.open()
    if _ui and _ui.menu and _ui.menu.enable then
        -- Rebuild window instance to recover from backends that keep a closed window hidden.
        _ui.window = nil
        _ui.menu.enable:set(true)
    end
end

return Window
