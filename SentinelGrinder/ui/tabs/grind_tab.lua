local GrindTab = {}

---@param ui any
---@param menu table
function GrindTab.register(ui, menu)
    ui:add_tab({ id = "grind", label = "Grind" }, function(t)
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
