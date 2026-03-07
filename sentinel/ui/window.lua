local SentinelUI = require("ui/lib/sentinel_ui")
local DashboardTab = require("ui/tabs/dashboard_tab")
local CombatTab = require("ui/tabs/combat_tab")
local BattlegroundTab = require("ui/tabs/battleground_tab")
local GrindTab = require("ui/tabs/grind_tab")
local DebugTab = require("ui/tabs/debug_tab")
local ProfileEditorTab = require("ui/tabs/profile_editor_tab")

local Window = {}

local _initialized = false
local _app = nil
local _ui = nil
local _menu = nil
local _menu_tree = nil
local _open_button = nil

-- Mode: 1 = Battleground, 2 = Grind
local function get_mode()
    return _menu and _menu.bot_mode and _menu.bot_mode:get() or 1
end

local function is_bg_mode()
    return get_mode() == 1
end

local function is_grind_mode()
    return get_mode() == 2
end

-- Class detection: 2 = Paladin
local function is_paladin()
    if not _app then
        return true
    end
    local bb = _app:get_blackboard()
    return (bb:get("player.class_id") or 2) == 2
end

local function queue_selection_key(value)
    local idx = tonumber(value) or 1
    if idx == 2 then
        return "WSG"
    end
    if idx == 3 then
        return "AB"
    end
    if idx == 4 then
        return "EOTS"
    end
    return "AV"
end

local function ensure_menu_controls()
    if not core or not core.menu then
        return
    end
    if not _menu_tree and type(core.menu.tree_node) == "function" then
        _menu_tree = core.menu.tree_node()
    end
    if not _open_button and type(core.menu.button) == "function" then
        _open_button = core.menu.button("sentinel_open_ui")
    end
end

local function fallback_checkbox(default_value)
    local state = default_value == true
    return {
        get_state = function()
            return state
        end,
        set = function(_, value)
            state = value == true
        end,
    }
end

local function fallback_slider_int(default_value)
    local value = tonumber(default_value) or 0
    return {
        get = function()
            return value
        end,
        set = function(_, next_value)
            value = math.floor(tonumber(next_value) or value)
        end,
    }
end

local function menu_checkbox(default_value, id)
    if core and core.menu and type(core.menu.checkbox) == "function" then
        return core.menu.checkbox(default_value, id)
    end
    return fallback_checkbox(default_value)
end

local function menu_slider_int(min_value, max_value, default_value, id)
    if core and core.menu then
        if type(core.menu.slider_int) == "function" then
            return core.menu.slider_int(min_value, max_value, default_value, id)
        end
        if type(core.menu.slider) == "function" then
            local slider = core.menu.slider(min_value, max_value, default_value, id)
            if slider and slider.as_int then
                return slider:as_int()
            end
            return slider
        end
        if type(core.menu.new_slider) == "function" then
            local slider = core.menu.new_slider(min_value, max_value, default_value, id)
            if slider and slider.as_int then
                return slider:as_int()
            end
            return slider
        end
    end
    return fallback_slider_int(default_value)
end

local function create_menu_elements()
    local bg_preferred_mount_id = {
        value = "184865",
        get = function(self)
            return self.value
        end,
        set = function(self, value)
            self.value = tostring(value or "")
        end,
    }
    return {
        -- Global
        bot_mode = menu_slider_int(1, 2, 1, "sentinel_ui_bot_mode"),
        combat_enabled = menu_checkbox(true, "sentinel_ui_combat_enabled"),
        burst_enabled = menu_checkbox(true, "sentinel_ui_burst_enabled"),
        combat_low_health_threshold = menu_slider_int(15, 70, 35, "sentinel_ui_combat_low_health_threshold"),
        combat_retreat_outnumber_delta = menu_slider_int(1, 5, 2, "sentinel_ui_combat_retreat_outnumber_delta"),

        -- Paladin-specific
        allow_estimated_twist = menu_checkbox(false, "sentinel_ui_allow_estimated_twist"),
        twist_window_ms = menu_slider_int(200, 450, 350, "sentinel_ui_twist_window_ms"),
        twist_mode = menu_slider_int(1, 2, 1, "sentinel_ui_twist_mode"),
        preferred_blessing = menu_slider_int(1, 2, 1, "sentinel_ui_preferred_blessing"),

        -- Battleground
        bg_enabled = menu_checkbox(true, "sentinel_ui_bg_enabled"),
        bg_auto_engage = menu_checkbox(true, "sentinel_ui_bg_auto_engage"),
        bg_auto_queue = menu_checkbox(false, "sentinel_ui_bg_auto_queue"),
        bg_post_game_auto_leave = menu_checkbox(true, "sentinel_ui_bg_post_game_auto_leave"),
        bg_auto_mount = menu_checkbox(true, "sentinel_ui_bg_auto_mount"),
        bg_low_health_threshold = menu_slider_int(15, 70, 35, "sentinel_ui_bg_low_health_threshold"),
        bg_engage_outnumber_grace = menu_slider_int(0, 3, 1, "sentinel_ui_bg_engage_outnumber_grace"),
        bg_retreat_outnumber_delta = menu_slider_int(1, 5, 2, "sentinel_ui_bg_retreat_outnumber_delta"),
        bg_queue_selection = menu_slider_int(1, 4, 1, "sentinel_ui_bg_queue_selection"),
        bg_mount_distance = menu_slider_int(10, 120, 45, "sentinel_ui_bg_mount_distance"),
        bg_preferred_mount_id = bg_preferred_mount_id,

        -- Grind
        grind_enabled = menu_checkbox(false, "sentinel_ui_grind_enabled"),
        grind_health_eat_pct = menu_slider_int(20, 90, 50, "sentinel_ui_grind_health_eat_pct"),
        grind_mana_drink_pct = menu_slider_int(20, 90, 40, "sentinel_ui_grind_mana_drink_pct"),
        grind_health_flee_pct = menu_slider_int(5, 50, 20, "sentinel_ui_grind_health_flee_pct"),
        grind_max_hostiles = menu_slider_int(1, 8, 3, "sentinel_ui_grind_max_hostiles"),
        grind_show_overlay = menu_checkbox(true, "sentinel_ui_grind_show_overlay"),

        -- Profile Editor
        profile_editor_hotspot_radius = menu_slider_int(10, 100, 40, "sentinel_ui_profile_editor_hotspot_radius"),
    }
end

local function register_tabs(ui, app, menu)
    ui:add_tab({ id = "dashboard", label = "Dashboard" }, function(t)
        DashboardTab.render(t, app, menu)
    end)
    ui:add_tab({
        id = "battleground",
        label = "Battleground",
        visible_when = is_bg_mode,
    }, function(t)
        BattlegroundTab.render(t, app, menu)
    end)
    ui:add_tab({
        id = "grind",
        label = "Grind",
        visible_when = is_grind_mode,
    }, function(t)
        GrindTab.render(t, app, menu)
    end)
    ui:add_tab({
        id = "profile_editor",
        label = "Profile Editor",
        visible_when = is_grind_mode,
    }, function(t)
        ProfileEditorTab.render(t, app, menu)
    end)
    ui:add_tab({ id = "combat", label = "Combat" }, function(t)
        CombatTab.render(t, app, menu)
    end)
    ui:add_tab({ id = "debug", label = "Debug" }, function(t)
        DebugTab.render(t, app, menu)
    end)
end

local function seed_runtime_defaults(blackboard)
    local defaults = {
        ["module.bg.queue_join_interval_s"] = 12,
        ["module.bg.queue_accept_delay_min_s"] = 0.6,
        ["module.bg.queue_accept_delay_max_s"] = 1.8,
        ["module.bg.queue_accept_mode"] = "strict_pvp",
        ["module.bg.queue_dependencies_policy"] = "accept_anyway",
        ["module.bg.queue_accept_retry_interval_s"] = 0.35,
        ["module.bg.queue_accept_max_attempts"] = 20,
        ["module.bg.queue_accept_confirm_timeout_s"] = 2.5,
        ["module.bg.queue_join_confirm_timeout_s"] = 5.0,
        ["module.bg.queue_active_without_bg_timeout_s"] = 10.0,
        ["module.bg.post_game_state5_streak_required"] = 1,
        ["module.bg.post_game_leave_initial_delay_s"] = 2.0,
        ["module.bg.post_game_leave_retry_interval_s"] = 1.0,
        ["module.bg.post_game_leave_max_attempts"] = 25,
        ["module.bg.auto_mount"] = true,
        ["module.bg.preferred_mount_id"] = 184865,
        ["module.bg.mount_distance_threshold"] = 45,
        ["module.bg.mount_require_outdoors"] = true,
        ["module.bg.mount_prefer_epic"] = true,
        ["module.bg.mount_micro_stop_for_cast_s"] = 0.45,
        ["module.bg.mount_settle_before_cast_s"] = 0.25,
        ["module.bg.mount_no_cast_grace_s"] = 3.0,
        ["module.bg.pregame_mount_early"] = true,
        ["module.bg.dismount_on_player_threat"] = true,
        ["module.bg.player_threat_scan_radius"] = 35,
        ["module.bg.capture_radius"] = 12,
        ["module.bg.capture_min_hold_s"] = 1.1,
        ["module.bg.objective_approach_mode"] = "adaptive_ring",
        ["module.bg.objective_approach_standoff_yd"] = 8,
        ["module.bg.objective_ring_radius_gy"] = 7,
        ["module.bg.objective_ring_radius_tower"] = 9,
        ["module.bg.objective_ring_radius_node"] = 8,
        ["module.bg.objective_ring_radius_flag"] = 6,
        ["module.bg.objective_ring_variant_count"] = 6,
        ["module.bg.ghost_mode"] = "release_wait",
    }
    for key, value in pairs(defaults) do
        if not blackboard:has(key) then
            blackboard:set(key, value)
        end
    end
end

local function sync_to_runtime()
    if not _app or not _menu then
        return
    end

    local blackboard = _app:get_blackboard()
    local combat = _app:get_module("combat")
    local battleground = _app:get_module("battleground")
    -- Mode sync: enable the active module, disable the other
    local mode = get_mode()
    blackboard:set("module.sentinel.bot_mode", mode == 2 and "grind" or "battleground")

    if combat and combat.set_enabled then
        combat:set_enabled(_menu.combat_enabled:get_state())
    else
        blackboard:set("module.combat.enabled", _menu.combat_enabled:get_state() == true)
    end

    -- BG module: only enabled in BG mode
    local bg_active = mode == 1 and _menu.bg_enabled:get_state() == true
    if battleground and battleground.set_enabled then
        battleground:set_enabled(bg_active)
    else
        blackboard:set("module.bg.enabled", bg_active)
    end

    -- Grind module: only enabled in grind mode
    local grind_active = mode == 2 and _menu.grind_enabled:get_state() == true
    blackboard:set("module.grind.enabled", grind_active)
    blackboard:set("module.grind.show_overlay", _menu.grind_show_overlay:get_state() == true)

    -- BG settings
    blackboard:set("module.bg.auto_engage", _menu.bg_auto_engage:get_state() == true)
    blackboard:set("module.bg.auto_queue", _menu.bg_auto_queue:get_state() == true)
    blackboard:set("module.bg.queue_selection", queue_selection_key(_menu.bg_queue_selection:get()))
    blackboard:set("module.bg.post_game_auto_leave", _menu.bg_post_game_auto_leave:get_state() == true)
    blackboard:set("module.bg.auto_mount", _menu.bg_auto_mount:get_state() == true)
    blackboard:set("module.bg.mount_distance_threshold", _menu.bg_mount_distance:get() or 45)
    blackboard:set("module.bg.preferred_mount_id", tonumber(_menu.bg_preferred_mount_id:get()) or 184865)
    blackboard:set("module.bg.low_health_threshold", (_menu.bg_low_health_threshold:get() or 35) / 100)
    blackboard:set("module.bg.engage_outnumber_grace", _menu.bg_engage_outnumber_grace:get() or 1)
    blackboard:set("module.bg.retreat_outnumber_delta", _menu.bg_retreat_outnumber_delta:get() or 2)

    -- Combat settings
    blackboard:set("module.combat.enable_burst", _menu.burst_enabled:get_state() == true)
    blackboard:set("module.combat.low_health_threshold", (_menu.combat_low_health_threshold:get() or 35) / 100)
    blackboard:set("module.combat.retreat_outnumber_delta", _menu.combat_retreat_outnumber_delta:get() or 2)

    -- Paladin-specific combat settings
    if is_paladin() then
        blackboard:set("module.combat.allow_estimated_twist", _menu.allow_estimated_twist:get_state() == true)
        blackboard:set("module.combat.twist_window_ms", _menu.twist_window_ms:get())
        blackboard:set("module.combat.twist_mode", _menu.twist_mode:get() == 2 and "force" or "auto")
        blackboard:set("module.combat.preferred_blessing", _menu.preferred_blessing:get() == 2 and "kings" or "might")
    end

    -- Grind settings
    blackboard:set("module.grind.health_eat_pct", (_menu.grind_health_eat_pct:get() or 50) / 100)
    blackboard:set("module.grind.mana_drink_pct", (_menu.grind_mana_drink_pct:get() or 40) / 100)
    blackboard:set("module.grind.health_flee_pct", (_menu.grind_health_flee_pct:get() or 20) / 100)
    blackboard:set("module.grind.max_hostiles", _menu.grind_max_hostiles:get() or 3)
end

function Window.init(app)
    if _initialized then
        return
    end

    _app = app
    ensure_menu_controls()
    _menu = create_menu_elements()
    seed_runtime_defaults(_app:get_blackboard())
    _ui = SentinelUI.new({
        id = "sentinel_control",
        title = "Sentinel Control",
        default_x = 560,
        default_y = 120,
        default_w = 820,
        default_h = 700,
        theme = "sentinel",
        render_layer = 1,
    })

    register_tabs(_ui, _app, _menu)
    if _ui and _ui.menu and _ui.menu.enable and _ui.menu.enable.set then
        _ui.menu.enable:set(false)
    end
    sync_to_runtime()
    _initialized = true
end

function Window.shutdown()
    _initialized = false
    _app = nil
    _ui = nil
    _menu = nil
    _menu_tree = nil
    _open_button = nil
end

function Window.on_update()
    if not _initialized then
        return
    end
    sync_to_runtime()
end

function Window.on_render()
    if not _initialized or not _ui then
        return
    end
    _ui:on_render()
end

function Window.on_menu_render()
    if not _initialized then
        return
    end
    ensure_menu_controls()

    if _ui then
        _ui:on_menu_render()
    end

    if _menu_tree and type(_menu_tree.render) == "function" then
        _menu_tree:render("Sentinel", function()
            if _open_button and type(_open_button.render) == "function" and _open_button:render("Open Sentinel UI") then
                local ui = _ui
                if ui and ui.menu and ui.menu.enable and ui.menu.enable.get_state and ui.menu.enable.set then
                    ui.menu.enable:set(not ui.menu.enable:get_state())
                end
            end
        end)
    end
end

function Window.get_ui()
    return _ui
end

function Window.get_menu()
    return _menu
end

return Window
