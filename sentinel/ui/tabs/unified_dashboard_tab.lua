local UnifiedDashboardTab = {}

local QUALITY_LABELS = { [0] = "Grey", [1] = "White", [2] = "Green", [3] = "Blue", [4] = "Epic" }

local function blackboard(app)
    return app:get_blackboard()
end

local function mode_label(menu)
    local idx = menu and menu.bot_mode and menu.bot_mode:get() or 1
    idx = tonumber(idx) or 1
    if idx == 2 then return "Grind" end
    return "Battleground"
end

local function is_grind_mode(menu)
    return mode_label(menu) == "Grind"
end

local function is_paladin(app)
    return (blackboard(app):get("player.class_id") or 2) == 2
end

function UnifiedDashboardTab.render(t, app, menu)
    -- Mode selector at top
    t:segmented_control({
        label = "Mode",
        element = menu.bot_mode,
        options = { "Battleground", "Grind" },
        tooltip = "Switch between Battleground PvP and open-world Grinding modes.",
    })

    -- Live metrics bar (always visible)
    t:metric_grid({
        label = "Live",
        elements = {
            {
                label = "Health %",
                value_fn = function()
                    return math.floor((blackboard(app):get("player.health_pct", 0) or 0) * 100)
                end,
            },
            {
                label = "Mana %",
                value_fn = function()
                    return math.floor((blackboard(app):get("player.mana_pct", 0) or 0) * 100)
                end,
            },
            {
                label = "Enemies 10yd",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.enemy_count_10yd", 0)) or 0
                end,
            },
            {
                label = "Allies 30yd",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.ally_count_30yd", 0)) or 0
                end,
            },
            {
                label = "Target Dist",
                value_fn = function()
                    return string.format("%.1f", tonumber(blackboard(app):get("combat.target_distance", 0)) or 0)
                end,
            },
            {
                label = "GCD Until",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.gcd_until_ms", 0)) or 0
                end,
            },
        },
    })

    -- Status row
    t:row_list({
        label = "Status",
        elements = {
            {
                type = "info",
                label = "Mode",
                value_fn = function() return mode_label(menu) end,
            },
            {
                type = "info",
                label = "Map",
                value_fn = function() return tostring(blackboard(app):get("system.map_name", "-")) end,
            },
            {
                type = "info",
                label = "Combat State",
                value_fn = function()
                    local combat = app:get_module("combat")
                    return combat and combat:get_state() or "-"
                end,
            },
            {
                type = "info",
                label = "Nav State",
                value_fn = function() return tostring(blackboard(app):get("nav.state", "idle")) end,
            },
            {
                type = "button",
                label = "Combat",
                text = "Disengage",
                tooltip = "Drop the current combat target and stop chase movement.",
                on_click = function()
                    local combat = app:get_module("combat")
                    if combat then combat:disengage("ui_disengage") end
                end,
            },
        },
    })

    -- Context-sensitive sections based on mode
    if is_grind_mode(menu) then
        render_grind_section(t, app, menu)
    else
        render_battleground_section(t, app, menu)
    end

    -- Combat section (always visible)
    render_combat_section(t, app, menu)

    -- Debug section (collapsible)
    render_debug_section(t, app, menu)
end

function render_grind_section(t, app, menu)
    -- Grind Controls
    t:row_list({
        label = "Grind Controls",
        elements = {
            {
                type = "toggle",
                label = "Grind Enabled",
                element = menu.grind_enabled,
                tooltip = "Master switch for the grinding module.",
            },
            {
                type = "toggle",
                label = "Show Overlay",
                element = menu.grind_show_overlay,
                tooltip = "Show 3D profile overlay (hotspots, route, vendors).",
            },
        },
    })

    t:segmented_control({
        label = "Grind Mode",
        element = menu.grind_mode,
        options = { "Profile", "Patrol" },
        tooltip = "Profile: follow a grinding profile. Patrol: roam and kill.",
    })

    -- Patrol-specific settings
    local is_patrol = menu.grind_mode:get() == 2
    if is_patrol then
        t:row_list({
            label = "Patrol Settings",
            elements = {
                {
                    type = "stepper",
                    label = "Patrol Radius",
                    element = menu.grind_patrol_radius,
                    min = 20,
                    max = 150,
                    step = 10,
                    suffix = " yd",
                    tooltip = "Radius around starting position to patrol for mobs.",
                },
                {
                    type = "info",
                    label = "Center",
                    value_fn = function()
                        local bb = blackboard(app)
                        local center = bb:get("module.grind.patrol_center")
                        if not center then return "Not set (starts on enable)" end
                        return string.format("(%.0f, %.0f)", center.x or 0, center.y or 0)
                    end,
                },
            },
        })
    end

    -- Thresholds
    t:row_list({
        label = "Thresholds",
        elements = {
            {
                type = "stepper",
                label = "Eat at HP",
                element = menu.grind_health_eat_pct,
                min = 20,
                max = 90,
                step = 5,
                suffix = "%",
                tooltip = "Sit and eat when health drops below this between pulls.",
            },
            {
                type = "stepper",
                label = "Drink at Mana",
                element = menu.grind_mana_drink_pct,
                min = 20,
                max = 90,
                step = 5,
                suffix = "%",
                tooltip = "Sit and drink when mana drops below this between pulls.",
            },
            {
                type = "stepper",
                label = "Flee at HP",
                element = menu.grind_health_flee_pct,
                min = 5,
                max = 50,
                step = 5,
                suffix = "%",
                tooltip = "Flee to safety when health drops below this during combat.",
            },
            {
                type = "stepper",
                label = "Max Hostiles",
                element = menu.grind_max_hostiles,
                min = 1,
                max = 8,
                step = 1,
                tooltip = "Maximum simultaneous hostile mobs before fleeing.",
            },
        },
    })

    -- Vendor
    t:row_list({
        label = "Vendor",
        elements = {
            {
                type = "stepper",
                label = "Sell Below Quality",
                element = menu.grind_vendor_sell_quality,
                min = 0,
                max = 4,
                step = 1,
                tooltip = "Sell items below this quality. 0=Grey, 1=White, 2=Green, 3=Blue, 4=Epic.",
                format_fn = function(val) return QUALITY_LABELS[val] or tostring(val) end,
            },
            {
                type = "stepper",
                label = "Repair Threshold",
                element = menu.grind_repair_threshold,
                min = 0,
                max = 200,
                step = 10,
                suffix = "s",
                tooltip = "Repair cost threshold in silver. Visit vendor when repair cost exceeds this.",
                format_fn = function(val) return tostring(val) .. "s" end,
            },
            {
                type = "info",
                label = "Bag Space",
                value_fn = function()
                    local bb = blackboard(app)
                    local free = bb:get("module.grind.bag_free_slots")
                    if not free then return "-" end
                    return tostring(free) .. " free"
                end,
            },
            {
                type = "info",
                label = "Repair Cost",
                value_fn = function()
                    local bb = blackboard(app)
                    local tracker = bb:get("module.grind.durability_tracker")
                    if not tracker or not tracker.get_repair_cost then return "-" end
                    local cost = tracker:get_repair_cost()
                    if not cost or cost == 0 then return "OK" end
                    local silver = math.floor(cost / 100)
                    local copper = cost % 100
                    return string.format("%ds %dc", silver, copper)
                end,
            },
        },
    })

    -- Target Filter
    t:row_list({
        label = "Target Filter",
        elements = {
            {
                type = "toggle",
                label = "Attack Neutral (Yellow)",
                element = menu.grind_attack_neutral,
                tooltip = "Target neutral mobs (yellow name) that don't attack unless provoked.",
            },
        },
    })

    -- Safety
    t:row_list({
        label = "Safety",
        elements = {
            {
                type = "toggle",
                label = "PvP Avoidance",
                element = menu.grind_pvp_avoidance,
                tooltip = "Pause grinding when enemy players are detected nearby.",
            },
            {
                type = "info",
                label = "Threat Map",
                value_fn = function()
                    local bb = blackboard(app)
                    local tm = bb:get("module.grind.threat_map")
                    if not tm or not tm.entry_count then return "-" end
                    local count = tm:entry_count()
                    if count == 0 then return "Clear" end
                    return tostring(count) .. " entries"
                end,
            },
        },
    })

    -- Session Stats
    t:row_list({
        label = "Session",
        elements = {
            {
                type = "info",
                label = "Kills / hr",
                value_fn = function()
                    local bb = blackboard(app)
                    local kills = bb:get("module.grind.telemetry.kills", 0)
                    local kph = bb:get("module.grind.telemetry.kills_per_hour", 0)
                    return string.format("%d  (%d/hr)", kills, kph)
                end,
            },
            {
                type = "info",
                label = "Deaths / hr",
                value_fn = function()
                    local bb = blackboard(app)
                    local deaths = bb:get("module.grind.telemetry.deaths", 0)
                    local dph = bb:get("module.grind.telemetry.deaths_per_hour", 0)
                    return string.format("%d  (%.1f/hr)", deaths, dph)
                end,
            },
            {
                type = "info",
                label = "XP / hr",
                value_fn = function()
                    return tostring(blackboard(app):get("module.grind.telemetry.xp_per_hour", 0))
                end,
            },
        },
    })

    -- Profile Management (Profile mode only)
    if not is_patrol then
        t:listbox({
            label = "Profiles",
            footer = "Click a profile to load it.",
            elements = {
                {
                    id = "grind_profile_list",
                    visible_rows = 4,
                    entries_fn = function()
                        local grind = app:get_module("grind")
                        if not grind or not grind.get_profile_manager then return {} end
                        local pm = grind:get_profile_manager()
                        if not pm then return {} end
                        local ok, profiles = pcall(pm.scan_profiles, pm)
                        if not ok or not profiles then return {} end
                        local entries = {}
                        for _, p in ipairs(profiles) do
                            entries[#entries + 1] = {
                                label = p.name or p.filename,
                                sublabel = string.format("Lv %d-%d", p.min_level or 1, p.max_level or 70),
                            }
                        end
                        return entries
                    end,
                    on_select = function(index)
                        local grind = app:get_module("grind")
                        if not grind or not grind.get_profile_manager then return end
                        local pm = grind:get_profile_manager()
                        if not pm then return end
                        local ok, profiles = pcall(pm.scan_profiles, pm)
                        if not ok or not profiles then return end
                        if profiles[index] then
                            pm:load_profile(profiles[index].filename)
                        end
                    end,
                },
            },
        })

        t:row_list({
            label = "Active Profile",
            elements = {
                {
                    type = "info",
                    label = "Profile Name",
                    value_fn = function()
                        return tostring(blackboard(app):get("module.grind.profile_name", "-") or "-")
                    end,
                },
                {
                    type = "info",
                    label = "Autoloader",
                    value_fn = function()
                        local ok, Autoloader = pcall(require, "modules/grind/autoloader")
                        if not ok or not Autoloader then return "None" end
                        return Autoloader.get_loaded_filename() or "None"
                    end,
                },
                {
                    type = "info",
                    label = "Hotspot",
                    value_fn = function()
                        local bb = blackboard(app)
                        local idx = bb:get("module.grind.current_hotspot_index")
                        local count = bb:get("module.grind.hotspot_count")
                        if not idx or not count then return "-" end
                        local spot = bb:get("module.grind.current_spot")
                        local label = spot and spot.hotspot_label
                        local text = string.format("%d / %d", idx, count)
                        if label and label ~= "" then
                            text = text .. " - " .. tostring(label)
                        end
                        return text
                    end,
                },
                {
                    type = "info",
                    label = "Current Target",
                    value_fn = function()
                        local target = blackboard(app):get("module.grind.current_target")
                        if not target then return "-" end
                        if type(target) == "table" and type(target.get_name) == "function" then
                            local ok, name = pcall(target.get_name, target)
                            if ok and name then return tostring(name) end
                        end
                        return "target"
                    end,
                },
            },
        })
    end
end

function render_battleground_section(t, app, menu)
    t:row_list({
        label = "Battleground",
        elements = {
            {
                type = "toggle",
                label = "BG Enabled",
                element = menu.bg_enabled,
                tooltip = "Enable battleground module.",
            },
            {
                type = "toggle",
                label = "Auto Engage",
                element = menu.bg_auto_engage,
                tooltip = "Automatically engage enemies in battlegrounds.",
            },
            {
                type = "toggle",
                label = "Auto Queue",
                element = menu.bg_auto_queue,
                tooltip = "Automatically queue for battlegrounds.",
            },
            {
                type = "segmented_control",
                label = "Queue",
                element = menu.bg_queue_selection,
                options = { "AV", "WSG", "AB", "EOTS" },
                tooltip = "Select battleground to queue for.",
            },
            {
                type = "stepper",
                label = "Mount Distance",
                element = menu.bg_mount_distance,
                min = 10,
                max = 120,
                step = 5,
                suffix = " yd",
                tooltip = "Distance to mount when moving between objectives.",
            },
            {
                type = "stepper",
                label = "Low Health %",
                element = menu.bg_low_health_threshold,
                min = 15,
                max = 70,
                step = 1,
                suffix = "%",
                tooltip = "Retreat when health falls below this threshold.",
            },
        },
    })
end

function render_combat_section(t, app, menu)
    local paladin = is_paladin(app)

    t:segmented_control({
        label = "Combat View",
        element = menu.debug_view,
        options = { "State", "Snapshot", "Rotation" },
    })

    local view = menu.debug_view
    local function view_is(n) return function() return (view and view:get() or 1) == n end end

    -- Combat State View
    t:row_list({
        label = "Combat State",
        visible_when = view_is(1),
        elements = {
            {
                type = "toggle",
                label = "Combat Enabled",
                element = menu.combat_enabled,
                tooltip = "Master switch for combat logic and chase ownership.",
            },
            {
                type = "toggle",
                label = "Auto Burst",
                element = menu.burst_enabled,
                tooltip = "Allow automatic cooldown usage during valid combat burst context.",
            },
            {
                type = "info",
                label = "In Combat",
                value_fn = function() return tostring(blackboard(app):get("player.in_combat", false) == true) end,
            },
            {
                type = "info",
                label = "Combat Source",
                value_fn = function() return tostring(blackboard(app):get("combat.source", "-")) end,
            },
            {
                type = "info",
                label = "Last Action",
                value_fn = function() return tostring(blackboard(app):get("rotation.last_action_id", "-") or "-") end,
            },
            {
                type = "info",
                label = "Burst Context",
                value_fn = function() return blackboard(app):get("combat.burst_context", false) and "yes" or "no" end,
            },
        },
    })

    if paladin then
        t:row_list({
            label = "Paladin Settings",
            visible_when = view_is(1),
            elements = {
                {
                    type = "segmented_control",
                    label = "Preferred Blessing",
                    element = menu.preferred_blessing,
                    options = { "Might", "Kings" },
                    tooltip = "Sets the out-of-combat blessing maintenance target.",
                },
                {
                    type = "segmented_control",
                    label = "Twist Mode",
                    element = menu.twist_mode,
                    options = { "Auto", "Force" },
                    tooltip = "Auto only twists with high-confidence swing timing. Force allows estimated timing when enabled.",
                },
                {
                    type = "toggle",
                    label = "Allow Estimated Twist",
                    element = menu.allow_estimated_twist,
                    tooltip = "Permit seal twisting when only estimated swing timing is available.",
                },
                {
                    type = "stepper",
                    label = "Twist Window",
                    element = menu.twist_window_ms,
                    min = 200,
                    max = 450,
                    step = 10,
                    suffix = " ms",
                    tooltip = "Maximum swing time remaining to prime Seal of Command.",
                },
            },
        })

        t:row_list({
            label = "Seal State",
            visible_when = view_is(1),
            elements = {
                { type = "info", label = "Active Seal", value_fn = function() return tostring(blackboard(app):get("rotation.active_seal", "-") or "-") end },
                { type = "info", label = "Primary Seal", value_fn = function() return tostring(blackboard(app):get("rotation.primary_seal", "-") or "-") end },
                { type = "info", label = "Desired Seal", value_fn = function() return tostring(blackboard(app):get("rotation.desired_seal", "-") or "-") end },
                { type = "info", label = "Desired Reason", value_fn = function() return tostring(blackboard(app):get("rotation.desired_seal_reason", "-") or "-") end },
                { type = "info", label = "Twist Enabled", value_fn = function() return blackboard(app):get("rotation.twist.enabled", false) and "yes" or "no" end },
                { type = "info", label = "Swing Confidence", value_fn = function() return string.format("%.2f", tonumber(blackboard(app):get("combat.swing.confidence", 0)) or 0) end },
            },
        })
    end

    -- Snapshot View
    local snapshot_elements = {
        { label = "Target Dist", value_fn = function() return string.format("%.1f", tonumber(blackboard(app):get("combat.target_distance", 0)) or 0) end },
        { label = "Enemies 10yd", value_fn = function() return tonumber(blackboard(app):get("combat.enemy_count_10yd", 0)) or 0 end },
    }
    if paladin then
        table.insert(snapshot_elements, 1, { label = "Swing ms", value_fn = function() return math.floor(tonumber(blackboard(app):get("combat.swing.remaining_ms", 0)) or 0) end })
        table.insert(snapshot_elements, 2, { label = "Vengeance", value_fn = function() return tonumber(blackboard(app):get("rotation.vengeance_stacks", 0)) or 0 end })
    end

    t:metric_grid({
        label = "Snapshot",
        visible_when = view_is(2),
        elements = snapshot_elements,
    })

    -- Rotation View
    t:row_list({
        label = "Rotation Debug",
        visible_when = view_is(3),
        elements = {
            {
                type = "info",
                label = "Profile ID",
                value_fn = function() return tostring(blackboard(app):get("rotation.profile_id", "-")) end,
            },
            {
                type = "info",
                label = "Last Spell",
                value_fn = function() return tostring(blackboard(app):get("rotation.last_spell_id", "-") or "-") end,
            },
            {
                type = "info",
                label = "Queue Mode",
                value_fn = function() return tostring(blackboard(app):get("rotation.last_queue_mode", "-") or "-") end,
            },
            {
                type = "info",
                label = "Queue Priority",
                value_fn = function() return tostring(blackboard(app):get("rotation.last_queue_priority", "-") or "-") end,
            },
            {
                type = "info",
                label = "Last Block",
                value_fn = function() return tostring(blackboard(app):get("rotation.last_block_reason", "-") or "-") end,
            },
            {
                type = "info",
                label = "Queue Size",
                value_fn = function() return tostring(blackboard(app):get("rotation.last_queue_snapshot_size", 0) or 0) end,
            },
        },
    })

    -- Thresholds (always visible at bottom)
    t:row_list({
        label = "Thresholds",
        elements = {
            {
                type = "stepper",
                label = "Retreat Health",
                element = menu.combat_low_health_threshold,
                min = 15,
                max = 70,
                step = 1,
                suffix = "%",
                tooltip = "Combat disengages when health falls at or below this threshold.",
            },
            {
                type = "stepper",
                label = "Outnumber Delta",
                element = menu.combat_retreat_outnumber_delta,
                min = 1,
                max = 5,
                step = 1,
                tooltip = "Combat disengages when enemies exceed allies by this amount.",
            },
        },
    })
end

function render_debug_section(t, app, menu)
    -- Debug section with system info
    t:row_list({
        label = "System Debug",
        elements = {
            { type = "info", label = "Map ID", value_fn = function() return tostring(blackboard(app):get("system.map_id", 0)) end },
            { type = "info", label = "Ping ms", value_fn = function() return tostring(blackboard(app):get("system.ping_ms", 0)) end },
            { type = "info", label = "Leash Center", value_fn = function()
                local v = blackboard(app):get("combat.leash_center")
                if type(v) ~= "table" then return "-" end
                return string.format("%.1f %.1f %.1f", tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0)
            end },
            { type = "info", label = "Nav Destination", value_fn = function()
                local v = blackboard(app):get("nav.destination")
                if type(v) ~= "table" then return "-" end
                return string.format("%.1f %.1f %.1f", tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0)
            end },
        },
    })
end

return UnifiedDashboardTab