local GrindTab = {}

---@param ui any
---@param menu table
---@param route_profile_labels string[]
function GrindTab.register(ui, menu, route_profile_labels)
    ui:add_tab({ id = "grind", label = "Grind" }, function(t)
        t:combo_list({
            label = "Patrol Route",
            elements = {
                {
                    element = menu.route_mode,
                    label = "Route Mode",
                    options = { "Circle (Legacy)", "Profile Route" },
                    tooltip = "Circle uses anchor-based patrol. Profile Route uses loaded grind profiles.",
                },
                {
                    element = menu.route_profile,
                    label = "Route Profile",
                    options = route_profile_labels,
                    tooltip = "Manual profile when auto profile selection is disabled.",
                },
            },
        })

        t:checkbox_grid({
            label = "Route Selection",
            columns = 1,
            elements = {
                {
                    element = menu.route_auto_profile,
                    label = "Auto Route Profile",
                    tooltip = "Auto-select route profile by current map and player level.",
                },
            },
        })

        t:slider_list({
            label = "Target Search",
            elements = {
                { element = menu.scan_radius, label = "Scan Radius", suffix = " yd", tooltip = "How far to scan enemies." },
                { element = menu.pull_range, label = "Pull Range", suffix = " yd", tooltip = "Max range to start combat actions." },
                { element = menu.chase_stop_range, label = "Chase Stop", suffix = " yd", tooltip = "Distance where chase turns into pull/combat." },
                { element = menu.mount_threshold, label = "Mount Threshold", suffix = " yd", tooltip = "Patrol distance needed before mounting." },
            },
        })

        t:slider_list({
            label = "Level Filter",
            elements = {
                { element = menu.min_level_delta, label = "Min Level Delta", tooltip = "Target level minus your level." },
                { element = menu.max_level_delta, label = "Max Level Delta", tooltip = "Default requested cap is +2." },
            },
        })

        t:checkbox_grid({
            label = "Safety",
            columns = 1,
            elements = {
                { element = menu.ignore_players, label = "Ignore Player Targets", tooltip = "Do not attack player units." },
                { element = menu.only_hostile_targets, label = "Only Hostile Targets", tooltip = "Ignore neutral (yellow) NPCs." },
                { element = menu.auto_mount_enabled, label = "Auto Mount On Patrol", tooltip = "Mount for long patrol moves and dismount before combat/pull." },
            },
        })
    end)
end

return GrindTab
