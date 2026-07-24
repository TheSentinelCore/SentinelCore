local Schema = require("core/blackboard_schema")

local Blackboard = {}
Blackboard.__index = Blackboard

function Blackboard:new()
    local o = setmetatable({}, Blackboard)
    o._data = {}
    return o
end

function Blackboard:get(key, default)
    local value = self._data[key]
    if value == nil then
        return default
    end
    return value
end

function Blackboard:set(key, value)
    local ok, err = Schema.validate_key(key)
    if not ok then
        error("blackboard set rejected: " .. tostring(err) .. " for key " .. tostring(key))
    end
    self._data[key] = value
end

function Blackboard:clear(key)
    self._data[key] = nil
end

function Blackboard:has(key)
    return self._data[key] ~= nil
end

-- `Blackboard:snapshot(prefix)` was REMOVED in Phase 1 and superseded by
-- `kernel/snapshot.lua`. ADR 08 §5.1 already recorded that it had zero callers, but dead
-- code was not the reason it had to go: it returned a SHALLOW copy of live blackboard
-- state, and this blackboard holds `player.object` -- a raw game_object handle written by
-- runtime/sensors/player_sensor.lua. It therefore produced precisely the artefact ADR 08
-- §2.7 forbids (a "snapshot" holding a pointer that can die inside the tick that froze it),
-- under a name that invited exactly the trust it could not honour.
--
-- The blackboard remains what it is: LIVE, mutable, read-through state. Anything that needs
-- a consistent view for the duration of a tick uses kernel/snapshot.lua.

return Blackboard
