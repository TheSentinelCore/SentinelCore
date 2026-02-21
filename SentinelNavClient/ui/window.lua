--[[
    SentinelNavClient UI Window Orchestrator

    Creates and manages the AstroUI settings window, registers all tabs,
    renders the "Show Advanced" toggle above the tab bar, and syncs menu
    element values into the Client config every frame.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("lib/AstroUI")
local Defaults = require("core/Defaults")

-- Tab modules
local MovementTab    = require("ui/tabs/movement_tab")
local PathfindingTab = require("ui/tabs/pathfinding_tab")
local ObstaclesTab   = require("ui/tabs/obstacles_tab")
local DebugTab       = require("ui/tabs/debug_tab")
local Visualizer     = require("ui/Visualizer")

local LAYOUT = AstroUI.LAYOUT

local Window = {}

-- Private state
local _ui = nil              -- RotationSettingsUI instance
local _initialized = false
local _client = nil          -- SentinelNavClient Client instance
local _menu = nil            -- menu elements table
local _visualizer = nil      -- Visualizer instance
local _reset_mappings = {}   -- per-tab reset mappings keyed by tab ID
local _health_cache = {
    inflight = false,
    last_check = 0,
    server_up = true,
    status = "ok",
    version = "-",
    uptime_secs = 0,
    loaded_maps = 0,
    last_error = nil,
}

local HEALTH_REFRESH_INTERVAL = 2.5

local UI_TOOLTIPS = {
    control_center = "Live navigation state and dependency health summary for SentinelNavClient.",
    show_advanced = "Toggles advanced controls in Movement, Pathfinding, and Obstacles tabs.",
    nav_server = "Periodic health check against SentinelNavServer.",
    path_progress = "Current active path waypoint progress and destination distance.",
    destination = "Active move target and current distance from player position.",
}

local function lighten_color(base_color, amount)
    local r, g, b, a = base_color:get()
    return color.new(
        math.min(255, r + amount),
        math.min(255, g + amount),
        math.min(255, b + amount),
        a
    )
end

local function attach_tooltip(ui, window, start_pos, end_pos, hint)
    if not hint or hint == "" then
        return
    end
    if ui and window:is_mouse_hovering_rect(start_pos, end_pos) then
        ui._tooltip = hint
    end
end

local function render_help_badge(ui, window, colors, x, y, hint)
    local label = "?"
    local text_size = window:get_text_size(label)
    local pad_x = 5
    local pad_y = 1
    local w = text_size.x + (pad_x * 2)
    local h = text_size.y + (pad_y * 2)
    local start_pos = vec2.new(x, y)
    local end_pos = vec2.new(x + w, y + h)
    local hovered = window:is_mouse_hovering_rect(start_pos, end_pos)
    window:is_mouse_hovering_rect_block_movement(start_pos, end_pos)

    local bg = hovered and lighten_color(colors.primary_accent, 10) or colors.section_bg
    local fg = hovered and colors.text_primary or colors.text_secondary
    window:render_rect_filled(start_pos, end_pos, bg, 6)
    window:render_rect(start_pos, end_pos, colors.section_border, 6, 1)
    window:render_text(
        enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + pad_x, y + pad_y),
        fg,
        label
    )
    attach_tooltip(ui, window, start_pos, end_pos, hint)
end

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

local function refresh_health_if_due()
    if not _client or not _client.health_check then
        return
    end

    local now = (core and core.time and core.time()) or 0
    if _health_cache.inflight then
        return
    end
    if (now - (_health_cache.last_check or 0)) < HEALTH_REFRESH_INTERVAL then
        return
    end

    _health_cache.inflight = true
    _health_cache.last_check = now

    _client:health_check(function(ok, data, err)
        _health_cache.inflight = false
        _health_cache.last_check = (core and core.time and core.time()) or now
        if ok and data then
            local loaded_maps = data.loaded_maps and #data.loaded_maps or 0
            _health_cache.server_up = true
            _health_cache.status = tostring(data.status or "ok")
            _health_cache.version = tostring(data.version or "-")
            _health_cache.uptime_secs = tonumber(data.uptime_secs) or 0
            _health_cache.loaded_maps = loaded_maps
            _health_cache.last_error = nil
        else
            _health_cache.server_up = false
            _health_cache.status = "down"
            _health_cache.last_error = tostring(err or "unknown")
        end
    end)
end

--------------------------------------------------------------------------------
-- Menu element creation
--------------------------------------------------------------------------------

---Create a menu element from a Defaults entry
---@param def table Defaults entry { type, min?, max?, default, id }
---@return any Menu element
local function make_element(def)
    if def.type == "bool" then
        return core.menu.checkbox(def.default, def.id)
    elseif def.type == "float" then
        return core.menu.slider_float(def.min, def.max, def.default, def.id)
    elseif def.type == "int" then
        return core.menu.slider_int(def.min, def.max, def.default, def.id)
    elseif def.type == "combo" then
        return core.menu.combobox(def.default, def.id)
    end
end

local function create_menu_elements()
    local D = Defaults
    local e = make_element

    return {
        -- Window-level
        show_advanced          = e(D.window.show_advanced),

        -- Movement basics (Tab 1)
        dynamic_speed          = e(D.movement.dynamic_speed),
        dyn_tol_scale          = e(D.movement.dynamic_speed_max_tolerance_scale),
        dyn_tol_bonus          = e(D.movement.dynamic_speed_max_tolerance_bonus),
        dyn_ramp_z             = e(D.movement.dynamic_speed_ramp_z_delta),
        dyn_ramp_tol           = e(D.movement.dynamic_speed_ramp_tolerance),
        dyn_ramp_look          = e(D.movement.dynamic_speed_ramp_look_distance),
        waypoint_tolerance     = e(D.movement.waypoint_tolerance),
        final_tolerance        = e(D.movement.final_tolerance),

        -- Anti-Detection (Tab 1)
        anti_detection         = e(D.movement.anti_detection),
        max_deviation          = e(D.movement.max_deviation),

        -- Stuck Recovery (Tab 1 advanced)
        stuck_interval         = e(D.movement.stuck_check_interval),
        stuck_distance         = e(D.movement.stuck_distance_min),
        max_stuck              = e(D.movement.max_stuck_attempts),

        -- Path Validation (Tab 1 advanced)
        path_check             = e(D.movement.path_check_interval),
        path_req_retries       = e(D.movement.path_request_max_retries),
        max_repath_failures    = e(D.movement.max_repath_failures),

        -- Deviation Detection (Tab 1 advanced)
        deviation_check_interval     = e(D.movement.deviation_check_interval),
        deviation_threshold          = e(D.movement.deviation_threshold),
        deviation_vertical_threshold = e(D.movement.deviation_vertical_threshold),
        deviation_corridor_factor    = e(D.movement.deviation_corridor_factor),
        repath_cooldown              = e(D.movement.repath_cooldown),
        max_deviation_repaths        = e(D.movement.max_deviation_repaths),

        -- String-Pull Tuning (Tab 2)
        sp_deviation           = e(D.movement.string_pull_deviation),
        sp_heading             = e(D.movement.string_pull_heading),
        sp_wall_dist           = e(D.movement.string_pull_wall_dist),
        densify_seg            = e(D.movement.densify_segment_length),

        -- Optimization (Tab 2)
        optimize               = e(D.movement.optimize),
        allow_partial          = e(D.movement.allow_partial),

        -- Terrain Costs (Tab 2)
        filter_ground          = e(D.movement.filter_ground),
        filter_water           = e(D.movement.filter_water),
        filter_lava            = e(D.movement.filter_lava),

        -- Indoor (Tab 2)
        corridor               = e(D.movement.use_corridor_indoor),
        corridor_probe         = e(D.movement.corridor_probe_dist),

        -- Wall Clearance (Tab 2)
        wall_clearance_en      = e(D.movement.wall_clearance_enabled),
        wall_clearance         = e(D.movement.wall_clearance),

        -- Obstacle Avoidance (Tab 3)
        proactive_obstacle     = e(D.movement.proactive_obstacle_check),
        obstacle_interval      = e(D.movement.proactive_obstacle_interval),
        avoidance_radius       = e(D.obstacles.avoidance_radius),
        max_zones              = e(D.obstacles.max_zones),
        zone_ttl               = e(D.obstacles.zone_ttl),

        -- Obstacle Costs (Tab 3 advanced)
        avoidance_cost         = e(D.obstacles.avoidance_cost),
        zone_prune             = e(D.obstacles.zone_prune_dist),

        -- Reactive Probing (Tab 3 advanced)
        probe_distance         = e(D.obstacles.probe_distance),
        probe_spread           = e(D.obstacles.probe_spread_deg),
        probe_height           = e(D.obstacles.probe_height_offset),

        -- Proactive Lookahead (Tab 3 advanced)
        look_height            = e(D.obstacles.lookahead_height_offset),
        look_spread            = e(D.obstacles.lookahead_spread_deg),
        look_segments          = e(D.obstacles.lookahead_segments),

        -- Debug (Tab 4)
        log_severity           = e(D.movement.log_severity),
        debug_verbose          = e(D.movement.debug_verbose),
        debug_mode             = e(D.debug.debug_mode),

        -- Visualization (Debug tab)
        viz_master             = e(D.debug.viz_master),
        viz_path               = e(D.debug.viz_path),
        viz_destination        = e(D.debug.viz_destination),
        viz_obstacles          = e(D.debug.viz_obstacles),
        viz_corridor           = e(D.debug.viz_corridor),
        viz_state              = e(D.debug.viz_state),
    }
end

--------------------------------------------------------------------------------
-- Before-tabs hook: "Show Advanced" toggle
--------------------------------------------------------------------------------

local function render_advanced_toggle(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)

    local destination = _client and _client.get_destination and _client:get_destination() or nil
    local path = _client and _client.get_current_path and _client:get_current_path() or nil
    local path_index = _client and _client.get_path_index and _client:get_path_index() or 0

    local distance_text = "-"
    local player = core and core.object_manager and core.object_manager.get_local_player and core.object_manager.get_local_player()
    if player and player.is_valid and player:is_valid() and destination and player.get_position then
        local pos = player:get_position()
        if pos and pos.dist_to then
            distance_text = string.format("%.1f yd", tonumber(pos:dist_to(destination)) or 0)
        end
    end

    local card_gap = 8
    local cb_size = 14
    local advanced_label = "Advanced"
    local advanced_label_w = window:get_text_size(advanced_label).x
    local advanced_w = cb_size + 6 + advanced_label_w
    local help_w = window:get_text_size("?").x + 10
    local control_w = advanced_w + 12 + help_w
    local cards_width = content_width - control_w - card_gap
    local card_w = math.floor((cards_width - (card_gap * 2)) / 3)
    local card_h = 44

    local nav_state = _health_cache.server_up and "good" or "bad"
    local nav_value = _health_cache.server_up and "Online" or "Offline"

    local path_value = "No Path"
    local path_state = "warn"
    if path and #path > 0 then
        path_value = string.format("%d / %d", math.min(path_index, #path), #path)
        path_state = "good"
    end

    local dest_value = destination and distance_text or "No Target"
    local dest_state = destination and "good" or "warn"

    render_status_card(window, colors, x_start, y_offset, card_w, "Nav Server", nav_value, nav_state)
    render_status_card(window, colors, x_start + card_w + card_gap, y_offset, card_w, "Path", path_value, path_state)
    render_status_card(window, colors, x_start + (card_w * 2) + (card_gap * 2), y_offset, card_w, "Destination", dest_value, dest_state)
    attach_tooltip(ui, window, vec2.new(x_start, y_offset), vec2.new(x_start + card_w, y_offset + card_h), UI_TOOLTIPS.nav_server)
    attach_tooltip(ui, window, vec2.new(x_start + card_w + card_gap, y_offset), vec2.new(x_start + (card_w * 2) + card_gap, y_offset + card_h), UI_TOOLTIPS.path_progress)
    attach_tooltip(ui, window, vec2.new(x_start + (card_w * 2) + (card_gap * 2), y_offset), vec2.new(x_start + (card_w * 3) + (card_gap * 2), y_offset + card_h), UI_TOOLTIPS.destination)

    local control_x = x_start + (card_w * 3) + (card_gap * 3)
    local is_on = _menu.show_advanced:get_state()
    local cb_y = y_offset + math.floor((card_h - cb_size) / 2)
    local cb_start = vec2.new(control_x, cb_y)
    local cb_end = vec2.new(control_x + cb_size, cb_y + cb_size)
    local cb_bg = is_on and colors.checkbox_active or colors.checkbox_inactive
    window:render_rect_filled(cb_start, cb_end, cb_bg, 3.0)
    window:render_rect(cb_start, cb_end, colors.checkbox_border, 3.0, 1.0)
    if is_on then
        local pad = 3
        window:render_rect_filled(
            vec2.new(control_x + pad, cb_y + pad),
            vec2.new(control_x + cb_size - pad, cb_y + cb_size - pad),
            color.white(255),
            2.0
        )
    end
    window:render_text(
        enums.window_enums.font_id.FONT_SMALL,
        vec2.new(control_x + cb_size + 6, cb_y - 1),
        is_on and colors.text_primary or colors.text_secondary,
        advanced_label
    )
    local adv_click_start = vec2.new(control_x, cb_y)
    local adv_click_end = vec2.new(control_x + advanced_w, cb_y + cb_size)
    window:is_mouse_hovering_rect_block_movement(adv_click_start, adv_click_end)
    attach_tooltip(ui, window, adv_click_start, adv_click_end, UI_TOOLTIPS.show_advanced)
    if window:is_rect_clicked(adv_click_start, adv_click_end) then
        _menu.show_advanced:set(not is_on)
    end
    render_help_badge(ui, window, colors, control_x + control_w - help_w, cb_y, UI_TOOLTIPS.control_center)

    y_offset = y_offset + card_h + 6
    local sep_start = vec2.new(x_start, y_offset)
    local sep_end = vec2.new(x_start + content_width, y_offset + LAYOUT.separator_height)
    window:render_rect_filled(sep_start, sep_end, colors.separator, 0)
    y_offset = y_offset + 6
    return y_offset
end

--------------------------------------------------------------------------------
-- Settings sync: menu elements -> Client config
--------------------------------------------------------------------------------

local function sync_to_client()
    if not _client then return end

    -- Wall clearance: 0 when disabled, slider value when enabled
    local wall_cl = _menu.wall_clearance_en:get_state() and _menu.wall_clearance:get() or 0
    local log_severity = math.floor(tonumber(_menu.log_severity:get()) or 2)
    if log_severity < 0 then log_severity = 0 end
    if log_severity > 3 then log_severity = 3 end
    if _menu.log_severity:get() ~= log_severity then
        _menu.log_severity:set(log_severity)
    end

    _client:update_config({
        movement = {
            dynamic_speed               = _menu.dynamic_speed:get_state(),
            dynamic_speed_max_tolerance_scale = _menu.dyn_tol_scale:get(),
            dynamic_speed_max_tolerance_bonus = _menu.dyn_tol_bonus:get(),
            dynamic_speed_ramp_z_delta  = _menu.dyn_ramp_z:get(),
            dynamic_speed_ramp_tolerance = _menu.dyn_ramp_tol:get(),
            dynamic_speed_ramp_look_distance = _menu.dyn_ramp_look:get(),
            waypoint_tolerance          = _menu.waypoint_tolerance:get(),
            final_tolerance             = _menu.final_tolerance:get(),
            anti_detection              = _menu.anti_detection:get_state(),
            max_deviation               = _menu.max_deviation:get(),
            stuck_check_interval        = _menu.stuck_interval:get(),
            stuck_distance_min          = _menu.stuck_distance:get(),
            max_stuck_attempts          = _menu.max_stuck:get(),
            path_check_interval         = _menu.path_check:get(),
            path_request_max_retries    = _menu.path_req_retries:get(),
            max_repath_failures         = _menu.max_repath_failures:get(),
            optimize                    = _menu.optimize:get_state(),
            string_pull_deviation       = _menu.sp_deviation:get(),
            string_pull_heading         = _menu.sp_heading:get(),
            string_pull_wall_dist       = _menu.sp_wall_dist:get(),
            densify_segment_length      = _menu.densify_seg:get(),
            allow_partial               = _menu.allow_partial:get_state(),
            filter_ground               = _menu.filter_ground:get(),
            filter_water                = _menu.filter_water:get(),
            filter_lava                 = _menu.filter_lava:get(),
            use_corridor_indoor         = _menu.corridor:get_state(),
            corridor_probe_dist         = _menu.corridor_probe:get(),
            wall_clearance              = wall_cl,
            proactive_obstacle_check    = _menu.proactive_obstacle:get_state(),
            proactive_obstacle_interval = _menu.obstacle_interval:get(),
            deviation_check_interval     = _menu.deviation_check_interval:get(),
            deviation_threshold          = _menu.deviation_threshold:get(),
            deviation_vertical_threshold = _menu.deviation_vertical_threshold:get(),
            deviation_corridor_factor    = _menu.deviation_corridor_factor:get(),
            repath_cooldown              = _menu.repath_cooldown:get(),
            max_deviation_repaths        = _menu.max_deviation_repaths:get(),
            log_severity                = log_severity,
            debug_verbose               = _menu.debug_verbose:get_state(),
        },
        obstacles = {
            avoidance_radius        = _menu.avoidance_radius:get(),
            max_zones               = _menu.max_zones:get(),
            zone_ttl                = _menu.zone_ttl:get(),
            avoidance_cost          = _menu.avoidance_cost:get(),
            zone_prune_dist         = _menu.zone_prune:get(),
            probe_distance          = _menu.probe_distance:get(),
            probe_spread_deg        = _menu.probe_spread:get(),
            probe_height_offset     = _menu.probe_height:get(),
            lookahead_height_offset = _menu.look_height:get(),
            lookahead_spread_deg    = _menu.look_spread:get(),
            lookahead_segments      = _menu.look_segments:get(),
        },
    })
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Initialize the SentinelNavClient settings UI
---@param client table The SentinelNavClient Client instance
function Window.init(client)
    if _initialized then return end

    _client = client
    _menu = create_menu_elements()

    -- Create the AstroUI window
    _ui = AstroUI.new({
        id = "sentinel_nav_client",
        title = "Sentinel Navigation Control Center",
        default_x = 560,
        default_y = 120,
        default_w = 760,
        default_h = 760,
        theme = "apple",
        render_layer = 1,
    })

    -- Build per-tab reset mappings
    local D = Defaults
    _reset_mappings = {
        movement = {
            { _menu.dynamic_speed,               D.movement.dynamic_speed },
            { _menu.dyn_tol_scale,               D.movement.dynamic_speed_max_tolerance_scale },
            { _menu.dyn_tol_bonus,               D.movement.dynamic_speed_max_tolerance_bonus },
            { _menu.dyn_ramp_z,                  D.movement.dynamic_speed_ramp_z_delta },
            { _menu.dyn_ramp_tol,                D.movement.dynamic_speed_ramp_tolerance },
            { _menu.dyn_ramp_look,               D.movement.dynamic_speed_ramp_look_distance },
            { _menu.waypoint_tolerance,          D.movement.waypoint_tolerance },
            { _menu.final_tolerance,             D.movement.final_tolerance },
            { _menu.anti_detection,              D.movement.anti_detection },
            { _menu.max_deviation,               D.movement.max_deviation },
            { _menu.stuck_interval,              D.movement.stuck_check_interval },
            { _menu.stuck_distance,              D.movement.stuck_distance_min },
            { _menu.max_stuck,                   D.movement.max_stuck_attempts },
            { _menu.path_check,                  D.movement.path_check_interval },
            { _menu.path_req_retries,            D.movement.path_request_max_retries },
            { _menu.max_repath_failures,         D.movement.max_repath_failures },
            { _menu.deviation_check_interval,    D.movement.deviation_check_interval },
            { _menu.deviation_threshold,         D.movement.deviation_threshold },
            { _menu.deviation_vertical_threshold,D.movement.deviation_vertical_threshold },
            { _menu.deviation_corridor_factor,   D.movement.deviation_corridor_factor },
            { _menu.repath_cooldown,             D.movement.repath_cooldown },
            { _menu.max_deviation_repaths,       D.movement.max_deviation_repaths },
        },
        pathfinding = {
            { _menu.optimize,          D.movement.optimize },
            { _menu.sp_deviation,      D.movement.string_pull_deviation },
            { _menu.sp_heading,        D.movement.string_pull_heading },
            { _menu.sp_wall_dist,      D.movement.string_pull_wall_dist },
            { _menu.densify_seg,       D.movement.densify_segment_length },
            { _menu.allow_partial,     D.movement.allow_partial },
            { _menu.filter_ground,     D.movement.filter_ground },
            { _menu.filter_water,      D.movement.filter_water },
            { _menu.filter_lava,       D.movement.filter_lava },
            { _menu.corridor,          D.movement.use_corridor_indoor },
            { _menu.corridor_probe,    D.movement.corridor_probe_dist },
            { _menu.wall_clearance_en, D.movement.wall_clearance_enabled },
            { _menu.wall_clearance,    D.movement.wall_clearance },
        },
        obstacles = {
            { _menu.proactive_obstacle, D.movement.proactive_obstacle_check },
            { _menu.obstacle_interval,  D.movement.proactive_obstacle_interval },
            { _menu.avoidance_radius,   D.obstacles.avoidance_radius },
            { _menu.max_zones,          D.obstacles.max_zones },
            { _menu.zone_ttl,           D.obstacles.zone_ttl },
            { _menu.avoidance_cost,     D.obstacles.avoidance_cost },
            { _menu.zone_prune,         D.obstacles.zone_prune_dist },
            { _menu.probe_distance,     D.obstacles.probe_distance },
            { _menu.probe_spread,       D.obstacles.probe_spread_deg },
            { _menu.probe_height,       D.obstacles.probe_height_offset },
            { _menu.look_height,        D.obstacles.lookahead_height_offset },
            { _menu.look_spread,        D.obstacles.lookahead_spread_deg },
            { _menu.look_segments,      D.obstacles.lookahead_segments },
        },
        debug = {
            { _menu.log_severity,   D.movement.log_severity },
            { _menu.debug_verbose,   D.movement.debug_verbose },
            { _menu.debug_mode,      D.debug.debug_mode },
            { _menu.viz_master,      D.debug.viz_master },
            { _menu.viz_path,        D.debug.viz_path },
            { _menu.viz_destination, D.debug.viz_destination },
            { _menu.viz_obstacles,   D.debug.viz_obstacles },
            { _menu.viz_corridor,    D.debug.viz_corridor },
            { _menu.viz_state,       D.debug.viz_state },
        },
    }

    -- "Show Advanced" toggle above tab bar
    _ui._before_tabs_fn = render_advanced_toggle

    -- Register tabs
    MovementTab.register(_ui, _menu)
    PathfindingTab.register(_ui, _menu)
    ObstaclesTab.register(_ui, _menu)
    DebugTab.register(_ui, _menu, _client, _reset_mappings)

    -- Create 3D Visualizer (self-registers its own render callback)
    _visualizer = Visualizer:new(_client, _menu, function()
        return DebugTab.get_preview_data()
    end)

    -- Always start with window closed; user opens via menu button
    _ui.menu.enable:set(false)

    _initialized = true
end

---Called every render frame
function Window.on_render()
    if not _initialized or not _ui then return end
    refresh_health_if_due()
    sync_to_client()
    DebugTab.update(_client, _menu)
    _ui:on_render()
end

---Called in the menu render callback
function Window.on_menu_render()
    if not _initialized or not _ui then return end
    _ui:on_menu_render()
end

---Get the UI instance
---@return table|nil
function Window.get_ui()
    return _ui
end

---Get menu elements (for external read access)
---@return table|nil
function Window.get_menu()
    return _menu
end

return Window
