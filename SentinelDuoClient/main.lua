-- main.lua — SentinelDuoFarm entry point.
-- Per design doc §4.2: register PS callbacks, lazy-init App on first update.

local App  = require("core/App")
local _app = nil

core.register_on_pre_tick_callback(function()
    if _app then _app:on_pre_tick() end
end)

core.register_on_update_callback(function()
    if not _app then
        _app = App:new()
        _app:initialize()
    end
    _app:on_update()
end)

core.register_on_render_callback(function()
    if _app then _app:on_render() end
end)

core.register_on_render_menu_callback(function()
    if _app then _app:on_render_menu() end
end)
