--[[
    NavLib UI Window Orchestrator

    Creates and manages the AstroUI settings window, registers all tabs,
    renders the "Show Advanced" toggle above the tab bar, and syncs menu
    element values into the Facade config every frame.
]]

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("shared/AstroUI")

-- Tab modules
local MovementTab    = require("ui/tabs/movement_tab")
local PathfindingTab = require("ui/tabs/pathfinding_tab")
local ObstaclesTab   = require("ui/tabs/obstacles_tab")
local DebugTab       = require("ui/tabs/debug_tab")
local Visualizer     = require("core/Visualizer")

local LAYOUT = AstroUI.LAYOUT

local Window = {}

-- Private state
local _ui = nil              -- RotationSettingsUI instance
local _initialized = false
local _facade = nil          -- NavLib Facade instance
local _menu = nil            -- menu elements table
local _visualizer = nil      -- Visualizer instance

--------------------------------------------------------------------------------
-- Menu element creation
--------------------------------------------------------------------------------

local function create_menu_elements()
    local cb    = core.menu.checkbox
    local si    = core.menu.slider_int
    local sf    = core.menu.slider_float
    local combo = core.menu.combobox

    return {
        -- Window-level
        show_advanced = cb(false, "navlib_show_advanced"),

        -- Movement basics (Tab 1)
        dynamic_speed      = cb(true, "navlib_dynamic_speed"),
        waypoint_tolerance = sf(0.5, 10.0, 3.0, "navlib_waypoint_tolerance"),
        final_tolerance    = sf(0.5, 5.0, 1.5, "navlib_final_tolerance"),

        -- Anti-Detection (Tab 1)
        anti_detection = cb(false, "navlib_anti_detection"),
        max_deviation  = sf(1.0, 20.0, 3.0, "navlib_max_deviation"),

        -- Stuck Recovery (Tab 1 advanced)
        stuck_interval = sf(0.25, 5.0, 0.5, "navlib_stuck_interval"),
        stuck_distance = sf(0.1, 5.0, 0.25, "navlib_stuck_distance"),
        max_stuck      = si(1, 10, 6, "navlib_max_stuck"),

        -- Path Validation (Tab 1 advanced)
        path_check = sf(1.0, 30.0, 8.0, "navlib_path_check"),

        -- Deviation Detection (Tab 1 advanced)
        deviation_check_interval     = sf(0.1, 5.0, 1.0, "navlib_deviation_check_interval"),
        deviation_threshold          = sf(1.0, 20.0, 5.0, "navlib_deviation_threshold"),
        deviation_vertical_threshold = sf(0.5, 10.0, 3.0, "navlib_deviation_vertical_threshold"),
        deviation_corridor_factor    = sf(0.1, 2.0, 0.75, "navlib_deviation_corridor_factor"),
        repath_cooldown              = sf(0.1, 5.0, 1.0, "navlib_repath_cooldown"),
        max_deviation_repaths        = si(1, 10, 3, "navlib_max_deviation_repaths"),

        -- Smoothing (Tab 2)
        smoothing         = combo(2, "navlib_smoothing"),  -- default: Chaikin (index 2)
        smooth_iterations = si(1, 5, 3, "navlib_smooth_iterations"),
        smooth_samples    = si(5, 50, 10, "navlib_smooth_samples"),
        smooth_ratio      = si(50, 95, 50, "navlib_smooth_ratio_pct"),
        corner_angle      = sf(0.0, 120.0, 90.0, "navlib_corner_angle"),
        keep_originals    = cb(false, "navlib_keep_originals"),

        -- Optimization (Tab 2)
        optimize      = cb(true, "navlib_optimize"),
        allow_partial = cb(true, "navlib_allow_partial"),

        -- Terrain Costs (Tab 2)
        filter_ground = sf(0.1, 10.0, 1.0, "navlib_filter_ground"),
        filter_water  = sf(0.1, 100.0, 10.0, "navlib_filter_water"),
        filter_lava   = sf(0.1, 1000.0, 100.0, "navlib_filter_lava"),

        -- Indoor (Tab 2)
        corridor       = cb(true, "navlib_corridor"),
        corridor_probe = sf(5.0, 30.0, 15.0, "navlib_corridor_probe"),

        -- Wall Clearance (Tab 2)
        wall_clearance_en = cb(true, "navlib_wall_clearance_en"),
        wall_clearance    = sf(0.5, 5.0, 1.0, "navlib_wall_clearance"),

        -- Obstacle Avoidance (Tab 3)
        proactive_obstacle = cb(true, "navlib_proactive_obstacle"),
        obstacle_interval  = sf(0.5, 5.0, 1.5, "navlib_obstacle_interval"),
        avoidance_radius   = sf(1.0, 10.0, 3.0, "navlib_avoidance_radius"),
        max_zones          = si(1, 20, 5, "navlib_max_zones"),
        zone_ttl           = sf(30.0, 300.0, 120.0, "navlib_zone_ttl"),

        -- Obstacle Costs (Tab 3 advanced)
        avoidance_cost = sf(1.0, 20.0, 5.0, "navlib_avoidance_cost"),
        zone_prune     = sf(50.0, 500.0, 100.0, "navlib_zone_prune"),

        -- Reactive Probing (Tab 3 advanced)
        probe_distance = sf(2.0, 20.0, 8.0, "navlib_probe_distance"),
        probe_spread   = sf(5.0, 45.0, 20.0, "navlib_probe_spread"),
        probe_height   = sf(0.5, 5.0, 1.0, "navlib_probe_height"),

        -- Proactive Lookahead (Tab 3 advanced)
        look_height   = sf(0.5, 5.0, 1.5, "navlib_look_height"),
        look_spread   = sf(5.0, 45.0, 15.0, "navlib_look_spread"),
        look_segments = si(1, 10, 3, "navlib_look_segments"),

        -- Debug (Tab 4)
        debug_verbose = cb(false, "navlib_debug_verbose"),
        debug_mode    = si(0, 12, 0, "navlib_debug_mode"),

        -- Visualization (Debug tab)
        viz_master      = cb(true,  "navlib_viz_master"),
        viz_path        = cb(true,  "navlib_viz_path"),
        viz_destination = cb(true,  "navlib_viz_destination"),
        viz_obstacles   = cb(true,  "navlib_viz_obstacles"),
        viz_corridor    = cb(true,  "navlib_viz_corridor"),
        viz_state       = cb(true,  "navlib_viz_state"),
    }
end

--------------------------------------------------------------------------------
-- Before-tabs hook: "Show Advanced" toggle
--------------------------------------------------------------------------------

local function render_advanced_toggle(ui, y_offset)
    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    local cb_size = 14
    local cb_start = vec2.new(x_start, y_offset)
    local cb_end   = vec2.new(x_start + cb_size, y_offset + cb_size)

    local is_on = _menu.show_advanced:get_state()

    -- Checkbox box
    local cb_bg = is_on and colors.checkbox_active or colors.checkbox_inactive
    window:render_rect_filled(cb_start, cb_end, cb_bg, 1.0)
    window:render_rect(cb_start, cb_end, colors.checkbox_border, 1.0, 1.0)

    -- Checkmark
    if is_on then
        local pad = 3
        window:render_rect_filled(
            vec2.new(x_start + pad, y_offset + pad),
            vec2.new(x_start + cb_size - pad, y_offset + cb_size - pad),
            color.white(255), 0.5)
    end

    -- Click area (checkbox + label)
    local label = "Show Advanced"
    local label_end_x = x_start + cb_size + 8 + window:get_text_size(label).x
    local click_start = vec2.new(x_start, y_offset)
    local click_end   = vec2.new(label_end_x, y_offset + cb_size)
    window:is_mouse_hovering_rect_block_movement(click_start, click_end)

    if window:is_rect_clicked(click_start, click_end) then
        _menu.show_advanced:set(not is_on)
    end

    -- Label text
    local label_y = y_offset + (cb_size - window:get_text_size(label).y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x_start + cb_size + 8, label_y),
        is_on and colors.text_primary or colors.text_secondary, label)

    y_offset = y_offset + cb_size + 6

    -- Separator
    local window_size = window:get_size()
    local content_width = window_size.x - (2 * LAYOUT.padding_side)
    local sep_start = vec2.new(x_start, y_offset)
    local sep_end   = vec2.new(x_start + content_width, y_offset + 2)
    window:render_rect_filled(sep_start, sep_end, colors.separator, 0)
    y_offset = y_offset + 6

    return y_offset
end

--------------------------------------------------------------------------------
-- Settings sync: menu elements -> Facade config
--------------------------------------------------------------------------------

local function sync_to_facade()
    if not _facade then return end

    -- Resolve smoothing algorithm name from combo index
    local smoothing_id = PathfindingTab.SMOOTHING_IDS[_menu.smoothing:get()] or "chaikin"

    -- Wall clearance: 0 when disabled, slider value when enabled
    local wall_cl = _menu.wall_clearance_en:get_state() and _menu.wall_clearance:get() or 0

    _facade:update_config({
        movement = {
            dynamic_speed               = _menu.dynamic_speed:get_state(),
            waypoint_tolerance          = _menu.waypoint_tolerance:get(),
            final_tolerance             = _menu.final_tolerance:get(),
            anti_detection              = _menu.anti_detection:get_state(),
            max_deviation               = _menu.max_deviation:get(),
            stuck_check_interval        = _menu.stuck_interval:get(),
            stuck_distance_min          = _menu.stuck_distance:get(),
            max_stuck_attempts          = _menu.max_stuck:get(),
            path_check_interval         = _menu.path_check:get(),
            smoothing                   = smoothing_id,
            smooth_iterations           = _menu.smooth_iterations:get(),
            smooth_samples              = _menu.smooth_samples:get(),
            smooth_ratio                = _menu.smooth_ratio:get() / 100,
            min_corner_angle            = _menu.corner_angle:get(),
            keep_originals              = _menu.keep_originals:get_state(),
            optimize                    = _menu.optimize:get_state(),
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

---Initialize the NavLib settings UI
---@param facade table The NavLib Facade instance
function Window.init(facade)
    if _initialized then return end

    _facade = facade
    _menu = create_menu_elements()

    -- Create the AstroUI window
    _ui = AstroUI.new({
        id = "navlib",
        title = "NavLib Settings",
        default_x = 550,
        default_y = 200,
        default_w = 450,
        default_h = 550,
        theme = "neutral",
    })

    -- "Show Advanced" toggle above tab bar
    _ui._before_tabs_fn = render_advanced_toggle

    -- Register tabs
    MovementTab.register(_ui, _menu)
    PathfindingTab.register(_ui, _menu)
    ObstaclesTab.register(_ui, _menu)
    DebugTab.register(_ui, _menu, _facade)

    -- Create 3D Visualizer (self-registers its own render callback)
    _visualizer = Visualizer:new(_facade, _menu)

    _initialized = true
    core.log("[NavLib] Settings UI initialized")
end

---Called every render frame
function Window.on_render()
    if not _initialized or not _ui then return end
    sync_to_facade()
    DebugTab.update(_facade, _menu)
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
