local DashboardTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

local function format_vec3(value)
    if type(value) ~= "table" then
        return "-"
    end
    return string.format("%.1f %.1f %.1f", tonumber(value.x) or 0, tonumber(value.y) or 0, tonumber(value.z) or 0)
end

function DashboardTab.render(t, app, _menu)
    t:metric_grid({
        label = "Live",
        elements = {
            {
                label = "Health %",
                value_fn = function()
                    return math.floor((blackboard(app):get("player.health_pct", 0) or 0) * 100)
                end,
            },
            {
                label = "Ping",
                value_fn = function()
                    return tonumber(blackboard(app):get("system.ping_ms", 0)) or 0
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

    t:row_list({
        label = "State",
        elements = {
            {
                type = "info",
                label = "Map",
                value_fn = function()
                    return tostring(blackboard(app):get("system.map_name", "-"))
                end,
            },
            {
                type = "info",
                label = "Combat State",
                value_fn = function()
                    local combat = app:get_module("combat")
                    return combat and combat:get_state() or "-"
                end,
            },
            {
                type = "info",
                label = "Battleground State",
                value_fn = function()
                    local battleground = app:get_module("battleground")
                    return battleground and battleground:get_state() or "-"
                end,
            },
            {
                type = "info",
                label = "Nav State",
                value_fn = function()
                    return tostring(blackboard(app):get("nav.state", "idle"))
                end,
            },
            {
                type = "info",
                label = "Objective",
                value_fn = function()
                    return tostring(blackboard(app):get("bg.objective_id", "-"))
                end,
            },
            {
                type = "info",
                label = "Destination",
                value_fn = function()
                    return format_vec3(blackboard(app):get("nav.destination"))
                end,
            },
        },
    })

    t:row_list({
        label = "Actions",
        elements = {
            {
                type = "button",
                label = "Combat",
                text = "Disengage",
                tooltip = "Drop the current combat target and stop chase movement owned by combat.",
                on_click = function()
                    local combat = app:get_module("combat")
                    if combat then
                        combat:disengage("ui_disengage")
                    end
                end,
            },
            {
                type = "button",
                label = "Battleground",
                text = "Regroup",
                tooltip = "Force the battleground module into retreat/regroup flow.",
                on_click = function()
                    local battleground = app:get_module("battleground")
                    if battleground then
                        battleground:force_regroup("ui_force_regroup")
                    end
                end,
            },
        },
    })
end

return DashboardTab
