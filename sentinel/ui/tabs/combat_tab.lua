local CombatTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

local function is_paladin(app)
    return (blackboard(app):get("player.class_id") or 2) == 2
end

function CombatTab.render(t, app, menu)
    local paladin = is_paladin(app)

    local automation_elements = {
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
            tooltip = "Allow automatic cooldown usage during valid combat burst context.",
        },
    }
    if paladin then
        automation_elements[#automation_elements + 1] = {
            type = "toggle",
            label = "Allow Estimated Twist",
            element = menu.allow_estimated_twist,
            tooltip = "Permit seal twisting when only estimated swing timing is available.",
        }
    end
    t:row_list({ label = "Controls", elements = automation_elements })

    if paladin then
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
    end

    local threshold_elements = {}
    if paladin then
        threshold_elements[#threshold_elements + 1] = {
            type = "stepper",
            label = "Twist Window",
            element = menu.twist_window_ms,
            min = 200,
            max = 450,
            step = 10,
            suffix = " ms",
            tooltip = "Maximum swing time remaining to prime Seal of Command.",
        }
    end
    threshold_elements[#threshold_elements + 1] = {
        type = "stepper",
        label = "Retreat Health",
        element = menu.combat_low_health_threshold,
        min = 15,
        max = 70,
        step = 1,
        suffix = "%",
        tooltip = "Combat disengages when health falls at or below this threshold.",
    }
    threshold_elements[#threshold_elements + 1] = {
        type = "stepper",
        label = "Outnumber Delta",
        element = menu.combat_retreat_outnumber_delta,
        min = 1,
        max = 5,
        step = 1,
        tooltip = "Combat disengages when enemies exceed allies by this amount.",
    }
    t:row_list({ label = "Thresholds", elements = threshold_elements })

    local snapshot_elements = {
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
    }
    if paladin then
        table.insert(snapshot_elements, 1, {
            label = "Swing ms",
            value_fn = function()
                return math.floor(tonumber(blackboard(app):get("combat.swing.remaining_ms", 0)) or 0)
            end,
        })
        table.insert(snapshot_elements, 2, {
            label = "Vengeance",
            value_fn = function()
                return tonumber(blackboard(app):get("rotation.vengeance_stacks", 0)) or 0
            end,
        })
    end
    t:metric_grid({ label = "Snapshot", elements = snapshot_elements })

    local state_elements = {
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
    }
    if paladin then
        state_elements[#state_elements + 1] = {
            type = "info",
            label = "Active Seal",
            value_fn = function()
                return tostring(blackboard(app):get("rotation.active_seal", "-") or "-")
            end,
        }
        state_elements[#state_elements + 1] = {
            type = "info",
            label = "Primary Seal",
            value_fn = function()
                return tostring(blackboard(app):get("rotation.primary_seal", "-") or "-")
            end,
        }
        state_elements[#state_elements + 1] = {
            type = "info",
            label = "Desired Seal",
            value_fn = function()
                return tostring(blackboard(app):get("rotation.desired_seal", "-") or "-")
            end,
        }
        state_elements[#state_elements + 1] = {
            type = "info",
            label = "Desired Reason",
            value_fn = function()
                return tostring(blackboard(app):get("rotation.desired_seal_reason", "-") or "-")
            end,
        }
        state_elements[#state_elements + 1] = {
            type = "info",
            label = "Twist Enabled",
            value_fn = function()
                return blackboard(app):get("rotation.twist.enabled", false) and "yes" or "no"
            end,
        }
        state_elements[#state_elements + 1] = {
            type = "info",
            label = "Swing Confidence",
            value_fn = function()
                return string.format("%.2f", tonumber(blackboard(app):get("combat.swing.confidence", 0)) or 0)
            end,
        }
    end
    t:row_list({ label = "State", elements = state_elements })
end

return CombatTab
