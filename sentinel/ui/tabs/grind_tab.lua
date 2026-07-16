local GrindTab = {}

local QUALITY_LABELS = { [0] = "Grey", [1] = "White", [2] = "Green", [3] = "Blue", [4] = "Epic" }

local function blackboard(app)
    return app:get_blackboard()
end

function GrindTab.render(t, app, menu)
    t:row_list({
        label = "Controls",
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
        label = "Mode",
        element = menu.grind_mode,
        options = { "Profile", "Patrol" },
        tooltip = "Profile: follow a grinding profile. Patrol: roam and kill.",
    })

    -- Patrol-specific settings (visible only in patrol mode)
    local is_patrol = menu.grind_mode:get() == 2
    if is_patrol then
        t:row_list({
            label = "Patrol",
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
                format_fn = function(val)
                    return QUALITY_LABELS[val] or tostring(val)
                end,
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
                format_fn = function(val)
                    return tostring(val) .. "s"
                end,
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
                    local bb = blackboard(app)
                    return tostring(bb:get("module.grind.telemetry.xp_per_hour", 0))
                end,
            },
        },
    })

    -- Profile-specific sections (hidden in patrol mode)
    local is_profile = not is_patrol

    if is_profile then
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
    end -- is_profile
end

return GrindTab
