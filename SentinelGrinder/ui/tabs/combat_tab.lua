local CombatTab = {}

---@param ui any
---@param menu table
function CombatTab.register(ui, menu)
    ui:add_tab({ id = "combat", label = "Combat" }, function(t)
        t:slider_list({
            label = "Target Search",
            elements = {
                { element = menu.scan_radius, label = "Scan Radius", suffix = " yd", tooltip = "How far to scan enemies." },
                { element = menu.pull_range, label = "Pull Range", suffix = " yd", tooltip = "Max range to start combat actions." },
                { element = menu.chase_stop_range, label = "Chase Stop", suffix = " yd", tooltip = "Distance where chase turns into pull/combat." },
            },
        })

        t:slider_list({
            label = "Engage Timings",
            elements = {
                { element = menu.pull_cooldown, label = "Pull Cooldown", suffix = " s", tooltip = "Delay between pull interactions." },
                { element = menu.target_timeout, label = "Target Timeout", suffix = " s", tooltip = "Blacklist target after this chase duration." },
                { element = menu.combat_retarget_interval, label = "Retarget Interval", suffix = " s", tooltip = "How often to check for better combat target." },
                { element = menu.stickiness_bonus, label = "Stickiness Bonus", tooltip = "Score bonus for keeping current target." },
            },
        })

        t:slider_list({
            label = "Level Filter",
            elements = {
                { element = menu.min_level_delta, label = "Min Level Delta", tooltip = "Target level minus your level." },
                { element = menu.max_level_delta, label = "Max Level Delta", tooltip = "Upper target level cap relative to player." },
            },
        })

        t:checkbox_grid({
            label = "Target Rules",
            columns = 1,
            elements = {
                { element = menu.ignore_players, label = "Ignore Player Targets", tooltip = "Do not attack player units." },
                { element = menu.only_hostile_targets, label = "Only Hostile Targets", tooltip = "Ignore neutral (yellow) NPCs." },
                { element = menu.prefer_player_target, label = "Prefer Manual Target", tooltip = "Keep manually selected valid target when possible." },
            },
        })
    end)
end

return CombatTab
