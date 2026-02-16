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
local Defaults = require("core/Defaults")

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

        -- Deviation Detection (Tab 1 advanced)
        deviation_check_interval     = e(D.movement.deviation_check_interval),
        deviation_threshold          = e(D.movement.deviation_threshold),
        deviation_vertical_threshold = e(D.movement.deviation_vertical_threshold),
        deviation_corridor_factor    = e(D.movement.deviation_corridor_factor),
        repath_cooldown              = e(D.movement.repath_cooldown),
        max_deviation_repaths        = e(D.movement.max_deviation_repaths),

        -- Smoothing (Tab 2)
        smoothing              = e(D.movement.smoothing),
        smooth_iterations      = e(D.movement.smooth_iterations),
        smooth_samples         = e(D.movement.smooth_samples),
        smooth_ratio           = e(D.movement.smooth_ratio),
        corner_angle           = e(D.movement.min_corner_angle),
        keep_originals         = e(D.movement.keep_originals),

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
        render_layer = 1,
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

    -- Always start with window closed; user opens via menu button
    _ui.menu.enable:set(false)

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
