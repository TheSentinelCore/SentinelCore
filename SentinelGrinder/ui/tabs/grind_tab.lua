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

        t:checkbox_grid({
            label = "Replenish",
            columns = 1,
            elements = {
                { element = menu.auto_replenish_enabled, label = "Enable Replenish", tooltip = "When bags are near full, find vendor to sell junk and repair." },
                {
                    element = menu.auto_vendor_sell_junk,
                    label = "Sell Junk (Gray)",
                    tooltip = "Automatically sell poor quality items at merchant.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
                {
                    element = menu.auto_vendor_repair,
                    label = "Auto Repair",
                    tooltip = "Automatically repair when merchant can repair.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
            },
        })

        t:slider_list({
            label = "Replenish Limits",
            elements = {
                {
                    element = menu.replenish_min_free_slots,
                    label = "Min Free Slots",
                    tooltip = "Start replenish mode when free slots are at or below this value.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
            },
        })

        t:slider_list({
            label = "Vendor",
            elements = {
                {
                    element = menu.vendor_npc_id,
                    label = "Vendor NPC ID",
                    tooltip = "Exact vendor NPC ID to interact with.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
                {
                    element = menu.vendor_scan_radius,
                    label = "Vendor Scan Radius",
                    suffix = " yd",
                    tooltip = "How far to look for the configured vendor.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
                {
                    element = menu.vendor_interact_range,
                    label = "Vendor Interact Range",
                    suffix = " yd",
                    tooltip = "Distance considered close enough to interact.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
            },
        })
    end)
end

return GrindTab
