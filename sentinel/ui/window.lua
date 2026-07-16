local SentinelUI = require("ui/lib/sentinel_ui")
local QuestWindow = require("ui/quest_ui/window")

local Window = {}

local _initialized = false
local _app = nil
local _ui = nil
local _menu = nil
local _menu_tree = nil
local _open_button = nil

-- Mode: Quest only (mode 3)
local function get_mode()
    return 3
end

local function is_quest_mode()
    return true
end

-- Class detection: 2 = Paladin
local function is_paladin()
    if not _app then
        return false
    end
    local bb = _app:get_blackboard()
    local class_id = bb:get("player.class_id")
    return class_id == 2
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

local function menu_combo(default_value, options, id)
    if core and core.menu and core.menu.combo then
        return core.menu.combo(default_value, options, id)
    end
    return { get = function() return default_value end, set = function() end }
end

local function create_menu_elements()
    return {
        -- Combat (global, always available)
        combat_enabled = menu_checkbox(true, "sentinel_ui_combat_enabled"),
        burst_enabled = menu_checkbox(true, "sentinel_ui_burst_enabled"),
        combat_low_health_threshold = menu_slider_int(15, 70, 35, "sentinel_ui_combat_low_health_threshold"),
        combat_retreat_outnumber_delta = menu_slider_int(1, 5, 2, "sentinel_ui_combat_retreat_outnumber_delta"),

        -- Paladin-specific
        allow_estimated_twist = menu_checkbox(false, "sentinel_ui_allow_estimated_twist"),
        twist_window_ms = menu_slider_int(200, 450, 350, "sentinel_ui_twist_window_ms"),
        twist_mode = menu_slider_int(1, 2, 1, "sentinel_ui_twist_mode"),
        preferred_blessing = menu_slider_int(1, 2, 1, "sentinel_ui_preferred_blessing"),

        -- Questing
        quest_enabled = menu_checkbox(true, "sentinel_ui_quest_enabled"),
        quest_auto_start = menu_checkbox(true, "sentinel_ui_quest_auto_start"),
        quest_auto_replan = menu_checkbox(true, "sentinel_ui_quest_auto_replan"),
        quest_replan_interval = menu_slider_int(1, 30, 5, "sentinel_ui_quest_replan_interval"),

        -- Quest Selection
        quest_max_active = menu_slider_int(1, 5, 3, "sentinel_ui_quest_max_active"),
        quest_skip_elites = menu_checkbox(true, "sentinel_ui_quest_skip_elites"),
        quest_skip_escorts = menu_checkbox(false, "sentinel_ui_quest_skip_escorts"),
        quest_skip_dungeons = menu_checkbox(true, "sentinel_ui_quest_skip_dungeons"),
        quest_skip_pvp = menu_checkbox(true, "sentinel_ui_quest_skip_pvp"),
        quest_max_travel = menu_slider_int(500, 5000, 1800, "sentinel_ui_quest_max_travel"),
        quest_min_xp_per_min = menu_slider_int(100, 2000, 500, "sentinel_ui_quest_min_xp_per_min"),

        -- Combat Integration
        quest_combat_enabled = menu_checkbox(true, "sentinel_ui_quest_combat_enabled"),
        quest_combat_health_flee = menu_slider_int(10, 50, 20, "sentinel_ui_quest_combat_health_flee"),
        quest_combat_max_hostiles = menu_slider_int(1, 5, 3, "sentinel_ui_quest_combat_max_hostiles"),

        -- Inventory Management
        quest_min_bag_slots = menu_slider_int(2, 10, 4, "sentinel_ui_quest_min_bag_slots"),
        quest_vendor_threshold = menu_slider_int(50, 95, 80, "sentinel_ui_quest_vendor_threshold"),
        quest_repair_threshold = menu_slider_int(10, 80, 40, "sentinel_ui_quest_repair_threshold"),
        quest_min_food = menu_slider_int(0, 20, 2, "sentinel_ui_quest_min_food"),
        quest_min_water = menu_slider_int(0, 20, 2, "sentinel_ui_quest_min_water"),

        -- Travel Optimization
        quest_use_flight_paths = menu_checkbox(true, "sentinel_ui_quest_use_flight_paths"),
        quest_hearthstone_threshold = menu_slider_int(5, 30, 10, "sentinel_ui_quest_hearthstone_threshold"),
        quest_max_walk_distance = menu_slider_int(200, 2000, 800, "sentinel_ui_quest_max_walk_distance"),

        -- Rewards
        quest_reward_policy = menu_combo(1, {"Vendor Value", "Upgrade (ilvl)", "Keep All"}, "sentinel_ui_quest_reward_policy"),
        quest_always_keep_quest_items = menu_checkbox(true, "sentinel_ui_quest_keep_quest_items"),

        -- Visual
        quest_show_overlay = menu_checkbox(true, "sentinel_ui_quest_show_overlay"),
        quest_show_path = menu_checkbox(true, "sentinel_ui_quest_show_path"),
        quest_show_objectives = menu_checkbox(true, "sentinel_ui_quest_show_objectives"),
        quest_overlay_scale = menu_slider_int(80, 150, 100, "sentinel_ui_quest_overlay_scale"),

        -- Debug
        quest_debug_logging = menu_checkbox(false, "sentinel_ui_quest_debug_logging"),
        quest_verbose = menu_checkbox(false, "sentinel_ui_quest_verbose"),
    }
end

local function register_tabs(ui, app, menu)
    -- Quest UI tabs using SentinelUI declarative API
    -- This properly renders checkboxes, sliders, combos using core.menu elements
    
    local content_pad = 16 -- LAYOUT.padding_side
    
    ui:add_tab({ id = "quest_dashboard", label = "Quest Dashboard", visible_when = is_quest_mode }, function(t)
        -- Dashboard is read-only info display, use custom render
        t:custom_render({
            render_fn = function(ui_instance, y_offset)
                local window = ui_instance.window
                local w = window:get_size()
                local content_w = w.x - content_pad * 2
                -- render_dashboard_tab expects (window, x, y, w, h) and returns new y
                -- We call it with the current y_offset and return the result
                local new_y = QuestWindow.render_dashboard_tab(window, content_pad, y_offset, content_w, 500)
                return new_y
            end
        })
    end)
    
    ui:add_tab({ id = "quest_planner", label = "Quest Planner", visible_when = is_quest_mode }, function(t)
        -- Planner is read-only info display, use custom render
        t:custom_render({
            render_fn = function(ui_instance, y_offset)
                local window = ui_instance.window
                local w = window:get_size()
                local content_w = w.x - content_pad * 2
                local new_y = QuestWindow.render_planner_tab(window, content_pad, y_offset, content_w, 500)
                return new_y
            end
        })
    end)
    
    ui:add_tab({ id = "quest_profiles", label = "Quest Profiles", visible_when = is_quest_mode }, function(t)
        -- Profiles tab - mix of info and actions
        t:custom_render({
            render_fn = function(ui_instance, y_offset)
                local window = ui_instance.window
                local w = window:get_size()
                local content_w = w.x - content_pad * 2
                local new_y = QuestWindow.render_profiles_tab(window, content_pad, y_offset, content_w, 500)
                return new_y
            end
        })
    end)
    
    ui:add_tab({ id = "quest_settings", label = "Quest Settings", visible_when = is_quest_mode }, function(t)
        -- Quest Selection section
        t:checkbox_grid({
            label = "Quest Selection",
            columns = 2,
            elements = {
                { element = menu.quest_skip_elites, label = "Skip Elite Quests" },
                { element = menu.quest_skip_escorts, label = "Skip Escort Quests" },
                { element = menu.quest_skip_dungeons, label = "Skip Dungeon Chains" },
                { element = menu.quest_skip_pvp, label = "Skip PvP Zones" },
            }
        })
        
        t:slider_list({
            label = "Travel & XP Thresholds",
            elements = {
                { element = menu.quest_max_travel, label = "Max Travel Distance", suffix = " yd" },
                { element = menu.quest_min_xp_per_min, label = "Min XP/Minute", suffix = " XP/min" },
                { element = menu.quest_max_active, label = "Max Active Quests" },
            }
        })
        
        -- Combat Integration section
        t:checkbox_grid({
            label = "Combat Integration",
            columns = 1,
            elements = {
                { element = menu.quest_combat_enabled, label = "Enable Combat During Quests" },
            }
        })
        
        t:slider_list({
            label = "Combat Thresholds",
            elements = {
                { element = menu.quest_combat_health_flee, label = "Flee Health Threshold", suffix = "%" },
                { element = menu.quest_combat_max_hostiles, label = "Max Simultaneous Hostiles" },
            }
        })
        
        -- Inventory Management section
        t:slider_list({
            label = "Inventory Management",
            elements = {
                { element = menu.quest_min_bag_slots, label = "Min Free Bag Slots" },
                { element = menu.quest_vendor_threshold, label = "Vendor Threshold", suffix = "%" },
                { element = menu.quest_repair_threshold, label = "Repair Threshold", suffix = "%" },
                { element = menu.quest_min_food, label = "Min Food Stacks" },
                { element = menu.quest_min_water, label = "Min Water Stacks" },
            }
        })
        
        -- Travel Optimization section
        t:checkbox_grid({
            label = "Travel Optimization",
            columns = 1,
            elements = {
                { element = menu.quest_use_flight_paths, label = "Use Flight Paths" },
            }
        })
        
        t:slider_list({
            label = "Travel Thresholds",
            elements = {
                { element = menu.quest_hearthstone_threshold, label = "Hearthstone Threshold", suffix = " min" },
                { element = menu.quest_max_walk_distance, label = "Max Walk Before Mount/Flight", suffix = " yd" },
            }
        })
        
        -- Rewards section
        t:combo_list({
            label = "Reward Selection",
            elements = {
                { element = menu.quest_reward_policy, label = "Reward Policy", options = {"Vendor Value", "Upgrade (ilvl)", "Keep All"} },
            }
        })
        
        t:checkbox_grid({
            label = "Reward Options",
            columns = 1,
            elements = {
                { element = menu.quest_always_keep_quest_items, label = "Always Keep Quest Items" },
            }
        })
        
        -- Visual/Debug section
        t:checkbox_grid({
            label = "Visual Options",
            columns = 2,
            elements = {
                { element = menu.quest_show_overlay, label = "Show Quest Overlay" },
                { element = menu.quest_show_path, label = "Show Path Visualization" },
                { element = menu.quest_show_objectives, label = "Show Objectives on Map" },
                { element = menu.quest_debug_logging, label = "Debug Logging" },
            }
        })
        
        t:slider_list({
            label = "Overlay Scale",
            elements = {
                { element = menu.quest_overlay_scale, label = "Overlay Scale", suffix = "%" },
            }
        })
    end)
end

local function seed_runtime_defaults(blackboard)
    local defaults = {
        ["module.quest.enabled"] = false,
        ["module.quest.auto_start"] = true,
        ["module.quest.auto_replan"] = true,
        ["module.quest.replan_interval"] = 5,
        ["module.quest.max_active"] = 3,
        ["module.quest.skip_elites"] = true,
        ["module.quest.skip_escorts"] = false,
        ["module.quest.skip_dungeons"] = true,
        ["module.quest.skip_pvp"] = true,
        ["module.quest.max_travel"] = 1800,
        ["module.quest.min_xp_per_min"] = 500,
        ["module.quest.combat_enabled"] = true,
        ["module.quest.combat_health_flee"] = 0.20,
        ["module.quest.combat_max_hostiles"] = 3,
        ["module.quest.min_bag_slots"] = 4,
        ["module.quest.vendor_threshold_pct"] = 80,
        ["module.quest.repair_threshold_pct"] = 40,
        ["module.quest.min_food_stacks"] = 2,
        ["module.quest.min_water_stacks"] = 2,
        ["module.quest.use_flight_paths"] = true,
        ["module.quest.hearthstone_threshold_minutes"] = 10,
        ["module.quest.max_walk_distance"] = 800,
        ["module.quest.reward_policy"] = "vendor_value",
        ["module.quest.keep_quest_items"] = true,
        ["module.quest.show_overlay"] = true,
        ["module.quest.show_path"] = true,
        ["module.quest.show_objectives"] = true,
        ["module.quest.overlay_scale"] = 1.0,
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
    local quest = _app:get_module("quest")
    local mode = get_mode()

    -- Only Quest mode is supported now
    local bot_mode = mode == 3 and "quest" or "quest"
    blackboard:set("module.sentinel.bot_mode", bot_mode)

    -- Combat (global, always available)
    if combat and combat.set_enabled then
        combat:set_enabled(_menu.combat_enabled:get_state())
    else
        blackboard:set("module.combat.enabled", _menu.combat_enabled:get_state() == true)
    end

    -- Quest module: only enabled in quest mode
    local quest_active = mode == 3 and _menu.quest_enabled:get_state() == true
    if quest and quest.set_enabled then
        quest:set_enabled(quest_active)
    else
        blackboard:set("module.quest.enabled", quest_active)
    end

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

    -- Quest settings
    blackboard:set("module.quest.enabled", _menu.quest_enabled:get_state())
    blackboard:set("module.quest.auto_start", _menu.quest_auto_start:get_state())
    blackboard:set("module.quest.auto_replan", _menu.quest_auto_replan:get_state())
    blackboard:set("module.quest.replan_interval", _menu.quest_replan_interval:get())
    blackboard:set("module.quest.max_active", _menu.quest_max_active:get())
    blackboard:set("module.quest.skip_elites", _menu.quest_skip_elites:get_state())
    blackboard:set("module.quest.skip_escorts", _menu.quest_skip_escorts:get_state())
    blackboard:set("module.quest.skip_dungeons", _menu.quest_skip_dungeons:get_state())
    blackboard:set("module.quest.skip_pvp", _menu.quest_skip_pvp:get_state())
    blackboard:set("module.quest.max_travel", _menu.quest_max_travel:get())
    blackboard:set("module.quest.min_xp_per_min", _menu.quest_min_xp_per_min:get())
    blackboard:set("module.quest.combat_enabled", _menu.quest_combat_enabled:get_state())
    blackboard:set("module.quest.combat_health_flee", _menu.quest_combat_health_flee:get() / 100)
    blackboard:set("module.quest.combat_max_hostiles", _menu.quest_combat_max_hostiles:get())
    blackboard:set("module.quest.min_bag_slots", _menu.quest_min_bag_slots:get())
    blackboard:set("module.quest.vendor_threshold_pct", _menu.quest_vendor_threshold:get())
    blackboard:set("module.quest.repair_threshold_pct", _menu.quest_repair_threshold:get())
    blackboard:set("module.quest.min_food_stacks", _menu.quest_min_food:get())
    blackboard:set("module.quest.min_water_stacks", _menu.quest_min_water:get())
    blackboard:set("module.quest.use_flight_paths", _menu.quest_use_flight_paths:get_state())
    blackboard:set("module.quest.hearthstone_threshold_minutes", _menu.quest_hearthstone_threshold:get())
    blackboard:set("module.quest.max_walk_distance", _menu.quest_max_walk_distance:get())
    blackboard:set("module.quest.reward_policy", _menu.quest_reward_policy:get())
    blackboard:set("module.quest.keep_quest_items", _menu.quest_always_keep_quest_items:get_state())
    blackboard:set("module.quest.show_overlay", _menu.quest_show_overlay:get_state())
    blackboard:set("module.quest.show_path", _menu.quest_show_path:get_state())
    blackboard:set("module.quest.show_objectives", _menu.quest_show_objectives:get_state())
    blackboard:set("module.quest.overlay_scale", _menu.quest_overlay_scale:get() / 100)
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

    -- Initialize Quest UI
    QuestWindow.init(app)

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
    QuestWindow.shutdown()
end

function Window.on_update()
    if not _initialized then
        return
    end
    sync_to_runtime()
    QuestWindow.on_update()
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