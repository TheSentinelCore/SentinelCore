local CallbackBridge = {}
CallbackBridge.__index = CallbackBridge

function CallbackBridge:new(event_bus)
    local o = setmetatable({}, CallbackBridge)
    o._event_bus = event_bus
    return o
end

function CallbackBridge:publish_engine(event_name)
    local payload = {
        now_ms = core and core.game_time and core.game_time() or 0,
        delta_ms = math.floor(((core and core.delta_time and core.delta_time()) or 0) * 1000),
        ping_ms = core and core.get_ping and core.get_ping() or 0,
        map_id = core and core.get_map_id and core.get_map_id() or 0,
        map_name = core and core.get_map_name and core.get_map_name() or "",
    }
    self._event_bus:publish(event_name, payload)
end

function CallbackBridge:on_pre_tick()
    self:publish_engine("engine:pre_tick")
end

function CallbackBridge:on_update()
    self:publish_engine("engine:update")
end

function CallbackBridge:on_render()
    self:publish_engine("engine:render")
end

function CallbackBridge:on_render_menu()
    self._event_bus:publish("engine:render_menu", {
        now_ms = core and core.game_time and core.game_time() or 0,
    })
end

function CallbackBridge:on_spell_cast(data)
    self._event_bus:publish("spell:world_cast", {
        spell_id = data and data.spell_id or 0,
        caster = data and data.caster or nil,
        target = data and data.target or nil,
        spell_cast_time_ms = data and data.spell_cast_time or 0,
    })
end

function CallbackBridge:on_legit_spell_cast(data)
    self._event_bus:publish("spell:manual_cast", {
        spell_id = type(data) == "table" and data.spell_id or data,
    })
end

return CallbackBridge
