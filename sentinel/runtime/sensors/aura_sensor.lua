local AuraCatalog = require("modules/combat/aura_catalog")

local AuraSensor = {}
AuraSensor.__index = AuraSensor

function AuraSensor:new(blackboard, event_bus, izi)
    local o = setmetatable({}, AuraSensor)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._izi = izi
    o._izi_unsubscribers = {}

    if izi then
        local eb = event_bus
        local bb = blackboard
        o:_register_izi_callback(izi.on_buff_gain, function(event)
            local player_obj = bb:get("player.object")
            if player_obj and event.unit == player_obj then
                eb:publish("player:buff_gained", {
                    spell_id = event.buff_id,
                    unit = event.unit,
                })
            elseif player_obj and event.unit ~= player_obj then
                local ok = pcall(player_obj.is_enemy_with, player_obj, event.unit)
                if ok then
                    eb:publish("unit:buff_applied", {
                        spell_id = event.buff_id,
                        unit = event.unit,
                    })
                end
            end
        end)
        o:_register_izi_callback(izi.on_buff_lose, function(event)
            local player_obj = bb:get("player.object")
            if player_obj and event.unit == player_obj then
                eb:publish("player:buff_lost", {
                    spell_id = event.buff_id,
                    unit = event.unit,
                })
            end
        end)
        o:_register_izi_callback(izi.on_debuff_gain, function(event)
            local player_obj = bb:get("player.object")
            if player_obj and event.unit ~= player_obj then
                local ok = pcall(player_obj.is_enemy_with, player_obj, event.unit)
                if ok then
                    eb:publish("unit:debuff_applied", {
                        spell_id = event.debuff_id,
                        unit = event.unit,
                    })
                end
            end
        end)
        o:_register_izi_callback(izi.on_combat_start, function(event)
            local player_obj = bb:get("player.object")
            if player_obj and event.unit == player_obj then
                eb:publish("player:izi_combat_started", {})
            end
        end)
        o:_register_izi_callback(izi.on_combat_finish, function(event)
            local player_obj = bb:get("player.object")
            if player_obj and event.unit == player_obj then
                eb:publish("player:izi_combat_finished", {})
            end
        end)
        o:_register_izi_callback(izi.on_spell_begin, function(event)
            local player_obj = bb:get("player.object")
            if player_obj and event.caster ~= player_obj then
                eb:publish("unit:spell_casting", {
                    spell_id = event.spell_id,
                    caster = event.caster,
                    target = event.target,
                })
            end
        end)
        o:_register_izi_callback(izi.on_spell_cancel, function(event)
            eb:publish("unit:spell_cancelled", {
                spell_id = event.spell_id,
                caster = event.caster,
            })
        end)
    end

    return o
end

function AuraSensor:_register_izi_callback(register_fn, handler)
    if type(register_fn) ~= "function" then return end
    local ok, unsub = pcall(register_fn, self._izi, handler)
    if ok and type(unsub) == "function" then
        self._izi_unsubscribers[#self._izi_unsubscribers + 1] = unsub
    end
end

function AuraSensor:refresh(player, now_ms)
    local active_seal = nil
    if player then
        if AuraCatalog.has_any(player, AuraCatalog.seal_of_blood) then
            active_seal = "blood"
        elseif AuraCatalog.has_any(player, AuraCatalog.seal_of_command_ranks) then
            active_seal = "command"
        end
    end
    self._blackboard:set("rotation.active_seal", active_seal)
end

function AuraSensor:shutdown()
    if self._izi_unsubscribers then
        for _, unsub in ipairs(self._izi_unsubscribers) do
            if type(unsub) == "function" then
                pcall(unsub)
            end
        end
        self._izi_unsubscribers = {}
    end
end

return AuraSensor
