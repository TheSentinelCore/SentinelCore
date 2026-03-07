local CombatTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

function CombatTab.render(t, app, menu)
    t:row_list({
        label = "Automation",
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
                tooltip = "Allow automatic Avenging Wrath usage only during valid combat burst context.",
            },
            {
                type = "toggle",
                label = "Allow Estimated Twist",
                element = menu.allow_estimated_twist,
                tooltip = "Permit seal twisting when only estimated swing timing is available.",
            },
        },
    })

    t:segmented_control({
        label = "Preferred Blessing",
        element = menu.preferred_blessing,
        options = { "Might", "Kings" },
        tooltip = "Sets the out-of-combat blessing maintenance target.",
    })

    t:segmented_control({
        label = "Twist Mode",
        element = menu.twist_mode,
        options = { "Auto", "Force" },
        tooltip = "Auto only twists with high-confidence swing timing. Force allows estimated timing when enabled.",
    })

    t:row_list({
        label = "Thresholds",
        elements = {
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

    t:metric_grid({
        label = "Snapshot",
        elements = {
            {
                label = "Swing ms",
                value_fn = function()
                    return math.floor(tonumber(blackboard(app):get("combat.swing.remaining_ms", 0)) or 0)
                end,
            },
            {
                label = "Vengeance",
                value_fn = function()
                    return tonumber(blackboard(app):get("rotation.vengeance_stacks", 0)) or 0
                end,
            },
            {
                label = "Target Dist",
                value_fn = function()
                    return string.format("%.1f", tonumber(blackboard(app):get("combat.target_distance", 0)) or 0)
                end,
            },
            {
                label = "Enemies 10yd",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.enemy_count_10yd", 0)) or 0
                end,
            },
        },
    })

    t:row_list({
        label = "State",
        elements = {
            {
                type = "info",
                label = "Rotation Profile",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.profile_id", "-"))
                end,
            },
            {
                type = "info",
                label = "In Combat",
                value_fn = function()
                    return tostring(blackboard(app):get("player.in_combat", false) == true)
                end,
            },
            {
                type = "info",
                label = "Active Seal",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.active_seal", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Primary Seal",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.primary_seal", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Desired Seal",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.desired_seal", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Desired Reason",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.desired_seal_reason", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Last Action",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_action_id", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Burst Context",
                value_fn = function()
                    return blackboard(app):get("combat.burst_context", false) and "yes" or "no"
                end,
            },
            {
                type = "info",
                label = "Twist Enabled",
                value_fn = function()
                    return blackboard(app):get("rotation.twist.enabled", false) and "yes" or "no"
                end,
            },
            {
                type = "info",
                label = "Swing Confidence",
                value_fn = function()
                    return string.format("%.2f", tonumber(blackboard(app):get("combat.swing.confidence", 0)) or 0)
                end,
            },
        },
    })
end

return CombatTab
