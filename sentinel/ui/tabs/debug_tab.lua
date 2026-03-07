local DebugTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

local function format_vec3(value)
    if type(value) ~= "table" then
        return "-"
    end
    return string.format("%.1f %.1f %.1f", tonumber(value.x) or 0, tonumber(value.y) or 0, tonumber(value.z) or 0)
end

function DebugTab.render(t, app, _menu)
    t:row_list({
        label = "Runtime",
        elements = {
            {
                type = "info",
                label = "Map ID",
                value_fn = function()
                    return tostring(blackboard(app):get("system.map_id", 0))
                end,
            },
            {
                type = "info",
                label = "Map Name",
                value_fn = function()
                    return tostring(blackboard(app):get("system.map_name", "-"))
                end,
            },
            {
                type = "info",
                label = "Ping ms",
                value_fn = function()
                    return tostring(blackboard(app):get("system.ping_ms", 0))
                end,
            },
            {
                type = "info",
                label = "Last Spell",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_spell_id", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Queue Mode",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_queue_mode", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Queue Priority",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_queue_priority", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Last Block",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_block_reason", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Queue Size",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_queue_snapshot_size", 0) or 0)
                end,
            },
            {
                type = "info",
                label = "Queue Call",
                value_fn = function()
                    local bb = blackboard(app)
                    return string.format(
                        "%s / %s",
                        tostring(bb:get("rotation.last_queue_call_mode", "-") or "-"),
                        tostring(bb:get("rotation.last_queue_call_method", "-") or "-")
                    )
                end,
            },
            {
                type = "info",
                label = "Queue Call OK",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_queue_call_ok", false) == true)
                end,
            },
            {
                type = "info",
                label = "Queue Observed",
                value_fn = function()
                    local value = blackboard(app):get("rotation.last_queue_observed")
                    if value == nil then
                        return "-"
                    end
                    return tostring(value == true)
                end,
            },
            {
                type = "info",
                label = "Queue Target",
                value_fn = function()
                    return tostring(blackboard(app):get("rotation.last_queue_target_guid", "-") or "-")
                end,
            },
            {
                type = "info",
                label = "Leash Center",
                value_fn = function()
                    return format_vec3(blackboard(app):get("combat.leash_center"))
                end,
            },
            {
                type = "info",
                label = "Nav Destination",
                value_fn = function()
                    return format_vec3(blackboard(app):get("nav.destination"))
                end,
            },
        },
    })

    t:metric_grid({
        label = "Signals",
        elements = {
            {
                label = "GCD Until",
                value_fn = function()
                    return tonumber(blackboard(app):get("combat.gcd_until_ms", 0)) or 0
                end,
            },
            {
                label = "Swing Conf",
                value_fn = function()
                    return string.format("%.2f", tonumber(blackboard(app):get("combat.swing.confidence", 0)) or 0)
                end,
            },
            {
                label = "Path Index",
                value_fn = function()
                    local progress = blackboard(app):get("nav.progress")
                    return progress and (tonumber(progress.path_index or 0) or 0) or 0
                end,
            },
            {
                label = "Distance Left",
                value_fn = function()
                    local progress = blackboard(app):get("nav.progress")
                    local value = progress and (tonumber(progress.distance_remaining or 0) or 0) or 0
                    return string.format("%.1f", value)
                end,
            },
        },
    })
end

return DebugTab
