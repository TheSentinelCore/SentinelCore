local CallbackBridge = {}
CallbackBridge.__index = CallbackBridge

function CallbackBridge:new(event_bus)
    local o = setmetatable({}, CallbackBridge)
    o._event_bus = event_bus

    -- Register game event callbacks for combat state transitions
    if core and type(core.register_on_game_event_callback) == "function" then
        pcall(core.register_on_game_event_callback, function(event_name, args)
            if event_name == "PLAYER_REGEN_DISABLED" then
                event_bus:publish("game:entered_combat", {})
            elseif event_name == "PLAYER_REGEN_ENABLED" then
                event_bus:publish("game:exited_combat", {})
            elseif event_name == "SPELLS_CHANGED" then
                event_bus:publish("game:spells_changed", {})
            elseif event_name == "GROUP_ROSTER_UPDATE" then
                event_bus:publish("game:group_updated", {})
            elseif event_name == "MAIL_SHOW" then
                event_bus:publish("game:mail_show", {})
            elseif event_name == "MAIL_CLOSED" then
                event_bus:publish("game:mail_closed", {})
            elseif event_name == "MAIL_INBOX_UPDATE" then
                event_bus:publish("game:mail_inbox_update", {})
            elseif event_name == "QUEST_LOG_UPDATE" then
                event_bus:publish("game:quest_log_update", {})
            elseif event_name == "UI_ERROR_MESSAGE" then
                -- The ONLY signal the client gives for hard inventory errors —
                -- get_num_bag_slots returns 0 live, so "Inventory is full." arrives
                -- here or nowhere. Consumed by questing's vendor maintenance.
                event_bus:publish("game:ui_error", {
                    error_type = args and args[1] or nil,
                    message = args and args[2] or nil,
                })
            elseif event_name == "LFG_LIST_SEARCH_RESULT_UPDATED" then
                event_bus:publish("game:lfg_search_result_updated", {})
            elseif event_name == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
                event_bus:publish("game:lfg_application_status_updated", {})
            end
        end)
    end

    return o
end

-- F6: publish_engine used to build a 5-field payload (5 SDK calls: core.game_time,
-- core.delta_time, core.get_ping, core.get_map_id, core.get_map_name) 3x/frame
-- (pre_tick/update/render), even for events with ZERO subscribers -- roughly 900 wasted SDK
-- calls/second. EventBus:publish() already early-returns with no subscribers, but only AFTER
-- the payload was built. This reaches into EventBus's internal `_subs` field (not a public
-- API -- core/event_bus.lua is out of scope for this change) defensively: if that field is
-- ever missing or renamed, treat it as "has subscribers" and build the payload anyway, exactly
-- like before F6.
local function event_bus_has_subscribers(event_bus, event_name)
    if type(event_bus) ~= "table" or type(event_bus._subs) ~= "table" then
        return true -- can't tell; never suppress a real publish
    end
    local list = event_bus._subs[event_name]
    return type(list) == "table" and #list > 0
end

function CallbackBridge:publish_engine(event_name)
    if not event_bus_has_subscribers(self._event_bus, event_name) then
        return
    end
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
