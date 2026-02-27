local SentinelUI = require("lib/SentinelUI")
local dashboard_tab = require("ui/tabs/dashboard_tab")
local recorder_tab = require("ui/tabs/recorder_tab")

local Window = {}

local _initialized = false
local _bot = nil
local _ui = nil

local function register_tabs(ui, bot)
    ui:add_tab({ id = "dashboard", label = "Dashboard" }, function(t)
        dashboard_tab.render(t, bot)
    end)

    ui:add_tab({ id = "recorder", label = "Recorder" }, function(t)
        recorder_tab.render(t, bot)
    end)
end

---@param bot StrathDuoBot
function Window.init(bot)
    if _initialized then
        return
    end

    _bot = bot
    _ui = SentinelUI.new({
        id = "strath_duo_mage",
        title = "Strath Duo Mage Control",
        default_x = 520,
        default_y = 110,
        default_w = 820,
        default_h = 660,
        theme = "apple",
        render_layer = 1,
    })

    register_tabs(_ui, _bot)
    _ui.menu.enable:set(false)
    _initialized = true
end

function Window.on_render()
    if not _initialized or not _ui then
        return
    end
    _ui:on_render()
end

function Window.on_menu_render()
    if not _initialized or not _ui then
        return
    end
    _ui:on_menu_render()
end

---@return any|nil
function Window.get_ui()
    return _ui
end

return Window
