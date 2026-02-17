local GrindTab = {}

---@param ui any
---@param menu table
---@param route_profile_labels string[]
---@param theme_labels string[]
function GrindTab.register(ui, menu, route_profile_labels, theme_labels)
    ui:add_tab({ id = "grind", label = "Grind" }, function(t)
        t:combo_list({
            label = "Interface",
            elements = {
                {
                    element = menu.ui_theme,
                    label = "Theme",
                    options = theme_labels,
                    tooltip = "Changes GrindBuddy window visual theme.",
                },
            },
        })

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
                    visible_when = function()
                        local profile_mode = menu.route_mode and menu.route_mode:get() == 2
                        local auto_profile = menu.route_auto_profile and menu.route_auto_profile:get_state() == true
                        return profile_mode and not auto_profile
                    end,
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
                    visible_when = function()
                        return menu.route_mode and menu.route_mode:get() == 2
                    end,
                },
            },
        })

        t:slider_list({
            label = "Route Radius",
            elements = {
                {
                    element = menu.route_radius_min,
                    label = "Min Radius",
                    suffix = " yd",
                    tooltip = "Base radius for circle patrol mode.",
                    visible_when = function() return menu.route_mode and menu.route_mode:get() == 1 end,
                },
                {
                    element = menu.route_radius_max,
                    label = "Max Radius",
                    suffix = " yd",
                    tooltip = "Maximum expansion radius in circle mode.",
                    visible_when = function() return menu.route_mode and menu.route_mode:get() == 1 end,
                },
                {
                    element = menu.route_expand_step,
                    label = "Expand Step",
                    suffix = " yd",
                    tooltip = "Amount of radius added when no target is found.",
                    visible_when = function() return menu.route_mode and menu.route_mode:get() == 1 end,
                },
                {
                    element = menu.route_expand_interval,
                    label = "Expand Interval",
                    suffix = " s",
                    tooltip = "Delay between each expansion.",
                    visible_when = function() return menu.route_mode and menu.route_mode:get() == 1 end,
                },
                { element = menu.mount_threshold, label = "Mount Threshold", suffix = " yd", tooltip = "Patrol distance needed before mounting." },
            },
        })

        t:checkbox_grid({
            label = "Route Behaviour",
            columns = 1,
            elements = {
                { element = menu.auto_mount_enabled, label = "Auto Mount On Patrol", tooltip = "Mount for long patrol moves and dismount before combat/pull." },
                { element = menu.prefer_player_target, label = "Prefer Manual Target", tooltip = "Use your selected valid target before auto-acquiring one." },
            },
        })
    end)
end

return GrindTab
