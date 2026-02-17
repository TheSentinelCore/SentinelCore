local LootTab = {}

---@param ui any
---@param menu table
function LootTab.register(ui, menu)
    ui:add_tab({ id = "loot", label = "Loot" }, function(t)
        t:checkbox_grid({
            label = "Loot",
            columns = 1,
            elements = {
                { element = menu.loot_enabled, label = "Enable Loot", tooltip = "Loot corpses after kills when safe." },
            },
        })

        t:slider_list({
            label = "Loot Settings",
            elements = {
                { element = menu.loot_range, label = "Loot Range", suffix = " yd", tooltip = "Distance before moving to corpse." },
                { element = menu.loot_attempt_interval, label = "Loot Attempt Interval", suffix = " s", tooltip = "Delay between loot interactions." },
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
                {
                    element = menu.replenish_timeout,
                    label = "Replenish Timeout",
                    suffix = " s",
                    tooltip = "Abort replenish if it takes too long.",
                    visible_when = function()
                        return menu.auto_replenish_enabled and menu.auto_replenish_enabled:get_state() == true
                    end,
                },
                {
                    element = menu.replenish_cooldown,
                    label = "Replenish Cooldown",
                    suffix = " s",
                    tooltip = "Cooldown before retry when no vendor action happened.",
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

return LootTab
