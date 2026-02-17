local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("shared/AstroUI")

local RotationTab = require("ui/tabs/rotation_tab")
local GrindTab = require("ui/tabs/grind_tab")

local LAYOUT = AstroUI.LAYOUT

local Window = {}

local _ui = nil
local _menu = nil
local _controller = nil
local _initialized = false
local _profile_labels = {}
local _route_profile_labels = {}

local function title_case_name(text)
    local spaced = tostring(text or ""):gsub("_", " ")
    if spaced == "" then
        return ""
    end
    return (spaced:gsub("(%a)([%w']*)", function(head, tail)
        return string.upper(head) .. string.lower(tail)
    end))
end

local function build_theme_lists()
    local ids = {}
    local labels = {}
    local seen = {}
    local preferred_order = { "neutral", "astro", "rogue", "hunter" }

    local themes = AstroUI.THEMES or {}
    for _, theme_id in ipairs(preferred_order) do
        if themes[theme_id] then
            ids[#ids + 1] = theme_id
            labels[#labels + 1] = title_case_name(theme_id)
            seen[theme_id] = true
        end
    end

    local extras = {}
    for theme_id, _ in pairs(themes) do
        if not seen[theme_id] then
            extras[#extras + 1] = theme_id
        end
    end
    table.sort(extras)
    for _, theme_id in ipairs(extras) do
        ids[#ids + 1] = theme_id
        labels[#labels + 1] = title_case_name(theme_id)
    end

    if #ids == 0 then
        ids[1] = "astro"
        labels[1] = "Astro"
    end

    return ids, labels
end

local UI_THEME_IDS, UI_THEME_LABELS = build_theme_lists()

local function make_slider_float(min_value, max_value, default_value, id)
    local element = core.menu.slider_float(min_value, max_value, default_value, id)
    if element and AstroUI.register_slider_metadata then
        AstroUI.register_slider_metadata(element, {
            type = "float",
            min = min_value,
            max = max_value,
            default = default_value,
            id = id,
        })
    end
    return element
end

local function make_slider_int(min_value, max_value, default_value, id)
    local element = core.menu.slider_int(min_value, max_value, default_value, id)
    if element and AstroUI.register_slider_metadata then
        AstroUI.register_slider_metadata(element, {
            type = "int",
            min = min_value,
            max = max_value,
            default = default_value,
            id = id,
        })
    end
    return element
end

local function create_menu_elements(defaults)
    return {
        auto_rotation = core.menu.checkbox(true, "grindbuddy_rotation_auto"),
        rotation_profile = core.menu.combobox(defaults.rotation_profile_index or 1, "grindbuddy_rotation_profile"),
        route_mode = core.menu.combobox(defaults.route_mode or 1, "grindbuddy_route_mode"),
        route_auto_profile = core.menu.checkbox(defaults.route_auto_profile ~= false, "grindbuddy_route_auto_profile"),
        route_profile = core.menu.combobox(defaults.route_profile_index or 1, "grindbuddy_route_profile"),
        ui_theme = core.menu.combobox(defaults.ui_theme_index or 1, "grindbuddy_ui_theme"),

        scan_radius = make_slider_float(20.0, 300.0, defaults.scan_radius or 60.0, "grindbuddy_scan_radius"),
        pull_range = make_slider_float(5.0, 35.0, defaults.pull_range or 28.0, "grindbuddy_pull_range"),
        chase_stop_range = make_slider_float(5.0, 80.0, defaults.chase_stop_range or 24.0, "grindbuddy_chase_stop_range"),
        auto_mount_enabled = core.menu.checkbox(defaults.auto_mount_enabled ~= false, "grindbuddy_auto_mount_enabled"),
        mount_threshold = make_slider_float(10.0, 120.0, defaults.mount_threshold or 42.0, "grindbuddy_mount_threshold"),
        min_level_delta = make_slider_int(-5, 5, defaults.min_target_level_delta or 0, "grindbuddy_min_level_delta"),
        max_level_delta = make_slider_int(0, 8, defaults.max_target_level_delta or 2, "grindbuddy_max_level_delta"),
        ignore_players = core.menu.checkbox(defaults.ignore_players ~= false, "grindbuddy_ignore_players"),
        only_hostile_targets = core.menu.checkbox(defaults.only_hostile_targets ~= false, "grindbuddy_only_hostile_targets"),

        auto_replenish_enabled = core.menu.checkbox(defaults.auto_replenish_enabled == true, "grindbuddy_auto_replenish_enabled"),
        replenish_min_free_slots = make_slider_int(0, 16, defaults.replenish_min_free_slots or 2, "grindbuddy_replenish_min_free_slots"),
        vendor_npc_id = make_slider_int(0, 500000, defaults.vendor_npc_id or 0, "grindbuddy_vendor_npc_id"),
        vendor_scan_radius = make_slider_float(20.0, 250.0, defaults.vendor_scan_radius or 120.0, "grindbuddy_vendor_scan_radius"),
        vendor_interact_range = make_slider_float(2.0, 12.0, defaults.vendor_interact_range or 5.0, "grindbuddy_vendor_interact_range"),
        auto_vendor_sell_junk = core.menu.checkbox(defaults.auto_vendor_sell_junk ~= false, "grindbuddy_auto_vendor_sell_junk"),
        auto_vendor_repair = core.menu.checkbox(defaults.auto_vendor_repair ~= false, "grindbuddy_auto_vendor_repair"),
    }
end

local function build_profile_labels(profiles, fallback_label)
    local labels = {}
    for _, profile in ipairs(profiles or {}) do
        labels[#labels + 1] = profile.label
    end
    if #labels == 0 then
        labels[1] = fallback_label or "No profile available"
    end
    return labels
end

local function render_header(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    local running = _controller and _controller:is_running() or false
    local state = _controller and _controller:get_state() or "unknown"
    local status = _controller and _controller:get_status() or ""
    local profile = _controller and _controller:get_rotation_profile_label() or "none"
    local route_profile = _controller and _controller:get_route_profile_label() or "none"

    local line1 = string.format("State: %s | Running: %s", tostring(state), running and "yes" or "no")
    local line2 = string.format("Active Rotation: %s", tostring(profile))
    local line3 = string.format("Route Profile: %s", tostring(route_profile))
    local line4 = string.format("Status: %s", tostring(status))

    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_primary, line1)
    y_offset = y_offset + 16
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_secondary, line2)
    y_offset = y_offset + 16
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_muted or color.white(180), line3)
    y_offset = y_offset + 16
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x_start, y_offset), colors.text_muted or color.white(180), line4)
    y_offset = y_offset + 10

    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local sep_start = vec2.new(x_start, y_offset)
    local sep_end = vec2.new(x_start + content_width, y_offset + 2)
    window:render_rect_filled(sep_start, sep_end, colors.separator, 0)
    y_offset = y_offset + 6

    return y_offset
end

local function clamp_theme_index(index)
    local parsed = math.floor(tonumber(index) or 1)
    if parsed < 1 then
        return 1
    end
    if parsed > #UI_THEME_IDS then
        return #UI_THEME_IDS
    end
    return parsed
end

local function get_selected_theme_id()
    if not _menu or not _menu.ui_theme then
        return UI_THEME_IDS[1]
    end

    local current_index = _menu.ui_theme:get()
    local clamped_index = clamp_theme_index(current_index)
    if clamped_index ~= current_index then
        _menu.ui_theme:set(clamped_index)
    end
    return UI_THEME_IDS[clamped_index]
end

local function sync_ui_theme()
    if not _ui or not _ui.set_theme then
        return
    end

    local theme_id = get_selected_theme_id()
    if _ui.get_theme and _ui:get_theme() == theme_id then
        return
    end
    _ui:set_theme(theme_id)
end

local function sync_to_controller()
    if not _controller or not _menu then
        return
    end

    _controller:set_grind_settings({
        scan_radius = _menu.scan_radius:get(),
        pull_range = _menu.pull_range:get(),
        chase_stop_range = _menu.chase_stop_range:get(),
        auto_mount_enabled = _menu.auto_mount_enabled:get_state(),
        mount_threshold = _menu.mount_threshold:get(),
        min_target_level_delta = _menu.min_level_delta:get(),
        max_target_level_delta = _menu.max_level_delta:get(),
        ignore_players = _menu.ignore_players:get_state(),
        only_hostile_targets = _menu.only_hostile_targets:get_state(),
        route_mode = _menu.route_mode:get(),
        route_auto_profile = _menu.route_auto_profile:get_state(),
        route_profile_index = _menu.route_profile:get(),
        auto_replenish_enabled = _menu.auto_replenish_enabled:get_state(),
        replenish_min_free_slots = _menu.replenish_min_free_slots:get(),
        vendor_npc_id = _menu.vendor_npc_id:get(),
        vendor_scan_radius = _menu.vendor_scan_radius:get(),
        vendor_interact_range = _menu.vendor_interact_range:get(),
        auto_vendor_sell_junk = _menu.auto_vendor_sell_junk:get_state(),
        auto_vendor_repair = _menu.auto_vendor_repair:get_state(),
    })

    local auto_mode = _menu.auto_rotation:get_state()
    _controller:set_rotation_auto_select(auto_mode)

    if not auto_mode then
        _controller:set_rotation_profile_index(_menu.rotation_profile:get())
    end
end

local function force_release_mouse_capture()
    if not _ui then
        return
    end
    _ui._active_slider = nil
    _ui._active_key_capture = nil
    _ui._scroll_drag = false
    _ui._last_scroll_mouse_y = nil
end

function Window.init(controller)
    if _initialized then
        return
    end

    _controller = controller
    local profiles = controller:get_rotation_profiles()
    _profile_labels = build_profile_labels(profiles, "No TBC profile available")
    local route_profiles = controller:get_route_profiles()
    _route_profile_labels = build_profile_labels(route_profiles, "No route profile available")
    local grind = controller:get_grind_settings()

    local defaults = {
        rotation_profile_index = controller:get_rotation_profile_index() or 1,
        route_mode = controller:get_route_mode() or 1,
        route_auto_profile = controller:is_route_auto_select(),
        route_profile_index = controller:get_route_profile_index() or 1,
        scan_radius = grind.scan_radius,
        pull_range = grind.pull_range,
        chase_stop_range = grind.chase_stop_range,
        auto_mount_enabled = grind.auto_mount_enabled,
        mount_threshold = grind.mount_threshold,
        min_target_level_delta = grind.min_target_level_delta,
        max_target_level_delta = grind.max_target_level_delta,
        ignore_players = grind.ignore_players,
        only_hostile_targets = grind.only_hostile_targets,
        auto_replenish_enabled = grind.auto_replenish_enabled,
        replenish_min_free_slots = grind.replenish_min_free_slots,
        vendor_npc_id = grind.vendor_npc_id,
        vendor_scan_radius = grind.vendor_scan_radius,
        vendor_interact_range = grind.vendor_interact_range,
        auto_vendor_sell_junk = grind.auto_vendor_sell_junk,
        auto_vendor_repair = grind.auto_vendor_repair,
    }

    _menu = create_menu_elements(defaults)
    _menu.auto_rotation:set(controller:is_rotation_auto_select())

    _ui = AstroUI.new({
        id = "grindbuddy",
        title = "GrindBuddy Settings",
        default_x = 780,
        default_y = 220,
        default_w = 520,
        default_h = 580,
        theme = get_selected_theme_id(),
    })

    _ui._before_tabs_fn = render_header

    GrindTab.register(_ui, _menu, _route_profile_labels, UI_THEME_LABELS)
    RotationTab.register(_ui, _menu, _profile_labels)
    sync_ui_theme()

    _initialized = true
    core.log("[GrindBuddy] Astro UI initialized")
end

function Window.on_render()
    if not _initialized or not _ui then
        return
    end

    sync_to_controller()
    sync_ui_theme()
    _ui:on_render()
end

function Window.on_menu_render()
    if not _initialized or not _ui then
        return
    end
    _ui:on_menu_render()
end

function Window.toggle()
    if not _ui or not _ui.menu or not _ui.menu.enable then
        return
    end
    local next_state = not _ui.menu.enable:get_state()
    _ui.menu.enable:set(next_state)
    if not next_state then
        force_release_mouse_capture()
    end
end

function Window.close()
    if not _ui or not _ui.menu or not _ui.menu.enable then
        return
    end
    _ui.menu.enable:set(false)
    force_release_mouse_capture()
end

function Window.get_ui()
    return _ui
end

return Window
