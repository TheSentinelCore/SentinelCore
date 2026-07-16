local BattlegroundTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

local function queue_target_label(menu)
    local idx = menu and menu.bg_queue_selection and menu.bg_queue_selection:get() or 1
    idx = tonumber(idx) or 1
    if idx == 2 then return "Warsong Gulch" end
    if idx == 3 then return "Arathi Basin" end
    if idx == 4 then return "Eye of the Storm" end
    return "Alterac Valley"
end

function BattlegroundTab.render(t, app, menu)
    -- Controls
    t:row_list({
        label = "Controls",
        elements = {
            {
                type = "toggle",
                label = "Battleground Enabled",
                element = menu.bg_enabled,
                tooltip = "Master switch for battleground state machines and strategic movement.",
            },
            {
                type = "toggle",
                label = "Auto Engage",
                element = menu.bg_auto_engage,
                tooltip = "Allow the battleground layer to hand tactical fights to combat automatically.",
            },
            {
                type = "toggle",
                label = "Auto Queue",
                element = menu.bg_auto_queue,
                tooltip = "Automatically join and accept the selected battleground queue.",
            },
            {
                type = "toggle",
                label = "Post-Game Auto Leave",
                element = menu.bg_post_game_auto_leave,
                tooltip = "Attempt to leave finished battlegrounds automatically after the post-game gate opens.",
            },
            {
                type = "toggle",
                label = "Auto Mount",
                element = menu.bg_auto_mount,
                tooltip = "Mount automatically during long battleground travel when safe.",
            },
        },
    })

    -- Settings (Queue + Mount merged)
    t:row_list({
        label = "Settings",
        elements = {
            {
                type = "stepper",
                label = "Queue Target",
                element = menu.bg_queue_selection,
                min = 1,
                max = 4,
                step = 1,
                tooltip = "Select the battleground that Auto Queue will join.",
            },
            {
                type = "info",
                label = "Selected BG",
                value_fn = function()
                    return queue_target_label(menu)
                end,
            },
            {
                type = "stepper",
                label = "Mount Distance",
                element = menu.bg_mount_distance,
                min = 10,
                max = 120,
                step = 1,
                suffix = "yd",
                tooltip = "Minimum travel distance before Sentinel attempts to mount.",
            },
        },
    })

    t:text_input_list({
        label = "Mount",
        id = "battleground_mount_inputs",
        elements = {
            {
                id = "preferred_mount_id",
                label = "Preferred Mount ID",
                value_fn = function()
                    return menu.bg_preferred_mount_id:get()
                end,
                placeholder = "184865",
                tooltip = "Preferred battleground mount item or spell ID. Sentinel tries use_item() with this ID first.",
                on_change = function(value)
                    menu.bg_preferred_mount_id:set(value)
                end,
            },
        },
    })

    -- Thresholds
    t:row_list({
        label = "Thresholds",
        elements = {
            {
                type = "stepper",
                label = "Retreat Health",
                element = menu.bg_low_health_threshold,
                min = 15,
                max = 70,
                step = 1,
                suffix = "%",
                tooltip = "Battleground retreat triggers when health falls at or below this threshold.",
            },
            {
                type = "stepper",
                label = "Engage Grace",
                element = menu.bg_engage_outnumber_grace,
                min = 0,
                max = 3,
                step = 1,
                tooltip = "Allowed enemy advantage before Battleground refuses a combat handoff.",
            },
            {
                type = "stepper",
                label = "Retreat Delta",
                element = menu.bg_retreat_outnumber_delta,
                min = 1,
                max = 5,
                step = 1,
                tooltip = "Battleground retreat triggers when enemies exceed allies by this amount.",
            },
        },
    })

    -- Actions
    t:row_list({
        label = "Actions",
        elements = {
            {
                type = "button",
                label = "Regroup",
                text = "Force",
                tooltip = "Force a retreat/regroup cycle from the UI.",
                on_click = function()
                    local battleground = app:get_module("battleground")
                    if battleground then
                        battleground:force_regroup("ui_force_regroup")
                    end
                end,
            },
            {
                type = "button",
                label = "Leave Now",
                text = "Test",
                tooltip = "Trigger the battleground leave manager immediately for runtime validation.",
                on_click = function()
                    local battleground = app:get_module("battleground")
                    if battleground and battleground.leave_now then
                        battleground:leave_now("ui_manual_test")
                    end
                end,
            },
        },
    })

    -- Snapshot
    t:metric_grid({
        label = "Snapshot",
        elements = {
            {
                label = "BG Active",
                value_fn = function()
                    return blackboard(app):get("bg.active", false) and 1 or 0
                end,
            },
            {
                label = "Failures",
                value_fn = function()
                    return tonumber(blackboard(app):get("nav.failure_count", 0)) or 0
                end,
            },
            {
                label = "Enemies",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.enemy_count_10yd", 0)) or 0
                end,
            },
            {
                label = "Allies",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.ally_count_30yd", 0)) or 0
                end,
            },
        },
    })

    -- Segmented Diagnostics
    t:segmented_control({
        label = "Diagnostics",
        element = menu.bg_diagnostics_view,
        options = { "State", "Queue", "Leave", "Mount", "Ghost" },
    })

    local diag = menu.bg_diagnostics_view
    local function diag_is(n) return function() return (diag and diag:get() or 1) == n end end

    -- State diagnostics (view 1)
    t:row_list({
        label = "State",
        visible_when = diag_is(1),
        elements = {
            {
                type = "info", label = "Battleground",
                value_fn = function() return tostring(blackboard(app):get("bg.key", "-") or "-") end,
            },
            {
                type = "info", label = "Detected BG",
                value_fn = function() return tostring(blackboard(app):get("bg.detected_key", "-") or "-") end,
            },
            {
                type = "info", label = "Detect Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.detect_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Activation Wait",
                value_fn = function() return tostring(blackboard(app):get("bg.activation_wait_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Side",
                value_fn = function() return tostring(blackboard(app):get("bg.side", "-") or "-") end,
            },
            {
                type = "info", label = "BG State",
                value_fn = function() return tostring(blackboard(app):get("bg.state", "-") or "-") end,
            },
            {
                type = "info", label = "Strategy",
                value_fn = function()
                    local bb = blackboard(app)
                    return tostring(bb:get("bg.strategy_label", bb:get("bg.strategy_id", "-")) or "-")
                end,
            },
            {
                type = "info", label = "Objective",
                value_fn = function() return tostring(blackboard(app):get("bg.objective_id", "-") or "-") end,
            },
            {
                type = "info", label = "Selected Objective",
                value_fn = function() return tostring(blackboard(app):get("bg.selected_objective_id", "-") or "-") end,
            },
            {
                type = "info", label = "Selected Score",
                value_fn = function()
                    local meta = blackboard(app):get("bg.selection_meta")
                    if type(meta) ~= "table" then return "-" end
                    return tostring(meta.selected_score or "-")
                end,
            },
            {
                type = "info", label = "Selection Reject",
                value_fn = function()
                    local meta = blackboard(app):get("bg.selection_meta")
                    if type(meta) ~= "table" then return "-" end
                    return tostring(meta.rejection_reason or "-")
                end,
            },
            {
                type = "info", label = "Selection Failure",
                value_fn = function() return tostring(blackboard(app):get("bg.selection_failure_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Objective Type",
                value_fn = function() return tostring(blackboard(app):get("bg.objective_type", "-") or "-") end,
            },
            {
                type = "info", label = "Prep Gate Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.prep_gate_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Nav Command",
                value_fn = function() return tostring(blackboard(app):get("nav.command", "-") or "-") end,
            },
            {
                type = "info", label = "Nav State",
                value_fn = function() return tostring(blackboard(app):get("nav.state", "idle") or "idle") end,
            },
            {
                type = "info", label = "Nav Owner",
                value_fn = function() return tostring(blackboard(app):get("nav.owner", "-") or "-") end,
            },
            {
                type = "info", label = "Nav Authority",
                value_fn = function() return tostring(blackboard(app):get("bg.nav_authority", "-") or "-") end,
            },
            {
                type = "info", label = "Nav Map ID",
                value_fn = function() return tostring(blackboard(app):get("bg.nav_map_id", "-") or "-") end,
            },
            {
                type = "info", label = "Route ID",
                value_fn = function() return tostring(blackboard(app):get("bg.route_id", "-") or "-") end,
            },
            {
                type = "info", label = "Bootstrap Phase",
                value_fn = function() return tostring(blackboard(app):get("bg.bootstrap.phase", "-") or "-") end,
            },
            {
                type = "info", label = "Bootstrap Route",
                value_fn = function() return tostring(blackboard(app):get("bg.bootstrap.route_id", "-") or "-") end,
            },
            {
                type = "info", label = "Approach Variant",
                value_fn = function() return tostring(blackboard(app):get("bg.objective_approach.variant", "-") or "-") end,
            },
            {
                type = "info", label = "Approach Source",
                value_fn = function() return tostring(blackboard(app):get("bg.objective_approach_source", "-") or "-") end,
            },
            {
                type = "info", label = "Approach Stage",
                value_fn = function() return tostring(blackboard(app):get("bg.objective_approach.stage", "-") or "-") end,
            },
            {
                type = "info", label = "Route Failure",
                value_fn = function() return tostring(blackboard(app):get("bg.route_failure_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Objective Center",
                value_fn = function()
                    local center = blackboard(app):get("bg.objective_center")
                    if type(center) ~= "table" then return "-" end
                    return string.format("%.1f, %.1f, %.1f", tonumber(center.x) or 0, tonumber(center.y) or 0, tonumber(center.z) or 0)
                end,
            },
            {
                type = "info", label = "Objective Nav Target",
                value_fn = function()
                    local target = blackboard(app):get("bg.objective_nav_target")
                    if type(target) ~= "table" then return "-" end
                    return string.format("%.1f, %.1f, %.1f", tonumber(target.x) or 0, tonumber(target.y) or 0, tonumber(target.z) or 0)
                end,
            },
            {
                type = "info", label = "Objective Anchor",
                value_fn = function()
                    local target = blackboard(app):get("bg.objective_anchor")
                    if type(target) ~= "table" then return "-" end
                    return string.format("%.1f, %.1f, %.1f", tonumber(target.x) or 0, tonumber(target.y) or 0, tonumber(target.z) or 0)
                end,
            },
            {
                type = "info", label = "Candidate #1",
                value_fn = function()
                    local list = blackboard(app):get("bg.candidates_top3")
                    local item = type(list) == "table" and list[1] or nil
                    if type(item) ~= "table" then return "-" end
                    return string.format("%s (%.2f)", tostring(item.id or "-"), tonumber(item.score) or 0)
                end,
            },
            {
                type = "info", label = "Candidate #2",
                value_fn = function()
                    local list = blackboard(app):get("bg.candidates_top3")
                    local item = type(list) == "table" and list[2] or nil
                    if type(item) ~= "table" then return "-" end
                    return string.format("%s (%.2f)", tostring(item.id or "-"), tonumber(item.score) or 0)
                end,
            },
            {
                type = "info", label = "Candidate #3",
                value_fn = function()
                    local list = blackboard(app):get("bg.candidates_top3")
                    local item = type(list) == "table" and list[3] or nil
                    if type(item) ~= "table" then return "-" end
                    return string.format("%s (%.2f)", tostring(item.id or "-"), tonumber(item.score) or 0)
                end,
            },
        },
    })

    -- Queue diagnostics (view 2)
    t:row_list({
        label = "Queue Diagnostics",
        visible_when = diag_is(2),
        elements = {
            {
                type = "info", label = "Sensor In BG",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.in_bg", false) == true) end,
            },
            {
                type = "info", label = "Queue Popup",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.queue_popup", false) == true) end,
            },
            -- Spawn barrier rows removed: sensor_hub never writes these keys
            {
                type = "info", label = "Prep Gate Armed",
                value_fn = function() return tostring(blackboard(app):get("bg.prep_gate_armed", false) == true) end,
            },
            {
                type = "info", label = "Prep Gate Released",
                value_fn = function() return tostring(blackboard(app):get("bg.prep_gate_released", false) == true) end,
            },
            {
                type = "info", label = "Prep Release Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.prep_release_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Queue Kind",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.queue_popup_kind", "-") or "-") end,
            },
            {
                type = "info", label = "Queue Source",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.queue_popup_source", "-") or "-") end,
            },
            {
                type = "info", label = "Queue Confidence",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.queue_popup_confidence", "-") or "-") end,
            },
            {
                type = "info", label = "Queue Status",
                value_fn = function()
                    return tostring(blackboard(app):get("bg.queue.status_summary", blackboard(app):get("bg.sensor.queue_status_summary", "-")) or "-")
                end,
            },
            {
                type = "info", label = "Join Pending",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.join_dispatched", false) == true) end,
            },
            {
                type = "info", label = "Last Join OK",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.last_join_ok", "-") or "-") end,
            },
            {
                type = "info", label = "Last Join BG ID",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.last_join_bg_id", "-") or "-") end,
            },
            {
                type = "info", label = "Join Confirmed",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.join_confirmed", "-") or "-") end,
            },
            {
                type = "info", label = "Accept Pending",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.accept_dispatched", false) == true) end,
            },
            {
                type = "info", label = "Accept Confirmed",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.accept_confirmed", false) == true) end,
            },
            {
                type = "info", label = "Accept Method",
                value_fn = function()
                    local bb = blackboard(app)
                    return tostring(bb:get("bg.queue.accept_method", bb:get("bg.queue.accept_method_attempted", "-")) or "-")
                end,
            },
            {
                type = "info", label = "Skip Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.queue.skip_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Nav Idle Abort",
                value_fn = function() return tostring(blackboard(app):get("nav.last_idle_abort_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Retreat Requested",
                value_fn = function() return tostring(blackboard(app):get("bg.retreat_requested", false) == true) end,
            },
            {
                type = "info", label = "Retreat Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.retreat_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Retreat Set At",
                value_fn = function() return tostring(blackboard(app):get("bg.retreat_set_at_ms", "-") or "-") end,
            },
            {
                type = "info", label = "Instance ID",
                value_fn = function() return tostring(blackboard(app):get("system.instance_id", "-") or "-") end,
            },
            {
                type = "info", label = "Instance Name",
                value_fn = function() return tostring(blackboard(app):get("system.instance_name", "-") or "-") end,
            },
            {
                type = "info", label = "BF State",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.battlefield_state", "-") or "-") end,
            },
            {
                type = "info", label = "State#5 Streak",
                value_fn = function() return tostring(blackboard(app):get("bg.sensor.battlefield_state_streak_5", 0) or 0) end,
            },
        },
    })

    -- Leave diagnostics (view 3)
    t:row_list({
        label = "Leave Diagnostics",
        visible_when = diag_is(3),
        elements = {
            {
                type = "info", label = "Leave Gate",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.gate_open", false) == true) end,
            },
            {
                type = "info", label = "Gate Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.gate_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Wait Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.wait_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Attempts",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.attempts", 0) or 0) end,
            },
            {
                type = "info", label = "Last Strategy",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.last_strategy", "-") or "-") end,
            },
            {
                type = "info", label = "Last Attempt OK",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.last_attempt_ok", "-") or "-") end,
            },
            {
                type = "info", label = "Confirmed",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.confirmed", false) == true) end,
            },
            {
                type = "info", label = "Confirm Reason",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.confirm_reason", "-") or "-") end,
            },
            {
                type = "info", label = "API Present",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.api_present", false) == true) end,
            },
            {
                type = "info", label = "Exhausted",
                value_fn = function() return tostring(blackboard(app):get("bg.leave.exhausted", false) == true) end,
            },
        },
    })

    -- Mount diagnostics (view 4)
    t:row_list({
        label = "Mount Diagnostics",
        visible_when = diag_is(4),
        elements = {
            {
                type = "info", label = "Mounted",
                value_fn = function() return tostring(blackboard(app):get("player.is_mounted", false) == true) end,
            },
            {
                type = "info", label = "Mount State",
                value_fn = function() return tostring(blackboard(app):get("bg.mount.state", "-") or "-") end,
            },
            {
                type = "info", label = "Mount Block",
                value_fn = function() return tostring(blackboard(app):get("bg.mount.block_reason", "-") or "-") end,
            },
            {
                type = "info", label = "Preferred Mount ID",
                value_fn = function() return tostring(blackboard(app):get("bg.mount.preferred_mount_id", "-") or "-") end,
            },
            {
                type = "info", label = "Selected Mount",
                value_fn = function()
                    local bb = blackboard(app)
                    return tostring(bb:get("bg.mount.selected_mount_name", bb:get("bg.mount.selected_mount_id", "-")) or "-")
                end,
            },
            {
                type = "info", label = "Mount Strategy",
                value_fn = function() return tostring(blackboard(app):get("bg.mount.selected_mount_strategy", "-") or "-") end,
            },
        },
    })

    -- Ghost diagnostics (view 5)
    t:row_list({
        label = "Death / Ghost",
        visible_when = diag_is(5),
        elements = {
            {
                type = "info", label = "Dead",
                value_fn = function() return tostring(blackboard(app):get("player.is_dead", false) == true) end,
            },
            {
                type = "info", label = "Ghost",
                value_fn = function() return tostring(blackboard(app):get("player.is_ghost", false) == true) end,
            },
            {
                type = "info", label = "Ghost Action",
                value_fn = function() return tostring(blackboard(app):get("bg.ghost.action", "-") or "-") end,
            },
            {
                type = "info", label = "Release Attempted",
                value_fn = function() return tostring(blackboard(app):get("bg.ghost.release_attempted", false) == true) end,
            },
            {
                type = "info", label = "Resurrect Delay",
                value_fn = function() return tostring(blackboard(app):get("player.resurrect_delay_s", "-") or "-") end,
            },
            {
                type = "info", label = "Ghost Blocking",
                value_fn = function() return tostring(blackboard(app):get("bg.ghost.active", false) == true) end,
            },
        },
    })
end

return BattlegroundTab
