--[[
    SentinelNavClient UI Window Orchestrator

    Creates and manages the AstroUI settings window, registers all tabs,
    renders the Apple HIG control bar (status cards + pill toggle) above
    the tab bar, and syncs menu element values into the Client config
    every frame.
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

local function attach_tooltip(ui, window, start_pos, end_pos, hint)
    if not hint or hint == "" then
        return
    end
    if ui and window:is_mouse_hovering_rect(start_pos, end_pos) then
        ui._tooltip = hint
    end
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
-- Before-tabs hook: Apple HIG control bar (status cards + pill toggle)
--------------------------------------------------------------------------------

--- Render a single status card with Apple HIG rounded-rect styling
local function render_status_card(window, colors, x, y, width, label, value, state)
    local h = 44
    local bg
    if state == "good" then
        bg = color.new(48, 140, 88, 170)
    elseif state == "warn" then
        bg = color.new(170, 120, 30, 170)
    elseif state == "bad" then
        bg = color.new(160, 65, 65, 170)
    else
        bg = colors.bg_card or colors.section_bg
    end

    local card_start = vec2.new(x, y)
    local card_end = vec2.new(x + width, y + h)
    window:render_rect_filled(card_start, card_end, bg, LAYOUT.card_corner_radius)
    window:render_rect(card_start, card_end, colors.section_border, LAYOUT.card_corner_radius, 1)

    -- Label (small, top)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + 10, y + 6), colors.text_secondary, label)

    -- Value (larger, bottom)
    window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG,
        vec2.new(x + 10, y + 22), colors.text_primary, value)

    return y + h + 6
end

--- Render an Apple-style pill toggle (track + sliding thumb + label)
---@return boolean|nil new_state if clicked, nil if not
local function render_pill_toggle(window, colors, x, y, is_on, label)
    local w = LAYOUT.toggle_width
    local h = LAYOUT.toggle_height
    local thumb_size = LAYOUT.toggle_thumb_size
    local margin = LAYOUT.toggle_thumb_margin
    local radius = h / 2

    -- Track
    local track_start = vec2.new(x, y)
    local track_end = vec2.new(x + w, y + h)
    local track_color = is_on
        and (colors.toggle_track_on or colors.secondary_accent)
        or (colors.toggle_track_off or colors.checkbox_inactive)
    window:render_rect_filled(track_start, track_end, track_color, radius)

    -- Thumb
    local thumb_x = is_on and (x + w - thumb_size - margin) or (x + margin)
    local thumb_y = y + margin
    local thumb_color = colors.toggle_thumb or color.new(255, 255, 255, 255)
    window:render_rect_filled(
        vec2.new(thumb_x, thumb_y),
        vec2.new(thumb_x + thumb_size, thumb_y + thumb_size),
        thumb_color, thumb_size / 2)

    -- Label to the right of the toggle
    local label_x = x + w + 6
    local label_y = y + (h - 12) / 2
    local label_color = is_on and colors.text_primary or colors.text_secondary
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(label_x, label_y), label_color, label)

    -- Hit area covers toggle + label
    local label_w = window:get_text_size(label).x
    local hit_start = vec2.new(x, y)
    local hit_end = vec2.new(label_x + label_w, y + h)
    local hovered = window:is_mouse_hovering_rect(hit_start, hit_end)
    if hovered then
        window:is_mouse_hovering_rect_block_movement(hit_start, hit_end)
    end

    local clicked = hovered and window:is_rect_clicked(hit_start, hit_end)
    if clicked then
        return not is_on
    end
    return nil
end

local function render_control_bar(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)

    -- Gather live data
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

    -- Layout: 3 cards + pill toggle on the right
    local card_gap = 8
    local card_h = 44
    local toggle_label = "Advanced"
    local toggle_w = LAYOUT.toggle_width + 6 + window:get_text_size(toggle_label).x
    local cards_width = content_width - toggle_w - card_gap * 2
    local card_w = math.floor((cards_width - (card_gap * 2)) / 3)

    -- Status values
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

    -- Render 3 status cards
    local cx = x_start
    render_status_card(window, colors, cx, y_offset, card_w, "Nav Server", nav_value, nav_state)
    attach_tooltip(ui, window, vec2.new(cx, y_offset), vec2.new(cx + card_w, y_offset + card_h), UI_TOOLTIPS.nav_server)

    cx = cx + card_w + card_gap
    render_status_card(window, colors, cx, y_offset, card_w, "Path", path_value, path_state)
    attach_tooltip(ui, window, vec2.new(cx, y_offset), vec2.new(cx + card_w, y_offset + card_h), UI_TOOLTIPS.path_progress)

    cx = cx + card_w + card_gap
    render_status_card(window, colors, cx, y_offset, card_w, "Destination", dest_value, dest_state)
    attach_tooltip(ui, window, vec2.new(cx, y_offset), vec2.new(cx + card_w, y_offset + card_h), UI_TOOLTIPS.destination)

    -- Render pill toggle (vertically centered with cards)
    local is_on = _menu.show_advanced:get_state()
    local toggle_x = x_start + content_width - toggle_w
    local toggle_y = y_offset + math.floor((card_h - LAYOUT.toggle_height) / 2)

    local new_state = render_pill_toggle(window, colors, toggle_x, toggle_y, is_on, toggle_label)
    if new_state ~= nil then
        _menu.show_advanced:set(new_state)
    end
    attach_tooltip(ui, window,
        vec2.new(toggle_x, toggle_y),
        vec2.new(toggle_x + toggle_w, toggle_y + LAYOUT.toggle_height),
        UI_TOOLTIPS.show_advanced)

    -- Separator below control bar
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

    -- Apple HIG control bar above tab bar
    _ui._before_tabs_fn = render_control_bar

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
