local GrindTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

function GrindTab.render(t, app, menu)
    -- Automation
    t:row_list({
        label = "Automation",
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

    -- Autoloader
    t:row_list({
        label = "Autoloader",
        elements = {
            {
                type = "info",
                label = "Active",
                value_fn = function()
                    local ok, Autoloader = pcall(require, "modules/grind/autoloader")
                    if not ok or not Autoloader then return "None" end
                    return Autoloader.get_loaded_filename() or "None"
                end,
            },
        },
    })

    -- Profile list
    t:listbox({
        label = "Profiles",
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
        on_select = function(index, entry)
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
    })

    -- Active Profile Status
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

return GrindTab
