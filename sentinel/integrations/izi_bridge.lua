local IziBridge = {}
IziBridge.__index = IziBridge

function IziBridge:new()
    local o = setmetatable({}, IziBridge)
    o._izi = require("common/izi_sdk")
    o._health_pred = require("common/modules/health_prediction")
    o._combat_forecast = require("common/modules/combat_forecast")
    return o
end

function IziBridge:get_izi()
    return self._izi
end

function IziBridge:predict_hp_pct(player, seconds)
    if not player then return nil end
    local ok, inc = pcall(self._health_pred.get_incoming_damage, self._health_pred, player, seconds)
    if not ok or type(inc) ~= "number" then return nil end
    local hp = player:get_health()
    local max_hp = player:get_max_health()
    if not max_hp or max_hp <= 0 then return nil end
    return (hp - inc) / max_hp
end

function IziBridge:get_forecast()
    local ok, forecast = pcall(self._combat_forecast.get_forecast, self._combat_forecast)
    return ok and type(forecast) == "number" and forecast or nil
end

function IziBridge:get_time_to_die(unit)
    if not unit then return nil end
    local ok, ttd = pcall(self._izi.get_time_to_die_global, self._izi, unit)
    return ok and type(ttd) == "number" and ttd or nil
end

function IziBridge:get_player()
    local ok, player = pcall(self._izi.get_player, self._izi)
    return ok and player or nil
end

function IziBridge:is_battleground(map_id)
    local ok, result = pcall(self._izi.is_battleground, self._izi, map_id)
    return ok and result == true
end

return IziBridge