local StrathDuoMage = require("init")
local UIWindow = require("ui/window")

local _loaded = false
local _menu_tree = core.menu.tree_node()
local _btn_open = core.menu.button("sdm_open")
local _btn_toggle = core.menu.button("sdm_toggle")
local _btn_role = core.menu.button("sdm_role")

local function safe_log(msg)
    if core and core.log then
        core.log("[StrathDuoMage] " .. tostring(msg))
    end
end

local function on_load()
    if _loaded then
        return
    end

    local ok, err = StrathDuoMage:initialize({})
    if not ok then
        if core and core.log_error then
            core.log_error("[StrathDuoMage] Initialization failed: " .. tostring(err))
        end
        return
    end

    _loaded = true

    local bot = StrathDuoMage:get_bot()
    if bot then
        UIWindow.init(bot)
    end

    safe_log("Loaded")
end

on_load()

core.register_on_update_callback(function()
    if not _loaded then
        return
    end

    local bot = StrathDuoMage:get_bot()
    if bot and bot.update then
        bot:update()
    end
end)

core.register_on_render_menu_callback(function()
    if not _loaded then
        return
    end

    UIWindow.on_menu_render()

    _menu_tree:render("Strath Duo Mage", function()
        if _btn_open:render("Open/Close UI") then
            local ui = UIWindow.get_ui()
            if ui and ui.menu and ui.menu.enable then
                ui.menu.enable:set(not ui.menu.enable:get_state())
            end
        end

        if _btn_toggle:render("Start/Stop") then
            local bot = StrathDuoMage:get_bot()
            if bot then
                if bot:is_running() then
                    bot:stop("menu_stop")
                else
                    bot:start()
                end
            end
        end

        if _btn_role:render("Switch Leader/Follower") then
            local bot = StrathDuoMage:get_bot()
            if bot and bot.toggle_role then
                bot:toggle_role()
            end
        end
    end)
end)

core.register_on_render_callback(function()
    if not _loaded then
        return
    end

    UIWindow.on_render()

    local bot = StrathDuoMage:get_bot()
    if bot and bot.render then
        bot:render()
    end
end)

local function on_unload()
    StrathDuoMage:destroy()
    _loaded = false
end

local function read_player_position()
    if not (core and core.object_manager and core.object_manager.get_local_player) then
        return nil
    end
    local player = core.object_manager.get_local_player()
    if not player or type(player.get_position) ~= "function" then
        return nil
    end
    local ok, pos = pcall(player.get_position, player)
    if not ok or type(pos) ~= "table" then
        return nil
    end
    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    local z = tonumber(pos.z)
    if not x or not y or not z then
        return nil
    end
    return { x = x, y = y, z = z }
end

_G.StrathDuoMage = {
    create = function(opts)
        StrathDuoMage:initialize(opts)
        return StrathDuoMage:get_bot()
    end,
    get_bot = function()
        return StrathDuoMage:get_bot()
    end,
    get_snapshot = function()
        local bot = StrathDuoMage:get_bot()
        return bot and bot.get_snapshot and bot:get_snapshot() or nil
    end,
    record_start = function(profile_path)
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_start then
            return false, "bot unavailable"
        end
        return bot:record_start(profile_path)
    end,
    record_stop = function(save_changes)
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_stop then
            return false, "bot unavailable"
        end
        return bot:record_stop(save_changes == true)
    end,
    record_save = function(path)
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_save then
            return false, "bot unavailable"
        end
        return bot:record_save(path)
    end,
    record_capture_pull_point = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_capture_pull_point then
            return false, "bot unavailable"
        end
        return bot:record_capture_pull_point()
    end,
    record_capture_gather_anchor = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_capture_gather_anchor then
            return false, "bot unavailable"
        end
        return bot:record_capture_gather_anchor()
    end,
    record_capture_lane_start = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_capture_lane_start then
            return false, "bot unavailable"
        end
        return bot:record_capture_lane_start()
    end,
    record_capture_lane_end = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_capture_lane_end then
            return false, "bot unavailable"
        end
        return bot:record_capture_lane_end()
    end,
    record_next_segment = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_next_segment then
            return false, "bot unavailable"
        end
        return bot:record_next_segment()
    end,
    record_prev_segment = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_prev_segment then
            return false, "bot unavailable"
        end
        return bot:record_prev_segment()
    end,
    record_toggle_strategy = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_toggle_strategy then
            return false, "bot unavailable"
        end
        return bot:record_toggle_strategy()
    end,
    record_undo = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_undo then
            return false, "bot unavailable"
        end
        return bot:record_undo()
    end,
    record_clear_pull_points = function()
        local bot = StrathDuoMage:get_bot()
        if not bot or not bot.record_clear_pull_points then
            return false, "bot unavailable"
        end
        return bot:record_clear_pull_points()
    end,
    capture_point = function(label)
        local pos = read_player_position()
        if not pos then
            safe_log("capture_point failed: player position unavailable")
            return nil
        end
        local text = string.format("{ \"x\": %.3f, \"y\": %.3f, \"z\": %.3f }", pos.x, pos.y, pos.z)
        if label and label ~= "" then
            safe_log(string.format("capture_point [%s] %s", tostring(label), text))
        else
            safe_log("capture_point " .. text)
        end
        return pos
    end,
    get_player_position = function()
        return read_player_position()
    end,
    ui = UIWindow,
    VERSION = StrathDuoMage.VERSION,
}

return {
    name = "StrathDuoMage",
    version = StrathDuoMage.VERSION,
    unload = on_unload,
}
