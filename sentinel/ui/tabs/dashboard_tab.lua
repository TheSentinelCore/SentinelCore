local DashboardTab = {}

local function blackboard(app)
    return app:get_blackboard()
end

local function mode_label(menu)
    local idx = menu and menu.bot_mode and menu.bot_mode:get() or 1
    idx = tonumber(idx) or 1
    if idx == 2 then
        return "Grind"
    end
    return "Battleground"
end

function DashboardTab.render(t, app, menu)
    t:segmented_control({
        label = "Bot Mode",
        element = menu.bot_mode,
        options = { "Battleground", "Grind" },
        tooltip = "Switch between Battleground PvP and open-world Grinding modes. Only the selected mode's tab and module will be active.",
    })

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
        label = "Status",
        elements = {
            {
                type = "info",
                label = "Mode",
                value_fn = function()
                    return mode_label(menu)
                end,
            },
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
                label = "Nav State",
                value_fn = function()
                    return tostring(blackboard(app):get("nav.state", "idle"))
                end,
            },
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
        },
    })
end

return DashboardTab
