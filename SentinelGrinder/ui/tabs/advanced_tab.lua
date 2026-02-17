local AdvancedTab = {}

---@param ui any
---@param menu table
function AdvancedTab.register(ui, menu)
    ui:add_tab({ id = "advanced", label = "Advanced" }, function(t)
        t:slider_list({
            label = "Loop Timing",
            elements = {
                { element = menu.tick_interval, label = "Main Tick Interval", suffix = " s", tooltip = "Core update loop interval." },
                { element = menu.scan_interval, label = "Target Scan Interval", suffix = " s", tooltip = "Delay between enemy scans." },
                { element = menu.route_profile_refresh_interval, label = "Route Profile Refresh", suffix = " s", tooltip = "How often auto route profile updates." },
            },
        })

        t:slider_list({
            label = "Route Expansion",
            elements = {
                { element = menu.route_radius_min, label = "Route Radius Min", suffix = " yd", tooltip = "Base radius for circle patrol mode." },
                { element = menu.route_radius_max, label = "Route Radius Max", suffix = " yd", tooltip = "Maximum expansion radius when no targets found." },
                { element = menu.route_expand_step, label = "Route Expand Step", suffix = " yd", tooltip = "How much radius increases per expansion step." },
                { element = menu.route_expand_interval, label = "Route Expand Interval", suffix = " s", tooltip = "Delay before each expansion step." },
            },
        })
    end)
end

return AdvancedTab
