-- integrations/izi_bridge.lua
-- Adapter over the injector-only IZI SDK (`common/izi_sdk` and its `common/modules/*`).
--
-- ADR 08 §11.6 -- TESTABILITY DEBT, CLEARED. This file used to `require("common/izi_sdk")`
-- UNGUARDED inside :new(). Those modules exist only inside the Sylvanas injector, so
-- constructing an IziBridge offline threw -- and since SentinelApp:new() constructs one
-- (app.lua) and so does the combat module wrapper (modules/combat/init.lua), the kernel's
-- entire composition root was unreachable from a test. tests/runtime/test_app_tick.lua
-- hand-stubbed around it and said so in a comment.
--
-- The guard is deliberately NOT a silent fallback (ADR 08 §12, the LazyBot
-- `try {} catch {}`-with-empty-body failure mode). Absence is a NAMED state --
-- `is_available()` -- and every accessor returns nil/false rather than a plausible-looking
-- zero (ADR 08 §9.3: "without an explicit unavailable value, every unreadable field
-- silently becomes a plausible-looking zero").

local IziBridge = {}
IziBridge.__index = IziBridge

--- Guarded module load. Returns nil when the injector is absent, never throws.
local function try_require(name)
    local ok, mod = pcall(require, name)
    if ok and mod ~= nil then
        return mod
    end
    return nil
end

---Construct the bridge.
---@param deps table|nil Optional injected SDK modules -- used by offline tests, which cannot
---       require the injector-only originals. Keys: izi, health_prediction, combat_forecast.
function IziBridge:new(deps)
    deps = deps or {}
    local o = setmetatable({}, IziBridge)
    o._izi = deps.izi or try_require("common/izi_sdk")
    o._health_pred = deps.health_prediction or try_require("common/modules/health_prediction")
    o._combat_forecast = deps.combat_forecast or try_require("common/modules/combat_forecast")
    return o
end

---@return boolean true only when the IZI SDK actually loaded. Callers that need to
---        distinguish "no data" from "cannot read" must consult this (ADR 08 §9.3).
function IziBridge:is_available()
    return self._izi ~= nil
end

function IziBridge:get_izi()
    return self._izi
end

function IziBridge:predict_hp_pct(player, seconds)
    if not player or not self._health_pred then return nil end
    local ok, inc = pcall(self._health_pred.get_incoming_damage, self._health_pred, player, seconds)
    if not ok or type(inc) ~= "number" then return nil end
    local hp = player:get_health()
    local max_hp = player:get_max_health()
    if not max_hp or max_hp <= 0 then return nil end
    return (hp - inc) / max_hp
end

function IziBridge:get_forecast()
    if not self._combat_forecast then return nil end
    local ok, forecast = pcall(self._combat_forecast.get_forecast, self._combat_forecast)
    return ok and type(forecast) == "number" and forecast or nil
end

function IziBridge:get_time_to_die(unit)
    if not unit or not self._izi then return nil end
    local ok, ttd = pcall(self._izi.get_time_to_die_global, self._izi, unit)
    return ok and type(ttd) == "number" and ttd or nil
end

function IziBridge:get_player()
    if not self._izi then return nil end
    local ok, player = pcall(self._izi.get_player, self._izi)
    return ok and player or nil
end

function IziBridge:is_battleground(map_id)
    if not self._izi then return false end
    local ok, result = pcall(self._izi.is_battleground, self._izi, map_id)
    return ok and result == true
end

return IziBridge
